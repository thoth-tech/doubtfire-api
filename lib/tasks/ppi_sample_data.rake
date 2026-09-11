require_all 'lib/helpers'
require Rails.root.join('lib/demo_data/all_features_scenario')

PPI_SAMPLE_LIFECYCLE_STATUSES = %i[
  not_started
  working_on_it
  ready_for_feedback
  fix_and_resubmit
  redo
  complete
  fail
].freeze
PPI_SAMPLE_UPLOADED_STATUSES = %i[
  ready_for_feedback
  fix_and_resubmit
  redo
  complete
  fail
].freeze

def ppi_viewer_vectors_safe?(unit:, snapshot:, minimum_cohort_size:)
  viewers = unit.active_projects.where(
    target_grade: snapshot.target_grade
  )

  viewers.all? do |project|
    viewer_task = project.tasks.find_by!(
      task_definition_id: snapshot.task_definition_id
    )
    peer_progress = PeerProgressViewerPolicy.build(
      snapshot: snapshot,
      viewer_project: project,
      viewer_task: viewer_task
    )
    peer_progress.present? &&
      peer_progress.fetch(:cohort_size) >= minimum_cohort_size &&
      PeerProgressViewerPolicy
        .public_metrics(peer_progress)
        .fetch(:status_distribution)
        .present?
  end
end

namespace :db do
  desc 'Create deterministic, privacy-threshold-ready demo data for the Peer Progress Indicator dashboard'
  task ppi_sample_data: :environment do
    # This task creates hundreds of synthetic users, enrolments and tasks. Use
    # the same non-interactive triple guard as the all-features demo instead of
    # permitting a typed confirmation against an arbitrary production database.
    DemoData::AllFeaturesScenario.new(reference_time: Time.zone.now).guard!

    Rails.logger.level = :info

    # ---- configuration -------------------------------------------------
    num_units = 2
    classes_per_unit = 2
    legacy_students_per_grade = 4
    grade_labels = { 0 => 'Pass', 1 => 'Credit', 2 => 'Distinction', 3 => 'HighDistinction' }.freeze
    grades = grade_labels.keys.freeze # [0, 1, 2, 3]
    num_tasks = 7 # within the requested 5-10 range
    weekdays = %w[Monday Tuesday Wednesday Thursday Friday].freeze

    # ---- helpers ---------------------------------------------------------

    def ppi_positive_integer_env!(name)
      value = Integer(ENV.fetch(name), 10)
      raise ArgumentError unless value.positive?

      value
    rescue KeyError, ArgumentError
      raise ArgumentError, "#{name} must be a positive integer"
    end

    # Finds or creates a user with a fixed, deterministic username - safe to re-run.
    def ppi_find_or_create_user(username, first_name, last_name, role_id)
      existing = User.find_by(username: username)
      if existing
        existing.update!(role_id: role_id) if existing.role_id != role_id
        return existing
      end

      profile = {
        first_name: first_name,
        last_name: last_name,
        nickname: username,
        role_id: role_id,
        email: "#{username}@doubtfire.com",
        username: username
      }
      unless AuthenticationHelpers.aaf_auth?
        profile[:password] = 'password'
        profile[:password_confirmation] = 'password'
      end
      User.create!(profile)
    end

    minimum_cohort_size = ppi_positive_integer_env!('DF_PPI_MINIMUM_COHORT_SIZE')
    stale_after_hours = ppi_positive_integer_env!('DF_PPI_STALE_AFTER_HOURS')
    if minimum_cohort_size < PeerProgressApi::MINIMUM_SAFE_COHORT_SIZE
      raise ArgumentError,
            "DF_PPI_MINIMUM_COHORT_SIZE must be at least #{PeerProgressApi::MINIMUM_SAFE_COHORT_SIZE}"
    end

    # The authenticated viewer is removed before the threshold is applied, so
    # each exact-grade cohort needs at least one more student than the peer floor.
    required_total_cohort = minimum_cohort_size + 1
    students_per_grade = required_total_cohort.fdiv(classes_per_unit).ceil
    baseline_students_per_grade =
      (PeerProgressApi::MINIMUM_SAFE_COHORT_SIZE + 1)
      .fdiv(classes_per_unit).ceil
    sample_start_date = Time.zone.now - 6.weeks
    sample_end_date = Time.zone.now + 7.weeks

    campus = Campus.first || Campus.create!(name: 'Online', mode: 'timetable', abbreviation: 'C', active: true)
    convenor = ppi_find_or_create_user('ppi_convenor', 'Peer', 'Convenor', Role.convenor_id)

    (1..num_units).each do |unit_num|
      code = "PPI100#{unit_num}"
      unit = Unit.find_or_initialize_by(code: code)
      unit.update!(
        name: "PPI Sample Unit #{unit_num}",
        description: 'Deterministic sample data for testing the Peer Progress Indicator dashboard. Not a real unit.',
        start_date: sample_start_date,
        end_date: sample_end_date,
        active: true,
        send_notifications: false,
        allow_flexible_dates: false,
        peer_progress_enabled: true
      )

      unless grades.all? { |target_grade| unit.grade_value?(target_grade) }
        raise "#{unit.code} must retain the four standard target grades for the PPI demo"
      end

      unit.employ_staff(convenor, Role.convenor)

      # All tasks are assigned regardless of a student's target grade (target_grade: 0 = Pass),
      # so every student in the unit has the same task list - needed to compare % completion
      # meaningfully across target-grade bands.
      task_defs = (1..num_tasks).map do |t|
        task_definition = unit.task_definitions.find_or_initialize_by(abbreviation: "T#{t}")
        task_definition.update!(
          name: "Task #{t}",
          description: "Sample task #{t} for PPI dashboard testing.",
          weighting: BigDecimal('1'),
          target_grade: 0,
          start_date: unit.start_date,
          target_date: unit.start_date + t.weeks,
          upload_requirements: [{ key: 'file0', name: 'Document', type: 'document' }]
        )
        task_definition
      end

      seeded_projects = []
      seeded_tasks = []

      (1..classes_per_unit).each do |class_num|
        tutor_username = "ppi_tutor_u#{unit_num}c#{class_num}"
        tutor = ppi_find_or_create_user(tutor_username, "Tutor#{unit_num}#{class_num}", 'PPI', Role.tutor_id)
        unit.employ_staff(tutor, Role.tutor)

        tutorial_abbrev = "PPI-U#{unit_num}-C#{class_num}"
        tutorial_capacity = students_per_grade * grades.length
        tutorial = unit.tutorials.find_by(abbreviation: tutorial_abbrev) || unit.add_tutorial(
          weekdays[class_num - 1],
          '10:00',
          "EN1-0#{class_num}",
          tutor,
          campus,
          tutorial_capacity,
          tutorial_abbrev
        )
        grades.each do |target_grade|
          students_per_grade.times do |i|
            # Keep the original four-per-grade usernames assigned to their
            # existing grade when this task repairs a previously seeded DB.
            if i < legacy_students_per_grade
              student_index = (target_grade * legacy_students_per_grade) + i + 1
              username = "ppi_u#{unit_num}c#{class_num}s#{student_index.to_s.rjust(2, '0')}"
            elsif i < baseline_students_per_grade
              legacy_total = grades.length * legacy_students_per_grade
              baseline_added_per_grade = baseline_students_per_grade - legacy_students_per_grade
              student_index = legacy_total + (target_grade * baseline_added_per_grade) +
                              (i - legacy_students_per_grade) + 1
              username = "ppi_u#{unit_num}c#{class_num}s#{student_index.to_s.rjust(2, '0')}"
            else
              student_index = 100 + (target_grade * 100) + i + 1
              username = "ppi_u#{unit_num}c#{class_num}g#{target_grade}s#{(i + 1).to_s.rjust(2, '0')}"
            end
            student = ppi_find_or_create_user(username, "Student#{student_index}", grade_labels[target_grade], Role.student_id)

            project = unit.enrol_student(student, campus)
            project.update!(target_grade: target_grade)
            project.enrol_in(tutorial)
            seeded_projects << project

            # Populate the full lifecycle on every task/grade cohort. Rotating
            # the extra members across tasks keeps the advanced bars varied,
            # while ensuring redo and resubmission states are always demoable.
            task_defs.each_with_index do |td, td_idx|
              task = project.task_for_task_definition(td)
              seeded_tasks << task

              cohort_ordinal = ((class_num - 1) * students_per_grade) + i
              status_key = PPI_SAMPLE_LIFECYCLE_STATUSES.fetch(
                (cohort_ordinal + td_idx + target_grade + unit_num) %
                  PPI_SAMPLE_LIFECYCLE_STATUSES.length
              )
              status = TaskStatus.public_send(status_key)
              uploaded = PPI_SAMPLE_UPLOADED_STATUSES.include?(status_key)
              submitted_at = uploaded ? Time.zone.now - 1.day : nil

              task.update!(
                task_status: status,
                file_uploaded_at: submitted_at,
                submission_date: submitted_at,
                completion_date:
                  status_key == :complete ? 1.day.ago.to_date : nil
              )
            end

            project.update_task_stats
          end
        end

        repaired_capacity = [tutorial_capacity, tutorial.num_students].max
        tutorial.update!(capacity: repaired_capacity) if tutorial.capacity != repaired_capacity
      end

      cohort_sizes = grades.index_with do |target_grade|
        unit.active_projects.where(target_grade: target_grade).count
      end
      unless cohort_sizes.values.all? do |size|
        size - 1 >= minimum_cohort_size
      end
        raise "#{unit.code} PPI cohorts are below the configured threshold: #{cohort_sizes.inspect}"
      end

      expected_project_count = classes_per_unit * grades.length * students_per_grade
      unless unit.active? && unit.peer_progress_enabled? &&
             seeded_projects.uniq.count == expected_project_count &&
             seeded_projects.all? { |project| project.enrolled? && project.user.role_id == Role.student_id }
        raise "#{unit.code} PPI demo projects are not active student enrolments"
      end

      expected_task_count = expected_project_count * task_defs.length
      tasks_released = seeded_tasks.uniq.count == expected_task_count && seeded_tasks.all? do |task|
        task.local_start_date.present? &&
          task.local_start_date <= Time.zone.now &&
          task.task_definition.target_grade <= task.project.target_grade
      end
      unless task_defs.all? { |task_definition| task_definition.target_grade.zero? } && tasks_released
        raise "#{unit.code} PPI demo tasks are not released at the pass target grade"
      end

      snapshots = PeerProgressAggregationService.call(unit: unit)
      task_definition_ids = task_defs.map(&:id)
      demo_snapshots = snapshots.select do |snapshot|
        task_definition_ids.include?(snapshot.task_definition_id) && grades.include?(snapshot.target_grade)
      end
      expected_snapshot_count = task_defs.length * grades.length
      latest_grade_changes = grades.index_with do |target_grade|
        unit.active_projects.where(target_grade: target_grade).maximum(:target_grade_changed_at)
      end
      fresh_after = stale_after_hours.hours.ago

      snapshots_valid = demo_snapshots.count == expected_snapshot_count &&
                        demo_snapshots.map { |snapshot| [snapshot.task_definition_id, snapshot.target_grade] }.uniq.count == expected_snapshot_count &&
                        demo_snapshots.all? do |snapshot|
                          latest_change = latest_grade_changes.fetch(snapshot.target_grade)
                          snapshot.cohort_size == cohort_sizes.fetch(snapshot.target_grade) &&
                            snapshot.submitted_count.is_a?(Integer) &&
                            !snapshot.submitted_percentage.nil? &&
                            ppi_viewer_vectors_safe?(
                              unit: unit,
                              snapshot: snapshot,
                              minimum_cohort_size: minimum_cohort_size
                            ) &&
                            snapshot.calculated_at >= fresh_after &&
                            (latest_change.nil? || snapshot.calculated_at >= latest_change)
                        end
      raise "#{unit.code} PPI demo snapshots failed post-seed validation" unless snapshots_valid

      puts "-> #{unit.code}: #{unit.tutorials.count} classes, #{unit.projects.count} students, " \
           "#{task_defs.count} tasks, peer-safe cohorts verified, " \
           "#{demo_snapshots.count} demo snapshots"
    end

    puts 'PPI sample dashboard data ready.'
  end
end

# frozen_string_literal: true

module DemoData
  # Builds the small, deterministic API dataset used by the all-features demo.
  #
  # This is intentionally not a general seed. Both creation and cleanup refuse
  # to run unless all three safety conditions match the dedicated local demo
  # database. Re-running creation first removes this namespace and rebuilds it,
  # so partial runs and stale relative dates cannot accumulate duplicate data.
  class AllFeaturesScenario
    class SafetyError < StandardError; end

    DATABASE_NAME = 'doubtfire-all-features-demo'
    PROFILE_NAME = 'all-features'
    CAMPUS_NAME = 'All Features Demo Campus'
    CAMPUS_ABBREVIATION = 'AFDEMO'
    DEMO_USERNAME = 'demo_student'
    CONVENOR_USERNAME = 'demo_convenor'
    PEER_USERNAMES = (1..24).map do |number|
      "demo_peer_#{number.to_s.rjust(2, '0')}"
    end.freeze
    USERNAMES = [DEMO_USERNAME, CONVENOR_USERNAME, *PEER_USERNAMES].freeze
    CURRENT_UNIT_CODES = %w[
      DEMO10001
      DEMO20007
      DEMO30046
      DEMO30243
    ].freeze
    PREVIOUS_UNIT_CODE = 'DEMO09999'
    UNIT_CODES = [*CURRENT_UNIT_CODES, PREVIOUS_UNIT_CODE].freeze
    PPI_UNIT_CODE = 'DEMO10001'
    PPI_TASK_ABBREVIATION = 'DUE7'
    COHORT_SIZE = 25
    PPI_STATUS_COUNTS = {
      not_started: 5,
      working_on_it: 5,
      ready_for_feedback: 4,
      fix_and_resubmit: 3,
      redo: 3,
      complete: 3,
      fail: 2
    }.freeze
    PPI_REQUIRED_VISIBLE_STATUSES = PPI_STATUS_COUNTS.keys.freeze
    PPI_UPLOADED_STATUSES = %i[
      ready_for_feedback
      fix_and_resubmit
      redo
      complete
      fail
    ].freeze
    PPI_PEER_STATUS_KEYS = PPI_STATUS_COUNTS.flat_map do |status, count|
      peer_count = status == :not_started ? count - 1 : count
      [status] * peer_count
    end.freeze
    SUBMITTED_COUNT = PPI_UPLOADED_STATUSES.sum do |status|
      PPI_STATUS_COUNTS.fetch(status)
    end
    NOTIFICATION_COUNT = 7

    TASK_BLUEPRINTS = [
      {
        abbreviation: 'OVERDUE',
        name: 'Overdue Foundations',
        start_offset: -21,
        target_offset: -1,
        status: :not_started,
        weighting: 3
      },
      {
        abbreviation: 'DUE3',
        name: 'Due Within Three Days',
        start_offset: -10,
        # The web maps date-only deadlines to the end of that day. Two calendar
        # days ahead therefore stays inside the 72-hour warning window all day.
        target_offset: 2,
        status: :not_started,
        weighting: 6
      },
      {
        abbreviation: PPI_TASK_ABBREVIATION,
        name: 'Due Within Seven Days',
        start_offset: -7,
        # Likewise, six days ahead remains inside the seven-day warning window
        # after the client applies its end-of-day display convention.
        target_offset: 6,
        status: :not_started,
        weighting: 4
      },
      {
        abbreviation: 'FUTURE',
        name: 'Future Planning',
        start_offset: 10,
        target_offset: 14,
        status: :not_started,
        weighting: 2
      },
      {
        abbreviation: 'WORK',
        name: 'Work in Progress',
        start_offset: -5,
        target_offset: 10,
        status: :working_on_it,
        weighting: 5
      },
      {
        abbreviation: 'DONE',
        name: 'Completed Practice',
        start_offset: -28,
        target_offset: -7,
        status: :complete,
        weighting: 1
      }
    ].freeze

    UNIT_NAMES = {
      'DEMO10001' => 'Foundations of OnTrack',
      'DEMO20007' => 'Active Learning Studio',
      'DEMO30046' => 'Applied Project Delivery',
      'DEMO30243' => 'Professional Practice',
      PREVIOUS_UNIT_CODE => 'Previous Study Portfolio'
    }.freeze

    def self.run!(reference_time: Time.zone.now)
      new(reference_time: reference_time).run!
    end

    def self.cleanup!
      new(reference_time: Time.zone.now).cleanup!
    end

    def self.verify!(reference_time: Time.zone.now)
      new(reference_time: reference_time).verify!
    end

    def initialize(reference_time:)
      @reference_time = reference_time.in_time_zone.beginning_of_day
    end

    def run!
      guard!

      result = nil
      ActiveRecord::Base.transaction do
        cleanup_records!
        create_scenario!
        result = summary
      end
      result
    end

    def cleanup!
      guard!

      ActiveRecord::Base.transaction { cleanup_records! }
      true
    end

    def verify!
      guard!

      minimum_cohort_size = configured_positive_integer!(
        'DF_PPI_MINIMUM_COHORT_SIZE'
      )
      stale_after_hours = configured_positive_integer!(
        'DF_PPI_STALE_AFTER_HOURS'
      )
      if minimum_cohort_size < PeerProgressApi::MINIMUM_SAFE_COHORT_SIZE
        raise SafetyError,
              'DF_PPI_MINIMUM_COHORT_SIZE is below the API privacy floor.'
      end

      student = User.find_by!(username: DEMO_USERNAME)
      unit = Unit.find_by!(code: PPI_UNIT_CODE)
      definition = unit.task_definitions.find_by!(
        abbreviation: PPI_TASK_ABBREVIATION
      )
      project = student.projects.find_by!(unit: unit)
      viewer_task = project.tasks.find_by!(task_definition: definition)
      snapshot = unit.peer_progress_snapshots.find_by!(
        task_definition: definition,
        target_grade: project.target_grade
      )

      cohort_size = unit.active_projects.where(
        target_grade: project.target_grade
      ).count
      unless unit.active? && unit.peer_progress_enabled? &&
             student.display_peer_progress? && project.enrolled? &&
             cohort_size == COHORT_SIZE &&
             cohort_size - 1 >= minimum_cohort_size
        raise SafetyError,
              'All-features peer-progress cohort or display settings are invalid.'
      end

      unless definition.target_grade <= project.target_grade &&
             definition.start_date.present? &&
             definition.start_date <= Time.zone.now
        raise SafetyError,
              'All-features peer-progress task is not released for the demo student.'
      end

      latest_grade_change = unit.active_projects.where(
        target_grade: project.target_grade
      ).maximum(:target_grade_changed_at)
      unless snapshot.cohort_size == cohort_size &&
             snapshot.submitted_count.is_a?(Integer) &&
             snapshot.submitted_percentage.present? &&
             snapshot.calculated_at >= stale_after_hours.hours.ago &&
             (latest_grade_change.nil? ||
               snapshot.calculated_at >= latest_grade_change)
        raise SafetyError,
              'All-features peer-progress snapshot is stale or inconsistent.'
      end

      peer_progress = PeerProgressViewerPolicy.build(
        snapshot: snapshot,
        viewer_project: project,
        viewer_task: viewer_task
      )
      if peer_progress.nil?
        raise SafetyError,
              'All-features peer-progress snapshot cannot exclude the demo viewer.'
      end

      public_metrics = PeerProgressViewerPolicy.public_metrics(peer_progress)
      distribution = public_metrics.fetch(:status_distribution)
      unless distribution&.length ==
             PeerProgressDistributionPolicy::STATUS_KEYS.length
        raise SafetyError,
              'All-features detailed peer-progress distribution is suppressed.'
      end

      percentages = distribution.index_by do |entry|
        entry.fetch(:status).to_sym
      end
      unless PPI_REQUIRED_VISIBLE_STATUSES.all? do |status|
        percentages.fetch(status).fetch(:percentage).positive?
      end
        raise SafetyError,
              'All-features peer-progress lifecycle statuses are not visible.'
      end

      {
        profile: PROFILE_NAME,
        submitted_percentage: public_metrics.fetch(:submitted_percentage),
        completed_percentage: public_metrics.fetch(:completed_percentage),
        status_distribution: distribution
      }
    rescue ActiveRecord::RecordNotFound => e
      raise SafetyError,
            "All-features demo data is incomplete: #{e.message}"
    end

    def guard!
      unless Rails.env.development?
        raise SafetyError,
              'All-features demo data can run only in Rails development.'
      end

      database_name = connected_database_name
      unless database_name == DATABASE_NAME
        raise SafetyError,
              "All-features demo data requires database #{DATABASE_NAME.inspect}; " \
              "connected to #{database_name.inspect}."
      end

      return if ENV.fetch('DF_DEMO_DATA_PROFILE', nil) == PROFILE_NAME

      raise SafetyError,
            'Set DF_DEMO_DATA_PROFILE=all-features to confirm this demo-only operation.'
    end

    private

    attr_reader :reference_time

    def connected_database_name
      ActiveRecord::Base.connection_db_config.database.to_s
    end

    def configured_positive_integer!(name)
      value = Integer(ENV.fetch(name), 10)
      raise ArgumentError unless value.positive?

      value
    rescue KeyError, ArgumentError
      raise SafetyError, "#{name} must be a positive integer."
    end

    def create_scenario!
      ensure_reference_data!
      campus = create_campus!
      convenor = create_user!(
        username: CONVENOR_USERNAME,
        first_name: 'Demo',
        last_name: 'Convenor',
        role: Role.convenor
      )
      demo_student = create_user!(
        username: DEMO_USERNAME,
        first_name: 'Demo',
        last_name: 'Student',
        role: Role.student,
        student_id: 'DEMO-STUDENT'
      )

      units = UNIT_CODES.index_with do |code|
        create_unit!(code: code, convenor: convenor)
      end

      units.each_value do |unit|
        project = enrol!(unit: unit, student: demo_student, campus: campus)
        materialise_demo_tasks!(project)
      end

      create_ppi_cohort!(unit: units.fetch(PPI_UNIT_CODE), campus: campus)
      aggregate_peer_progress!(units.fetch(PPI_UNIT_CODE))
      create_notifications!(demo_student)
    end

    def ensure_reference_data!
      missing_roles = (1..Role.auditor_id).reject { |id| Role.exists?(id: id) }
      missing_statuses = (1..TaskStatus.count).reject do |id|
        TaskStatus.exists?(id: id)
      end
      return if missing_roles.empty? && missing_statuses.empty?

      raise SafetyError,
            'Run db:init before db:all_features_demo; required roles or task statuses are missing.'
    end

    def create_campus!
      Campus.create!(
        name: CAMPUS_NAME,
        abbreviation: CAMPUS_ABBREVIATION,
        mode: :manual,
        active: true,
        timezone: 'Australia/Melbourne'
      )
    end

    def create_user!(
      username:,
      first_name:,
      last_name:,
      role:,
      student_id: nil,
      notifications_enabled: true
    )
      User.create!(
        username: username,
        login_id: username,
        email: "#{username}@all-features.invalid",
        first_name: first_name,
        last_name: last_name,
        nickname: first_name,
        role: role,
        student_id: student_id,
        password: 'password',
        password_confirmation: 'password',
        receive_task_notifications: notifications_enabled,
        receive_feedback_notifications: notifications_enabled,
        receive_portfolio_notifications: notifications_enabled,
        display_peer_progress: true,
        opt_in_to_research: false,
        has_run_first_time_setup: true
      )
    end

    def create_unit!(code:, convenor:)
      previous = code == PREVIOUS_UNIT_CODE
      unit = Unit.create!(
        code: code,
        name: UNIT_NAMES.fetch(code),
        description: 'Synthetic local data for the isolated all-features demo.',
        start_date: previous ? reference_time - 24.weeks : reference_time - 6.weeks,
        end_date: previous ? reference_time - 8.weeks : reference_time + 7.weeks,
        active: !previous,
        send_notifications: false,
        enable_sync_timetable: false,
        enable_sync_enrolments: false,
        allow_flexible_dates: false,
        peer_progress_enabled: code == PPI_UNIT_CODE,
        grade_definitions: Unit::DEFAULT_GRADE_DEFINITIONS
      )
      unit.employ_staff(convenor, Role.convenor)
      create_task_definitions!(unit)
      unit
    end

    def create_task_definitions!(unit)
      TASK_BLUEPRINTS.each do |blueprint|
        TaskDefinition.create!(
          unit: unit,
          name: blueprint.fetch(:name),
          abbreviation: blueprint.fetch(:abbreviation),
          description: 'Synthetic task for the isolated all-features demo.',
          weighting: blueprint.fetch(:weighting),
          target_grade: 0,
          start_date: reference_time + blueprint.fetch(:start_offset).days,
          target_date: reference_time + blueprint.fetch(:target_offset).days,
          due_date: reference_time + (blueprint.fetch(:target_offset) + 4).days,
          upload_requirements: [
            {
              'key' => 'file0',
              'name' => 'Demo document',
              'type' => 'document'
            }
          ]
        )
      end
    end

    def enrol!(unit:, student:, campus:)
      project = unit.enrol_student(student, campus)
      project.update!(
        target_grade: 0,
        enrolled: true,
        started: true,
        progress: 'Synthetic all-features demo progress.'
      )
      project
    end

    def materialise_demo_tasks!(project)
      TASK_BLUEPRINTS.each do |blueprint|
        status = TaskStatus.public_send(blueprint.fetch(:status))
        attributes = {
          project: project,
          task_definition: project.unit.task_definitions.find_by!(
            abbreviation: blueprint.fetch(:abbreviation)
          ),
          task_status: status
        }

        if status == TaskStatus.complete
          attributes[:completion_date] = (reference_time - 8.days).to_date
          attributes[:submission_date] = reference_time - 9.days
        end

        Task.create!(attributes)
      end
      project.update_task_stats
    end

    def create_ppi_cohort!(unit:, campus:)
      ppi_definition = unit.task_definitions.find_by!(
        abbreviation: PPI_TASK_ABBREVIATION
      )

      PEER_USERNAMES.each_with_index do |username, index|
        student = create_user!(
          username: username,
          first_name: 'Demo',
          last_name: "Peer #{(index + 1).to_s.rjust(2, '0')}",
          role: Role.student,
          student_id: "DEMO-PEER-#{(index + 1).to_s.rjust(2, '0')}",
          notifications_enabled: false
        )
        project = enrol!(unit: unit, student: student, campus: campus)
        status_key = PPI_PEER_STATUS_KEYS.fetch(index)
        status = TaskStatus.public_send(status_key)
        uploaded = PPI_UPLOADED_STATUSES.include?(status_key)
        submitted_at = uploaded ? reference_time - 1.day : nil
        Task.create!(
          project: project,
          task_definition: ppi_definition,
          task_status: status,
          file_uploaded_at: submitted_at,
          submission_date: submitted_at,
          completion_date:
            status_key == :complete ? (reference_time - 1.day).to_date : nil
        )
        project.update_task_stats
      end
    end

    def aggregate_peer_progress!(unit)
      # Run the production aggregation job synchronously. Calling #perform does
      # not enqueue Sidekiq work and therefore does not touch the running demo.
      AggregatePeerProgressJob.new.perform(unit.id)
    end

    def create_notifications!(student)
      projects_by_code = student.projects.includes(:unit).index_by do |project|
        project.unit.code
      end
      project = projects_by_code.fetch(PPI_UNIT_CODE)
      task_notifications = CURRENT_UNIT_CODES.each_with_index.map do |code, index|
        {
          type: 'task',
          event: 'task_due_soon',
          message: "DUE3 in #{code} is due soon.",
          link: "/projects/#{projects_by_code.fetch(code).id}/dashboard/DUE3",
          dedupe_suffix: "task_due_soon:#{code}",
          age: (15 + (index * 10)).minutes,
          read: false
        }
      end
      notification_blueprints = [
        *task_notifications,
        {
          type: 'feedback',
          event: 'demo_feedback_ready',
          message: 'New feedback is ready for WORK in DEMO10001.',
          link: "/projects/#{project.id}/dashboard/WORK",
          age: 2.hours,
          read: false
        },
        {
          type: 'portfolio',
          event: 'demo_portfolio_available',
          message: 'Your DEMO10001 portfolio is ready to review.',
          link: "/projects/#{project.id}/dashboard",
          age: 1.day,
          read: true
        },
        {
          type: 'general',
          event: 'demo_welcome',
          message: 'Welcome to the isolated all-features demo.',
          link: "/projects/#{project.id}/dashboard/OVERDUE",
          age: 2.days,
          read: true
        }
      ]

      notification_blueprints.each do |blueprint|
        created_at = reference_time - blueprint.fetch(:age)
        notification = NotificationService.reserve(
          user: student,
          type: blueprint.fetch(:type),
          event: blueprint.fetch(:event),
          message: blueprint.fetch(:message),
          link: blueprint.fetch(:link),
          dedupe_key: "all_features_demo:#{blueprint.fetch(:dedupe_suffix, blueprint.fetch(:event))}"
        )
        notification.update!(
          created_at: created_at,
          updated_at: created_at,
          delivered_at: created_at,
          read_at: blueprint.fetch(:read) ? created_at + 5.minutes : nil
        )
      end
    end

    def cleanup_records!
      Unit.where(code: UNIT_CODES).find_each(&:destroy!)
      User.where(username: USERNAMES).find_each(&:destroy!)
      Campus.find_by(abbreviation: CAMPUS_ABBREVIATION)&.destroy!
    end

    def summary
      ppi_unit = Unit.find_by!(code: PPI_UNIT_CODE)
      ppi_definition = ppi_unit.task_definitions.find_by!(
        abbreviation: PPI_TASK_ABBREVIATION
      )
      snapshot = ppi_unit.peer_progress_snapshots.find_by!(
        task_definition: ppi_definition,
        target_grade: 0
      )
      demo_project = User.find_by!(username: DEMO_USERNAME)
                         .projects.find_by!(unit: ppi_unit)
      viewer_task = demo_project.tasks.find_by!(
        task_definition: ppi_definition
      )
      peer_progress = PeerProgressViewerPolicy.build(
        snapshot: snapshot,
        viewer_project: demo_project,
        viewer_task: viewer_task
      )
      public_metrics = PeerProgressViewerPolicy.public_metrics(peer_progress)

      {
        profile: PROFILE_NAME,
        login: DEMO_USERNAME,
        password: 'password',
        unit_codes: UNIT_CODES,
        users: User.where(username: USERNAMES).count,
        projects: Project.joins(:unit).where(units: { code: UNIT_CODES }).count,
        tasks: Task.joins(project: :unit).where(units: { code: UNIT_CODES }).count,
        notifications: User.find_by!(username: DEMO_USERNAME).notifications.count,
        push_subscriptions: PushSubscription.joins(:user).where(users: { username: USERNAMES }).count,
        peer_progress: {
          unit_code: PPI_UNIT_CODE,
          task_abbreviation: PPI_TASK_ABBREVIATION,
          submitted_percentage: public_metrics.fetch(:submitted_percentage),
          completed_percentage: public_metrics.fetch(:completed_percentage),
          distribution_available:
            public_metrics.fetch(:status_distribution).present?
        }
      }
    end
  end
end

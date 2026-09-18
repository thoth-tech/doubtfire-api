# frozen_string_literal: true

require Rails.root.join('lib/demo_data/mobile_feedback_scenario')

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
    CURRENT_UNIT_CODES = MobileFeedbackScenario::CURRENT_UNIT_CODES
    PREVIOUS_UNIT_CODE = MobileFeedbackScenario::PREVIOUS_UNIT_CODE
    UNIT_CODES = MobileFeedbackScenario::UNIT_CODES
    PPI_UNIT_CODE = MobileFeedbackScenario::PRIMARY_UNIT_CODE
    PPI_TASK_ABBREVIATION = MobileFeedbackScenario::PPI_TASK_ABBREVIATION
    COHORT_SIZE = 25
    PPI_STATUS_COUNTS = MobileFeedbackScenario::PPI_PEER_STATUS_COUNTS
                        .fetch(PPI_UNIT_CODE)
                        .merge(ready_for_feedback: 5)
                        .freeze
    PPI_REQUIRED_VISIBLE_STATUSES =
      MobileFeedbackScenario::EXPECTED_TASK_STATUS_PERCENTAGES.keys.freeze
    PPI_UPLOADED_STATUSES = MobileFeedbackScenario::UPLOADED_STATUSES
    SUBMITTED_COUNT = PPI_UPLOADED_STATUSES.sum do |status|
      PPI_STATUS_COUNTS.fetch(status, 0)
    end
    NOTIFICATION_COUNT = 7
    TASK_BLUEPRINTS = MobileFeedbackScenario::TASK_BLUEPRINTS
    UNIT_NAMES = MobileFeedbackScenario::UNIT_NAMES

    def self.run!(reference_time: Time.zone.now)
      new(reference_time: reference_time).run!
    end

    def self.cleanup!
      new(reference_time: Time.zone.now).cleanup!
    end

    def self.verify!(reference_time: Time.zone.now)
      new(reference_time: reference_time).verify!
    end

    def self.contract_for(user:, reference_time: Time.zone.now)
      new(reference_time: reference_time).contract_for(user: user)
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

      contract = contract_for(user: student)
      lifecycle = contract.fetch(:task_lifecycle)
      lifecycle_percentages = lifecycle.fetch(:statuses).to_h do |entry|
        [entry.fetch(:status).to_sym, entry.fetch(:percentage)]
      end
      expected_lifecycle =
        MobileFeedbackScenario::EXPECTED_TASK_STATUS_PERCENTAGES
      ppi_states = contract.fetch(:units).index_by { |item| item.fetch(:code) }
      available_ppi_units = MobileFeedbackScenario::PPI_PEER_STATUS_COUNTS.keys
      lifecycle_valid = lifecycle.fetch(:total_tasks) == 10 &&
                        lifecycle.fetch(:submitted_percentage).to_f.round == 60 &&
                        lifecycle.fetch(:completed_percentage).to_f.round == 10 &&
                        lifecycle_percentages == expected_lifecycle
      available_ppi_valid = available_ppi_units.all? do |code|
        ppi_states.fetch(code).fetch(:ppi).fetch(:state) == 'available'
      end
      unavailable_ppi_valid = ppi_states.fetch(
        MobileFeedbackScenario::PPI_UNAVAILABLE_UNIT_CODE
      ).fetch(:ppi).fetch(:state) == 'unavailable'
      notifications_valid = contract.fetch(:notification_hooks)
                                    .pluck(:event).uniq.length ==
                            NOTIFICATION_COUNT
      group_valid = contract.dig(:group_hook, :member_count) ==
                    MobileFeedbackScenario::GROUP.fetch(:member_count)

      unless lifecycle_valid && available_ppi_valid &&
             unavailable_ppi_valid && notifications_valid && group_valid
        raise SafetyError,
              'All-features mobile-feedback scenario contract is inconsistent.'
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

    def contract_for(user:)
      guard!
      unless user&.username == DEMO_USERNAME
        raise SafetyError, 'The demo scenario is unavailable for this account.'
      end

      projects = user.projects.includes(:unit).index_by { |item| item.unit.code }
      units = CURRENT_UNIT_CODES.to_h do |code|
        project = projects.fetch(code)
        unit = project.unit
        definition = unit.task_definitions.find_by!(
          abbreviation: PPI_TASK_ABBREVIATION
        )
        [
          code,
          {
            key: code,
            code: code,
            name: unit.name,
            unit_id: unit.id,
            project_id: project.id,
            ppi: ppi_contract(
              unit: unit,
              project: project,
              definition: definition
            )
          }
        ]
      end

      {
        schema_version: MobileFeedbackScenario::SCHEMA_VERSION,
        scenario_id: MobileFeedbackScenario::SCENARIO_ID,
        demo_only: true,
        generated_at: PeerProgressSnapshot.joins(:unit)
                                          .where(units: { code: CURRENT_UNIT_CODES })
                                          .maximum(:calculated_at)&.utc&.iso8601,
        primary_unit_key: PPI_UNIT_CODE,
        units: units.values,
        task_lifecycle: task_lifecycle_contract(projects.fetch(PPI_UNIT_CODE)),
        notification_hooks: notification_contract(user),
        group_hook: group_contract(projects),
        walkthrough_links: walkthrough_contract(projects)
      }
    rescue ActiveRecord::RecordNotFound, KeyError => e
      raise SafetyError, "All-features demo data is incomplete: #{e.message}"
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

    def ppi_contract(unit:, project:, definition:)
      snapshot = unit.peer_progress_snapshots.find_by!(
        task_definition: definition,
        target_grade: project.target_grade
      )
      viewer_task = project.tasks.find_by!(task_definition: definition)
      peer_cohort_size = [snapshot.cohort_size - 1, 0].max

      if peer_cohort_size < PeerProgressApi::MINIMUM_SAFE_COHORT_SIZE
        return {
          state: 'unavailable',
          unavailable_reason: 'insufficient_cohort',
          task_abbreviation: definition.abbreviation,
          task_definition_id: definition.id,
          submitted_percentage: nil,
          completed_percentage: nil,
          status_distribution: nil
        }
      end

      peer_progress = PeerProgressViewerPolicy.build(
        snapshot: snapshot,
        viewer_project: project,
        viewer_task: viewer_task
      )
      # build returns nil once the viewer's project or task has changed since
      # aggregation. Report that the way PeerProgressApi does instead of
      # failing the whole contract.
      if peer_progress.nil?
        return {
          state: 'unavailable',
          unavailable_reason: 'aggregation_incomplete',
          task_abbreviation: definition.abbreviation,
          task_definition_id: definition.id,
          submitted_percentage: nil,
          completed_percentage: nil,
          status_distribution: nil
        }
      end

      metrics = PeerProgressViewerPolicy.public_metrics(peer_progress)
      distribution = metrics.fetch(:status_distribution)
      if distribution.blank?
        raise SafetyError, 'Demo peer-progress distribution is unavailable.'
      end

      {
        state: 'available',
        unavailable_reason: nil,
        task_abbreviation: definition.abbreviation,
        task_definition_id: definition.id,
        submitted_percentage: metrics.fetch(:submitted_percentage),
        completed_percentage: metrics.fetch(:completed_percentage),
        status_distribution: distribution
      }
    end

    # Percentages are derived from the persisted tasks, so verify! can compare
    # them with the canonical fixture and the contract never pairs live counts
    # with fixed percentages.
    def task_lifecycle_contract(project)
      grouped = project.tasks.group(:task_status_id).count
      total = project.tasks.count
      # Every fixture status, then any other status a demo task has moved to,
      # so the counts always add up to total_tasks.
      expected_keys = MobileFeedbackScenario::EXPECTED_TASK_STATUS_PERCENTAGES.keys
      other_keys = TaskStatus.where(id: grouped.keys).map(&:status_key) - expected_keys
      statuses = (expected_keys + other_keys).map do |status|
        task_status = TaskStatus.public_send(status)
        count = grouped.fetch(task_status.id, 0)
        tasks = project.tasks
                       .joins(:task_definition)
                       .where(task_status: task_status)
                       .order('task_definitions.abbreviation')
        {
          status: status.to_s,
          count: count,
          percentage: lifecycle_percentage(count, total),
          task_abbreviations: tasks.pluck('task_definitions.abbreviation')
        }
      end

      {
        unit_key: project.unit.code,
        total_tasks: total,
        submitted_percentage: lifecycle_percentage(
          project.tasks.where.not(file_uploaded_at: nil).count,
          total
        ),
        completed_percentage: lifecycle_percentage(
          grouped.fetch(TaskStatus.complete.id, 0),
          total
        ),
        statuses: statuses
      }
    end

    def lifecycle_percentage(count, total)
      return 0.0 if total.zero?

      (count * 100.0 / total).round(1)
    end

    # Resolve each hook through the dedupe key it was seeded with. Other
    # notifications can share an event, for example a tutor comment made
    # while walking through the demo.
    def notification_contract(user)
      records = user.notifications
                    .where(dedupe_key: MobileFeedbackScenario::NOTIFICATIONS.map { |fixture| notification_dedupe_key(fixture) })
                    .index_by(&:dedupe_key)
      MobileFeedbackScenario::NOTIFICATIONS.map do |fixture|
        notification = records.fetch(notification_dedupe_key(fixture))
        {
          key: fixture.fetch(:key),
          id: notification.id,
          event: notification.event,
          notification_type: notification.notification_type,
          read: notification.read?,
          created_at: notification.created_at.utc.iso8601,
          link: notification.link
        }
      end
    end

    def notification_dedupe_key(fixture)
      "all_features_demo:#{fixture.fetch(:key)}"
    end

    def group_contract(projects)
      fixture = MobileFeedbackScenario::GROUP
      project = projects.fetch(fixture.fetch(:unit_code))
      group_set = project.unit.group_sets.find_by!(
        name: fixture.fetch(:group_set_name)
      )
      group = group_set.groups.find_by!(name: fixture.fetch(:name))

      {
        key: fixture.fetch(:key),
        unit_key: project.unit.code,
        unit_id: project.unit_id,
        project_id: project.id,
        group_set_id: group_set.id,
        group_id: group.id,
        name: group.name,
        member_count: group.student_count,
        capacity: group.capacity,
        route: "/projects/#{project.id}/groups"
      }
    end

    def walkthrough_contract(projects)
      MobileFeedbackScenario::WALKTHROUGH_LINKS.map do |fixture|
        route = case fixture.fetch(:route)
                when :notifications
                  '/notifications'
                when :dashboard
                  project = projects.fetch(fixture.fetch(:unit_code))
                  "/projects/#{project.id}/dashboard"
                when :task
                  project = projects.fetch(fixture.fetch(:unit_code))
                  "/projects/#{project.id}/dashboard/#{fixture.fetch(:task)}"
                end
        route = "#{route}?#{fixture.fetch(:query)}" if fixture[:query]
        {
          key: fixture.fetch(:key),
          label: fixture.fetch(:label),
          route: route
        }
      end
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
      peers = create_peer_users!

      units = UNIT_CODES.index_with do |code|
        create_unit!(code: code, convenor: convenor)
      end

      demo_projects = units.transform_values do |unit|
        project = enrol!(unit: unit, student: demo_student, campus: campus)
        materialise_demo_tasks!(project)
        project
      end

      peer_projects = create_ppi_cohorts!(
        units: units,
        peers: peers,
        campus: campus
      )
      CURRENT_UNIT_CODES.each do |code|
        aggregate_peer_progress!(units.fetch(code))
      end
      create_group_hook!(
        unit: units.fetch(MobileFeedbackScenario::GROUP.fetch(:unit_code)),
        campus: campus,
        convenor: convenor,
        demo_project: demo_projects.fetch(
          MobileFeedbackScenario::GROUP.fetch(:unit_code)
        ),
        peer_projects: peer_projects.fetch(
          MobileFeedbackScenario::GROUP.fetch(:unit_code)
        ).first(2)
      )
      create_notifications!(demo_student)
    end

    def create_peer_users!
      PEER_USERNAMES.each_with_index.map do |username, index|
        create_user!(
          username: username,
          first_name: 'Demo',
          last_name: "Peer #{(index + 1).to_s.rjust(2, '0')}",
          role: Role.student,
          student_id: "DEMO-PEER-#{(index + 1).to_s.rjust(2, '0')}",
          notifications_enabled: false
        )
      end
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
        peer_progress_enabled: CURRENT_UNIT_CODES.include?(code),
        grade_definitions: Unit::DEFAULT_GRADE_DEFINITIONS
      )
      unit.employ_staff(convenor, Role.convenor)
      create_task_definitions!(unit)
      unit
    end

    def create_task_definitions!(unit)
      TASK_BLUEPRINTS.each do |blueprint|
        target_offset = blueprint.fetch(:target_offset)
        if unit.code != PPI_UNIT_CODE
          target_offset = MobileFeedbackScenario::NON_PRIMARY_TARGET_OVERRIDES
                          .fetch(blueprint.fetch(:abbreviation), target_offset)
        end
        TaskDefinition.create!(
          unit: unit,
          name: blueprint.fetch(:name),
          abbreviation: blueprint.fetch(:abbreviation),
          description: 'Synthetic task for the isolated all-features demo.',
          weighting: blueprint.fetch(:weighting),
          target_grade: 0,
          start_date: reference_time + blueprint.fetch(:start_offset).days,
          target_date: reference_time + target_offset.days,
          due_date: reference_time + (target_offset + 4).days,
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
      TASK_BLUEPRINTS.each_with_index do |blueprint, index|
        status = TaskStatus.public_send(blueprint.fetch(:status))
        attributes = {
          project: project,
          task_definition: project.unit.task_definitions.find_by!(
            abbreviation: blueprint.fetch(:abbreviation)
          ),
          task_status: status
        }

        if PPI_UPLOADED_STATUSES.include?(blueprint.fetch(:status))
          submitted_at = reference_time - (index + 1).hours
          attributes[:file_uploaded_at] = submitted_at
          attributes[:submission_date] = submitted_at
        end

        if status == TaskStatus.complete
          attributes[:completion_date] = (reference_time - 8.days).to_date
        end

        Task.create!(attributes)
      end
      project.update_task_stats
    end

    def create_ppi_cohorts!(units:, peers:, campus:)
      MobileFeedbackScenario::PPI_PEER_STATUS_COUNTS.to_h do |code, counts|
        unit = units.fetch(code)
        definition = unit.task_definitions.find_by!(
          abbreviation: PPI_TASK_ABBREVIATION
        )
        statuses = counts.flat_map { |status, count| [status] * count }
        projects = peers.each_with_index.map do |student, index|
          project = enrol!(unit: unit, student: student, campus: campus)
          status_key = statuses.fetch(index)
          submitted_at = if PPI_UPLOADED_STATUSES.include?(status_key)
                           reference_time - 1.day
                         end
          Task.create!(
            project: project,
            task_definition: definition,
            task_status: TaskStatus.public_send(status_key),
            file_uploaded_at: submitted_at,
            submission_date: submitted_at,
            completion_date:
              status_key == :complete ? (reference_time - 1.day).to_date : nil
          )
          project.update_task_stats
          project
        end
        [code, projects]
      end
    end

    def aggregate_peer_progress!(unit)
      # Run the production aggregation job synchronously. Calling #perform does
      # not enqueue Sidekiq work and therefore does not touch the running demo.
      AggregatePeerProgressJob.new.perform(unit.id)
    end

    def create_group_hook!(
      unit:,
      campus:,
      convenor:,
      demo_project:,
      peer_projects:
    )
      fixture = MobileFeedbackScenario::GROUP
      unit_role = unit.unit_roles.find_by!(user: convenor)
      tutorial = Tutorial.create!(
        unit: unit,
        unit_role: unit_role,
        campus: campus,
        abbreviation: fixture.fetch(:tutorial),
        meeting_day: 'Wednesday',
        meeting_time: '10:00',
        meeting_location: 'Synthetic demo room'
      )
      group_set = GroupSet.create!(
        unit: unit,
        name: fixture.fetch(:group_set_name),
        capacity: fixture.fetch(:capacity),
        allow_students_to_manage_groups: false,
        allow_students_to_create_groups: false,
        keep_groups_in_same_class: false,
        locked: false
      )
      group = Group.create!(
        group_set: group_set,
        tutorial: tutorial,
        name: fixture.fetch(:name)
      )
      [demo_project, *peer_projects].each do |project|
        group.add_member(project, notify: false)
      end
    end

    def create_notifications!(student)
      projects_by_code = student.projects.includes(:unit).index_by do |project|
        project.unit.code
      end
      project = projects_by_code.fetch(PPI_UNIT_CODE)

      MobileFeedbackScenario::NOTIFICATIONS.each do |blueprint|
        created_at = reference_time - blueprint.fetch(:age)
        link = "/projects/#{project.id}/dashboard/" \
               "#{blueprint.fetch(:task)}#{blueprint.fetch(:suffix, '')}"
        notification = NotificationService.reserve(
          user: student,
          type: blueprint.fetch(:type),
          event: blueprint.fetch(:event),
          message: blueprint.fetch(:message),
          link: link,
          dedupe_key: notification_dedupe_key(blueprint)
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

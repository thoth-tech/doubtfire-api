# frozen_string_literal: true

require 'test_helper'
require 'minitest/mock'
require Rails.root.join('lib/demo_data/all_features_scenario')

class AllFeaturesScenarioTest < ActiveSupport::TestCase
  include Rack::Test::Methods
  include TestHelpers::AuthHelper
  include TestHelpers::JsonHelper

  REFERENCE_TIME = Time.zone.parse('2026-08-24 10:00:00')

  setup do
    @scenario = DemoData::AllFeaturesScenario.new(
      reference_time: REFERENCE_TIME
    )
    @original_profile = ENV.fetch('DF_DEMO_DATA_PROFILE', nil)
    @original_minimum_cohort_size = ENV.fetch(
      'DF_PPI_MINIMUM_COHORT_SIZE',
      nil
    )
    @original_stale_after_hours = ENV.fetch(
      'DF_PPI_STALE_AFTER_HOURS',
      nil
    )
    clear_auth_header
  end

  teardown do
    restore_env('DF_DEMO_DATA_PROFILE', @original_profile)
    restore_env(
      'DF_PPI_MINIMUM_COHORT_SIZE',
      @original_minimum_cohort_size
    )
    restore_env('DF_PPI_STALE_AFTER_HOURS', @original_stale_after_hours)
    clear_auth_header
  end

  test 'hard fails unless every safety guard matches' do
    ENV['DF_DEMO_DATA_PROFILE'] = DemoData::AllFeaturesScenario::PROFILE_NAME

    error = assert_raises(DemoData::AllFeaturesScenario::SafetyError) do
      @scenario.guard!
    end
    assert_includes error.message, 'Rails development'

    with_environment('development') do
      @scenario.stub(:connected_database_name, 'ordinary-development') do
        error = assert_raises(DemoData::AllFeaturesScenario::SafetyError) do
          @scenario.guard!
        end
        assert_includes error.message,
                        DemoData::AllFeaturesScenario::DATABASE_NAME
      end

      @scenario.stub(
        :connected_database_name,
        DemoData::AllFeaturesScenario::DATABASE_NAME
      ) do
        ENV.delete('DF_DEMO_DATA_PROFILE')
        error = assert_raises(DemoData::AllFeaturesScenario::SafetyError) do
          @scenario.guard!
        end
        assert_includes error.message, 'DF_DEMO_DATA_PROFILE=all-features'
      end
    end
  end

  test 'recreates a complete privacy-safe all-features scenario' do
    first_summary = run_scenario_without_delivery!

    assert_equal DemoData::AllFeaturesScenario::PROFILE_NAME,
                 first_summary.fetch(:profile)
    assert_equal DemoData::AllFeaturesScenario::DEMO_USERNAME,
                 first_summary.fetch(:login)
    assert_equal 'password', first_summary.fetch(:password)

    assert_units_and_task_states
    assert_ppi_cohort_and_endpoint
    assert_notifications_are_curated
    assert_group_hook
    assert_demo_contract
    assert_identities_are_generic

    counts_after_first_run = namespace_counts
    second_summary = run_scenario_without_delivery!

    assert_equal counts_after_first_run, namespace_counts
    assert_equal first_summary.except(:peer_progress),
                 second_summary.except(:peer_progress)
    assert_equal 60.0,
                 second_summary.dig(:peer_progress, :submitted_percentage)
    assert_equal 10.0,
                 second_summary.dig(:peer_progress, :completed_percentage)
    assert second_summary.dig(:peer_progress, :distribution_available)
    assert_equal DemoData::AllFeaturesScenario::NOTIFICATION_COUNT,
                 demo_student.notifications.count

    assert_contract_follows_changed_demo_data

    with_demo_safety { @scenario.cleanup! }

    assert_empty Unit.where(code: DemoData::AllFeaturesScenario::UNIT_CODES)
    assert_empty User.where(username: DemoData::AllFeaturesScenario::USERNAMES)
    assert_nil Campus.find_by(
      abbreviation: DemoData::AllFeaturesScenario::CAMPUS_ABBREVIATION
    )
  end

  private

  def run_scenario_without_delivery!
    no_delivery = lambda do |*_args|
      raise 'demo scenario must not invoke an external delivery channel'
    end

    PushNotificationDeliveryJob.stub(:perform_async, no_delivery) do
      NotificationEmailJob.stub(:perform_async, no_delivery) do
        with_demo_safety { @scenario.run! }
      end
    end
  end

  def with_demo_safety(&block)
    ENV['DF_DEMO_DATA_PROFILE'] = DemoData::AllFeaturesScenario::PROFILE_NAME
    with_environment('development') do
      @scenario.stub(
        :connected_database_name,
        DemoData::AllFeaturesScenario::DATABASE_NAME,
        &block
      )
    end
  end

  def with_environment(name, &)
    environment = ActiveSupport::EnvironmentInquirer.new(name)
    Rails.stub(:env, environment, &)
  end

  def assert_units_and_task_states
    scenario_units = Unit.where(
      code: DemoData::AllFeaturesScenario::UNIT_CODES
    )
    assert_equal DemoData::AllFeaturesScenario::UNIT_CODES.sort,
                 scenario_units.pluck(:code).sort
    assert_equal DemoData::AllFeaturesScenario::CURRENT_UNIT_CODES.sort,
                 scenario_units.where(active: true).pluck(:code).sort
    assert_not Unit.find_by!(
      code: DemoData::AllFeaturesScenario::PREVIOUS_UNIT_CODE
    ).active?

    expected_statuses = {
      'OVERDUE' => :not_started,
      'FUTURE' => :not_started,
      'DUE3' => :working_on_it,
      'WORK' => :working_on_it,
      'DUE7' => :ready_for_feedback,
      'AWAITING' => :ready_for_feedback,
      'RESUBMIT' => :fix_and_resubmit,
      'REDO' => :redo,
      'DONE' => :complete,
      'FAILED' => :fail
    }

    DemoData::AllFeaturesScenario::CURRENT_UNIT_CODES.each do |code|
      project = demo_student.projects.joins(:unit).find_by!(
        units: { code: code }
      )
      assert_equal 0, project.target_grade
      assert project.enrolled?
      assert_equal expected_statuses.keys.sort,
                   project.tasks.joins(:task_definition)
                          .pluck('task_definitions.abbreviation').sort

      statuses = project.tasks.includes(:task_definition).to_h do |task|
        [task.task_definition.abbreviation, task.status]
      end
      assert_equal expected_statuses, statuses
      assert_equal 6, project.tasks.where.not(file_uploaded_at: nil).count
      assert_equal 1, project.tasks.where.not(completion_date: nil).count
      assert_not project.unit.send_notifications?
      assert project.unit.task_definitions.none?(&:new_task_notifications_from?)

      definitions = project.unit.task_definitions.index_by(&:abbreviation)
      assert_equal REFERENCE_TIME.to_date - 1,
                   definitions.fetch('OVERDUE').target_date.to_date
      expected_due3_target = code == 'DEMO10001' ? 2 : 9
      assert_equal REFERENCE_TIME.to_date + expected_due3_target,
                   definitions.fetch('DUE3').target_date.to_date
      assert_equal REFERENCE_TIME.to_date + 6,
                   definitions.fetch('DUE7').target_date.to_date
      assert_operator definitions.fetch('FUTURE').start_date,
                      :>,
                      REFERENCE_TIME
    end

    recommendation_unit_ids = TaskPrioritizationService
                              .new(demo_student, today: REFERENCE_TIME.to_date)
                              .call
                              .pluck(:unit_id)
                              .uniq
    expected_unit_ids = Unit.where(
      code: DemoData::AllFeaturesScenario::CURRENT_UNIT_CODES
    ).pluck(:id)
    assert_equal expected_unit_ids.sort, recommendation_unit_ids.sort
  end

  def assert_ppi_cohort_and_endpoint
    unit = Unit.find_by!(code: DemoData::AllFeaturesScenario::PPI_UNIT_CODE)
    definition = unit.task_definitions.find_by!(
      abbreviation: DemoData::AllFeaturesScenario::PPI_TASK_ABBREVIATION
    )
    project = demo_student.projects.find_by!(unit: unit)
    snapshot = unit.peer_progress_snapshots.find_by!(
      task_definition: definition,
      target_grade: 0
    )

    assert unit.peer_progress_enabled?
    assert_equal DemoData::AllFeaturesScenario::COHORT_SIZE,
                 unit.active_projects.where(target_grade: 0).count
    assert_equal DemoData::AllFeaturesScenario::SUBMITTED_COUNT,
                 unit.tasks.where(task_definition: definition)
                     .where.not(file_uploaded_at: nil).count
    assert_equal DemoData::AllFeaturesScenario::COHORT_SIZE,
                 snapshot.cohort_size
    assert_equal DemoData::AllFeaturesScenario::SUBMITTED_COUNT,
                 snapshot.submitted_count
    assert_equal 64.0, snapshot.submitted_percentage.to_f
    expected_status_counts = PeerProgressDistributionPolicy::STATUS_KEYS
                             .index_with { 0 }
                             .merge(
                               DemoData::AllFeaturesScenario::PPI_STATUS_COUNTS
                                 .stringify_keys
                             )
    assert_equal expected_status_counts, snapshot.status_counts

    ENV['DF_PPI_MINIMUM_COHORT_SIZE'] =
      PeerProgressApi::MINIMUM_SAFE_COHORT_SIZE.to_s
    ENV['DF_PPI_STALE_AFTER_HOURS'] = '48'
    clear_auth_header
    add_auth_header_for(user: demo_student)
    get "/api/projects/#{project.id}/task_def_id/#{definition.id}/peer_progress"

    assert_equal 200, last_response.status, last_response.body
    assert_equal 60.0, last_response_body.fetch('submitted_percentage')
    assert_equal 10.0, last_response_body.fetch('completed_percentage')
    assert_equal true,
                 last_response_body.fetch('distribution_available')
    assert_equal PeerProgressDistributionPolicy::STATUS_KEYS,
                 last_response_body.fetch('status_distribution').pluck('status')
    assert_equal false, last_response_body.fetch('is_suppressed')

    verification = with_demo_safety { @scenario.verify! }
    assert_equal 60.0, verification.fetch(:submitted_percentage)
    assert_equal 10.0, verification.fetch(:completed_percentage)
    assert_equal PeerProgressDistributionPolicy::STATUS_KEYS,
                 verification.fetch(:status_distribution).pluck(:status)

    expected_states = {
      'DEMO10001' => [60.0, 10.0],
      'DEMO20007' => [70.0, 20.0],
      'DEMO30046' => [50.0, 20.0]
    }
    expected_states.each do |code, (submitted, complete)|
      state = with_demo_safety { @scenario.contract_for(user: demo_student) }
              .fetch(:units)
              .find { |item| item.fetch(:code) == code }
              .fetch(:ppi)
      assert_equal 'available', state.fetch(:state)
      assert_equal submitted, state.fetch(:submitted_percentage)
      assert_equal complete, state.fetch(:completed_percentage)
      assert_equal PeerProgressDistributionPolicy::STATUS_KEYS,
                   state.fetch(:status_distribution).pluck(:status)
    end

    contract = with_demo_safety do
      @scenario.contract_for(user: demo_student)
    end
    unavailable = contract.fetch(:units).find do |item|
      item.fetch(:code) ==
        DemoData::MobileFeedbackScenario::PPI_UNAVAILABLE_UNIT_CODE
    end.fetch(:ppi)
    assert_equal 'unavailable', unavailable.fetch(:state)
    assert_equal 'insufficient_cohort', unavailable.fetch(:unavailable_reason)
    assert_nil unavailable.fetch(:status_distribution)
  end

  def assert_notifications_are_curated
    notifications = demo_student.notifications.order(:created_at)

    assert_equal DemoData::AllFeaturesScenario::NOTIFICATION_COUNT,
                 notifications.count
    assert_equal %w[extension feedback portfolio task task task task],
                 notifications.pluck(:notification_type).sort
    assert notifications.all?(&:delivered_at?)
    assert(notifications.all? { |notification| notification.link.present? })
    assert(notifications.all? { |notification| notification.dedupe_key.present? })
    assert_equal 4, notifications.where(read_at: nil).count
    assert_equal 3, notifications.where.not(read_at: nil).count
    assert_equal DemoData::MobileFeedbackScenario::NOTIFICATIONS.pluck(:event).sort,
                 notifications.pluck(:event).sort
    assert_equal notifications.count, notifications.distinct.count
    assert_equal 'You have new feedback in OnTrack.',
                 notifications.find_by!(event: 'task_comment_created').message
    assert_equal 0, PushSubscription.joins(:user).where(
      users: { username: DemoData::AllFeaturesScenario::USERNAMES }
    ).count

    travel_to REFERENCE_TIME do
      active_demo_units = Unit.where(
        code: DemoData::AllFeaturesScenario::CURRENT_UNIT_CODES,
        active: true
      )

      Unit.stub(:where, active_demo_units) do
        assert_no_difference('Notification.count') do
          SendDueSoonRemindersJob.new.perform
        end
      end
    end
  end

  def assert_group_hook
    fixture = DemoData::MobileFeedbackScenario::GROUP
    unit = Unit.find_by!(code: fixture.fetch(:unit_code))
    group_set = unit.group_sets.find_by!(name: fixture.fetch(:group_set_name))
    group = group_set.groups.find_by!(name: fixture.fetch(:name))

    assert_equal fixture.fetch(:capacity), group.capacity
    assert_equal fixture.fetch(:member_count), group.student_count
    assert group.has_user(demo_student)
    assert_equal fixture.fetch(:tutorial), group.tutorial.abbreviation
  end

  def assert_demo_contract
    contract = with_demo_safety do
      @scenario.contract_for(user: demo_student)
    end

    assert_equal 1, contract.fetch(:schema_version)
    assert_equal 'mobile-feedback-v1', contract.fetch(:scenario_id)
    assert_equal true, contract.fetch(:demo_only)
    assert_equal 10, contract.dig(:task_lifecycle, :total_tasks)
    assert_equal 60.0, contract.dig(:task_lifecycle, :submitted_percentage)
    assert_equal 10.0, contract.dig(:task_lifecycle, :completed_percentage)
    assert_equal(
      DemoData::MobileFeedbackScenario::EXPECTED_TASK_STATUS_PERCENTAGES,
      contract.fetch(:task_lifecycle).fetch(:statuses).to_h do |entry|
        [entry.fetch(:status).to_sym, entry.fetch(:percentage)]
      end
    )
    assert_equal 7, contract.fetch(:notification_hooks).count
    assert_equal 7,
                 contract.fetch(:notification_hooks).pluck(:event).uniq.count
    assert_equal 'Team Indigo', contract.dig(:group_hook, :name)
    assert_equal %w[burndown notifications ppi tasks],
                 contract.fetch(:walkthrough_links).pluck(:key).sort
    assert contract.to_json.exclude?('@all-features.invalid')
    assert contract.to_json.exclude?('demo_peer_')

    error = assert_raises(DemoData::AllFeaturesScenario::SafetyError) do
      with_demo_safety do
        @scenario.contract_for(user: User.find_by!(username: DemoData::AllFeaturesScenario::CONVENOR_USERNAME))
      end
    end
    assert_includes error.message, 'unavailable for this account'

    clear_auth_header
    add_auth_header_for(user: demo_student)
    DemoData::AllFeaturesScenario.stub(:contract_for, contract) do
      get '/api/demo/scenario'
    end
    assert_equal 200, last_response.status, last_response.body
    assert_equal 'private, no-store', last_response.headers['Cache-Control']
    assert_equal 'mobile-feedback-v1', last_response_body.fetch('scenario_id')

    get '/api/demo/scenario'
    assert_equal 404, last_response.status
    assert_equal({ 'error' => 'Not found.' }, last_response_body)
  end

  def assert_identities_are_generic
    users = User.where(username: DemoData::AllFeaturesScenario::USERNAMES)

    assert_equal DemoData::AllFeaturesScenario::USERNAMES.length, users.count
    assert(users.all? { |user| user.email.end_with?('.invalid') })
    assert(users.all? { |user| user.login_id == user.username })
    assert demo_student.valid_password?('password')

    peers = users.where(
      username: DemoData::AllFeaturesScenario::PEER_USERNAMES
    )
    assert(peers.all? { |peer| !peer.receive_task_notifications? })
    assert(peers.all? { |peer| !peer.receive_feedback_notifications? })
    assert(peers.all? { |peer| !peer.receive_portfolio_notifications? })
    assert users.all?(&:display_peer_progress?)
  end

  def namespace_counts
    {
      campuses: Campus.where(
        abbreviation: DemoData::AllFeaturesScenario::CAMPUS_ABBREVIATION
      ).count,
      units: Unit.where(
        code: DemoData::AllFeaturesScenario::UNIT_CODES
      ).count,
      users: User.where(
        username: DemoData::AllFeaturesScenario::USERNAMES
      ).count,
      projects: Project.joins(:unit).where(
        units: { code: DemoData::AllFeaturesScenario::UNIT_CODES }
      ).count,
      tasks: Task.joins(project: :unit).where(
        units: { code: DemoData::AllFeaturesScenario::UNIT_CODES }
      ).count,
      notifications: Notification.joins(:user).where(
        users: { username: DemoData::AllFeaturesScenario::USERNAMES }
      ).count,
      group_sets: GroupSet.joins(:unit).where(
        units: { code: DemoData::AllFeaturesScenario::UNIT_CODES }
      ).count,
      groups: Group.joins(group_set: :unit).where(
        units: { code: DemoData::AllFeaturesScenario::UNIT_CODES }
      ).count,
      group_memberships: GroupMembership.joins(group: { group_set: :unit }).where(
        units: { code: DemoData::AllFeaturesScenario::UNIT_CODES }
      ).count,
      push_subscriptions: PushSubscription.joins(:user).where(
        users: { username: DemoData::AllFeaturesScenario::USERNAMES }
      ).count
    }
  end

  # Runs after the idempotency checks because it changes seeded rows.
  def assert_contract_follows_changed_demo_data
    projects = demo_student.projects.includes(:unit).index_by { |project| project.unit.code }

    # A demo project changed after aggregation leaves its snapshot behind.
    stale_project = projects.fetch('DEMO20007')
    definition = stale_project.unit.task_definitions.find_by!(
      abbreviation: DemoData::AllFeaturesScenario::PPI_TASK_ABBREVIATION
    )
    snapshot = stale_project.unit.peer_progress_snapshots.find_by!(
      task_definition: definition,
      target_grade: stale_project.target_grade
    )
    stale_project.touch(time: snapshot.calculated_at + 1.minute)

    # Move the failed task to complete without the status side effects.
    failed_task = projects.fetch('DEMO10001').tasks.joins(:task_definition)
                          .find_by!(task_definitions: { abbreviation: 'FAILED' })
    failed_task.update_columns(task_status_id: TaskStatus.complete.id) # rubocop:disable Rails/SkipsModelValidations

    contract = with_demo_safety { @scenario.contract_for(user: demo_student) }

    stale = contract.fetch(:units).find { |item| item.fetch(:code) == 'DEMO20007' }.fetch(:ppi)
    assert_equal 'unavailable', stale.fetch(:state)
    assert_equal 'aggregation_incomplete', stale.fetch(:unavailable_reason)
    assert_nil stale.fetch(:status_distribution)

    lifecycle = contract.fetch(:task_lifecycle)
    percentages = lifecycle.fetch(:statuses).to_h do |entry|
      [entry.fetch(:status), entry.fetch(:percentage)]
    end
    assert_equal 20.0, percentages.fetch('complete')
    assert_equal 0.0, percentages.fetch('fail')
    assert_equal 20.0, lifecycle.fetch(:completed_percentage)

    assert_contract_ignores_unseeded_data(projects)
  end

  def assert_contract_ignores_unseeded_data(projects)
    seeded_feedback = demo_student.notifications.find_by!(dedupe_key: 'all_features_demo:feedback')
    # Tutor comments during the walkthrough raise more notifications with the
    # same event. Their keys sort either side of the seeded one, so a lookup by
    # event picks the wrong row whichever order the rows come back in.
    %w[aa-walkthrough-comment zz-walkthrough-comment].each do |dedupe_key|
      FactoryBot.create(:notification, :feedback, user: demo_student, event: 'task_comment_created', dedupe_key: dedupe_key)
    end
    # A status outside the fixture set.
    work_task = projects.fetch('DEMO10001').tasks.joins(:task_definition)
                        .find_by!(task_definitions: { abbreviation: 'WORK' })
    work_task.update_columns(task_status_id: TaskStatus.need_help.id) # rubocop:disable Rails/SkipsModelValidations

    contract = with_demo_safety { @scenario.contract_for(user: demo_student) }

    feedback_hook = contract.fetch(:notification_hooks).find { |hook| hook.fetch(:key) == 'feedback' }
    assert_equal seeded_feedback.id, feedback_hook.fetch(:id)

    lifecycle = contract.fetch(:task_lifecycle)
    assert_equal lifecycle.fetch(:total_tasks), lifecycle.fetch(:statuses).sum { |entry| entry.fetch(:count) }
    need_help = lifecycle.fetch(:statuses).find { |entry| entry.fetch(:status) == 'need_help' }
    assert_equal ['WORK'], need_help.fetch(:task_abbreviations)
  end

  def demo_student
    User.find_by!(username: DemoData::AllFeaturesScenario::DEMO_USERNAME)
  end

  def restore_env(name, value)
    value.nil? ? ENV.delete(name) : ENV[name] = value
  end
end

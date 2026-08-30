# frozen_string_literal: true

require 'grape'

class PeerProgressApi < Grape::API
  helpers AuthenticationHelpers

  UNAVAILABLE_MESSAGE = 'Peer progress is currently unavailable.'
  NOT_FOUND_MESSAGE = 'Peer progress is unavailable for this project or task.'
  CONFIG_ERROR_MESSAGE = 'Peer progress is not configured.'
  # These two constants are a pair and must not be changed independently.
  #
  # The zero and hundred edge buckets only hide the underlying submitted count
  # while half a bucket is wider than one student's share of the peer-only
  # cohort. At 20 remaining peers, one peer is exactly five percentage points
  # and zero becomes a singleton bucket. A floor of 21 remaining peers makes
  # one peer's share smaller than the boundary, so every returned bucket
  # represents at least two possible peer counts.
  #
  # 21 and 10.0 leave no cohort size at or above the floor from which the count
  # can be recovered. peer_progress_api_test.rb asserts the relationship holds.
  MINIMUM_SAFE_COHORT_SIZE = 21
  PERCENTAGE_BUCKET_SIZE =
    PeerProgressDistributionPolicy::PERCENTAGE_BUCKET_SIZE

  before do
    header 'Cache-Control', 'private, no-store'
    authenticated?
  end

  helpers do
    def peer_progress_not_found!
      error!({ error: PeerProgressApi::NOT_FOUND_MESSAGE }, 404)
    end

    def effective_task(project:, task_definition:)
      project.tasks.find_by(
        task_definition_id: task_definition.id
      ) || Task.new(
        project: project,
        task_definition: task_definition,
        task_status: TaskStatus.not_started,
        extensions: 0
      )
    end

    def released_for_project?(project:, task_definition:)
      start_date = effective_task(
        project: project,
        task_definition: task_definition
      ).local_start_date

      start_date.present? && start_date <= Time.zone.now
    end

    def safe_target_grade(project)
      target_grade = project.target_grade

      target_grade if target_grade.present? &&
                      project.unit.grade_value?(target_grade)
    end

    def positive_integer_env!(name)
      value = Integer(ENV.fetch(name), 10)
      raise ArgumentError unless value.positive?

      value
    rescue KeyError, ArgumentError
      error!({ error: PeerProgressApi::CONFIG_ERROR_MESSAGE }, 503)
    end

    def minimum_cohort_size!
      value = positive_integer_env!(
        'DF_PPI_MINIMUM_COHORT_SIZE'
      )

      return value if value >= PeerProgressApi::MINIMUM_SAFE_COHORT_SIZE

      error!(
        { error: PeerProgressApi::CONFIG_ERROR_MESSAGE },
        503
      )
    end

    def peer_progress_payload(project:, task_definition:, **overrides)
      state = {
        snapshot: nil,
        submitted_percentage: nil,
        completed_percentage: nil,
        status_distribution: nil,
        distribution_unavailable_reason: nil,
        is_suppressed: false,
        is_stale: false,
        is_feature_enabled: true,
        is_user_enabled: current_user.display_peer_progress?,
        unavailable_reason: nil,
        unavailable_message: ''
      }
      overrides.assert_valid_keys(*state.keys)
      state.merge!(overrides)

      distribution_available = state[:status_distribution].present?
      if !distribution_available &&
         state[:distribution_unavailable_reason].nil?
        state[:distribution_unavailable_reason] = state[:unavailable_reason]
      end

      {
        task_definition_id: task_definition.id,
        unit_id: project.unit_id,
        target_grade: safe_target_grade(project),
        submitted_percentage: state[:submitted_percentage],
        completed_percentage: state[:completed_percentage],
        status_distribution: state[:status_distribution],
        distribution_available: distribution_available,
        distribution_unavailable_reason:
          state[:distribution_unavailable_reason],
        is_suppressed: state[:is_suppressed],
        is_stale: state[:is_stale],
        is_feature_enabled: state[:is_feature_enabled],
        is_user_enabled: state[:is_user_enabled],
        last_updated_at: state[:snapshot]&.calculated_at&.utc&.iso8601,
        unavailable_reason: state[:unavailable_reason],
        unavailable_message: state[:unavailable_message]
      }
    end

    def peer_progress_result(project:, task_definition:)
      unit = project.unit

      unless current_user.display_peer_progress?
        return peer_progress_payload(
          project: project,
          task_definition: task_definition,
          is_user_enabled: false,
          unavailable_reason: 'user_disabled',
          unavailable_message: PeerProgressApi::UNAVAILABLE_MESSAGE
        )
      end

      unless unit.peer_progress_enabled?
        return peer_progress_payload(
          project: project,
          task_definition: task_definition,
          is_feature_enabled: false,
          unavailable_reason: 'feature_disabled',
          unavailable_message: PeerProgressApi::UNAVAILABLE_MESSAGE
        )
      end

      target_grade = safe_target_grade(project)
      unless target_grade
        return peer_progress_payload(
          project: project,
          task_definition: task_definition,
          unavailable_reason: 'target_grade_unavailable',
          unavailable_message: PeerProgressApi::UNAVAILABLE_MESSAGE
        )
      end

      snapshot = unit.peer_progress_snapshots.find_by(
        task_definition_id: task_definition.id,
        target_grade: target_grade
      )

      if snapshot.nil? ||
         (project.target_grade_changed_at.present? &&
           snapshot.calculated_at < project.target_grade_changed_at)
        return peer_progress_payload(
          project: project,
          task_definition: task_definition,
          unavailable_reason: 'snapshot_unavailable',
          unavailable_message: PeerProgressApi::UNAVAILABLE_MESSAGE
        )
      end

      viewer_task = effective_task(
        project: project,
        task_definition: task_definition
      )
      unless PeerProgressViewerPolicy.viewer_context_current?(
        snapshot: snapshot,
        viewer_project: project,
        viewer_task: viewer_task
      )
        return peer_progress_payload(
          project: project,
          task_definition: task_definition,
          snapshot: snapshot,
          unavailable_reason: 'snapshot_unavailable',
          unavailable_message: PeerProgressApi::UNAVAILABLE_MESSAGE
        )
      end

      minimum_cohort_size = minimum_cohort_size!
      stale_after_hours = positive_integer_env!(
        'DF_PPI_STALE_AFTER_HOURS'
      )

      is_stale = snapshot.calculated_at < stale_after_hours.hours.ago

      # Treat an empty cohort exactly like every other cohort below the
      # privacy threshold. This prevents the response from revealing
      # whether a target-grade group is empty or merely small.
      peer_cohort_size = [snapshot.cohort_size - 1, 0].max
      if peer_cohort_size < minimum_cohort_size
        return peer_progress_payload(
          project: project,
          task_definition: task_definition,
          snapshot: snapshot,
          is_suppressed: true,
          is_stale: is_stale,
          unavailable_reason: 'insufficient_cohort',
          unavailable_message: PeerProgressApi::UNAVAILABLE_MESSAGE
        )
      end

      peer_progress = PeerProgressViewerPolicy.build(
        snapshot: snapshot,
        viewer_project: project,
        viewer_task: viewer_task
      )
      if peer_progress.nil?
        return peer_progress_payload(
          project: project,
          task_definition: task_definition,
          snapshot: snapshot,
          is_stale: is_stale,
          unavailable_reason: 'aggregation_incomplete',
          unavailable_message: PeerProgressApi::UNAVAILABLE_MESSAGE
        )
      end

      if is_stale
        return peer_progress_payload(
          project: project,
          task_definition: task_definition,
          snapshot: snapshot,
          is_stale: true,
          unavailable_reason: 'stale',
          unavailable_message: PeerProgressApi::UNAVAILABLE_MESSAGE
        )
      end

      peer_progress_payload(
        project: project,
        task_definition: task_definition,
        snapshot: snapshot,
        **PeerProgressViewerPolicy.public_metrics(peer_progress)
      )
    end
  end

  desc 'Get anonymous task-level peer progress for the authenticated student',
       tags: ['peer_progress'],
       summary: 'Get anonymous task-level peer progress'
  params do
    requires :id,
             type: Integer,
             desc: 'The authenticated student project ID'
    requires :task_definition_id,
             type: Integer,
             desc: 'The task definition ID'
  end
  get '/projects/:id/task_def_id/:task_definition_id/peer_progress' do
    peer_progress_not_found! if current_user.role.id != Role.student_id

    project = Project.for_user(current_user, false)
                     .includes(:unit)
                     .find_by(id: params[:id])
    peer_progress_not_found! if project.nil?

    unit = project.unit
    task_definition = unit.task_definitions.find_by(
      id: params[:task_definition_id]
    )
    peer_progress_not_found! if task_definition.nil?

    peer_progress_not_found! unless released_for_project?(
      project: project,
      task_definition: task_definition
    )

    target_grade = project.target_grade
    if target_grade.present? && unit.grade_value?(target_grade) &&
       task_definition.target_grade > target_grade
      peer_progress_not_found!
    end

    present peer_progress_result(
      project: project,
      task_definition: task_definition
    ), with: Grape::Presenters::Presenter
  end
end

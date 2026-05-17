# frozen_string_literal: true

#
# Computes a prioritised list of tasks for a student across their
# active enrolled units.
#
# Score formula:
#   priority = (W_DEADLINE * deadline_score)
#            + (W_EFFORT   * effort_score)
#            + (W_WORKLOAD * workload_score)
#
# The effort_score is a heuristic placeholder based on task weighting.
# It is intended to be replaced by an AI-driven estimator; keep the
# `effort_score_for(task)` method as the integration seam.
#
class TaskPrioritizationService
  # --- Scoring weights ----------------------------------------------------
  W_DEADLINE = 0.5
  W_EFFORT   = 0.3
  W_WORKLOAD = 0.2

  # --- Deadline buckets (days remaining => score) -------------------------
  DEADLINE_BUCKETS = [
    [1,   100],
    [3,   80],
    [7,   60],
    [14,  40]
  ].freeze
  DEADLINE_DEFAULT = 20
  DEADLINE_NONE    = 0   # task has no due_date

  # --- Effort buckets (weighting => score) --------------------------------
  EFFORT_BUCKETS = [
    [10, 30],
    [20, 50],
    [40, 70]
  ].freeze
  EFFORT_DEFAULT = 90

  # --- Workload sub-scoring ------------------------------------------------
  TASK_PRESSURE = { light: 30, medium: 60, heavy: 90 }.freeze
  TASK_PRESSURE_THRESHOLDS = { light: 4, medium: 9 }.freeze # <=4 light, <=9 medium, else heavy

  # target_grade enum: 0=Pass, 1=Credit, 2=Distinction, 3=HD
  TARGET_GRADE_SCORE = { 0 => 40, 1 => 60, 2 => 75, 3 => 90 }.freeze
  TARGET_GRADE_DEFAULT = 40

  WORKLOAD_PRESSURE_WEIGHT = 0.6
  WORKLOAD_GRADE_WEIGHT    = 0.4

  def initialize(user)
    @user = user
  end

  # Public: returns an Array of Hashes sorted by descending priority_score.
  def call
    tasks = active_tasks_for_user
    return [] if tasks.empty?

    workload = workload_score(tasks)

    tasks
      .map { |t| score_task(t, workload) }
      .sort_by { |t| -t[:priority_score] }
  end

  # Exposed for testing and for downstream replacement by AI service.
  def effort_score_for(task)
    weighting = task.task_definition&.weighting.to_f
    bucket_lookup(weighting, EFFORT_BUCKETS, EFFORT_DEFAULT)
  end

  def deadline_score_for(task)
    due_date = task.task_definition&.due_date
    return DEADLINE_NONE unless due_date

    days_left = (due_date.to_date - Time.zone.today).to_i
    bucket_lookup(days_left, DEADLINE_BUCKETS, DEADLINE_DEFAULT)
  end

  private

  attr_reader :user

  # Tasks that require *student action* across active enrolments.
  # Excludes statuses that are complete or awaiting staff assessment.
  def active_tasks_for_user
    Task
      .joins(project: :unit)
      .includes(:task_definition, project: :unit)
      .where(projects: { user_id: user.id, enrolled: true })
      .where(units: { active: true })
      .where.not(task_status_id: completed_status_ids)
      .to_a
  end

  # Status IDs we consider "no further student action needed".
  # Resolved by name from the TaskStatus table — robust against seed reordering.
  def completed_status_ids
    @completed_status_ids ||= TaskStatus
      .where(name: %w[complete discuss demonstrate])
      .pluck(:id)
  end

  def score_task(task, workload)
    deadline = deadline_score_for(task)
    effort   = effort_score_for(task)

    priority = (W_DEADLINE * deadline) +
               (W_EFFORT   * effort)   +
               (W_WORKLOAD * workload)

    {
      task_id:        task.id,
      task_name:      task.task_definition&.name,
      unit_id:        task.project.unit_id,
      project_id:     task.project_id,
      deadline_score: deadline,
      effort_score:   effort,
      workload_score: workload,
      priority_score: priority.round(2)
    }
  end

  def workload_score(tasks)
    pressure = task_pressure_score(tasks.length)
    grade    = target_grade_score

    ((WORKLOAD_PRESSURE_WEIGHT * pressure) +
     (WORKLOAD_GRADE_WEIGHT    * grade)).round
  end

  def task_pressure_score(total_tasks)
    return TASK_PRESSURE[:light]  if total_tasks <= TASK_PRESSURE_THRESHOLDS[:light]
    return TASK_PRESSURE[:medium] if total_tasks <= TASK_PRESSURE_THRESHOLDS[:medium]

    TASK_PRESSURE[:heavy]
  end

  def target_grade_score
    avg = Project
          .where(user_id: user.id, enrolled: true)
          .average(:target_grade)
    return TARGET_GRADE_DEFAULT if avg.nil?

    TARGET_GRADE_SCORE.fetch(avg.round, TARGET_GRADE_DEFAULT)
  end

  # Walks ascending [threshold, score] pairs and returns the first matching score.
  def bucket_lookup(value, buckets, default)
    buckets.each { |threshold, score| return score if value <= threshold }
    default
  end
end

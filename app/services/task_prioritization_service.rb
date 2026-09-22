# frozen_string_literal: true

class TaskPrioritizationService
  Candidate = Data.define(:project, :task_definition, :task, :due_date, :blocked)

  DEADLINE_HORIZON_DAYS = 28
  DEADLINE_WEIGHT = 0.60
  WORKLOAD_WEIGHT = 0.25
  TASK_SIZE_WEIGHT = 0.15
  WORKLOAD_MIDPOINT = 5.0
  PREREQUISITE_STATUS_LEVELS = {
    attention_required: 0,
    ready_for_feedback: 1,
    assess_in_portfolio: 1,
    discuss: 2,
    rediscuss: 2,
    demonstrate: 2,
    complete: 3
  }.freeze

  def initialize(user, today: Time.zone.today)
    @user = user
    @today = today
  end

  def call
    candidates = remaining_candidates
    recommendation_candidates = candidates.reject(&:blocked)
    task_size_scores = calculate_task_size_scores(candidates)
    workload_scores = calculate_workload_scores(candidates, task_size_scores)

    recommendations = recommendation_candidates.map do |candidate|
      [candidate, build_recommendation(candidate, task_size_scores, workload_scores)]
    end
    sorted_recommendations = recommendations.sort_by do |candidate, recommendation|
      [
        -recommendation[:priority_score],
        candidate.due_date || Date.new(9999, 12, 31),
        recommendation[:project_id],
        recommendation[:task_definition_id]
      ]
    end

    sorted_recommendations.map(&:last)
  end

  private

  attr_reader :today, :user

  def remaining_candidates
    projects.flat_map do |project|
      tasks_by_definition = project.tasks.index_by(&:task_definition_id)

      assigned_task_definitions(project).filter_map do |task_definition|
        task = tasks_by_definition[task_definition.id]
        next if task && final_status_ids.include?(task.task_status_id)

        Candidate.new(
          project: project,
          task_definition: task_definition,
          task: task,
          due_date: effective_due_date(project, task_definition, task)&.to_date,
          blocked: blocked_by_prerequisite?(task_definition, tasks_by_definition)
        )
      end
    end
  end

  def projects
    Project
      .for_user(user, false)
      .includes(
        { tasks: [:task_status, { task_definition: :grade_due_dates }] },
        { unit: { task_definitions: [:grade_due_dates, :task_prerequisites] } }
      )
  end

  def assigned_task_definitions(project)
    @assigned_task_definitions ||= {}
    @assigned_task_definitions[project.id] ||= project.unit.task_definitions.select do |task_definition|
      task_definition.target_grade <= project.target_grade.to_i
    end
  end

  def final_status_ids
    @final_status_ids ||= [
      TaskStatus.complete.id,
      TaskStatus.fail.id,
      TaskStatus.feedback_exceeded.id,
      TaskStatus.time_exceeded.id,
      TaskStatus.assess_in_portfolio.id,
      TaskStatus.ready_for_feedback.id
    ]
  end

  def effective_due_date(project, task_definition, task)
    return task.local_due_date if task

    if project.unit.allow_flexible_dates
      grade_target_date = task_definition.grade_target_date(project.target_grade.to_i)
      return grade_target_date if grade_target_date
    end

    task_definition.target_date
  end

  def blocked_by_prerequisite?(task_definition, tasks_by_definition)
    task_definition.task_prerequisites.any? do |link|
      prerequisite_task = tasks_by_definition[link.prerequisite_id]
      next true unless prerequisite_task&.ready_or_complete?

      current_level = PREREQUISITE_STATUS_LEVELS[prerequisite_task.status]
      required_level = PREREQUISITE_STATUS_LEVELS[TaskStatus.id_to_key(link.task_status_id)]

      current_level.nil? || required_level.nil? || current_level < required_level
    end
  end

  # Weighting is comparable within a unit, not across units. The denominator
  # includes all work assigned at the student's target grade, so completing a
  # task does not inflate the relative size of every task that remains.
  def calculate_task_size_scores(candidates)
    project_totals = candidates.map(&:project).uniq.to_h do |project|
      assigned_definitions = assigned_task_definitions(project)
      total_weight = assigned_definitions.sum { |task_definition| definition_weight(task_definition) }

      [project.id, { weight: total_weight, count: assigned_definitions.length }]
    end

    candidates.to_h do |candidate|
      totals = project_totals.fetch(candidate.project.id)
      score = if totals[:weight].positive?
                (task_weight(candidate) / totals[:weight]) * 100
              elsif totals[:count].positive?
                100.0 / totals[:count]
              else
                0
              end
      [candidate, score]
    end
  end

  # Workload pressure is full-project percentage points due by this task's date
  # per available day. A fixed saturating curve maps five percentage points per
  # day to 50 without rescaling recommendations against one another.
  # Grouping equal dates before accumulating preserves the inclusive
  # "work due by this date" semantics without rescanning every candidate.
  def calculate_workload_scores(candidates, task_size_scores)
    workload_scores = candidates.index_with { 0 }
    candidates_with_due_dates = candidates.select(&:due_date).group_by(&:due_date)
    cumulative_work = 0.0

    candidates_with_due_dates.sort_by { |due_date, _| due_date }.each do |due_date, due_candidates|
      cumulative_work += due_candidates.sum { |candidate| task_size_scores.fetch(candidate) }
      available_days = [(due_date - today).to_i, 1].max
      raw_pressure = cumulative_work / available_days
      pressure = (raw_pressure * 100) / (raw_pressure + WORKLOAD_MIDPOINT)

      due_candidates.each do |candidate|
        workload_scores[candidate] = pressure
      end
    end

    workload_scores
  end

  def task_weight(candidate)
    definition_weight(candidate.task_definition)
  end

  def definition_weight(task_definition)
    [task_definition.weighting.to_f, 0].max
  end

  def deadline_score(candidate)
    return 0 unless candidate.due_date

    days_left = (candidate.due_date - today).to_i
    return 100 if days_left <= 0
    return 0 if days_left >= DEADLINE_HORIZON_DAYS

    ((DEADLINE_HORIZON_DAYS - days_left) / DEADLINE_HORIZON_DAYS.to_f) * 100
  end

  def build_recommendation(candidate, task_size_scores, workload_scores)
    priority_score =
      (DEADLINE_WEIGHT * deadline_score(candidate)) +
      (WORKLOAD_WEIGHT * workload_scores.fetch(candidate)) +
      (TASK_SIZE_WEIGHT * task_size_scores.fetch(candidate))
    priority_score = priority_score.clamp(0, 100)

    {
      task_id: candidate.task&.id,
      task_definition_id: candidate.task_definition.id,
      task_name: candidate.task_definition.name,
      project_id: candidate.project.id,
      unit_id: candidate.project.unit_id,
      priority_score: priority_score.round(2)
    }
  end
end

# frozen_string_literal: true

require 'test_helper'

class TaskPrioritizationApiTest < ActiveSupport::TestCase
  include Rack::Test::Methods
  include TestHelpers::AuthHelper
  include TestHelpers::JsonHelper

  setup do
    clear_auth_header
    @today = Time.zone.parse('2026-08-24 10:00:00 UTC')
  end

  teardown do
    clear_auth_header
  end

  test 'requires authentication' do
    get endpoint

    assert_equal 419, last_response.status
  end

  test 'recommends assigned definitions even before task rows exist' do
    travel_to @today do
      unit = create_unit
      later_definition = create_task_definition(unit, name: 'Later task', target_date: 12.days.from_now)
      urgent_definition = create_task_definition(unit, name: 'Urgent task', target_date: 2.days.from_now)
      student = create(:user, :student)
      project = enrol_student(unit, student, target_grade: 0)

      assert_empty project.tasks

      assert_no_difference 'Task.count' do
        request_as(student)
      end

      assert_equal 200, last_response.status, last_response.body
      body = last_response_body
      assert_equal [urgent_definition.id, later_definition.id], body['data'].pluck('task_definition_id')
      assert(body['data'].all? { |recommendation| recommendation['task_id'].nil? })
      assert_equal %w[
        task_id
        task_definition_id
        task_name
        project_id
        unit_id
        priority_score
      ], body['data'].first.keys
      assert_equal(
        {
          'page' => 1,
          'per_page' => TaskPrioritizationApi::DEFAULT_PER_PAGE,
          'total_count' => 2,
          'total_pages' => 1
        },
        body['meta']
      )
    end
  end

  test 'uses flexible grade dates for assigned definitions without task rows' do
    travel_to @today do
      unit = create_unit(allow_flexible_dates: true)
      base_earlier_definition = create_task_definition(
        unit,
        name: 'Base earlier task',
        target_date: 2.days.from_now
      )
      base_later_definition = create_task_definition(
        unit,
        name: 'Base later task',
        target_date: 12.days.from_now
      )
      create_grade_due_date(base_earlier_definition, target_grade: 1, target_due_date: 20.days.from_now)
      create_grade_due_date(base_later_definition, target_grade: 1, target_due_date: 1.day.from_now)
      student = create(:user, :student)
      project = enrol_student(unit, student, target_grade: 1)

      assert_empty project.tasks

      request_as(student)

      assert_equal [base_later_definition.id, base_earlier_definition.id],
                   last_response_body['data'].pluck('task_definition_id')
      assert_empty project.tasks.reload
    end
  end

  test 'uses personalized local due dates for materialized tasks' do
    travel_to @today do
      unit = create_unit(allow_flexible_dates: true)
      base_earlier_definition = create_task_definition(
        unit,
        name: 'Base earlier task',
        target_date: 1.day.from_now
      )
      base_later_definition = create_task_definition(
        unit,
        name: 'Base later task',
        target_date: 20.days.from_now
      )
      student = create(:user, :student)
      project = enrol_student(unit, student, target_grade: 0)
      base_earlier_task = project.task_for_task_definition(base_earlier_definition)
      base_later_task = project.task_for_task_definition(base_later_definition)

      base_earlier_task.update!(target_due_date: 20.days.from_now)
      base_later_task.update!(target_due_date: 1.day.from_now)

      request_as(student)

      assert_equal [base_later_definition.id, base_earlier_definition.id],
                   last_response_body['data'].pluck('task_definition_id')
      assert_operator last_response_body['data'].first['priority_score'],
                      :>,
                      last_response_body['data'].last['priority_score']
    end
  end

  test 'uses extension-adjusted due dates for materialized tasks' do
    travel_to @today do
      unit = create_unit
      extended_definition = create_task_definition(
        unit,
        name: 'Extended task',
        target_date: 1.day.from_now
      )
      nearer_definition = create_task_definition(
        unit,
        name: 'Nearer task',
        target_date: 7.days.from_now
      )
      student = create(:user, :student)
      project = enrol_student(unit, student, target_grade: 0)
      extended_task = project.task_for_task_definition(extended_definition)
      project.task_for_task_definition(nearer_definition)

      extended_task.update!(extensions: 2)

      request_as(student)

      assert_equal [nearer_definition.id, extended_definition.id],
                   last_response_body['data'].pluck('task_definition_id')
    end
  end

  test 'uses task-specific deadline workload and relative size in the ranking' do
    travel_to @today do
      unit = create_unit
      early_definition = create_task_definition(
        unit,
        name: 'Small early task',
        target_date: 5.days.from_now,
        weighting: 1
      )
      clustered_small_definition = create_task_definition(
        unit,
        name: 'Small clustered task',
        target_date: 6.days.from_now,
        weighting: 1
      )
      clustered_large_definition = create_task_definition(
        unit,
        name: 'Large clustered task',
        target_date: 6.days.from_now,
        weighting: 8
      )
      student = create(:user, :student)
      enrol_student(unit, student, target_grade: 0)

      request_as(student)

      returned_ids = last_response_body['data'].pluck('task_definition_id')
      assert_equal clustered_large_definition.id, returned_ids.first
      assert_operator returned_ids.index(clustered_small_definition.id), :<, returned_ids.index(early_definition.id)
    end
  end

  test 'completed work lowers workload without inflating the remaining task size' do
    travel_to @today do
      unit = create_unit
      remaining_definition = create_task_definition(
        unit,
        name: 'Remaining task',
        target_date: 7.days.from_now,
        weighting: 1
      )
      completed_definition = create_task_definition(
        unit,
        name: 'Task to complete',
        target_date: 7.days.from_now,
        weighting: 1
      )
      student = create(:user, :student)
      project = enrol_student(unit, student, target_grade: 0)

      request_as(student)
      score_before_completion = score_for(last_response_body['data'], remaining_definition)

      project.task_for_task_definition(completed_definition).update!(task_status: TaskStatus.complete)
      request_as(student)
      score_after_completion = score_for(last_response_body['data'], remaining_definition)

      assert_operator score_after_completion, :<, score_before_completion
    end
  end

  test 'does not recommend a dependent until its prerequisite reaches the required status' do
    travel_to @today do
      unit = create_unit
      prerequisite_definition = create_task_definition(unit, name: 'Prerequisite')
      dependent_definition = create_task_definition(unit, name: 'Dependent')
      TaskPrerequisite.create!(
        task_definition: dependent_definition,
        prerequisite: prerequisite_definition,
        task_status_id: TaskStatus.complete.id
      )
      student = create(:user, :student)
      project = enrol_student(unit, student, target_grade: 0)

      request_as(student)
      assert_equal [prerequisite_definition.id], last_response_body['data'].pluck('task_definition_id')

      prerequisite_task = project.task_for_task_definition(prerequisite_definition)
      prerequisite_task.update!(task_status: TaskStatus.ready_for_feedback)
      request_as(student)
      assert_empty last_response_body['data']

      prerequisite_task.update!(task_status: TaskStatus.complete)
      request_as(student)
      assert_equal [dependent_definition.id], last_response_body['data'].pluck('task_definition_id')
    end
  end

  test 'keeps attention required blocked to match submission authorization' do
    travel_to @today do
      unit = create_unit
      prerequisite_definition = create_task_definition(unit, name: 'Attention prerequisite')
      dependent_definition = create_task_definition(unit, name: 'Attention dependent')
      create_prerequisite(
        dependent_definition,
        prerequisite_definition,
        required_status: TaskStatus.attention_required
      )
      student = create(:user, :student)
      project = enrol_student(unit, student, target_grade: 0)
      project
        .task_for_task_definition(prerequisite_definition)
        .update!(task_status: TaskStatus.attention_required)

      request_as(student)

      assert_not_includes last_response_body['data'].pluck('task_definition_id'), dependent_definition.id
    end
  end

  test 'accepts rediscuss for a discussion-level prerequisite' do
    travel_to @today do
      unit = create_unit
      prerequisite_definition = create_task_definition(unit, name: 'Discussion prerequisite')
      dependent_definition = create_task_definition(unit, name: 'Discussion dependent')
      create_prerequisite(
        dependent_definition,
        prerequisite_definition,
        required_status: TaskStatus.discuss
      )
      student = create(:user, :student)
      project = enrol_student(unit, student, target_grade: 0)
      project
        .task_for_task_definition(prerequisite_definition)
        .update!(task_status: TaskStatus.rediscuss)

      request_as(student)

      assert_includes last_response_body['data'].pluck('task_definition_id'), dependent_definition.id
    end
  end

  test 'keeps overdue and future priority scores within the zero to one hundred contract' do
    travel_to @today do
      unit = create_unit
      overdue_definition = create_task_definition(unit, name: 'Overdue task', target_date: 40.days.ago)
      future_definition = create_task_definition(unit, name: 'Future task', target_date: 7.days.from_now)
      student = create(:user, :student)
      enrol_student(unit, student, target_grade: 0)

      request_as(student)

      recommendations = last_response_body['data']
      scores = recommendations.pluck('priority_score')
      assert(scores.all? { |score| score.between?(0, 100) })
      assert_operator score_for(recommendations, overdue_definition),
                      :>,
                      score_for(recommendations, future_definition)
    end
  end

  test 'only returns eligible unfinished work owned by the authenticated student' do
    travel_to @today do
      active_unit = create_unit
      open_definition = create_task_definition(active_unit, name: 'Open task', target_grade: 0)
      higher_grade_definition = create_task_definition(active_unit, name: 'Higher grade task', target_grade: 3)
      excluded_definitions = non_actionable_statuses.each_with_index.to_h do |status, index|
        definition = create_task_definition(active_unit, name: "Non-actionable task #{index}", target_grade: 0)
        [definition, status]
      end
      student = create(:user, :student)
      project = enrol_student(active_unit, student, target_grade: 0)
      excluded_definitions.each do |definition, status|
        project.task_for_task_definition(definition).update!(task_status: status)
      end

      other_student = create(:user, :student)
      enrol_student(active_unit, other_student, target_grade: 3)

      inactive_unit = create_unit(active: false)
      inactive_definition = create_task_definition(inactive_unit, name: 'Inactive task')
      enrol_student(inactive_unit, student, target_grade: 0)

      withdrawn_unit = create_unit
      withdrawn_definition = create_task_definition(withdrawn_unit, name: 'Withdrawn task')
      withdrawn_project = enrol_student(withdrawn_unit, student, target_grade: 0)
      withdrawn_project.update!(enrolled: false)

      request_as(student)

      returned_ids = last_response_body['data'].pluck('task_definition_id')
      assert_equal [open_definition.id], returned_ids
      assert_not_includes returned_ids, higher_grade_definition.id
      assert_not_includes returned_ids, inactive_definition.id
      assert_not_includes returned_ids, withdrawn_definition.id
      excluded_definitions.each_key do |definition|
        assert_not_includes returned_ids, definition.id
      end
    end
  end

  test 'paginates every recommendation without overlap' do
    travel_to @today do
      unit = create_unit
      definitions = 3.times.map do |index|
        create_task_definition(
          unit,
          name: "Task #{index}",
          target_date: (index + 1).days.from_now
        )
      end
      student = create(:user, :student)
      enrol_student(unit, student, target_grade: 0)

      add_auth_header_for(user: student)
      get endpoint, page: 1, per_page: 2
      first_page = last_response_body

      get endpoint, page: 2, per_page: 2
      second_page = last_response_body

      returned_ids = first_page['data'].pluck('task_definition_id') +
                     second_page['data'].pluck('task_definition_id')
      assert_equal definitions.map(&:id).sort, returned_ids.sort
      assert_equal 2, first_page['data'].length
      assert_equal 1, second_page['data'].length
      assert_equal(
        {
          'page' => 1,
          'per_page' => 2,
          'total_count' => 3,
          'total_pages' => 2
        },
        first_page['meta']
      )
      assert_empty first_page['data'].pluck('task_definition_id') &
                   second_page['data'].pluck('task_definition_id')
    end
  end

  test 'uses project and task definition ids as deterministic tie breakers' do
    travel_to @today do
      unit = create_unit
      definitions = 2.times.map do |index|
        create_task_definition(
          unit,
          name: "Equal task #{index}",
          target_date: 5.days.from_now,
          weighting: 1
        )
      end
      student = create(:user, :student)
      enrol_student(unit, student, target_grade: 0)

      request_as(student)

      assert_equal definitions.map(&:id).sort, last_response_body['data'].pluck('task_definition_id')
    end
  end

  private

  def endpoint
    '/api/tasks/recommended'
  end

  def request_as(user)
    add_auth_header_for(user: user)
    get endpoint
  end

  def non_actionable_statuses
    [
      TaskStatus.complete,
      TaskStatus.fail,
      TaskStatus.feedback_exceeded,
      TaskStatus.time_exceeded,
      TaskStatus.assess_in_portfolio,
      TaskStatus.ready_for_feedback
    ]
  end

  def create_unit(active: true, allow_flexible_dates: false)
    create(
      :unit,
      with_students: false,
      task_count: 0,
      staff_count: 0,
      outcome_count: 0,
      active: active,
      allow_flexible_dates: allow_flexible_dates,
      start_date: @today - 30.days,
      end_date: @today + 90.days
    )
  end

  def create_task_definition(
    unit,
    name:,
    target_date: @today + 7.days,
    target_grade: 0,
    weighting: 1
  )
    create(
      :task_definition,
      unit: unit,
      name: name,
      start_date: @today - 7.days,
      target_date: target_date,
      due_date: @today + 60.days,
      target_grade: target_grade,
      weighting: weighting,
      outcome_count: 0
    )
  end

  def create_grade_due_date(task_definition, target_grade:, target_due_date:)
    create(
      :task_definition_grade_due_date,
      task_definition: task_definition,
      target_grade: target_grade,
      target_due_date: target_due_date,
      start_date: task_definition.start_date
    )
  end

  def create_prerequisite(task_definition, prerequisite, required_status:)
    TaskPrerequisite.create!(
      task_definition: task_definition,
      prerequisite: prerequisite,
      task_status_id: required_status.id
    )
  end

  def score_for(recommendations, task_definition)
    recommendations.find do |recommendation|
      recommendation['task_definition_id'] == task_definition.id
    end.fetch('priority_score')
  end

  def enrol_student(unit, student, target_grade:)
    project = unit.enrol_student(student, unit.tutorials.first&.campus)
    project.update!(target_grade: target_grade)
    project
  end
end

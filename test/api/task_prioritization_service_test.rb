require 'test_helper'

class TaskPrioritizationServiceTest < ActiveSupport::TestCase
  setup do
    @user = FactoryBot.create(:user, :student)
    @unit = FactoryBot.create(:unit, active: true)
    @project = FactoryBot.create(
      :project,
      user: @user,
      unit: @unit,
      enrolled: true,
      target_grade: 2 # Distinction
    )
  end

  # ---------------------------------------------------------------------------
  # deadline_score_for
  # ---------------------------------------------------------------------------

  test 'deadline_score returns 100 when due tomorrow' do
    task = build_task_with_due_date(Time.zone.today + 1.day)
    service = TaskPrioritizationService.new(@user)
    assert_equal 100, service.deadline_score_for(task)
  end

  test 'deadline_score returns 80 when due in 3 days' do
    task = build_task_with_due_date(Time.zone.today + 3.days)
    service = TaskPrioritizationService.new(@user)
    assert_equal 80, service.deadline_score_for(task)
  end

  test 'deadline_score returns 60 when due in a week' do
    task = build_task_with_due_date(Time.zone.today + 7.days)
    service = TaskPrioritizationService.new(@user)
    assert_equal 60, service.deadline_score_for(task)
  end

  test 'deadline_score returns 40 when due in 2 weeks' do
    task = build_task_with_due_date(Time.zone.today + 14.days)
    service = TaskPrioritizationService.new(@user)
    assert_equal 40, service.deadline_score_for(task)
  end

  test 'deadline_score returns 20 when far in the future' do
    task = build_task_with_due_date(Time.zone.today + 90.days)
    service = TaskPrioritizationService.new(@user)
    assert_equal 20, service.deadline_score_for(task)
  end

  test 'deadline_score returns 0 when due_date is nil' do
    task = build_task_with_due_date(nil)
    service = TaskPrioritizationService.new(@user)
    assert_equal 0, service.deadline_score_for(task)
  end

  test 'deadline_score returns 100 for an overdue task' do
    task = build_task_with_due_date(Time.zone.today - 5.days)
    service = TaskPrioritizationService.new(@user)
    assert_equal 100, service.deadline_score_for(task)
  end

  # ---------------------------------------------------------------------------
  # effort_score_for
  # ---------------------------------------------------------------------------

  test 'effort_score buckets weighting correctly' do
    service = TaskPrioritizationService.new(@user)

    assert_equal 30, service.effort_score_for(build_task_with_weighting(5))
    assert_equal 30, service.effort_score_for(build_task_with_weighting(10))
    assert_equal 50, service.effort_score_for(build_task_with_weighting(20))
    assert_equal 70, service.effort_score_for(build_task_with_weighting(40))
    assert_equal 90, service.effort_score_for(build_task_with_weighting(60))
  end

  test 'effort_score handles nil weighting as zero' do
    service = TaskPrioritizationService.new(@user)
    assert_equal 30, service.effort_score_for(build_task_with_weighting(nil))
  end

  # ---------------------------------------------------------------------------
  # call — integration
  # ---------------------------------------------------------------------------

  test 'returns empty array when user has no tasks' do
    assert_equal [], TaskPrioritizationService.new(@user).call
  end

  test 'returns tasks sorted by descending priority_score' do
    create_task(@project, weighting: 5,  due_in_days: 30) # low effort, far deadline
    create_task(@project, weighting: 50, due_in_days: 1)  # high effort, urgent

    results = TaskPrioritizationService.new(@user).call

    assert_equal 2, results.length
    assert results.first[:priority_score] >= results.last[:priority_score]
  end

  test 'excludes tasks belonging to other students' do
    create_task(@project, weighting: 10, due_in_days: 5)

    other_user = FactoryBot.create(:user, :student)
    other_project = FactoryBot.create(:project, user: other_user, unit: @unit, enrolled: true)
    create_task(other_project, weighting: 10, due_in_days: 5)

    results = TaskPrioritizationService.new(@user).call
    assert_equal 1, results.length
  end

  test 'excludes tasks from inactive units' do
    inactive_unit = FactoryBot.create(:unit, active: false)
    inactive_project = FactoryBot.create(
      :project, user: @user, unit: inactive_unit, enrolled: true
    )
    create_task(inactive_project, weighting: 10, due_in_days: 5)

    assert_equal [], TaskPrioritizationService.new(@user).call
  end

  test 'excludes tasks from unenrolled projects' do
    unenrolled_project = FactoryBot.create(
      :project, user: @user, unit: @unit, enrolled: false
    )
    create_task(unenrolled_project, weighting: 10, due_in_days: 5)

    assert_equal [], TaskPrioritizationService.new(@user).call
  end

  test 'excludes completed and staff-assessed tasks' do
    create_task(@project, weighting: 10, due_in_days: 5,
                          status_name: 'complete')
    create_task(@project, weighting: 10, due_in_days: 5,
                          status_name: 'discuss')
    create_task(@project, weighting: 10, due_in_days: 5,
                          status_name: 'demonstrate')
    actionable = create_task(@project, weighting: 10, due_in_days: 5,
                                       status_name: 'fix_and_resubmit')

    results = TaskPrioritizationService.new(@user).call
    assert_equal 1, results.length
    assert_equal actionable.id, results.first[:task_id]
  end

  test 'response shape includes all expected keys' do
    create_task(@project, weighting: 10, due_in_days: 5)
    result = TaskPrioritizationService.new(@user).call.first

    %i[task_id task_name unit_id project_id deadline_score
       effort_score workload_score priority_score].each do |key|
      assert result.key?(key), "missing key #{key}"
    end
  end

  test 'workload score reflects task pressure and target grade' do
    # 5 tasks => medium pressure (60), HD target_grade => 90
    # workload = 0.6*60 + 0.4*90 = 36 + 36 = 72
    @project.update!(target_grade: 3)
    5.times { create_task(@project, weighting: 10, due_in_days: 10) }

    results = TaskPrioritizationService.new(@user).call
    assert_equal 72, results.first[:workload_score]
  end

  # ---------------------------------------------------------------------------
  # helpers
  # ---------------------------------------------------------------------------

  private

  def build_task_with_due_date(due_date)
    task_definition = FactoryBot.build(:task_definition, due_date: due_date, weighting: 10)
    FactoryBot.build(:task, project: @project, task_definition: task_definition)
  end

  def build_task_with_weighting(weighting)
    task_definition = FactoryBot.build(:task_definition,
                                       weighting: weighting,
                                       due_date: Time.zone.today + 5.days)
    FactoryBot.build(:task, project: @project, task_definition: task_definition)
  end

  def create_task(project, weighting:, due_in_days:, status_name: 'not_started')
    task_definition = FactoryBot.create(
      :task_definition,
      unit: project.unit,
      weighting: weighting,
      due_date: Time.zone.today + due_in_days.days
    )
    status = TaskStatus.find_by(name: status_name) || TaskStatus.first
    FactoryBot.create(
      :task,
      project: project,
      task_definition: task_definition,
      task_status: status
    )
  end
end

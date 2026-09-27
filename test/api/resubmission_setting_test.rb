require 'test_helper'

class ResubmissionSettingTest < ActiveSupport::TestCase
  include Rack::Test::Methods
  include TestHelpers::AuthHelper
  include TestHelpers::JsonHelper

  def app
    Rails.application
  end

  setup do
    @unit = FactoryBot.create(:unit, student_count: 1, task_count: 1, staff_count: 2)
    @definition = @unit.task_definitions.first
    @endpoint = "/api/units/#{@unit.id}/task_definitions/#{@definition.id}"
  end

  test 'convenor can disable and reenable one task with server controlled change attribution' do
    add_auth_header_for(user: @unit.main_convenor_user)
    put_json @endpoint, { task_def: { resubmission_extensions_enabled: false,
                                    resubmission_extensions_changed_by_id: @unit.active_projects.first.student.id } }
    assert_equal 200, last_response.status, last_response.body
    assert_not @definition.reload.resubmission_extensions_enabled
    assert_equal false, last_response_body['resubmission_extensions_enabled']
    assert_equal @unit.main_convenor_user.id, @definition.resubmission_extensions_changed_by_id
    assert_not_nil @definition.resubmission_extensions_changed_at
    original_time = @definition.resubmission_extensions_changed_at
    put_json @endpoint, { task_def: { resubmission_extensions_enabled: false } }
    assert_equal original_time, @definition.reload.resubmission_extensions_changed_at
    put_json @endpoint, { task_def: { resubmission_extensions_enabled: true } }
    assert_equal 200, last_response.status
    assert @definition.reload.resubmission_extensions_enabled
  end

  test 'student tutor and unrelated convenor cannot change the setting' do
    tutor = FactoryBot.create(:user, :tutor)
    FactoryBot.create(:unit_role, unit: @unit, user: tutor, role: Role.tutor)
    outsider = FactoryBot.create(:unit, student_count: 0, task_count: 0).main_convenor_user
    [@unit.active_projects.first.student, tutor, outsider].each do |user|
      add_auth_header_for(user: user)
      put_json @endpoint, { task_def: { resubmission_extensions_enabled: false } }
      assert_equal 403, last_response.status, "Unexpected result for #{user.id}: #{last_response.body}"
      assert @definition.reload.resubmission_extensions_enabled
      assert_nil @definition.resubmission_extensions_changed_by_id
    end
  end

  test 'project load and task refresh expose the same canonical deadline metadata' do
    @unit.update!(allow_flexible_dates: false, extension_weeks_on_resubmit_request: 1)
    @definition.update!(start_date: Time.current - 2.weeks, target_date: Time.current - 2.days,
                        due_date: Time.current + 4.weeks, target_grade: 0)
    project = @unit.active_projects.first
    task = project.task_for_task_definition(@definition)
    task.assess(TaskStatus.fix_and_resubmit, @unit.main_convenor_user)
    task.reload
    add_auth_header_for(user: project.student)

    get "/api/projects/#{project.id}"
    assert_equal 200, last_response.status, last_response.body
    row = last_response_body.fetch('tasks').find { |item| item['id'] == task.id }
    assert_equal task.effective_deadline_date.iso8601, row['effective_deadline_date']
    assert_equal 'post_feedback_extension', row['effective_deadline_reason']
    assert_equal task.resubmission_extension_comment.id, row['effective_deadline_source_id']

    get "/api/projects/#{project.id}/refresh_tasks/#{@definition.id}"
    assert_equal 200, last_response.status, last_response.body
    assert_equal row['effective_deadline_date'], last_response_body['effective_deadline_date']
    assert_equal row['effective_deadline_reason'], last_response_body['effective_deadline_reason']
    assert_equal row['effective_deadline_source_id'], last_response_body['effective_deadline_source_id']
  end

end

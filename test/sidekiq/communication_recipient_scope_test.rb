require 'test_helper'

class CommunicationRecipientScopeTest < ActiveSupport::TestCase
  setup do
    @unit = FactoryBot.create(:unit, with_students: false, task_count: 0,
                             stream_count: 0, tutorials: 0, outcome_count: 0, staff_count: 0)
    @convenor = @unit.main_convenor_user
    @tutor_role = @unit.employ_staff(FactoryBot.create(:user, :tutor), Role.tutor)
    @project = @unit.enrol_student(FactoryBot.create(:user, :student), Campus.first)
    @job = ExecuteCommunicationSetJob.new
  end

  def test_convenor_only_actions_do_not_include_unit_tutors
    action = Struct.new(:email_tutors, :email_convenors).new(false, true)
    recipients = @job.send(:staff_recipients_for, @project, @unit, action)

    assert_equal [@convenor.id], recipients.map(&:id)
    assert_not_includes recipients, @tutor_role.user
  end

  def test_action_log_csv_is_delivered_only_to_convenors
    set = @unit.communication_sets.create!(name: 'Recipient privacy', active: true)
    rule = set.communication_rules.create!(name: 'Private log', operator: 'and', position: 0)
    ActionMailer::Base.deliveries.clear

    result = @job.send(:send_action_log_to_convenors, [@project], @unit, rule, [])

    assert_equal [@convenor.email], result.map { |row| row[:recipient_email] }
    assert_equal [[@convenor.email]], ActionMailer::Base.deliveries.map(&:to)
    assert_equal 1, ActionMailer::Base.deliveries.first.attachments.length
  end

  def test_explicit_tutor_actions_still_include_the_assigned_tutor
    tutorial = FactoryBot.create(:tutorial, unit: @unit, campus: @project.campus, unit_role: @tutor_role)
    @project.enrol_in(tutorial)
    @unit.employ_staff(FactoryBot.create(:user, :tutor), Role.tutor)
    action = Struct.new(:email_tutors, :email_convenors).new(true, true)

    recipients = @job.send(:staff_recipients_for, @project, @unit, action)

    assert_equal [@convenor.id, @tutor_role.user_id].sort, recipients.map(&:id).sort
  end
end

require 'test_helper'

class TutorNoteMailerTest < ActionMailer::TestCase
  # BGW-21: a tutor note can refer to a task that is absent from the filtered
  # marking inbox. Send staff through the unfiltered task explorer instead of
  # the student dashboard or a filtered inbox route that cannot select it.
  def test_notify_tutor_note_links_to_task_explorer_when_task_is_not_in_inbox
    unit = FactoryBot.create :unit
    convenor = FactoryBot.create :user, :convenor

    ur = unit.employ_staff convenor, Role.convenor
    unit.update main_convenor: ur

    tutor = FactoryBot.create :user, :tutor
    tutor_role = unit.employ_staff tutor, Role.tutor

    project = unit.active_projects.first
    task = project.task_for_task_definition(unit.task_definitions.first)
    task.task_definition.update!(abbreviation: 'Portfolio Reflection')
    task.update!(task_status: TaskStatus.not_started)

    assert_not_includes unit.tasks_for_task_inbox(convenor).map(&:task_id), task.id,
                        'regression setup requires a task that the marking inbox filters out'

    tutor_note = TutorNote.create!(
      unit_role: tutor_role,
      user: tutor,
      task: task,
      note: 'Please take a look at this submission.',
      read_by_unit_role: false
    )

    mail = TutorNoteMailer.notify_tutor_note(tutor_note, convenor)

    host = Doubtfire::Application.config.institution[:host]
    expected = "#{host}/units/#{unit.id}/tasks/definition/#{project.user.id}/Portfolio%20Reflection"

    assert mail.html_part.body.to_s.include?(expected), 'html link should point at the task explorer'
    assert mail.text_part.body.to_s.include?(expected), 'text link should point at the task explorer'
    assert_not mail.html_part.body.to_s.include?('/tasks/inbox/'), 'the filtered inbox route should be gone'
    assert_not mail.html_part.body.to_s.include?('?tutor=true'), "the dead tutor flag should be gone"

    unit.destroy!
  end
end

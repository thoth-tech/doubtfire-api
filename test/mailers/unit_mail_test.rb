require 'test_helper'
require 'grade_helper'

class UnitMailTest < ActionMailer::TestCase
  def test_send_summary_email
    unit = FactoryBot.create :unit

    summary_stats = {}

    summary_stats[:week_end] = Time.zone.now
    summary_stats[:week_start] = summary_stats[:week_end] - 7.days
    summary_stats[:weeks_comments] = TaskComment.where("created_at >= :start AND created_at < :end", start: summary_stats[:week_start], end: summary_stats[:week_end]).count
    summary_stats[:weeks_engagements] = TaskEngagement.where("engagement_time >= :start AND engagement_time < :end", start: summary_stats[:week_start], end: summary_stats[:week_end]).count

    unit.send_weekly_status_emails(summary_stats)

    assert_equal unit.active_projects.count + unit.staff.count, ActionMailer::Base.deliveries.count
    unit.destroy!
  end

  def test_send_portfolio_ready_from_main_convenor
    unit = FactoryBot.create :unit
    convenor = FactoryBot.create :user, :convenor

    ur = unit.employ_staff convenor, Role.convenor

    unit.update main_convenor: ur

    project = unit.active_projects.first

    mail = PortfolioEvidenceMailer.portfolio_ready(project)

    assert_equal 1, mail.from.count
    assert_equal convenor.email, mail.from.first
    assert mail.html_part.body.include? "#{Doubtfire::Application.config.institution[:host]}/projects/#{project.id}/portfolio"
    # The text-only part must carry the same deep link so plain-text recipients
    # have something to act on (BGW-29).
    assert mail.text_part.body.include?("projects/#{project.id}/portfolio"), mail.text_part.body.to_s
    unit.destroy!
  end

  def test_send_portfolio_fail_from_main_convenor
    unit = FactoryBot.create :unit
    convenor = FactoryBot.create :user, :convenor

    ur = unit.employ_staff convenor, Role.convenor

    unit.update main_convenor: ur

    project = unit.active_projects.first

    mail = PortfolioEvidenceMailer.portfolio_failed(project)

    assert_equal 1, mail.from.count
    assert_equal convenor.email, mail.from.first
    assert mail.html_part.body.include? "#{Doubtfire::Application.config.institution[:host]}/projects/#{project.id}/portfolio"
    assert mail.text_part.body.include?("projects/#{project.id}/portfolio"), mail.text_part.body.to_s
    unit.destroy!
  end

  def test_send_overseer_assessment_failed_email
    unit = FactoryBot.create :unit
    convenor = FactoryBot.create :user, :convenor

    ur = unit.employ_staff convenor, Role.convenor

    unit.update main_convenor: ur

    project = unit.active_projects.first
    task = project.task_for_task_definition(unit.task_definitions.first)
    task.task_definition.update!(abbreviation: 'Portfolio Reflection')

    mail = PortfolioEvidenceMailer.overseer_assessment_failed(project, [task])

    assert_equal 1, mail.from.count
    assert_equal convenor.email, mail.from.first
    assert_equal project.student.email, mail.to.first
    assert mail.html_part.body.include? "#{Doubtfire::Application.config.institution[:host]}/projects/#{project.id}/dashboard/Portfolio%20Reflection"
    assert mail.text_part.body.include?("projects/#{project.id}/dashboard/Portfolio%20Reflection"), mail.text_part.body.to_s
  end

  def test_send_task_pdf_failed_email_carries_a_deep_link
    unit = FactoryBot.create :unit
    convenor = FactoryBot.create :user, :convenor
    ur = unit.employ_staff convenor, Role.convenor
    unit.update main_convenor: ur

    project = unit.active_projects.first
    task = project.task_for_task_definition(unit.task_definitions.first)
    task.task_definition.update!(abbreviation: 'Portfolio Reflection')

    mail = PortfolioEvidenceMailer.task_pdf_failed(project, [task])

    host = Doubtfire::Application.config.institution[:host]
    link = "#{host}/projects/#{project.id}/dashboard/Portfolio%20Reflection"
    assert mail.html_part.body.include?(link), mail.html_part.body.to_s
    assert mail.text_part.body.include?("projects/#{project.id}/dashboard/Portfolio%20Reflection"), mail.text_part.body.to_s
    unit.destroy!
  end

  def test_send_task_pdf_ready_email_carries_a_deep_link
    unit = FactoryBot.create :unit
    convenor = FactoryBot.create :user, :convenor
    ur = unit.employ_staff convenor, Role.convenor
    unit.update main_convenor: ur

    project = unit.active_projects.first
    task = project.task_for_task_definition(unit.task_definitions.first)
    task.task_definition.update!(abbreviation: 'Portfolio Reflection')

    mail = PortfolioEvidenceMailer.task_pdf_ready_message(project, [task])

    host = Doubtfire::Application.config.institution[:host]
    link = "#{host}/projects/#{project.id}/dashboard/Portfolio%20Reflection"
    assert mail.html_part.body.include?(link), mail.html_part.body.to_s
    assert mail.text_part.body.include?("projects/#{project.id}/dashboard/Portfolio%20Reflection"), mail.text_part.body.to_s
    unit.destroy!
  end

  def test_send_task_feedback_ready_email_carries_a_deep_link
    unit = FactoryBot.create :unit
    convenor = FactoryBot.create :user, :convenor
    ur = unit.employ_staff convenor, Role.convenor
    unit.update main_convenor: ur

    project = unit.active_projects.first
    task = project.task_for_task_definition(unit.task_definitions.first)
    task.task_definition.update!(abbreviation: 'Portfolio Reflection')

    mail = PortfolioEvidenceMailer.task_feedback_ready(project, [task])

    host = Doubtfire::Application.config.institution[:host]
    link = "#{host}/projects/#{project.id}/dashboard/Portfolio%20Reflection"
    assert mail.html_part.body.include?(link), mail.html_part.body.to_s
    assert mail.text_part.body.include?("projects/#{project.id}/dashboard/Portfolio%20Reflection"), mail.text_part.body.to_s
    unit.destroy!
  end

end

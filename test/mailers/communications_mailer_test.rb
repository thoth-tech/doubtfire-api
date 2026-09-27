require 'test_helper'

class CommunicationsMailerTest < ActionMailer::TestCase
  # Regression for the nested-ERB-comment leak: the text part used
  # `<%# Hi <%= ... %> %>`, and because an ERB comment ends at the first `%>`
  # the trailing ` %>` printed literally in every email. Assert the rendered
  # text part carries no raw ERB delimiter and the greeting and sign-off render.
  def test_text_part_renders_without_leaking_erb
    unit = FactoryBot.create :unit
    recipient = FactoryBot.create :user
    sender = FactoryBot.create :user, :convenor

    mail = CommunicationsMailer.communication_email(
      to: recipient.email,
      from: sender.email,
      subject: 'Weekly update',
      body: "First paragraph.\nSecond paragraph.",
      recipient: recipient,
      sender: sender,
      unit: unit,
      rule: nil
    )

    text = mail.text_part.body.to_s

    assert_not_includes text, '%>', "text part leaked a raw ERB delimiter:\n#{text}"
    assert_not_includes text, '<%', "text part leaked a raw ERB delimiter:\n#{text}"
    assert_includes text, "Hi #{recipient.first_name},"
    assert_includes text, 'First paragraph.'
    assert_includes text, 'Cheers,'
    assert_includes text, "on behalf of #{sender.name}"
  ensure
    unit&.destroy!
  end

  def test_communication_email_has_greeting_sign_off_and_unsubscribe
    recipient = FactoryBot.create :user, :student
    sender = FactoryBot.create :user, :convenor

    mail = CommunicationsMailer.communication_email(
      to: recipient.email,
      from: sender.email,
      subject: 'A message from your convenor',
      body: "First paragraph.\nSecond paragraph.",
      recipient: recipient,
      sender: sender,
      unit: nil,
      rule: nil
    )

    html = mail.html_part.body.to_s
    expected_name = recipient.nickname.presence || recipient.first_name

    assert_includes html, "Hi #{ERB::Util.html_escape(expected_name)},"
    assert_includes html, "on behalf of #{ERB::Util.html_escape(sender.name)}"
    assert_includes html, 'Unsubscribe'
    assert_includes html, 'First paragraph.'
    assert_includes html, 'Second paragraph.'
  end

  def test_communication_email_html_escapes_apostrophes_in_names
    recipient = FactoryBot.create :user, :student, first_name: "Sha'Carri", nickname: nil
    sender = FactoryBot.create :user, :convenor, first_name: 'Antonio', last_name: "D'Amore"

    mail = CommunicationsMailer.communication_email(
      to: recipient.email,
      from: sender.email,
      subject: 'A message from your convenor',
      body: 'A message.',
      recipient: recipient,
      sender: sender,
      unit: nil,
      rule: nil
    )

    html = mail.html_part.body.to_s

    assert_includes html, 'Hi Sha&#39;Carri,'
    assert_includes html, 'on behalf of Antonio D&#39;Amore'
  end
end

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
end

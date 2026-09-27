require 'test_helper'

class AdditionalNotificationEmailTest < ActiveSupport::TestCase
  setup do
    @user = FactoryBot.create(:user, email: 'primary@example.edu')
  end

  def test_normalises_the_address_and_never_stores_a_verification_token
    record = AdditionalNotificationEmailService.request(
      user: @user,
      email: '  SECONDARY@Example.ORG '
    )

    assert_equal 'secondary@example.org', record.email
    assert_not record.verified?
    assert_not record.attributes.key?('verification_token')
    assert_not record.attributes.key?('verification_token_digest')
    assert_equal [record.id, record.verification_version],
                 AdditionalNotificationEmailVerificationJob.jobs.last['args']
  end

  def test_primary_address_cannot_be_reused_case_insensitively
    error = assert_raises(ActiveRecord::RecordInvalid) do
      AdditionalNotificationEmailService.request(
        user: @user,
        email: 'PRIMARY@example.edu'
      )
    end

    assert_includes error.message, 'must be different from the institutional email'
  end

  def test_verification_is_required_and_a_link_cannot_be_replayed
    record = AdditionalNotificationEmailService.request(
      user: @user,
      email: 'secondary@example.org'
    )
    token = record.verification_token

    verified = AdditionalNotificationEmailService.verify(token: token)

    assert verified.reload.verified?
    assert_raises(AdditionalNotificationEmailService::AlreadyVerified) do
      AdditionalNotificationEmailService.verify(token: token)
    end
  end

  def test_expired_token_is_rejected
    record = AdditionalNotificationEmailService.request(
      user: @user,
      email: 'secondary@example.org'
    )
    token = record.verification_token
    # Deliberately bypass the model to exercise a token that expired after issue.
    record.update_column(:verification_expires_at, 1.minute.ago) # rubocop:disable Rails/SkipsModelValidations

    assert_raises(AdditionalNotificationEmailService::InvalidToken) do
      AdditionalNotificationEmailService.verify(token: token)
    end
  end

  def test_replacement_invalidates_the_previous_link
    first = AdditionalNotificationEmailService.request(
      user: @user,
      email: 'first@example.org'
    )
    old_token = first.verification_token

    replacement = AdditionalNotificationEmailService.request(
      user: @user,
      email: 'replacement@example.org'
    )

    assert_equal first.id, replacement.id
    assert_equal 'replacement@example.org', replacement.email
    assert_nil AdditionalNotificationEmail.record_for_token(old_token)
    assert_equal 1,
                 @user.additional_notification_email_audits.where(event: 'address_replaced').count
  end

  def test_resend_invalidates_the_previous_link_and_is_rate_limited
    record = AdditionalNotificationEmailService.request(
      user: @user,
      email: 'secondary@example.org'
    )
    old_token = record.verification_token

    AdditionalNotificationEmailService.resend(user: @user)
    AdditionalNotificationEmailService.resend(user: @user)

    assert_nil AdditionalNotificationEmail.record_for_token(old_token)
    assert_raises(AdditionalNotificationEmailService::RateLimited) do
      AdditionalNotificationEmailService.resend(user: @user)
    end
    assert_equal 3,
                 @user.additional_notification_email_audits.where(event: 'verification_requested').count
  end

  def test_verification_locks_the_user_before_touching_the_address
    record = AdditionalNotificationEmailService.request(
      user: @user,
      email: 'secondary@example.org'
    )
    token = record.verification_token
    locks = []
    user = record.user
    user.define_singleton_method(:with_lock) do |*args, &block|
      locks << :user
      super(*args, &block)
    end
    record.define_singleton_method(:with_lock) do |*args, &block|
      locks << :address
      super(*args, &block)
    end

    AdditionalNotificationEmail.stub(:record_for_token, ->(_token) { locks.include?(:user) ? record.reload : record }) do
      AdditionalNotificationEmailService.verify(token: token)
    end

    # request, resend and remove lock the user first. The same order here
    # cannot deadlock against them.
    assert_equal [:user], locks
    assert record.reload.verified?
  end

  def test_removal_stops_future_use_and_keeps_a_token_free_audit
    record = AdditionalNotificationEmailService.request(
      user: @user,
      email: 'secondary@example.org'
    )
    token = record.verification_token

    assert AdditionalNotificationEmailService.remove(user: @user)
    assert_nil @user.reload.additional_notification_email
    assert_nil AdditionalNotificationEmail.record_for_token(token)

    audit = @user.additional_notification_email_audits.find_by!(event: 'removed')
    assert_equal %w[id user_id event created_at updated_at].sort, audit.attributes.keys.sort
  end
end

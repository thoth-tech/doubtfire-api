require 'test_helper'
require 'minitest/mock'

class AuthorisationHelpersTest < ActiveSupport::TestCase
  # Capture Rails.logger.warn for the duration of the block, tolerating any
  # arity so an unrelated warn elsewhere does not blow up the test.
  def capture_warnings(&block)
    warnings = []
    Rails.logger.stub(:warn, ->(*args, &warn_block) { warnings << (args.first || warn_block&.call) }) do
      block.call
    end
    warnings
  end

  def test_denial_when_user_has_no_role_is_logged
    unit = FactoryBot.create(:unit)
    outsider = FactoryBot.create(:user, :student)

    warnings = capture_warnings do
      assert_not AuthorisationHelpers.authorise?(outsider, unit, :get)
    end

    assert warnings.any? { |m| m.to_s.include?('authorisation denied') && m.to_s.include?('get') },
           "expected a denial warning, got: #{warnings.inspect}"
  end

  def employed_convenor(unit)
    convenor = FactoryBot.create :user, :convenor
    unit.employ_staff(convenor, Role.convenor)
    convenor
  end

  def test_denial_when_action_is_absent_from_the_permission_hash_is_logged
    unit = FactoryBot.create(:unit)
    convenor = employed_convenor(unit)
    perms = ->(_role, _hash, _other) { [:some_allowed_action] }

    warnings = capture_warnings do
      assert_not AuthorisationHelpers.authorise?(convenor, unit, :a_denied_action, perms)
    end

    assert warnings.any? { |m| m.to_s.include?('authorisation denied') && m.to_s.include?('a_denied_action') },
           "expected a denial warning, got: #{warnings.inspect}"
  end

  def test_granted_authorisation_logs_nothing
    unit = FactoryBot.create(:unit)
    convenor = employed_convenor(unit)
    perms = ->(_role, _hash, _other) { [:some_allowed_action] }

    warnings = capture_warnings do
      assert AuthorisationHelpers.authorise?(convenor, unit, :some_allowed_action, perms)
    end

    assert_not warnings.any? { |m| m.to_s.include?('authorisation denied') },
               "expected no denial warning, got: #{warnings.inspect}"
  end
end

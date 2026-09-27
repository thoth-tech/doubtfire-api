require 'test_helper'

# User#name is built from first_name/last_name, which are user-editable and
# validated for presence only. Interpolating it straight into
# %("#{name}" <#{email}>) let a name carrying a quote close the display name and
# add a second recipient, and a name carrying a newline fold an extra header
# into the message.
class AddressWithNameTest < ActiveSupport::TestCase
  class Probe < ApplicationMailer
    def check(user)
      address_with_name(user)
    end
  end

  Person = Struct.new(:name, :email)

  def addresses_in(value)
    Mail::AddressList.new(value).addresses
  end

  def assert_single_recipient(name)
    built = Probe.new.check(Person.new(name, 'ann@uni.test'))

    refute_match(/[\r\n]/, built, 'a display name must not be able to fold a header')
    parsed = addresses_in(built)
    assert_equal 1, parsed.size, "expected one recipient, got #{parsed.map(&:address).join(', ')}"
    assert_equal 'ann@uni.test', parsed.first.address
  end

  def test_a_quote_in_the_name_cannot_add_a_second_recipient
    assert_single_recipient('Ann " <evil@attacker.test>, "x')
  end

  def test_a_comma_in_the_name_cannot_add_a_second_recipient
    assert_single_recipient('Ann, evil@attacker.test')
  end

  def test_a_newline_in_the_name_cannot_fold_a_header
    assert_single_recipient("Ann\r\nBcc: evil@attacker.test")
    assert_single_recipient("Ann\nBcc: evil@attacker.test")
  end

  def test_an_ordinary_name_is_left_readable
    built = Probe.new.check(Person.new('Ann Example', 'ann@uni.test'))
    assert_equal 'Ann Example <ann@uni.test>', built
  end

  # The point of moving it to ApplicationMailer: every mailer that addresses a
  # person gets it, not just the one that had it.
  def test_every_mailer_can_reach_it
    [NotificationsMailer, PortfolioEvidenceMailer, TutorNoteMailer].each do |mailer|
      assert mailer.private_method_defined?(:address_with_name),
             "#{mailer} cannot reach address_with_name"
    end
  end
end

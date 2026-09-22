# frozen_string_literal: true

require 'test_helper'

class UnitCalendarTest < ActiveSupport::TestCase
  def test_date_for_week_and_day_keeps_earlier_weekday_in_the_requested_week
    unit = Unit.new(start_date: Time.zone.local(2026, 8, 7)) # Friday

    assert_equal Time.zone.local(2026, 8, 9), unit.date_for_week_and_day(1, 'Sun')
  end
end

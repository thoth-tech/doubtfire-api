# frozen_string_literal: true

require 'test_helper'

# Exercises the shared setup guard/assignment in test/test_helper.rb by evaluating the
# literal source lines under simulated empty-table conditions (Role/Unit stubbed to zero,
# or Unit.last/maximum stubbed to nil), without touching real fixture data. This keeps the
# tests tied to the actual lines shipped in test_helper.rb rather than a copy of them.
class TestHelperTest < ActiveSupport::TestCase
  def test_last_unit_id_capture_survives_an_empty_units_table
    assignment_line = test_helper_source_line('@last_unit_id =')
    assert(assignment_line, 'expected test_helper.rb to assign @last_unit_id in its setup block')

    Unit.stub(:last, nil) do
      Unit.stub(:maximum, nil) do
        assert_equal(0, eval(assignment_line)) # rubocop:disable Security/Eval
      end
    end
  end

  def test_setup_aborts_with_a_readable_message_when_the_database_is_unpopulated
    guard_line = test_helper_source_line('abort(')
    assert(guard_line, 'expected test_helper.rb to guard against an unpopulated test database')

    Role.stub(:count, 0) do
      Unit.stub(:count, 5) do
        _stdout, stderr = capture_io do
          assert_raises(SystemExit) { eval(guard_line) } # rubocop:disable Security/Eval
        end
        assert_includes stderr, 'rake test:setup'
      end
    end
  end

  def test_setup_does_not_abort_when_seed_data_is_present
    guard_line = test_helper_source_line('abort(')
    assert(guard_line, 'expected test_helper.rb to guard against an unpopulated test database')

    Role.stub(:count, 3) do
      Unit.stub(:count, 3) do
        assert_nil(eval(guard_line)) # rubocop:disable Security/Eval
      end
    end
  end

  private

  def test_helper_source_line(needle)
    File.readlines(Rails.root.join('test/test_helper.rb'))
        .find { |line| line.strip.start_with?(needle) }
        &.strip
  end
end

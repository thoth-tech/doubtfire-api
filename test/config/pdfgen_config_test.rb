require 'test_helper'

class PdfgenConfigTest < ActiveSupport::TestCase
  ENV_NAME = 'DF_MAX_PDF_GEN_PROCESSES'.freeze

  def teardown
    ENV.delete(ENV_NAME)
  end

  def parse(raw)
    if raw.nil?
      ENV.delete(ENV_NAME)
    else
      ENV[ENV_NAME] = raw
    end
    Doubtfire::Application.fetch_positive_integer_env(ENV_NAME, default: 2, max: 100)
  end

  def test_uses_the_default_when_unset
    assert_equal 2, parse(nil)
  end

  def test_parses_a_configured_value
    assert_equal 5, parse('5')
  end

  def test_result_is_an_integer_not_a_string
    # Regression: a String here made the generator compare Integer with String and raise.
    assert_kind_of Integer, parse('3')
  end

  def test_rejects_a_non_integer_value
    assert_raises(RuntimeError) { parse('three') }
  end

  def test_rejects_a_value_below_one
    assert_raises(RuntimeError) { parse('0') }
  end

  def test_rejects_a_value_above_the_maximum
    assert_raises(RuntimeError) { parse('101') }
  end
end

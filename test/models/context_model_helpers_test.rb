require 'test_helper'

class ContextModelHelpersTest < ActiveSupport::TestCase
  include ContextModelHelpers

  def test_context_models_are_explicitly_allowlisted
    assert_equal Unit, send(:context_class_for, 'units')
    assert_equal TaskDefinition, send(:context_class_for, 'task_definitions')
  end

  def test_arbitrary_constants_cannot_be_selected
    assert_raises(KeyError) do
      send(:context_class_for, 'Kernel')
    end
  end
end

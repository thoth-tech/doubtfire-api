require 'test_helper'

#
# Tests for Criterion model objects - not accessed via API
#
class CriterionModelTest < ActiveSupport::TestCase

    setup do
        @stage = FactoryBot.create(:stage)
    end
    
    # Test you can create a valid criterion
    def test_valid_criterion_creation
        criterion = Criterion.create(stage: @stage, description: 'Criterion 1', order: 1)
    
        assert criterion.valid?
        assert criterion.stage == @stage
        assert criterion.description == 'Criterion 1'
        assert criterion.order == 1
    end
    
    # Test you cannot create an invalid criterion
    def test_criterion_order_and_description_are_required
        criterion = Criterion.create(stage: @stage)
    
        refute criterion.valid? # "refute": fail if true, pass if false
        # Validator is included in criterion model at doubtfire-api/app/models/feedback/criterion.rb
        criterion.description = 'Criterion 1'
        refute criterion.valid? # still should not be valid until order is added
        criterion.order = 1
        assert criterion.valid?
        criterion.description = nil
        refute criterion.valid?
        criterion.description = 'Criterion'
        criterion.order = nil
        refute criterion.valid?
    
        refute criterion.save # fail if criterion is saved
    end
end
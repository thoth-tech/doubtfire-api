require 'test_helper'
require 'json'

class CriterionApiTest < ActiveSupport::TestCase
    include Rack::Test::Methods
    include TestHelpers::AuthHelper
    include TestHelpers::JsonHelper

    def app
        Rails.application
    end

    setup do
        @unit = FactoryBot.create(:unit)
        @stage = FactoryBot.create(:stage, unit: @unit)

        @data_to_post = {
            description: 'Criterion 1',
            order: '1',
            stage_id: @stage.id
        }
    end

    # Test that the main convenor of the unit can POST a criterion
    def test_create_criterion_via_post

        user = @unit.main_convenor_user
        add_auth_header_for(user: user)

        criterion_count = Criterion.count

        post_json '/api/criteria', @data_to_post
        assert_equal 201, last_response.status, last_response.body

        criterion = Criterion.last

        assert_equal @data_to_post[:description], criterion.description
        assert_equal @data_to_post[:order].to_i, criterion.order
        assert_equal @data_to_post[:stage_id], criterion.stage_id
        assert_equal criterion_count + 1, Criterion.count
    end

    # Test that a student of the unit cannot POST a criterion
    def test_students_cannot_create_criteria

        user = @unit.students.first.user
        add_auth_header_for(user: user)

        criterion_count = Criterion.count

        post_json '/api/criteria', @data_to_post
        assert_equal 403, last_response.status, last_response.body
        assert_equal criterion_count, Criterion.count
    end
    
end
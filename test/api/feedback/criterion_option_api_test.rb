require 'test_helper'
require 'json'

class CriterionOptionApiTest < ActiveSupport::TestCase
    include Rack::Test::Methods
    include TestHelpers::AuthHelper
    include TestHelpers::JsonHelper

    def app
        Rails.application
    end

    setup do
        @unit = FactoryBot.create(:unit)
        @stage = FactoryBot.create(:stage, unit: @unit)
        @criterion = FactoryBot.create(:criterion, stage: @stage)
        @task_status = TaskStatus.create(name: 'Ready for Feedback', description: 'You are ready for a tutor to give feedback for this task', created_at: Time.now, updated_at: Time.now)
        @data_to_post = {
            criterion_id: @criterion.id,
            task_status_id: @task_status.id,
            outcome_status: 'fix_and_resubmit',
            resolved_message_text: 'This is the resolved message text',
            unresolved_message_text: 'This is the unresolved message text'
        }
    end

    # Test that the main convenor of the unit can POST a criterion option
    def test_create_criterion_option_via_post

        user = @unit.main_convenor_user
        add_auth_header_for(user: user)

        criterion_option_count = CriterionOption.count

        post_json '/api/criterion_options', @data_to_post
        assert_equal 201, last_response.status, last_response.body

        criterion_option = CriterionOption.last

        assert_equal @data_to_post[:outcome_status], criterion_option.outcome_status
        assert_equal @data_to_post[:resolved_message_text], criterion_option.resolved_message_text
        assert_equal @data_to_post[:unresolved_message_text], criterion_option.unresolved_message_text
        assert_equal criterion_option_count + 1, CriterionOption.count
    end

    # Test that a student of the unit cannot POST a criterion option
    def test_students_cannot_create_criterion_options

        user = @unit.students.first.user
        add_auth_header_for(user: user)

        criterion_option_count = CriterionOption.count

        post_json '/api/criterion_options', @data_to_post
        assert_equal 403, last_response.status, last_response.body
        
        assert_equal criterion_option_count, CriterionOption.count
    end
end
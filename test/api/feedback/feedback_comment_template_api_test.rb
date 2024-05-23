require 'test_helper'
require 'json'

class FeedbackCommentTemplateApiTest < ActiveSupport::TestCase
    include Rack::Test::Methods
    include TestHelpers::AuthHelper
    include TestHelpers::JsonHelper

    def app
        Rails.application
    end

    setup do
        @unit = FactoryBot.create(:unit)
        @stage = FactoryBot.create(:stage, unit: @unit)

        @criterion = Criterion.create(
            stage: @stage,
            order: 1,
            description: 'Some description'
          )
          
        @criterion_option = CriterionOption.create(
            criterion: @criterion,
            resolved_message_text: 'Resolved message',
            unresolved_message_text: 'Unresolved message',
            outcome_status: 'Some outcome status'
        ) 
    end

    # Test that the main convenor of the unit can POST a feedback comment template
    def test_create_feedback_comment_template_via_post
    
        user = @unit.main_convenor_user  # "main_convenor_user": a method in "Unit" model that returns the main convenor of the unit
        add_auth_header_for(user: user) # "add_auth_header_for": a method in "TestHelpers::AuthHelper" that adds username and auth_token to header

        data_to_post = { # request that will be sent to the server
            comment_text_situation: 'This is a comment',
            comment_text_next_action: 'This is another comment',
            criterion_option_id: @criterion_option.id,
            user_id: user.id
        }

        feedback_comment_template_count = FeedbackCommentTemplate.count # number of feedback comment templates in database

        post_json '/api/feedback_comment_templates', data_to_post 
        # "post_json" method: sends data to server
        # '/api/feedback_comment_templates': path to API
        # "data_to_post": data, stipulated above, that will be sent to server

        assert_equal 201, last_response.status, last_response.body
        # "assert_equal" method: actual value = expected value?
        # "last_response.status": HTTP status code of response = 201? Has request succeeded and resource been created?
        # "last_response.body": body of response (the data returned from server)

        feedback_comment_template = FeedbackCommentTemplate.last 
        # "FeedbackCommentTemplate": model in "app/models/feedback_comment_template.rb"
        
        assert_equal data_to_post[:comment_text_situation], feedback_comment_template.comment_text_situation
        assert_equal data_to_post[:comment_text_next_action], feedback_comment_template.comment_text_next_action
        assert_equal data_to_post[:user_id], feedback_comment_template.user_id
        # assert_equal data_to_post[:criterion_option_id], feedback_comment_template.criterion_option_id
        
        # "assert_equal" method: actual value = expected value?
        # "data_to_post[:comment_text_situation]": the comment text situation that is expected
        # "feedback_comment_template.< >": the < > returned from server

        assert_equal feedback_comment_template_count + 1, FeedbackCommentTemplate.count
    end

    # # Test that a student of the unit cannot POST a feedback comment template
    # def test_students_cannot_create_feedback_comment_templates
    #     unit = FactoryBot.create(:unit)
    #     stage = FactoryBot.create(:stage)
    #     criterion_option = FactoryBot.create(:criterion_option)

    #     data_to_post = {
    #         comment_text_situation: 'This is a comment',
    #         stage_id: stage.id,
    #         criterion_option_id: criterion_option.id
    #     }

    #     user = FactoryBot.create(:student)

    #     add_auth_header_for(user: user)

    #     post_json '/api/feedback_comment_templates', data_to_post

    #     assert_equal 403, last_response.status, last_response.body # 403 = forbidden

    #     unit.destroy
    # end
end

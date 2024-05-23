require 'test_helper'
require 'json'

class FeedbackCommentApiTest < ActiveSupport::TestCase
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
        @criterion_option = FactoryBot.create(:criterion_option, criterion: @criterion)
    end

    # Test that a main convenor of the unit can POST a feedback comment
    def test_create_feedback_comment_via_post

        user = @unit.main_convenor_user
        add_auth_header_for(user: user)

        feedback_comment_count = FeedbackComment.count

        data_to_post = {
            comment_text_situation: 'This is the situation',
            comment_text_next_action: 'This is the next action',
            criterion_option_id: @criterion_option.id,
            user_id: user.id
        }

        post_json '/api/feedback_comments', data_to_post
        assert_equal 201, last_response.status, last_response.body

        feedback_comment = FeedbackComment.last

        assert_equal data_to_post[:comment], feedback_comment.comment
        assert_equal data_to_post[:order].to_i, feedback_comment.order
        assert_equal feedback_comment_count + 1, FeedbackComment.count
    end

    # # Test that a student of the unit cannot POST a feedback comment
    # def test_students_cannot_create_feedback_comments

    #     user = FactoryBot.create(:user)

    #     feedback_comment_count = FeedbackComment.count

    #     add_auth_header_for(user: user)

    #     post_json '/api/feedback_comments', data_to_post

    #     assert_equal 403, last_response.status, last_response.body

    #     assert_equal feedback_comment_count, FeedbackComment.count
    # end
end
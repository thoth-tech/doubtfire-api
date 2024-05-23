require 'grape'

module FeedbackApi
  class FeedbackCommentTemplateApi < Grape::API
    desc 'Feedback comment templates are used to provide a list of comments that can be used to provide feedback on a task. This endpoint allows you to create a new feedback comment template.'
    params do
      requires :comment_text_situation, type: String, desc: 'What the comment is about. Could be what is wrong with or what is good about a student\'s submission.'
      requires :comment_text_next_action, type: String, desc: 'What the student should do next to improve their submission'
      optional :criterion_option_id, type: Integer, desc: 'The criterion option to which the comment template is associated'
    end
    post '/feedback_comment_templates' do # pathname of URL
      criterion_option = CriterionOption.find(params[:criterion_option_id])

      unless authorise? current_user, criterion_option.unit, :update
        error!({ error: 'Not authorised to create a feedback comment template for this unit' }, 403)
      end

      feedback_comment_template_parameters = ActionController::Parameters.new(params)
                                                                         .permit(:comment_text_situation, :comment_text_next_action)

      feedback_comment_template_parameters[:criterion_option] = criterion_option

      result = FeedbackCommentTemplate.create!(feedback_comment_template_parameters)

      present result, with: Entities::FeedbackEntities::FeedbackCommentTemplateEntity
      # presents JSON format of the newly posted FeedbackCommentTemplate object from the FeedbackCommentTemplateEntity
    end

    desc 'This endpoint allows you to get all the feedback comment templates for a given criterion_option.'
    params do
      requires :criterion_option_id, type: Integer, desc: 'The criterion option to which the comment template belongs'
    end
    get '/feedback_comment_templates' do
      criterion_option = CriterionOption.find(params[:criterion_option_id])

      unless authorise? current_user, criterion_option.unit, :read
        error!({ error: 'Not authorised to read feedback comment templates for this unit' }, 403)
      end

      present stage.feedback_comment_templates, with: Entities::FeedbackEntities::FeedbackCommentTemplateEntity
    end

    desc 'This endpoint allows you to update the comment text situation or comment text next action for a feedback comment template.'
    params do
      optional :comment_text_situation, type: String, desc: 'The new comment text situation for the feedback comment template'
      optional :comment_text_next_action, type: String, desc: 'The new comment text next action for the feedback comment template'
    end
    put '/feedback_comment_templates/:id' do
      feedback_comment_template = FeedbackCommentTemplate.find(params[:id])

      unless authorise? current_user, feedback_comment_template.unit, :update
        error!({ error: 'Not authorised to update feedback comment templates for this unit' }, 403)
      end

      feedback_comment_template_parameters = ActionController::Parameters.new(params)
                                                                         .permit(:comment_text_situation, :comment_text_next_action)

      feedback_comment_template.update!(feedback_comment_template_parameters)

      present feedback_comment_template, with: Entities::FeedbackEntities::FeedbackCommentTemplateEntity
    end

    desc 'This endpoint allows you to delete a feedback comment template.'
    delete '/feedback_comment_templates/:id' do
      feedback_comment_template = FeedbackCommentTemplate.find(params[:id])

      unless authorise? current_user, feedback_comment_template.unit, :update
        error!({ error: 'Not authorised to delete feedback comment templates for this unit' }, 403)
      end

      feedback_comment_template.destroy!
    end
  end
end

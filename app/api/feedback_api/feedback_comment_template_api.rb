require 'grape'

module FeedbackApi
  class FeedbackCommentTemplateApi < Grape::API
    desc 'Feedback comment templates are used to provide a list of comments that can be used to provide feedback on a task. This endpoint allows you to create a new feedback comment template.'
    params do
      requires :abbreviation,       type: String,   desc: 'A short abbreviation for the feedback comment template'
      requires :order,              type: Integer,  desc: 'The order in which to display the comment templates'
      requires :chip_text,          type: String,   desc: 'A short text displayed on the feedback UI'
      requires :description,        type: String,   desc: 'A detailed description of the feedback comment template'
      requires :comment_text,       type: String,   desc: 'The actual feedback comment text'
      requires :summary_text,       type: String,   desc: 'A short summary of the feedback comment'
      optional :task_status_id,     type: Integer,  desc: 'The task status associated with this feedback comment template'
      requires :feedback_group_id,  type: Integer,  desc: 'The feedback group to which the comment template belongs'
    end
    post '/feedback_comment_templates' do # pathname of URL
      feedback_group = FeedbackGroup.find(params[:feedback_group_id])

      unless authorise? current_user, feedback_group.unit, :update
        error!({ error: 'Not authorised to create a feedback comment template for this unit' }, 403)
      end

      feedback_comment_template_parameters = ActionController::Parameters.new(params)
                                                                         .permit(:abbreviation, :order, :chip_text, :description, :comment_text, :summary_text, :task_status_id)
      feedback_comment_template_parameters[:feedback_group] = feedback_group

      # If the task_status_id is provided, find the task status and add it to
      # the feedback_comment_template_parameters
      if params[:task_status_id]
        task_status = TaskStatus.find(params[:task_status_id])
        feedback_comment_template_parameters[:task_status] = task_status
      end

      result = FeedbackCommentTemplate.create!(feedback_comment_template_parameters)

      present result, with: Entities::FeedbackEntities::FeedbackCommentTemplateEntity
      # presents JSON format of the newly posted FeedbackCommentTemplate object from the FeedbackCommentTemplateEntity
    end

    desc 'This endpoint allows you to get all the feedback comment templates for a given feedback_group.'
    params do
      requires :feedback_group_id, type: Integer, desc: 'The feedback group to which the comment template belongs'
    end

    get '/feedback_comment_templates' do
      feedback_group = FeedbackGroup.find(params[:feedback_group_id])

      unless authorise? current_user, feedback_group.unit, :read
        error!({ error: 'Not authorised to read feedback comment templates for this unit' }, 403)
      end

      present stage.feedback_comment_templates, with: Entities::FeedbackEntities::FeedbackCommentTemplateEntity
    end

    desc 'This endpoint allows you to update a feedback comment template.'
    params do
      optional :abbreviation,     type: String,   desc: 'The new abbreviation for the feedback comment template'
      optional :order,            type: Integer,  desc: 'The new order value for the comment template'
      optional :chip_text,        type: String,   desc: 'The new chip text for the feedback comment template'
      optional :description,      type: String,   desc: 'The new description for the feedback comment template'
      optional :comment_text,     type: String,   desc: 'The new comment text for the feedback comment template'
      optional :summary_text,     type: String,   desc: 'The new summary text for the feedback comment template'
      optional :task_status_id,   type: Integer,  desc: 'The new task status associated with this feedback comment template'
    end
    put '/feedback_comment_templates/:id' do
      feedback_comment_template = FeedbackCommentTemplate.find(params[:id])

      unless authorise? current_user, feedback_comment_template.unit, :update
        error!({ error: 'Not authorised to update feedback comment templates for this unit' }, 403)
      end

      feedback_comment_template_parameters = ActionController::Parameters.new(params)
                                                                         .permit(:abbreviation, :order, :chip_text, :description, :comment_text, :summary_text, :task_status_id)

      if params[:task_status_id]
        task_status = TaskStatus.find(params[:task_status_id])
        feedback_comment_template_parameters[:task_status] = task_status
      end

      feedback_comment_template.update!(feedback_comment_template_parameters)

      present feedback_comment_template, with: Entities::FeedbackEntities::FeedbackCommentTemplateEntity
    end

    desc 'This endpoint allows you to delete a feedback comment template.'
    delete '/feedback_comment_templates/:id' do
      feedback_comment_template = FeedbackCommentTemplate.find(params[:id])

      unless authorise? current_user, feedback_comment_template.feedback_group.unit, :update
        error!({ error: 'Not authorised to delete feedback comment templates for this unit' }, 403)
      end

      feedback_comment_template.destroy!
    end
  end
end

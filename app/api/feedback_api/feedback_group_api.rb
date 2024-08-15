require 'grape'
require_relative '../../models/feedback/feedback_group'

module FeedbackApi
  class FeedbackGroupApi < Grape::API

    desc 'Feedback is grouped for tasks. This endpoint allows you to create a new feedback group for a given task definition.'
    params do
      requires :task_definition_id, type: Integer, desc: 'The task definition to which the feedback group belongs'
      requires :title, type: String,  desc: 'The title of the new feedback group'
      requires :order, type: Integer, desc: 'The order in which to display the feedback groups'
    end
    post '/feedback_groups' do
      task_definition = TaskDefinition.find(params[:task_definition_id])

      unless authorise? current_user, task_definition.unit, :update
        error!({ error: 'Not authorised to create a feedback group for this unit' }, 403)
      end

      feedback_group_parameters = ActionController::Parameters.new(params)
                                                              .permit(:title, :order) # only `:title` and `:order` fields of the feedback group model can be set directly from the user input.
      feedback_group_parameters[:task_definition] = task_definition

      result = FeedbackGroup.create!(feedback_group_parameters)

      present result, with: Entities::FeedbackEntities::FeedbackGroupEntity
    end

    desc 'This endpoint allows you to get all the feedback groups for a given task definition.'
    params do
      requires :task_definition_id, type: Integer, desc: 'The task definition to which the feedback group belongs'
    end
    get '/feedback_groups' do
      task_definition = TaskDefinition.find(params[:task_definition_id])

      unless authorise? current_user, task_definition.unit, :provide_feedback
        error!({ error: 'Not authorised to get feedback feedback_groups for this unit' }, 403)
      end

      present task_definition.feedback_groups, with: Entities::FeedbackEntities::FeedbackGroupEntity
    end

    desc 'This endpoint allows you to update the name and order of a feedback group.'
    params do
      optional :title, type: String,  desc: 'The new title for the feedback group'
      optional :order, type: Integer, desc: 'The order value for the feedback group'
    end
    put '/feedback_groups/:id' do
      # Get the feeedback group from the task definition
      feedback_group = FeedbackGroup.find(params[:id])

      unless authorise? current_user, feedback_group.unit, :update
        error!({ error: 'Not authorised to update feedback feedback_groups for this unit' }, 403)
      end

      feedback_group_parameters = ActionController::Parameters.new(params)
                                                              .permit(:title, :order)

      FeedbackGroup.update!(feedback_group_parameters)

      present FeedbackGroup, with: Entities::FeedbackEntities::FeedbackGroupEntity
    end

    desc 'This endpoint allows you to delete a feedback group.'
    delete '/feedback_groups/:id' do
      # Get the feedback group from the task definition
      feedback_group = FeedbackGroup.find(params[:id])

      unless authorise? current_user, feedback_group.unit, :update
        error!({ error: 'Not authorised to delete feedback feedback_groups for this unit' }, 403)
      end

      FeedbackGroup.destroy!
    end
  end
end

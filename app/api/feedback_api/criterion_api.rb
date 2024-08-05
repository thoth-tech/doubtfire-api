require 'grape'

module FeedbackApi
  class CriterionApi < Grape::API
    desc 'Stages are completed through criteria. This endpoint allows you to create a new criterion for a given stage.'
    params do
      requires :stage_id, type: Integer, desc: 'The stage to which the criterion belongs'
      requires :description, type: String,  desc: 'The description of the new criterion'
      requires :order, type: Integer, desc: 'The order in which to display the criteria'
      optional :help_text, type: String, desc: 'The context that a tutor may need to make sense of the criterion'
    end
    post '/criteria' do # POST to /api/feedback/criteria endpoint
      stage = Stage.find(params[:stage_id])

      unless authorise? current_user, stage.unit, :update
        error!({ error: 'Not authorised to create a criterion for this unit' }, 403)
      end

      criterion_parameters = ActionController::Parameters.new(params)
                                                         .permit(:description, :order) # "permit" method: only allow these parameters to be passed

      criterion_parameters[:stage] = stage # "criterion_parameters" hash: add the stage to the hash

      result = Criterion.create!(criterion_parameters) # "result" variable: create a new criterion with the parameters

      present result, with: Entities::FeedbackEntities::CriterionEntity # "present" method: present the result with the "CriterionEntity" entity (defined in "doubtfire-api/app/api/entities/feedback_entities/criterion_entity.rb")
    end

    desc 'This endpoint allows you to get all the criteria for a given stage.'
    params do
      requires :stage_id, type: Integer, desc: 'The stage to which the criterion belongs'
    end
    get '/criteria' do
      stage = Stage.find(params[:stage_id])

      unless authorise? current_user, stage.unit, :provide_feedback
        error!({ error: 'Not authorised to get feedback criteria for this unit' }, 403)
      end

      present stage.criteria, with: Entities::FeedbackEntities::CriterionEntity
    end

    desc 'This endpoint allows you to update the description and order of a criterion.'
    params do
      optional :description, type: String, desc: 'The new description for the criterion'
      optional :order, type: Integer, desc: 'The new order value for the criterion'
    end
    put '/criteria/:id' do
      # Get the criterion from the stage
      criterion = Criterion.find(params[:id])

      unless authorise? current_user, criterion.unit, :update
        error!({ error: 'Not authorised to update feedback criteria for this unit' }, 403)
      end

      criterion_params = ActionController::Parameters.new(params)
                                                     .permit(:description, :order)

      criterion.update!(criterion_params)

      present criterion, with: Entities::FeedbackEntities::CriterionEntity
    end

    desc 'This endpoint allows you to delete a criterion.'
    delete '/criteria/:id' do
      criterion = Criterion.find(params[:id])

      unless authorise? current_user, criterion.unit, :update
        error!({ error: 'Not authorised to delete feedback criteria for this unit' }, 403)
      end

      criterion.destroy!
    end
  end
end

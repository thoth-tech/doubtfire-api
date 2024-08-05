require 'grape'

module FeedbackApi
  class CriterionOptionApi < Grape::API
    desc 'Criteria have criterion options. This endpoint allows you to create a new criterion option for a given criterion.'
    params do
      requires :criterion_id, type: Integer, desc: 'The criterion to which the criterion option belongs'
      optional :outcome_status, type: String, desc: 'The outcome status for the student when this criterion option is true; e.g., "Fix and Rebsubmit", "Complete", etc'
      optional :unresolved_message_text, type: String, desc: 'text that the tutor returns to the student who has not resolved the issue on resubmit'
      optional :resolved_message_text, type: String, desc: 'text that the tutor returns to the student who has resolved the issue on resubmit'
    end
    post '/criterion_options' do
      criterion = Criterion.find(params[:criterion_id])

      unless authorise? current_user, criterion.stage.task_definition.unit, :update
        error!({ error: 'Not authorised to create a criterion option for this unit' }, 403)
      end

      criterion_option_parameters = ActionController::Parameters.new(params)
                                                                .permit(:outcome_status, :unresolved_message_text, :resolved_message_text)

      criterion_option_parameters[:criterion] = criterion

      result = CriterionOption.create!(criterion_option_parameters)

      present result, with: Entities::FeedbackEntities::CriterionOptionEntity
    end

    desc 'This endpoint allows you to get all the criterion options for a given criterion.'
    params do
      requires :criterion_id, type: Integer, desc: 'The criterion to which the criterion option belongs'
    end
    get '/criterion_options' do
      criterion = Criterion.find(params[:criterion_id])

      unless authorise? current_user, criterion.unit, :provide_feedback
        error!({ error: 'Not authorised to get feedback criterion options for this unit' }, 403)
      end

      present criterion.criterion_options, with: Entities::FeedbackEntities::CriterionOptionEntity
    end

    desc 'This endpoint allows you to update the outcome status, unresolved message text and resolved message text of a criterion option.'
    params do
      optional :outcome_status, type: String, desc: 'The new outcome status for the criterion option'
      optional :unresolved_message_text, type: String, desc: 'The new unresolved message text for the criterion option'
      optional :resolved_message_text, type: String, desc: 'The new resolved message text for the criterion option'
    end
    put '/criterion_options/:id' do
      criterion_option = CriterionOption.find(params[:id])

      unless authorise? current_user, criterion_option.unit, :update
        error!({ error: 'Not authorised to update feedback criterion options for this unit' }, 403)
      end

      criterion_option_params = ActionController::Parameters.new(params)
                                                            .permit(:outcome_status, :unresolved_message_text, :resolved_message_text)

      criterion_option.update!(criterion_option_params)

      present criterion_option, with: Entities::FeedbackEntities::CriterionOptionEntity
    end

    desc 'This endpoint allows you to delete a criterion option.'
    delete '/criterion_options/:id' do
      criterion_option = CriterionOption.find(params[:id])

      unless authorise? current_user, criterion_option.unit, :update
        error!({ error: 'Not authorised to delete feedback criterion options for this unit' }, 403)
      end

      criterion_option.destroy!

      present criterion_option, with: Entities::FeedbackEntities::CriterionOptionEntity
    end
  end
end

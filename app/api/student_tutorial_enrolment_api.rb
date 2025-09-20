require 'grape'

class StudentTutorialEnrolmentApi < Grape::API
  helpers AuthenticationHelpers
  helpers AuthorisationHelpers

  before do
    authenticated?
  end

  resource :projects do
    route_param :project_id do
      resource :tutorial_enrolments do
        desc 'Enrol student in tutorial for self-enrolment task'
        params do
          requires :task_definition_id, type: Integer, desc: 'Task definition with self enrolment enabled'
          requires :tutorial_id, type: Integer, desc: 'Tutorial to enrol in'
        end
        post do
          project = Project.find(params[:project_id])

          # Authorization check
          error!('Unauthorized', 401) unless project.student == current_user

          task_def = TaskDefinition.find(params[:task_definition_id])
          tutorial = Tutorial.find(params[:tutorial_id])

          # Validation checks
          error!('Task does not allow self enrolment', 400) unless task_def.tutorial_self_enrolment_enabled?
          error!('Tutorial not available for this task', 400) unless task_def.available_tutorials_for_self_enrolment.include?(tutorial)
          if tutorial.respond_to?(:at_capacity?) && tutorial.at_capacity?
            error!('Tutorial is full', 400)
          end

          # Check if already enrolled in this stream
          existing_enrolment = project.tutorial_enrolments.joins(:tutorial)
                                     .where(tutorials: { tutorial_stream_id: task_def.tutorial_self_enrolment_stream_id })
                                     .first

          if existing_enrolment
            # Update existing enrolment
            existing_enrolment.update!(tutorial: tutorial)
            message = 'Tutorial enrolment updated successfully'
          else
            # Create new enrolment
            project.enrol_in(tutorial)
            message = 'Tutorial enrolment created successfully'
          end

          {
            success: true,
            message: message,
            tutorial: {
              id: tutorial.id,
              abbreviation: tutorial.abbreviation,
              campus_id: tutorial.campus_id
            }
          }
        end

        desc 'Get current tutorial enrolment for task'
        params do
          requires :task_definition_id, type: Integer, desc: 'Task definition with self enrolment enabled'
        end
        get do
          project = Project.find(params[:project_id])

          # Authorization check
          error!('Unauthorized', 401) unless project.student == current_user || authorise?(current_user, project, :get)

          task_def = TaskDefinition.find(params[:task_definition_id])

          # Find enrolment in the relevant stream
          enrolment = project.tutorial_enrolments.joins(:tutorial)
                            .where(tutorials: { tutorial_stream_id: task_def.tutorial_self_enrolment_stream_id })
                            .first

          if enrolment
            {
              enrolled: true,
              tutorial: {
                id: enrolment.tutorial.id,
                abbreviation: enrolment.tutorial.abbreviation,
                campus_id: enrolment.tutorial.campus_id
              }
            }
          else
            { enrolled: false }
          end
        end
      end
    end
  end
end

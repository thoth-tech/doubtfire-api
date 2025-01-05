require 'grape'

class ProjectsApi < Grape::API
  helpers AuthenticationHelpers
  helpers AuthorisationHelpers
  helpers DbHelpers

  before do
    authenticated?
  end

  desc "Fetches all of the current user's projects"
  params do
    optional :include_inactive, type: Boolean, desc: 'Include projects for units that are no longer active?'
  end
  get '/projects' do
    include_inactive = params[:include_inactive] || false

    projects = Project.eager_load(:unit, :user).for_user current_user, include_inactive
    present projects, with: Entities::ProjectEntity, for_student: true, summary_only: true, user: current_user
  end

  desc 'Get project with target grade history'
  params do
    requires :id, type: Integer, desc: 'The id of the project to get'
  end
  get '/projects/:id' do
    project = Project.includes(:unit, :user, target_grade_histories: :changed_by).find(params[:id])

    if authorise? current_user, project, :get
      present project, with: Entities::ProjectEntity, user: current_user, for_student: true, in_project: true
    else
      error!({ error: "Couldn't find Project with id=#{params[:id]}" }, 403)
    end
  end

  desc 'Update a project'
  params do
    optional :trigger,            type: String,  desc: 'The update trigger'
    optional :campus_id,          type: Integer, desc: 'Campus this project is part of, or -1 for no campus'
    optional :enrolled,           type: Boolean, desc: 'Enrol or withdraw this project'
    optional :target_grade,       type: Integer, desc: 'New target grade'
    optional :submitted_grade,    type: Integer, desc: 'New submitted grade'
    optional :compile_portfolio,  type: Boolean, desc: 'Schedule a construction of the portfolio'
    optional :grade,              type: Integer, desc: 'New grade'
    optional :old_grade,          type: Integer, desc: 'Old grade to check it has not changed...'
    optional :grade_rationale,    type: String,  desc: 'New grade rationale'
  end
  put '/projects/:id' do
    project = Project.find(params[:id])

    for_student = true

    if params[:trigger].nil? == false
      if params[:trigger] == 'trigger_week_end'
        if authorise? current_user, project, :trigger_week_end
          project.trigger_week_end(current_user)
        else
          error!({ error: "You are not authorised to perform this action" }, 403)
        end
      else
        error!({ error: "Invalid trigger - #{params[:trigger]} unknown" }, 403)
      end
    # If we are only updating the campus
    elsif params[:campus_id].present?
      unless authorise? current_user, project, :change_campus
        error!({ error: "You cannot change the campus for this student" }, 403)
      end
      for_student = false
      project.campus_id = params[:campus_id] == -1 ? nil : params[:campus_id]
      project.save!
    elsif !params[:enrolled].nil?
      unless authorise? current_user, project.unit, :change_project_enrolment
        error!({ error: "You cannot change the enrolment for this student" }, 403)
      end
      for_student = false
      project.enrolled = params[:enrolled]
      project.save
    elsif !params[:target_grade].nil?
      unless authorise? current_user, project, :change
        error!({ error: "You do not have permissions to change this student" }, 403)
      end

      previous_grade = project.target_grade
      new_grade = params[:target_grade]

      project.target_grade = new_grade

      if project.save
        # Record the grade change history
        TargetGradeHistory.create(
          project_id: project.id,
          user_id: project.user_id,
          previous_grade: previous_grade,
          new_grade: new_grade,
          changed_by_id: current_user.id,
          changed_at: Time.current
        )
      else
        error!({ error: "Failed to update target grade: #{project.errors.full_messages.join(', ')}" }, 422)
      end

    elsif !params[:submitted_grade].nil?
      unless authorise? current_user, project, :change
        error!({ error: "You do not have permissions to change this student" }, 403)
      end
      if project.portfolio_exists?
        error!({ error: "You cannot change your submitted grade after portfolio submission" }, 403)
      end

      project.submitted_grade = params[:submitted_grade]
      project.save
    elsif !params[:grade].nil?
      unless authorise? current_user, project, :assess
        error!({ error: "You do not have permissions to assess this student" }, 403)
      end

      if params[:grade_rationale].nil?
        error!({ error: 'Grade rationale required to perform assessment.' }, 403)
      end

      if params[:old_grade].nil?
        error!({ error: 'Existing project grade is required to perform assessment.' }, 403)
      end

      if params[:old_grade] != project.grade
        error!({ error: 'Existing project grade does not match current grade. Refresh project and try again.' }, 403)
      end

      for_student = false

      project.grade = params[:grade]
      project.grade_rationale = params[:grade_rationale]
      project.save!

      present project, Entities::ProjectEntity, for_staff: true
      return
    elsif !params[:compile_portfolio].nil?
      unless authorise? current_user, project, :change
        error!({ error: "You do not have permissions to change this student" }, 403)
      end

      # if someone changes this setting manually, clear the autogenerated status
      project.portfolio_auto_generated = false
      project.compile_portfolio = params[:compile_portfolio]
      project.save
    end

    Entities::ProjectEntity.represent(project, only: [:campus_id, :enrolled, :target_grade, :submitted_grade, :compile_portfolio, :portfolio_available, :uses_draft_learning_summary, :stats], for_student: for_student)
  end # put

  desc 'Enrol a student in a unit, creating them a project'
  params do
    requires :unit_id, type: Integer, desc: 'Unit Id'
    requires :student_num, type: String, desc: 'Student Number 7 digit code'
    requires :campus_id, type: Integer, desc: 'Campus this project is part of'
  end
  post '/projects' do
    unit = Unit.find(params[:unit_id])
    student = User.find_by(username: params[:student_num])
    student = User.find_by(student_id: params[:student_num]) if student.nil?
    student = User.find_by(email: params[:student_num]) if student.nil?

    if student.nil?
      error!({ error: "Couldn't find Student with username=#{params[:student_num]}" }, 403)
    end

    campus = Campus.find(params[:campus_id])

    if authorise? current_user, unit, :enrol_student
      proj = unit.enrol_student(student, campus)
      if proj.nil?
        error!({ error: 'Error adding student to unit' }, 403)
      else
        result = {
          id: proj.id,
          enrolled: proj.enrolled,
          student: {
            id: proj.student.id,
            student_id: proj.student.student_id,
            username: proj.student.username,
            email: proj.student.email,
            first_name: proj.student.first_name,
            last_name: proj.student.last_name,
            nickname: proj.student.nickname
          },
          target_grade: proj.target_grade,
          campus_id: proj.campus_id,
          compile_portfolio: false,
          grade: proj.grade,
          grade_rationale: proj.grade_rationale,
          similarity_flag: false,
          has_portfolio: false,
          stats: Project::DEFAULT_TASK_STATS
        }
        present result, with: Grape::Presenters::Presenter
      end
    else
      error!({ error: "Couldn't find Unit with id=#{params[:unit_id]}" }, 403)
    end
  end
end

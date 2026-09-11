require 'grape'

class LtiApi < Grape::API
  helpers AuthenticationHelpers
  helpers AuthorisationHelpers
  helpers LtiHelper
  helpers SidekiqHelper
  include LogHelper

  # before do
  #   authenticated?
  # end

  desc 'Returns success if current user is allowed to link requested unit'
  params do
    requires :ltik, type: String, desc: 'LtiKey provided with user info and deeplink resources'
  end
  post '/lti/link' do
    authenticated?

    unless authorise? current_user, User, :convene_units
      error!({ error: "Not authorised to link this unit." }, 403)
    end

    token = decode_lti_token(params[:ltik])

    unit_id = token["unit_id"]
    if unit_id.nil?
      error!({ error: 'Invalid LTI token.' }, 400)
    end

    unit = Unit.find_by(id: unit_id)

    if unit.nil?
      error!({ error: 'Unit does not exist.' }, 404)
    end

    unless authorise? current_user, unit, :enrol_student
      error!({ error: "Not authorised to link this unit." }, 403)
    end

    status 200
  end

  desc 'Enrol a student into a linked Lti unit'
  params do
    requires :ltik, type: String, desc: 'LtiKey provided with user info and deeplink resources'
  end
  post '/lti/enrol' do
    authenticated?

    token = decode_lti_token(params[:ltik])

    unit_id = token["unit_id"]
    if unit_id.nil?
      error!({ error: 'Invalid LTI token.' }, 400)
    end

    unit = Unit.find_by(id: unit_id)
    if unit.nil?
      error!({ error: 'Unit does not exist.' }, 404)
    end

    member = token['member']
    if member.nil?
      error!({ error: 'Invalid LTI token.' }, 400)
    end

    valid_member, missing = valid_lti_member?(member)
    unless valid_member
      error!({ error: "Missing required fields:  #{missing.join(', ')}" }, 400)
    end

    # The token names the person the launch was issued for, and its roles decide
    # what that person gets. Apply it to that person, and only while that person
    # is the one holding the session.
    unless lti_member_is?(member, current_user)
      error!({ error: 'This LTI token was not issued for the signed in user.' }, 403)
    end

    subject = current_user

    unit_role = Doubtfire::Application.config.institution_settings.should_employ_lti_member(member)
    enrol_member = Doubtfire::Application.config.institution_settings.should_enrol_lti_member(member)

    project = nil
    consumed = ConsumedLtiToken.find_by(jti: token['jti'])

    if consumed.present?
      # The web client carries the one launch token for the whole session and
      # calls this route on every mount of the dashboard, so the subject
      # presenting their own token again is not a replay. The token is spent
      # either way, so nothing is applied a second time.
      unless consumed.spent_by?(subject)
        error!({ error: 'This LTI token has already been used.' }, 403)
      end

      project = unit.projects.find_by(user_id: subject.id) if enrol_member
    else
      begin
        ActiveRecord::Base.transaction do
          # Spend the token before anything is applied. A concurrent replay
          # loses on the unique index and rolls the whole enrolment back.
          ConsumedLtiToken.consume!(token, user: subject)

          unit.employ_staff(subject, unit_role) unless unit_role.nil?

          # TODO: which campus?
          project = unit.enrol_student(subject, nil) if enrol_member
        end
      rescue ConsumedLtiToken::AlreadyUsed
        error!({ error: 'This LTI token has already been used.' }, 403)
      end
    end

    if project.nil?
      # error!({ error: 'User can not be enrolled into this unit.' }, 404)
      status 204
    else
      present project, with: Entities::ProjectEntity, user: subject, for_student: true, in_project: true
    end
  end

  desc 'Enrol a list of students into a linked Lti unit'
  params do
    requires :ltik, type: String, desc: 'LtiKey provided with unit id and list of members'
    # requires :members, type: Array,
    #   requires :email, type: String
    #   requires :family_name, type: String
    #   requires :given_name, type: String
    #   requires :name, type: String
    #   requires :user_id, type: String
    #   requires :roles, type: Array[String]
    # end
  end
  post '/lti/enrol/bulk' do
    authenticated?

    token = decode_lti_token(params[:ltik])

    unit_id = token["unit_id"]
    if unit_id.nil?
      error!({ error: 'Invalid LTI token.' }, 400)
    end

    unit = Unit.find_by(id: unit_id)
    if unit.nil?
      error!({ error: 'Unit does not exist.' }, 404)
    end

    unless authorise? current_user, unit, :enrol_student
      error!({ error: "Not authorised to link this unit." }, 403)
    end

    job_id = ImportStudentsLtiJob.perform_async(unit.id, token['members'])
    job = setup_job(job_id)
    present job, with: Entities::SidekiqJobEntity
  end

  desc 'Get grades for a list of students'
  params do
    requires :ltik, type: String, desc: 'LtiKey provided with user info and deeplink resources'
  end
  post '/lti/grades' do
    authenticated?

    token = decode_lti_token(params[:ltik])

    unless authorise? current_user, User, :convene_units
      error!({ error: "Not authorised to sync grades." }, 403)
    end

    unit_id = token["unit_id"]
    if unit_id.nil?
      error!({ error: 'Invalid LTI token.' }, 400)
    end

    unit = Unit.find_by(id: unit_id)
    if unit.nil?
      error!({ error: 'Unit does not exist.' }, 404)
    end

    student_emails = token["student_emails"]

    if student_emails.nil?
      error!({ error: 'Student emails field does not exist.' }, 400)
    end

    unless student_emails.is_a?(Array)
      error!({ error: 'Student emails must be an array.' }, 400)
    end

    projects = unit.projects.joins(:user).where(users: { email: student_emails })

    projects_hash = {}

    projects.each do |project|
      projects_hash[project.user.email] = if authorise?(current_user, project, :assess)
                                            project.grade
                                          else
                                            # Let the lti API know that user doesnt have permission to this project
                                            -1
                                          end
    end

    projects_hash
  end
end

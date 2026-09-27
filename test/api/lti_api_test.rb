require 'test_helper'
require 'minitest/mock'
require 'securerandom'
require 'json'

class LtiApiTest < ActiveSupport::TestCase
  include Rack::Test::Methods
  include TestHelpers::AuthHelper
  include TestHelpers::JsonHelper

  # Build the LTI member block that describes an existing Doubtfire user, using
  # the identity fields the LTI routes map onto a user.
  def lti_member_for(user, roles:)
    {
      user_id: user.id.to_s,
      name: user.nickname || user.first_name,
      given_name: user.first_name,
      family_name: user.last_name,
      email: user.email,
      ext_user_username: user.login_id,
      roles: roles
    }
  end

  def lti_user(trait)
    FactoryBot.create(:user, trait, login_id: "lti-#{SecureRandom.hex(6)}")
  end

  # Pass jti: nil to build a token that carries no JWT id at all.
  def lti_enrol_token(unit, member, jti: SecureRandom.uuid)
    payload = {
      unit_id: unit.id,
      member: member,
      exp: Time.now.to_i + 30
    }
    payload[:jti] = jti unless jti.nil?

    JWT.encode(payload, Doubtfire::Application.config.lti_api_secret, 'HS256')
  end

  def test_ensure_jwt_secret_is_valid
    # Simply validate that our ENV var is not nil
    secret_key = Doubtfire::Application.config.lti_api_secret
    assert_not_nil secret_key, "Lti API Secret is not set"
  end

  def test_invalid_jwt
    urls = [
      "/api/auth/lti",
      "/api/lti/link",
      "/api/lti/enrol",
      "/api/lti/enrol/bulk",
      "/api/lti/grades"
    ]

    # Test tokens without jti or expiration
    token_missing_exp = {
      jti: SecureRandom.uuid
    }
    token_missing_jti = {
      exp: Time.now.to_i + 30
    }

    # Test an expired token
    token_expired = {
      exp: Time.now.to_i - 30,
      jti: SecureRandom.uuid
    }

    payloads = [
      token_missing_exp,
      token_missing_jti,
      token_expired
    ]

    secret_key = Doubtfire::Application.config.lti_api_secret

    tokens = []
    payloads.each do |payload|
      token = JWT.encode(payload, secret_key, 'HS256')
      tokens.push(token)

      # Test invalid signatures
      token_wrong_sig = JWT.encode(payload, 'wrong-secret-key', 'HS256')
      tokens.push(token_wrong_sig)
    end

    add_auth_header_for(user: FactoryBot.create(:user, :convenor))

    urls.each do |url|
      tokens.each do |token|
        data = {
          ltik: token
        }
        post url, data
        assert_equal 403, last_response.status, "Expected 'Invalid LTI token. #{url} -  #{last_response_body}"
        assert_equal "Invalid LTI token.", last_response_body['error'], "Expected 'Invalid LTI token.' #{url} - #{last_response_body}"
      end
    end
  end

  def test_invalid_unit
    secret_key = Doubtfire::Application.config.lti_api_secret

    routes_expecting_unit = [
      "/api/lti/link",
      "/api/lti/enrol",
      "/api/lti/enrol/bulk",
      "/api/lti/grades"
    ]

    payload_missing_unit_id = {
      exp: Time.now.to_i + 30,
      jti: SecureRandom.uuid
    }
    token_missing_unit_id = JWT.encode(payload_missing_unit_id, secret_key, 'HS256')

    add_auth_header_for(user: FactoryBot.create(:user, :convenor))

    # Ensure we get a 401 error if unit_id is missing from the token
    routes_expecting_unit.each do |url|
      post url, { ltik: token_missing_unit_id }
      assert_equal 400, last_response.status, "Expected 400 from #{url} with missing unit_id #{last_response_body}"
      assert_equal "Invalid LTI token.", last_response_body['error']
    end

    # Ensure we get a 404 if the unit (id) does not exist
    payload_invalid_unit_id = {
      unit_id: 9_999_999, # Unit should not exist
      exp: Time.now.to_i + 30,
      jti: SecureRandom.uuid
    }
    token_invalid_unit_id = JWT.encode(payload_invalid_unit_id, secret_key, 'HS256')

    routes_expecting_unit.each do |url|
      post url, { ltik: token_invalid_unit_id }
      assert_equal 404, last_response.status, "Expected 404 from #{url} with invalid unit #{last_response_body}"
      assert_equal "Unit does not exist.", last_response_body['error']
    end
  end

  def test_lti_authentication
    secret_key = Doubtfire::Application.config.lti_api_secret

    username = 'user12345'
    member = {
      user_id: '3',
      name: 'Nickname 2',
      given_name: 'First name 2',
      family_name: 'Last name 2',
      email: "#{username}@doubtfire.com",
      ext_user_username: 'student_test_lti3',
      roles: ['Learner']
    }
    token = JWT.encode({
                         member: member,
                         exp: Time.now.to_i + 30,
                         jti: SecureRandom.uuid
                       }, secret_key, 'HS256')

    #  Retrieve the temporary auth token and username
    post '/api/auth/lti', { ltik: token }
    assert_equal 201, last_response.status
    assert last_response_body.key?('username')
    assert last_response_body.key?('auth_token')
    assert_equal username, last_response_body['username']

    # Sign in with the one-time auth token and username
    post '/api/auth', { username: last_response_body['username'], auth_token: last_response_body['auth_token'] }
    assert_equal 201, last_response.status
    assert last_response_body.key?('user')
    user_body = last_response_body['user']
    assert user_body.key?('id')
    user_id = user_body['id']

    # Ensure user was created
    user = User.find(user_id)
    assert user.valid?

    assert_equal member[:ext_user_username], user.login_id
    assert_equal member[:given_name], user.first_name
    assert_equal member[:family_name], user.last_name
    assert_equal member[:name], user.nickname
    assert_equal member[:email], user.email
    assert_equal username, user.username
  end

  def test_convenor_can_link_requested_unit
    # Create convenor
    convenor = FactoryBot.create(:user, :convenor)

    # Add Auth header for convenor
    add_auth_header_for(user: convenor)

    # Create a new unit as a convenor
    post '/api/units', {
      unit: {
        name: 'New Unit',
        code: 'Unit101'
      }
    }
    assert_equal 201, last_response.status, last_response_body

    unit_id = last_response_body['id']
    unit = Unit.find(unit_id)

    # Ensure that convenor is able to get this unit
    get '/api/units'
    assert_equal 200, last_response.status
    assert_equal 1, last_response_body.count
    last_response_body.each do |data|
      the_unit = Unit.find(data['id'])
      assert_equal data['id'].to_i, unit.id
      assert_equal the_unit.id, unit.id
    end

    payload = {
      unit_id: unit.id,
      exp: Time.now.to_i + 30,
      jti: SecureRandom.uuid
    }

    secret_key = Doubtfire::Application.config.lti_api_secret
    token = JWT.encode(payload, secret_key, 'HS256')

    users_can = [
      convenor,
      FactoryBot.create(:user, :admin)
    ]

    # Test to ensure convenor and admins can link the unit
    users_can.each do |_user|
      post '/api/lti/link', { ltik: token }
      assert_equal 200, last_response.status, last_response_body
    end

    # Test to ensure that convenors cant link a unit they can not already enrol students in
    payload_invalid_unit = {
      unit_id: Unit.first.id,
      exp: Time.now.to_i + 30,
      jti: SecureRandom.uuid
    }

    token_invalid_unit = JWT.encode(payload_invalid_unit, secret_key, 'HS256')

    post '/api/lti/link', { ltik: token_invalid_unit }
    assert_equal 403, last_response.status, last_response_body
    assert_equal "Not authorised to link this unit.", last_response_body['error'], last_response_body

    users_cant = [
      FactoryBot.create(:user, :student),
      FactoryBot.create(:user, :tutor)
    ]

    # Ensure that students and tutors cant link the unit
    users_cant.each do |user|
      add_auth_header_for(user: user)
      post '/api/lti/link', { ltik: token }
      assert_equal 403, last_response.status, last_response_body
    end
    unit.destroy
  end

  def test_correct_roles_are_enrolled
    roles_can_be_enrolled = %w[
      Student
      Learner
    ]

    roles_cant_be_enrolled = %w[
      Admin
      Instructor
    ]

    unit = FactoryBot.create(:unit, with_students: false)

    # Each launch is presented by the person it was issued for, and each one
    # carries its own token id.
    roles_cant_be_enrolled.each do |role|
      user = lti_user(:student)
      token = lti_enrol_token(unit, lti_member_for(user, roles: [role]))

      add_auth_header_for(user: user)
      post '/api/lti/enrol', { ltik: token }

      assert_equal 204, last_response.status, last_response.body
    end

    roles_can_be_enrolled.each do |role|
      user = lti_user(:student)
      token = lti_enrol_token(unit, lti_member_for(user, roles: [role]))

      add_auth_header_for(user: user)
      post '/api/lti/enrol', { ltik: token }

      assert_equal 201, last_response.status, last_response.body
      id = last_response_body['id']
      assert_not_nil id, "Expected project ID in response"

      project = Project.find(id)
      assert project.valid?, "Expected project to be created"
      assert_equal unit.id, project.unit.id
      assert_equal user.id, project.user_id
    end
  end

  # The launch subject enrolling themselves is the ordinary path and must keep
  # working.
  def test_lti_enrol_binds_a_token_to_its_subject
    unit = FactoryBot.create(:unit, with_students: false)
    student = lti_user(:student)

    token = lti_enrol_token(unit, lti_member_for(student, roles: ['Learner']))

    add_auth_header_for(user: student)
    post '/api/lti/enrol', { ltik: token }

    assert_equal 201, last_response.status, last_response.body

    project = Project.find(last_response_body['id'])
    assert_equal student.id, project.user_id
    assert_equal unit.id, project.unit_id
  end

  # A token issued for a member of staff must not give its bearer that staff
  # role in the unit.
  def test_lti_enrol_rejects_a_token_presented_by_another_user
    unit = FactoryBot.create(:unit, with_students: false)
    staff = lti_user(:tutor)
    # Tutor capable, so without the check the token's Instructor role would
    # actually land on them.
    bearer = lti_user(:tutor)

    token = lti_enrol_token(unit, lti_member_for(staff, roles: ['Instructor']))

    add_auth_header_for(user: bearer)
    post '/api/lti/enrol', { ltik: token }

    unit.reload
    assert_nil unit.unit_role_for(bearer), "Bearer of the token gained a unit role"
    assert_nil unit.unit_role_for(staff), "Subject of the token gained a unit role"
    assert_equal 0, unit.projects.where(user_id: bearer.id).count

    assert_equal 403, last_response.status, last_response.body
  end

  # The web client carries the one launch token for the whole session, so the
  # subject presenting it again has to keep working, and has to give the same
  # enrolment back rather than a second one.
  def test_lti_enrol_lets_the_launch_subject_present_the_same_token_again
    unit = FactoryBot.create(:unit, with_students: false)
    student = lti_user(:student)
    jti = SecureRandom.uuid

    token = lti_enrol_token(unit, lti_member_for(student, roles: ['Learner']), jti: jti)

    add_auth_header_for(user: student)

    post '/api/lti/enrol', { ltik: token }
    assert_equal 201, last_response.status, last_response.body
    project_id = last_response_body['id']

    post '/api/lti/enrol', { ltik: token }
    assert_equal 201, last_response.status, last_response.body
    assert_equal project_id, last_response_body['id']

    assert_equal 1, unit.projects.where(user_id: student.id).count
    assert_equal 1, ConsumedLtiToken.where(jti: jti).count
  end

  # A token already spent by somebody else must not be spendable again, even by
  # a caller the member fields now resolve to.
  def test_lti_enrol_rejects_a_token_already_spent_by_another_user
    unit = FactoryBot.create(:unit, with_students: false)
    student = lti_user(:student)
    other = lti_user(:student)
    jti = SecureRandom.uuid

    ConsumedLtiToken.create!(jti: jti, user: other, expires_at: 1.minute.from_now)

    token = lti_enrol_token(unit, lti_member_for(student, roles: ['Learner']), jti: jti)

    add_auth_header_for(user: student)
    post '/api/lti/enrol', { ltik: token }

    assert_equal 403, last_response.status, last_response.body
    assert_equal 'This LTI token has already been used.', last_response_body['error']
    assert_equal 0, unit.projects.where(user_id: student.id).count
  end

  # The replay record belongs to the account whose launch spent it. It must not
  # turn the new foreign key into a reason an otherwise unused account cannot be
  # deleted.
  def test_consumed_lti_token_is_removed_with_its_user
    user = lti_user(:student)
    consumed = ConsumedLtiToken.create!(jti: SecureRandom.uuid, user: user, expires_at: 1.minute.from_now)

    user.destroy!

    assert_not ConsumedLtiToken.exists?(consumed.id)
  end

  # The loser of a race on the unique index saw nothing recorded when it
  # started, and still must not spend the token a second time.
  def test_lti_enrol_rejects_a_concurrent_replay
    unit = FactoryBot.create(:unit, with_students: false)
    student = lti_user(:student)

    token = lti_enrol_token(unit, lti_member_for(student, roles: ['Learner']))

    add_auth_header_for(user: student)

    duplicate = ->(*_args, **_kwargs) { raise ActiveRecord::RecordNotUnique, 'Duplicate entry' }
    ConsumedLtiToken.stub(:create!, duplicate) do
      post '/api/lti/enrol', { ltik: token }
    end

    assert_equal 403, last_response.status, last_response.body
    assert_equal 'This LTI token has already been used.', last_response_body['error']
    assert_equal 0, unit.projects.where(user_id: student.id).count
  end

  # A unique index failure from anywhere else in the enrolment is not a replay
  # and must not be reported as one.
  def test_lti_enrol_does_not_report_an_unrelated_unique_failure_as_a_replay
    unit = FactoryBot.create(:unit, with_students: false)
    student = lti_user(:student)

    token = lti_enrol_token(unit, lti_member_for(student, roles: ['Learner']))

    add_auth_header_for(user: student)

    duplicate = lambda do |*_args, **_kwargs|
      raise ActiveRecord::RecordNotUnique, "Duplicate entry for key 'index_projects_on_unit_id_and_user_id'"
    end

    Project.stub(:create!, duplicate) do
      post '/api/lti/enrol', { ltik: token }
    end

    assert_not_equal 403, last_response.status, last_response.body
    assert_not_equal 'This LTI token has already been used.', last_response_body['error']
  end

  # A token whose member only lines up with the local part of somebody's email
  # address names nobody. The platform asserts a login id and an email, and
  # neither of those is the caller here.
  def test_lti_enrol_rejects_a_token_matching_only_a_derived_username
    unit = FactoryBot.create(:unit, with_students: false)

    local_part = "alex-#{SecureRandom.hex(4)}"
    # Tutor capable, so the token's Instructor role would actually land on them.
    caller_user = FactoryBot.create(
      :user,
      :tutor,
      username: local_part,
      login_id: "lti-#{SecureRandom.hex(6)}",
      email: "#{local_part}@another.example"
    )

    jti = SecureRandom.uuid
    member = {
      user_id: "unseen-#{SecureRandom.hex(4)}",
      name: 'New Staff',
      given_name: 'New',
      family_name: 'Staff',
      email: "#{local_part}@provider.example",
      ext_user_username: "new-staff-#{SecureRandom.hex(4)}",
      roles: ['Instructor']
    }

    token = lti_enrol_token(unit, member, jti: jti)

    add_auth_header_for(user: caller_user)
    post '/api/lti/enrol', { ltik: token }

    assert_equal 403, last_response.status, last_response.body

    unit.reload
    assert_nil unit.unit_role_for(caller_user), "Caller gained the token's staff role"
    assert_nil ConsumedLtiToken.find_by(jti: jti)
  end

  # A token that names a login_id has said who it is for. If that does not match,
  # a shared or reused email address must not let it bind anyway.
  def test_lti_enrol_rejects_a_token_whose_login_id_does_not_match
    unit = FactoryBot.create(:unit, with_students: false)

    shared_email = "shared-#{SecureRandom.hex(4)}@provider.example"
    caller_user = FactoryBot.create(
      :user,
      :tutor,
      username: "alex-#{SecureRandom.hex(4)}",
      login_id: "lti-#{SecureRandom.hex(6)}",
      email: shared_email
    )

    jti = SecureRandom.uuid
    member = {
      user_id: "unseen-#{SecureRandom.hex(4)}",
      name: 'New Staff',
      given_name: 'New',
      family_name: 'Staff',
      # Same address, but the platform is naming a different person.
      email: shared_email,
      ext_user_username: "new-staff-#{SecureRandom.hex(4)}",
      roles: ['Instructor']
    }

    token = lti_enrol_token(unit, member, jti: jti)

    add_auth_header_for(user: caller_user)
    post '/api/lti/enrol', { ltik: token }

    assert_equal 403, last_response.status, last_response.body

    unit.reload
    assert_nil unit.unit_role_for(caller_user), "Caller gained the token's staff role on an email match alone"
    assert_nil ConsumedLtiToken.find_by(jti: jti)
  end

  # Recording token ids must not let a token through that carries no id.
  def test_lti_enrol_rejects_a_token_without_a_jti
    unit = FactoryBot.create(:unit, with_students: false)
    student = lti_user(:student)

    token = lti_enrol_token(unit, lti_member_for(student, roles: ['Learner']), jti: nil)

    add_auth_header_for(user: student)
    post '/api/lti/enrol', { ltik: token }

    assert_equal 403, last_response.status, last_response.body
    assert_equal "Invalid LTI token.", last_response_body['error']
    assert_equal 0, unit.projects.where(user_id: student.id).count
  end

  # An empty token id is no more recordable than a missing one, so it has to be
  # turned away in the same place rather than blowing up on the insert.
  def test_lti_enrol_rejects_a_token_with_an_empty_jti
    unit = FactoryBot.create(:unit, with_students: false)
    student = lti_user(:student)

    token = lti_enrol_token(unit, lti_member_for(student, roles: ['Learner']), jti: '')

    add_auth_header_for(user: student)
    post '/api/lti/enrol', { ltik: token }

    assert_equal 403, last_response.status, last_response.body
    assert_equal "Invalid LTI token.", last_response_body['error']
    assert_equal 0, unit.projects.where(user_id: student.id).count
  end

  # An ordinary staff launch still employs the person it was issued for, with
  # the role the token asks for.
  def test_lti_enrol_employs_the_launch_subject_as_staff
    unit = FactoryBot.create(:unit, with_students: false)
    tutor = lti_user(:tutor)

    token = lti_enrol_token(unit, lti_member_for(tutor, roles: ['Instructor']))

    add_auth_header_for(user: tutor)
    post '/api/lti/enrol', { ltik: token }

    assert_equal 204, last_response.status, last_response.body

    # The dashboard mounts again with the same token after the unit is linked.
    post '/api/lti/enrol', { ltik: token }
    assert_equal 204, last_response.status, last_response.body

    unit.reload
    assert_equal 1, unit.unit_roles.where(user_id: tutor.id).count
    unit_role = unit.unit_role_for(tutor)
    assert_not_nil unit_role, "Expected the launch subject to be employed"
    assert_equal Role.tutor.id, unit_role.role_id
  end

  def test_enrol_students_bulk
    Sidekiq::Testing.inline! do
      unit = FactoryBot.create(:unit, with_students: false, student_count: 0)

      payload = {
        unit_id: unit.id,
        members: [
          # Valid
          {
            user_id: '1',
            name: 'Nickname 1',
            given_name: 'First name 1',
            family_name: 'Last name 1',
            email: 'email1@doubtfire.com',
            ext_user_username: 'student_test_lti1',
            roles: ['Learner']
          },
          # Valid
          {
            user_id: '2',
            name: 'Nickname 2',
            given_name: 'First name 2',
            family_name: 'Last name 2',
            email: 'email2@doubtfire.com',
            ext_user_username: 'student_test_lti2',
            roles: ['Instructor'] # This user should not be enrolled
          },
          # Valid
          {
            user_id: '3',
            name: 'Nickname 2',
            given_name: 'First name 2',
            family_name: 'Last name 2',
            email: 'email3@doubtfire.com',
            ext_user_username: 'student_test_lti3',
            roles: ['Learner', 'http://purl.imsglobal.org/vocab/lis/v2/person#Administrator']
          },
          # Error (Can't create user)
          {
            user_id: '4',
            name: 'Nickname 4',
            given_name: 'First name 4',
            family_name: 'Last name 4',
            email: 'bademail',
            ext_user_username: 'student_test_lti4',
            roles: ['Learner', 'http://purl.imsglobal.org/vocab/lis/v2/person#Administrator']
          },
          # Ignored: missing member data
          {
            # Missing user_id and roles
            name: 'Nickname 4',
            given_name: 'First name 4',
            family_name: 'Last name 4',
            email: 'email5@doubtfire.com',
            ext_user_username: 'student_test_lti4'
          }
        ],
        exp: Time.now.to_i + 30,
        jti: SecureRandom.uuid
      }

      secret_key = Doubtfire::Application.config.lti_api_secret
      token = JWT.encode(payload, secret_key, 'HS256')

      convenor = FactoryBot.create(:user, :convenor)
      unit.employ_staff(convenor, Role.convenor)

      add_auth_header_for(user: convenor)

      expected_enrolled_projects_count = 2
      expected_success_count = 3 # 2 Projects enrolled + 1 Tutor added as staff. The staff will also be added to the ignored row for not being enrolled as a project.
      expected_error_count = 1
      expected_ignore_count = 2
      assert_equal expected_enrolled_projects_count + expected_error_count + expected_ignore_count, payload[:members].count

      post '/api/lti/enrol/bulk', { ltik: token }
      assert_equal 201, last_response.status

      job = last_response_body

      assert_not_nil job['id']

      results = JSON.parse(job['result'])

      assert_equal expected_enrolled_projects_count, unit.projects.count, results
      assert_equal expected_success_count, results['success'].count, results
      assert_equal expected_error_count, results['errors'].count, results
      assert_equal expected_ignore_count, results['ignored'].count, results

      student = FactoryBot.create(:user, :student)
      unit.enrol_student(student, nil)

      # Ensure students cant access this route
      add_auth_header_for(user: student)
      post '/api/lti/enrol/bulk', { ltik: token }
      assert_equal 403, last_response.status
      Sidekiq::Testing.fake!
    end
  end

  def test_get_grades_for_members
    unit = FactoryBot.create(:unit, with_students: false)

    student1 = FactoryBot.create(:user, :student)
    student2 = FactoryBot.create(:user, :student)
    student3 = FactoryBot.create(:user, :student)
    student4 = FactoryBot.create(:user, :student)
    student5 = FactoryBot.create(:user, :student)

    project1 = unit.enrol_student(student1, nil)
    project2 = unit.enrol_student(student2, nil)
    project3 = unit.enrol_student(student3, nil)
    project4 = unit.enrol_student(student4, nil)
    # Don't enrol student5

    project1.grade = 75
    project2.grade = 52
    project3.grade = 85
    project4.grade = 0
    project1.save!
    project2.save!
    project3.save!
    project4.save!

    expected_grades = {
      student1.email.to_s => 75,
      student2.email.to_s => 52,
      student3.email.to_s => 85,
      student4.email.to_s => 0,
      student5.email.to_s => -1
    }

    project1.reload
    project2.reload
    project3.reload
    project4.reload

    tutor =  FactoryBot.create(:user, :student)
    convenor = FactoryBot.create(:user, :convenor)

    unit.employ_staff(tutor, Role.tutor)
    unit.employ_staff(convenor, Role.convenor)

    admin = FactoryBot.create(:user, :admin)
    unit.employ_staff(admin, Role.admin)

    users_cant = [
      student1,
      student2,
      student3,
      student4,
      student5,
      tutor
    ]

    users_can = [
      # Admins have :convene_units permissions, but do not have :assess permissions
      # They will instead receive -1 to indicate they dont have permissions to retrieve grades
      admin,
      convenor
    ]

    secret_key = Doubtfire::Application.config.lti_api_secret

    # Ensure we get an error if we dont pass student_emails fiel
    token_missing_emails = JWT.encode({
                                        unit_id: unit.id,
                                        exp: Time.now.to_i + 30,
                                        jti: SecureRandom.uuid
                                      }, secret_key, 'HS256')

    users_can.each do |user|
      add_auth_header_for(user: user)
      post '/api/lti/grades', { ltik: token_missing_emails }
      assert_equal 400, last_response.status
      assert_equal "Student emails field does not exist.", last_response_body['error']
    end

    # Ensure we get an error if we dont pass in an array

    token_non_array = JWT.encode({
                                   unit_id: unit.id,
                                   student_emails: "not-an-array",
                                   exp: Time.now.to_i + 30,
                                   jti: SecureRandom.uuid
                                 }, secret_key, 'HS256')

    users_can.each do |user|
      add_auth_header_for(user: user)
      post '/api/lti/grades', { ltik: token_non_array }
      assert_equal 400, last_response.status
      assert_equal "Student emails must be an array.", last_response_body['error']
    end

    payload = {
      unit_id: unit.id,
      student_emails: [
        student1.email,
        student2.email,
        student3.email,
        student4.email,
        student5.email
      ],
      exp: Time.now.to_i + 30,
      jti: SecureRandom.uuid
    }

    token = JWT.encode(payload, secret_key, 'HS256')

    users_cant.each do |user|
      add_auth_header_for(user: user)
      post '/api/lti/grades', { ltik: token }
      assert_equal 403, last_response.status
    end

    users_can.each do |user|
      add_auth_header_for(user: user)
      post '/api/lti/grades', { ltik: token }
      assert_equal 201, last_response.status
      assert_equal unit.projects.count, last_response_body.count
      last_response_body.each do |email, grade|
        if unit.role_for(user) == Role.admin
          assert_equal(-1, grade)
        else
          assert_equal(expected_grades[email], grade)
        end
        assert payload[:student_emails].include?(email)
      end
    end
  end

  def test_valid_member_data
    unit = FactoryBot.create(:unit, with_students: false)
    convenor = FactoryBot.create(:user, :convenor)
    unit.employ_staff(convenor, Role.convenor)

    secret_key = Doubtfire::Application.config.lti_api_secret

    token_missing_member = JWT.encode({
                                        unit_id: unit.id,
                                        exp: Time.now.to_i + 30,
                                        jti: SecureRandom.uuid
                                      }, secret_key, 'HS256')

    token_invalid_member_object = JWT.encode({
                                               unit_id: unit.id,
                                               member: "not-a-hash",
                                               exp: Time.now.to_i + 30,
                                               jti: SecureRandom.uuid
                                             }, secret_key, 'HS256')

    token_missing_member_fields = JWT.encode({
                                               unit_id: unit.id,
                                               member: {
                                                 user_id: nil
                                               },
                                               exp: Time.now.to_i + 30,
                                               jti: SecureRandom.uuid
                                             }, secret_key, 'HS256')

    token_member_invalid_email = JWT.encode({
                                              unit_id: unit.id,
                                              member: {
                                                user_id: '3',
                                                name: 'Nickname 2',
                                                given_name: 'First name 2',
                                                family_name: 'Last name 2',
                                                email: nil,
                                                ext_user_username: 'student_test_lti3',
                                                roles: ['Learner']
                                              },
                                              exp: Time.now.to_i + 30,
                                              jti: SecureRandom.uuid
                                            }, secret_key, 'HS256')
    add_auth_header_for(user: convenor)

    urls = [
      '/api/lti/enrol',
      '/api/auth/lti'
    ]

    urls.each do |url|
      post url, { ltik: token_missing_member }
      assert_equal 400, last_response.status
      assert last_response_body['error'].start_with?('Invalid LTI token.'), last_response_body['error']

      post url, { ltik: token_invalid_member_object }
      assert_equal 400, last_response.status
      assert last_response_body['error'].start_with?('Missing required fields:'), last_response_body['error']

      post url, { ltik: token_missing_member_fields }
      assert_equal 400, last_response.status
      assert last_response_body['error'].start_with?('Missing required fields:'), last_response_body['error']

      post url, { ltik: token_member_invalid_email }
      assert_equal 400, last_response.status
      assert last_response_body['error'].start_with?('Missing required fields:'), last_response_body['error']
    end
  end
end

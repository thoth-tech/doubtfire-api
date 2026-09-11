require 'grape'

class UsersApi < Grape::API
  helpers AuthenticationHelpers
  helpers AuthorisationHelpers
  helpers MimeCheckHelpers

  before do
    authenticated?
  end

  desc 'Get the list of users'
  get '/users' do
    unless authorise? current_user, User, :list_users
      error!({ error: 'Cannot list users - not authorised' }, 403)
    end

    present User.all.eager_load(:role), with: Entities::UserEntity
  end

  desc 'Get user'
  get '/users/:id', requirements: { id: /[0-9]*/ } do
    user = User.eager_load(:role).find(params[:id])
    unless (user.id == current_user.id) || (authorise? current_user, User, :get_user)
      error!({ error: "Cannot find User with id #{params[:id]}" }, 403)
    end

    present user,
            with: Entities::UserEntity,
            theme_owner_id: current_user.id
  end

  desc 'Get convenors'
  get '/users/convenors' do
    unless authorise? current_user, User, :get_staff_list
      error!({ error: 'Cannot list convenors - not authorised' }, 403)
    end

    present User.convenors, with: Entities::UserEntity
  end

  desc 'Get tutors'
  get '/users/tutors' do
    unless authorise? current_user, User, :get_staff_list
      error!({ error: 'Cannot list tutors - not authorised' }, 403)
    end

    present User.tutors.eager_load(:role), with: Entities::UserEntity
  end

  desc 'Update a user'
  params do
    requires :id, type: Integer, desc: 'The user id to update'
    requires :user, type: Hash do
      optional :first_name, type: String, desc: 'New first name for user'
      optional :last_name, type: String, desc: 'New last name for user'
      optional :email, type: String, desc: 'New email address for user'
      optional :student_id, type: String, desc: 'New student_id for user'
      optional :nickname, type: String, desc: 'New nickname for user'
      optional :system_role, type: String, desc: 'New role for user [Admin, Auditor, Convenor, Tutor, Student]'
      optional :receive_task_notifications, type: Boolean, desc: 'Allow user to be sent task notifications'
      optional :receive_portfolio_notifications, type: Boolean, desc: 'Allow user to be sent portfolio notifications'
      optional :receive_feedback_notifications, type: Boolean, desc: 'Allow user to be sent feedback notifications'
      optional :display_peer_progress, type: Boolean, desc: 'Display anonymous peer progress information'
      optional :opt_in_to_research, type: Boolean, desc: 'Allow user to opt in to research conducted by Doubtfire'
      optional :has_run_first_time_setup, type: Boolean, desc: 'Whether or not user has run first-time setup'
      optional :theme_preference, type: String, desc: 'Theme preference for the user [light, dark, system]; null means never chosen'
    end
  end
  put '/users/:id' do
    change_self = (params[:id] == current_user.id)

    # Default notification preferences to true when explicitly sent as null.
    # (Previously this wrote the portfolio key three times and read the
    # top-level params instead of the nested :user hash, so it never applied.)
    %i[receive_task_notifications receive_portfolio_notifications receive_feedback_notifications].each do |pref|
      params[:user][pref] = true if params[:user].key?(pref) && params[:user][pref].nil?
    end
    if params[:user].key?(:display_peer_progress) &&
       params[:user][:display_peer_progress].nil?
      params[:user][:display_peer_progress] = true
    end

    # can only modify if current_user.id is same as :id provided
    # (i.e., user wants to update their own data) or if update_user token
    if change_self || (authorise? current_user, User, :update_user)

      user = User.eager_load(:role).find(params[:id])

      user_parameters = ActionController::Parameters.new(params)
                                                    .require(:user)
                                                    .permit(
                                                      :first_name,
                                                      :last_name,
                                                      :email,
                                                      :student_id,
                                                      :nickname,
                                                      :receive_task_notifications,
                                                      :receive_portfolio_notifications,
                                                      :receive_feedback_notifications,
                                                      :display_peer_progress,
                                                      :opt_in_to_research,
                                                      :has_run_first_time_setup,
                                                      :theme_preference
                                                    )

      # Theme preference belongs only to the account itself. Keep authorised
      # staff profile updates backward-compatible by ignoring this one private
      # field instead of rejecting the rest of an otherwise valid update.
      user_parameters.delete(:theme_preference) unless change_self

      user.role = Role.student if user.role.nil?
      old_role = user.role

      # have to translate the system_role -> role
      # note we only let user_parameters role if we're actually *changing* the role
      # (i.e., not passing in the *same* role)
      #
      # You cannot change your own permissions
      #
      if !change_self && params[:user][:system_role] && old_role.name != params[:user][:system_role]
        user_parameters[:role] = params[:user][:system_role]
      end

      #
      # Only allow change of role if current user has permissions to demote/promote the user to the new role
      #
      if user_parameters[:role]
        # work out if promoting or demoting
        new_role = Role.with_name(user_parameters[:role])

        if new_role.nil?
          error!({ error: "No such role name #{user_parameters[:role]}" }, 403)
        end

        if old_role == Role.auditor
          action - :promote_user
        elsif new_role == Role.auditor
          action = old_role == Role.student ? :promote_user : :demote_user
        else
          action = new_role.id > old_role.id ? :promote_user : :demote_user
        end

        # current user not authorised to peform action with new role?
        unless authorise? current_user, User, action, User.get_change_role_perm_fn, [old_role.to_sym, new_role.to_sym]
          error!({ error: "Not authorised to #{action} user with id=#{params[:id]} to #{new_role.name}" }, 403)
        end
        # update :role to actual Role object rather than String type
        user_parameters[:role] = new_role
      end

      # An explicit preference is a synchronization write, even when its value
      # matches the stored value. Clients use this timestamp to reconcile a
      # newer offline choice with the account copy.
      if user_parameters.key?(:theme_preference)
        user.theme_preference_updated_at = user_parameters[:theme_preference].nil? ? nil : Time.current
      end

      # Update changes made to user
      user.update!(user_parameters)
      present user,
              with: Entities::UserEntity,
              theme_owner_id: current_user.id
    else
      error!({ error: "Cannot modify user with id=#{params[:id]} - not authorised" }, 403)
    end
  end

  desc 'Create user'
  params do
    requires :user, type: Hash do
      requires :first_name, type: String, desc: 'New first name for user'
      requires :last_name, type: String, desc: 'New last name for user'
      requires :email, type: String, desc: 'New email address for user'
      optional :student_id, type: String, desc: 'New student_id for user'
      requires :username, type: String,   desc: 'New username for user'
      requires :nickname, type: String,   desc: 'New nickname for user'
      requires :system_role, type: String, desc: 'New system role for user [Admin, Auditor, Convenor, Tutor, Student]'
    end
  end
  post '/users' do
    #
    # Only admins and convenors can create users
    #
    unless authorise? current_user, User, :create_user
      error!({ error: 'Not authorised to create new users' }, 403)
    end

    user_parameters = ActionController::Parameters.new(params)
                                                  .require(:user)
                                                  .permit(
                                                    :first_name,
                                                    :last_name,
                                                    :student_id,
                                                    :email,
                                                    :username,
                                                    :nickname
                                                  )

    # have to translate the system_role -> role
    user_parameters[:role] = params[:user][:system_role]

    #
    # Give new user their new role
    #
    new_role = Role.with_name(user_parameters[:role])
    if new_role.nil?
      error!({ error: "No such role name #{user_parameters[:role]}" }, 403)
    end

    #
    # Check permission to create user with this role
    #
    unless authorise? current_user, User, :create_user, User.get_change_role_perm_fn, [:nil, new_role.name.downcase.to_sym]
      error!({ error: "Not authorised to create new users with role #{new_role.name}" }, 403)
    end

    # update :role to actual Role object rather than String type
    user_parameters[:role] = new_role

    logger.info "#{current_user.username}: Created new user #{user_parameters[:username]} with role #{new_role.name}"

    user = User.create!(user_parameters)
    present user, with: Entities::UserEntity
  end

  desc 'Upload CSV of users'
  params do
    requires :file, type: File, desc: 'CSV upload file.'
  end
  post '/csv/users' do
    unless authorise? current_user, User, :upload_csv
      error!({ error: 'Not authorised to upload CSV of users' }, 403)
    end

    if params[:file].blank?
      error!({ error: "No file uploaded" }, 403)
    end

    path = params[:file][:tempfile].path

    # check mime is correct before uploading
    ensure_csv!(path)

    # Actually import...
    User.import_from_csv(current_user, File.new(path))
  end

  desc 'Download CSV of all users'
  get '/csv/users' do
    unless authorise? current_user, User, :download_system_csv
      error!({ error: 'Not authorised to download CSV of all users' }, 403)
    end

    content_type 'application/octet-stream'
    header['Content-Disposition'] = 'attachment; filename=doubtfire_users.csv'
    header['Access-Control-Expose-Headers'] = 'Content-Disposition'
    env['api.format'] = :binary
    User.export_to_csv
  end
end

require 'grape'

class NotificationsApi < Grape::API
  helpers AuthenticationHelpers
  helpers AuthorisationHelpers

  before do
    authenticated?
  end

  desc 'Get the current user notifications'
  params do
    optional :unread_only, type: Boolean, default: false, desc: 'Only return unread notifications'
  end
  get '/notifications' do
    notifications = current_user.notifications.recent_first
    notifications = notifications.unread if params[:unread_only]

    present notifications, with: Entities::NotificationEntity
  end

  desc 'Get the current user unread notification count'
  get '/notifications/unread_count' do
    { count: current_user.notifications.unread.count }
  end

  desc 'Mark a notification as read'
  params do
    requires :id, type: Integer, desc: 'The notification id'
  end
  put '/notifications/:id/read' do
    notification = current_user.notifications.find(params[:id])
    notification.mark_read!

    present notification, with: Entities::NotificationEntity
  end

  desc 'Mark all of the current user notifications as read'
  put '/notifications/read_all' do
    # rubocop:disable Rails/SkipsModelValidations
    current_user.notifications.unread.update_all(read_at: Time.zone.now)
    # rubocop:enable Rails/SkipsModelValidations

    status 200
    { success: true }
  end

  desc 'Delete the current user notifications up to a confirmed boundary'
  params do
    requires :through_id,
             type: Integer,
             values: ->(value) { value.positive? },
             desc: 'Delete only notifications whose id is at or below this value'
  end
  delete '/notifications' do
    # The boundary is part of the contract, not an optimisation. A notification
    # can arrive after the browser has shown "Delete all" and while the user is
    # reading the confirmation. Deleting the unbounded association here would
    # remove that unseen notification too. Scoping through current_user keeps
    # the operation account-local in the same way as the single-row endpoint.
    deleted_count = current_user.notifications
                                .where('notifications.id <= ?', params[:through_id])
                                .delete_all

    status 200
    { success: true, deleted_count: deleted_count }
  end

  desc 'Delete a notification'
  params do
    requires :id, type: Integer, desc: 'The notification id'
  end
  delete '/notifications/:id' do
    notification = current_user.notifications.find(params[:id])
    notification.destroy!

    status 200
    { success: true }
  end
end

require 'grape'

class PushSubscriptionsApi < Grape::API
  helpers AuthenticationHelpers
  helpers AuthorisationHelpers

  before do
    authenticated?
  end

  desc 'Get the push subscriptions belonging to the current user'
  get '/push_subscriptions' do
    present current_user.push_subscriptions.order(:id), with: Entities::PushSubscriptionEntity
  end

  # The endpoint posted here is later used as the target of an outbound request
  # by PushNotificationService, so it is not accepted as free text.
  # PushSubscription validates it against PUSH_SERVICE_HOSTS, and a URL that is
  # not an https push service URL fails with a 400 from the handler in
  # api_root.rb. PushNotificationService checks again before it sends.
  desc 'Register this browser to receive push notifications'
  params do
    requires :endpoint, type: String, desc: 'The push service URL, from PushSubscription.endpoint'
    requires :p256dh, type: String, desc: 'The browser public key, from PushSubscription.getKey("p256dh")'
    requires :auth, type: String, desc: 'The browser auth secret, from PushSubscription.getKey("auth")'
  end
  post '/push_subscriptions' do
    subscription = current_user.push_subscriptions.find_by(endpoint: params[:endpoint])

    # Not ours, or not stored yet. An endpoint identifies a browser rather than
    # a person, so an endpoint held by another user means someone has signed in
    # on a machine that account used. Move the registration across instead of
    # failing on the unique index.
    #
    # This is the only lookup in this file that is not scoped to current_user,
    # and it is safe. The push service delivers to that browser no matter which
    # row owns it, and the payload is encrypted to the keys posted here. Taking
    # over someone else's endpoint cannot read their notifications, it can only
    # stop them arriving, and you need the endpoint URL to try it at all.
    subscription ||= PushSubscription.find_by(endpoint: params[:endpoint]) || PushSubscription.new

    subscription.assign_attributes(
      user: current_user,
      endpoint: params[:endpoint],
      p256dh: params[:p256dh],
      auth: params[:auth]
    )
    subscription.save!

    present subscription, with: Entities::PushSubscriptionEntity
  end

  desc 'Stop this browser receiving push notifications'
  params do
    requires :endpoint, type: String, desc: 'The push service URL to remove'
  end
  delete '/push_subscriptions' do
    subscription = current_user.push_subscriptions.find_by!(endpoint: params[:endpoint])
    subscription.destroy!

    status 200
    { success: true }
  end
end

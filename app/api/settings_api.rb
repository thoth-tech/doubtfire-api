require 'grape'

class SettingsApi < Grape::API
  helpers AuthenticationHelpers

  before do
    authenticated?
  end

  desc 'Return authenticated feature configuration for the Doubtfire front end'
  get '/settings' do
    response = {
      overseerEnabled: Doubtfire::Application.config.overseer_enabled,
      tiiEnabled: TurnItIn.enabled?,
      d2lEnabled: D2lIntegration.enabled?,

      # Web push. The VAPID *public* key is not a secret — the browser has to
      # send it to the push service to subscribe at all. Serving it here means it
      # is configured in one place instead of being copied into the front end and
      # going stale the first time the keys are rotated.
      #
      # Blank when push is not configured, which is how the client knows not to
      # offer the opt-in.
      pushEnabled: PushNotificationService.configured?,
      vapidPublicKey: ENV.fetch('DOUBTFIRE_VAPID_PUBLIC_KEY', nil).presence
    }

    present response, with: Grape::Presenters::Presenter
  end
end

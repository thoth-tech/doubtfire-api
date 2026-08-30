require 'grape'

class SettingsPublicApi < Grape::API
  # This endpoint is required before sign-in.
  # Keep this response explicitly allowlisted.
  desc 'Return public branding details for the Doubtfire front end'
  get '/settings/public' do
    response = {
      externalName: Doubtfire::Application.config.institution[:product_name],
      hasLogo: Doubtfire::Application.config.institution[:has_logo],
      logoUrl: Doubtfire::Application.config.institution[:logo_url],
      logoLinkUrl: Doubtfire::Application.config.institution[:logo_link_url]
    }

    present response, with: Grape::Presenters::Presenter
  end

  desc 'Return public privacy policy details'
  get '/settings/privacy' do
    response = {
      privacy: Doubtfire::Application.config.institution[:privacy],
      plagiarism: Doubtfire::Application.config.institution[:plagiarism]
    }

    present response, with: Grape::Presenters::Presenter
  end
end

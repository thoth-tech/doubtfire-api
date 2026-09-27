# frozen_string_literal: true

require 'grape'
require Rails.root.join('lib/demo_data/all_features_scenario')

class DemoScenarioApi < Grape::API
  helpers AuthenticationHelpers

  before do
    header 'Cache-Control', 'private, no-store'
    authenticated?
  end

  desc 'Get the guarded local mobile-feedback demo scenario contract',
       tags: ['demo'],
       summary: 'Get guarded local demo scenario'
  get '/demo/scenario' do
    DemoData::AllFeaturesScenario.contract_for(user: current_user)
  rescue DemoData::AllFeaturesScenario::SafetyError
    error!({ error: 'Not found.' }, 404)
  end
end

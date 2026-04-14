# app/services/effort_prediction_service.rb

require 'net/http'
require 'json'

class EffortPredictionService
  TORCHSERVE_URL = ENV.fetch("TORCHSERVE_URL", "http://effort-predictor:8080/predictions/effort-predictor")

  def self.predict(features)
    uri = URI(TORCHSERVE_URL)
    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{ENV.fetch('TORCHSERVE_INFERENCE_KEY', nil)}"
    }
    body = { features: features }.to_json

    response = Net::HTTP.post(uri, body, headers)

    if response.is_a?(Net::HTTPSuccess)
      parsed = begin
        JSON.parse(response.body)
      rescue StandardError
        response.body
      end
      parsed.is_a?(Hash) ? parsed["predicted_effort"] || parsed.values.first : parsed
    else
      Rails.logger.error("TorchServe error: #{response.code} #{response.body}")
      nil
    end
  end
end

require 'grape'

class TaskDownloadsController < ApplicationController
  include AuthenticationHelpers
  include AuthorisationHelpers
  include LogHelper

  class MyException < RuntimeError
    attr_reader :status

    def initialize(status)
      @status = status
    end
  end

  def error!(message, status = options[:default_status], _headers = {}, _backtrace = [])
    raise MyException.new(status), message
  end

  # desc "Retrieve tasks for a unit"
  def index
    unless authenticated?
      error!({ error: "Not authorised to download tasks for unit '#{params[:id]}'" }, 401)
    end

    unit = Unit.find(params[:id])

    unless authorise? current_user, unit, :get_students
      error!({ error: "Not authorised to download tasks for unit '#{params[:id]}'" }, 401)
    end

    td = unit.task_definitions.find(params[:task_def_id])

    output_zip = unit.get_task_submissions_zip(current_user, td)

    error!({ error: 'No files to download' }, 403) if output_zip.nil?

    # Set download headers...
    # content_type "application/octet-stream"
    download_id = "#{Time.zone.now.strftime('%Y-%m-%d %H:%m:%S')}-#{unit.code}-#{td.abbreviation}-#{current_user.username}-files"
    download_id.gsub! /[\\\/]/, '-'
    download_id = FileHelper.sanitized_filename(download_id)
    # header['Content-Disposition'] = "attachment; filename=#{download_id}.zip"
    # env['api.format'] = :binary

    logger.debug "Downloading task for #{td.abbreviation} from #{output_zip}"

    send_file output_zip, content_type: 'application/octet-stream', disposition: "attachment; filename=#{download_id}.zip"
  rescue MyException => e
    render json: e.message, status: e.status
  end

  # prediction effort function

  protect_from_forgery with: :null_session # allow API POST without CSRF token
  # skip_before_action :verify_authenticity_token, only: [:predict_effort]

  # def predict_effort
  #   features = params[:features] # expects an array of numbers
  #   effort = EffortPredictionService.predict(features)

  #   if effort
  #     render json: { predicted_effort: effort }
  #   else
  #     render json: { error: "Prediction failed" }, status: :unprocessable_entity
  #   end
  # end

  # def predict_effort
  #   features = params[:features]

  #   # Call TorchServe
  #   uri = URI("http://effort-predictor:8080/predictions/effort-predictor")
  #   response = Net::HTTP.post(uri, features.to_json, { "Content-Type" => "application/json" })

  #   # Parse TorchServe output
  #   prediction = JSON.parse(response.body)

  #   # Handle array vs single value
  #   prediction_value = prediction.is_a?(Array) ? prediction.first : prediction

  #   # Return clean JSON
  #   render json: { predicted_effort: prediction_value }
  # end

  # def predict_effort
  #   features = params[:features]

  #   # Call TorchServe
  #   uri = URI("http://effort-predictor:8080/predictions/effort-predictor")
  #   response = Net::HTTP.post(uri, features.to_json, { "Content-Type" => "application/json" })

  #   # Debug log raw response (optional)
  #   Rails.logger.info("TorchServe raw response: #{response.body}")

  #   # Parse TorchServe output
  #   prediction = JSON.parse(response.body) rescue response.body

  #   # Handle array vs single value
  #   prediction_value =
  #     if prediction.is_a?(Array)
  #       prediction.first
  #     elsif prediction.is_a?(Hash) && prediction["prediction"]
  #       prediction["prediction"]
  #     else
  #       prediction
  #     end

  #   # Return clean JSON
  #   render json: { predicted_effort: prediction_value }
  # end

  # def predict_effort
  #   features = params[:features]

  #   # Call TorchServe
  #   uri = URI("http://effort-predictor:8080/predictions/effort-predictor")
  #   response = Net::HTTP.post(uri, features.to_json, { "Content-Type" => "application/json" })

  #   # Debug log raw response
  #   Rails.logger.info("TorchServe raw response: #{response.body}")

  #   # Parse TorchServe output safely
  #   prediction = begin
  #     JSON.parse(response.body)
  #   rescue JSON::ParserError
  #     response.body
  #   end

  #   # Normalize output
  #   prediction_value =
  #     if prediction.is_a?(Array)
  #       prediction.first
  #     elsif prediction.is_a?(Hash) && prediction["prediction"]
  #       prediction["prediction"]
  #     else
  #       prediction
  #     end

  #   # Return clean JSON
  #   render json: { predicted_effort: prediction_value }
  # end

  # def predict_effort
  #   features = params[:features]

  #   # Call TorchServe
  #   uri = URI("http://effort-predictor:8080/predictions/effort-predictor")
  #   response = Net::HTTP.post(uri, features.to_json, { "Content-Type" => "application/json" })

  #   # Parse TorchServe output safely
  #   prediction = begin
  #     JSON.parse(response.body)
  #   rescue JSON::ParserError
  #     response.body
  #   end

  #   # Normalize output
  #   prediction_value =
  #     if prediction.is_a?(Array)
  #       prediction.first
  #     elsif prediction.is_a?(Hash) && prediction["prediction"]
  #       prediction["prediction"]
  #     else
  #       prediction
  #     end

  #   # Return clean JSON
  #   render json: { predicted_effort: prediction_value }
  # end

  # this one was working
  #   def predict_effort
  #     features = params[:features]

  #     # Call TorchServe
  #     uri = URI("http://effort-predictor:8080/predictions/effort-predictor")
  #     response = Net::HTTP.post(uri, features.to_json, { "Content-Type" => "application/json" })

  #     # Parse TorchServe output safely
  #     prediction = JSON.parse(response.body) rescue response.body

  #     # Normalize output
  #     prediction_value =
  #       case prediction
  #       when Array
  #         prediction.first
  #       when Hash
  #         prediction["prediction"] || prediction.values.first
  #       else
  #         prediction
  #       end

  #     # Force JSON response
  #     render json: { predicted_effort: prediction_value }
  #   end
  # end

  # POST /tasks/predict_effort
  def predict_effort
    features = params[:features]

    if features.blank?
      render json: { error: "Features parameter is required" }, status: :bad_request
      return
    end

    uri = URI("http://localhost:8080/predictions/effort-predictor")
    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{ENV.fetch('TORCHSERVE_INFERENCE_KEY', nil)}"
    }
    body = { features: features }.to_json

    response = Net::HTTP.post(uri, body, headers)
    Rails.logger.info("TorchServe raw response: #{response.body}")

    if response.is_a?(Net::HTTPSuccess)
      prediction = begin
        JSON.parse(response.body)
      rescue StandardError
        response.body
      end
      prediction_value =
        case prediction
        when Array
          prediction.first
        when Hash
          prediction["predicted_effort"] || prediction.values.first
        else
          prediction
        end

      render json: { predicted_effort: prediction_value }
    else
      Rails.logger.error("TorchServe error: #{response.code} #{response.body}")
      render json: { error: "Prediction failed" }, status: :internal_server_error
    end
  end
end

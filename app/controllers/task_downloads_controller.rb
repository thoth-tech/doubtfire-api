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

  # POST /tasks/predict_effort
  def predict_effort
    features = params[:features]

    if features.blank?
      render json: { error: "Features parameter is required" }, status: :bad_request
      return
    end

    prediction_value = EffortPredictionService.predicted_effort(features)

    if prediction_value
      render json: { predicted_effort: prediction_value }
    else
      render json: { error: "Prediction failed" }, status: :internal_server_error
    end
  end

end

require "net/http"
require "json"

class PredictEffortJob
  include Sidekiq::Worker
  include Sidekiq::Status::Worker

  def perform(task_def_id, user_id)
    store initiator: user_id
    td = TaskDefinition.find(task_def_id)
    payload = build_payload(td)

    ml_url = ENV.fetch('ML_SERVICE_URL')
    if ml_url.blank?
      raise StandardError, "ML_SERVICE_URL is not configured"
    end
    Rails.logger.info("ML payload: #{payload.to_json}")

    response = Net::HTTP.post(
      URI("#{ml_url}predict"),
      payload.to_json,
      "Content-Type" => "application/json"
    )

    unless response.is_a?(Net::HTTPSuccess)
      raise StandardError, "ML service returned #{response.code}: #{response.body}"
    end
    result = JSON.parse(response.body)
    Rails.logger.info("FastAPI response: #{response.body}")
    td.update(predicted_effort: result["predicted_effort"])
    store result: result
  rescue StandardError => e
    Rails.logger.error("PredictEffortJob failed: #{e.message}")

    store(
      status: 'failed',
      message: e.message,
      result: { error: e.message }
    )

    raise e
  end

  private

  def build_payload(task_def)
    {
      estimated_hours: task_def.estimated_hours,
      target_grade: task_def.target_grade,
      start_date: task_def.start_date,
      due_date: task_def.due_date # ,
      # TODO: task sheet for TF-IDF
    }
  end
end

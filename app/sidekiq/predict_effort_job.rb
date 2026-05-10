require "net/http"
require "json"

class PredictEffortJob
  include Sidekiq::Worker

  def perform(task_def_id)
    td = TaskDefinition.find(task_def_id)
    payload = build_payload(td)
    Rails.logger.info("ML payload: #{payload.to_json}")
    response = Net::HTTP.post(
      URI("#{ENV.fetch('ML_SERVICE_URL')}predict"),
      payload.to_json,
      "Content-Type" => "application/json"
    )

    result = JSON.parse(response.body)
    Rails.logger.info("FastAPI response: #{response.body}")
    td.update(predicted_effort: result["predicted_effort"])
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

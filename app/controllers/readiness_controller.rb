class ReadinessController < ActionController::API
  def show
    head(ReadinessCheck.new.ready? ? :ok : :service_unavailable)
  end
end

# Ensure log outputs to stdout in development
if Rails.env.development? || Doubtfire::Application.config.log_to_stdout
  Rails.logger.broadcast_to(ActiveSupport::Logger.new($stdout, level: Rails.logger.level))
end

class FormatifFormatter < Logger::Formatter
  include ActiveSupport::TaggedLogging::Formatter

  # This method is invoked when a log event occurs
  def call(severity, timestamp, _progname, msg)
    remote_ip = Thread.current.thread_variable_get(:ip) || 'unknown'
    "#{timestamp},#{remote_ip},#{severity}: #{msg.to_s.gsub(/\n/, '\n')}\n"
  end
end

Rails.logger.formatter = FormatifFormatter.new

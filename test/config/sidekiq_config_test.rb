# frozen_string_literal: true

require 'test_helper'
require 'erb'
require 'yaml'

class SidekiqConfigTest < ActiveSupport::TestCase
  def test_production_worker_consumes_notification_and_submission_queues_before_default
    rendered = ERB.new(Rails.root.join('config/sidekiq.yml').read).result
    config = YAML.safe_load(rendered, permitted_classes: [Symbol], aliases: true)

    assert_equal %w[mailers notifications submissions default], config.fetch(:queues)
  end
end

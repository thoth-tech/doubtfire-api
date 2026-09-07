# frozen_string_literal: true

require 'test_helper'
require 'erb'
require 'yaml'

class SidekiqConfigTest < ActiveSupport::TestCase
  def test_production_worker_consumes_both_notification_channels_before_default
    rendered = ERB.new(Rails.root.join('config/sidekiq.yml').read).result
    config = YAML.safe_load(rendered, permitted_classes: [Symbol], aliases: true)

    assert_equal %w[mailers notifications default], config.fetch(:queues)
  end
end

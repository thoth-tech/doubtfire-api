# frozen_string_literal: true

class AggregatePeerProgressJob
  class AggregationError < StandardError; end

  include Sidekiq::Job
  include Sidekiq::Status::Worker
  include LogHelper
  include ApplicationHelper

  sidekiq_options lock: :until_executed,
                  lock_args_method: lambda { |args|
                    [args.first || 'all-active-units']
                  },
                  on_conflict: :reject,
                  retry: 3

  def perform(unit_id = nil)
    return enqueue_active_units if unit_id.blank?

    aggregate_unit(Unit.find(unit_id))
  rescue StandardError => e
    log_unit_id = unit_id.presence || 'all-active-units'
    failure_message =
      "Peer progress aggregation failed for unit_id=#{log_unit_id}: " \
      "#{e.class.name}"

    logger.error(failure_message)
    raise AggregationError, failure_message, cause: nil
  end

  private

  def enqueue_active_units
    logger.info(
      'Queueing peer progress aggregation for active units...'
    )

    # Only units whose convenor has opted in. Aggregating the rest would store
    # derived cohort statistics for units that never enabled the feature, and
    # the endpoint returns early on peer_progress_enabled? so those rows could
    # never be served anyway.
    Unit.active_units.where(peer_progress_enabled: true).find_each do |unit|
      self.class.perform_async(unit.id)
    end

    logger.info(
      'Queued peer progress aggregation jobs.'
    )
  end

  def aggregate_unit(unit)
    unless unit.active?
      logger.info(
        "Skipping peer progress aggregation for inactive unit_id=#{unit.id}"
      )
      return
    end

    unless unit.peer_progress_enabled?
      logger.info(
        "Skipping peer progress aggregation for unit_id=#{unit.id}, " \
        'peer progress is not enabled'
      )
      return
    end

    logger.info(
      "Starting peer progress aggregation for unit_id=#{unit.id}..."
    )

    at(0)
    total(1)

    PeerProgressAggregationService.call(
      unit: unit,
      calculated_at: Time.zone.now
    )

    at(1)

    logger.info(
      "Completed peer progress aggregation for unit_id=#{unit.id}."
    )
  end
end

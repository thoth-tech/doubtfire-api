# frozen_string_literal: true

# On-demand plagiarism rescan for a single unit. Wraps Unit#check_jplag_similarity
# so a convenor can trigger a scan from the product instead of waiting for the
# nightly cron, which is the only thing that ran it before.
#
# Locked until_executed and rejecting on conflict, keyed on the unit id, so two
# convenors pressing the button cannot queue duplicate scans for the same unit.
class CheckUnitSimilarityJob
  include Sidekiq::Job
  include Sidekiq::Status::Worker
  include LogHelper
  include ApplicationHelper

  sidekiq_options lock: :until_executed,
                  lock_args_method: ->(args) { [args.first] },
                  on_conflict: :reject,
                  retry: false

  # Two entry points, both keyed on the unit id so a nightly scan and an on-demand
  # scan of the same unit reject each other rather than racing on the shared
  # tmp/jplag working directory.
  #
  # - No unit id: the config/schedule.yml cron enqueues this way. It fans out one
  #   child job per active unit with force off, so only units whose files or task
  #   definitions changed are rescanned, and one unit's failure does not abort the
  #   rest. Each child locks on its own unit id.
  # - A unit id: one unit is scanned. The endpoint passes force true so a threshold
  #   change alone is enough to rescan, which is the gap this path exists to close;
  #   the nightly children pass force false.
  #
  # task_definition_id is accepted so the queued job and its lock key are stable if
  # per-definition scanning is added later. check_jplag_similarity is unit-scoped
  # today, so the scan currently covers the whole unit regardless.
  def perform(unit_id = nil, force = nil, task_definition_id = nil)
    at(0)
    total(1)

    if unit_id.present?
      logger.info "Starting similarity scan for unit #{unit_id} (force=#{force})..."
      if task_definition_id.present?
        logger.info "Similarity scan requested for task definition #{task_definition_id}; " \
                    "running a unit-wide scan because check_jplag_similarity is unit-scoped."
      end
      Unit.find(unit_id).check_jplag_similarity(force: force)
    else
      logger.info 'Fanning out nightly similarity scans for active units...'
      Unit.active_units.find_each { |unit| CheckUnitSimilarityJob.perform_async(unit.id, false) }
    end

    at(1)
    logger.info 'Completed similarity scan dispatch!'
  rescue StandardError => e
    logger.error e
    raise e
  end
end

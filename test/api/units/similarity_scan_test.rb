require 'test_helper'

# Covers POST /units/:id/similarity/scan, the on-demand plagiarism rescan.
class UnitsSimilarityScanApiTest < ActiveSupport::TestCase
  include Rack::Test::Methods
  include TestHelpers::AuthHelper
  include TestHelpers::JsonHelper

  def app
    Rails.application
  end

  # A tutor is not one of the roles granted :run_similarity_scan, so the endpoint
  # must refuse before it queues anything.
  def test_tutor_cannot_run_similarity_scan
    unit = FactoryBot.create(:unit, with_students: false, task_count: 0)
    tutor = FactoryBot.create(:user, :tutor)
    unit.employ_staff(tutor, Role.tutor)

    add_auth_header_for(user: tutor)
    post "/api/units/#{unit.id}/similarity/scan"

    assert_equal 403, last_response.status, last_response_body
  end

  # A scan recorded in the last 30 minutes puts the unit inside the cooldown, so a
  # convenor's request is rate limited rather than queuing a second scan.
  def test_similarity_scan_is_rate_limited_within_the_cooldown
    unit = FactoryBot.create(:unit, with_students: false, task_count: 0)
    unit.update!(last_plagarism_scan: Time.zone.now)

    add_auth_header_for(user: unit.main_convenor_user)
    post "/api/units/#{unit.id}/similarity/scan"

    assert_equal 429, last_response.status, last_response_body
  end

  # sidekiq-unique-jobs returns nil when its :reject conflict strategy refuses a
  # duplicate. That is distinct from the completed-scan cooldown above: the first
  # job may still be queued or running and therefore has not stamped the unit yet.
  def test_similarity_scan_returns_conflict_when_duplicate_enqueue_is_rejected
    unit = FactoryBot.create(:unit, with_students: false, task_count: 0)

    add_auth_header_for(user: unit.main_convenor_user)
    CheckUnitSimilarityJob.stub(:perform_async, nil) do
      post "/api/units/#{unit.id}/similarity/scan"
    end

    assert_equal 409, last_response.status, last_response_body
    assert_equal 'A similarity scan is already queued or running for this unit.', last_response_body['error']
  end
end

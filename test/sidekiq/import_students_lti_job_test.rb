# frozen_string_literal: true

require 'test_helper'

class ImportStudentsLtiJobTest < ActiveSupport::TestCase
  def test_stores_readable_error_message_when_member_import_raises
    unit = create(
      :unit,
      with_students: false,
      student_count: 0
    )

    members = [
      {
        "user_id" => "test-user",
        "name" => "Test User",
        "given_name" => "Test",
        "family_name" => "User",
        "email" => "test@example.com",
        "ext_user_username" => "test-user",
        "roles" => ["Learner"]
      }
    ]

    stored_result = nil
    job = ImportStudentsLtiJob.new

    job.stub(
      :user_for_asserted_identity,
      ->(**_kwargs) { raise StandardError, "test import failure" }
    ) do
      job.stub(
        :store,
        ->(**kwargs) { stored_result = kwargs[:result] }
      ) do
        job.perform(unit.id, members)
      end
    end

    results = JSON.parse(stored_result)

    assert_equal 1, results["errors"].count

    message = results["errors"].first["message"]

    assert_equal "StandardError: test import failure", message
  end

  def test_logs_the_exception_when_member_import_raises
    unit = create(
      :unit,
      with_students: false,
      student_count: 0
    )

    members = [
      {
        "user_id" => "test-user",
        "name" => "Test User",
        "given_name" => "Test",
        "family_name" => "User",
        "email" => "test@example.com",
        "ext_user_username" => "test-user",
        "roles" => ["Learner"]
      }
    ]

    error = StandardError.new("test import failure")
    logged_error = nil

    logger = Object.new
    logger.define_singleton_method(:info) { |_message| }
    logger.define_singleton_method(:error) { |exception| logged_error = exception }

    job = ImportStudentsLtiJob.new

    job.stub(:logger, logger) do
      job.stub(
        :user_for_asserted_identity,
        ->(**_kwargs) { raise error }
      ) do
        job.stub(:store, ->(**_kwargs) {}) do
          job.perform(unit.id, members)
        end
      end
    end

    assert_same error, logged_error
  end
end

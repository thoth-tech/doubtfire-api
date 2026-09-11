# frozen_string_literal: true

require 'test_helper'

# PR-FILE-05 – Portfolio upload size limit
#
# The portfolio upload endpoint (POST /api/submission/project/:id/portfolio)
# previously enforced no file size limit at all. This test confirms the fix:
# a part exceeding Doubtfire::Application.config.max_file_size is rejected
# with 413, and confirms the rejected file is never copied into the
# project's portfolio directory (the status code alone does not prove that).
class PortfolioApiTest < ActiveSupport::TestCase
  include Rack::Test::Methods
  include TestHelpers::AuthHelper

  def with_tempfile(extension, content = 'dummy content')
    Tempfile.create(['portfolio_size_test', extension]) do |f|
      f.write(content)
      f.flush
      yield f
    end
  end

  test 'rejects portfolio part exceeding the configured max_file_size and stores nothing' do
    original_max = Doubtfire::Application.config.max_file_size
    Doubtfire::Application.config.max_file_size = 1_024 # 1 KB

    unit    = FactoryBot.create(:unit, student_count: 1, task_count: 0)
    project = unit.active_projects.first

    add_auth_header_for(user: project.student)

    files_before = project.portfolio_files

    with_tempfile('.py', 'x' * 2_048) do |f|
      uploaded = Rack::Test::UploadedFile.new(f.path, 'text/plain', true)
      post "/api/submission/project/#{project.id}/portfolio",
           name: 'OversizedPart',
           kind: 'code',
           file0: uploaded
    end

    assert_equal 413, last_response.status,
                 "Expected 413 for a portfolio part exceeding max_file_size, got: #{last_response.body}"
    assert_match(/exceeds the \d+MB file limit/i, last_response.body)
    assert_equal files_before, project.portfolio_files,
                 'Rejected oversized portfolio upload must not add any file to the portfolio directory'
  ensure
    unit.destroy
    Doubtfire::Application.config.max_file_size = original_max
  end
end
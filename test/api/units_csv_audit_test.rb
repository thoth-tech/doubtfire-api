require 'test_helper'
require 'tempfile'

class UnitsCsvAuditTest < ActiveSupport::TestCase
  include Rack::Test::Methods
  include TestHelpers::AuthHelper
  include TestHelpers::JsonHelper
  include TestHelpers::TestFileHelper

  def app
    Rails.application
  end

  # Swap Rails.logger for a StringIO-backed logger for the duration of the
  # block and return everything written to it. The endpoints log through
  # Rails.logger explicitly, so the swap captures their lines.
  def with_captured_rails_log
    io = StringIO.new
    original = Rails.logger
    # Wrap in TaggedLogging so the request's own Rails::Rack::Logger.tagged call
    # still works while we are capturing.
    Rails.logger = ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new(io))
    begin
      yield
    ensure
      Rails.logger = original
    end
    io.string
  end

  def convenor_for(unit)
    convenor = FactoryBot.create :user, :convenor
    ur = unit.employ_staff convenor, Role.convenor
    unit.update(main_convenor: ur)
    convenor
  end

  def test_bulk_withdraw_writes_an_audit_line
    unit = FactoryBot.create :unit
    convenor = convenor_for(unit)
    student = unit.active_projects.first.user

    csv = Tempfile.new(['withdraw', '.csv'])
    csv.write("unit_code,username\n#{unit.code},#{student.username}\n")
    csv.rewind

    add_auth_header_for(user: convenor)

    log = with_captured_rails_log do
      post "/api/csv/units/#{unit.id}/withdraw",
           file: Rack::Test::UploadedFile.new(csv.path, 'text/csv')
    end

    refute_equal 403, last_response.status, last_response.body
    audit_line = log.lines.grep(/bulk withdraw by/).first
    assert_match(/bulk withdraw by user #{convenor.id} on unit #{unit.id}: 1 withdrawn/, audit_line)
    assert_not_includes audit_line, convenor.username
  ensure
    csv&.close!
  end

  def test_class_csv_export_writes_an_audit_line
    unit = FactoryBot.create :unit
    convenor = convenor_for(unit)

    add_auth_header_for(user: convenor)

    log = with_captured_rails_log do
      get "/api/csv/units/#{unit.id}"
    end

    assert_equal 200, last_response.status, last_response.body
    audit_line = log.lines.grep(/class CSV export by/).first
    assert_match(/class CSV export by user #{convenor.id} on unit #{unit.id}/, audit_line)
    assert_not_includes audit_line, convenor.username
  end
end

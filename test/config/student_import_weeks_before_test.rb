require "test_helper"

class StudentImportWeeksBeforeTest < ActiveSupport::TestCase
  def application_rb_source
    File.read(Rails.root.join('config', 'application.rb'))
  end

  def test_prefers_correct_spelling_with_fallback_to_misspelled_variable
    assert_match(
      /ENV\.fetch\('DF_IMPORT_STUDENTS_WEEKS_BEFORE'\)\s*\{\s*ENV\.fetch\('DF_IMPORT_STUDENTS_WEEKS_BEFPRE',\s*1\)\s*\}/,
      application_rb_source,
      "Expected config/application.rb to prefer DF_IMPORT_STUDENTS_WEEKS_BEFORE, falling back to the misspelled DF_IMPORT_STUDENTS_WEEKS_BEFPRE"
    )
  end

  def test_no_longer_reads_only_the_misspelled_variable
    refute_match(
      /ENV\.fetch\('DF_IMPORT_STUDENTS_WEEKS_BEFPRE',\s*1\)\.to_f\s*\*\s*1\.week/,
      application_rb_source,
      "config/application.rb should not read DF_IMPORT_STUDENTS_WEEKS_BEFPRE as the sole/primary source"
    )
  end
end

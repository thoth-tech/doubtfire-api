require 'test_helper'

# OnTrack writes some comments itself. They are stored against the tutor for the
# task, because a comment needs an author, so without a marker they read as
# something that person wrote.
class AutomatedCommentTest < ActiveSupport::TestCase
  def build_comment(text)
    comment = TaskComment.new
    comment.comment = text
    comment
  end

  def test_recognises_both_markers_ontrack_writes
    assert build_comment('**Automated Message:** This task was extended.').automated?
    assert build_comment('**Automated Comment**: Something went wrong.').automated?
  end

  def test_a_person_writing_about_automation_is_not_automated
    refute build_comment('The **Automated Message:** you got was wrong, sorry.').automated?
    refute build_comment('Nice work on this one.').automated?
    refute build_comment('').automated?
    refute build_comment(nil).automated?
  end

  # The marker closes with bold that AUTOMATED_PREFIXES stops short of, because
  # that constant matches the same literal the existing LIKE queries use. A
  # strip that only removed the prefix left the closing asterisks behind.
  def test_strips_the_whole_marker_including_the_bold_that_closes_it
    comment = build_comment('**Automated Message:** This task was extended by 1 week.')
    assert_equal 'This task was extended by 1 week.', comment.comment_without_automated_prefix

    other = build_comment('**Automated Comment**: Something went wrong.')
    assert_equal 'Something went wrong.', other.comment_without_automated_prefix

    written = build_comment('Nice work on this one.')
    assert_equal 'Nice work on this one.', written.comment_without_automated_prefix
  end
end

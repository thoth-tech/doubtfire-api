# frozen_string_literal: true

module DemoData
  # Canonical semantic contract for the isolated mobile-feedback walkthrough.
  #
  # This module intentionally contains no database IDs. All dynamic identifiers
  # are resolved only after the guarded all-features seed has been materialised.
  # The web client consumes the authenticated /api/demo/scenario projection and
  # never inserts this contract into normal project, unit, task, notification or
  # group caches.
  module MobileFeedbackScenario
    SCHEMA_VERSION = 1
    SCENARIO_ID = 'mobile-feedback-v1'
    PRIMARY_UNIT_CODE = 'DEMO10001'
    PPI_TASK_ABBREVIATION = 'DUE7'

    CURRENT_UNIT_CODES = %w[
      DEMO10001
      DEMO20007
      DEMO30046
      DEMO30243
    ].freeze
    PREVIOUS_UNIT_CODE = 'DEMO09999'
    UNIT_CODES = [*CURRENT_UNIT_CODES, PREVIOUS_UNIT_CODE].freeze

    UNIT_NAMES = {
      'DEMO10001' => 'Foundations of OnTrack',
      'DEMO20007' => 'Active Learning Studio',
      'DEMO30046' => 'Applied Project Delivery',
      'DEMO30243' => 'Professional Practice',
      PREVIOUS_UNIT_CODE => 'Previous Study Portfolio'
    }.freeze

    UPLOADED_STATUSES = %i[
      ready_for_feedback
      fix_and_resubmit
      redo
      complete
      fail
    ].freeze

    TASK_BLUEPRINTS = [
      {
        abbreviation: 'OVERDUE', name: 'Overdue Foundations',
        start_offset: -21, target_offset: -1,
        status: :not_started, weighting: 3
      },
      {
        abbreviation: 'FUTURE', name: 'Future Planning',
        start_offset: 10, target_offset: 14,
        status: :not_started, weighting: 2
      },
      {
        abbreviation: 'DUE3', name: 'Due Within Three Days',
        start_offset: -10, target_offset: 2,
        status: :working_on_it, weighting: 6
      },
      {
        abbreviation: 'WORK', name: 'Work in Progress',
        start_offset: -5, target_offset: 10,
        status: :working_on_it, weighting: 5
      },
      {
        abbreviation: PPI_TASK_ABBREVIATION,
        name: 'Due Within Seven Days',
        start_offset: -7, target_offset: 6,
        status: :ready_for_feedback, weighting: 4
      },
      {
        abbreviation: 'AWAITING', name: 'Awaiting Tutor Feedback',
        start_offset: -12, target_offset: 5,
        status: :ready_for_feedback, weighting: 4
      },
      {
        abbreviation: 'RESUBMIT', name: 'Fix and Resubmit',
        start_offset: -18, target_offset: 4,
        status: :fix_and_resubmit, weighting: 4
      },
      {
        abbreviation: 'REDO', name: 'Redo Required',
        start_offset: -20, target_offset: 8,
        status: :redo, weighting: 4
      },
      {
        abbreviation: 'DONE', name: 'Completed Practice',
        start_offset: -28, target_offset: -7,
        status: :complete, weighting: 1
      },
      {
        abbreviation: 'FAILED', name: 'Not Yet Passed',
        start_offset: -24, target_offset: -5,
        status: :fail, weighting: 3
      }
    ].map(&:freeze).freeze

    NON_PRIMARY_TARGET_OVERRIDES = { 'DUE3' => 9 }.freeze

    EXPECTED_TASK_STATUS_PERCENTAGES = {
      not_started: 20.0,
      working_on_it: 20.0,
      ready_for_feedback: 20.0,
      fix_and_resubmit: 10.0,
      redo: 10.0,
      complete: 10.0,
      fail: 10.0
    }.freeze

    # Peer-only counts. The authenticated viewer is added by the normal task
    # materialisation path, then excluded by PeerProgressViewerPolicy before any
    # values are returned. Raw counts never cross the API boundary.
    PPI_PEER_STATUS_COUNTS = {
      'DEMO10001' => {
        not_started: 4, working_on_it: 5, ready_for_feedback: 4,
        fix_and_resubmit: 3, redo: 3, complete: 3, fail: 2
      },
      'DEMO20007' => {
        not_started: 2, working_on_it: 5, ready_for_feedback: 5,
        fix_and_resubmit: 2, redo: 2, complete: 5, fail: 3
      },
      'DEMO30046' => {
        not_started: 7, working_on_it: 4, ready_for_feedback: 3,
        fix_and_resubmit: 2, redo: 2, complete: 4, fail: 2
      }
    }.transform_values(&:freeze).freeze
    PPI_UNAVAILABLE_UNIT_CODE = 'DEMO30243'

    NOTIFICATIONS = [
      {
        key: 'new-task', type: 'task', event: 'new_task_available',
        message: 'A new task is available in DEMO10001.',
        task: 'FUTURE', age: 20.minutes, read: false
      },
      {
        key: 'due-soon', type: 'task', event: 'task_due_soon',
        message: 'DUE3 in DEMO10001 is due soon.',
        task: 'DUE3', age: 45.minutes, read: false
      },
      {
        key: 'date-changed', type: 'task', event: 'task_due_date_changed',
        message: 'The due date for DUE7 has changed.',
        task: PPI_TASK_ABBREVIATION, age: 90.minutes, read: false
      },
      {
        key: 'feedback', type: 'feedback', event: 'task_comment_created',
        message: 'You have new feedback in OnTrack.',
        task: 'AWAITING', suffix: '/feedback', age: 3.hours, read: false
      },
      {
        key: 'status-changed', type: 'task', event: 'task_status_changed',
        message: 'RESUBMIT has changed status.',
        task: 'RESUBMIT', age: 8.hours, read: true
      },
      {
        key: 'extension', type: 'extension', event: 'extension_assessed',
        message: 'Your extension request has been assessed.',
        task: 'WORK', age: 1.day, read: true
      },
      {
        key: 'portfolio', type: 'portfolio', event: 'portfolio_received',
        message: 'Your portfolio is ready to review.',
        task: 'DONE', age: 2.days, read: true
      }
    ].map(&:freeze).freeze

    GROUP = {
      key: 'project-team', unit_code: 'DEMO20007',
      group_set_name: 'Demo project teams', tutorial: 'ST1',
      name: 'Team Indigo', capacity: 4, member_count: 3
    }.freeze

    WALKTHROUGH_LINKS = [
      { key: 'tasks', label: 'Tasks and CPD', unit_code: PRIMARY_UNIT_CODE,
        route: :dashboard },
      { key: 'ppi', label: 'Peer Progress Indicator',
        unit_code: PRIMARY_UNIT_CODE, task: PPI_TASK_ABBREVIATION,
        route: :task, query: 'walkthrough=ppi' },
      { key: 'burndown', label: 'Progress Burndown',
        unit_code: PRIMARY_UNIT_CODE, route: :dashboard,
        query: 'walkthrough=burndown' },
      { key: 'notifications', label: 'Notifications', route: :notifications }
    ].map(&:freeze).freeze
  end
end

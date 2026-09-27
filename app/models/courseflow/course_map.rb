# frozen_string_literal: true

module Courseflow
  # A student's complete plan is one row, so failed saves cannot leave half a plan.
  class CourseMap < ApplicationRecord
    self.table_name = 'courseflow_maps'
    attribute :periods, :json
    attribute :slots, :json

    PERIOD_KEYS = %w[year trimester].freeze
    SLOT_KEYS = %w[unit_code year trimester position].freeze

    belongs_to :user
    belongs_to :course, class_name: 'Courseflow::Course'

    validates :name, presence: true, length: { maximum: 200 }
    validate :immutable_references, on: :update
    validate :validate_plan

    def as_plan
      planning_issues = issues
      attributes.slice('id', 'course_id', 'name', 'lock_version', 'periods', 'slots').merge(
        'issues' => planning_issues,
        'complete' => planning_issues.empty?,
        'updated_at' => updated_at.iso8601(6)
      )
    end

    # These are planning checks only, not an assessment of degree eligibility.
    def issues
      scheduled = slots.index_by { |slot| slot['unit_code'] }
      result = []
      course.units.each do |unit|
        slot = scheduled[unit['code']]
        if unit['required'] && slot.nil?
          result << issue('missing_required', "Add required unit #{unit['code']}.", unit['code'])
        end
        next unless slot

        unless unit['offered_trimesters'].include?(slot['trimester'])
          result << issue('unavailable_trimester', "#{unit['code']} is not offered in trimester #{slot['trimester']}.", unit['code'])
        end
        unit['prerequisites'].each do |prerequisite|
          preceding = scheduled[prerequisite]
          next if preceding && period_number(preceding) < period_number(slot)

          result << issue('prerequisite', "Schedule #{prerequisite} before #{unit['code']}.", unit['code'])
        end
      end
      elective_codes = course.units.reject { |unit| unit['required'] }.pluck('code')
      elective_total = (scheduled.keys & elective_codes).length
      if elective_total != course.elective_count
        result << issue('elective_count', "Plan exactly #{course.elective_count} elective units; currently #{elective_total}.")
      end
      result
    end

    private

    def issue(code, message, unit_code = nil)
      { 'code' => code, 'message' => message }.tap { |value| value['unit_code'] = unit_code if unit_code }
    end

    def period_number(value)
      (value['year'] * 3) + value['trimester']
    end

    def immutable_references
      errors.add(:course_id, 'cannot change on a saved map') if will_save_change_to_course_id?
      errors.add(:user_id, 'cannot change on a saved map') if will_save_change_to_user_id?
    end

    def valid_period?(period)
      period.is_a?(Hash) && period['year'].is_a?(Integer) && period['year'].between?(2000, 2200) &&
        period['trimester'].is_a?(Integer) && period['trimester'].between?(1, 3)
    end

    def validate_plan
      unless periods.is_a?(Array) && periods.length.between?(1, 60) &&
             periods.all? { |period| valid_period?(period) && period.keys.sort == PERIOD_KEYS.sort }
        errors.add(:periods, 'must contain 1 to 60 periods with integer year 2000..2200 and trimester 1..3')
        return
      end
      period_ids = periods.map { |period| period_number(period) }
      errors.add(:periods, 'must not contain duplicates') if period_ids.uniq.length != period_ids.length

      unless slots.is_a?(Array) && slots.length <= 240 && slots.all? { |slot| valid_slot?(slot) }
        errors.add(:slots, 'must contain at most 240 slots with a unit code and integer year, trimester and position 1..4')
        return
      end
      validate_slot_references(period_ids)
    end

    def valid_slot?(slot)
      valid_period?(slot) && slot.keys.sort == SLOT_KEYS.sort &&
        slot['unit_code'].is_a?(String) && Course::UNIT_CODE.match?(slot['unit_code']) &&
        slot['position'].is_a?(Integer) && slot['position'].between?(1, 4)
    end

    def validate_slot_references(period_ids)
      codes = slots.pluck('unit_code')
      positions = slots.map { |slot| [period_number(slot), slot['position']] }
      errors.add(:slots, 'must not repeat a unit') if codes.uniq.length != codes.length
      errors.add(:slots, 'must not repeat a position') if positions.uniq.length != positions.length
      errors.add(:slots, 'must belong to a declared period') unless slots.all? { |slot| period_ids.include?(period_number(slot)) }
      return unless course

      errors.add(:slots, 'must use unit codes from the selected course') if (codes - course.units.pluck('code')).any?
    end
  end
end

# frozen_string_literal: true

module Courseflow
  # A versioned planning catalog, independent of teaching units and enrolments.
  class Course < ApplicationRecord
    self.table_name = 'courseflow_courses'
    attribute :units, :json

    MAX_UNITS = 240
    UNIT_KEYS = %w[code name required prerequisites offered_trimesters].freeze
    CATALOG_KEYS = %w[code name version elective_count units].freeze
    UNIT_CODE = /\A[A-Z0-9][A-Z0-9_-]{0,19}\z/

    has_many :maps, class_name: 'Courseflow::CourseMap', dependent: :restrict_with_exception

    validates :code, presence: true, length: { maximum: 40 }, format: { with: /\A[A-Z0-9][A-Z0-9_-]*\z/ }
    validates :name, presence: true, length: { maximum: 200 }
    validates :version, presence: true, length: { maximum: 40 }, uniqueness: { scope: :code }
    validates :elective_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validate :validate_units
    validate :immutable_catalog, on: :update

    def as_catalog
      attributes.slice('id', *CATALOG_KEYS)
    end

    private

    def immutable_catalog
      errors.add(:base, 'Catalog versions are immutable; import a new version') if changed.intersect?(CATALOG_KEYS)
    end

    def validate_units
      unless units.is_a?(Array) && units.length.between?(1, MAX_UNITS)
        errors.add(:units, "must contain between 1 and #{MAX_UNITS} unit definitions")
        return
      end

      units.each_with_index { |unit, index| validate_unit(unit, index) }
      return if errors[:units].any?

      codes = units.pluck('code')
      errors.add(:units, 'must have unique codes') if codes.uniq.length != codes.length
      units.each do |unit|
        errors.add(:units, "#{unit['code']} has unknown prerequisites") if (unit['prerequisites'] - codes).any?
      end
      return if errors[:units].any?

      dependencies = units.to_h { |unit| [unit['code'], unit['prerequisites']] }
      if cyclic?(dependencies)
        errors.add(:units, 'prerequisites must not contain cycles')
        return
      end
      validate_elective_count(dependencies)
    end

    def validate_unit(unit, index)
      unless unit.is_a?(Hash) && unit.keys.sort == UNIT_KEYS.sort
        errors.add(:units, "entry #{index + 1} must contain exactly #{UNIT_KEYS.join(', ')}")
        return
      end

      valid = unit['code'].is_a?(String) && UNIT_CODE.match?(unit['code']) &&
              unit['name'].is_a?(String) && unit['name'].strip.present? && unit['name'].length <= 200 &&
              [true, false].include?(unit['required']) &&
              unit['prerequisites'].is_a?(Array) && unit['prerequisites'].length <= MAX_UNITS &&
              unit['prerequisites'].all? { |code| code.is_a?(String) && UNIT_CODE.match?(code) } &&
              unit['prerequisites'].uniq == unit['prerequisites'] &&
              unit['offered_trimesters'].is_a?(Array) && unit['offered_trimesters'].any? &&
              unit['offered_trimesters'].all? { |value| value.is_a?(Integer) && value.between?(1, 3) } &&
              unit['offered_trimesters'].uniq == unit['offered_trimesters']
      errors.add(:units, "entry #{index + 1} has invalid planning rules") unless valid
    end

    def cyclic?(dependencies)
      visiting = Set.new
      visited = Set.new
      visit = lambda do |code|
        return true if visiting.include?(code)
        return false if visited.include?(code)

        visiting.add(code)
        return true if dependencies.fetch(code).any? { |prerequisite| visit.call(prerequisite) }

        visiting.delete(code)
        visited.add(code)
        false
      end
      dependencies.keys.any? { |code| visit.call(code) }
    end

    def validate_elective_count(dependencies)
      return unless elective_count.is_a?(Integer)

      required = units.select { |unit| unit['required'] }.pluck('code')
      closure = required.to_set
      pending = required.dup
      until pending.empty?
        dependencies.fetch(pending.pop).each do |prerequisite|
          pending << prerequisite if closure.add?(prerequisite)
        end
      end
      minimum_electives = closure.length - required.length
      maximum_electives = units.length - required.length
      depths = {}
      depth = ->(code) { depths[code] ||= 1 + (dependencies.fetch(code).map { |prerequisite| depth.call(prerequisite) }.max || 0) }
      if required.any? { |code| depth.call(code) > 60 }
        errors.add(:units, 'required prerequisite chains must fit within 60 study periods')
      end
      return if elective_count.between?(minimum_electives, maximum_electives)

      errors.add(:elective_count, "must be between #{minimum_electives} and #{maximum_electives} for these prerequisites")
    end
  end
end

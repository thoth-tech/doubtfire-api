require 'csv_helper'
require 'csv'
class Tutorial < ApplicationRecord
  include CsvHelper
  # Model associations
  belongs_to :unit, optional: false # Foreign key
  belongs_to :unit_role, optional: true # Foreign key
  belongs_to :campus, optional: true
  belongs_to :tutorial_stream, optional: true

  has_one    :tutor, through: :unit_role, source: :user

  has_many   :groups, dependent: :restrict_with_exception
  has_many   :tutorial_enrolments, dependent: :destroy
  has_many   :projects, through: :tutorial_enrolments

  # Callbacks - methods called are private
  before_destroy :can_destroy?

  validates :abbreviation, uniqueness: { scope: :unit,
                                         message: 'must be unique within the unit' }

  # Make sure that unit in tutorial and tutorial stream are consistent
  validate :unit_must_be_same

  def unit_must_be_same
    if unit.present? and tutorial_stream.present? and !unit.eql? tutorial_stream.unit
      errors.add(:unit, "should be same as the unit in the associated tutorial stream")
    end
  end

  def self.default
    tutorial = new

    tutorial.unit_role_id     = -1
    tutorial.meeting_day      = 'Enter a regular meeting day.'
    tutorial.meeting_time     = 'Enter a regular meeting time.'
    tutorial.meeting_location = 'Enter a location.'

    tutorial
  end

  def self.find_by_user(user)
    Tutorial.joins(:tutor).where('user_id = :user_id', user_id: user.id)
  end

  def tutor
    unit_role.user unless unit_role.nil?
  end

  def name
    "#{meeting_day} #{meeting_time} (#{meeting_location})"
  end

  def change_tutor(new_tutor)
    # Get the unit role for current tutor
    assign_tutor(new_tutor)
  end

  def assign_tutor(tutor_user)
    # Create a role for the user if they're not already a tutor
    # TODO: Move creation to UnitRole and pass it approriate params
    tutor_unit_role = UnitRole.find_by(
      unit_id: unit_id,
      user_id: tutor_user.id
    )

    if tutor_unit_role && tutor_user.has_tutor_capability? && (tutor_unit_role.role == Role.tutor || tutor_unit_role.role == Role.convenor)
      self.unit_role = tutor_unit_role
      save
    end
    self
  end

  def num_students
    projects.where('enrolled = true').count
  end

  def self.missing_headers(row, headers)
    headers - row.to_hash.keys
  end

  def self.csv_columns
    %w[code abbreviation unit_id tutor_id tutorial_stream]
  end

  def self.import_from_csv(file)
    success = []
    errors = []
    ignored = []
    data = FileHelper.read_file_to_str(file).gsub('\\n', "\n")
    CSV.parse(data,
              headers: true,
              header_converters: [->(i) { i.nil? ? '' : i }, :downcase, ->(hdr) { hdr.strip unless hdr.nil? }],
              converters: [->(body) { body.encode!('UTF-8', 'binary', invalid: :replace, undef: :replace, replace: '') unless body.nil? }]).each do |row|
      missing = missing_headers(row, csv_columns)
      if missing.count > 0
        errors << { row: row, message: "Missing headers: #{missing.join(', ')}" }
        next
      end

      tutorial_code = row['code'].strip unless row['code'].nil?
      abbreviation = row['abbreviation'].strip unless row['abbreviation'].nil?
      unit_id = row['unit_id'].strip unless row['unit_id'].nil?
      user_id = row['tutor_id'].strip unless row['tutor_id'].nil?
      tutorial_stream_name = row['tutorial_stream'].strip unless row['tutorial_stream'].nil?

      # find unit role using tutor's user_id and unit_id
      unit_role = UnitRole.find_by(user_id: user_id, unit_id: unit_id)

      if unit_role.nil?
        errors << { row: row, message: "Tutor with user_id (#{user_id}) not found in unit roles" }
        next
      end

      # if tutorial is found set it, otherwise leave it blank
      tutorial_stream = TutorialStream.find_by(name: tutorial_stream_name) if tutorial_stream_name.present?

      # handle missing tutorial stream
      tutorial_stream = nil if tutorial_stream_name.blank?

      # create a new tutorial
      tutorial = Tutorial.new(
        unit_id: unit_id,
        code: tutorial_code,
        abbreviation: abbreviation,
        unit_role_id: unit_role.id,
        tutorial_stream_id: tutorial_stream&.id
      )

      if tutorial.save
        success << { row: row, message: "Created tutorial #{abbreviation} #{unit_id}" }
      else
        errors << {row: row, message: "Failed to create tutorial #{abbreviation} #{unit_id}" }
      end
    rescue StandardError => e
      errors << { row: row, message: e.message }
    end
    {
      success: success,
      ignored: ignored,
      errors: errors
    }
  end

  def self.export_to_csv
    exportables = %w[code abbreviation unit_id unit_role_id tutorial_stream_id]

    # Generate the CSV file
    CSV.generate do |csv|
      # Add header row
      csv << Tutorial.attribute_names.select { |attribute| exportables.include? attribute }.map do |attribute|
        if attribute == 'tutorial_stream_id'
          'tutorial_stream'
        elsif attribute == 'unit_role_id'
          'tutor_id'
        else
          attribute
        end
      end

      # Add data rows
      Tutorial.order('id').each do |tutorial|
        csv << tutorial.attributes.select { |attribute| exportables.include? attribute }.map do |key, value|
          # make the values more readable
          if key == 'tutorial_stream_id'
            stream_name = TutorialStream.find_by(id: value)&.name
            stream_name
          elsif key == 'unit_role_id'
            tutor_id = UnitRole.find_by(id: value)&.user_id
            tutor_id
          else
            value
          end
        end
      end
    end
  end

  private

  def can_destroy?
    active_enrolment_count = num_students
    return true if active_enrolment_count == 0 && groups.count == 0

    errors.add :base, "Cannot delete tutorial with enrolments" if active_enrolment_count > 0
    errors.add :base, "Cannot delete tutorial with groups" if groups.count > 0
    throw :abort
  end
end

FactoryBot.define do
  factory :course_map_unit, class: 'Courseflow::Coursemapunit' do
    courseMapId { 1 }
    unitId { 1 }
    yearSlot { 1 }
    teachingPeriodSlot { 1 }
    unitSlot { 1 }
  end
end

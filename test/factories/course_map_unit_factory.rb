FactoryBot.define do
  factory :coursemapunit, class: 'Courseflow::CourseMapUnit' do
    courseMapId { 1 }
    unitId { 1 }
    yearSlot { 1 }
    teachingPeriodSlot { 1 }
    unitSlot { 1 }
  end
end

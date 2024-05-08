FactoryBot.define do
  factory :course_map, class: 'Courseflow::Coursemap' do
    userId { 1 }
    courseId { 1 }
  end
end

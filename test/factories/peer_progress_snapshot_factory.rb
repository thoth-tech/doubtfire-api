FactoryBot.define do
  factory :peer_progress_snapshot do
    unit do
      create(
        :unit,
        with_students: false,
        task_count: 0,
        stream_count: 0
      )
    end

    task_definition do
      create(
        :task_definition,
        unit: unit,
        target_grade: 0,
        outcome_count: 0
      )
    end

    target_grade { task_definition.target_grade }
    submitted_percentage { 50.0 }
    cohort_size { 10 }
    calculated_at { Time.current }
  end
end

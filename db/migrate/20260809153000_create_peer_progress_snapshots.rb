class CreatePeerProgressSnapshots < ActiveRecord::Migration[8.0]
  def change
    create_table :peer_progress_snapshots,
                 options: 'ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 ' \
                          'COLLATE=utf8mb4_general_ci' do |t|
      t.references :unit, null: false
      t.references :task_definition, null: false

      t.integer :target_grade, null: false

      # nil represents suppressed or unavailable data.
      # A genuine zero result is stored as 0.00.
      t.decimal :submitted_percentage,
                precision: 5,
                scale: 2

      # Internal only. Never expose this raw value through the student API.
      t.integer :cohort_size, null: false

      # The time the aggregate was calculated, rather than when this row
      # happened to be inserted or updated.
      t.datetime :calculated_at, null: false

      t.timestamps
    end

    add_index :peer_progress_snapshots,
              [:unit_id, :task_definition_id, :target_grade],
              unique: true,
              name: 'idx_peer_progress_unit_task_grade'
  end
end

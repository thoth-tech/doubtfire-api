class CreateFeedbackGroupsAndTemplates < ActiveRecord::Migration[7.0]
  def change
    create_table :feedback_groups do |t|
      t.string :title, null: false
      t.integer :order, null: false

      # Foreign keys
      t.references :task_definition, null: false, foreign_key: true
    end

    add_index :feedback_groups, [:task_definition_id, :order], unique: true

    create_table :feedback_comment_templates do |t|
      # Fields
      t.string :abbreviation, null: false
      t.integer :order, null: false
      t.string :chip_text, limit: 20
      t.string :description, null: false
      t.string :comment_text, null: false
      t.string :summary_text, null: false

      # Foreign keys
      t.references :feedback_group, null: false, foreign_key: true
      t.references :task_status, foreign_key: true
    end
  end
end

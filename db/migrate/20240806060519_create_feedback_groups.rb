class CreateFeedbackGroups < ActiveRecord::Migration[7.0]
  def change
    create_table :feedback_groups do |t|

      t.timestamps
    end
  end
end

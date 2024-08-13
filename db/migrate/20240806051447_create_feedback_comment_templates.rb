class CreateFeedbackCommentTemplates < ActiveRecord::Migration[7.0]
  def change
    create_table :feedback_comment_templates do |t|

      t.timestamps
    end
  end
end

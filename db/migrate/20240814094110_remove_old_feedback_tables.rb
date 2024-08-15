class RemoveOldFeedbackTables < ActiveRecord::Migration[7.0]
  def change
    drop_table :stages if ActiveRecord::Base.connection.table_exists?(:stages)
    drop_table :criteria if ActiveRecord::Base.connection.table_exists?(:criteria)
    drop_table :criterion_options if ActiveRecord::Base.connection.table_exists?(:criterion_options)

    if ActiveRecord::Base.connection.column_exists?(:task_comments, :feedback_comment_template_id)
      remove_reference :task_comments, :feedback_comment_template, index: true
    end

    if ActiveRecord::Base.connection.column_exists?(:task_comments, :criterion_option_id)
      remove_reference :task_comments, :criterion_option, index: true
    end
  end
end

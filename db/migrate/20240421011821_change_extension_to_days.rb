class ChangeExtensionToDays < ActiveRecord::Migration[7.1]
  def up
    # update extension data in task comments and delete the old column
    rename_column :task_comments, :extension_weeks, :extension_days
    execute <<~SQL.squish
      UPDATE task_comments
      SET extension_days = extension_days * 7
      WHERE extension_days IS NOT NULL;
    SQL

    # update extension data in unit settings and delete the old column
    rename_column :units, :extension_weeks_on_resubmit_request, :extension_days_on_resubmit_request
    execute <<~SQL.squish
      UPDATE units
      SET extension_days_on_resubmit_request = extension_days_on_resubmit_request * 7;
    SQL
  end

  def down
    rename_column :task_comments, :extension_days, :extension_weeks
    # anything less than 7 days should be restored to 1 week
    execute <<~SQL.squish
      UPDATE task_comments
      SET extension_weeks = (extension_weeks + 6) / 7
      WHERE extension_weeks IS NOT NULL;
    SQL

    rename_column :units, :extension_days_on_resubmit_request, :extension_weeks_on_resubmit_request
    # anything less than 7 days should be restored to 1 week
    execute <<~SQL.squish
      UPDATE units
      SET extension_weeks_on_resubmit_request = (extension_weeks_on_resubmit_request + 6) / 7;
    SQL
  end
end

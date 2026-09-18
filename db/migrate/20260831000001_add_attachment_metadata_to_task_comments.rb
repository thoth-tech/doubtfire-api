# frozen_string_literal: true

class AddAttachmentMetadataToTaskComments < ActiveRecord::Migration[8.0]
  def change
    add_column :task_comments, :attachment_original_filename, :string
    add_column :task_comments, :attachment_content_type, :string
    add_column :task_comments, :attachment_byte_size, :bigint
    add_column :task_comments, :client_request_id, :string
    add_index :task_comments, [:user_id, :task_id, :client_request_id],
              unique: true,
              name: 'idx_task_comments_user_task_client_request'
  end
end

class CreateConsumedLtiTokens < ActiveRecord::Migration[8.0]
  def change
    create_table :consumed_lti_tokens do |t|
      t.string :jti, null: false
      t.references :user, null: false, foreign_key: true
      t.datetime :expires_at, null: false

      t.timestamps
    end

    add_index :consumed_lti_tokens, :jti, unique: true
    add_index :consumed_lti_tokens, :expires_at
  end
end

# frozen_string_literal: true

class AddThemePreferenceToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :theme_preference, :string
    add_column :users, :theme_preference_updated_at, :datetime
  end
end

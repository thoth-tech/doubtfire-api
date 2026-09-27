# frozen_string_literal: true

# How often a student wants the unit summary email. Until now that email went out
# weekly to everyone with feedback notifications on, with no way to ask for it
# more or less often, and no way to stop it without also losing feedback mail.
#
# 'weekly' is the default because it is what every existing account already
# receives, so adding the column changes nothing until someone chooses.
class AddDigestFrequencyToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :digest_frequency, :string, default: 'weekly', null: false
  end
end

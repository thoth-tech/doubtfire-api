require 'test_helper'

class DxA02Test < ActiveSupport::TestCase
  test 'dead config and scaffold files are removed' do
    refute File.exist?(Rails.root.join('.rspec')), '.rspec should have been deleted'
    refute File.exist?(Rails.root.join('.overcommit.yml')), '.overcommit.yml should have been deleted'
    refute File.exist?(Rails.root.join('FETCH_HEAD')), 'FETCH_HEAD should have been deleted'
    refute File.exist?(Rails.root.join('docs', 'README_FOR_APP')), 'docs/README_FOR_APP should have been deleted'
  end

  test 'User.default no longer exists' do
    assert_raises(NoMethodError) { User.default }
  end
end
require 'minitest/autorun'
require 'pathname'

class Tci33Test < Minitest::Test
  ROOT = Pathname.new(__dir__).join('..', '..').expand_path

  def test_dead_rspec_scaffolding_is_removed
    refute File.exist?(ROOT.join('.rspec')),
           '.rspec should not exist'
    refute File.exist?(ROOT.join('test/channels/application_cable/connection_test.rb')),
           'dead ActionCable connection test should not exist'
    refute File.exist?(ROOT.join('test/integration/.keep')),
           'unused integration test placeholder should not exist'
  end

  def test_readme_documents_the_minitest_workflow
    readme = File.read(ROOT.join('README.md'))

    assert_includes readme, 'Minitest'
    assert_includes readme, 'test/models'
    assert_includes readme, 'test/api'
    assert_includes readme, 'rake test'
  end
end

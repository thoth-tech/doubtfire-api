require "test_helper"

class OverseerImageTest < ActiveSupport::TestCase

  def test_valid
    oi = OverseerImage.create(
      name: 'Image',
      tag: 'image'
    )

    assert oi.valid?
  end

  def test_valid_with_example
    oi = OverseerImage.create(
      name: 'Image',
      tag: 'macite/overseer-dotnet:test'
    )

    assert oi.valid?, oi.errors
  end

  def test_cannot_pull_invalid_tag
    oi = OverseerImage.create(
      name: 'Image',
      tag: 'image & ls'
    )

    refute oi.valid?
    # pull from docker, will refuse as invalid
    refute oi.pull_from_docker
  end

  def test_cannot_inject_code_in_tag
    oi = OverseerImage.create(
      name: 'Image',
      tag: 'image & ls'
    )

    refute oi.valid?

    oi.tag = 'image&ls'
    refute oi.valid?

    oi.tag = 'image|ls'
    refute oi.valid?

    oi.tag = 'image>ls'
    refute oi.valid?

    oi.tag = 'image<ls'
    refute oi.valid?

    oi.tag = 'image($ls)'
    refute oi.valid?

    oi.tag = 'image$ls'
    refute oi.valid?
  end

  def test_database_population_can_create_the_seed_image_without_pulling_it
    original_skip = ENV.fetch('SKIP_OVERSEER_IMAGE_PULL_ON_POPULATE', nil)
    pull_called = false
    created_attributes = nil
    image = Object.new
    image.define_singleton_method(:tag) { 'bash:latest' }
    image.define_singleton_method(:pull_from_docker) { pull_called = true }
    create_image = lambda do |**attributes|
      created_attributes = attributes
      image
    end

    OverseerImage.stub(:create!, create_image) do
      ENV['SKIP_OVERSEER_IMAGE_PULL_ON_POPULATE'] = 'true'
      DatabasePopulator.allocate.generate_overseer_images
    end

    assert_equal({ name: 'Bash', tag: 'bash:latest' }, created_attributes)
    assert_equal false, pull_called
  ensure
    if original_skip.nil?
      ENV.delete('SKIP_OVERSEER_IMAGE_PULL_ON_POPULATE')
    else
      ENV['SKIP_OVERSEER_IMAGE_PULL_ON_POPULATE'] = original_skip
    end
  end
end

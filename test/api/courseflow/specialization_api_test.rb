require "test_helper"

class SpecializationTest < ActiveSupport::TestCase
  include Rack::Test::Methods
  include TestHelpers::JsonHelper

  def app
    Rails.application
  end

  def test_get_all_specializations
    specialization1 = FactoryBot.create(:specialization)
    specialization2 = FactoryBot.create(:specialization)
    specialization3 = FactoryBot.create(:specialization)
    specialization4 = FactoryBot.create(:specialization)
    get "/api/specialization"
    assert_equal 200, last_response.status
    assert_equal 4, JSON.parse(last_response.body).size
  ensure
    specialization1.destroy
    specialization2.destroy
    specialization3.destroy
    specialization4.destroy
  end

  def test_get_specialization_by_id
    test_id = 101
    specialization = FactoryBot.create(:specialization, id: test_id)
    get "/api/specialization/specializationId/#{test_id}"
    assert_equal 200, last_response.status
  ensure
    specialization.destroy
  end

  def test_create_specialization
    data_to_post = { specialization: '101' }
    post_json "/api/specialization", data_to_post
    assert_equal 201, last_response.status
  end

  def test_update_specialization
    specialization = FactoryBot.create(:specialization, specialization: '101')
    data_to_put = { specialization: '102' }
    put_json "/api/specialization/specializationId/#{specialization.id}", data_to_put
    assert_equal 200, last_response.status
  ensure
    specialization.destroy
  end

  def test_delete_specialization
    specialization = FactoryBot.create(:specialization, specialization: '101')
    delete_json "/api/specialization/specializationId/#{specialization.id}"
    assert_equal 0, Courseflow::Specialization.where(id: specialization.id).count
  ensure
    specialization.destroy
  end
end

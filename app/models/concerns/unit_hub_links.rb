# frozen_string_literal: true

require 'uri'

# Links are displayed, never fetched by the server. Reject executable protocols
# and embedded credentials before staff can publish a link.
module UnitHubLinks
  extend ActiveSupport::Concern

  included do
    validate :safe_unit_hub_links
  end

  private

  def safe_unit_hub_links
    %i[source_url join_url].each do |field|
      next unless respond_to?(field)

      value = public_send(field)
      next if value.blank?

      valid = value.length <= 2048 && !value.match?(/[[:space:][:cntrl:]]/)
      uri = URI.parse(value) if valid
      valid &&= uri.is_a?(URI::HTTPS) && uri.host.present? && uri.userinfo.nil?
      errors.add(field, 'must be a complete HTTPS link without embedded credentials') unless valid
    rescue URI::InvalidURIError
      errors.add(field, 'must be a complete HTTPS link without embedded credentials')
    end
  end
end

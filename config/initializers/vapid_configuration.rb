# frozen_string_literal: true

require_relative '../../lib/vapid_configuration'

VapidConfiguration.validate!(production: Rails.env.production?)
Rails.application.config.filter_parameters += %i[doubtfire_vapid_private_key vapid_private_key private_key]

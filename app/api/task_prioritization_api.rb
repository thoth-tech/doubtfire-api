# frozen_string_literal: true

require 'grape'

class TaskPrioritizationApi < Grape::API
  helpers AuthenticationHelpers
  helpers AuthorisationHelpers
  helpers DbHelpers

  DEFAULT_PER_PAGE = 50
  MAX_PER_PAGE = 50

  before do
    authenticated?
  end

  desc 'Get prioritized task recommendations for a student',
       detail: 'Returns the authenticated student\'s actionable tasks ranked by effective deadline, relative task size, and deadline workload.'

  params do
    optional :page, type: Integer, default: 1, values: ->(value) { value.positive? }
    optional :per_page, type: Integer, default: DEFAULT_PER_PAGE, values: 1..MAX_PER_PAGE
  end

  get '/tasks/recommended' do
    recommendations = TaskPrioritizationService.new(current_user).call
    offset = (params[:page] - 1) * params[:per_page]

    {
      data: recommendations.slice(offset, params[:per_page]) || [],
      meta: {
        page: params[:page],
        per_page: params[:per_page],
        total_count: recommendations.length,
        total_pages: (recommendations.length / params[:per_page].to_f).ceil
      }
    }
  end
end

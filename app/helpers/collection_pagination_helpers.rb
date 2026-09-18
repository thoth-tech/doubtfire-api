module CollectionPaginationHelpers
  MAX_PAGE = 2_147_483_647
  MAX_PER_PAGE = 500
  DEFAULT_PER_PAGE = 50

  # Existing web/mobile callers consume a complete array. Only callers that
  # explicitly request pagination receive a bounded page, still as an array.
  # Count the already-authorised relation, never the unrestricted model.
  def paginate_collection(relation)
    return relation if params[:page].nil? && params[:per_page].nil?

    page = params[:page] || 1
    per_page = params[:per_page] || DEFAULT_PER_PAGE
    total = relation.count

    header 'X-Total-Count', total.to_s
    header 'X-Page', page.to_s
    header 'X-Per-Page', per_page.to_s
    header 'X-Total-Pages', ((total + per_page - 1) / per_page).to_s

    relation.reorder(id: :asc).limit(per_page).offset((page - 1) * per_page)
  end
end

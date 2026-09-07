module ContextModelHelpers
  CONTEXT_MODELS = {
    'units' => Unit,
    'task_definitions' => TaskDefinition
  }.freeze

  def context_model_for(context_type_plural, context_id)
    context_class_for(context_type_plural).find(context_id)
  end

  def context_type_for(context_type_plural)
    context_class_for(context_type_plural).name
  end

  private

  def context_class_for(context_type_plural)
    CONTEXT_MODELS.fetch(context_type_plural.to_s)
  end
end

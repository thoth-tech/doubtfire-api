class PeerProgressController < ApplicationController
  def show
    student_id = params[:student_id].to_i
    unit_id = params[:unit_id].to_i

    project = Project.find_by(user_id: student_id, unit_id: unit_id)

    return render json: { error: "Project not found" }, status: :not_found unless project

    target_grade = project.target_grade

    required_tasks = project.unit.tasks.where(project_id: project.id).select do |task|
      task.task_definition.present? &&
        task.task_definition.target_grade.present? &&
        task.task_definition.target_grade <= target_grade
    end

    tasks_required = required_tasks.count
    tasks_completed = required_tasks.select(&:complete?).count

    progress_percentage =
      tasks_required.positive? ? ((tasks_completed.to_f / tasks_required) * 100).round : 0

    render json: {
      student_id: student_id,
      unit_id: unit_id,
      target_grade: project.target_grade_desc,
      tasks_completed: tasks_completed,
      tasks_required: tasks_required,
      progress_percentage: progress_percentage
    }
  end
end

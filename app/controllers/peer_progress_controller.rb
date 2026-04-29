class PeerProgressController < ApplicationController
  def show
  student_id = params[:student_id].to_i
  unit_id = params[:unit_id].to_i

  project = Project.find_by(user_id: student_id, unit_id: unit_id)

  return render json: { error: "Project not found" }, status: 404 unless project

  # Tasks required for target grade
  required_tasks = project.tasks.joins(:task_definition)
    .where('task_definitions.target_grade <= ?', project.target_grade)

  tasks_required = required_tasks.count

  # Tasks completed
  tasks_completed = required_tasks.select(&:complete?).count

  # Percentage
  progress_percentage = tasks_required > 0 ? ((tasks_completed.to_f / tasks_required) * 100).round : 0

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

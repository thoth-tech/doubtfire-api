require 'grape'

class CourseMapApi < Grape::API
  format :json

    desc "Get course map via user ID"
    params do
      requires :userId, type: Integer, desc: "User ID"
    end
    get '/coursemap/:userId' do
      coursemap = Coursemap.find_by(userId: params[:userId])
      if coursemap
        present coursemap, with: CourseMapEntity
      else
        error!({ error: "Course map #{params[:userId]} not found" }, 404)
      end
    end

    desc "Get course map via course ID"
    params do
      requires :courseId, type: Integer, desc: "Course ID"
    end
    get '/coursemap/:courseId' do
      coursemaps = Coursemap.where(courseId: params[:courseId])
      present coursemaps, with: CourseMapEntity
    end

    desc "Add a new course map"
    params do
      requires :userId, type: Integer
      requires :courseId, type: Integer
    end
    post '/coursemap' do
      coursemap = Coursemap.new(params)
      if coursemap.save
        present coursemap, with: CourseMapEntity
      else
        error!({ error: "Failed to create course map", details: course_map.errors.full_messages }, 400)
      end
    end

    desc "Update an existing course map unit via its ID"
    params do
      requires :courseMapId, type: Integer, desc: "Course map ID"
      requires :userId, type: Integer
      requires :courseId, type: Integer
    end
    put '/coursemap/:courseMapId' do
      coursemap = Coursemap.find(params[:courseMapId])
      if coursemap.update(params.except(:courseMapId))
        present coursemap, with: CourseMapEntity
      else
        error!({ error: "Failed to update course map", details: course_map.errors.full_messages }, 400)
      end
    end

    desc "Delete all course map units via its associated course map ID"
    params do
      requires :courseMapId, type: Integer, desc: "Course map ID"
    end
    delete '/coursemap/:courseMapId' do
      coursemaps = Coursemap.where(courseId: params[:courseMapId])
      if coursemaps
        coursemaps.destroy_all
      else
        error!({ error: "Course map #{params[:courseMapId]} not found" }, 404)
      end
    end
  end


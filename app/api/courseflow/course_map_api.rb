require 'grape'
module Courseflow
  class CourseMapApi < Grape::API
    format :json

    desc "Get course map via user ID"
    params do
      requires :userId, type: Integer, desc: "User ID"
    end
    get '/coursemap/user/:userId' do
      course_map = Coursemap.find_by(userId: params[:userId])
      if course_map
        present course_map, with: Entities::CourseMapEntity
      else
        error!({ error: "Course map #{params[:userId]} not found" }, 404)
      end
    end

    desc "Get course map via course ID"
    params do
      requires :courseId, type: Integer, desc: "Course ID"
    end
    get '/coursemap/course/:courseId' do
      course_map = Coursemap.where(courseId: params[:courseId])
      if course_map
        present course_map, with: Entities::CourseMapEntity
      else
        error!({ error: "Course map #{params[:courseId]} not found" }, 404)
      end
    end

    desc "Add a new course map"
    params do
      requires :userId, type: Integer
      requires :courseId, type: Integer
    end
    post '/coursemap' do
      course_map = Coursemap.new(params)
      if course_map.save
        present course_map, with: Entities::CourseMapEntity
      else
        error!({ error: "Failed to create course map", details: coursemap.errors.full_messages }, 400)
      end
    end

    desc "Update an existing course map unit via its ID"
    params do
      requires :courseMapId, type: Integer, desc: "Course map ID"
      requires :userId, type: Integer
      requires :courseId, type: Integer
    end
    put '/coursemap/:courseMapId' do
      course_map = Coursemap.find(params[:courseMapId])
      if course_map.update(params.except(:courseMapId))
        present course_map, with: Entities::CourseMapEntity
      else
        error!({ error: "Failed to update course map", details: coursemap.errors.full_messages }, 400)
      end
    end

    desc "Delete all course map units via its associated course map ID"
    params do
      requires :courseMapId, type: Integer, desc: "Course map ID"
    end
    delete '/coursemap/:courseMapId' do
      course_map = Coursemap.find(params[:courseMapId])
      if course_map
        course_map.destroy
      else
        error!({ error: "Course map #{params[:courseMapId]} not found" }, 404)
      end
    end

    desc "Delete all course map units via its associated user ID"
    params do
      requires :userId, type: Integer, desc: "User ID"
    end
    delete '/coursemap/user/:userId' do
      course_map = Coursemap.find(params[:userId])
      if course_map
        course_map.destroy
      else
        error!({ error: "Course map #{params[:userId]} not found" }, 404)
      end
    end
  end
end

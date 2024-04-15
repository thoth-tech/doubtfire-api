require 'grape'

class CourseMapUnitApi < Grape::API

    desc "Get course map unit via course map ID"
    params do
      requires :courseMapId, type: Integer, desc: "Course map ID"
    end
    get '/coursemapunit/:courseMapId' do
      Coursemapunit.where(courseMapId: params[:courseMapId]) # get all course map units associated with the course map ID
    end

    desc "Add a new course map unit"
    params do
      requires :courseMapId, type: Integer
      requires :unitId, type: Integer
      requires :yearSlot, type: Integer
      requires :teachingPeriodSlot, type: Integer
      requires :unitSlot, type: Integer
    end
    post do
      Coursemapunit.create!(params) # create a new course map unit with the provided params
    end

    desc "Update an existing course map unit via its ID"
    params do
      requires :courseMapUnitId, type: Integer, desc: "Course map unit ID"
      requires :courseMapId, type: Integer
      requires :unitId, type: Integer
      requires :yearSlot, type: Integer
      requires :teachingPeriodSlot, type: Integer
      requires :unitSlot, type: Integer
    end
    put '/coursemapunit/:courseMapUnitId' do
      coursemapunit = Coursemapunit.find(params[:courseMapUnitId])
      coursemapunit.update(params.except(:courseMapUnitId))
      coursemapunit
    end

    desc "Delete all course map units via its associated course map ID"
    params do
      requires :courseMapId, type: Integer, desc: "Course map ID"
    end
    delete '/coursemapunit/:courseMapId' do
      Coursemapunit.where(courseMapId: params[:courseMapId]).destroy_all # delete all course map units associated with the course map ID
    end

    desc "Delete a course map unit via its ID"
    params do
      requires :courseMapUnitId, type: Integer, desc: "Course map unit ID"
    end
    delete '/coursemapunit/:courseMapUnitId' do
      Coursemapunit.find(params[:courseMapUnitId]).destroy # delete the course map unit by ID
    end
  end


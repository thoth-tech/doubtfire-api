require 'test_helper'
require 'tempfile'

class AcceptOverseerJobTest < Minitest::Test
  def setup
    @task_id = 987_654
    @assessment_id = 876_543
    @work_dir = Rails.root.join(
      'tmp',
      'overseer',
      "#{@task_id}-#{@assessment_id}"
    )

    FileUtils.rm_rf(@work_dir)
  end

  def teardown
    FileUtils.rm_rf(@work_dir) if @work_dir
  end

  def test_removes_work_directory_and_reraises_on_failure
    step = Struct.new(:enabled).new(true)
    task_definition = Struct.new(:overseer_steps).new([step])

    task = Struct.new(:id, :task_definition).new(
      @task_id,
      task_definition
    )

    task.define_singleton_method(:processing_pdf?) { false }
    task.define_singleton_method(:has_done_file?) { true }

    assessment = Object.new
    assessment.define_singleton_method(:update!) { |**| true }

    job = AcceptOverseerJob.new

    Tempfile.create(['overseer-submission', '.zip']) do |submission|
      forced_failure = lambda do |*|
        assert Dir.exist?(@work_dir),
               'work directory should exist before forced failure'

        raise 'forced overseer failure'
      end

      Task.stub(:find, task) do
        OverseerAssessment.stub(:find, assessment) do
          job.stub(:at, nil) do
            job.stub(:total, nil) do
              error = job.stub(
                :extract_student_submission_files,
                forced_failure
              ) do
                assert_raises(RuntimeError) do
                  job.perform(
                    @task_id,
                    nil,
                    'dummy:image',
                    submission.path,
                    '/tmp/no-assessment.zip',
                    '123456',
                    @assessment_id
                  )
                end
              end

              assert_equal 'forced overseer failure', error.message
            end
          end
        end
      end
    end

    refute Dir.exist?(@work_dir),
           'work directory should be removed after failure'
  end
end
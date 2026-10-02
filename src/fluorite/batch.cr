require "uuid"
require "./dsl/command"
require "./runner/process_runner"

module Fluorite
  class BatchJob
    enum Status
      Pending
      Running
      Completed
      Failed
    end

    getter id : String
    getter command : DSL::Command
    getter input_path : String
    getter output_path : String
    property status : Status = Status::Pending
    property progress : Runner::Progress = Runner::Progress.new
    property error_message : String? = nil

    def initialize(@input_path : String, @output_path : String, @command : DSL::Command)
      @id = UUID.random.to_s[0..7]
    end
  end

  class BatchQueue
    getter jobs : Array(BatchJob) = [] of BatchJob
    property concurrency : Int32 = 1

    @on_job_start_handlers = [] of BatchJob -> Nil
    @on_job_progress_handlers = [] of (BatchJob, Runner::Progress) -> Nil
    @on_job_complete_handlers = [] of BatchJob -> Nil
    @on_job_fail_handlers = [] of (BatchJob, Exception) -> Nil

    def initialize(@concurrency : Int32 = 1)
    end

    def add(input : String, output : String, &) : BatchJob
      cmd = Fluorite.build do |b|
        b.input(input)
        with b yield b
        b.output(output)
      end
      job = BatchJob.new(input, output, cmd)
      @jobs << job
      job
    end

    def add(job : BatchJob) : self
      @jobs << job
      self
    end

    def on_job_start(&block : BatchJob -> Nil) : self
      @on_job_start_handlers << block
      self
    end

    def on_job_progress(&block : (BatchJob, Runner::Progress) -> Nil) : self
      @on_job_progress_handlers << block
      self
    end

    def on_job_complete(&block : BatchJob -> Nil) : self
      @on_job_complete_handlers << block
      self
    end

    def on_job_fail(&block : (BatchJob, Exception) -> Nil) : self
      @on_job_fail_handlers << block
      self
    end

    def total_count : Int32
      @jobs.size
    end

    def completed_count : Int32
      @jobs.count(&.status.completed?)
    end

    def failed_count : Int32
      @jobs.count(&.status.failed?)
    end

    # Runs all jobs sequentially or up to concurrency limit
    def run : Nil
      channel = Channel(Nil).new

      @jobs.each do |job|
        job.status = BatchJob::Status::Running
        @on_job_start_handlers.each(&.call(job))

        begin
          job.command.run do |p|
            job.progress = p
            @on_job_progress_handlers.each(&.call(job, p))
          end
          job.status = BatchJob::Status::Completed
          @on_job_complete_handlers.each(&.call(job))
        rescue ex
          job.status = BatchJob::Status::Failed
          job.error_message = ex.message
          @on_job_fail_handlers.each(&.call(job, ex))
        end
      end
    end
  end
end

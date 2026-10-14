require "uuid"
require "./dsl/command"
require "./runner/process_runner"
require "./presets/base"
require "./presets/discord"
require "./presets/gif"
require "./presets/web"
require "./presets/audio"
require "./presets/trim"
require "./presets/sprite_sheet"
require "./sprite_sheet/core/pipeline"
require "./sprite_sheet/dsl/sprite_sheet_builder"

module Fluorite
  class BatchJob
    enum Status
      Pending
      Running
      Completed
      Failed
    end

    enum JobKind
      Transcode
      SpriteSheet
      AudioExtract
      LosslessTrim
    end

    getter id : String
    getter command : DSL::Command
    getter input_path : String
    getter output_path : String
    property preset_name : String
    property job_kind : JobKind
    property sprite_config : SpriteSheet::Core::PipelineConfig?
    property atlas_plan : SpriteSheet::Core::AtlasPlan?
    property status : Status = Status::Pending
    property progress : Runner::Progress = Runner::Progress.new
    property error_message : String? = nil

    def initialize(
      @input_path : String,
      @output_path : String,
      @command : DSL::Command,
      @preset_name : String = "Custom",
      @job_kind : JobKind = JobKind::Transcode,
      @sprite_config : SpriteSheet::Core::PipelineConfig? = nil,
      @atlas_plan : SpriteSheet::Core::AtlasPlan? = nil,
    )
      @id = UUID.random.to_s[0..7]
    end

    def sprite_sheet? : Bool
      @job_kind.sprite_sheet? || !@atlas_plan.nil?
    end

    def status_badge : String
      case @status
      when Status::Pending   then "[PEND]"
      when Status::Running   then "[RUN ]"
      when Status::Completed then "[DONE]"
      when Status::Failed    then "[FAIL]"
      else                        "[PEND]"
      end
    end

    def effective_percent : Float64
      case @status
      when Status::Completed then 100.0
      when Status::Running   then @progress.percent.clamp(0.0, 100.0)
      else                        @progress.percent.clamp(0.0, 100.0)
      end
    end

    def display_label : String
      in_base = File.basename(@input_path)
      out_base = File.basename(@output_path)
      if plan = @atlas_plan
        "#{in_base} -> #{out_base} [#{@preset_name} #{plan.columns}x#{plan.rows} #{plan.format.upcase}]"
      else
        "#{in_base} -> #{out_base} [#{@preset_name}]"
      end
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

    def add(input : String, output : String, preset_name : String = "Custom", &) : BatchJob
      cmd = Fluorite.build do |b|
        b.input(input)
        with b yield b
        b.output(output)
      end
      job = BatchJob.new(input, output, cmd, preset_name: preset_name)
      @jobs << job
      job
    end

    def add(job : BatchJob) : self
      @jobs << job
      self
    end

    # Enqueues a sprite-sheet packing job configured via the SpriteSheetBuilder DSL
    def add_spritesheet(input : String, output : String? = nil, preset_name : String = "Sprite Sheet", &) : BatchJob
      builder = SpriteSheet::DSL::SpriteSheetBuilder.new
      builder.input(input)
      if out_p = output
        builder.output(out_p)
      end
      with builder yield builder
      if builder.config.output_path.strip.empty?
        ext = builder.config.format.webp? ? ".webp" : ".png"
        base = File.basename(input, File.extname(input))
        builder.output("#{base}_sheet#{ext}")
      end
      add_spritesheet(builder.config, preset_name: preset_name)
    end

    # Enqueues a sprite-sheet packing job from a PipelineConfig
    def add_spritesheet(config : SpriteSheet::Core::PipelineConfig, preset_name : String = "Sprite Sheet") : BatchJob
      plan = SpriteSheet::Core::Planner.create_plan(config)
      cmd = SpriteSheet::Core::Planner.build_command(config, plan)
      job = BatchJob.new(
        input_path: config.input_path,
        output_path: config.output_path,
        command: cmd,
        preset_name: preset_name,
        job_kind: BatchJob::JobKind::SpriteSheet,
        sprite_config: config,
        atlas_plan: plan
      )
      @jobs << job
      job
    end

    # Enqueues a job from a named Studio preset (including Discord, Web, GIF, Sprite Sheet CLUT8/CLUT4, Audio, Trim)
    def add_preset(input : String, preset_title : String, output : String? = nil) : BatchJob
      base_name = File.basename(input, File.extname(input))

      case preset_title
      when "Sprite Sheet (CLUT8)"
        out_file = output || "#{base_name}_sheet.png"
        cfg = Presets::SpriteSheet.build_config(input, out_file, format: :clut8)
        return add_spritesheet(cfg, preset_name: preset_title)
      when "Sprite Sheet (CLUT4)"
        out_file = output || "#{base_name}_clut4_sheet.png"
        cfg = Presets::SpriteSheet.build_config(input, out_file, format: :clut4)
        return add_spritesheet(cfg, preset_name: preset_title)
      when "Discord (25MB)"
        out_file = output || "#{base_name}_discord25.mp4"
        cmd = Presets::Discord.build_command(input, out_file, target_mb: 24.5)
        job = BatchJob.new(input, out_file, cmd, preset_name: preset_title, job_kind: BatchJob::JobKind::Transcode)
      when "Discord (10MB)"
        out_file = output || "#{base_name}_discord10.mp4"
        cmd = Presets::Discord.build_command(input, out_file, target_mb: 9.5)
        job = BatchJob.new(input, out_file, cmd, preset_name: preset_title, job_kind: BatchJob::JobKind::Transcode)
      when "Web MP4 (FastStart)"
        out_file = output || "#{base_name}_web.mp4"
        cmd = Presets::Web.build_command(input, out_file)
        job = BatchJob.new(input, out_file, cmd, preset_name: preset_title, job_kind: BatchJob::JobKind::Transcode)
      when "High-Definition GIF"
        out_file = output || "#{base_name}.gif"
        cmd = Presets::Gif.build_command(input, out_file)
        job = BatchJob.new(input, out_file, cmd, preset_name: preset_title, job_kind: BatchJob::JobKind::Transcode)
      when "Extract Audio (MP3)"
        out_file = output || "#{base_name}.mp3"
        cmd = Presets::Audio.build_command(input, out_file, format: :mp3)
        job = BatchJob.new(input, out_file, cmd, preset_name: preset_title, job_kind: BatchJob::JobKind::AudioExtract)
      when "Extract Audio (Opus)"
        out_file = output || "#{base_name}.opus"
        cmd = Presets::Audio.build_command(input, out_file, format: :opus)
        job = BatchJob.new(input, out_file, cmd, preset_name: preset_title, job_kind: BatchJob::JobKind::AudioExtract)
      else
        out_file = output || "#{base_name}_trim.mp4"
        cmd = Presets::Trim.build_command(input, out_file, from: "00:00:00", to: "00:00:30")
        job = BatchJob.new(input, out_file, cmd, preset_name: preset_title, job_kind: BatchJob::JobKind::LosslessTrim)
      end

      @jobs << job
      job
    end

    def remove_at(index : Int32) : BatchJob?
      return nil unless index >= 0 && index < @jobs.size
      return nil if @jobs[index].status.running?
      @jobs.delete_at(index)
    end

    def clear_completed! : Int32
      before = @jobs.size
      @jobs.reject! { |j| j.status.completed? || j.status.failed? }
      before - @jobs.size
    end

    def clear! : self
      @jobs.reject!(&.status.running?)
      @jobs.clear if @jobs.none?(&.status.running?)
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

    def pending_count : Int32
      @jobs.count(&.status.pending?)
    end

    def running_count : Int32
      @jobs.count(&.status.running?)
    end

    def completed_count : Int32
      @jobs.count(&.status.completed?)
    end

    def failed_count : Int32
      @jobs.count(&.status.failed?)
    end

    def overall_percent : Float64
      return 0.0 if @jobs.empty?
      sum = 0.0
      @jobs.each { |j| sum += j.effective_percent }
      (sum / @jobs.size.to_f64).clamp(0.0, 100.0)
    end

    # Runs all pending jobs sequentially or up to concurrency limit
    def run : Nil
      @jobs.each do |job|
        next if job.status.completed?
        job.status = BatchJob::Status::Running
        @on_job_start_handlers.each(&.call(job))

        begin
          job.command.run do |p|
            job.progress = p
            @on_job_progress_handlers.each(&.call(job, p))
          end
          if (cfg = job.sprite_config) && (plan = job.atlas_plan)
            SpriteSheet::DSL::SpriteSheetBuilder.new(cfg).write_sidecars!(plan)
          end
          job.progress = Runner::Progress.new(
            frame: job.progress.frame,
            fps: job.progress.fps,
            q: job.progress.q,
            size_bytes: job.progress.size_bytes,
            current_time: job.progress.current_time,
            total_duration: job.progress.total_duration,
            percent: 100.0,
            bitrate_kbps: job.progress.bitrate_kbps,
            speed: job.progress.speed,
            eta: Time::Span.zero
          )
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

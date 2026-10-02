require "./progress"
require "../config"
require "../error"

module Flourite
  module Runner
    class ProcessRunner
      getter args : Array(String)
      getter total_duration : Time::Span?
      getter latest_progress : Progress
      getter? running : Bool = false
      getter exit_status : Process::Status? = nil
      getter error_log : IO::Memory = IO::Memory.new

      @process : Process? = nil
      @on_start_handlers = [] of String -> Nil
      @on_progress_handlers = [] of Progress -> Nil
      @on_log_handlers = [] of String -> Nil
      @on_finish_handlers = [] of Process::Status -> Nil
      @on_error_handlers = [] of Exception -> Nil

      def initialize(@args : Array(String), @total_duration : Time::Span? = nil)
        @latest_progress = Progress.new(total_duration: @total_duration)
      end

      def on_start(&block : String -> Nil) : self
        @on_start_handlers << block
        self
      end

      def on_progress(&block : Progress -> Nil) : self
        @on_progress_handlers << block
        self
      end

      def on_log(&block : String -> Nil) : self
        @on_log_handlers << block
        self
      end

      def on_finish(&block : Process::Status -> Nil) : self
        @on_finish_handlers << block
        self
      end

      def on_error(&block : Exception -> Nil) : self
        @on_error_handlers << block
        self
      end

      def command_string : String
        ffmpeg = Flourite.config.ffmpeg_path
        all_args = [ffmpeg] + @args
        all_args.map { |a| a.includes?(' ') ? "\"#{a}\"" : a }.join(' ')
      end

      # Executes the command synchronously, blocking until finished
      def run : Process::Status
        run_async
        wait
      end

      # Launches execution in background fibers
      def run_async : self
        ffmpeg = Flourite.config.ffmpeg_path

        # Inject -progress pipe:1 and -nostats to ensure machine-readable stdout progress
        actual_args = [] of String
        actual_args << "-progress" << "pipe:1" << "-nostats"
        actual_args.concat(@args)

        @on_start_handlers.each(&.call(command_string))

        proc = Process.new(
          ffmpeg,
          actual_args,
          output: Process::Redirect::Pipe,
          error: Process::Redirect::Pipe
        )
        @process = proc
        @running = true

        # Fiber to parse stdout key=value progress lines
        spawn do
          parse_progress_stream(proc.output)
        rescue ex
          # ignore pipe closed errors on exit
        end

        # Fiber to capture and stream stderr logs
        spawn do
          parse_stderr_stream(proc.error)
        rescue ex
          # ignore pipe closed errors on exit
        end

        self
      end

      # Waits for the running process to complete
      def wait : Process::Status
        proc = @process
        raise Error.new("Process has not been started") unless proc

        status = proc.wait
        @exit_status = status
        @running = false

        if status.success?
          @on_finish_handlers.each(&.call(status))
        else
          err = ExecutionError.new(command_string, status.exit_code, @error_log.to_s)
          @on_error_handlers.each(&.call(err))
          raise err
        end

        status
      end

      # Gracefully terminates or kills the process
      def kill : Nil
        if proc = @process
          proc.terminate
          @running = false
        end
      end

      private def parse_progress_stream(io : IO) : Nil
        current_frame = 0_i64
        current_fps = 0.0
        current_q = 0.0
        current_size = 0_i64
        current_time = Time::Span.zero
        current_bitrate = 0.0
        current_speed = 0.0

        io.each_line do |line|
          trimmed = line.strip
          next if trimmed.empty?

          if idx = trimmed.index('=')
            key = trimmed[0...idx].strip
            val = trimmed[(idx + 1)..].strip

            case key
            when "frame"
              current_frame = val.to_i64? || current_frame
            when "fps"
              current_fps = val.to_f64? || current_fps
            when "out_time_us"
              if us = val.to_i64?
                current_time = Time::Span.new(nanoseconds: us * 1_000)
              end
            when "out_time"
              if span = parse_time_string(val)
                current_time = span
              end
            when "total_size"
              current_size = val.to_i64? || current_size
            when "bitrate"
              # e.g. "  450.2kbits/s"
              clean_br = val.gsub(/[^\d.]/, "")
              current_bitrate = clean_br.to_f64? || current_bitrate
            when "speed"
              # e.g. "1.85x"
              clean_sp = val.gsub('x', "").strip
              current_speed = clean_sp.to_f64? || current_speed
            when "progress"
              # Calculate percent and ETA
              pct = 0.0
              eta = nil

              if td = @total_duration
                total_sec = td.total_seconds
                if total_sec > 0
                  pct = (current_time.total_seconds / total_sec) * 100.0
                  pct = 100.0 if val == "end"
                  pct = pct.clamp(0.0, 100.0)

                  rem_sec = [total_sec - current_time.total_seconds, 0.0].max
                  if current_speed > 0
                    eta_sec = rem_sec / current_speed
                    eta = Time::Span.new(seconds: eta_sec.to_i)
                  end
                end
              end

              prog = Progress.new(
                frame: current_frame,
                fps: current_fps,
                q: current_q,
                size_bytes: current_size,
                current_time: current_time,
                total_duration: @total_duration,
                percent: pct,
                bitrate_kbps: current_bitrate,
                speed: current_speed,
                eta: eta
              )
              @latest_progress = prog
              @on_progress_handlers.each(&.call(prog))
            end
          end
        end
      end

      private def parse_stderr_stream(io : IO) : Nil
        io.each_line do |line|
          @error_log.puts(line)
          @on_log_handlers.each(&.call(line))
        end
      end

      private def parse_time_string(val : String) : Time::Span?
        # Format: HH:MM:SS.micro
        parts = val.split(':')
        if parts.size == 3
          h = parts[0].to_i? || 0
          m = parts[1].to_i? || 0
          sec_parts = parts[2].split('.')
          s = sec_parts[0].to_i? || 0
          ms = sec_parts[1]?.try(&.[0..2].to_i?) || 0
          Time::Span.new(days: 0, hours: h, minutes: m, seconds: s, nanoseconds: ms * 1_000_000)
        else
          nil
        end
      rescue
        nil
      end
    end
  end
end

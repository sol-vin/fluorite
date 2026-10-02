require "./input"
require "./output"
require "./filter_graph"
require "../runner/process_runner"
require "../probe/runner"

module Flourite
  module DSL
    class Command
      getter inputs : Array(Input) = [] of Input
      getter outputs : Array(Output) = [] of Output
      getter filter_graph : FilterGraph = FilterGraph.new
      getter global_options : Array(String) = [] of String
      property threads_count : Int32? = nil
      property overwrite_mode : Bool = true
      property hwaccel_mode : String? = nil

      def initialize
      end

      def threads(n : Int32) : self
        @threads_count = n
        self
      end

      def overwrite! : self
        @overwrite_mode = true
        self
      end

      def no_overwrite! : self
        @overwrite_mode = false
        self
      end

      def hwaccel(accel : String | Symbol) : self
        @hwaccel_mode = accel.to_s
        self
      end

      def global_option(flag : String, value : String? = nil) : self
        @global_options << flag
        @global_options << value if value
        self
      end

      def add_input(input : Input) : self
        @inputs << input
        self
      end

      def add_output(output : Output) : self
        @outputs << output
        self
      end

      # Assembles arguments into array for process execution
      def to_args : Array(String)
        args = [] of String

        # Global flags
        args << "-y" if @overwrite_mode
        args << "-threads" << @threads_count.to_s if @threads_count
        args << "-hwaccel" << @hwaccel_mode.not_nil! if @hwaccel_mode
        args.concat(@global_options)

        # Inputs
        @inputs.each do |inp|
          args.concat(inp.to_args)
        end

        # Filter graph
        unless @filter_graph.empty?
          args.concat(@filter_graph.to_args)
        end

        # Outputs
        @outputs.each do |outp|
          args.concat(outp.to_args)
        end

        args
      end

      def to_cmd_string : String
        ffmpeg = Flourite.config.ffmpeg_path
        all_args = [ffmpeg] + to_args
        all_args.map { |a| a.includes?(' ') ? "\"#{a}\"" : a }.join(' ')
      end

      # Attempts to determine duration of first input for progress percentage
      def estimate_duration : Time::Span?
        first_input = @inputs.first?
        return nil unless first_input

        # Check if input had an explicit duration set
        if dur_str = first_input.duration_time
          if sec = dur_str.to_f64?
            return Time::Span.new(seconds: sec.to_i)
          end
        end

        # Try probing file
        if File.exists?(first_input.path)
          probe_result = Flourite.probe(first_input.path)
          return probe_result.duration
        end

        nil
      rescue
        nil
      end

      # Runs command synchronously with optional progress block
      def run(&block : Runner::Progress -> Nil) : Process::Status
        runner = create_runner
        runner.on_progress(&block)
        runner.run
      end

      def run : Process::Status
        create_runner.run
      end

      # Runs command asynchronously returning the ProcessRunner
      def run_async : Runner::ProcessRunner
        runner = create_runner
        runner.run_async
        runner
      end

      private def create_runner : Runner::ProcessRunner
        Runner::ProcessRunner.new(to_args, estimate_duration)
      end
    end
  end
end

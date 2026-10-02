require "./command"

module Flourite
  module DSL
    class VideoConfig
      getter output : Output

      def initialize(@output : Output)
      end

      def codec(codec_name : String | Symbol) : self
        @output.video_codec(codec_name)
        self
      end

      def video_codec(codec_name : String | Symbol) : self
        codec(codec_name)
      end

      def crf(val : Int32) : self
        @output.crf(val)
        self
      end

      def preset(val : String | Symbol) : self
        @output.preset(val)
        self
      end

      def bitrate(val : String | Int32) : self
        @output.video_bitrate(val)
        self
      end

      def video_bitrate(val : String | Int32) : self
        bitrate(val)
      end

      def maxrate(val : String | Int32) : self
        @output.maxrate(val)
        self
      end

      def bufsize(val : String | Int32) : self
        @output.bufsize(val)
        self
      end

      def scale(w : Int32, h : Int32) : self
        @output.scale(w, h)
        self
      end

      def fps(r : Float64 | Int32) : self
        @output.fps(r)
        self
      end

      def pixel_format(fmt : String) : self
        @output.pixel_format(fmt)
        self
      end

      def copy : self
        @output.copy_video
        self
      end
    end

    class AudioConfig
      getter output : Output

      def initialize(@output : Output)
      end

      def codec(codec_name : String | Symbol) : self
        @output.audio_codec(codec_name)
        self
      end

      def audio_codec(codec_name : String | Symbol) : self
        codec(codec_name)
      end

      def bitrate(val : String | Int32) : self
        @output.audio_bitrate(val)
        self
      end

      def audio_bitrate(val : String | Int32) : self
        bitrate(val)
      end

      def channels(c : Int32) : self
        @output.channels(c)
        self
      end

      def sample_rate(sr : Int32) : self
        @output.sample_rate(sr)
        self
      end

      def copy : self
        @output.copy_audio
        self
      end
    end

    class Builder
      getter command : Command

      def initialize
        @command = Command.new
      end

      def threads(n : Int32) : self
        @command.threads(n)
        self
      end

      def overwrite! : self
        @command.overwrite!
        self
      end

      def no_overwrite! : self
        @command.no_overwrite!
        self
      end

      def hwaccel(accel : String | Symbol) : self
        @command.hwaccel(accel)
        self
      end

      def input(path : String, &) : Input
        inp = Input.new(path)
        with inp yield inp
        @command.add_input(inp)
        inp
      end

      def input(path : String) : Input
        inp = Input.new(path)
        @command.add_input(inp)
        inp
      end

      def output(path : String, &) : Output
        outp = if last = @command.outputs.last?
                 if last.path.empty?
                   last.path = path
                   last
                 else
                   new_out = Output.new(path)
                   @command.add_output(new_out)
                   new_out
                 end
               else
                 new_out = Output.new(path)
                 @command.add_output(new_out)
                 new_out
               end
        with outp yield outp
        outp
      end

      def output(path : String) : Output
        if last = @command.outputs.last?
          if last.path.empty?
            last.path = path
            return last
          end
        end
        outp = Output.new(path)
        @command.add_output(outp)
        outp
      end

      # Configures video options on the current/last output
      def video(&) : self
        outp = @command.outputs.last? || begin
          new_out = Output.new("")
          @command.add_output(new_out)
          new_out
        end
        vc = VideoConfig.new(outp)
        with vc yield vc
        self
      end

      # Configures audio options on the current/last output
      def audio(&) : self
        outp = @command.outputs.last? || begin
          new_out = Output.new("")
          @command.add_output(new_out)
          new_out
        end
        ac = AudioConfig.new(outp)
        with ac yield ac
        self
      end

      # Configures filtergraph
      def filter(&) : self
        with @command.filter_graph yield @command.filter_graph
        self
      end
    end

    class ChainBuilder
      getter command : Command
      getter current_input : Input
      getter current_output : Output

      def initialize(input_path : String)
        @command = Command.new
        @current_input = Input.new(input_path)
        @current_output = Output.new("")
        @command.add_input(@current_input)
        @command.add_output(@current_output)
      end

      def to(output_path : String) : self
        @current_output.path = output_path
        self
      end

      def output(output_path : String) : self
        to(output_path)
      end

      def video_codec(codec : String | Symbol) : self
        @current_output.video_codec(codec)
        self
      end

      def codec(codec : String | Symbol) : self
        video_codec(codec)
      end

      def audio_codec(codec : String | Symbol) : self
        @current_output.audio_codec(codec)
        self
      end

      def crf(val : Int32) : self
        @current_output.crf(val)
        self
      end

      def preset(p : String | Symbol) : self
        @current_output.preset(p)
        self
      end

      def scale(w : Int32, h : Int32) : self
        @current_output.scale(w, h)
        self
      end

      def fps(rate : Float64 | Int32) : self
        @current_output.fps(rate)
        self
      end

      def video_bitrate(br : String | Int32) : self
        @current_output.video_bitrate(br)
        self
      end

      def audio_bitrate(br : String | Int32) : self
        @current_output.audio_bitrate(br)
        self
      end

      def faststart(enable : Bool = true) : self
        @current_output.faststart(enable)
        self
      end

      def seek(time : Time::Span | String | Number) : self
        @current_input.seek(time)
        self
      end

      def duration(time : Time::Span | String | Number) : self
        @current_input.duration(time)
        self
      end

      def hwaccel(accel : String | Symbol) : self
        @command.hwaccel(accel)
        self
      end

      def to_cmd_string : String
        @command.to_cmd_string
      end

      def run(&block : Runner::Progress -> Nil) : Process::Status
        @command.run(&block)
      end

      def run : Process::Status
        @command.run
      end

      def run_async : Runner::ProcessRunner
        @command.run_async
      end
    end
  end

  # Fluent block builder: Flourite.build { ... }
  def self.build(&)
    builder = DSL::Builder.new
    with builder yield builder
    builder.command
  end

  # Chainable builder: Flourite.input("file.mp4").video_codec(:h264)...
  def self.input(path : String) : DSL::ChainBuilder
    DSL::ChainBuilder.new(path)
  end

  # Chainable builder alias: Flourite.convert("in.mp4").to("out.mp4")
  def self.convert(input_path : String) : DSL::ChainBuilder
    DSL::ChainBuilder.new(input_path)
  end
end

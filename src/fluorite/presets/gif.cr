require "./base"

module Fluorite
  module Presets
    class Gif < Base
      def self.convert(
        input_path : String,
        output_path : String,
        fps : Int32 = 15,
        width : Int32 = 480,
        seek : (String | Time::Span)? = nil,
        duration : (String | Time::Span)? = nil,
        &progress_block : Runner::Progress -> Nil
      ) : Process::Status
        cmd = build_command(input_path, output_path, fps, width, seek, duration)
        cmd.run(&progress_block)
      end

      def self.convert(
        input_path : String,
        output_path : String,
        fps : Int32 = 15,
        width : Int32 = 480,
        seek : (String | Time::Span)? = nil,
        duration : (String | Time::Span)? = nil,
      ) : Process::Status
        cmd = build_command(input_path, output_path, fps, width, seek, duration)
        cmd.run
      end

      def self.build_command(
        input_path : String,
        output_path : String,
        fps : Int32 = 15,
        width : Int32 = 480,
        seek : (String | Time::Span)? = nil,
        duration : (String | Time::Span)? = nil,
      ) : DSL::Command
        Fluorite.build do
          overwrite!

          input(input_path) do |inp|
            inp.seek(seek) if seek
            inp.duration(duration) if duration
          end

          filter do |f|
            f.palette_gif(fps_val: fps, scale_w: width)
          end

          output(output_path)
        end
      end
    end
  end
end

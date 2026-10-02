require "./base"

module Flourite
  module Presets
    class Trim < Base
      # Fast lossless stream-copy trim in milliseconds without re-encoding
      def self.cut(
        input_path : String,
        output_path : String,
        from : String | Time::Span,
        to : (String | Time::Span)? = nil,
        duration : (String | Time::Span)? = nil,
      ) : Process::Status
        cmd = build_command(input_path, output_path, from, to, duration)
        cmd.run
      end

      def self.build_command(
        input_path : String,
        output_path : String,
        from : String | Time::Span,
        to : (String | Time::Span)? = nil,
        duration : (String | Time::Span)? = nil,
      ) : DSL::Command
        Flourite.build do
          overwrite!

          input(input_path) do |inp|
            inp.seek(from)
            inp.duration(duration) if duration
          end

          output(output_path) do |outp|
            outp.copy
            if to && !duration
              # -to flag on output
              to_str = to.is_a?(Time::Span) ? sprintf("%02d:%02d:%02d.%03d", to.hours, to.minutes, to.seconds, to.milliseconds) : to.to_s
              outp.option("-to", to_str)
            end
          end
        end
      end
    end

    class Thumbnail < Base
      # Extracts a single high quality frame at specified timestamp
      def self.capture(
        input_path : String,
        output_path : String,
        at : String | Time::Span = "00:00:01",
        width : Int32? = nil,
      ) : Process::Status
        cmd = build_command(input_path, output_path, at, width)
        cmd.run
      end

      def self.build_command(
        input_path : String,
        output_path : String,
        at : String | Time::Span = "00:00:01",
        width : Int32? = nil,
      ) : DSL::Command
        Flourite.build do
          overwrite!

          input(input_path) do |inp|
            inp.seek(at)
          end

          if w = width
            filter do |f|
              f.scale(w, -1)
            end
          end

          output(output_path) do |outp|
            outp.option("-vframes", "1")
            outp.option("-q:v", "2")
          end
        end
      end
    end
  end
end

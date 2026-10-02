require "./base"

module Fluorite
  module Presets
    class Web < Base
      def self.convert(
        input_path : String,
        output_path : String,
        crf : Int32 = 22,
        preset : Symbol = :medium,
        &progress_block : Runner::Progress -> Nil
      ) : Process::Status
        cmd = build_command(input_path, output_path, crf, preset)
        cmd.run(&progress_block)
      end

      def self.convert(
        input_path : String,
        output_path : String,
        crf : Int32 = 22,
        preset : Symbol = :medium,
      ) : Process::Status
        cmd = build_command(input_path, output_path, crf, preset)
        cmd.run
      end

      def self.build_command(
        input_path : String,
        output_path : String,
        crf : Int32 = 22,
        preset : Symbol = :medium,
      ) : DSL::Command
        Fluorite.build do
          overwrite!

          input(input_path)

          video do |v|
            v.video_codec("libx264")
            v.crf(crf)
            v.preset(preset)
            v.pixel_format("yuv420p")
          end

          audio do |a|
            a.audio_codec("aac")
            a.audio_bitrate("192k")
          end

          output(output_path) do |outp|
            outp.faststart!
          end
        end
      end
    end
  end
end

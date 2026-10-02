require "./base"

module Flourite
  module Presets
    class Audio < Base
      # Extracts audio to target format: :mp3, :opus, :aac, :flac, :wav
      def self.extract(
        input_path : String,
        output_path : String,
        format : Symbol = :mp3,
        bitrate : String = "320k",
        &progress_block : Runner::Progress -> Nil
      ) : Process::Status
        cmd = build_command(input_path, output_path, format, bitrate)
        cmd.run(&progress_block)
      end

      def self.extract(
        input_path : String,
        output_path : String,
        format : Symbol = :mp3,
        bitrate : String = "320k",
      ) : Process::Status
        cmd = build_command(input_path, output_path, format, bitrate)
        cmd.run
      end

      def self.build_command(
        input_path : String,
        output_path : String,
        format : Symbol = :mp3,
        bitrate : String = "320k",
      ) : DSL::Command
        Flourite.build do
          overwrite!
          input(input_path)

          output(output_path) do |outp|
            outp.no_video

            case format
            when :mp3
              outp.audio_codec("libmp3lame")
              outp.audio_bitrate(bitrate)
            when :opus
              outp.audio_codec("libopus")
              outp.audio_bitrate(bitrate == "320k" ? "160k" : bitrate)
            when :aac
              outp.audio_codec("aac")
              outp.audio_bitrate(bitrate == "320k" ? "256k" : bitrate)
            when :flac
              outp.audio_codec("flac")
            when :wav
              outp.audio_codec("pcm_s16le")
            else
              outp.audio_codec(format.to_s)
            end
          end
        end
      end
    end
  end
end

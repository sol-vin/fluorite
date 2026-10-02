require "./base"

module Flourite
  module Presets
    class Discord < Base
      # Calculates ideal bitrates and encodes input to strictly fit under Discord target size in MB
      def self.convert(
        input_path : String,
        output_path : String,
        target_mb : Float64 = 24.5,
        hwaccel : Symbol? = nil,
        &progress_block : Runner::Progress -> Nil
      ) : Process::Status
        cmd = build_command(input_path, output_path, target_mb, hwaccel)
        cmd.run(&progress_block)
      end

      # Non-blocking overload without progress block
      def self.convert(
        input_path : String,
        output_path : String,
        target_mb : Float64 = 24.5,
        hwaccel : Symbol? = nil
      ) : Process::Status
        cmd = build_command(input_path, output_path, target_mb, hwaccel)
        cmd.run
      end

      # Builds the DSL::Command without executing it (useful for inspection or customization)
      def self.build_command(
        input_path : String,
        output_path : String,
        target_mb : Float64 = 24.5,
        hwaccel : Symbol? = nil
      ) : DSL::Command
        info = Flourite.probe(input_path)
        duration_sec = info.duration.total_seconds
        raise Error.new("Could not determine duration for #{input_path}") if duration_sec <= 0.0

        # Total allowed bits with 5% safety margin for muxing/container overhead
        total_bits = target_mb * 1024.0 * 1024.0 * 8.0 * 0.95

        # Choose audio bitrate based on duration
        audio_bitrate_kbps = if duration_sec > 600
                               64
                             elsif duration_sec > 180
                               96
                             else
                               128
                             end

        audio_bits = audio_bitrate_kbps.to_f64 * 1000.0 * duration_sec
        video_bits = [total_bits - audio_bits, 100_000.0].max
        video_bitrate_kbps = (video_bits / duration_sec / 1000.0).to_i

        # Auto-downscale if video bitrate is constrained to maintain visual sharpness
        scale_target = if video_bitrate_kbps < 500
                         {854, 480}
                       elsif video_bitrate_kbps < 1200
                         {1280, 720}
                       else
                         nil
                       end

        # Pick video encoder
        vcodec = if hwaccel == :cuda && Flourite.config.nvenc_available?
                   "h264_nvenc"
                 else
                   "libx264"
                 end

        Flourite.build do
          overwrite!

          input(input_path) do |inp|
            inp.hwaccel(hwaccel) if hwaccel
          end

          video do |v|
            v.video_codec(vcodec)
            v.video_bitrate("#{video_bitrate_kbps}k")
            v.maxrate("#{(video_bitrate_kbps * 1.2).to_i}k")
            v.bufsize("#{(video_bitrate_kbps * 2).to_i}k")
            v.pixel_format("yuv420p")
            v.preset(:medium)
            if s = scale_target
              v.scale(s[0], s[1])
            end
          end

          audio do |a|
            a.audio_codec("aac")
            a.audio_bitrate("#{audio_bitrate_kbps}k")
          end

          output(output_path) do |outp|
            outp.faststart!
          end
        end
      end
    end
  end
end

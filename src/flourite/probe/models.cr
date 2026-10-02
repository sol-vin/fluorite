require "json"

module Flourite
  module Probe
    struct Stream
      include JSON::Serializable

      getter index : Int32 = 0
      getter codec_name : String? = nil
      getter codec_long_name : String? = nil
      getter codec_type : String? = nil # "video", "audio", "subtitle", "data"
      getter profile : String? = nil
      getter width : Int32? = nil
      getter height : Int32? = nil
      getter sample_aspect_ratio : String? = nil
      getter display_aspect_ratio : String? = nil
      getter pix_fmt : String? = nil
      getter r_frame_rate : String? = nil
      getter avg_frame_rate : String? = nil
      getter time_base : String? = nil
      getter start_time : String? = nil
      getter duration : String? = nil
      getter bit_rate : String? = nil
      getter max_bit_rate : String? = nil
      getter nb_frames : String? = nil
      getter sample_rate : String? = nil
      getter channels : Int32? = nil
      getter channel_layout : String? = nil
      getter bits_per_sample : Int32? = nil
      getter tags : Hash(String, String)? = nil

      def initialize(
        @index : Int32 = 0,
        @codec_name : String? = nil,
        @codec_long_name : String? = nil,
        @codec_type : String? = nil,
        @profile : String? = nil,
        @width : Int32? = nil,
        @height : Int32? = nil,
        @sample_aspect_ratio : String? = nil,
        @display_aspect_ratio : String? = nil,
        @pix_fmt : String? = nil,
        @r_frame_rate : String? = nil,
        @avg_frame_rate : String? = nil,
        @time_base : String? = nil,
        @start_time : String? = nil,
        @duration : String? = nil,
        @bit_rate : String? = nil,
        @max_bit_rate : String? = nil,
        @nb_frames : String? = nil,
        @sample_rate : String? = nil,
        @channels : Int32? = nil,
        @channel_layout : String? = nil,
        @bits_per_sample : Int32? = nil,
        @tags : Hash(String, String)? = nil,
      )
      end

      def video? : Bool
        codec_type == "video"
      end

      def audio? : Bool
        codec_type == "audio"
      end

      def subtitle? : Bool
        codec_type == "subtitle"
      end

      # Parses fractional framerate (e.g. "60/1" or "30000/1001") into Float64
      def fps : Float64
        str = avg_frame_rate || r_frame_rate || ""
        return 0.0 if str.empty? || str == "0/0"

        if str.includes?('/')
          parts = str.split('/')
          num = parts[0]?.try(&.to_f64?) || 0.0
          den = parts[1]?.try(&.to_f64?) || 1.0
          den.zero? ? 0.0 : (num / den)
        else
          str.to_f64? || 0.0
        end
      end

      def duration_span : Time::Span?
        if dur_str = duration
          if sec = dur_str.to_f64?
            return Time::Span.new(nanoseconds: (sec * 1_000_000_000).to_i64)
          end
        end
        nil
      end

      def bitrate_kbps : Int32?
        if br = bit_rate
          if val = br.to_i64?
            return (val / 1000).to_i32
          end
        end
        nil
      end

      def resolution : Tuple(Int32, Int32)?
        if (w = width) && (h = height)
          {w, h}
        else
          nil
        end
      end

      def aspect_ratio_str : String
        if dar = display_aspect_ratio
          return dar unless dar.empty? || dar == "0:1"
        end

        if (w = width) && (h = height) && h > 0
          g = w.gcd(h)
          "#{w // g}:#{h // g}"
        else
          "N/A"
        end
      end

      def summary : String
        if video?
          res = resolution ? "#{resolution.not_nil![0]}x#{resolution.not_nil![1]}" : "unknown res"
          fps_s = fps > 0 ? " @ #{fps.round(2)} fps" : ""
          pix = pix_fmt ? " (#{pix_fmt})" : ""
          br = bitrate_kbps ? " [#{bitrate_kbps} kbps]" : ""
          "Video: #{codec_name || "unknown"} #{res}#{fps_s}#{pix}#{br}"
        elsif audio?
          sr = sample_rate ? "#{sample_rate} Hz" : "unknown Hz"
          ch = channels ? "#{channels}ch (#{channel_layout || "stereo"})" : "channels unknown"
          br = bitrate_kbps ? " @ #{bitrate_kbps} kbps" : ""
          "Audio: #{codec_name || "unknown"} #{ch}#{br}, #{sr}"
        elsif subtitle?
          lang = tags.try(&.[]?("language")) || "und"
          "Subtitle: #{codec_name || "unknown"} [#{lang}]"
        else
          "#{codec_type || "Unknown stream"}: #{codec_name || "unknown"}"
        end
      end
    end

    struct Format
      include JSON::Serializable

      getter filename : String? = nil
      getter nb_streams : Int32 = 0
      getter nb_programs : Int32 = 0
      getter format_name : String? = nil
      getter format_long_name : String? = nil
      getter start_time : String? = nil
      getter duration : String? = nil
      getter size : String? = nil
      getter bit_rate : String? = nil
      getter probe_score : Int32? = nil
      getter tags : Hash(String, String)? = nil

      def initialize(
        @filename : String? = nil,
        @nb_streams : Int32 = 0,
        @nb_programs : Int32 = 0,
        @format_name : String? = nil,
        @format_long_name : String? = nil,
        @start_time : String? = nil,
        @duration : String? = nil,
        @size : String? = nil,
        @bit_rate : String? = nil,
        @probe_score : Int32? = nil,
        @tags : Hash(String, String)? = nil,
      )
      end

      def size_bytes : Int64
        size.try(&.to_i64?) || 0_i64
      end

      def duration_seconds : Float64
        duration.try(&.to_f64?) || 0.0
      end

      def duration_span : Time::Span
        Time::Span.new(nanoseconds: (duration_seconds * 1_000_000_000).to_i64)
      end

      def bitrate_kbps : Int32
        (((bit_rate.try(&.to_i64?) || 0_i64) // 1000)).to_i32
      end

      def human_size : String
        bytes = size_bytes.to_f64
        units = ["B", "KB", "MB", "GB", "TB"]
        idx = 0
        while bytes >= 1024.0 && idx < units.size - 1
          bytes /= 1024.0
          idx += 1
        end
        "#{bytes.round(2)} #{units[idx]}"
      end
    end

    struct Chapter
      include JSON::Serializable

      getter id : Int64 = 0
      getter time_base : String? = nil
      getter start : Int64 = 0
      getter start_time : String? = nil
      getter end_time : String? = nil
      getter tags : Hash(String, String)? = nil

      def initialize(
        @id : Int64 = 0,
        @time_base : String? = nil,
        @start : Int64 = 0,
        @start_time : String? = nil,
        @end_time : String? = nil,
        @tags : Hash(String, String)? = nil,
      )
      end

      def title : String?
        tags.try(&.[]?("title"))
      end
    end

    struct ProbeResult
      include JSON::Serializable

      getter streams : Array(Stream) = [] of Stream
      getter format : Format = Format.new
      getter chapters : Array(Chapter) = [] of Chapter

      def initialize(
        @streams : Array(Stream) = [] of Stream,
        @format : Format = Format.new,
        @chapters : Array(Chapter) = [] of Chapter,
      )
      end

      def video_streams : Array(Stream)
        streams.select(&.video?)
      end

      def audio_streams : Array(Stream)
        streams.select(&.audio?)
      end

      def subtitle_streams : Array(Stream)
        streams.select(&.subtitle?)
      end

      def primary_video_stream : Stream?
        video_streams.first?
      end

      def primary_audio_stream : Stream?
        audio_streams.first?
      end

      def duration : Time::Span
        if primary_vid = primary_video_stream
          if d = primary_vid.duration_span
            return d if d.total_seconds > 0
          end
        end
        format.duration_span
      end

      def duration_formatted : String
        dur = duration
        hours = dur.hours
        minutes = dur.minutes
        seconds = dur.seconds
        millis = dur.milliseconds
        sprintf("%02d:%02d:%02d.%02d", hours, minutes, seconds, millis // 10)
      end

      def resolution : Tuple(Int32, Int32)?
        primary_video_stream.try(&.resolution)
      end

      def fps : Float64
        primary_video_stream.try(&.fps) || 0.0
      end

      def human_size : String
        format.human_size
      end

      def format_name : String
        format.format_name || "unknown"
      end

      def video_summary : String
        primary_video_stream.try(&.summary) || "No video stream"
      end

      def audio_summary : String
        primary_audio_stream.try(&.summary) || "No audio stream"
      end
    end
  end
end

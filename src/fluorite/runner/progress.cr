module Fluorite
  module Runner
    struct Progress
      property frame : Int64 = 0_i64
      property fps : Float64 = 0.0
      property q : Float64 = 0.0
      property size_bytes : Int64 = 0_i64
      property current_time : Time::Span = Time::Span.zero
      property total_duration : Time::Span? = nil
      property percent : Float64 = 0.0
      property bitrate_kbps : Float64 = 0.0
      property speed : Float64 = 0.0
      property eta : Time::Span? = nil

      def initialize(
        @frame : Int64 = 0_i64,
        @fps : Float64 = 0.0,
        @q : Float64 = 0.0,
        @size_bytes : Int64 = 0_i64,
        @current_time : Time::Span = Time::Span.zero,
        @total_duration : Time::Span? = nil,
        @percent : Float64 = 0.0,
        @bitrate_kbps : Float64 = 0.0,
        @speed : Float64 = 0.0,
        @eta : Time::Span? = nil,
      )
      end

      # Formats time span as HH:MM:SS
      def self.format_span(span : Time::Span) : String
        h = span.hours
        m = span.minutes
        s = span.seconds
        sprintf("%02d:%02d:%02d", h, m, s)
      end

      def time_formatted : String
        Progress.format_span(@current_time)
      end

      def total_formatted : String
        if td = @total_duration
          Progress.format_span(td)
        else
          "--:--:--"
        end
      end

      def eta_formatted : String
        if e = @eta
          Progress.format_span(e)
        else
          "--:--:--"
        end
      end

      def speed_formatted : String
        if @speed > 0
          sprintf("%.2fx", @speed)
        else
          "0.00x"
        end
      end

      def human_size : String
        bytes = @size_bytes.to_f64
        units = ["B", "KB", "MB", "GB"]
        idx = 0
        while bytes >= 1024.0 && idx < units.size - 1
          bytes /= 1024.0
          idx += 1
        end
        "#{bytes.round(1)} #{units[idx]}"
      end

      # Generates a smooth Unicode progress bar
      def bar(width : Int32 = 25) : String
        clamped = @percent.clamp(0.0, 100.0)
        filled_length = ((clamped / 100.0) * width).to_i
        empty_length = width - filled_length

        chars = "█" * filled_length
        spaces = "░" * empty_length
        "[#{chars}#{spaces}] #{sprintf("%5.1f%%", clamped)}"
      end
    end
  end
end

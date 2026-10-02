module Fluorite
  module DSL
    class Input
      property path : String
      property seek_time : String? = nil
      property duration_time : String? = nil
      property format_name : String? = nil
      property hwaccel_name : String? = nil
      property loop_count : Int32? = nil
      property input_fps : Float64? = nil
      property raw_options : Array(String) = [] of String

      def initialize(@path : String)
      end

      # Seeks to timestamp prior to reading (fast keyframe seek)
      def seek(time : Time::Span | String | Number) : self
        @seek_time = case time
                     when Time::Span
                       sprintf("%02d:%02d:%02d.%03d", time.hours, time.minutes, time.seconds, time.milliseconds)
                     else
                       time.to_s
                     end
        self
      end

      # Limits duration of reading
      def duration(time : Time::Span | String | Number) : self
        @duration_time = case time
                         when Time::Span
                           sprintf("%02d:%02d:%02d.%03d", time.hours, time.minutes, time.seconds, time.milliseconds)
                         else
                           time.to_s
                         end
        self
      end

      def format(name : String) : self
        @format_name = name
        self
      end

      def hwaccel(accel : String | Symbol) : self
        @hwaccel_name = accel.to_s
        self
      end

      def loop(count : Int32) : self
        @loop_count = count
        self
      end

      def fps(rate : Float64 | Int32) : self
        @input_fps = rate.to_f64
        self
      end

      def option(flag : String, value : String? = nil) : self
        @raw_options << flag
        @raw_options << value if value
        self
      end

      def to_args : Array(String)
        args = [] of String
        if ha = @hwaccel_name
          args << "-hwaccel" << ha
        end
        if sk = @seek_time
          args << "-ss" << sk
        end
        if dur = @duration_time
          args << "-t" << dur
        end
        if fmt = @format_name
          args << "-f" << fmt
        end
        if lc = @loop_count
          args << "-stream_loop" << lc.to_s
        end
        if r = @input_fps
          args << "-r" << r.to_s
        end
        args.concat(@raw_options)
        args << "-i" << @path
        args
      end
    end
  end
end

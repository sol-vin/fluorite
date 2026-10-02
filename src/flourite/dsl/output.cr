module Flourite
  module DSL
    class Output
      property path : String
      property format_name : String? = nil
      property vcodec : String? = nil
      property acodec : String? = nil
      property scodec : String? = nil
      property crf_val : Int32? = nil
      property preset_name : String? = nil
      property pix_fmt : String? = nil
      property v_bitrate : String? = nil
      property a_bitrate : String? = nil
      property max_bitrate : String? = nil
      property buffer_size : String? = nil
      property frame_rate : Float64? = nil
      property scale_size : Tuple(Int32, Int32)? = nil
      property channels_count : Int32? = nil
      property sample_rate_val : Int32? = nil
      property faststart_flag : Bool = false
      property shortest_flag : Bool = false
      property overwrite_flag : Bool = true
      property threads_count : Int32? = nil
      property map_streams : Array(String) = [] of String
      property raw_options : Array(String) = [] of String

      def initialize(@path : String)
      end

      def video_codec(codec : String | Symbol) : self
        @vcodec = codec.to_s
        self
      end

      def codec(codec : String | Symbol) : self
        video_codec(codec)
      end

      def audio_codec(codec : String | Symbol) : self
        @acodec = codec.to_s
        self
      end

      def subtitle_codec(codec : String | Symbol) : self
        @scodec = codec.to_s
        self
      end

      def copy : self
        @vcodec = "copy"
        @acodec = "copy"
        self
      end

      def copy_video : self
        @vcodec = "copy"
        self
      end

      def copy_audio : self
        @acodec = "copy"
        self
      end

      def no_video : self
        @raw_options << "-vn"
        self
      end

      def no_audio : self
        @raw_options << "-an"
        self
      end

      def crf(val : Int32) : self
        @crf_val = val
        self
      end

      def preset(val : String | Symbol) : self
        @preset_name = val.to_s
        self
      end

      def pixel_format(fmt : String) : self
        @pix_fmt = fmt
        self
      end

      def bitrate(val : String | Int32) : self
        video_bitrate(val)
      end

      def video_bitrate(val : String | Int32) : self
        @v_bitrate = val.is_a?(Int32) ? "#{val}k" : val.to_s
        self
      end

      def audio_bitrate(val : String | Int32) : self
        @a_bitrate = val.is_a?(Int32) ? "#{val}k" : val.to_s
        self
      end

      def maxrate(val : String | Int32) : self
        @max_bitrate = val.is_a?(Int32) ? "#{val}k" : val.to_s
        self
      end

      def bufsize(val : String | Int32) : self
        @buffer_size = val.is_a?(Int32) ? "#{val}k" : val.to_s
        self
      end

      def scale(w : Int32, h : Int32) : self
        @scale_size = {w, h}
        self
      end

      def fps(r : Float64 | Int32) : self
        @frame_rate = r.to_f64
        self
      end

      def channels(c : Int32) : self
        @channels_count = c
        self
      end

      def sample_rate(sr : Int32) : self
        @sample_rate_val = sr
        self
      end

      def faststart(enable : Bool = true) : self
        @faststart_flag = enable
        self
      end

      def faststart! : self
        faststart(true)
      end

      def shortest(enable : Bool = true) : self
        @shortest_flag = enable
        self
      end

      def shortest! : self
        shortest(true)
      end

      def overwrite(enable : Bool = true) : self
        @overwrite_flag = enable
        self
      end

      def overwrite! : self
        overwrite(true)
      end

      def format(fmt : String) : self
        @format_name = fmt
        self
      end

      def map(stream_spec : String) : self
        @map_streams << stream_spec
        self
      end

      def threads(n : Int32) : self
        @threads_count = n
        self
      end

      def option(flag : String, value : String? = nil) : self
        @raw_options << flag
        @raw_options << value if value
        self
      end

      def to_args : Array(String)
        args = [] of String

        args << "-y" if @overwrite_flag
        args << "-threads" << @threads_count.to_s if @threads_count

        @map_streams.each do |m|
          args << "-map" << m
        end

        args << "-c:v" << @vcodec.not_nil! if @vcodec
        args << "-c:a" << @acodec.not_nil! if @acodec
        args << "-c:s" << @scodec.not_nil! if @scodec

        args << "-crf" << @crf_val.to_s if @crf_val
        args << "-preset" << @preset_name.not_nil! if @preset_name
        args << "-pix_fmt" << @pix_fmt.not_nil! if @pix_fmt

        args << "-b:v" << @v_bitrate.not_nil! if @v_bitrate
        args << "-b:a" << @a_bitrate.not_nil! if @a_bitrate
        args << "-maxrate" << @max_bitrate.not_nil! if @max_bitrate
        args << "-bufsize" << @buffer_size.not_nil! if @buffer_size

        if s = @scale_size
          args << "-vf" << "scale=#{s[0]}:#{s[1]}"
        end

        args << "-r" << @frame_rate.to_s if @frame_rate
        args << "-ac" << @channels_count.to_s if @channels_count
        args << "-ar" << @sample_rate_val.to_s if @sample_rate_val

        args << "-movflags" << "+faststart" if @faststart_flag
        args << "-shortest" if @shortest_flag
        args << "-f" << @format_name.not_nil! if @format_name

        args.concat(@raw_options)
        args << @path
        args
      end
    end
  end
end

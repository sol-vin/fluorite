module Fluorite
  module DSL
    class Filter
      getter name : String
      getter params : Hash(String, String)

      def initialize(@name : String, @params : Hash(String, String) = Hash(String, String).new)
      end

      def to_s(io : IO) : Nil
        io << @name
        unless @params.empty?
          io << '='
          io << @params.map { |k, v| "#{k}=#{v}" }.join(':')
        end
      end
    end

    class FilterGraph
      getter video_filters : Array(String) = [] of String
      getter audio_filters : Array(String) = [] of String
      getter complex_filters : Array(String) = [] of String

      def empty? : Bool
        @video_filters.empty? && @audio_filters.empty? && @complex_filters.empty?
      end

      # Video filter: scale
      def scale(width : Int32 | String, height : Int32 | String, flags : String = "lanczos") : self
        @video_filters << "scale=#{width}:#{height}:flags=#{flags}"
        self
      end

      # Video filter: crop
      def crop(w : Int32 | String, h : Int32 | String, x : Int32 | String = 0, y : Int32 | String = 0) : self
        @video_filters << "crop=#{w}:#{h}:#{x}:#{y}"
        self
      end

      # Video filter: pad
      def pad(w : Int32 | String, h : Int32 | String, x : Int32 | String = 0, y : Int32 | String = 0, color : String = "black") : self
        @video_filters << "pad=#{w}:#{h}:#{x}:#{y}:color=#{color}"
        self
      end

      # Video filter: fps
      def fps(fps_val : Float64 | Int32) : self
        @video_filters << "fps=#{fps_val}"
        self
      end

      # Video filter: flips & rotate
      def hflip : self
        @video_filters << "hflip"
        self
      end

      def vflip : self
        @video_filters << "vflip"
        self
      end

      def rotate(radians_or_expr : String | Float64) : self
        @video_filters << "rotate=#{radians_or_expr}"
        self
      end

      # Video filter: drawtext
      def drawtext(
        text : String,
        fontfile : String? = nil,
        fontsize : Int32 = 24,
        fontcolor : String = "white",
        x : String | Int32 = 10,
        y : String | Int32 = 10,
        box : Bool = false,
        boxcolor : String = "black@0.5",
      ) : self
        # Escape text for ffmpeg drawtext
        escaped_text = text.gsub("'", "\\'").gsub(":", "\\:")
        parts = ["text='#{escaped_text}'", "fontsize=#{fontsize}", "fontcolor=#{fontcolor}", "x=#{x}", "y=#{y}"]
        parts << "fontfile=#{fontfile}" if fontfile
        if box
          parts << "box=1"
          parts << "boxcolor=#{boxcolor}"
        end
        @video_filters << "drawtext=#{parts.join(':')}"
        self
      end

      # Audio filter: volume
      def volume(vol : Float64 | String) : self
        @audio_filters << "volume=#{vol}"
        self
      end

      # Audio filter: loudnorm (EBU R128 loudness normalization)
      def loudnorm(i : Float64 = -24.0, lra : Float64 = 7.0, tp : Float64 = -2.0) : self
        @audio_filters << "loudnorm=I=#{i}:LRA=#{lra}:tp=#{tp}"
        self
      end

      # Audio filter: fade
      def afade(type : Symbol = :in, start_time : Float64 = 0.0, duration : Float64 = 2.0) : self
        @audio_filters << "afade=t=#{type}:st=#{start_time}:d=#{duration}"
        self
      end

      # 2-pass palette generation & usage for crisp GIFs
      def palette_gif(fps_val : Int32 = 15, scale_w : Int32 = 480) : self
        @complex_filters << "[0:v]fps=#{fps_val},scale=#{scale_w}:-1:flags=lanczos,split[s0][s1];[s0]palettegen=stats_mode=full[p];[s1][p]paletteuse=dither=sierra2_4a"
        self
      end

      # Video filter: tile (packs animation frames into a cols x rows sprite sheet grid)
      def tile(
        columns : Int32,
        rows : Int32,
        nb_frames : Int32? = nil,
        padding : Int32 = 0,
        margin : Int32 = 0,
        color : String = "0x00000000",
      ) : self
        frames_count = nb_frames || (columns * rows)
        parts = ["layout=#{columns}x#{rows}", "nb_frames=#{frames_count}"]
        parts << "padding=#{padding}" if padding > 0
        parts << "margin=#{margin}" if margin > 0
        parts << "color=#{color}" unless color.empty?
        @video_filters << "tile=#{parts.join(':')}"
        self
      end

      # 2-pass palette generation & usage for indexed CLUT8/CLUT4 sprite sheets
      def palette_spritesheet(
        columns : Int32,
        rows : Int32,
        frame_width : Int32 = 64,
        frame_height : Int32 = 64,
        fps_val : Float64 | Int32 = 12,
        nb_frames : Int32? = nil,
        max_colors : Int32 = 256,
        dither : String = "sierra2_4a",
        scale_flags : String = "neighbor",
        padding : Int32 = 0,
        margin : Int32 = 0,
        color : String = "0x00000000",
        reserve_transparent : Bool = true,
      ) : self
        frames_count = nb_frames || (columns * rows)
        tile_parts = ["layout=#{columns}x#{rows}", "nb_frames=#{frames_count}"]
        tile_parts << "padding=#{padding}" if padding > 0
        tile_parts << "margin=#{margin}" if margin > 0
        tile_parts << "color=#{color}" unless color.empty?
        reserve = reserve_transparent ? "1" : "0"
        @complex_filters << "[0:v]fps=#{fps_val},scale=#{frame_width}:#{frame_height}:flags=#{scale_flags},tile=#{tile_parts.join(':')},split[s0][s1];[s0]palettegen=max_colors=#{max_colors}:reserve_transparent=#{reserve}:stats_mode=full[p];[s1][p]paletteuse=dither=#{dither}"
        self
      end

      # Adds raw video filter expression
      def vf(filter_str : String) : self
        @video_filters << filter_str
        self
      end

      # Adds raw audio filter expression
      def af(filter_str : String) : self
        @audio_filters << filter_str
        self
      end

      # Adds raw complex filter expression
      def complex(filter_str : String) : self
        @complex_filters << filter_str
        self
      end

      def to_args : Array(String)
        args = [] of String
        unless @complex_filters.empty?
          args << "-filter_complex" << @complex_filters.join(";")
        else
          unless @video_filters.empty?
            args << "-vf" << @video_filters.join(",")
          end
          unless @audio_filters.empty?
            args << "-af" << @audio_filters.join(",")
          end
        end
        args
      end
    end
  end
end

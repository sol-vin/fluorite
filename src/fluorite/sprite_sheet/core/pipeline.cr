require "json"
require "yaml"
require "../../error"
require "../../probe/models"
require "../../probe/runner"
require "../../dsl/builder"

module Fluorite
  module SpriteSheet
    module Core
      # Target compression and color format for sprite sheets
      enum CompressionFormat
        RGBA32 # Uncompressed / standard 32-bit RGBA PNG (`rgba`)
        CLUT8  # 8-bit 256-color indexed palette PNG (`pal8`) — 75% VRAM reduction
        CLUT4  # 4-bit 16-color indexed palette PNG (`pal8` with 16 colors) — 87.5% VRAM reduction
        WEBP   # Lossless or near-lossless WebP atlas (`libwebp`)
        RGB565 # 16-bit high-color RGB565 (`rgb565le`) — 50% VRAM reduction

        def max_colors : Int32
          case self
          when CLUT8 then 256
          when CLUT4 then 16
          else            0
          end
        end

        def indexed_palette? : Bool
          self == CLUT8 || self == CLUT4
        end

        def bits_per_pixel : Int32
          case self
          when RGBA32 then 32
          when WEBP   then 32
          when RGB565 then 16
          when CLUT8  then 8
          when CLUT4  then 4
          else             32
          end
        end

        # Base palette table overhead in bytes (for PS2 GS / GPU CLUT storage)
        def palette_bytes : Int64
          case self
          when CLUT8 then 256_i64 * 4_i64 # 1024 bytes (256 x RGBA32 entries)
          when CLUT4 then 16_i64 * 4_i64  # 64 bytes (16 x RGBA32 entries)
          else            0_i64
          end
        end

        def to_slug : String
          to_s.downcase
        end

        def self.parse_mode(value : String | Symbol) : self
          case value.to_s.downcase.strip
          when "rgba32", "rgba", "truecolor", "png32"
            RGBA32
          when "clut8", "psmt8", "pal8", "indexed8", "256"
            CLUT8
          when "clut4", "psmt4", "pal4", "indexed4", "16"
            CLUT4
          when "webp"
            WEBP
          when "rgb565", "16bit"
            RGB565
          else
            raise Error.new("Unknown sprite sheet compression format: '#{value}'")
          end
        end
      end

      # Dithering algorithm used during palette quantization (`paletteuse`)
      enum DitherAlgorithm
        None
        Bayer
        Heckbert
        FloydSteinberg
        Sierra2
        Sierra2_4a

        def to_ffmpeg : String
          case self
          when None           then "none"
          when Bayer          then "bayer"
          when Heckbert       then "heckbert"
          when FloydSteinberg then "floyd_steinberg"
          when Sierra2        then "sierra2"
          when Sierra2_4a     then "sierra2_4a"
          else                     "sierra2_4a"
          end
        end

        def self.parse_mode(value : String | Symbol) : self
          case value.to_s.downcase.strip
          when "none", "off"
            None
          when "bayer", "ordered"
            Bayer
          when "heckbert"
            Heckbert
          when "floyd_steinberg", "floyd", "fs"
            FloydSteinberg
          when "sierra2"
            Sierra2
          when "sierra2_4a", "sierra"
            Sierra2_4a
          else
            raise Error.new("Unknown dither algorithm: '#{value}'")
          end
        end
      end

      # Scaling interpolation filter used when resizing frames
      enum ScaleFlags
        Nearest
        Bilinear
        Bicubic
        Lanczos
        Spline

        def to_ffmpeg : String
          case self
          when Nearest  then "neighbor"
          when Bilinear then "bilinear"
          when Bicubic  then "bicubic"
          when Lanczos  then "lanczos"
          when Spline   then "spline"
          else               "lanczos"
          end
        end

        def self.parse_mode(value : String | Symbol) : self
          case value.to_s.downcase.strip
          when "nearest", "neighbor", "pixel", "point"
            Nearest
          when "bilinear"
            Bilinear
          when "bicubic"
            Bicubic
          when "lanczos"
            Lanczos
          when "spline"
            Spline
          else
            raise Error.new("Unknown scale flags: '#{value}'")
          end
        end
      end

      # Layout strategy for arranging frames in the sprite sheet
      enum LayoutPolicy
        Grid       # Balanced square-like grid (columns x rows)
        Horizontal # Single horizontal strip (N x 1)
        Vertical   # Single vertical strip (1 x N)
        FixedCols  # Fixed column count, auto-calculated rows
        FixedRows  # Fixed row count, auto-calculated columns
      end

      # Value struct representing a single animation frame's UV and pixel bounds within the packed atlas
      struct SpriteFrameRect
        include JSON::Serializable
        include YAML::Serializable

        getter index : Int32
        getter column : Int32
        getter row : Int32
        getter x : Int32
        getter y : Int32
        getter width : Int32
        getter height : Int32
        getter u0 : Float64
        getter v0 : Float64
        getter u1 : Float64
        getter v1 : Float64
        getter timestamp_sec : Float64

        def initialize(
          @index : Int32,
          @column : Int32,
          @row : Int32,
          @x : Int32,
          @y : Int32,
          @width : Int32,
          @height : Int32,
          @u0 : Float64,
          @v0 : Float64,
          @u1 : Float64,
          @v1 : Float64,
          @timestamp_sec : Float64 = 0.0,
        )
        end
      end

      # Value struct representing VRAM & file compression telemetry
      struct CompressionMetrics
        include JSON::Serializable
        include YAML::Serializable

        getter raw_rgba_bytes : Int64
        getter compressed_vram_bytes : Int64
        getter palette_overhead_bytes : Int64
        getter total_vram_bytes : Int64
        getter vram_savings_bytes : Int64
        getter vram_savings_percent : Float64
        getter compression_ratio : Float64

        def initialize(
          @raw_rgba_bytes : Int64,
          @compressed_vram_bytes : Int64,
          @palette_overhead_bytes : Int64,
        )
          @total_vram_bytes = @compressed_vram_bytes + @palette_overhead_bytes
          @vram_savings_bytes = Math.max(0_i64, @raw_rgba_bytes - @total_vram_bytes)
          if @raw_rgba_bytes > 0
            @vram_savings_percent = ((@vram_savings_bytes.to_f64 / @raw_rgba_bytes.to_f64) * 100.0).round(2)
            @compression_ratio = (@raw_rgba_bytes.to_f64 / Math.max(1_i64, @total_vram_bytes).to_f64).round(2)
          else
            @vram_savings_percent = 0.0
            @compression_ratio = 1.0
          end
        end
      end

      # Pure Core Engine configuration for the automated sprite sheet compression pipeline
      struct PipelineConfig
        property input_path : String
        property output_path : String
        property metadata_path : String?
        property godot_import_path : String?
        property frame_width : Int32
        property frame_height : Int32
        property frame_count : Int32
        property fps : Float64
        property columns : Int32?
        property rows : Int32?
        property layout_policy : LayoutPolicy
        property padding : Int32
        property margin : Int32
        property background_color : String
        property power_of_two : Bool
        property format : CompressionFormat
        property max_colors : Int32?
        property dither : DitherAlgorithm
        property bayer_scale : Int32
        property scale_flags : ScaleFlags
        property png_compression_level : Int32
        property webp_quality : Int32
        property webp_lossless : Bool
        property reserve_transparent : Bool
        property stats_mode : String
        property seek : (String | Time::Span)?
        property duration : (String | Time::Span)?
        property crop_rect : Tuple(Int32, Int32, Int32, Int32)?
        property animation_name : String
        property loop_animation : Bool

        def initialize(
          @input_path : String = "",
          @output_path : String = "",
          @metadata_path : String? = nil,
          @godot_import_path : String? = nil,
          @frame_width : Int32 = 64,
          @frame_height : Int32 = 64,
          @frame_count : Int32 = 16,
          @fps : Float64 = 12.0,
          @columns : Int32? = nil,
          @rows : Int32? = nil,
          @layout_policy : LayoutPolicy = LayoutPolicy::Grid,
          @padding : Int32 = 0,
          @margin : Int32 = 0,
          @background_color : String = "0x00000000",
          @power_of_two : Bool = false,
          @format : CompressionFormat = CompressionFormat::CLUT8,
          @max_colors : Int32? = nil,
          @dither : DitherAlgorithm = DitherAlgorithm::Sierra2_4a,
          @bayer_scale : Int32 = 2,
          @scale_flags : ScaleFlags = ScaleFlags::Nearest,
          @png_compression_level : Int32 = 9,
          @webp_quality : Int32 = 90,
          @webp_lossless : Bool = true,
          @reserve_transparent : Bool = true,
          @stats_mode : String = "full",
          @seek : (String | Time::Span)? = nil,
          @duration : (String | Time::Span)? = nil,
          @crop_rect : Tuple(Int32, Int32, Int32, Int32)? = nil,
          @animation_name : String = "default",
          @loop_animation : Bool = true,
        )
        end

        def effective_max_colors : Int32
          if mc = @max_colors
            mc.clamp(2, 256)
          else
            case @format
            when CompressionFormat::CLUT4 then 16
            when CompressionFormat::CLUT8 then 256
            else                               256
            end
          end
        end

        def validate! : Nil
          raise Error.new("Input path cannot be empty") if @input_path.strip.empty?
          raise Error.new("Output path cannot be empty") if @output_path.strip.empty?
          raise Error.new("Frame dimensions must be positive (got #{@frame_width}x#{@frame_height})") if @frame_width <= 0 || @frame_height <= 0
          raise Error.new("Frame count must be at least 1 (got #{@frame_count})") if @frame_count < 1
          raise Error.new("FPS must be positive (got #{@fps})") if @fps <= 0.0
          raise Error.new("Padding cannot be negative (got #{@padding})") if @padding < 0
          raise Error.new("Margin cannot be negative (got #{@margin})") if @margin < 0
          raise Error.new("PNG compression level must be between 0 and 9 (got #{@png_compression_level})") unless (0..9).includes?(@png_compression_level)
          raise Error.new("Bayer scale must be between 0 and 5 (got #{@bayer_scale})") unless (0..5).includes?(@bayer_scale)
        end
      end

      # Complete computed layout plan and atlas manifest for a sprite sheet
      class AtlasPlan
        include JSON::Serializable
        include YAML::Serializable

        getter input_path : String
        getter output_path : String
        getter animation_name : String
        getter loop_animation : Bool
        getter format : String
        getter frame_width : Int32
        getter frame_height : Int32
        getter frame_count : Int32
        getter columns : Int32
        getter rows : Int32
        getter padding : Int32
        getter margin : Int32
        getter raw_atlas_width : Int32
        getter raw_atlas_height : Int32
        getter atlas_width : Int32
        getter atlas_height : Int32
        getter power_of_two : Bool
        getter fps : Float64
        getter max_colors : Int32
        getter dither : String
        getter scale_flags : String
        getter metrics : CompressionMetrics
        getter frames : Array(SpriteFrameRect)

        def initialize(
          @input_path : String,
          @output_path : String,
          @animation_name : String,
          @loop_animation : Bool,
          @format : String,
          @frame_width : Int32,
          @frame_height : Int32,
          @frame_count : Int32,
          @columns : Int32,
          @rows : Int32,
          @padding : Int32,
          @margin : Int32,
          @raw_atlas_width : Int32,
          @raw_atlas_height : Int32,
          @atlas_width : Int32,
          @atlas_height : Int32,
          @power_of_two : Bool,
          @fps : Float64,
          @max_colors : Int32,
          @dither : String,
          @scale_flags : String,
          @metrics : CompressionMetrics,
          @frames : Array(SpriteFrameRect),
        )
        end

        # Generates deterministic Godot 4.8 `.import` metadata for compressed 2D SpriteSheets
        def to_godot_import(source_res_path : String? = nil) : String
          res_path = source_res_path || "res://#{File.basename(@output_path)}"
          mipmaps = false
          filter_mode = @scale_flags == "neighbor" ? 0 : 1 # 0 = Nearest, 1 = Linear

          String.build do |io|
            io << "[remap]\n\n"
            io << "importer=\"texture\"\n"
            io << "type=\"CompressedTexture2D\"\n"
            io << "path=\"res://.godot/imported/#{File.basename(@output_path)}-fluorite.ctex\"\n"
            io << "metadata={\n"
            io << "\"vram_texture\": false,\n"
            io << "\"fluorite_atlas\": {\n"
            io << "  \"animation\": \"#{@animation_name}\",\n"
            io << "  \"hframes\": #{@columns},\n"
            io << "  \"vframes\": #{@rows},\n"
            io << "  \"frame_count\": #{@frame_count},\n"
            io << "  \"frame_width\": #{@frame_width},\n"
            io << "  \"frame_height\": #{@frame_height},\n"
            io << "  \"fps\": #{@fps},\n"
            io << "  \"format\": \"#{@format}\"\n"
            io << "}\n"
            io << "}\n\n"
            io << "[deps]\n\n"
            io << "source_file=\"#{res_path}\"\n\n"
            io << "[params]\n\n"
            io << "compress/mode=0\n"
            io << "compress/high_quality=false\n"
            io << "compress/lossy_quality=0.7\n"
            io << "compress/hdr_compression=1\n"
            io << "compress/normal_map=0\n"
            io << "compress/channel_pack=0\n"
            io << "mipmaps/generate=#{mipmaps}\n"
            io << "mipmaps/limit=-1\n"
            io << "roughness/mode=0\n"
            io << "roughness/src_normal=\"\"\n"
            io << "process/fix_alpha_border=true\n"
            io << "process/premult_alpha=false\n"
            io << "process/normal_map_invert_y=false\n"
            io << "process/hdr_as_srgb=false\n"
            io << "process/hdr_clamp_exposure=false\n"
            io << "process/size_limit=0\n"
            io << "detect_3d/compress_to=0\n"
            io << "filter/mode=#{filter_mode}\n"
          end
        end
      end

      # Pure Core Engine planner & command generator for Sprite Sheet Compression
      module Planner
        # Computes next power of two >= value (minimum 1)
        def self.next_power_of_two(value : Int32) : Int32
          return 1 if value <= 1
          v = value - 1
          v |= v >> 1
          v |= v >> 2
          v |= v >> 4
          v |= v >> 8
          v |= v >> 16
          v + 1
        end

        # Checks if an integer is an exact power of two
        def self.power_of_two?(value : Int32) : Bool
          value > 0 && (value & (value - 1)) == 0
        end

        # Computes optimal {columns, rows} grid dimensions for a given frame count and policy
        def self.compute_grid(
          frame_count : Int32,
          policy : LayoutPolicy = LayoutPolicy::Grid,
          fixed_cols : Int32? = nil,
          fixed_rows : Int32? = nil,
          frame_width : Int32 = 64,
          frame_height : Int32 = 64,
          padding : Int32 = 0,
          margin : Int32 = 0,
          power_of_two : Bool = false,
        ) : Tuple(Int32, Int32)
          count = Math.max(1, frame_count)

          if (c = fixed_cols) && (r = fixed_rows) && c > 0 && r > 0
            return {c, r}
          end

          case policy
          when LayoutPolicy::Horizontal
            return {count, 1}
          when LayoutPolicy::Vertical
            return {1, count}
          when LayoutPolicy::FixedCols
            cols = Math.max(1, fixed_cols || Math.sqrt(count.to_f64).ceil.to_i32)
            rows = (count + cols - 1) // cols
            return {cols, rows}
          when LayoutPolicy::FixedRows
            rows = Math.max(1, fixed_rows || Math.sqrt(count.to_f64).ceil.to_i32)
            cols = (count + rows - 1) // rows
            return {cols, rows}
          else
            if c = fixed_cols
              if c > 0
                r = (count + c - 1) // c
                return {c, r}
              end
            end
            if r = fixed_rows
              if r > 0
                c = (count + r - 1) // r
                return {c, r}
              end
            end

            # Search for grid {cols, rows} that minimizes wasted atlas area and aspect imbalance
            best_cols = Math.sqrt(count.to_f64).ceil.to_i32
            best_rows = (count + best_cols - 1) // best_cols
            best_score = Float64::MAX

            (1..count).each do |cols|
              rows = (count + cols - 1) // cols
              raw_w = cols * frame_width + Math.max(0, cols - 1) * padding + margin * 2
              raw_h = rows * frame_height + Math.max(0, rows - 1) * padding + margin * 2
              atlas_w = power_of_two ? next_power_of_two(raw_w) : raw_w
              atlas_h = power_of_two ? next_power_of_two(raw_h) : raw_h

              area = atlas_w.to_f64 * atlas_h.to_f64
              aspect = atlas_w >= atlas_h ? (atlas_w.to_f64 / atlas_h.to_f64) : (atlas_h.to_f64 / atlas_w.to_f64)
              # Prefer compact area and balanced square-ish aspect ratio
              score = area * (1.0 + (aspect - 1.0) * 0.15)
              if score < best_score
                best_score = score
                best_cols = cols
                best_rows = rows
              end
            end

            {best_cols, best_rows}
          end
        end

        # Builds the complete `AtlasPlan` including frame rects, normalized UVs, and VRAM metrics
        def self.create_plan(config : PipelineConfig) : AtlasPlan
          config.validate!

          cols, rows = compute_grid(
            frame_count: config.frame_count,
            policy: config.layout_policy,
            fixed_cols: config.columns,
            fixed_rows: config.rows,
            frame_width: config.frame_width,
            frame_height: config.frame_height,
            padding: config.padding,
            margin: config.margin,
            power_of_two: config.power_of_two
          )

          raw_w = cols * config.frame_width + Math.max(0, cols - 1) * config.padding + config.margin * 2
          raw_h = rows * config.frame_height + Math.max(0, rows - 1) * config.padding + config.margin * 2

          atlas_w = config.power_of_two ? next_power_of_two(raw_w) : raw_w
          atlas_h = config.power_of_two ? next_power_of_two(raw_h) : raw_h

          # Compute VRAM metrics
          total_pixels = atlas_w.to_i64 * atlas_h.to_i64
          raw_rgba_bytes = total_pixels * 4_i64
          compressed_pixels_bytes = (total_pixels * config.format.bits_per_pixel.to_i64) // 8_i64
          metrics = CompressionMetrics.new(
            raw_rgba_bytes: raw_rgba_bytes,
            compressed_vram_bytes: compressed_pixels_bytes,
            palette_overhead_bytes: config.format.palette_bytes
          )

          # Compute individual frame coordinates and normalized UVs
          frames = Array(SpriteFrameRect).new(config.frame_count)
          inv_w = atlas_w > 0 ? (1.0 / atlas_w.to_f64) : 0.0
          inv_h = atlas_h > 0 ? (1.0 / atlas_h.to_f64) : 0.0
          frame_dt = config.fps > 0.0 ? (1.0 / config.fps) : 0.0

          config.frame_count.times do |idx|
            col = idx % cols
            row = idx // cols
            fx = config.margin + col * (config.frame_width + config.padding)
            fy = config.margin + row * (config.frame_height + config.padding)

            u0 = (fx.to_f64 * inv_w).round(6)
            v0 = (fy.to_f64 * inv_h).round(6)
            u1 = ((fx + config.frame_width).to_f64 * inv_w).round(6)
            v1 = ((fy + config.frame_height).to_f64 * inv_h).round(6)
            ts = (idx.to_f64 * frame_dt).round(4)

            frames << SpriteFrameRect.new(
              index: idx,
              column: col,
              row: row,
              x: fx,
              y: fy,
              width: config.frame_width,
              height: config.frame_height,
              u0: u0,
              v0: v0,
              u1: u1,
              v1: v1,
              timestamp_sec: ts
            )
          end

          AtlasPlan.new(
            input_path: config.input_path,
            output_path: config.output_path,
            animation_name: config.animation_name,
            loop_animation: config.loop_animation,
            format: config.format.to_slug,
            frame_width: config.frame_width,
            frame_height: config.frame_height,
            frame_count: config.frame_count,
            columns: cols,
            rows: rows,
            padding: config.padding,
            margin: config.margin,
            raw_atlas_width: raw_w,
            raw_atlas_height: raw_h,
            atlas_width: atlas_w,
            atlas_height: atlas_h,
            power_of_two: config.power_of_two,
            fps: config.fps,
            max_colors: config.effective_max_colors,
            dither: config.dither.to_ffmpeg,
            scale_flags: config.scale_flags.to_ffmpeg,
            metrics: metrics,
            frames: frames
          )
        end

        # Synthesizes the FFmpeg filtergraph expression for sprite sheet packing & palette quantization
        def self.build_filter_expression(config : PipelineConfig, plan : AtlasPlan? = nil) : String
          resolved_plan = plan || create_plan(config)
          stages = [] of String

          # 1. Framerate sampling
          fps_str = config.fps == config.fps.to_i.to_f64 ? config.fps.to_i.to_s : config.fps.to_s
          stages << "fps=#{fps_str}"

          # 2. Optional source crop prior to scaling
          if crop = config.crop_rect
            stages << "crop=#{crop[0]}:#{crop[1]}:#{crop[2]}:#{crop[3]}"
          end

          # 3. Frame scaling with specified filter flags
          stages << "scale=#{config.frame_width}:#{config.frame_height}:flags=#{config.scale_flags.to_ffmpeg}"

          # 4. Tile filter for atlas packing
          tile_parts = [
            "layout=#{resolved_plan.columns}x#{resolved_plan.rows}",
            "nb_frames=#{resolved_plan.frame_count}",
          ]
          tile_parts << "padding=#{resolved_plan.padding}" if resolved_plan.padding > 0
          tile_parts << "margin=#{resolved_plan.margin}" if resolved_plan.margin > 0
          tile_parts << "color=#{config.background_color}" unless config.background_color.empty?
          stages << "tile=#{tile_parts.join(':')}"

          # 5. Optional Power-of-Two (POT) canvas expansion via pad filter
          if resolved_plan.power_of_two && (resolved_plan.atlas_width > resolved_plan.raw_atlas_width || resolved_plan.atlas_height > resolved_plan.raw_atlas_height)
            stages << "pad=#{resolved_plan.atlas_width}:#{resolved_plan.atlas_height}:0:0:color=#{config.background_color}"
          end

          base_chain = stages.join(",")

          # 6. Color format & 2-pass CLUT palette compression
          if config.format.indexed_palette?
            max_c = resolved_plan.max_colors
            reserve = config.reserve_transparent ? "1" : "0"
            dither_str = config.dither.to_ffmpeg
            paletteuse_opts = ["dither=#{dither_str}"]
            if config.dither == DitherAlgorithm::Bayer
              paletteuse_opts << "bayer_scale=#{config.bayer_scale}"
            end
            "[0:v]#{base_chain},split[s0][s1];[s0]palettegen=max_colors=#{max_c}:reserve_transparent=#{reserve}:stats_mode=#{config.stats_mode}[p];[s1][p]paletteuse=#{paletteuse_opts.join(':')}"
          else
            base_chain
          end
        end

        # Builds the executable `Fluorite::DSL::Command` for the configured sprite sheet pipeline
        def self.build_command(config : PipelineConfig, plan : AtlasPlan? = nil) : Fluorite::DSL::Command
          resolved_plan = plan || create_plan(config)
          filter_expr = build_filter_expression(config, resolved_plan)

          Fluorite.build do
            overwrite!

            input(config.input_path) do |inp|
              if sk = config.seek
                inp.seek(sk)
              end
              if dur = config.duration
                inp.duration(dur)
              end
            end

            filter do |f|
              if config.format.indexed_palette?
                f.complex(filter_expr)
              else
                f.vf(filter_expr)
              end
            end

            output(config.output_path) do |outp|
              outp.no_audio
              outp.option("-frames:v", "1")

              case config.format
              when CompressionFormat::WEBP
                outp.video_codec("libwebp")
                outp.option("-lossless", config.webp_lossless ? "1" : "0")
                outp.option("-quality", config.webp_quality.to_s)
                outp.option("-compression_level", "6")
              when CompressionFormat::RGB565
                outp.pixel_format("rgb565le")
                outp.option("-compression_level", config.png_compression_level.to_s)
              when CompressionFormat::RGBA32
                outp.pixel_format("rgba")
                outp.option("-compression_level", config.png_compression_level.to_s)
              when CompressionFormat::CLUT8, CompressionFormat::CLUT4
                outp.option("-compression_level", config.png_compression_level.to_s)
              end
            end
          end
        end
      end
    end
  end
end

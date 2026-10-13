require "../core/pipeline"

module Fluorite
  module SpriteSheet
    module DSL
      # Declarative builder for configuring and executing a SpriteSheet compression pipeline
      class SpriteSheetBuilder
        getter config : Core::PipelineConfig

        def initialize(@config : Core::PipelineConfig = Core::PipelineConfig.new)
        end

        def input(path : String) : self
          @config.input_path = path
          self
        end

        def output(path : String) : self
          @config.output_path = path
          self
        end

        def to(path : String) : self
          output(path)
        end

        def metadata(path : String) : self
          @config.metadata_path = path
          self
        end

        def godot_import(path : String) : self
          @config.godot_import_path = path
          self
        end

        def godot_import!(enable : Bool = true) : self
          if enable && !@config.output_path.empty?
            @config.godot_import_path = "#{@config.output_path}.import"
          elsif !enable
            @config.godot_import_path = nil
          end
          self
        end

        def frame_size(width : Int32, height : Int32) : self
          @config.frame_width = width
          @config.frame_height = height
          self
        end

        def frame_width(width : Int32) : self
          @config.frame_width = width
          self
        end

        def frame_height(height : Int32) : self
          @config.frame_height = height
          self
        end

        def frames(count : Int32) : self
          @config.frame_count = count
          self
        end

        def frame_count(count : Int32) : self
          @config.frame_count = count
          self
        end

        def fps(rate : Float64 | Int32) : self
          @config.fps = rate.to_f64
          self
        end

        def columns(cols : Int32) : self
          @config.columns = cols
          @config.layout_policy = Core::LayoutPolicy::FixedCols unless @config.rows
          self
        end

        def rows(r : Int32) : self
          @config.rows = r
          @config.layout_policy = Core::LayoutPolicy::FixedRows unless @config.columns
          self
        end

        def grid(cols : Int32, r : Int32) : self
          @config.columns = cols
          @config.rows = r
          @config.layout_policy = Core::LayoutPolicy::Grid
          if @config.frame_count == 16 && (cols * r != 16)
            @config.frame_count = cols * r
          end
          self
        end

        def layout(policy : Symbol | String | Core::LayoutPolicy) : self
          @config.layout_policy = case policy
                                  when Core::LayoutPolicy
                                    policy
                                  else
                                    case policy.to_s.downcase.strip
                                    when "horizontal", "strip_h", "row"
                                      Core::LayoutPolicy::Horizontal
                                    when "vertical", "strip_v", "col", "column"
                                      Core::LayoutPolicy::Vertical
                                    when "fixed_cols", "cols"
                                      Core::LayoutPolicy::FixedCols
                                    when "fixed_rows", "rows"
                                      Core::LayoutPolicy::FixedRows
                                    else
                                      Core::LayoutPolicy::Grid
                                    end
                                  end
          self
        end

        def horizontal_strip! : self
          @config.layout_policy = Core::LayoutPolicy::Horizontal
          self
        end

        def vertical_strip! : self
          @config.layout_policy = Core::LayoutPolicy::Vertical
          self
        end

        def padding(px : Int32) : self
          @config.padding = px
          self
        end

        def margin(px : Int32) : self
          @config.margin = px
          self
        end

        def background(color : String) : self
          @config.background_color = color
          self
        end

        def power_of_two(enable : Bool = true) : self
          @config.power_of_two = enable
          self
        end

        def power_of_two! : self
          power_of_two(true)
        end

        def format(fmt : Symbol | String | Core::CompressionFormat) : self
          @config.format = fmt.is_a?(Core::CompressionFormat) ? fmt : Core::CompressionFormat.parse_mode(fmt)
          self
        end

        def clut8!(dither : Symbol | String | Core::DitherAlgorithm = Core::DitherAlgorithm::Sierra2_4a) : self
          @config.format = Core::CompressionFormat::CLUT8
          @config.max_colors = 256
          self.dither(dither)
        end

        def clut4!(dither : Symbol | String | Core::DitherAlgorithm = Core::DitherAlgorithm::Sierra2_4a) : self
          @config.format = Core::CompressionFormat::CLUT4
          @config.max_colors = 16
          self.dither(dither)
        end

        def rgba32! : self
          @config.format = Core::CompressionFormat::RGBA32
          self
        end

        def rgb565! : self
          @config.format = Core::CompressionFormat::RGB565
          self
        end

        def webp!(quality : Int32 = 90, lossless : Bool = true) : self
          @config.format = Core::CompressionFormat::WEBP
          @config.webp_quality = quality
          @config.webp_lossless = lossless
          self
        end

        def max_colors(colors : Int32) : self
          @config.max_colors = colors.clamp(2, 256)
          self
        end

        def dither(algo : Symbol | String | Core::DitherAlgorithm) : self
          @config.dither = algo.is_a?(Core::DitherAlgorithm) ? algo : Core::DitherAlgorithm.parse_mode(algo)
          self
        end

        def bayer_scale(scale : Int32) : self
          @config.bayer_scale = scale.clamp(0, 5)
          self
        end

        def scale_flags(flags : Symbol | String | Core::ScaleFlags) : self
          @config.scale_flags = flags.is_a?(Core::ScaleFlags) ? flags : Core::ScaleFlags.parse_mode(flags)
          self
        end

        def pixel_art! : self
          @config.scale_flags = Core::ScaleFlags::Nearest
          self
        end

        def compression_level(level : Int32) : self
          @config.png_compression_level = level.clamp(0, 9)
          self
        end

        def reserve_transparent(enable : Bool = true) : self
          @config.reserve_transparent = enable
          self
        end

        def seek(time : String | Time::Span) : self
          @config.seek = time
          self
        end

        def duration(time : String | Time::Span) : self
          @config.duration = time
          self
        end

        def crop(w : Int32, h : Int32, x : Int32 = 0, y : Int32 = 0) : self
          @config.crop_rect = {w, h, x, y}
          self
        end

        def animation(name : String, loop_anim : Bool = true) : self
          @config.animation_name = name
          @config.loop_animation = loop_anim
          self
        end

        # Computes and returns the `Core::AtlasPlan`
        def plan : Core::AtlasPlan
          Core::Planner.create_plan(@config)
        end

        # Builds the underlying `Fluorite::DSL::Command`
        def command : Fluorite::DSL::Command
          Core::Planner.build_command(@config)
        end

        def to_cmd_string : String
          command.to_cmd_string
        end

        # Writes metadata JSON/YAML and Godot `.import` sidecar files if configured
        def write_sidecars!(atlas_plan : Core::AtlasPlan? = nil) : Core::AtlasPlan
          resolved = atlas_plan || plan
          if meta_path = @config.metadata_path
            if meta_path.ends_with?(".yml") || meta_path.ends_with?(".yaml")
              File.write(meta_path, resolved.to_yaml)
            else
              File.write(meta_path, resolved.to_pretty_json)
            end
          end

          if import_path = @config.godot_import_path
            File.write(import_path, resolved.to_godot_import)
          end
          resolved
        end

        # Runs the compression pipeline and writes any configured metadata sidecar files
        def run(&progress_block : Runner::Progress -> Nil) : Tuple(Process::Status, Core::AtlasPlan)
          resolved = plan
          cmd = Core::Planner.build_command(@config, resolved)
          status = cmd.run(&progress_block)
          write_sidecars!(resolved) if status.success?
          {status, resolved}
        end

        def run : Tuple(Process::Status, Core::AtlasPlan)
          resolved = plan
          cmd = Core::Planner.build_command(@config, resolved)
          status = cmd.run
          write_sidecars!(resolved) if status.success?
          {status, resolved}
        end
      end
    end
  end
end

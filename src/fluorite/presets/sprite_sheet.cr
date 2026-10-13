require "./base"
require "../sprite_sheet/core/pipeline"
require "../sprite_sheet/dsl/sprite_sheet_builder"

module Fluorite
  module Presets
    # Automated Sprite Sheet Packing & Palette Quantization Preset
    class SpriteSheet < Base
      def self.convert(
        input_path : String,
        output_path : String,
        frame_width : Int32 = 64,
        frame_height : Int32 = 64,
        frames : Int32 = 16,
        fps : Float64 | Int32 = 12,
        columns : Int32? = nil,
        rows : Int32? = nil,
        padding : Int32 = 0,
        margin : Int32 = 0,
        power_of_two : Bool = false,
        format : Symbol | String | Fluorite::SpriteSheet::Core::CompressionFormat = :clut8,
        dither : Symbol | String | Fluorite::SpriteSheet::Core::DitherAlgorithm = :sierra2_4a,
        scale_flags : Symbol | String | Fluorite::SpriteSheet::Core::ScaleFlags = :nearest,
        metadata_path : String? = nil,
        godot_import_path : String? = nil,
        seek : (String | Time::Span)? = nil,
        duration : (String | Time::Span)? = nil,
        &progress_block : Runner::Progress -> Nil
      ) : Process::Status
        cfg = build_config(
          input_path, output_path, frame_width, frame_height, frames, fps,
          columns, rows, padding, margin, power_of_two, format, dither,
          scale_flags, metadata_path, godot_import_path, seek, duration
        )
        builder = Fluorite::SpriteSheet::DSL::SpriteSheetBuilder.new(cfg)
        status, _plan = builder.run(&progress_block)
        status
      end

      def self.convert(
        input_path : String,
        output_path : String,
        frame_width : Int32 = 64,
        frame_height : Int32 = 64,
        frames : Int32 = 16,
        fps : Float64 | Int32 = 12,
        columns : Int32? = nil,
        rows : Int32? = nil,
        padding : Int32 = 0,
        margin : Int32 = 0,
        power_of_two : Bool = false,
        format : Symbol | String | Fluorite::SpriteSheet::Core::CompressionFormat = :clut8,
        dither : Symbol | String | Fluorite::SpriteSheet::Core::DitherAlgorithm = :sierra2_4a,
        scale_flags : Symbol | String | Fluorite::SpriteSheet::Core::ScaleFlags = :nearest,
        metadata_path : String? = nil,
        godot_import_path : String? = nil,
        seek : (String | Time::Span)? = nil,
        duration : (String | Time::Span)? = nil,
      ) : Process::Status
        cfg = build_config(
          input_path, output_path, frame_width, frame_height, frames, fps,
          columns, rows, padding, margin, power_of_two, format, dither,
          scale_flags, metadata_path, godot_import_path, seek, duration
        )
        builder = Fluorite::SpriteSheet::DSL::SpriteSheetBuilder.new(cfg)
        status, _plan = builder.run
        status
      end

      def self.build_command(
        input_path : String,
        output_path : String,
        frame_width : Int32 = 64,
        frame_height : Int32 = 64,
        frames : Int32 = 16,
        fps : Float64 | Int32 = 12,
        columns : Int32? = nil,
        rows : Int32? = nil,
        padding : Int32 = 0,
        margin : Int32 = 0,
        power_of_two : Bool = false,
        format : Symbol | String | Fluorite::SpriteSheet::Core::CompressionFormat = :clut8,
        dither : Symbol | String | Fluorite::SpriteSheet::Core::DitherAlgorithm = :sierra2_4a,
        scale_flags : Symbol | String | Fluorite::SpriteSheet::Core::ScaleFlags = :nearest,
        metadata_path : String? = nil,
        godot_import_path : String? = nil,
        seek : (String | Time::Span)? = nil,
        duration : (String | Time::Span)? = nil,
      ) : DSL::Command
        cfg = build_config(
          input_path, output_path, frame_width, frame_height, frames, fps,
          columns, rows, padding, margin, power_of_two, format, dither,
          scale_flags, metadata_path, godot_import_path, seek, duration
        )
        Fluorite::SpriteSheet::Core::Planner.build_command(cfg)
      end

      def self.build_plan(
        input_path : String,
        output_path : String,
        frame_width : Int32 = 64,
        frame_height : Int32 = 64,
        frames : Int32 = 16,
        fps : Float64 | Int32 = 12,
        columns : Int32? = nil,
        rows : Int32? = nil,
        padding : Int32 = 0,
        margin : Int32 = 0,
        power_of_two : Bool = false,
        format : Symbol | String | Fluorite::SpriteSheet::Core::CompressionFormat = :clut8,
        dither : Symbol | String | Fluorite::SpriteSheet::Core::DitherAlgorithm = :sierra2_4a,
        scale_flags : Symbol | String | Fluorite::SpriteSheet::Core::ScaleFlags = :nearest,
        metadata_path : String? = nil,
        godot_import_path : String? = nil,
        seek : (String | Time::Span)? = nil,
        duration : (String | Time::Span)? = nil,
      ) : Fluorite::SpriteSheet::Core::AtlasPlan
        cfg = build_config(
          input_path, output_path, frame_width, frame_height, frames, fps,
          columns, rows, padding, margin, power_of_two, format, dither,
          scale_flags, metadata_path, godot_import_path, seek, duration
        )
        Fluorite::SpriteSheet::Core::Planner.create_plan(cfg)
      end

      def self.build_config(
        input_path : String,
        output_path : String,
        frame_width : Int32 = 64,
        frame_height : Int32 = 64,
        frames : Int32 = 16,
        fps : Float64 | Int32 = 12,
        columns : Int32? = nil,
        rows : Int32? = nil,
        padding : Int32 = 0,
        margin : Int32 = 0,
        power_of_two : Bool = false,
        format : Symbol | String | Fluorite::SpriteSheet::Core::CompressionFormat = :clut8,
        dither : Symbol | String | Fluorite::SpriteSheet::Core::DitherAlgorithm = :sierra2_4a,
        scale_flags : Symbol | String | Fluorite::SpriteSheet::Core::ScaleFlags = :nearest,
        metadata_path : String? = nil,
        godot_import_path : String? = nil,
        seek : (String | Time::Span)? = nil,
        duration : (String | Time::Span)? = nil,
      ) : Fluorite::SpriteSheet::Core::PipelineConfig
        comp_fmt = format.is_a?(Fluorite::SpriteSheet::Core::CompressionFormat) ? format : Fluorite::SpriteSheet::Core::CompressionFormat.parse_mode(format)
        dither_alg = dither.is_a?(Fluorite::SpriteSheet::Core::DitherAlgorithm) ? dither : Fluorite::SpriteSheet::Core::DitherAlgorithm.parse_mode(dither)
        s_flags = scale_flags.is_a?(Fluorite::SpriteSheet::Core::ScaleFlags) ? scale_flags : Fluorite::SpriteSheet::Core::ScaleFlags.parse_mode(scale_flags)

        Fluorite::SpriteSheet::Core::PipelineConfig.new(
          input_path: input_path,
          output_path: output_path,
          metadata_path: metadata_path,
          godot_import_path: godot_import_path,
          frame_width: frame_width,
          frame_height: frame_height,
          frame_count: frames,
          fps: fps.to_f64,
          columns: columns,
          rows: rows,
          padding: padding,
          margin: margin,
          power_of_two: power_of_two,
          format: comp_fmt,
          dither: dither_alg,
          scale_flags: s_flags,
          seek: seek,
          duration: duration
        )
      end
    end
  end
end

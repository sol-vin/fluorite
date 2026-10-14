require "./fluorite/version"
require "./fluorite/error"
require "./fluorite/config"
require "./fluorite/probe/models"
require "./fluorite/probe/runner"
require "./fluorite/dsl/input"
require "./fluorite/dsl/output"
require "./fluorite/dsl/filter_graph"
require "./fluorite/dsl/command"
require "./fluorite/dsl/builder"
require "./fluorite/runner/progress"
require "./fluorite/runner/process_runner"
require "./fluorite/presets/base"
require "./fluorite/presets/discord"
require "./fluorite/presets/gif"
require "./fluorite/presets/web"
require "./fluorite/presets/audio"
require "./fluorite/presets/trim"
require "./fluorite/sprite_sheet/core/pipeline"
require "./fluorite/sprite_sheet/dsl/sprite_sheet_builder"
require "./fluorite/presets/sprite_sheet"
require "./fluorite/batch"
require "./fluorite/tui/core/telemetry_engine"
require "./fluorite/tui/split_pane_bridge"
require "./fluorite/tui/telemetry_dashboard"
require "./fluorite/tui/app"
require "./fluorite/c/libav"
require "./fluorite/docs"

module Fluorite
  # Probes a media file or URL and returns a parsed ProbeResult
  def self.probe(target : String) : Probe::ProbeResult
    Probe.run(target)
  end

  # Fluent block-based DSL to build a Command
  def self.build(&)
    builder = DSL::Builder.new
    with builder yield builder
    builder.command
  end

  # Fluent chainable builder starting with an input
  def self.input(path : String) : DSL::ChainBuilder
    DSL::ChainBuilder.new(path)
  end

  # Fluent chainable conversion starting from an input path
  def self.convert(input_path : String) : DSL::ChainBuilder
    DSL::ChainBuilder.new(input_path)
  end

  # Cuts a media file losslessly in milliseconds without re-encoding
  def self.trim(input : String, output : String, from : String | Time::Span, to : (String | Time::Span)? = nil) : Process::Status
    Presets::Trim.cut(input, output, from, to)
  end

  # Compresses media to strictly fit under Discord's attachment size limit
  def self.discord(input : String, output : String, target_mb : Float64 = 24.5, &progress : Runner::Progress -> Nil) : Process::Status
    Presets::Discord.convert(input, output, target_mb, &progress)
  end

  def self.discord(input : String, output : String, target_mb : Float64 = 24.5) : Process::Status
    Presets::Discord.convert(input, output, target_mb)
  end

  # Generates high definition GIF using 2-pass palette generation
  def self.gif(input : String, output : String, fps : Int32 = 15, width : Int32 = 480, &progress : Runner::Progress -> Nil) : Process::Status
    Presets::Gif.convert(input, output, fps: fps, width: width, &progress)
  end

  def self.gif(input : String, output : String, fps : Int32 = 15, width : Int32 = 480) : Process::Status
    Presets::Gif.convert(input, output, fps: fps, width: width)
  end

  # Creates a Web-ready MP4 with faststart moov atom
  def self.web(input : String, output : String, &progress : Runner::Progress -> Nil) : Process::Status
    Presets::Web.convert(input, output, &progress)
  end

  def self.web(input : String, output : String) : Process::Status
    Presets::Web.convert(input, output)
  end

  # Declarative block DSL for automated Sprite Sheet packing and compression
  def self.spritesheet(&) : SpriteSheet::DSL::SpriteSheetBuilder
    builder = SpriteSheet::DSL::SpriteSheetBuilder.new
    with builder yield builder
    builder
  end

  # Fluent chainable Sprite Sheet builder starting from an input path
  def self.spritesheet(input_path : String) : SpriteSheet::DSL::SpriteSheetBuilder
    builder = SpriteSheet::DSL::SpriteSheetBuilder.new
    builder.input(input_path)
    builder
  end
end

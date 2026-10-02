require "./flourite/version"
require "./flourite/error"
require "./flourite/config"
require "./flourite/probe/models"
require "./flourite/probe/runner"
require "./flourite/dsl/input"
require "./flourite/dsl/output"
require "./flourite/dsl/filter_graph"
require "./flourite/dsl/command"
require "./flourite/dsl/builder"
require "./flourite/runner/progress"
require "./flourite/runner/process_runner"
require "./flourite/presets/base"
require "./flourite/presets/discord"
require "./flourite/presets/gif"
require "./flourite/presets/web"
require "./flourite/presets/audio"
require "./flourite/presets/trim"
require "./flourite/batch"
require "./flourite/c/libav"
require "./flourite/docs"

module Flourite
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
end

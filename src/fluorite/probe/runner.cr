require "./models"
require "../config"
require "../error"

module Fluorite
  module Probe
    # Executes ffprobe on a file path or URL and returns a parsed ProbeResult
    def self.run(target : String) : ProbeResult
      ffprobe = Fluorite.config.ffprobe_path
      args = [
        "-v", "quiet",
        "-print_format", "json",
        "-show_format",
        "-show_streams",
        "-show_chapters",
        target,
      ]

      stdout = IO::Memory.new
      stderr = IO::Memory.new

      status = Process.run(ffprobe, args, output: stdout, error: stderr)
      unless status.success?
        raise FFprobeError.new("ffprobe failed on '#{target}': #{stderr.to_s}")
      end

      json_str = stdout.to_s.strip
      if json_str.empty?
        raise FFprobeError.new("ffprobe returned empty output for '#{target}'")
      end

      ProbeResult.from_json(json_str)
    rescue ex : JSON::ParseException
      raise FFprobeError.new("Failed to parse ffprobe JSON output: #{ex.message}")
    end
  end

  # Shortcut method: Fluorite.probe("file.mp4")
  def self.probe(target : String) : Probe::ProbeResult
    Probe.run(target)
  end
end

require "option_parser"
require "opal"
require "../flourite"
require "./tui/app"

module Flourite
  module CLI
    def self.run(args : Array(String) = ARGV) : Nil
      if args.empty?
        # Default with no arguments: Launch interactive TUI
        TUI.run
        return
      end

      subcommand = args[0]
      sub_args = args[1..]

      case subcommand
      when "tui", "ui", "studio"
        TUI.run
      when "probe", "info"
        run_probe(sub_args)
      when "wizard"
        run_wizard
      when "discord"
        run_discord(sub_args)
      when "gif"
        run_gif(sub_args)
      when "trim", "cut"
        run_trim(sub_args)
      when "audio", "sound"
        run_audio(sub_args)
      when "convert"
        run_convert(sub_args)
      when "version", "-v", "--version"
        run_version
      when "help", "-h", "--help"
        run_help
      else
        # If the argument is an existing media file, probe it directly!
        if File.exists?(subcommand)
          run_probe([subcommand])
        else
          puts Opal.style.bold.fg(:red).render("Unknown command or file: #{subcommand}")
          run_help
        end
      end
    end

    def self.run_probe(args : Array(String)) : Nil
      json_output = false
      target_file : String? = nil

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: flourite probe <file_or_url> [options]"
        opts.on("--json", "Output raw ffprobe JSON") { json_output = true }
        opts.on("-h", "--help", "Show help") { puts opts; exit 0 }
      end
      parser.parse(args)

      target_file = args.first?
      unless target_file
        puts Opal.style.bold.fg(:red).render("Error: No media file specified to probe.")
        exit 1
      end

      unless File.exists?(target_file) || target_file.starts_with?("http")
        puts Opal.style.bold.fg(:red).render("Error: File not found: '#{target_file}'")
        exit 1
      end

      result = Flourite.probe(target_file)

      if json_output
        puts result.to_json
        return
      end

      # Render styled Opal Media Card
      puts
      puts Opal.style.bold.fg(:magenta).render("╔══════════════════════════════════════════════════════════════╗")
      puts Opal.style.bold.fg(:magenta).render("║                FLOURITE MEDIA INSPECTOR                      ║")
      puts Opal.style.bold.fg(:magenta).render("╚══════════════════════════════════════════════════════════════╝")
      puts "  " + Opal.style.bold.render("File:      ") + Opal.style.fg(:cyan).render(target_file)
      puts "  " + Opal.style.bold.render("Format:    ") + "#{result.format_name} (#{result.human_size})"
      puts "  " + Opal.style.bold.render("Duration:  ") + "#{result.duration_formatted} (#{result.duration.total_seconds.round(2)}s)"
      puts "  " + Opal.style.bold.render("Bitrate:   ") + "#{result.format.bitrate_kbps} kbps"
      puts

      if vid = result.primary_video_stream
        puts Opal.style.bold.fg(:green).render("  ▶ Video Track:")
        puts "    Codec:       #{vid.codec_name} [#{vid.profile || "default"}]"
        res_s = vid.resolution ? "#{vid.resolution.not_nil![0]}x#{vid.resolution.not_nil![1]}" : "N/A"
        puts "    Resolution:  #{res_s} (Aspect: #{vid.aspect_ratio_str})"
        puts "    Framerate:   #{vid.fps.round(2)} fps"
        puts "    Pixel Fmt:   #{vid.pix_fmt || "N/A"}"
        puts "    Bitrate:     #{vid.bitrate_kbps ? "#{vid.bitrate_kbps} kbps" : "auto"}"
        puts
      end

      result.audio_streams.each_with_index do |aud, idx|
        puts Opal.style.bold.fg(:yellow).render("  ▶ Audio Track ##{idx + 1}:")
        puts "    Codec:       #{aud.codec_name}"
        puts "    Channels:    #{aud.channels || 2}ch (#{aud.channel_layout || "stereo"})"
        puts "    Sample Rate: #{aud.sample_rate || 48000} Hz"
        puts "    Bitrate:     #{aud.bitrate_kbps ? "#{aud.bitrate_kbps} kbps" : "auto"}"
        puts
      end

      unless result.subtitle_streams.empty?
        puts Opal.style.bold.fg(:blue).render("  ▶ Subtitles:")
        result.subtitle_streams.each_with_index do |sub, idx|
          lang = sub.tags.try(&.[]?("language")) || "und"
          puts "    ##{idx + 1}: #{sub.codec_name} [#{lang}]"
        end
        puts
      end
    end

    def self.run_discord(args : Array(String)) : Nil
      target_mb = 24.5
      output_file : String? = nil
      input_file : String? = nil

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: flourite discord <input_file> [options]"
        opts.on("--limit LIMIT", "Target size in MB (e.g. 10, 25, 50)") do |lim|
          clean = lim.gsub(/[^0-9.]/, "")
          target_mb = clean.to_f64? || 24.5
          target_mb -= 0.5 if target_mb > 1.0 # 0.5MB safety margin
        end
        opts.on("-o FILE", "--output FILE", "Output file path") { |o| output_file = o }
        opts.on("-h", "--help", "Show help") { puts opts; exit 0 }
      end
      parser.parse(args)

      input_file = args.first?
      unless input_file
        puts Opal.style.bold.fg(:red).render("Error: No input file specified.")
        exit 1
      end

      in_file = input_file.not_nil!
      out_file = (output_file || "#{File.basename(in_file, File.extname(in_file))}_discord#{(target_mb + 0.5).to_i}mb.mp4").as(String)

      puts Opal.style.bold.fg(:cyan).render("\n=== Flourite Discord Optimizer ===")
      puts "Input:     #{in_file}"
      puts "Output:    #{out_file}"
      puts "Target:    < #{target_mb + 0.5} MB\n"

      start_time = Time.instant
      Presets::Discord.convert(in_file, out_file, target_mb: target_mb) do |p|
        pct = p.percent.clamp(0.0, 100.0)
        print "\r#{p.bar(30)} | Speed: #{p.speed_formatted} | FPS: #{p.fps.round(1)} | ETA: #{p.eta_formatted}"
      end

      elapsed = (Time.instant - start_time).total_seconds
      puts
      puts Opal.style.bold.fg(:green).render("✓ Finished in #{elapsed.round(1)}s! Output size: #{human_file_size(out_file)}")
    end

    def self.run_gif(args : Array(String)) : Nil
      fps = 15
      width = 480
      output_file : String? = nil
      input_file : String? = nil
      seek : String? = nil
      duration : String? = nil

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: flourite gif <input_file> [options]"
        opts.on("--fps FPS", "Frame rate (default: 15)") { |f| fps = f.to_i? || 15 }
        opts.on("--width W", "Width in pixels (default: 480)") { |w| width = w.to_i? || 480 }
        opts.on("--seek TIME", "Start timestamp (HH:MM:SS)") { |s| seek = s }
        opts.on("--duration TIME", "Clip duration (HH:MM:SS or seconds)") { |d| duration = d }
        opts.on("-o FILE", "--output FILE", "Output gif path") { |o| output_file = o }
        opts.on("-h", "--help", "Show help") { puts opts; exit 0 }
      end
      parser.parse(args)

      input_file = args.first?
      unless input_file
        puts Opal.style.bold.fg(:red).render("Error: No input file specified.")
        exit 1
      end

      in_file = input_file.not_nil!
      out_file = (output_file || "#{File.basename(in_file, File.extname(in_file))}.gif").as(String)

      puts Opal.style.bold.fg(:magenta).render("\n=== Flourite High-Definition GIF Generator ===")
      puts "Input:     #{in_file}"
      puts "Output:    #{out_file}"
      puts "Specs:     #{width}px width @ #{fps} fps (2-pass palette)\n"

      start_time = Time.instant
      Presets::Gif.convert(in_file, out_file, fps: fps, width: width, seek: seek, duration: duration) do |p|
        print "\r#{p.bar(30)} | Speed: #{p.speed_formatted} | FPS: #{p.fps.round(1)} | ETA: #{p.eta_formatted}"
      end

      elapsed = (Time.instant - start_time).total_seconds
      puts
      puts Opal.style.bold.fg(:green).render("✓ Created #{out_file} (#{human_file_size(out_file)}) in #{elapsed.round(1)}s!")
    end

    def self.run_trim(args : Array(String)) : Nil
      from_time : String? = nil
      to_time : String? = nil
      duration : String? = nil
      output_file : String? = nil
      input_file : String? = nil

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: flourite trim <input_file> --from <HH:MM:SS> [options]"
        opts.on("--from TIME", "Start time") { |t| from_time = t }
        opts.on("--to TIME", "End time") { |t| to_time = t }
        opts.on("--duration TIME", "Duration") { |d| duration = d }
        opts.on("-o FILE", "--output FILE", "Output path") { |o| output_file = o }
        opts.on("-h", "--help", "Show help") { puts opts; exit 0 }
      end
      parser.parse(args)

      input_file = args.first?
      unless input_file && from_time
        puts Opal.style.bold.fg(:red).render("Error: Both <input_file> and --from are required.")
        exit 1
      end

      in_file = input_file.not_nil!
      out_file = (output_file || "#{File.basename(in_file, File.extname(in_file))}_cut#{File.extname(in_file)}").as(String)

      puts Opal.style.bold.fg(:cyan).render("\n=== Flourite Lossless Fast Trim ===")
      puts "Cutting '#{in_file}' from #{from_time} to #{to_time || duration || "end"}..."

      Presets::Trim.cut(in_file, out_file, from: from_time.not_nil!, to: to_time, duration: duration)
      puts Opal.style.bold.fg(:green).render("✓ Lossless cut completed: #{out_file}")
    end

    def self.run_audio(args : Array(String)) : Nil
      target_format = :mp3
      bitrate = "320k"
      output_file : String? = nil
      input_file : String? = nil

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: flourite audio <input_file> [options]"
        opts.on("--format FMT", "Audio format: mp3, opus, aac, flac, wav") do |f|
          target_format = case f.downcase
                          when "opus" then :opus
                          when "aac"  then :aac
                          when "flac" then :flac
                          when "wav"  then :wav
                          else             :mp3
                          end
        end
        opts.on("--bitrate BR", "Audio bitrate (e.g. 320k, 192k)") { |b| bitrate = b }
        opts.on("-o FILE", "--output FILE", "Output audio file") { |o| output_file = o }
        opts.on("-h", "--help", "Show help") { puts opts; exit 0 }
      end
      parser.parse(args)

      input_file = args.first?
      unless input_file
        puts Opal.style.bold.fg(:red).render("Error: No input file specified.")
        exit 1
      end

      in_file = input_file.not_nil!
      out_file = (output_file || "#{File.basename(in_file, File.extname(in_file))}.#{target_format}").as(String)

      puts Opal.style.bold.fg(:yellow).render("\n=== Flourite Audio Extraction ===")
      puts "Input:     #{in_file}"
      puts "Output:    #{out_file} (#{target_format.to_s.upcase} @ #{bitrate})\n"

      Presets::Audio.extract(in_file, out_file, format: target_format, bitrate: bitrate) do |p|
        print "\r#{p.bar(30)} | Speed: #{p.speed_formatted} | ETA: #{p.eta_formatted}"
      end

      puts
      puts Opal.style.bold.fg(:green).render("✓ Extracted #{out_file} (#{human_file_size(out_file)})")
    end

    def self.run_convert(args : Array(String)) : Nil
      input_file : String? = nil
      output_file : String? = nil
      vcodec : String? = nil
      acodec : String? = nil
      crf : Int32? = nil
      preset : String? = nil
      scale_w : Int32? = nil
      scale_h : Int32? = nil

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: flourite convert <input> -o <output> [options]"
        opts.on("-o FILE", "--output FILE", "Output path") { |o| output_file = o }
        opts.on("--vcodec CODEC", "Video codec") { |c| vcodec = c }
        opts.on("--acodec CODEC", "Audio codec") { |c| acodec = c }
        opts.on("--crf NUM", "CRF value") { |c| crf = c.to_i? }
        opts.on("--preset NAME", "Encoding preset") { |p| preset = p }
        opts.on("--scale WxH", "Scale resolution") do |s|
          parts = s.split('x')
          if parts.size == 2
            scale_w = parts[0].to_i?
            scale_h = parts[1].to_i?
          end
        end
        opts.on("-h", "--help", "Show help") { puts opts; exit 0 }
      end
      parser.parse(args)

      input_file = args.first?
      unless input_file && output_file
        puts Opal.style.bold.fg(:red).render("Error: Both input and -o output are required.")
        exit 1
      end

      in_target = input_file.not_nil!
      out_target = output_file.not_nil!

      cmd = Flourite.build do
        overwrite!
        input(in_target)

        video do |v|
          if vc = vcodec
            v.video_codec(vc)
          end
          if cf = crf
            v.crf(cf)
          end
          if pr = preset
            v.preset(pr)
          end
          if (w = scale_w) && (h = scale_h)
            v.scale(w, h)
          end
        end

        audio do |a|
          if ac = acodec
            a.audio_codec(ac)
          end
        end

        output(out_target)
      end

      puts Opal.style.bold.fg(:cyan).render("\n=== Flourite Transcoder ===")
      puts "Running: #{cmd.to_cmd_string}\n\n"

      cmd.run do |p|
        print "\r#{p.bar(30)} | Speed: #{p.speed_formatted} | FPS: #{p.fps.round(1)} | ETA: #{p.eta_formatted}"
      end
      puts
      puts Opal.style.bold.fg(:green).render("✓ Transcode finished: #{out_target}")
    end

    def self.run_wizard : Nil
      puts Opal.style.bold.fg(:magenta).render("\n=== Flourite Interactive Setup Wizard ===\n")

      # Discover media files
      files = [] of String
      Dir.children(Dir.current).each do |f|
        ext = File.extname(f).downcase
        files << f if TUI::App::MEDIA_EXTENSIONS.includes?(ext) && File.file?(f)
      end

      if files.empty?
        puts Opal.style.bold.fg(:yellow).render("No media files found in current directory.")
        files << Opal.ask("Enter media file path or URL", required: true)
      end

      chosen_file = Opal.select("Select media file to process", files)

      # Probe file
      probe = Flourite.probe(chosen_file)
      puts Opal.style.fg(:cyan).render("\nDetected: #{probe.format_name} | #{probe.duration_formatted} | #{probe.video_summary}")

      goal = Opal.select("Select conversion goal", [
        "Discord Fit (< 25MB auto bitrate)",
        "Discord Free Tier (< 10MB auto bitrate)",
        "FastWeb MP4 (FastStart streamable)",
        "High Quality GIF (2-pass palette)",
        "Extract Audio (MP3 320k)",
        "Extract Audio (Opus 160k)",
      ])

      base_name = File.basename(chosen_file, File.extname(chosen_file))
      default_out = case goal
                    when .starts_with?("Discord Fit")  then "#{base_name}_discord25.mp4"
                    when .starts_with?("Discord Free") then "#{base_name}_discord10.mp4"
                    when .starts_with?("FastWeb")      then "#{base_name}_web.mp4"
                    when .starts_with?("High Quality") then "#{base_name}.gif"
                    when .starts_with?("Extract Audio (MP3") then "#{base_name}.mp3"
                    else "#{base_name}.opus"
                    end

      out_file = Opal.ask("Destination output path", default: default_out)

      confirm = Opal.confirm("Ready to transcode now?", default: true)
      return unless confirm

      puts Opal.style.bold.fg(:green).render("\nStarting transcode...")

      case goal
      when .starts_with?("Discord Fit")
        Presets::Discord.convert(chosen_file, out_file, target_mb: 24.5) do |p|
          print "\r#{p.bar(30)} | Speed: #{p.speed_formatted} | ETA: #{p.eta_formatted}"
        end
      when .starts_with?("Discord Free")
        Presets::Discord.convert(chosen_file, out_file, target_mb: 9.5) do |p|
          print "\r#{p.bar(30)} | Speed: #{p.speed_formatted} | ETA: #{p.eta_formatted}"
        end
      when .starts_with?("FastWeb")
        Presets::Web.convert(chosen_file, out_file) do |p|
          print "\r#{p.bar(30)} | Speed: #{p.speed_formatted} | ETA: #{p.eta_formatted}"
        end
      when .starts_with?("High Quality")
        Presets::Gif.convert(chosen_file, out_file) do |p|
          print "\r#{p.bar(30)} | Speed: #{p.speed_formatted} | ETA: #{p.eta_formatted}"
        end
      when .starts_with?("Extract Audio (MP3")
        Presets::Audio.extract(chosen_file, out_file, format: :mp3) do |p|
          print "\r#{p.bar(30)} | Speed: #{p.speed_formatted} | ETA: #{p.eta_formatted}"
        end
      else
        Presets::Audio.extract(chosen_file, out_file, format: :opus) do |p|
          print "\r#{p.bar(30)} | Speed: #{p.speed_formatted} | ETA: #{p.eta_formatted}"
        end
      end

      puts
      puts Opal.style.bold.fg(:green).render("✓ Finished! Generated: #{out_file}")
    end

    def self.run_version : Nil
      puts "Flourite #{Flourite::VERSION}"
      cfg = Flourite.config
      puts "  FFmpeg:  #{cfg.ffmpeg_path} (#{cfg.ffmpeg_available? ? "Available" : "Missing"})"
      puts "  FFprobe: #{cfg.ffprobe_path} (#{cfg.ffprobe_available? ? "Available" : "Missing"})"
      puts "  NVENC:   #{cfg.nvenc_available? ? "Detected" : "Not detected"}"
      puts "  QSV:     #{cfg.qsv_available? ? "Detected" : "Not detected"}"
      puts "  AMF:     #{cfg.amf_available? ? "Detected" : "Not detected"}"
    end

    def self.run_help : Nil
      puts <<-HELP
Flourite #{Flourite::VERSION} - FFMPEG Studio & DSL for Crystal

USAGE:
  flourite                     Launch interactive full-screen Opal TUI
  flourite tui                 Launch interactive full-screen Opal TUI
  flourite wizard              Step-by-step interactive CLI setup wizard
  flourite probe <file>        Inspect media file specs, codecs & streams
  flourite discord <file>      Auto bit-budget to strictly fit Discord size limits
  flourite gif <file>          High-definition 2-pass palette GIF generator
  flourite trim <file>         Instant lossless stream-copy cut (-c copy)
  flourite audio <file>        Extract MP3 / Opus / FLAC / AAC audio track
  flourite convert <in> -o ... Fluent transcode with video/audio parameters
  flourite version             Show version and hardware acceleration details
  flourite help                Show this help screen
HELP
    end

    private def self.human_file_size(path : String) : String
      return "0 B" unless File.exists?(path)
      bytes = File.size(path).to_f64
      units = ["B", "KB", "MB", "GB"]
      idx = 0
      while bytes >= 1024.0 && idx < units.size - 1
        bytes /= 1024.0
        idx += 1
      end
      "#{bytes.round(2)} #{units[idx]}"
    end
  end
end

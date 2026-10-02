require "opal"
require "../../flourite"

module Flourite
  module TUI
    class App
      include Opal::TEA::Model

      MEDIA_EXTENSIONS = Set{
        ".mp4", ".mkv", ".mov", ".avi", ".webm", ".flv", ".wmv", ".ts", ".m4v",
        ".mp3", ".wav", ".ogg", ".flac", ".m4a", ".aac", ".opus",
        ".gif",
      }

      enum ActivePane
        Files
        Presets
        Logs
      end

      getter header : Opal::UI::Header
      getter footer : Opal::UI::Footer
      getter rich_log : Opal::UI::RichLog
      getter media_files : Array(String) = [] of String
      property selected_file_idx : Int32 = 0
      property active_pane : ActivePane = ActivePane::Files

      getter presets : Array(Tuple(String, String)) = [
        {"Discord (25MB)", "Auto-allocates video & audio bitrates to guarantee < 25MB"},
        {"Discord (10MB)", "Strictly fits under Discord free attachment limit"},
        {"Web MP4 (FastStart)", "H.264 + AAC with moov atom up front for instant streaming"},
        {"High-Definition GIF", "2-pass palettegen + paletteuse with Lanczos scaling"},
        {"Extract Audio (MP3)", "Direct 320kbps MP3 extraction without video"},
        {"Extract Audio (Opus)", "High-efficiency 160kbps Opus extraction"},
        {"Lossless Fast Trim", "Instant stream-copy cut in milliseconds without re-encoding"},
      ]
      property selected_preset_idx : Int32 = 0

      property current_probe : Probe::ProbeResult? = nil
      property current_runner : Runner::ProcessRunner? = nil
      property running_job : Bool = false
      property job_completed : Bool = false
      property latest_progress : Runner::Progress = Runner::Progress.new
      property status_message : String = "Ready. Select a file and preset to begin."
      property generated_cmd : String = ""

      def initialize
        # Header & Footer
        @header = Opal::UI::Header.new(
          title: "FLOURITE FFMPEG STUDIO",
          subtitle: "v#{Flourite::VERSION} - Fluent Crystal Video Engine",
          icon: "🎬",
          show_clock: true
        )

        @footer = Opal::UI::Footer.new
        @footer.add("Tab", "Switch Pane")
        @footer.add("↑/↓", "Navigate")
        @footer.add("Enter", "Execute Transcode")
        @footer.add("C", "Copy Command")
        @footer.add("R", "Refresh Files")
        @footer.add("Q", "Quit")

        @rich_log = Opal::UI::RichLog.new(max_lines: 200)
        @rich_log.write("[Studio] Flourite TUI booted. Engine: pure-crystal.")

        refresh_files
        update_selected_probe
      end

      def refresh_files
        @media_files.clear
        current_dir = Dir.current
        Dir.children(current_dir).each do |entry|
          ext = File.extname(entry).downcase
          if MEDIA_EXTENSIONS.includes?(ext) && File.file?(entry)
            @media_files << entry
          end
        end
        @media_files.sort!
        @selected_file_idx = 0 if @selected_file_idx >= @media_files.size
      end

      def selected_file : String?
        @media_files[@selected_file_idx]?
      end

      def update_selected_probe
        file = selected_file
        if file && File.exists?(file)
          begin
            @current_probe = Flourite.probe(file)
            update_command_preview
          rescue ex
            @current_probe = nil
          end
        else
          @current_probe = nil
          @generated_cmd = ""
        end
      end

      def update_command_preview
        file = selected_file
        return unless file

        preset_title = @presets[@selected_preset_idx][0]
        base_name = File.basename(file, File.extname(file))

        case preset_title
        when "Discord (25MB)"
          out_file = "#{base_name}_discord25.mp4"
          @generated_cmd = Presets::Discord.build_command(file, out_file, target_mb: 24.5).to_cmd_string
        when "Discord (10MB)"
          out_file = "#{base_name}_discord10.mp4"
          @generated_cmd = Presets::Discord.build_command(file, out_file, target_mb: 9.5).to_cmd_string
        when "Web MP4 (FastStart)"
          out_file = "#{base_name}_web.mp4"
          @generated_cmd = Presets::Web.build_command(file, out_file).to_cmd_string
        when "High-Definition GIF"
          out_file = "#{base_name}.gif"
          @generated_cmd = Presets::Gif.build_command(file, out_file).to_cmd_string
        when "Extract Audio (MP3)"
          out_file = "#{base_name}.mp3"
          @generated_cmd = Presets::Audio.build_command(file, out_file, format: :mp3).to_cmd_string
        when "Extract Audio (Opus)"
          out_file = "#{base_name}.opus"
          @generated_cmd = Presets::Audio.build_command(file, out_file, format: :opus).to_cmd_string
        when "Lossless Fast Trim"
          out_file = "#{base_name}_trim.mp4"
          @generated_cmd = Presets::Trim.build_command(file, out_file, from: "00:00:00", to: "00:00:30").to_cmd_string
        end
      rescue ex
        @generated_cmd = "# Unable to generate command: #{ex.message}"
      end

      def start_conversion
        file = selected_file
        unless file
          @status_message = "No media file selected!"
          return
        end

        return if @running_job

        update_command_preview
        preset_title = @presets[@selected_preset_idx][0]
        base_name = File.basename(file, File.extname(file))

        @running_job = true
        @job_completed = false
        @status_message = "Transcoding '#{file}' with preset '#{preset_title}'..."
        @rich_log.write("[Start] #{status_message}")
        @rich_log.write("[Cmd] #{@generated_cmd}")

        spawn do
          cmd = case preset_title
                when "Discord (25MB)"
                  Presets::Discord.build_command(file, "#{base_name}_discord25.mp4", target_mb: 24.5)
                when "Discord (10MB)"
                  Presets::Discord.build_command(file, "#{base_name}_discord10.mp4", target_mb: 9.5)
                when "Web MP4 (FastStart)"
                  Presets::Web.build_command(file, "#{base_name}_web.mp4")
                when "High-Definition GIF"
                  Presets::Gif.build_command(file, "#{base_name}.gif")
                when "Extract Audio (MP3)"
                  Presets::Audio.build_command(file, "#{base_name}.mp3", format: :mp3)
                when "Extract Audio (Opus)"
                  Presets::Audio.build_command(file, "#{base_name}.opus", format: :opus)
                else
                  Presets::Trim.build_command(file, "#{base_name}_trim.mp4", from: "00:00:00", to: "00:00:30")
                end

          runner = cmd.run_async
          @current_runner = runner

          runner.on_progress do |prog|
            @latest_progress = prog
          end

          runner.on_log do |line|
            @rich_log.write(line)
          end

          begin
            status = runner.wait
            @running_job = false
            @job_completed = true
            if status.success?
              @status_message = "Transcode completed successfully!"
              @rich_log.write("[Success] Output generated successfully.")
            else
              @status_message = "Transcode failed with exit code #{status.exit_code}."
              @rich_log.write("[Error] Transcode failed.")
            end
          rescue ex
            @running_job = false
            @status_message = "Error: #{ex.message}"
            @rich_log.write("[Exception] #{ex.message}")
          end
        end
      end

      # --- TEA Lifecycle ---

      def init : Opal::TEA::Cmd
        schedule_tick
      end

      def update(msg : Opal::TEA::Msg) : {Opal::TEA::Model, Opal::TEA::Cmd}
        case msg
        when Opal::TEA::TickMsg
          {self, schedule_tick}
        when Opal::TEA::KeyMsg
          case msg.key
          when "q", "Q", "esc", "escape"
            {self, Opal::TEA::Cmd.quit}
          when "tab"
            @active_pane = case @active_pane
                           when ActivePane::Files   then ActivePane::Presets
                           when ActivePane::Presets then ActivePane::Logs
                           when ActivePane::Logs    then ActivePane::Files
                           else                          ActivePane::Files
                           end
            {self, Opal::TEA::Cmd.redraw}
          when "up", "k"
            case @active_pane
            when ActivePane::Files
              if @selected_file_idx > 0
                @selected_file_idx -= 1
                update_selected_probe
              end
            when ActivePane::Presets
              if @selected_preset_idx > 0
                @selected_preset_idx -= 1
                update_command_preview
              end
            when ActivePane::Logs
              @rich_log.auto_scroll = false
              @rich_log.scroll_offset = Math.max(0, @rich_log.scroll_offset - 2)
            end
            {self, Opal::TEA::Cmd.redraw}
          when "down", "j"
            case @active_pane
            when ActivePane::Files
              if @selected_file_idx < @media_files.size - 1
                @selected_file_idx += 1
                update_selected_probe
              end
            when ActivePane::Presets
              if @selected_preset_idx < @presets.size - 1
                @selected_preset_idx += 1
                update_command_preview
              end
            when ActivePane::Logs
              @rich_log.scroll_offset += 2
            end
            {self, Opal::TEA::Cmd.redraw}
          when "enter", " "
            start_conversion
            {self, Opal::TEA::Cmd.redraw}
          when "c", "C"
            if !@generated_cmd.empty?
              Opal.copy_to_clipboard(@generated_cmd)
              @status_message = "Copied FFmpeg command to system clipboard!"
              @rich_log.write("[Clipboard] Command copied to clipboard.")
            end
            {self, Opal::TEA::Cmd.redraw}
          when "r", "R"
            refresh_files
            update_selected_probe
            @status_message = "Refreshed media files in directory."
            {self, Opal::TEA::Cmd.redraw}
          else
            {self, Opal::TEA::Cmd.redraw}
          end
        else
          {self, Opal::TEA::Cmd.none}
        end
      end

      # --- Rendering ---

      def render(buffer : Opal::UI::Buffer) : Nil
        cols = buffer.width
        rows = buffer.height
        return if cols < 40 || rows < 12

        buffer.fill(0, 0, cols, rows, ' ')
        theme = Opal::Theme.current

        # Header & Footer
        @header.render(buffer, 0, 0, cols, 1)
        @footer.render(buffer, 0, rows - 1, cols, 1)

        main_y = 1
        main_h = Math.max(0, rows - 2)

        # Split screen into: Left (Files & Presets), Right (Inspector & Telemetry/Logs)
        left_w = Math.min(36, (cols * 0.35).to_i)
        right_x = left_w + 1
        right_w = Math.max(20, cols - right_x)

        # 1. Left Top: Media Files Box
        files_h = Math.max(5, (main_h * 0.52).to_i)
        files_border_fg = @active_pane.files? ? theme.primary : theme.border
        files_box = Opal::UI::Box.new(
          border: :rounded,
          title: "Media Files (#{@media_files.size})",
          border_fg: files_border_fg,
          title_fg: theme.primary
        )
        files_box.render(buffer, 0, main_y, left_w, files_h)

        if @media_files.empty?
          buffer.put_string(2, main_y + 2, "(No media files found in .)", fg: theme.text_muted)
          buffer.put_string(2, main_y + 3, "Press 'R' after adding video/audio", fg: theme.text_muted)
        else
          max_visible = files_h - 2
          @media_files.each_with_index do |filename, idx|
            break if idx >= max_visible
            is_sel = idx == @selected_file_idx
            prefix = is_sel ? "▶ " : "  "
            display_str = "#{prefix}#{filename}"
            if display_str.size > left_w - 4
              display_str = display_str[0...(left_w - 7)] + "..."
            end
            fg_col = is_sel ? theme.accent : theme.text
            buffer.put_string(2, main_y + 1 + idx, display_str, fg: fg_col, bold: is_sel)
          end
        end

        # 2. Left Bottom: Presets Box
        presets_y = main_y + files_h
        presets_h = Math.max(5, main_h - files_h)
        presets_border_fg = @active_pane.presets? ? theme.primary : theme.border
        presets_box = Opal::UI::Box.new(
          border: :rounded,
          title: "Conversion Presets",
          border_fg: presets_border_fg,
          title_fg: theme.accent
        )
        presets_box.render(buffer, 0, presets_y, left_w, presets_h)

        max_p_visible = presets_h - 2
        @presets.each_with_index do |preset, idx|
          break if idx >= max_p_visible
          is_sel = idx == @selected_preset_idx
          prefix = is_sel ? "● " : "○ "
          display_str = "#{prefix}#{preset[0]}"
          if display_str.size > left_w - 4
            display_str = display_str[0...(left_w - 7)] + "..."
          end
          fg_col = is_sel ? theme.success : theme.text_muted
          buffer.put_string(2, presets_y + 1 + idx, display_str, fg: fg_col, bold: is_sel)
        end

        # 3. Right Top: Media Info & Command Preview
        info_h = Math.min(10, (main_h * 0.42).to_i)
        info_box = Opal::UI::Box.new(
          border: :rounded,
          title: "Inspector & Target",
          border_fg: theme.border,
          title_fg: theme.info
        )
        info_box.render(buffer, right_x, main_y, right_w, info_h)

        if probe = @current_probe
          buffer.put_string(right_x + 2, main_y + 1, "Format:   #{probe.format_name} (#{probe.human_size})", bold: true)
          buffer.put_string(right_x + 2, main_y + 2, "Duration: #{probe.duration_formatted}")
          buffer.put_string(right_x + 2, main_y + 3, probe.video_summary, fg: theme.primary)
          buffer.put_string(right_x + 2, main_y + 4, probe.audio_summary, fg: theme.accent)
        else
          buffer.put_string(right_x + 2, main_y + 2, "Select a valid media file to inspect details.", fg: theme.text_muted)
        end

        if info_h >= 8 && !@generated_cmd.empty?
          buffer.put_string(right_x + 2, main_y + 6, "Generated Command (Press 'C' to copy):", fg: theme.warning, bold: true)
          cmd_preview = @generated_cmd
          if cmd_preview.size > right_w - 4
            cmd_preview = cmd_preview[0...(right_w - 7)] + "..."
          end
          buffer.put_string(right_x + 2, main_y + 7, cmd_preview, fg: theme.text_muted)
        end

        # 4. Right Bottom: Transcode Monitor & Streaming RichLog
        mon_y = main_y + info_h
        mon_h = Math.max(5, main_h - info_h)
        mon_border_fg = @active_pane.logs? ? theme.primary : theme.border
        mon_box = Opal::UI::Box.new(
          border: :rounded,
          title: "Job Monitor & Stream Log",
          border_fg: mon_border_fg,
          title_fg: theme.success
        )
        mon_box.render(buffer, right_x, mon_y, right_w, mon_h)

        # Progress bar & metrics line
        prog = @latest_progress
        status_badge = if @running_job
                         "[RUNNING]"
                       elsif @job_completed
                         "[COMPLETED]"
                       else
                         "[IDLE]"
                       end
        badge_fg = @running_job ? theme.warning : (@job_completed ? theme.success : theme.text_muted)

        buffer.put_string(right_x + 2, mon_y + 1, status_badge, fg: badge_fg, bold: true)
        buffer.put_string(right_x + 13, mon_y + 1, @status_message, fg: theme.text)

        bar_str = prog.bar(Math.max(10, right_w - 45))
        stats_str = "Speed: #{prog.speed_formatted} | FPS: #{prog.fps.round(1)} | ETA: #{prog.eta_formatted}"
        buffer.put_string(right_x + 2, mon_y + 2, "#{bar_str}  #{stats_str}", fg: theme.accent, bold: true)

        # RichLog stream
        log_y = mon_y + 4
        log_h = Math.max(1, mon_h - 5)
        if log_h > 0
          buffer.put_string(right_x + 2, mon_y + 3, "─" * Math.max(0, right_w - 4), fg: theme.border)
          @rich_log.render(buffer, right_x + 1, log_y, right_w - 2, log_h)
        end
      end

      def view : String
        cols, rows = Opal::Terminal.default_driver.size
        cols = cols.clamp(70, 160)
        rows = rows.clamp(20, 50)

        buffer = Opal::UI::Buffer.new(cols, rows)
        render(buffer)
        buffer.render_to_string(with_ansi: true)
      end

      private def schedule_tick : Opal::TEA::Cmd
        Opal::TEA::Cmd.tick(100.milliseconds) do |_time|
          Opal::TEA::TickMsg.new
        end
      end
    end

    def self.run : Nil
      Opal.run_tea(App.new, alt_screen: true, diff_render: true)
    end
  end
end

require "opal"
require "../../fluorite"
require "./core/telemetry_engine"
require "./split_pane_bridge"
require "./telemetry_dashboard"

module Fluorite
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
        Queue
        Logs
      end

      getter header : Opal::UI::Header
      getter footer : Opal::UI::Footer
      getter rich_log : Opal::UI::RichLog
      getter telemetry : Core::TelemetryEngine
      getter batch_queue : BatchQueue
      getter telemetry_dashboard : TelemetryDashboard
      getter media_files : Array(String) = [] of String
      property selected_file_idx : Int32 = 0
      property selected_job_idx : Int32 = 0
      property active_pane : ActivePane = ActivePane::Files

      property main_split_ratio : Float64 = 0.34
      property left_split_ratio : Float64 = 0.52
      property right_top_ratio : Float64 = 0.30
      property telemetry_split_ratio : Float64 = 0.48

      getter presets : Array(Tuple(String, String)) = [
        {"Discord (25MB)", "Auto-allocates video & audio bitrates to guarantee < 25MB"},
        {"Discord (10MB)", "Strictly fits under Discord free attachment limit"},
        {"Web MP4 (FastStart)", "H.264 + AAC with moov atom up front for instant streaming"},
        {"High-Definition GIF", "2-pass palettegen + paletteuse with Lanczos scaling"},
        {"Sprite Sheet (CLUT8)", "Packs frames into 256-color indexed atlas with 75% VRAM savings"},
        {"Sprite Sheet (CLUT4)", "Packs frames into 16-color PS2 GS CLUT4 atlas with 87.5% VRAM savings"},
        {"Extract Audio (MP3)", "Direct 320kbps MP3 extraction without video"},
        {"Extract Audio (Opus)", "High-efficiency 160kbps Opus extraction"},
        {"Lossless Fast Trim", "Instant stream-copy cut in milliseconds without re-encoding"},
      ]
      property selected_preset_idx : Int32 = 0

      property current_probe : Probe::ProbeResult? = nil
      property current_sprite_plan : SpriteSheet::Core::AtlasPlan? = nil
      property current_runner : Runner::ProcessRunner? = nil
      property running_job : Bool = false
      property job_completed : Bool = false
      property latest_progress : Runner::Progress = Runner::Progress.new
      property status_message : String = "Ready. Select a file and preset to begin."
      property generated_cmd : String = ""

      def initialize
        @header = Opal::UI::Header.new(
          title: "FLUORITE FFMPEG STUDIO",
          subtitle: "v#{Fluorite::VERSION} - Split-Pane Telemetry & Sprite Packing TUI",
          icon: "🎬",
          show_clock: true
        )

        @footer = Opal::UI::Footer.new
        @footer.add("Tab", "Switch Pane")
        @footer.add("↑/↓", "Navigate")
        @footer.add("A", "Queue File")
        @footer.add("B", "Run Batch")
        @footer.add("Enter", "Transcode")
        @footer.add("[/]", "Resize Split")
        @footer.add("C", "Copy Cmd")
        @footer.add("Q", "Quit")

        @rich_log = Opal::UI::RichLog.new(max_lines: 200)
        @rich_log.write("[Studio] Fluorite TUI booted. Split-pane telemetry & batch queue ready.")

        @telemetry = Core::TelemetryEngine.new(capacity: 60)
        @batch_queue = BatchQueue.new
        @telemetry_dashboard = TelemetryDashboard.new(
          telemetry: @telemetry,
          queue: @batch_queue,
          direction: :horizontal,
          split_ratio: 0.52
        )

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

      def active_preset_title : String
        @presets[@selected_preset_idx][0]
      end

      def update_selected_probe
        file = selected_file
        if file && File.exists?(file)
          begin
            @current_probe = Fluorite.probe(file)
          rescue
            @current_probe = nil
          end
          update_command_preview
        elsif file
          @current_probe = nil
          update_command_preview
        else
          @current_probe = nil
          @current_sprite_plan = nil
          @telemetry.attach_sprite_plan(nil)
          @generated_cmd = ""
        end
      end

      def update_command_preview
        file = selected_file
        unless file
          @current_sprite_plan = nil
          @telemetry.attach_sprite_plan(nil)
          @generated_cmd = ""
          return
        end

        preset_title = active_preset_title
        base_name = File.basename(file, File.extname(file))
        @current_sprite_plan = nil

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
        when "Sprite Sheet (CLUT8)"
          out_file = "#{base_name}_sheet.png"
          plan = Presets::SpriteSheet.build_plan(file, out_file, format: :clut8)
          @current_sprite_plan = plan
          @generated_cmd = Presets::SpriteSheet.build_command(file, out_file, format: :clut8).to_cmd_string
        when "Sprite Sheet (CLUT4)"
          out_file = "#{base_name}_clut4_sheet.png"
          plan = Presets::SpriteSheet.build_plan(file, out_file, format: :clut4)
          @current_sprite_plan = plan
          @generated_cmd = Presets::SpriteSheet.build_command(file, out_file, format: :clut4).to_cmd_string
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

        @telemetry.attach_sprite_plan(@current_sprite_plan)
      rescue ex
        @generated_cmd = "# Unable to generate command: #{ex.message}"
      end

      # Enqueues the currently selected media file with the active preset into the batch job queue.
      def enqueue_selected_file : BatchJob?
        file = selected_file
        unless file
          @status_message = "No media file selected to enqueue!"
          return nil
        end

        preset_title = active_preset_title
        job = @batch_queue.add_preset(file, preset_title)
        @selected_job_idx = @batch_queue.jobs.size - 1
        @telemetry.attach_sprite_plan(job.atlas_plan) if job.atlas_plan
        @telemetry.active_job_label = job.display_label
        @status_message = "Queued '#{file}' [#{preset_title}] (#{@batch_queue.total_count} in queue)."
        @rich_log.write("[Queue] Added #{job.display_label}")
        job
      rescue ex
        @status_message = "Queue error: #{ex.message}"
        @rich_log.write("[Queue Error] #{ex.message}")
        nil
      end

      # Enqueues all discovered media files in the directory with the active preset.
      def enqueue_all_files : Int32
        return 0 if @media_files.empty?
        preset_title = active_preset_title
        added = 0
        @media_files.each do |file|
          begin
            job = @batch_queue.add_preset(file, preset_title)
            @telemetry.attach_sprite_plan(job.atlas_plan) if job.atlas_plan
            added += 1
          rescue
          end
        end
        @selected_job_idx = Math.max(0, @batch_queue.jobs.size - 1)
        @status_message = "Queued #{added} file(s) with preset '#{preset_title}'."
        @rich_log.write("[Queue] Batch-enqueued #{added} file(s) [#{preset_title}].")
        added
      end

      # Removes the currently selected job from the batch queue if not running.
      def remove_selected_job : BatchJob?
        return nil if @batch_queue.jobs.empty?
        removed = @batch_queue.remove_at(@selected_job_idx)
        if removed
          @selected_job_idx = (@selected_job_idx.clamp(0, Math.max(0, @batch_queue.jobs.size - 1)))
          @status_message = "Removed '#{File.basename(removed.input_path)}' from queue."
          @rich_log.write("[Queue] Removed #{removed.display_label}")
        end
        removed
      end

      # Records a live FFmpeg progress sample into both App state and the TelemetryEngine sparklines.
      def record_progress(prog : Runner::Progress) : Nil
        @latest_progress = prog
        @telemetry.record(prog)
      end

      def adjust_main_split(delta : Float64) : Float64
        @main_split_ratio = (@main_split_ratio + delta).clamp(0.22, 0.55)
      end

      def adjust_telemetry_split(delta : Float64) : Float64
        @telemetry_dashboard.adjust_ratio(delta)
      end

      def start_conversion
        file = selected_file
        unless file
          if @batch_queue.pending_count > 0
            start_batch_queue
          else
            @status_message = "No media file selected!"
          end
          return
        end

        return if @running_job

        job = enqueue_selected_file
        return unless job

        start_batch_queue
      end

      def start_batch_queue
        return if @running_job
        if @batch_queue.pending_count == 0
          @status_message = "No pending jobs in queue!"
          return
        end

        @running_job = true
        @job_completed = false
        @status_message = "Running batch queue (#{@batch_queue.pending_count} pending)..."
        @rich_log.write("[Batch] Starting #{@batch_queue.pending_count} queued job(s)...")

        spawn do
          @batch_queue.jobs.each_with_index do |job, idx|
            next if job.status.completed?
            @selected_job_idx = idx
            job.status = BatchJob::Status::Running
            @telemetry.active_job_label = job.display_label
            @telemetry.attach_sprite_plan(job.atlas_plan)
            @status_message = "Processing #{File.basename(job.input_path)} [#{job.preset_name}]..."
            @rich_log.write("[Start] #{job.display_label}")
            @rich_log.write("[Cmd] #{job.command.to_cmd_string}")

            begin
              runner = job.command.run_async
              @current_runner = runner

              runner.on_progress do |prog|
                job.progress = prog
                record_progress(prog)
              end

              runner.on_log do |line|
                @rich_log.write(line)
              end

              status = runner.wait
              if status.success?
                if (cfg = job.sprite_config) && (plan = job.atlas_plan)
                  SpriteSheet::DSL::SpriteSheetBuilder.new(cfg).write_sidecars!(plan)
                end
                done_prog = Runner::Progress.new(
                  frame: @latest_progress.frame,
                  fps: @latest_progress.fps,
                  q: @latest_progress.q,
                  size_bytes: @latest_progress.size_bytes,
                  current_time: @latest_progress.current_time,
                  total_duration: @latest_progress.total_duration,
                  percent: 100.0,
                  bitrate_kbps: @latest_progress.bitrate_kbps,
                  speed: @latest_progress.speed,
                  eta: Time::Span.zero
                )
                job.progress = done_prog
                record_progress(done_prog)
                job.status = BatchJob::Status::Completed
                @telemetry.completed_jobs += 1
                @rich_log.write("[Success] Completed #{job.output_path}")
              else
                job.status = BatchJob::Status::Failed
                job.error_message = "Exit code #{status.exit_code}"
                @telemetry.failed_jobs += 1
                @rich_log.write("[Error] Failed #{job.output_path} (exit #{status.exit_code})")
              end
            rescue ex
              job.status = BatchJob::Status::Failed
              job.error_message = ex.message
              @telemetry.failed_jobs += 1
              @rich_log.write("[Exception] #{ex.message}")
            end
          end

          @running_job = false
          @job_completed = (@batch_queue.failed_count == 0 && @batch_queue.completed_count > 0)
          if @batch_queue.failed_count == 0
            @status_message = "Batch completed (#{@batch_queue.completed_count}/#{@batch_queue.total_count} succeeded)!"
          else
            @status_message = "Batch finished with #{@batch_queue.failed_count} failure(s)."
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
                           when ActivePane::Presets then ActivePane::Queue
                           when ActivePane::Queue   then ActivePane::Logs
                           when ActivePane::Logs    then ActivePane::Files
                           else                          ActivePane::Files
                           end
            {self, Opal::TEA::Cmd.redraw}
          when "shift+tab", "backtab"
            @active_pane = case @active_pane
                           when ActivePane::Files   then ActivePane::Logs
                           when ActivePane::Presets then ActivePane::Files
                           when ActivePane::Queue   then ActivePane::Presets
                           when ActivePane::Logs    then ActivePane::Queue
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
            when ActivePane::Queue
              if @selected_job_idx > 0
                @selected_job_idx -= 1
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
            when ActivePane::Queue
              if @selected_job_idx < @batch_queue.jobs.size - 1
                @selected_job_idx += 1
              end
            when ActivePane::Logs
              @rich_log.scroll_offset += 2
            end
            {self, Opal::TEA::Cmd.redraw}
          when "a"
            enqueue_selected_file
            {self, Opal::TEA::Cmd.redraw}
          when "A"
            enqueue_all_files
            {self, Opal::TEA::Cmd.redraw}
          when "x", "X", "delete", "backspace"
            remove_selected_job
            {self, Opal::TEA::Cmd.redraw}
          when "b", "B"
            start_batch_queue
            {self, Opal::TEA::Cmd.redraw}
          when "["
            adjust_main_split(-0.04)
            {self, Opal::TEA::Cmd.redraw}
          when "]"
            adjust_main_split(0.04)
            {self, Opal::TEA::Cmd.redraw}
          when "{"
            adjust_telemetry_split(-0.05)
            {self, Opal::TEA::Cmd.redraw}
          when "}"
            adjust_telemetry_split(0.05)
            {self, Opal::TEA::Cmd.redraw}
          when "enter", " "
            if @active_pane.queue? && @batch_queue.pending_count > 0
              start_batch_queue
            else
              start_conversion
            end
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

      # --- Split-Pane Declarative Layout & Rendering ---

      # Builds the complete hierarchical `Opal.split_pane` workspace layout tree.
      def build_workspace_split(cols : Int32, main_h : Int32) : Opal::UI::SplitView
        theme = Opal::Theme.current

        # Left column: Vertical split between Media Files (top) and Conversion Presets (bottom)
        left_column = Opal.split_pane(
          direction: :vertical,
          ratio: @left_split_ratio,
          min_first_size: 5,
          show_separator: false,
          focused_pane: @active_pane.presets? ? :second : :first
        ) do |left_sp|
          left_sp.top(build_files_pane(cols, main_h))
          left_sp.bottom(build_presets_pane(cols, main_h))
        end

        # Sync telemetry dashboard state
        @telemetry_dashboard.selected_job_idx = @selected_job_idx
        @telemetry_dashboard.queue_focused = @active_pane.queue?
        @telemetry_dashboard.telemetry_focused = false

        # Right bottom: Vertical split between Telemetry/Queue Dashboard and Job Monitor/RichLog
        right_bottom = Opal.split_pane(
          direction: :vertical,
          ratio: @telemetry_split_ratio,
          min_first_size: 6,
          show_separator: false,
          focused_pane: @active_pane.logs? ? :second : :first
        ) do |rb_sp|
          rb_sp.top(@telemetry_dashboard)
          rb_sp.bottom(build_monitor_pane(cols, main_h))
        end

        # Right column: Vertical split between Inspector (top) and Telemetry+Monitor (bottom)
        right_column = Opal.split_pane(
          direction: :vertical,
          ratio: @right_top_ratio,
          min_first_size: 7,
          max_first_size: 10,
          show_separator: false,
          focused_pane: (@active_pane.queue? || @active_pane.logs?) ? :second : :first
        ) do |right_sp|
          right_sp.top(build_inspector_pane(cols, main_h))
          right_sp.bottom(right_bottom)
        end

        # Root workspace: Horizontal split between Left Navigation and Right Studio Telemetry
        Opal.split_pane(
          direction: :horizontal,
          ratio: @main_split_ratio,
          min_first_size: 26,
          max_first_size: 52,
          separator: '│',
          separator_fg: theme.border,
          focused_pane: (@active_pane.files? || @active_pane.presets?) ? :first : :second,
          show_separator: true
        ) do |root_sp|
          root_sp.left(left_column)
          root_sp.right(right_column)
        end
      end

      def render(buffer : Opal::UI::Buffer) : Nil
        cols = buffer.width
        rows = buffer.height
        return if cols < 40 || rows < 12

        buffer.fill(0, 0, cols, rows, ' ')
        @header.render(buffer, 0, 0, cols, 1)
        @footer.render(buffer, 0, rows - 1, cols, 1)

        main_y = 1
        main_h = Math.max(0, rows - 2)
        return if main_h <= 0

        workspace = build_workspace_split(cols, main_h)
        workspace.render(buffer, 0, main_y, cols, main_h)
      end

      private def build_files_pane(cols : Int32, main_h : Int32) : Opal::UI::Element
        theme = Opal::Theme.current
        files_border_fg = @active_pane.files? ? theme.primary : theme.border

        canvas = Opal::UI::CanvasBlock.new(cols, main_h) do |buf, cx, cy, cw, ch|
          if @media_files.empty?
            buf.put_string(cx + 1, cy + 1, "(No media files found in .)", fg: theme.text_muted, max_width: Math.max(0, cw - 1))
            if ch >= 3
              buf.put_string(cx + 1, cy + 2, "Press 'R' after adding video/audio", fg: theme.text_muted, max_width: Math.max(0, cw - 1))
            end
          else
            max_visible = Math.max(1, ch)
            @media_files.each_with_index do |filename, idx|
              break if idx >= max_visible
              is_sel = idx == @selected_file_idx
              prefix = is_sel ? "▶ " : "  "
              display_str = "#{prefix}#{filename}"
              if display_str.size > cw - 2 && cw > 5
                display_str = display_str[0...(cw - 5)] + "..."
              end
              fg_col = is_sel ? theme.accent : theme.text
              buf.put_string(cx + 1, cy + idx, display_str, fg: fg_col, bold: is_sel, max_width: Math.max(0, cw - 1))
            end
          end
        end

        Opal::UI::Box.new(
          child: canvas,
          border: :rounded,
          title: "Media Files (#{@media_files.size})",
          border_fg: files_border_fg,
          title_fg: theme.primary
        )
      end

      private def build_presets_pane(cols : Int32, main_h : Int32) : Opal::UI::Element
        theme = Opal::Theme.current
        presets_border_fg = @active_pane.presets? ? theme.primary : theme.border

        canvas = Opal::UI::CanvasBlock.new(cols, main_h) do |buf, cx, cy, cw, ch|
          max_p_visible = Math.max(1, ch)
          @presets.each_with_index do |preset, idx|
            break if idx >= max_p_visible
            is_sel = idx == @selected_preset_idx
            prefix = is_sel ? "● " : "○ "
            display_str = "#{prefix}#{preset[0]}"
            if display_str.size > cw - 2 && cw > 5
              display_str = display_str[0...(cw - 5)] + "..."
            end
            fg_col = is_sel ? theme.success : theme.text_muted
            buf.put_string(cx + 1, cy + idx, display_str, fg: fg_col, bold: is_sel, max_width: Math.max(0, cw - 1))
          end
        end

        Opal::UI::Box.new(
          child: canvas,
          border: :rounded,
          title: "Conversion Presets",
          border_fg: presets_border_fg,
          title_fg: theme.accent
        )
      end

      private def build_inspector_pane(cols : Int32, main_h : Int32) : Opal::UI::Element
        theme = Opal::Theme.current

        canvas = Opal::UI::CanvasBlock.new(cols, main_h) do |buf, cx, cy, cw, ch|
          if probe = @current_probe
            buf.put_string(cx + 1, cy, "Format:   #{probe.format_name} (#{probe.human_size})", bold: true, max_width: Math.max(0, cw - 1))
            buf.put_string(cx + 1, cy + 1, "Duration: #{probe.duration_formatted}", max_width: Math.max(0, cw - 1)) if ch >= 2
            buf.put_string(cx + 1, cy + 2, probe.video_summary, fg: theme.primary, max_width: Math.max(0, cw - 1)) if ch >= 3
            buf.put_string(cx + 1, cy + 3, probe.audio_summary, fg: theme.accent, max_width: Math.max(0, cw - 1)) if ch >= 4
          elsif sp_plan = @current_sprite_plan
            sp_tel = Core::SpritePackingTelemetry.from_plan(sp_plan)
            buf.put_string(cx + 1, cy, "Sprite Sheet Plan: #{sp_tel.grid_summary} -> #{sp_tel.atlas_summary}", fg: theme.primary, bold: true, max_width: Math.max(0, cw - 1))
            buf.put_string(cx + 1, cy + 1, "VRAM Compression:  #{sp_tel.savings_summary}", fg: theme.success, max_width: Math.max(0, cw - 1)) if ch >= 2
          else
            buf.put_string(cx + 1, cy + 1, "Select a valid media file to inspect details.", fg: theme.text_muted, max_width: Math.max(0, cw - 1))
          end

          if ch >= 5 && (sp_plan = @current_sprite_plan) && @current_probe
            sp_tel = Core::SpritePackingTelemetry.from_plan(sp_plan)
            buf.put_string(cx + 1, cy + 4, "Atlas Plan: #{sp_tel.compact_badge}", fg: theme.success, bold: true, max_width: Math.max(0, cw - 1))
          end

          if ch >= 6 && !@generated_cmd.empty?
            cmd_label_y = cy + Math.min(ch - 2, 5)
            buf.put_string(cx + 1, cmd_label_y, "Generated Command (Press 'C' to copy):", fg: theme.warning, bold: true, max_width: Math.max(0, cw - 1))
            cmd_preview = @generated_cmd
            if cmd_preview.size > cw - 2 && cw > 5
              cmd_preview = cmd_preview[0...(cw - 5)] + "..."
            end
            buf.put_string(cx + 1, cmd_label_y + 1, cmd_preview, fg: theme.text_muted, max_width: Math.max(0, cw - 1))
          end
        end

        Opal::UI::Box.new(
          child: canvas,
          border: :rounded,
          title: "Inspector & Target",
          border_fg: theme.border,
          title_fg: theme.info
        )
      end

      private def build_monitor_pane(cols : Int32, main_h : Int32) : Opal::UI::Element
        theme = Opal::Theme.current
        mon_border_fg = @active_pane.logs? ? theme.primary : theme.border

        canvas = Opal::UI::CanvasBlock.new(cols, main_h) do |buf, cx, cy, cw, ch|
          prog = @latest_progress
          status_badge = if @running_job
                           "[RUNNING]"
                         elsif @job_completed
                           "[COMPLETED]"
                         else
                           "[IDLE]"
                         end
          badge_fg = @running_job ? theme.warning : (@job_completed ? theme.success : theme.text_muted)

          buf.put_string(cx + 1, cy, status_badge, fg: badge_fg, bold: true, max_width: Math.max(0, cw - 1))
          if cw > 13
            buf.put_string(cx + 12, cy, @status_message, fg: theme.text, max_width: Math.max(0, cw - 13))
          end

          if ch >= 2
            bar_str = prog.bar(Math.max(10, cw - 45))
            stats_str = "Speed: #{prog.speed_formatted} | FPS: #{prog.fps.round(1)} | ETA: #{prog.eta_formatted}"
            buf.put_string(cx + 1, cy + 1, "#{bar_str}  #{stats_str}", fg: theme.accent, bold: true, max_width: Math.max(0, cw - 1))
          end

          if ch >= 4
            buf.put_string(cx + 1, cy + 2, "─" * Math.max(0, cw - 2), fg: theme.border, max_width: Math.max(0, cw - 1))
            log_h = Math.max(1, ch - 3)
            @rich_log.render(buf, cx, cy + 3, cw, log_h)
          end
        end

        Opal::UI::Box.new(
          child: canvas,
          border: :rounded,
          title: "Job Monitor & Stream Log",
          border_fg: mon_border_fg,
          title_fg: theme.success
        )
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

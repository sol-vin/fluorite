require "opal"
require "../batch"
require "./core/telemetry_engine"
require "./split_pane_bridge"

module Fluorite
  module TUI
    # Declarative builder for configuring `TelemetryDashboard` instances.
    class TelemetryDashboardBuilder
      property telemetry : Core::TelemetryEngine = Core::TelemetryEngine.new
      property queue : BatchQueue = BatchQueue.new
      property direction : Opal::UI::SplitDirection = Opal::UI::SplitDirection::Horizontal
      property split_ratio : Float64 = 0.52
      property sparkline_split_ratio : Float64 = 0.5
      property selected_job_idx : Int32 = 0
      property queue_focused : Bool = false
      property telemetry_focused : Bool = false
      property show_separator : Bool = true

      def telemetry(@telemetry : Core::TelemetryEngine) : self
        self
      end

      def queue(@queue : BatchQueue) : self
        self
      end

      def direction(dir : Opal::UI::SplitDirection | Symbol | String) : self
        @direction = Opal::UI::SplitDirection.from(dir)
        self
      end

      def ratio(val : Float64) : self
        @split_ratio = val.clamp(0.15, 0.85)
        self
      end

      def sparkline_ratio(val : Float64) : self
        @sparkline_split_ratio = val.clamp(0.2, 0.8)
        self
      end

      def selected_job(idx : Int32) : self
        @selected_job_idx = Math.max(0, idx)
        self
      end

      def focus_queue(focused : Bool = true) : self
        @queue_focused = focused
        self
      end

      def focus_telemetry(focused : Bool = true) : self
        @telemetry_focused = focused
        self
      end

      def build : TelemetryDashboard
        TelemetryDashboard.new(
          telemetry: @telemetry,
          queue: @queue,
          direction: @direction,
          split_ratio: @split_ratio,
          sparkline_split_ratio: @sparkline_split_ratio,
          selected_job_idx: @selected_job_idx,
          queue_focused: @queue_focused,
          telemetry_focused: @telemetry_focused,
          show_separator: @show_separator
        )
      end
    end

    # Tier-2 Declarative Component: Real-time FFmpeg FPS & Bitrate Sparklines paired alongside
    # an interactive per-file Batch Transcoding & Sprite-Sheet Packing Job Queue using `Opal.split_pane`.
    class TelemetryDashboard < Opal::UI::Element
      property telemetry : Core::TelemetryEngine
      property queue : BatchQueue
      property direction : Opal::UI::SplitDirection
      property split_ratio : Float64
      property sparkline_split_ratio : Float64
      property selected_job_idx : Int32
      property? queue_focused : Bool
      property? telemetry_focused : Bool
      property? show_separator : Bool

      def initialize(
        @telemetry : Core::TelemetryEngine = Core::TelemetryEngine.new,
        @queue : BatchQueue = BatchQueue.new,
        direction : Opal::UI::SplitDirection | Symbol | String = Opal::UI::SplitDirection::Horizontal,
        split_ratio : Float64 = 0.52,
        sparkline_split_ratio : Float64 = 0.5,
        @selected_job_idx : Int32 = 0,
        @queue_focused : Bool = false,
        @telemetry_focused : Bool = false,
        @show_separator : Bool = true,
      )
        @direction = Opal::UI::SplitDirection.from(direction)
        @split_ratio = split_ratio.clamp(0.15, 0.85)
        @sparkline_split_ratio = sparkline_split_ratio.clamp(0.2, 0.8)
      end

      def self.build(&) : TelemetryDashboard
        builder = TelemetryDashboardBuilder.new
        with builder yield builder
        builder.build
      end

      def adjust_ratio(delta : Float64, min_ratio : Float64 = 0.2, max_ratio : Float64 = 0.8) : Float64
        @split_ratio = (@split_ratio + delta).clamp(min_ratio, max_ratio)
      end

      def preferred_size(available_w : Int32, available_h : Int32) : {Int32, Int32}
        {available_w, Math.min(Math.max(6, available_h), available_h)}
      end

      # Builds the `Opal::UI::SplitView` tree powered by `Opal.split_pane`.
      def to_split_view(width : Int32 = 80, height : Int32 = 10) : Opal::UI::SplitView
        theme = Opal::Theme.current
        focus_sym = @queue_focused ? :second : :first

        Opal.split_pane(
          direction: @direction,
          ratio: @split_ratio,
          separator_fg: theme.border,
          focused_pane: focus_sym,
          show_separator: @show_separator
        ) do |sp|
          sp.first(build_telemetry_pane(width, height))
          sp.second(build_queue_pane(width, height))
        end
      end

      def render(buffer : Opal::UI::Buffer, x : Int32, y : Int32, width : Int32, height : Int32) : Nil
        return if width <= 0 || height <= 0
        split_tree = to_split_view(width, height)
        split_tree.render(buffer, x, y, width, height)
      end

      private def build_telemetry_pane(total_w : Int32, total_h : Int32) : Opal::UI::Element
        theme = Opal::Theme.current
        border_col = @telemetry_focused ? theme.primary : theme.border

        inner_canvas = Opal::UI::CanvasBlock.new(total_w, total_h) do |buf, cx, cy, cw, ch|
          spark_points = Math.max(8, cw - 2)

          fps_spark = Opal::UI::Sparkline.new(
            data: @telemetry.fps_series.sparkline_values(spark_points),
            color: theme.success,
            title: @telemetry.fps_title,
            min: 0.0
          )

          bitrate_spark = Opal::UI::Sparkline.new(
            data: @telemetry.bitrate_series.sparkline_values(spark_points),
            color: theme.primary,
            title: @telemetry.bitrate_title,
            min: 0.0
          )

          if ch >= 5
            # Nested vertical Opal.split_pane giving full width to both FPS and Bitrate sparklines
            spark_split = Opal.split_pane(
              direction: :vertical,
              ratio: 0.5,
              show_separator: false
            ) do |sp|
              sp.top(fps_spark)
              sp.bottom(bitrate_spark)
            end
            spark_split.render(buf, cx, cy, cw, 4)

            buf.put_string(cx, cy + 4, @telemetry.speed_summary, fg: theme.accent, max_width: cw)
            if ch >= 6
              if sp_tel = @telemetry.sprite_telemetry
                buf.put_string(cx, cy + 5, "Atlas: #{sp_tel.compact_badge}", fg: theme.warning, bold: true, max_width: cw)
              else
                buf.put_string(cx, cy + 5, "Job: #{@telemetry.active_job_label}", fg: theme.text_muted, max_width: cw)
              end
            end
          else
            # Compact horizontal Opal.split_pane for tight heights
            spark_split = Opal.split_pane(
              direction: :horizontal,
              ratio: @sparkline_split_ratio,
              separator: '│',
              separator_fg: theme.border,
              show_separator: true
            ) do |sp|
              sp.left(fps_spark)
              sp.right(bitrate_spark)
            end
            spark_h = Math.min(2, ch)
            spark_split.render(buf, cx, cy, cw, spark_h)

            if ch >= 3
              buf.put_string(cx, cy + 2, @telemetry.speed_summary, fg: theme.accent, max_width: cw)
            end
            if ch >= 4
              if sp_tel = @telemetry.sprite_telemetry
                buf.put_string(cx, cy + 3, "Atlas: #{sp_tel.compact_badge}", fg: theme.warning, bold: true, max_width: cw)
              else
                buf.put_string(cx, cy + 3, "Job: #{@telemetry.active_job_label}", fg: theme.text_muted, max_width: cw)
              end
            end
          end
        end

        Opal::UI::Box.new(
          child: inner_canvas,
          border: :rounded,
          title: "Live FFmpeg Telemetry (FPS / Bitrate)",
          border_fg: border_col,
          title_fg: theme.info
        )
      end

      private def build_queue_pane(total_w : Int32, total_h : Int32) : Opal::UI::Element
        theme = Opal::Theme.current
        border_col = @queue_focused ? theme.primary : theme.border
        q_pct = sprintf("%.0f%%", @queue.overall_percent)
        box_title = "Job Queue (#{@queue.completed_count}/#{@queue.total_count} | #{q_pct})"

        inner_canvas = Opal::UI::CanvasBlock.new(total_w, total_h) do |buf, cx, cy, cw, ch|
          if @queue.jobs.empty?
            buf.put_string(cx + 1, cy, "(Queue empty - 'A' add file, 'B' run batch)", fg: theme.text_muted, max_width: Math.max(0, cw - 1))
            if ch >= 2
              buf.put_string(cx + 1, cy + 1, "Supports batch video & CLUT sprite packing", fg: theme.text_muted, max_width: Math.max(0, cw - 1))
            end
          else
            max_rows = Math.max(1, ch)
            start_idx = 0
            if @selected_job_idx >= max_rows
              start_idx = @selected_job_idx - max_rows + 1
            end

            max_rows.times do |row_i|
              job_idx = start_idx + row_i
              break if job_idx >= @queue.jobs.size
              job = @queue.jobs[job_idx]
              is_sel = (job_idx == @selected_job_idx)

              badge_fg = case job.status
                         when BatchJob::Status::Running   then theme.warning
                         when BatchJob::Status::Completed then theme.success
                         when BatchJob::Status::Failed    then theme.danger
                         else                                  theme.text_muted
                         end

              prefix = is_sel ? "▶" : " "
              pct_str = sprintf("%5.1f%%", job.effective_percent)
              badge = job.status_badge

              buf.put_string(cx, cy + row_i, prefix, fg: is_sel ? theme.accent : theme.text_muted, bold: is_sel, max_width: 1)
              buf.put_string(cx + 2, cy + row_i, badge, fg: badge_fg, bold: true, max_width: 6)

              pct_x = Math.max(cx + 9, cx + cw - 6)
              avail_label_w = Math.max(0, pct_x - (cx + 9) - 1)
              if avail_label_w > 0
                label = job.display_label
                if label.size > avail_label_w && avail_label_w > 3
                  label = label[0...(avail_label_w - 3)] + "..."
                end
                row_fg = is_sel ? theme.accent : theme.text
                buf.put_string(cx + 9, cy + row_i, label, fg: row_fg, bold: is_sel, max_width: avail_label_w)
              end

              if cw >= 16
                buf.put_string(pct_x, cy + row_i, pct_str, fg: badge_fg, bold: is_sel, max_width: 6)
              end
            end
          end
        end

        Opal::UI::Box.new(
          child: inner_canvas,
          border: :rounded,
          title: box_title,
          border_fg: border_col,
          title_fg: theme.accent
        )
      end
    end

    def self.telemetry_dashboard(
      telemetry : Core::TelemetryEngine = Core::TelemetryEngine.new,
      queue : BatchQueue = BatchQueue.new,
      direction : Opal::UI::SplitDirection | Symbol | String = Opal::UI::SplitDirection::Horizontal,
      split_ratio : Float64 = 0.52,
      selected_job_idx : Int32 = 0,
      queue_focused : Bool = false,
    ) : TelemetryDashboard
      TelemetryDashboard.new(
        telemetry: telemetry,
        queue: queue,
        direction: direction,
        split_ratio: split_ratio,
        selected_job_idx: selected_job_idx,
        queue_focused: queue_focused
      )
    end
  end
end

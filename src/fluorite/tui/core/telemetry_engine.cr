require "../../runner/progress"
require "../../sprite_sheet/core/pipeline"

module Fluorite
  module TUI
    module Core
      # Bounded rolling telemetry metric series for zero-churn sparkline rendering and statistics.
      class MetricSeries
        getter capacity : Int32
        getter samples : Array(Float64)
        getter latest : Float64 = 0.0
        getter min_observed : Float64 = 0.0
        getter max_observed : Float64 = 0.0
        getter total_count : Int64 = 0_i64

        def initialize(capacity : Int32 = 60)
          @capacity = Math.max(4, capacity)
          @samples = Array(Float64).new(@capacity)
        end

        def push(value : Float64) : self
          clean = (value.nan? || value.infinite? || value < 0.0) ? 0.0 : value
          if @samples.size >= @capacity
            @samples.shift
          end
          @samples << clean
          @latest = clean

          if @total_count == 0
            @min_observed = clean
            @max_observed = clean
          else
            @min_observed = clean if clean < @min_observed
            @max_observed = clean if clean > @max_observed
          end
          @total_count += 1
          self
        end

        def empty? : Bool
          @samples.empty?
        end

        def size : Int32
          @samples.size
        end

        def average : Float64
          return 0.0 if @samples.empty?
          sum = 0.0
          @samples.each { |v| sum += v }
          sum / @samples.size.to_f64
        end

        def peak : Float64
          @max_observed
        end

        def minimum : Float64
          @total_count > 0 ? @min_observed : 0.0
        end

        # Returns sample array suitable for `Opal::UI::Sparkline`, optionally left-padded to `min_points`.
        def sparkline_values(min_points : Int32 = 16) : Array(Float64)
          target_min = Math.max(1, min_points)
          return Array(Float64).new(target_min, 0.0) if @samples.empty?
          if @samples.size < target_min
            pad = Array(Float64).new(target_min - @samples.size, 0.0)
            pad.concat(@samples)
            pad
          else
            @samples.dup
          end
        end

        def clear! : self
          @samples.clear
          @latest = 0.0
          @min_observed = 0.0
          @max_observed = 0.0
          @total_count = 0_i64
          self
        end
      end

      # Value struct capturing sprite-sheet atlas layout and VRAM compression telemetry.
      struct SpritePackingTelemetry
        getter format : String
        getter columns : Int32
        getter rows : Int32
        getter frame_count : Int32
        getter frame_width : Int32
        getter frame_height : Int32
        getter atlas_width : Int32
        getter atlas_height : Int32
        getter power_of_two : Bool
        getter vram_bytes : Int64
        getter raw_rgba_bytes : Int64
        getter vram_savings_percent : Float64
        getter compression_ratio : Float64
        getter dither : String
        getter fps : Float64

        def initialize(
          @format : String,
          @columns : Int32,
          @rows : Int32,
          @frame_count : Int32,
          @frame_width : Int32,
          @frame_height : Int32,
          @atlas_width : Int32,
          @atlas_height : Int32,
          @power_of_two : Bool,
          @vram_bytes : Int64,
          @raw_rgba_bytes : Int64,
          @vram_savings_percent : Float64,
          @compression_ratio : Float64,
          @dither : String = "sierra2_4a",
          @fps : Float64 = 12.0,
        )
        end

        def self.from_plan(plan : SpriteSheet::Core::AtlasPlan) : self
          new(
            format: plan.format.upcase,
            columns: plan.columns,
            rows: plan.rows,
            frame_count: plan.frame_count,
            frame_width: plan.frame_width,
            frame_height: plan.frame_height,
            atlas_width: plan.atlas_width,
            atlas_height: plan.atlas_height,
            power_of_two: plan.power_of_two,
            vram_bytes: plan.metrics.total_vram_bytes,
            raw_rgba_bytes: plan.metrics.raw_rgba_bytes,
            vram_savings_percent: plan.metrics.vram_savings_percent,
            compression_ratio: plan.metrics.compression_ratio,
            dither: plan.dither,
            fps: plan.fps
          )
        end

        def human_vram : String
          format_bytes(@vram_bytes)
        end

        def human_raw_rgba : String
          format_bytes(@raw_rgba_bytes)
        end

        def grid_summary : String
          "#{@columns}x#{@rows} (#{@frame_count}f @ #{@frame_width}x#{@frame_height}px)"
        end

        def atlas_summary : String
          "#{@atlas_width}x#{@atlas_height}px#{@power_of_two ? " [POT]" : ""}"
        end

        def savings_summary : String
          "#{human_vram} vs #{human_raw_rgba} (-#{@vram_savings_percent}% VRAM, #{@compression_ratio}x)"
        end

        def compact_badge : String
          "[#{@format} #{@columns}x#{@rows} -> #{@atlas_width}x#{@atlas_height} | -#{@vram_savings_percent}% VRAM]"
        end

        private def format_bytes(bytes_val : Int64) : String
          bytes = bytes_val.to_f64
          units = ["B", "KB", "MB", "GB"]
          idx = 0
          while bytes >= 1024.0 && idx < units.size - 1
            bytes /= 1024.0
            idx += 1
          end
          "#{bytes.round(1)} #{units[idx]}"
        end
      end

      # Tier-1 Core Engine: Real-time FFmpeg FPS/bitrate/speed telemetry aggregator and sprite packing state.
      class TelemetryEngine
        getter fps_series : MetricSeries
        getter bitrate_series : MetricSeries
        getter speed_series : MetricSeries
        property latest_progress : Runner::Progress
        property sprite_telemetry : SpritePackingTelemetry?
        property active_job_label : String
        property completed_jobs : Int32 = 0
        property failed_jobs : Int32 = 0

        def initialize(capacity : Int32 = 60)
          @fps_series = MetricSeries.new(capacity)
          @bitrate_series = MetricSeries.new(capacity)
          @speed_series = MetricSeries.new(capacity)
          @latest_progress = Runner::Progress.new
          @sprite_telemetry = nil
          @active_job_label = "Idle"
        end

        def record(progress : Runner::Progress) : self
          @latest_progress = progress
          @fps_series.push(progress.fps)
          @bitrate_series.push(progress.bitrate_kbps)
          @speed_series.push(progress.speed)
          self
        end

        def attach_sprite_plan(plan : SpriteSheet::Core::AtlasPlan?) : self
          @sprite_telemetry = plan ? SpritePackingTelemetry.from_plan(plan) : nil
          self
        end

        def fps_title : String
          "FPS: #{sprintf("%.1f", @fps_series.latest)} (avg #{sprintf("%.1f", @fps_series.average)} | pk #{sprintf("%.1f", @fps_series.peak)})"
        end

        def bitrate_title : String
          "Bitrate: #{sprintf("%.1f", @bitrate_series.latest)} kbps (avg #{sprintf("%.1f", @bitrate_series.average)} | pk #{sprintf("%.1f", @bitrate_series.peak)})"
        end

        def speed_summary : String
          "Speed: #{@latest_progress.speed_formatted} | Frame: #{@latest_progress.frame} | Size: #{@latest_progress.human_size} | ETA: #{@latest_progress.eta_formatted}"
        end

        def reset_series! : self
          @fps_series.clear!
          @bitrate_series.clear!
          @speed_series.clear!
          @latest_progress = Runner::Progress.new
          self
        end

        def reset! : self
          reset_series!
          @sprite_telemetry = nil
          @active_job_label = "Idle"
          @completed_jobs = 0
          @failed_jobs = 0
          self
        end
      end
    end
  end
end

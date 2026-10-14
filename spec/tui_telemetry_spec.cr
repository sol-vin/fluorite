require "./spec_helper"

describe Fluorite::TUI::Core::TelemetryEngine do
  it "tracks rolling FPS, bitrate, and speed series with bounded capacity" do
    engine = Fluorite::TUI::Core::TelemetryEngine.new(capacity: 5)

    [30.0, 45.0, 60.0, 75.0, 90.0, 120.0].each_with_index do |fps, idx|
      prog = Fluorite::Runner::Progress.new(
        frame: (idx + 1).to_i64 * 100_i64,
        fps: fps,
        bitrate_kbps: 1500.0 + idx * 250.0,
        speed: 1.0 + idx * 0.25,
        size_bytes: 1_048_576_i64 * (idx + 1),
        percent: (idx + 1) * 15.0
      )
      engine.record(prog)
    end

    # Rolling capacity is 5, so oldest sample (30.0) was evicted
    engine.fps_series.size.should eq(5)
    engine.fps_series.latest.should eq(120.0)
    engine.fps_series.peak.should eq(120.0)
    engine.fps_series.minimum.should eq(30.0)
    engine.fps_series.average.should be_close((45.0 + 60.0 + 75.0 + 90.0 + 120.0) / 5.0, 0.01)

    engine.bitrate_series.latest.should eq(2750.0)
    engine.bitrate_series.peak.should eq(2750.0)

    engine.fps_title.should contain("FPS: 120.0")
    engine.bitrate_title.should contain("Bitrate: 2750.0 kbps")
    engine.speed_summary.should contain("Speed: 2.25x")
  end

  it "computes sprite-sheet packing telemetry from AtlasPlan" do
    plan = Fluorite::Presets::SpriteSheet.build_plan(
      "knight_attack.mp4",
      "knight_sheet.png",
      frame_width: 64,
      frame_height: 64,
      frames: 16,
      format: :clut8,
      power_of_two: true
    )

    engine = Fluorite::TUI::Core::TelemetryEngine.new
    engine.attach_sprite_plan(plan)

    sp_tel = engine.sprite_telemetry.should_not be_nil
    sp_tel.format.should eq("CLUT8")
    sp_tel.columns.should eq(4)
    sp_tel.rows.should eq(4)
    sp_tel.atlas_width.should eq(256)
    sp_tel.atlas_height.should eq(256)
    sp_tel.power_of_two.should be_true
    sp_tel.vram_savings_percent.should be > 70.0
    sp_tel.compact_badge.should contain("CLUT8 4x4 -> 256x256")
  end
end

describe Fluorite::TUI::TelemetryDashboard do
  it "renders live FFmpeg FPS/bitrate sparklines alongside per-file job queues via Opal.split_pane" do
    telemetry = Fluorite::TUI::Core::TelemetryEngine.new
    [24.0, 48.0, 60.0, 72.0, 64.0].each_with_index do |fps, i|
      telemetry.record(
        Fluorite::Runner::Progress.new(
          frame: (i + 1).to_i64 * 60_i64,
          fps: fps,
          bitrate_kbps: 1800.0 + i * 200.0,
          speed: 1.85,
          percent: (i + 1) * 20.0
        )
      )
    end

    queue = Fluorite::BatchQueue.new
    job1 = queue.add_preset("intro.mp4", "Web MP4 (FastStart)")
    job1.status = Fluorite::BatchJob::Status::Completed
    job2 = queue.add_preset("player_run.mp4", "Sprite Sheet (CLUT8)")
    job2.status = Fluorite::BatchJob::Status::Running
    job2.progress = Fluorite::Runner::Progress.new(percent: 65.0)
    telemetry.attach_sprite_plan(job2.atlas_plan)

    dashboard = Fluorite::TUI::TelemetryDashboard.build do
      telemetry(telemetry)
      queue(queue)
      direction(:horizontal)
      ratio(0.52)
      selected_job(1)
      focus_queue(true)
    end

    split_view = dashboard.to_split_view(120, 10)
    split_view.should be_a(Opal::UI::SplitView)

    buf = Opal::UI::Buffer.new(120, 10)
    dashboard.render(buf, 0, 0, 120, 10)
    rendered = buf.to_s

    rendered.should contain("Live FFmpeg Telemetry")
    rendered.should contain("FPS: 64.0")
    rendered.should contain("Bitrate: 2600.0 kbps")
    rendered.should contain("CLUT8 4x4 -> 256x256")
    rendered.should contain("Job Queue (1/2")
    rendered.should contain("[DONE]")
    rendered.should contain("[RUN ]")
    rendered.should contain("65.0%")
  end
end

describe Fluorite::TUI::App do
  it "integrates Opal.split_pane, batch/sprite queueing, pane navigation, and split resizing" do
    app = Fluorite::TUI::App.new
    app.media_files << "sample_a.mp4"
    app.media_files << "sample_b.mp4"
    app.selected_file_idx = 0

    # Select Sprite Sheet (CLUT8) preset (index 4)
    app.selected_preset_idx = 4
    app.update_command_preview
    app.current_sprite_plan.should_not be_nil
    app.telemetry.sprite_telemetry.should_not be_nil

    # Enqueue current file with 'a' key
    app.update(Opal::TEA::KeyMsg.new("a"))
    app.batch_queue.total_count.should eq(1)
    app.batch_queue.jobs.first.sprite_sheet?.should be_true

    # Enqueue all files with 'A' key
    app.update(Opal::TEA::KeyMsg.new("A"))
    app.batch_queue.total_count.should eq(3)

    # Cycle focus across Files -> Presets -> Queue -> Logs -> Files
    app.active_pane.should eq(Fluorite::TUI::App::ActivePane::Files)
    app.update(Opal::TEA::KeyMsg.new("tab"))
    app.active_pane.should eq(Fluorite::TUI::App::ActivePane::Presets)
    app.update(Opal::TEA::KeyMsg.new("tab"))
    app.active_pane.should eq(Fluorite::TUI::App::ActivePane::Queue)

    # Navigate and remove a job in Queue pane
    app.selected_job_idx.should eq(2)
    app.update(Opal::TEA::KeyMsg.new("up"))
    app.selected_job_idx.should eq(1)
    app.update(Opal::TEA::KeyMsg.new("x"))
    app.batch_queue.total_count.should eq(2)

    # Resize main horizontal split and telemetry split
    initial_main_ratio = app.main_split_ratio
    app.update(Opal::TEA::KeyMsg.new("]"))
    app.main_split_ratio.should be > initial_main_ratio

    initial_tel_ratio = app.telemetry_dashboard.split_ratio
    app.update(Opal::TEA::KeyMsg.new("}"))
    app.telemetry_dashboard.split_ratio.should be > initial_tel_ratio

    # Record live FFmpeg telemetry progress and render full TUI buffer
    app.record_progress(
      Fluorite::Runner::Progress.new(
        frame: 420_i64,
        fps: 88.5,
        bitrate_kbps: 3120.4,
        speed: 2.45,
        percent: 42.0
      )
    )

    buf = Opal::UI::Buffer.new(120, 34)
    app.render(buf)
    screen_text = buf.to_s

    screen_text.should contain("FLUORITE FFMPEG STUDIO")
    screen_text.should contain("Media Files (2)")
    screen_text.should contain("Conversion Presets")
    screen_text.should contain("Inspector & Target")
    screen_text.should contain("Live FFmpeg Telemetry")
    screen_text.should contain("FPS: 88.5")
    screen_text.should contain("Bitrate: 3120.4 kbps")
    screen_text.should contain("Job Queue (0/2")
    screen_text.should contain("Job Monitor & Stream Log")
  end
end

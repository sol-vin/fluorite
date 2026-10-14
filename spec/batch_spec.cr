require "./spec_helper"

describe Fluorite::BatchQueue do
  it "manages job queue correctly" do
    queue = Fluorite::BatchQueue.new
    queue.add("a.mp4", "a_out.mp4") do
      video { codec(:h264) }
      audio { codec(:aac) }
    end

    queue.total_count.should eq(1)
    queue.pending_count.should eq(1)
    queue.completed_count.should eq(0)
    queue.failed_count.should eq(0)
    queue.jobs.first.status.should eq(Fluorite::BatchJob::Status::Pending)
    queue.jobs.first.status_badge.should eq("[PEND]")
  end

  it "enqueues sprite-sheet packing jobs and studio presets with atlas plans" do
    queue = Fluorite::BatchQueue.new

    sprite_job = queue.add_spritesheet("hero_walk.mp4", "hero_sheet.png", preset_name: "Sprite Sheet (CLUT8)") do
      frame_size(64, 64)
      frames(16)
      fps(12)
      clut8!
      power_of_two!
    end

    sprite_job.sprite_sheet?.should be_true
    sprite_job.job_kind.should eq(Fluorite::BatchJob::JobKind::SpriteSheet)
    plan = sprite_job.atlas_plan.should_not be_nil
    plan.columns.should eq(4)
    plan.rows.should eq(4)
    plan.atlas_width.should eq(256)
    plan.atlas_height.should eq(256)
    sprite_job.display_label.should contain("4x4 CLUT8")

    web_job = queue.add_preset("clip.mp4", "Web MP4 (FastStart)")
    web_job.output_path.should eq("clip_web.mp4")
    web_job.job_kind.should eq(Fluorite::BatchJob::JobKind::Transcode)

    clut4_job = queue.add_preset("boss.mp4", "Sprite Sheet (CLUT4)")
    clut4_job.sprite_sheet?.should be_true
    clut4_job.atlas_plan.not_nil!.format.should eq("clut4")

    queue.total_count.should eq(3)
    queue.overall_percent.should eq(0.0)

    web_job.progress = Fluorite::Runner::Progress.new(percent: 50.0)
    web_job.status = Fluorite::BatchJob::Status::Running
    sprite_job.status = Fluorite::BatchJob::Status::Completed

    # (100.0 + 50.0 + 0.0) / 3 = 50.0
    queue.overall_percent.should be_close(50.0, 0.01)

    removed = queue.remove_at(2)
    removed.should eq(clut4_job)
    queue.total_count.should eq(2)

    cleared = queue.clear_completed!
    cleared.should eq(1)
    queue.total_count.should eq(1)
  end
end

require "./spec_helper"

describe Fluorite::Config do
  it "detects installed ffmpeg and ffprobe binaries" do
    cfg = Fluorite.config
    cfg.ffmpeg_available?.should be_true
    cfg.ffprobe_available?.should be_true
    cfg.ffmpeg_path.should_not be_empty
    cfg.ffprobe_path.should_not be_empty
  end

  it "detects available encoders" do
    encoders = Fluorite.config.available_encoders
    encoders.should_not be_empty
    encoders.should contain("libx264")
  end

  it "detects hardware acceleration methods" do
    hwaccels = Fluorite.config.available_hwaccels
    hwaccels.should_not be_nil
  end

  it "recommends best encoder for format" do
    encoder = Fluorite.config.best_encoder_for(:h264)
    encoder.should_not be_empty
  end
end

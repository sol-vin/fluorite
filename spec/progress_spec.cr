require "./spec_helper"

describe Fluorite::Runner::Progress do
  it "formats time spans and percentage correctly" do
    prog = Fluorite::Runner::Progress.new(
      frame: 1500_i64,
      fps: 60.5,
      size_bytes: 15_728_640_i64,
      current_time: Time::Span.new(hours: 0, minutes: 1, seconds: 30),
      total_duration: Time::Span.new(hours: 0, minutes: 3, seconds: 0),
      percent: 50.0,
      bitrate_kbps: 1398.2,
      speed: 2.1,
      eta: Time::Span.new(seconds: 43)
    )

    prog.time_formatted.should eq("00:01:30")
    prog.total_formatted.should eq("00:03:00")
    prog.eta_formatted.should eq("00:00:43")
    prog.speed_formatted.should eq("2.10x")
    prog.human_size.should eq("15.0 MB")
    prog.bar(20).should contain("50.0%")
  end
end

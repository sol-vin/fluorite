require "./spec_helper"

describe Fluorite::DSL do
  it "builds command with block syntax" do
    cmd = Fluorite.build do
      overwrite!
      threads 4
      hwaccel :cuda

      input("raw.mov") do
        seek 10.seconds
        duration 30.seconds
      end

      video do
        codec :h264
        crf 20
        preset :slow
        scale 1280, 720
        fps 60
      end

      audio do
        codec :aac
        bitrate "192k"
      end

      output("final.mp4") do
        faststart!
      end
    end

    args = cmd.to_args
    args.should contain("-y")
    args.should contain("-threads")
    args.should contain("4")
    args.should contain("-hwaccel")
    args.should contain("cuda")
    args.should contain("-ss")
    args.should contain("00:00:10.000")
    args.should contain("-t")
    args.should contain("00:00:30.000")
    args.should contain("-i")
    args.should contain("raw.mov")
    args.should contain("-c:v")
    args.should contain("h264")
    args.should contain("-crf")
    args.should contain("20")
    args.should contain("-c:a")
    args.should contain("aac")
    args.should contain("-b:a")
    args.should contain("192k")
    args.should contain("-movflags")
    args.should contain("+faststart")
    args.should contain("final.mp4")
  end

  it "builds command with chainable syntax" do
    builder = Fluorite.input("source.mkv")
      .video_codec(:h264)
      .crf(22)
      .scale(1920, 1080)
      .audio_codec(:aac)
      .audio_bitrate("256k")
      .output("web.mp4")

    args = builder.command.to_args
    args.should contain("-i")
    args.should contain("source.mkv")
    args.should contain("-c:v")
    args.should contain("h264")
    args.should contain("-crf")
    args.should contain("22")
    args.should contain("-c:a")
    args.should contain("aac")
    args.should contain("-b:a")
    args.should contain("256k")
    args.should contain("web.mp4")
  end
end

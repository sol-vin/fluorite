require "./spec_helper"

describe Fluorite::Presets do
  it "builds Web preset command correctly" do
    cmd = Fluorite::Presets::Web.build_command("source.mov", "dest.mp4", crf: 20)
    args = cmd.to_args
    args.should contain("-c:v")
    args.should contain("libx264")
    args.should contain("-crf")
    args.should contain("20")
    args.should contain("-c:a")
    args.should contain("aac")
    args.should contain("-movflags")
    args.should contain("+faststart")
  end

  it "builds GIF preset command correctly" do
    cmd = Fluorite::Presets::Gif.build_command("clip.mov", "anim.gif", fps: 12, width: 320)
    args = cmd.to_args
    filter_idx = args.index("-filter_complex").not_nil!
    filter_arg = args[filter_idx + 1]
    filter_arg.should contain("fps=12")
    filter_arg.should contain("scale=320:-1")
    filter_arg.should contain("palettegen")
    filter_arg.should contain("paletteuse")
  end

  it "builds Audio extraction command correctly" do
    cmd = Fluorite::Presets::Audio.build_command("video.mkv", "audio.mp3", format: :mp3, bitrate: "320k")
    args = cmd.to_args
    args.should contain("-vn")
    args.should contain("-c:a")
    args.should contain("libmp3lame")
    args.should contain("-b:a")
    args.should contain("320k")
  end

  it "builds Trim command correctly" do
    cmd = Fluorite::Presets::Trim.build_command("long.mp4", "short.mp4", from: "00:00:15", to: "00:00:45")
    args = cmd.to_args
    args.should contain("-ss")
    args.should contain("00:00:15")
    args.should contain("-to")
    args.should contain("00:00:45")
    args.should contain("-c:v")
    args.should contain("copy")
  end
end

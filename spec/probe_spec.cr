require "./spec_helper"

SAMPLE_FFPROBE_JSON = <<-JSON
{
  "streams": [
    {
      "index": 0,
      "codec_name": "h264",
      "codec_long_name": "H.264 / AVC / MPEG-4 AVC",
      "codec_type": "video",
      "profile": "High",
      "width": 1920,
      "height": 1080,
      "r_frame_rate": "60/1",
      "avg_frame_rate": "60/1",
      "pix_fmt": "yuv420p",
      "duration": "120.500",
      "bit_rate": "4500000"
    },
    {
      "index": 1,
      "codec_name": "aac",
      "codec_long_name": "AAC (Advanced Audio Coding)",
      "codec_type": "audio",
      "sample_rate": "48000",
      "channels": 2,
      "channel_layout": "stereo",
      "duration": "120.500",
      "bit_rate": "192000"
    }
  ],
  "format": {
    "filename": "sample_video.mp4",
    "nb_streams": 2,
    "format_name": "mov,mp4,m4a,3gp,3g2,mj2",
    "format_long_name": "QuickTime / MOV",
    "duration": "120.500",
    "size": "70000000",
    "bit_rate": "4692000"
  }
}
JSON

describe Fluorite::Probe do
  it "parses ffprobe JSON output accurately" do
    result = Fluorite::Probe::ProbeResult.from_json(SAMPLE_FFPROBE_JSON)

    result.format_name.should eq("mov,mp4,m4a,3gp,3g2,mj2")
    result.format.size_bytes.should eq(70_000_000_i64)
    result.format.bitrate_kbps.should eq(4692)

    result.streams.size.should eq(2)
    result.video_streams.size.should eq(1)
    result.audio_streams.size.should eq(1)

    vid = result.primary_video_stream.not_nil!
    vid.codec_name.should eq("h264")
    vid.resolution.should eq({1920, 1080})
    vid.fps.should eq(60.0)
    vid.aspect_ratio_str.should eq("16:9")

    aud = result.primary_audio_stream.not_nil!
    aud.codec_name.should eq("aac")
    aud.channels.should eq(2)
    aud.sample_rate.should eq("48000")

    result.duration_formatted.should eq("00:02:00.50")
  end
end

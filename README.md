# Flourite 🎬💎

[![Crystal](https://img.shields.io/badge/crystal-%3E%3D1.10.0-black.svg)](https://crystal-lang.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![TUI: Opal](https://img.shields.io/badge/TUI-Opal-magenta.svg)](https://github.com/sol-vin/opal)
[![Docs: Jasper](https://img.shields.io/badge/Docs-Jasper-blue.svg)](https://github.com/sol-vin/jasper)
[![Version: Carbon](https://img.shields.io/badge/Version-Carbon-green.svg)](https://github.com/sol-vin/carbon)

> **Next-generation FFMPEG bindings, fluent Crystal DSL, asynchronous streaming process wrapper, smart conversion presets, and full-screen Opal terminal UI.**

Flourite turns complex, arcane `ffmpeg` and `ffprobe` command strings into elegant, type-safe, and self-documenting Crystal code. Whether you need a 1-line Discord video compressor that is mathematically guaranteed to fit under upload limits, an interactive full-screen TUI to batch transcode media, a microsecond-accurate real-time progress streamer, or low-level C FFI access, Flourite delivers the ultimate developer experience.

---

## ✨ Features at a Glance

- **Fluent Block & Chainable DSL**: Express complex inputs, multi-stream mappings, hardware acceleration, video/audio codecs, and filter graphs naturally in Crystal.
- **Microsecond Real-Time Progress Streaming**: Non-blocking asynchronous fiber execution with structured progress events (FPS, percentage, speed, dynamic ETA countdown, bitrate, size).
- **Smart UX Presets**:
  - **Discord Bit Budgeting**: Automatically measures media duration, calculates total bit allocation ($V + A$), and transcodes video guaranteed to fit under Discord's 10MB/25MB/50MB limits!
  - **Crisp 2-Pass GIF**: Generates optimum 256-color palettes with Lanczos scaling for non-dithered high-definition GIFs.
  - **Web FastStart**: Optimizes MP4 containers for instant browser playback by moving the `moov` atom up front.
  - **Instant Stream Copy Trim**: Lossless cutting in milliseconds (`-c copy`) without re-encoding.
  - **Audio Extraction**: Direct conversion to MP3 (VBR/CBR), Opus, AAC, or lossless FLAC.
  - **Hardware Acceleration**: Automatic GPU detection and mapping for NVIDIA NVENC (`h264_nvenc`, `hevc_nvenc`, `av1_nvenc`), Intel QSV, AMD AMF, and Apple VideoToolbox.
- **Deep Media Probing (`Flourite::Probe`)**: Type-safe parser for `ffprobe` JSON, providing structured containers, audio/video stream specs, framerates, color spaces, aspect ratios, and tags.
- **Interactive Opal Terminal UI (`flourite tui`)**: Full-screen workspace built on `sol-vin/opal` featuring file browsing, media inspector cards, preset launcher, live Unicode progress gauges, FPS sparklines, and raw command preview.
- **CLI & Interactive Wizard (`flourite wizard`)**: Beautiful colorized terminal utilities and step-by-step interactive configuration.
- **Low-Level C FFI Bindings (`Flourite::C` / `LibAV`)**: Native declarations for `libavcodec`, `libavformat`, and `libavutil`.
- **Integrated Tooling**: Automated commit-based versioning via `sol-vin/carbon` and multi-track documentation via `sol-vin/jasper`.

---

## 🚀 Installation

Add `flourite` to your `shard.yml`:

```yaml
dependencies:
  flourite:
    github: sol-vin/flourite
    branch: main
```

Run `shards install`.

*Requires `ffmpeg` and `ffprobe` installed on your system (e.g., via Scoop, Chocolatey, Homebrew, or apt).*

---

## 🛠️ Quick Start

### 1. Fluent Block DSL

```crystal
require "flourite"

cmd = Flourite.build do
  # Global options
  overwrite!
  threads 0

  # Input configuration
  input("gameplay.mkv") do
    seek 10.seconds
    duration 30.seconds
    hwaccel :cuda # or :auto, :qsv, :amf
  end

  # Video options
  video do
    codec :h264
    crf 20
    preset :slow
    scale 1920, 1080
    fps 60
  end

  # Audio options
  audio do
    codec :aac
    bitrate "192k"
    volume 1.2
  end

  # Filter graph
  filter do
    drawtext text: "Recorded with Flourite", fontsize: 24, fontcolor: "white@0.8", x: 20, y: 20
  end

  # Output destination
  output("highlight.mp4") do
    faststart!
  end
end

# Run with real-time progress callbacks
runner = cmd.run do |p|
  print "\rTranscoding: #{p.percent.round(1)}% | FPS: #{p.fps} | Speed: #{p.speed}x | ETA: #{p.eta_formatted}"
end

puts "\nDone! Saved to highlight.mp4"
```

### 2. Chainable Fluent Syntax

```crystal
require "flourite"

Flourite.input("raw.mov")
  .video_codec(:h264)
  .crf(22)
  .scale(1280, 720)
  .audio_codec(:aac)
  .output("encoded.mp4")
  .run
```

### 3. Deep Media Inspection (`Flourite::Probe`)

```crystal
info = Flourite.probe("movie.mkv")

puts "Format:   #{info.format_name}"
puts "Duration: #{info.duration_formatted} (#{info.duration.total_seconds}s)"
puts "Size:     #{info.human_size}"
puts "Video:    #{info.video_summary}" # e.g. "H.264 1920x1080 @ 60.0 fps (yuv420p)"
puts "Audio:    #{info.audio_summary}" # e.g. "AAC 2.0 @ 192 kbps, 48000 Hz"
```

### 4. Smart UX Presets

```crystal
# 1. Discord 25MB Fit (auto bit budgeting)
Flourite::Presets::Discord.convert("long_recording.mp4", "discord_upload.mp4", target_mb: 25)

# 2. High-Quality 2-Pass Palette GIF
Flourite::Presets::Gif.convert("clip.mov", "preview.gif", fps: 15, width: 480)

# 3. Web-Optimized FastStart MP4
Flourite::Presets::Web.convert("source.avi", "streamable.mp4")

# 4. Extract High-Quality Audio
Flourite::Presets::Audio.extract("concert.mkv", "track.mp3", format: :mp3, bitrate: "320k")

# 5. Millisecond Stream-Copy Trim (no re-encoding!)
Flourite::Presets::Trim.cut("movie.mp4", "clip.mp4", from: "00:01:30", to: "00:02:15")
```

---

## 🖥️ Interactive Terminal UI (TUI)

Flourite includes a full-screen, reactive terminal application powered by **Opal**:

```bash
# Launch full-screen interactive TUI
flourite tui
```

### TUI Highlights:
- **File Browser**: Browse media files in the workspace with audio/video extension filtering.
- **Inspector Panel**: Dynamic cards detailing container format, codecs, resolution, bitrate, and streams.
- **Conversion Presets**: 1-click presets for Discord, Web MP4, GIF, Audio extraction, and AV1.
- **Live Transcode Monitor**: Real-time Opal progress gauge, digital speed & FPS telemetry, dynamic ETA countdown, FPS sparkline chart, and scrolling log viewer.
- **Command Preview**: Press `C` anywhere to inspect and copy the exact generated `ffmpeg` command line.

---

## 💻 CLI Commands

Flourite also acts as a standalone terminal powerhouse:

```bash
# Interactive TUI
flourite tui

# Interactive step-by-step CLI setup wizard
flourite wizard

# Beautiful colorized media inspection table
flourite probe video.mp4

# Compress for Discord (10MB / 25MB / 50MB)
flourite discord video.mp4 --limit 25MB

# Convert to crisp high-definition GIF
flourite gif animation.mov --fps 15 --width 480

# Ultra-fast lossless cut
flourite trim video.mp4 --from 00:01:00 --to 00:01:45 -o clip.mp4

# Extract audio track
flourite audio podcast.mp4 --format opus -o podcast.opus
```

---

## 📚 Documentation (Jasper)

Flourite's documentation is compiled via `sol-vin/jasper`:

```bash
# Validate guides
jasper validate

# Compile into Crystal docs
jasper build

# Generate static HTML doc site
crystal docs
```

---

## ⚡ Versioning (Carbon)

Flourite uses `sol-vin/carbon` for automated commit-based versioning:

```bash
# Audit repository version health
carbon doctor

# Bump commit version and sync manifests
carbon bump
```

---

## 📄 License

MIT © [Ian Rash (sol-vin)](https://github.com/sol-vin)

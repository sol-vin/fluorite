require "./spec_helper"

describe Fluorite::SpriteSheet do
  describe Fluorite::SpriteSheet::Core::Planner do
    it "calculates next power of two accurately" do
      Fluorite::SpriteSheet::Core::Planner.next_power_of_two(1).should eq(1)
      Fluorite::SpriteSheet::Core::Planner.next_power_of_two(64).should eq(64)
      Fluorite::SpriteSheet::Core::Planner.next_power_of_two(192).should eq(256)
      Fluorite::SpriteSheet::Core::Planner.next_power_of_two(260).should eq(512)
      Fluorite::SpriteSheet::Core::Planner.power_of_two?(256).should be_true
      Fluorite::SpriteSheet::Core::Planner.power_of_two?(192).should be_false
    end

    it "computes balanced grid layouts and strip policies" do
      Fluorite::SpriteSheet::Core::Planner.compute_grid(16).should eq({4, 4})
      Fluorite::SpriteSheet::Core::Planner.compute_grid(
        8,
        policy: Fluorite::SpriteSheet::Core::LayoutPolicy::Horizontal
      ).should eq({8, 1})
      Fluorite::SpriteSheet::Core::Planner.compute_grid(
        8,
        policy: Fluorite::SpriteSheet::Core::LayoutPolicy::Vertical
      ).should eq({1, 8})
      Fluorite::SpriteSheet::Core::Planner.compute_grid(
        10,
        policy: Fluorite::SpriteSheet::Core::LayoutPolicy::FixedCols,
        fixed_cols: 4
      ).should eq({4, 3})
    end

    it "computes accurate frame rects, normalized UVs, and VRAM compression metrics" do
      cfg = Fluorite::SpriteSheet::Core::PipelineConfig.new(
        input_path: "walk.mp4",
        output_path: "walk_sheet.png",
        frame_width: 64,
        frame_height: 64,
        frame_count: 16,
        fps: 10.0,
        format: Fluorite::SpriteSheet::Core::CompressionFormat::CLUT8
      )

      plan = Fluorite::SpriteSheet::Core::Planner.create_plan(cfg)
      plan.columns.should eq(4)
      plan.rows.should eq(4)
      plan.atlas_width.should eq(256)
      plan.atlas_height.should eq(256)
      plan.frames.size.should eq(16)

      first = plan.frames[0]
      first.x.should eq(0)
      first.y.should eq(0)
      first.u0.should eq(0.0)
      first.v0.should eq(0.0)
      first.u1.should eq(0.25)
      first.v1.should eq(0.25)
      first.timestamp_sec.should eq(0.0)

      last = plan.frames[15]
      last.column.should eq(3)
      last.row.should eq(3)
      last.x.should eq(192)
      last.y.should eq(192)
      last.u0.should eq(0.75)
      last.v0.should eq(0.75)
      last.u1.should eq(1.0)
      last.v1.should eq(1.0)
      last.timestamp_sec.should eq(1.5)

      # 256x256 RGBA32 = 262,144 bytes; CLUT8 = 65,536 + 1,024 = 66,560 bytes (~74.61% savings)
      plan.metrics.raw_rgba_bytes.should eq(262_144_i64)
      plan.metrics.compressed_vram_bytes.should eq(65_536_i64)
      plan.metrics.palette_overhead_bytes.should eq(1_024_i64)
      plan.metrics.total_vram_bytes.should eq(66_560_i64)
      plan.metrics.vram_savings_percent.should be > 74.0
    end

    it "expands atlas dimensions when power_of_two is enabled" do
      cfg = Fluorite::SpriteSheet::Core::PipelineConfig.new(
        input_path: "attack.mp4",
        output_path: "attack_sheet.png",
        frame_width: 60,
        frame_height: 60,
        frame_count: 9,
        columns: 3,
        rows: 3,
        power_of_two: true,
        format: Fluorite::SpriteSheet::Core::CompressionFormat::CLUT4
      )

      plan = Fluorite::SpriteSheet::Core::Planner.create_plan(cfg)
      plan.raw_atlas_width.should eq(180)
      plan.raw_atlas_height.should eq(180)
      plan.atlas_width.should eq(256)
      plan.atlas_height.should eq(256)
      plan.max_colors.should eq(16)
      plan.metrics.vram_savings_percent.should be > 87.0

      expr = Fluorite::SpriteSheet::Core::Planner.build_filter_expression(cfg, plan)
      expr.should contain("pad=256:256:0:0")
      expr.should contain("palettegen=max_colors=16")
    end

    it "generates deterministic Godot 4.8 .import metadata" do
      cfg = Fluorite::SpriteSheet::Core::PipelineConfig.new(
        input_path: "hero.mp4",
        output_path: "hero_sheet.png",
        frame_width: 32,
        frame_height: 32,
        frame_count: 8,
        columns: 4,
        rows: 2,
        animation_name: "run_cycle"
      )
      plan = Fluorite::SpriteSheet::Core::Planner.create_plan(cfg)
      import_ini = plan.to_godot_import("res://sprites/hero_sheet.png")
      import_ini.should contain("importer=\"texture\"")
      import_ini.should contain("type=\"CompressedTexture2D\"")
      import_ini.should contain("\"animation\": \"run_cycle\"")
      import_ini.should contain("\"hframes\": 4")
      import_ini.should contain("\"vframes\": 2")
      import_ini.should contain("source_file=\"res://sprites/hero_sheet.png\"")
      import_ini.should contain("filter/mode=0")
    end
  end

  describe Fluorite::SpriteSheet::DSL::SpriteSheetBuilder do
    it "builds CLUT8 sprite sheet command using block DSL" do
      sheet = Fluorite.spritesheet do
        input "knight.mov"
        output "knight_atlas.png"
        frame_size 48, 48
        frames 12
        columns 4
        fps 15
        padding 2
        margin 4
        power_of_two!
        clut8! dither: :bayer
        bayer_scale 3
        pixel_art!
        animation "idle"
      end

      plan = sheet.plan
      plan.columns.should eq(4)
      plan.rows.should eq(3)
      plan.raw_atlas_width.should eq(4 * 48 + 3 * 2 + 8) # 206
      plan.atlas_width.should eq(256)

      args = sheet.command.to_args
      args.should contain("-i")
      args.should contain("knight.mov")
      args.should contain("-filter_complex")
      filter_idx = args.index("-filter_complex").not_nil!
      filter_str = args[filter_idx + 1]
      filter_str.should contain("fps=15")
      filter_str.should contain("scale=48:48:flags=neighbor")
      filter_str.should contain("tile=layout=4x3:nb_frames=12:padding=2:margin=4")
      filter_str.should contain("pad=256:256")
      filter_str.should contain("palettegen=max_colors=256")
      filter_str.should contain("paletteuse=dither=bayer:bayer_scale=3")
      args.should contain("-frames:v")
      args.should contain("1")
      args.should contain("knight_atlas.png")
    end

    it "builds WebP and RGBA32 sprite sheets using chainable DSL" do
      builder = Fluorite.spritesheet("explosion.mp4")
        .to("explosion.webp")
        .frame_size(128, 128)
        .grid(4, 4)
        .fps(24)
        .webp!(quality: 95, lossless: true)
        .scale_flags(:lanczos)

      args = builder.command.to_args
      args.should contain("-vf")
      args.should contain("-c:v")
      args.should contain("libwebp")
      args.should contain("-lossless")
      args.should contain("1")
      args.should contain("explosion.webp")
    end
  end
end

require "./spec_helper"

describe Fluorite::DSL::FilterGraph do
  it "builds video filter arguments" do
    fg = Fluorite::DSL::FilterGraph.new
    fg.scale(1280, 720)
    fg.crop(1000, 600, 10, 20)
    fg.hflip
    fg.drawtext("Hello World", fontsize: 32, fontcolor: "white")

    args = fg.to_args
    args.should contain("-vf")
    vf_str = args[1]
    vf_str.should contain("scale=1280:720:flags=lanczos")
    vf_str.should contain("crop=1000:600:10:20")
    vf_str.should contain("hflip")
    vf_str.should contain("drawtext=text='Hello World':fontsize=32:fontcolor=white:x=10:y=10")
  end

  it "builds audio filter arguments" do
    fg = Fluorite::DSL::FilterGraph.new
    fg.volume(1.5)
    fg.loudnorm(i: -23.0)

    args = fg.to_args
    args.should contain("-af")
    af_str = args[1]
    af_str.should contain("volume=1.5")
    af_str.should contain("loudnorm=I=-23.0:LRA=7.0:tp=-2.0")
  end

  it "builds 2-pass palette gif filter" do
    fg = Fluorite::DSL::FilterGraph.new
    fg.palette_gif(fps_val: 20, scale_w: 640)

    args = fg.to_args
    args.should contain("-filter_complex")
    args[1].should contain("palettegen")
    args[1].should contain("paletteuse")
  end

  it "builds tile and palette_spritesheet filters" do
    fg = Fluorite::DSL::FilterGraph.new
    fg.tile(4, 4, nb_frames: 16, padding: 2)
    args = fg.to_args
    args.should contain("-vf")
    args[1].should contain("tile=layout=4x4:nb_frames=16:padding=2")

    fg2 = Fluorite::DSL::FilterGraph.new
    fg2.palette_spritesheet(4, 4, frame_width: 64, frame_height: 64, max_colors: 256)
    args2 = fg2.to_args
    args2.should contain("-filter_complex")
    args2[1].should contain("tile=layout=4x4:nb_frames=16")
    args2[1].should contain("palettegen=max_colors=256")
  end
end

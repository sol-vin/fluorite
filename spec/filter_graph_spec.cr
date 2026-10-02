require "./spec_helper"

describe Flourite::DSL::FilterGraph do
  it "builds video filter arguments" do
    fg = Flourite::DSL::FilterGraph.new
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
    fg = Flourite::DSL::FilterGraph.new
    fg.volume(1.5)
    fg.loudnorm(i: -23.0)

    args = fg.to_args
    args.should contain("-af")
    af_str = args[1]
    af_str.should contain("volume=1.5")
    af_str.should contain("loudnorm=I=-23.0:LRA=7.0:tp=-2.0")
  end

  it "builds 2-pass palette gif filter" do
    fg = Flourite::DSL::FilterGraph.new
    fg.palette_gif(fps_val: 20, scale_w: 640)

    args = fg.to_args
    args.should contain("-filter_complex")
    args[1].should contain("palettegen")
    args[1].should contain("paletteuse")
  end
end

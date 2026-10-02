require "./error"

module Flourite
  class Config
    property ffmpeg_path : String
    property ffprobe_path : String
    property ffplay_path : String
    property default_threads : Int32 = 0
    property temp_dir : String = Dir.tempdir
    property auto_hwaccel : Bool = true

    @available_hwaccels : Set(String)? = nil
    @available_encoders : Set(String)? = nil

    def initialize
      @ffmpeg_path = Config.find_binary("ffmpeg") || "ffmpeg"
      @ffprobe_path = Config.find_binary("ffprobe") || "ffprobe"
      @ffplay_path = Config.find_binary("ffplay") || "ffplay"
    end

    def ffmpeg_available? : Bool
      check_binary(@ffmpeg_path, "-version")
    end

    def ffprobe_available? : Bool
      check_binary(@ffprobe_path, "-version")
    end

    def ffplay_available? : Bool
      check_binary(@ffplay_path, "-version")
    end

    # Returns the set of supported hardware acceleration methods
    def available_hwaccels : Set(String)
      @available_hwaccels ||= begin
        accels = Set(String).new
        return accels unless ffmpeg_available?

        output = IO::Memory.new
        status = Process.run(@ffmpeg_path, ["-hwaccels"], output: output, error: Process::Redirect::Close)
        if status.success?
          output.to_s.each_line do |line|
            trimmed = line.strip
            next if trimmed.empty? || trimmed.starts_with?("Hardware acceleration")
            accels << trimmed.downcase
          end
        end
        accels
      rescue
        Set(String).new
      end
    end

    # Returns the set of supported video and audio encoders
    def available_encoders : Set(String)
      @available_encoders ||= begin
        encoders = Set(String).new
        return encoders unless ffmpeg_available?

        output = IO::Memory.new
        status = Process.run(@ffmpeg_path, ["-encoders"], output: output, error: Process::Redirect::Close)
        if status.success?
          output.to_s.each_line do |line|
            # Format: V..... libx264              H.264 / AVC / MPEG-4 AVC / MPEG-4 part 10
            parts = line.strip.split(/\s+/, 3)
            if parts.size >= 2 && parts[0].size >= 6
              encoders << parts[1].downcase
            end
          end
        end
        encoders
      rescue
        Set(String).new
      end
    end

    def nvenc_available? : Bool
      available_encoders.includes?("h264_nvenc") || available_hwaccels.includes?("cuda")
    end

    def qsv_available? : Bool
      available_encoders.includes?("h264_qsv") || available_hwaccels.includes?("qsv")
    end

    def amf_available? : Bool
      available_encoders.includes?("h264_amf") || available_hwaccels.includes?("amf")
    end

    def vaapi_available? : Bool
      available_hwaccels.includes?("vaapi")
    end

    def videotoolbox_available? : Bool
      available_encoders.includes?("h264_videotoolbox") || available_hwaccels.includes?("videotoolbox")
    end

    # Discovers best available hardware accelerated video encoder for given format
    def best_encoder_for(format : Symbol) : String
      case format
      when :h264
        return "h264_nvenc" if nvenc_available?
        return "h264_qsv" if qsv_available?
        return "h264_amf" if amf_available?
        return "h264_videotoolbox" if videotoolbox_available?
        "libx264"
      when :hevc, :h265
        return "hevc_nvenc" if nvenc_available? && available_encoders.includes?("hevc_nvenc")
        return "hevc_qsv" if qsv_available? && available_encoders.includes?("hevc_qsv")
        return "hevc_amf" if amf_available? && available_encoders.includes?("hevc_amf")
        return "hevc_videotoolbox" if videotoolbox_available? && available_encoders.includes?("hevc_videotoolbox")
        "libx265"
      when :av1
        return "av1_nvenc" if nvenc_available? && available_encoders.includes?("av1_nvenc")
        return "av1_qsv" if qsv_available? && available_encoders.includes?("av1_qsv")
        return "av1_amf" if amf_available? && available_encoders.includes?("av1_amf")
        "libsvtav1"
      else
        format.to_s
      end
    end

    def self.find_binary(name : String) : String?
      # Try Process.find_executable first
      if found = Process.find_executable(name)
        return found
      end

      # Platform-specific search paths
      exts = {% if flag?(:windows) %}
               [".exe", ".cmd", ".bat", ""]
             {% else %}
               [""]
             {% end %}

      candidates = [] of String

      {% if flag?(:windows) %}
        user_home = ENV["USERPROFILE"]? || ENV["HOME"]? || ""
        candidates << File.join(user_home, "scoop", "shims")
        candidates << File.join(user_home, "scoop", "apps", "ffmpeg", "current", "bin")
        candidates << "C:\\ProgramData\\chocolatey\\bin"
        candidates << "C:\\ffmpeg\\bin"
        candidates << "C:\\Program Files\\ffmpeg\\bin"
      {% else %}
        candidates << "/usr/local/bin"
        candidates << "/opt/homebrew/bin"
        candidates << "/usr/bin"
        candidates << "/bin"
      {% end %}

      candidates.each do |dir|
        exts.each do |ext|
          full = File.join(dir, "#{name}#{ext}")
          return full if File.exists?(full)
        end
      end

      nil
    end

    private def check_binary(path : String, flag : String) : Bool
      status = Process.run(path, [flag], output: Process::Redirect::Close, error: Process::Redirect::Close)
      status.success?
    rescue
      false
    end
  end

  # Global configuration singleton
  def self.config : Config
    @@config ||= Config.new
  end

  def self.configure(& : Config ->)
    yield config
  end
end

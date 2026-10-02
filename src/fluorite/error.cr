module Fluorite
  class Error < Exception
  end

  class BinaryNotFoundError < Error
    getter binary_name : String

    def initialize(@binary_name : String, search_paths : Array(String) = [] of String)
      msg = "Could not find '#{@binary_name}' binary in PATH or standard installation locations."
      unless search_paths.empty?
        msg += " Searched: #{search_paths.join(", ")}"
      end
      super(msg)
    end
  end

  class FFprobeError < Error
  end

  class ExecutionError < Error
    getter command : String
    getter exit_code : Int32?
    getter stderr : String

    def initialize(@command : String, @exit_code : Int32?, @stderr : String)
      super("FFmpeg command failed (exit code: #{@exit_code}):\n#{@stderr}")
    end
  end

  class InvalidFormatError < Error
  end
end

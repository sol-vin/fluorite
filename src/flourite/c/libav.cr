# Optional low-level C declarations for developers linking against FFmpeg libraries directly.
# (libavcodec, libavformat, libavutil)

module Flourite
  module C
    @[Link("avutil")]
    @[Link("avcodec")]
    @[Link("avformat")]
    lib LibAV
      enum AVMediaType
        UNKNOWN = -1
        VIDEO
        AUDIO
        DATA
        SUBTITLE
        ATTACHMENT
        NB
      end

      struct AVRational
        num : LibC::Int
        den : LibC::Int
      end

      type AVDictionary = Void*

      struct AVFormatContext
        av_class : Void*
        iformat : Void*
        oformat : Void*
        priv_data : Void*
        pb : Void*
        ctx_flags : LibC::Int
        nb_streams : LibC::UInt
        streams : Void**
        url : LibC::Char*
        start_time : LibC::LongLong
        duration : LibC::LongLong
        bit_rate : LibC::LongLong
      end

      struct AVCodec
        name : LibC::Char*
        long_name : LibC::Char*
        type : AVMediaType
        id : LibC::Int
      end

      struct AVCodecContext
        av_class : Void*
        log_level_offset : LibC::Int
        codec_type : AVMediaType
        codec : AVCodec*
        codec_id : LibC::Int
        codec_tag : LibC::UInt
        priv_data : Void*
        internal : Void*
        opaque : Void*
        bit_rate : LibC::LongLong
        width : LibC::Int
        height : LibC::Int
        pix_fmt : LibC::Int
        time_base : AVRational
      end

      struct AVPacket
        buf : Void*
        pts : LibC::LongLong
        dts : LibC::LongLong
        data : UInt8*
        size : LibC::Int
        stream_index : LibC::Int
        flags : LibC::Int
        duration : LibC::LongLong
        pos : LibC::LongLong
      end

      struct AVFrame
        data : UInt8*[8]
        linesize : LibC::Int[8]
        extended_data : UInt8**
        width : LibC::Int
        height : LibC::Int
        nb_samples : LibC::Int
        format : LibC::Int
        pts : LibC::LongLong
      end

      # Commonly used libav functions
      fun av_version_info : LibC::Char*
      fun avformat_version : LibC::UInt
      fun avcodec_version : LibC::UInt
      fun avutil_version : LibC::UInt
      fun av_strerror(errnum : LibC::Int, errbuf : LibC::Char*, errbuf_size : LibC::SizeT) : LibC::Int
    end
  end
end

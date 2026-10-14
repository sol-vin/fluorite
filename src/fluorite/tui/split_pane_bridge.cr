require "opal"

module Opal
  module UI
    enum SplitDirection
      {% unless @type.class.has_method?(:from) %}
        def self.from(val : SplitDirection | Symbol | String) : SplitDirection
          return val if val.is_a?(SplitDirection)
          case val.to_s.downcase.strip
          when "vertical", "vert", "v", "col", "column", "top_bottom", "stacked"
            Vertical
          else
            Horizontal
          end
        end
      {% end %}
    end

    # Custom lightweight canvas element that delegates rendering within its solved clip rect to a proc.
    class CanvasBlock < Element
      getter preferred_w : Int32
      getter preferred_h : Int32
      @draw : Proc(Buffer, Int32, Int32, Int32, Int32, Nil)

      def initialize(
        @preferred_w : Int32 = 80,
        @preferred_h : Int32 = 24,
        &@draw : Buffer, Int32, Int32, Int32, Int32 -> Nil
      )
      end

      def preferred_size(available_w : Int32, available_h : Int32) : {Int32, Int32}
        {Math.min(@preferred_w, available_w), Math.min(@preferred_h, available_h)}
      end

      def render(buffer : Buffer, x : Int32, y : Int32, width : Int32, height : Int32) : Nil
        return if width <= 0 || height <= 0
        @draw.call(buffer, x, y, width, height)
      end
    end

    class SplitBuilder
      {% unless @type.has_method?(:left) %}
        property first : Element?
        property second : Element?
        property direction_override : SplitDirection? = nil
        property ratio_override : Float64? = nil
        property first_size_override : Int32? = nil
        property second_size_override : Int32? = nil
        property min_first_size_override : Int32? = nil
        property max_first_size_override : Int32? = nil
        property separator_override : Char? = nil
        property separator_fg_override : Color? = nil
        property focused_pane_override : Symbol? = nil
        property show_separator_override : Bool? = nil

        def left(&) : Nil
          first { |b| with b yield b }
        end

        def left(element : Element) : Nil
          first(element)
        end

        def right(&) : Nil
          second { |b| with b yield b }
        end

        def right(element : Element) : Nil
          second(element)
        end

        def top(&) : Nil
          first { |b| with b yield b }
        end

        def top(element : Element) : Nil
          first(element)
        end

        def bottom(&) : Nil
          second { |b| with b yield b }
        end

        def bottom(element : Element) : Nil
          second(element)
        end

        def pane(
          title : String? = nil,
          border : Symbol | Border | Nil = nil,
          border_fg : Color | Symbol | String = Color.none,
          title_fg : Color | Symbol | String = :cyan,
          padding : Int32 = 0,
          bg : Color | Symbol | String = Color.none,
          &
        ) : Element?
          b = Builder.new
          with b yield b
          el = if title || border
                 Box.new(
                   child: b.root,
                   border: border || :rounded,
                   border_fg: border_fg,
                   padding: padding,
                   title: title,
                   title_fg: title_fg,
                   bg: bg
                 )
               else
                 b.root
               end
          if @first.nil?
            @first = el
          else
            @second = el
          end
          el
        end

        def pane(element : Element) : Element
          if @first.nil?
            @first = element
          else
            @second = element
          end
          element
        end

        def direction(dir : SplitDirection | Symbol | String) : self
          @direction_override = SplitDirection.from(dir)
          self
        end

        def horizontal : self
          @direction_override = SplitDirection::Horizontal
          self
        end

        def vertical : self
          @direction_override = SplitDirection::Vertical
          self
        end

        def ratio(val : Float64) : self
          @ratio_override = val
          self
        end

        def first_size(sz : Int32) : self
          @first_size_override = sz
          self
        end

        def second_size(sz : Int32) : self
          @second_size_override = sz
          self
        end

        def min_first_size(sz : Int32) : self
          @min_first_size_override = sz
          self
        end

        def max_first_size(sz : Int32) : self
          @max_first_size_override = sz
          self
        end

        def separator(ch : Char, fg : Color | Symbol | String = Color.none) : self
          @separator_override = ch
          @separator_fg_override = Color.from(fg)
          @show_separator_override = true
          self
        end

        def hide_separator : self
          @show_separator_override = false
          self
        end

        def focus(pane : Symbol) : self
          @focused_pane_override = pane
          self
        end
      {% end %}
    end

    class SplitView < Element
      {% unless @type.has_method?(:min_first_size) %}
        property min_first_size : Int32? = nil
        property max_first_size : Int32? = nil

        def initialize(
          @first : Element? = nil,
          @second : Element? = nil,
          direction : SplitDirection | Symbol | String = SplitDirection::Horizontal,
          @ratio : Float64? = 0.5,
          @first_size : Int32? = nil,
          @second_size : Int32? = nil,
          @min_first_size : Int32? = nil,
          @max_first_size : Int32? = nil,
          separator : Char? = nil,
          separator_fg : Color | Symbol | String = Color.none,
          focused_pane : Symbol = :first,
          @show_separator : Bool = true,
        )
          @direction = SplitDirection.from(direction)
          @separator = separator || (@direction == SplitDirection::Horizontal ? '│' : '─')
          @separator_fg = Color.from(separator_fg)
          @focused_pane = normalize_focus(focused_pane)
        end

        def self.new(
          direction : SplitDirection | Symbol | String = SplitDirection::Horizontal,
          ratio : Float64? = 0.5,
          first_size : Int32? = nil,
          second_size : Int32? = nil,
          min_first_size : Int32? = nil,
          max_first_size : Int32? = nil,
          separator : Char? = nil,
          separator_fg : Color | Symbol | String = Color.none,
          focused_pane : Symbol = :first,
          show_separator : Bool = true,
          &
        ) : SplitView
          sb = SplitBuilder.new
          with sb yield sb
          new(
            first: sb.first,
            second: sb.second,
            direction: sb.direction_override || direction,
            ratio: sb.ratio_override || ratio,
            first_size: sb.first_size_override || first_size,
            second_size: sb.second_size_override || second_size,
            min_first_size: sb.min_first_size_override || min_first_size,
            max_first_size: sb.max_first_size_override || max_first_size,
            separator: sb.separator_override || separator,
            separator_fg: sb.separator_fg_override || separator_fg,
            focused_pane: sb.focused_pane_override || focused_pane,
            show_separator: sb.show_separator_override.nil? ? show_separator : sb.show_separator_override.not_nil!
          )
        end

        def toggle_focus : Symbol
          @focused_pane = (@focused_pane == :first ? :second : :first)
        end

        def focus_first : Nil
          @focused_pane = :first
        end

        def focus_second : Nil
          @focused_pane = :second
        end

        def adjust_ratio(delta : Float64, min_ratio : Float64 = 0.1, max_ratio : Float64 = 0.9) : Float64
          current = @ratio || 0.5
          updated = (current + delta).clamp(min_ratio, max_ratio)
          @ratio = updated
          updated
        end

        private def normalize_focus(pane : Symbol) : Symbol
          case pane
          when :second, :right, :bottom
            :second
          else
            :first
          end
        end

        private def resolve_first_extent(avail : Int32) : Int32
          raw = if fs = @first_size
                  fs.clamp(0, avail)
                elsif ss = @second_size
                  avail - ss.clamp(0, avail)
                else
                  r = (@ratio || 0.5).clamp(0.0, 1.0)
                  (avail * r).round.to_i.clamp(0, avail)
                end
          if min_s = @min_first_size
            raw = Math.max(raw, min_s.clamp(0, avail))
          end
          if max_s = @max_first_size
            raw = Math.min(raw, max_s.clamp(0, avail))
          end
          raw.clamp(0, avail)
        end

        private def render_horizontal(buffer : Buffer, x : Int32, y : Int32, width : Int32, height : Int32) : Nil
          sep_w = @show_separator ? 1 : 0
          avail_w = Math.max(0, width - sep_w)

          w1 = resolve_first_extent(avail_w)
          w2 = avail_w - w1

          if (el1 = @first) && w1 > 0
            buffer.with_clip(x, y, w1, height) do
              el1.render(buffer, x, y, w1, height)
            end
          end

          if @show_separator && sep_w > 0
            sep_x = x + w1
            (0...height).each do |sy|
              buffer.put_char(sep_x, y + sy, @separator, fg: @separator_fg)
            end
          end

          if (el2 = @second) && w2 > 0
            pane2_x = x + w1 + sep_w
            buffer.with_clip(pane2_x, y, w2, height) do
              el2.render(buffer, pane2_x, y, w2, height)
            end
          end
        end

        private def render_vertical(buffer : Buffer, x : Int32, y : Int32, width : Int32, height : Int32) : Nil
          sep_h = @show_separator ? 1 : 0
          avail_h = Math.max(0, height - sep_h)

          h1 = resolve_first_extent(avail_h)
          h2 = avail_h - h1

          if (el1 = @first) && h1 > 0
            buffer.with_clip(x, y, width, h1) do
              el1.render(buffer, x, y, width, h1)
            end
          end

          if @show_separator && sep_h > 0
            sep_y = y + h1
            (0...width).each do |sx|
              buffer.put_char(x + sx, sep_y, @separator, fg: @separator_fg)
            end
          end

          if (el2 = @second) && h2 > 0
            pane2_y = y + h1 + sep_h
            buffer.with_clip(x, pane2_y, width, h2) do
              el2.render(buffer, x, pane2_y, width, h2)
            end
          end
        end
      {% end %}
    end

    module DSL
      def canvas_block(preferred_w : Int32 = 80, preferred_h : Int32 = 24, &block : Buffer, Int32, Int32, Int32, Int32 -> Nil) : CanvasBlock
        el = CanvasBlock.new(preferred_w, preferred_h, &block)
        add_element(el)
        el
      end

      {% unless @type.has_method?(:split_pane) %}
        def split_pane(
          direction : SplitDirection | Symbol | String = SplitDirection::Horizontal,
          ratio : Float64? = 0.5,
          first_size : Int32? = nil,
          second_size : Int32? = nil,
          min_first_size : Int32? = nil,
          max_first_size : Int32? = nil,
          separator : Char? = nil,
          separator_fg : Color | Symbol | String = Color.none,
          focused_pane : Symbol = :first,
          show_separator : Bool = true,
          &
        ) : SplitView
          sb = SplitBuilder.new
          with sb yield sb
          el = SplitView.new(
            first: sb.first,
            second: sb.second,
            direction: sb.direction_override || direction,
            ratio: sb.ratio_override || ratio,
            first_size: sb.first_size_override || first_size,
            second_size: sb.second_size_override || second_size,
            min_first_size: sb.min_first_size_override || min_first_size,
            max_first_size: sb.max_first_size_override || max_first_size,
            separator: sb.separator_override || separator,
            separator_fg: sb.separator_fg_override || separator_fg,
            focused_pane: sb.focused_pane_override || focused_pane,
            show_separator: sb.show_separator_override.nil? ? show_separator : sb.show_separator_override.not_nil!
          )
          add_element(el)
          el
        end

        def hsplit(
          ratio : Float64? = 0.5,
          first_width : Int32? = nil,
          second_width : Int32? = nil,
          min_first_width : Int32? = nil,
          max_first_width : Int32? = nil,
          separator : Char? = nil,
          separator_fg : Color | Symbol | String = Color.none,
          focused_pane : Symbol = :first,
          show_separator : Bool = true,
          &
        ) : SplitView
          split_pane(
            direction: SplitDirection::Horizontal,
            ratio: ratio,
            first_size: first_width,
            second_size: second_width,
            min_first_size: min_first_width,
            max_first_size: max_first_width,
            separator: separator,
            separator_fg: separator_fg,
            focused_pane: focused_pane,
            show_separator: show_separator
          ) { |sb| with sb yield sb }
        end

        def vsplit(
          ratio : Float64? = 0.5,
          first_height : Int32? = nil,
          second_height : Int32? = nil,
          min_first_height : Int32? = nil,
          max_first_height : Int32? = nil,
          separator : Char? = nil,
          separator_fg : Color | Symbol | String = Color.none,
          focused_pane : Symbol = :first,
          show_separator : Bool = true,
          &
        ) : SplitView
          split_pane(
            direction: SplitDirection::Vertical,
            ratio: ratio,
            first_size: first_height,
            second_size: second_height,
            min_first_size: min_first_height,
            max_first_size: max_first_height,
            separator: separator,
            separator_fg: separator_fg,
            focused_pane: focused_pane,
            show_separator: show_separator
          ) { |sb| with sb yield sb }
        end
      {% end %}
    end

    {% unless @type.class.has_method?(:split_pane) %}
      def self.split_pane(
        direction : SplitDirection | Symbol | String = SplitDirection::Horizontal,
        ratio : Float64? = 0.5,
        first_size : Int32? = nil,
        second_size : Int32? = nil,
        min_first_size : Int32? = nil,
        max_first_size : Int32? = nil,
        separator : Char? = nil,
        separator_fg : Color | Symbol | String = Color.none,
        focused_pane : Symbol = :first,
        show_separator : Bool = true,
        &
      ) : SplitView
        SplitView.new(
          direction: direction,
          ratio: ratio,
          first_size: first_size,
          second_size: second_size,
          min_first_size: min_first_size,
          max_first_size: max_first_size,
          separator: separator,
          separator_fg: separator_fg,
          focused_pane: focused_pane,
          show_separator: show_separator
        ) { |sb| with sb yield sb }
      end

      def self.hsplit(
        ratio : Float64? = 0.5,
        first_width : Int32? = nil,
        second_width : Int32? = nil,
        min_first_width : Int32? = nil,
        max_first_width : Int32? = nil,
        separator : Char? = nil,
        separator_fg : Color | Symbol | String = Color.none,
        focused_pane : Symbol = :first,
        show_separator : Bool = true,
        &
      ) : SplitView
        split_pane(
          direction: SplitDirection::Horizontal,
          ratio: ratio,
          first_size: first_width,
          second_size: second_width,
          min_first_size: min_first_width,
          max_first_size: max_first_width,
          separator: separator,
          separator_fg: separator_fg,
          focused_pane: focused_pane,
          show_separator: show_separator
        ) { |sb| with sb yield sb }
      end

      def self.vsplit(
        ratio : Float64? = 0.5,
        first_height : Int32? = nil,
        second_height : Int32? = nil,
        min_first_height : Int32? = nil,
        max_first_height : Int32? = nil,
        separator : Char? = nil,
        separator_fg : Color | Symbol | String = Color.none,
        focused_pane : Symbol = :first,
        show_separator : Bool = true,
        &
      ) : SplitView
        split_pane(
          direction: SplitDirection::Vertical,
          ratio: ratio,
          first_size: first_height,
          second_size: second_height,
          min_first_size: min_first_height,
          max_first_size: max_first_height,
          separator: separator,
          separator_fg: separator_fg,
          focused_pane: focused_pane,
          show_separator: show_separator
        ) { |sb| with sb yield sb }
      end
    {% end %}
  end

  {% unless @type.class.has_method?(:split_pane) %}
    # Declarative top-level `Opal.split_pane` layout builder.
    def self.split_pane(
      direction : UI::SplitDirection | Symbol | String = UI::SplitDirection::Horizontal,
      ratio : Float64? = 0.5,
      first_size : Int32? = nil,
      second_size : Int32? = nil,
      min_first_size : Int32? = nil,
      max_first_size : Int32? = nil,
      separator : Char? = nil,
      separator_fg : Color | Symbol | String = Color.none,
      focused_pane : Symbol = :first,
      show_separator : Bool = true,
      &
    ) : UI::SplitView
      UI.split_pane(
        direction: direction,
        ratio: ratio,
        first_size: first_size,
        second_size: second_size,
        min_first_size: min_first_size,
        max_first_size: max_first_size,
        separator: separator,
        separator_fg: separator_fg,
        focused_pane: focused_pane,
        show_separator: show_separator
      ) { |sb| with sb yield sb }
    end

    def self.hsplit(
      ratio : Float64? = 0.5,
      first_width : Int32? = nil,
      second_width : Int32? = nil,
      min_first_width : Int32? = nil,
      max_first_width : Int32? = nil,
      separator : Char? = nil,
      separator_fg : Color | Symbol | String = Color.none,
      focused_pane : Symbol = :first,
      show_separator : Bool = true,
      &
    ) : UI::SplitView
      UI.hsplit(
        ratio: ratio,
        first_width: first_width,
        second_width: second_width,
        min_first_width: min_first_width,
        max_first_width: max_first_width,
        separator: separator,
        separator_fg: separator_fg,
        focused_pane: focused_pane,
        show_separator: show_separator
      ) { |sb| with sb yield sb }
    end

    def self.vsplit(
      ratio : Float64? = 0.5,
      first_height : Int32? = nil,
      second_height : Int32? = nil,
      min_first_height : Int32? = nil,
      max_first_height : Int32? = nil,
      separator : Char? = nil,
      separator_fg : Color | Symbol | String = Color.none,
      focused_pane : Symbol = :first,
      show_separator : Bool = true,
      &
    ) : UI::SplitView
      UI.vsplit(
        ratio: ratio,
        first_height: first_height,
        second_height: second_height,
        min_first_height: min_first_height,
        max_first_height: max_first_height,
        separator: separator,
        separator_fg: separator_fg,
        focused_pane: focused_pane,
        show_separator: show_separator
      ) { |sb| with sb yield sb }
    end
  {% end %}
end

--[[
    Second vt100 implementation.  Should be fairly compatible with console_codes(5).
    Copyright (C) 2024 ULOS Developers

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <https://www.gnu.org/licenses/>.
  ]]--

printk(k.L_INFO, "tty")

do
  -- control characters
  local NUL = '\x00'
  local BEL = '\x07'
  local BS  = '\x08'
  local HT  = '\x09'
  local LF  = '\x0a'
  local VT  = '\x0b'
  local FF  = '\x0c'
  local CR  = '\x0d'
  -- UNSUPPORTED: SO, SI
  local SO  = '\x0e'
  local SI  = '\x0f'
  local CAN = '\x18'
  local SUB = '\x1a'
  local ESC = '\x1b'
  -- ignored apparently
  local DEL = '\x7f'
  -- equivalent to esc [
  local CSI = '\x9B'

  local MODE_NORMAL = 0
  local MODE_ESC = 1
  local MODE_CSI = 2
  local MODE_DSAT = 3
  local MODE_CHARSET = 4
  local MODE_G0 = 5
  local MODE_G1 = 6
  local MODE_OSC = 7

  local control_chars = {
    [NUL] = true,
    [BEL] = true,
    [BS] = true,
    [HT] = true,
    [LF] = true,
    [VT] = true,
    [FF] = true,
    [CR] = true,
    [SO] = true,
    [SI] = true,
    [CAN] = true,
    [SUB] = true,
    [ESC] = true,
    [DEL] = true,
    [CSI] = true,
  }

  local scancode_lookups = {
    [200] = "A",
    [208] = "B",
    [205] = "C",
    [203] = "D"
  }

  local colors = {
    0x000000,
    0xaa0000,
    0x00aa00,
    0xaaaa00,
    0x0000aa,
    0xaa00aa,
    0x00aaaa,
    0xaaaaaa,
    -- bright
    0x555555,
    0xff5555,
    0x55ff55,
    0xffff55,
    0x5555ff,
    0xff55ff,
    0x55ffff,
    0xffffff
  }

  -- use string.gmatch for parsing smaller than this, string.sub for everything longer or equal
  -- in normal Lua gmatch is twice as fast for everything, but OpenComputers reimplements the
  -- pattern-matching functions in Lua, which is approximately 100x slower.
  -- on my machine lua5.4 gmatch takes 4.5 seconds to process 128MB of data;
  -- OpenComputers gmatch takes nearly 10 minutes.
  -- string.sub takes roughly 8 seconds on lua5.4 and 12 on OpenComputers.
  local MAX_GMATCH = 500

  local gmatch, sub = string.gmatch, string.sub
  local function get_iter(str)
    if #str < MAX_GMATCH then
      return gmatch(str, "()(.)")
    else
      local n, len = 0, #str
      return function()
        n = n + 1
        if n < len then return n, sub(str, n, n) end
      end
    end
  end

  function k.open_tty(gpu, screen)
    checkArg(1, gpu, "string", "table")
    checkArg(2, screen, "string", "nil")

    if type(gpu) == "string" then gpu = component.proxy(gpu) end
    if screen then gpu.bind(screen) end

    local w, h = gpu.getResolution()
    local mode = MODE_NORMAL
    local seq = {}
    local wbuf, rbuf = "", ""
    local tab_width = 8
    local question = false
    local autocr, reverse, insert, display, mousereport, cursor, altcursor, autowrap
      = true, false, false, false, false, true, false, true
    local cx, cy, scx, scy = 1, 1
    local st, sb = 1, h
    local fg, bg = colors[8], colors[1]
    local save = {fg = fg, bg = bg, autocr = autocr, reverse = reverse, display = display, insert = insert,
      mousereport = mousereport, altcursor = altcursor, cursor = cursor, autowrap = autowrap}
    local cursorvisible = false
    local shouldchange = false
    local keyboards = {}
    local new = {}

    for _, kbaddr in pairs(component.invoke(gpu.getScreen(), "getKeyboards")) do
      keyboards[kbaddr] = true
    end

    local function setcursor(v)
      if cursorvisible ~= v then
        shouldchange = true
        cursorvisible = v
        local c, cfg, cbg = gpu.get(cx, cy)
        gpu.setBackground(cfg)
        gpu.setForeground(cbg)
        gpu.set(cx, cy, c)
      end
    end

    local function scroll(n)
      if n < 0 then
        gpu.copy(1, st, w, sb+n, 0, -n)
        gpu.fill(1, 1, w, -n, " ")
      else
        gpu.copy(1, st+n, w, sb, 0, -n)
        gpu.fill(1, sb - n + 1, w, n, " ")
      end
    end

    local function corral()
      cx = math.max(1, cx)
      if cx > w and autowrap then
        cx = 1
        cy = cy + 1
      end
      if cy > sb then
        scroll(cy - sb)
        cy = sb
      elseif cy < st then
        scroll(-(st - cy))
        cy = st
      end
    end

    local function clamp()
      cx, cy = math.min(w, math.max(1, cx)), math.min(h, math.max(1, cy))
    end

    local function flush()
      gpu.setForeground(reverse and bg or fg)
      gpu.setBackground(reverse and fg or bg)
      repeat
        local towrite = sub(wbuf, 1, w-cx+1)
        wbuf = sub(wbuf, #towrite+1)
        if insert then
          gpu.copy(cx, cy, w, 1, #towrite, 0)
        end
        gpu.set(cx, cy, towrite)
        cx = cx + #towrite
        corral()
      until #wbuf == 0 or not autowrap
      if new.discipline and #rbuf > 0 then
        new.discipline:processInput(rbuf)
        rbuf = ""
      end
    end

    local function write(_, str)
      if #str == 0 then return end

      setcursor(false)
      if shouldchange then
        gpu.setForeground(reverse and bg or fg)
        gpu.setBackground(reverse and fg or bg)
      end

      local pi = 1
      for i, c in get_iter(str) do
        if control_chars[c] then
          if pi > 0 then
            wbuf = wbuf .. sub(str, pi, i-1)
            flush()
            pi = -1
          end
          -- control characters are always processed, even in the middle of a sequence
          if c == BEL then
            computer.beep()
          elseif c == BS then
            cx = cx - 1
            corral()
          elseif c == HT then
            cx = tab_width * math.floor((cx + tab_width + 1) / tab_width) - 1
            corral()
          elseif c == LF or c == VT or c == FF then
            if autocr then cx = 1 end
            cy = cy + 1
            corral()
          elseif c == CR then
            cx = 1
          elseif c == CAN or c == SUB then
            mode = MODE_NORMAL
          elseif c == ESC then -- start new ESC-sequence
            seq = {}
            mode = MODE_ESC
          elseif c == CSI then -- start new CSI-sequence (ESC [)
            seq = {}
            question = false
            mode = MODE_CSI
          end

        elseif mode == MODE_ESC then
          if c == "[" then
            mode = MODE_CSI
            question = false
          elseif c == "c" then -- RIS / reset
            fg, bg = colors[8], colors[1]
            autocr, reverse, insert, display, mousereport, cursor, altcursor, autowrap
              = false, false, false, false, false, true, false, true
          elseif c == "D" then -- IND / line feed
            cy = cy + 1
            corral()
          elseif c == "E" then -- NEL / newline
            cy = cy + 1
            cx = 1
            corral()
          elseif c == "F" then -- cursor to lower left of screen
            cx, cy = 1, h
          elseif c == "H" then -- HTS / set tab stop at current column
            error("TODO: ESC H")
          elseif c == "M" then -- RI / reverse linefeed
            cy = cy - 1
            corral()
          elseif c == "Z" then -- DECID / DEC private identification.  return ESC [ ? 6 c (VT102)
            rbuf = rbuf .. ESC .. "[?6c"
          elseif c == "7" then -- DECSC / save current state (cursor, attributes, charsets)
            save = {fg = fg, bg = bg, autocr = autocr, reverse = reverse, display = display, insert = insert,
              mousereport = mousereport, altcursor = altcursor, cursor = cursor, autowrap = autowrap}
          elseif c == "8" then -- DECRC / restore last ESC 7 state
            fg, bg = save.fg, save.bg
            autocr, reverse, display, insert = save.autocr, save.reverse, save.display, save.insert
            mousereport, altcursor, cursor, autowrap = save.mousereport, save.altcursor, save.cursor, save.autowrap
          elseif c == "%" then -- start sequence selecting character set
            mode = MODE_CHARSET
          elseif c == "#" then -- start DECALN
            mode = MODE_DSAT
          elseif c == "(" then -- define G0
            mode = MODE_G0 -- TODO
          elseif c == ")" then -- define G1
            mode = MODE_G1 -- TODO
          elseif c == ">" then -- DECPNM / set numeric keypad mode
            -- TODO
          elseif c == "=" then -- DECPAM / set application keypad mode
            -- TODO
          elseif c == "]" then -- OSC / operating system command
            mode = MODE_OSC
          end

        elseif mode == MODE_CSI then
          if c == "?" then
            if #seq > 0 or question then
              mode = MODE_NORMAL
              question = false
            else
              question = true
            end
          elseif c == "@" then -- ICH / insert blank characters
            if seq[1] and seq[1] > 0 then
              gpu.copy(cx, cy, w, 1, seq[1], 0)
              gpu.fill(cx, cy, seq[1], 1, " ")
            end
          elseif c == "A" then -- CUU / cursor up
            cy = cy - (seq[1] or 1)
            clamp()
          elseif c == "B" or c == "e" then -- CUD, VPR / cursor down
            cy = cy + (seq[1] or 1)
            clamp()
          elseif c == "C" or c == "a" then -- CUF, HPR / cursor right
            cx = cx + (seq[1] or 1)
            clamp()
          elseif c == "D" then -- CUB / cursor left
            cx = cx - (seq[1] or 1)
            clamp()
          elseif c == "E" then -- CNL / cursor down N rows to column 1
            cx = 1
            cy = cy - (seq[1] or 1)
            clamp()
          elseif c == "F" then -- CPL / cursor up N rows to column 1
            cx = 1
            cy = cy + (seq[1] or 1)
            clamp()
          elseif c == "G" or c == "`" then -- CHA, HPA / cursor to column
            cx = (seq[1] or 1)
            clamp()
          elseif c == "H" or c == "f" then -- CUP, HVP / cursor to row, column
            cy, cx = seq[1] or 1, seq[3] or 1
            clamp()
          elseif c == "J" then -- ED / erase display
            local m = seq[1] or 0
            if m == 0 then
              -- erase from cursor to end
              gpu.fill(cx, cy, w, 1, " ")
              gpu.fill(1, cy+1, w, h, " ")
            elseif m == 1 then
              -- erase from start to cursor
              gpu.fill(1, 1, w, cy-1, " ")
              gpu.fill(1, cy, cx, 1, " ")
            elseif m == 2 or m == 3 then
              -- erase whole screen
              gpu.fill(1, 1, w, h, " ")
            end
          elseif c == "K" then -- EL / erase line
            local m = seq[1] or 0
            if m == 0 then -- erase from cursor to end
              gpu.fill(cx, cy, w, 1, " ")
            elseif m == 1 then -- erase from start to cursor
              gpu.fill(1, cy, cx, 1, " ")
            elseif m == 2 then -- erase whole line
              gpu.fill(1, cy, w, 1, " ")
            end
          elseif c == "L" then -- IL / insert blank lines
            local n = seq[1] or 1
            gpu.copy(1, cy, w, h, 0, n)
            gpu.fill(1, cy, w, n, " ")
          elseif c == "M" then -- DL / delete lines
            local n = seq[1] or 1
            gpu.copy(1, cy, w, h, 0, -n)
            gpu.fill(1, h-n, w, n, " ")
          elseif c == "P" then -- DCH / delete characters
            local n = seq[1] or 1
            gpu.copy(cx, cy, w, 1, -n, 0)
          elseif c == "S" then -- not in console_codes(4) / scroll down
            scroll(seq[1] or 1)
          elseif c == "T" then -- not in console_codes(4) / scroll up
            scroll(-(seq[1] or 1))
          elseif c == "X" then -- ECH / erase characters
            local n = seq[1] or 1
            gpu.fill(cx, cy, n, 1, " ")

          -- ESC [ a identical to ESC [ C, see above
          elseif c == "c" then -- DA / answer "VT102"
            rbuf = rbuf .. ESC .. "?6c"
          elseif c == "d" then -- VPA / move cursor to row, current column
            cy = seq[1] or 1
            clamp()
          -- e / VPR identical to B
          -- f / HVP identical to H
          elseif c == "g" then -- TBC / clear current tab stop
            -- TODO
            -- if arg == 3 clear ALL tab stops
          elseif c == "h" or c == "l" then -- SM, RM / set mode, reset mode
            local set = c == "h"
            if question then -- DEC private modes
              for i=1, #seq, 2 do
                if seq[i] == 1 then -- DECCKM / cursor keys send ESC O instead of ESC [
                  altcursor = set
                -- DECCOLM / 80/132 col switch not implemented
                -- DECSCNM / reverse video mode not implemented
                elseif seq[i] == 6 then -- DECOM / cursor addressing relative to scroll region
                  -- TODO
                elseif seq[i] == 7 then -- DECAWM / autowrap
                  autowrap = set
                elseif seq[i] == 9 then -- X10 mouse reporting
                  mousereport = set and 1 or 0
                elseif seq[i] == 25 then -- DECTECM / set cursor visible
                  cursor = set
                elseif seq[i] == 1000 then -- X11 mouse reporting
                  mousereport = set and 2 or 0
                end
              end

            else -- ECMA-48 modes
              for i=1, #seq, 2 do
                if seq[i] == 3 then -- DECCRM / display control characters
                  display = set
                elseif seq[i] == 4 then -- set insert mode
                  insert = set
                elseif seq[i] == 20 then -- autocr
                  autocr = set
                end
              end
            end
          elseif c == "m" then -- SGR / set attributes
            if not seq[1] then seq[1] = 0 end
            for i=1, #seq, 2 do
              -- only implement a subset of these that it makes sense to
              if seq[i] == 0 then -- reset
                fg, bg = colors[8], colors[1]
                reverse = false
              elseif seq[i] == 7 then -- reverse
                reverse = true
              elseif seq[i] == 27 then -- unset reverse
                reverse = false
              elseif seq[i] > 29 and seq[i] < 38 then -- foreground
                fg = colors[seq[i] - 29]
                shouldchange = true
              elseif seq[i] > 39 and seq[i] < 48 then -- background
                bg = colors[seq[i] - 39]
                shouldchange = true
                -- TODO: 38/48 rgb color support?
              elseif seq[i] == 39 then -- default fg
                fg = colors[8]
                shouldchange = true
              elseif seq[i] == 49 then -- default bg
                bg = colors[1]
                shouldchange = true
              elseif seq[i] > 89 and seq[i] < 98 then -- bright foreground
                fg = colors[seq[i] - 81]
                shouldchange = true
              elseif seq[i] > 99 and seq[i] < 108 then -- bright background
                bg = colors[seq[i] - 91]
                shouldchange = true
              end
            end
          elseif c == "n" then -- DSR / status report
            for i=1, #seq, 2 do
              if seq[i] == 5 then -- DSR / device status report
                rbuf = rbuf .. ESC .. "[0n" -- Terminal OK
              elseif seq[i] == 6 then -- CPR / cursor position report
                rbuf = rbuf .. string.format("%s[%d;%dR", ESC, cy, cx)
              end
            end
          -- no [ q / DECLL, keyboard LEDs not implemented
          elseif c == "r" then -- DECSTBM / set scrolling region
            st, sb = seq[1] or 1, seq[2] or h
          elseif c == "s" then -- ? / save cursor position
            scx, scy = cx, cy
          elseif c == "u" then -- ? / restore cursor position
            cx, cy = scx or cx, scy or cy
          -- HPA identical to CHA/G

          -- CSI [ c and ESC [ [ c are ignored, to ignore echoed function keys
          elseif c == "[" then
            seq = "["
          elseif seq == "[" then
            mode = MODE_NORMAL

          elseif c == ";" then
            if seq[#seq] == ";" then
              seq[#seq+1] = 0
            end
            seq[#seq+1] = ";"
          elseif tonumber(c) then
            if seq[#seq] == ";" then
              seq[#seq+1] = tonumber(c)
            else
              seq[math.max(1, #seq)] = (seq[#seq] or 0) * 10 + tonumber(c)
            end
          end

          if c ~= ";" and c ~= "?" and not tonumber(c) then
            mode = MODE_NORMAL
          end

        elseif mode == MODE_NORMAL then
          if pi < 1 then
            pi = i
          end

        elseif mode == MODE_OSC then
          -- TODO
          mode = MODE_NORMAL

        elseif mode == MODE_G0 then
          mode = MODE_NORMAL -- TODO

        elseif mode == MODE_G1 then
          mode = MODE_NORMAL -- TODO

        elseif mode == MODE_CHARSET then
          mode = MODE_NORMAL -- TODO

        elseif mode == MODE_DSAT then
          if c == "8" then
            gpu.fill(1, 1, w, h, "E")
          end
          mode = MODE_NORMAL
        end
      end

      if pi > 0 then
        wbuf = wbuf .. sub(str, pi, #str)
      end

      flush()

      if mode == MODE_NORMAL and cursor then
        setcursor(true)
      end
    end

    new.write = write
    new.flush = function() end

    new.khid = k.add_signal_handler("key_down", function(_, kbd, char, code)
      if not keyboards[kbd] then return end
      if not new.discipline then return end

      local to_buffer
      if scancode_lookups[code] then
        local c = scancode_lookups[code]
        local interim = altcursor and "O" or "["
        to_buffer = ESC .. interim .. c

      elseif char > 0 then
        to_buffer = string.char(char)
      end

      if to_buffer then
        new.discipline:processInput(to_buffer)
      end
    end)

    return new
  end

  k.init_ttys()
end

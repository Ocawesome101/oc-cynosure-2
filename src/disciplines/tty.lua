--[[
  TTY line discipline
  Copyright (C) 2022 Ocawesome101

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

printk(k.L_INFO, "disciplines/tty")

do
  local discipline = {}

  function discipline.open(obj)
    checkArg(1, obj, "table")

    local new = setmetatable({
      obj = obj,
      mode = "line", rbuf = "", wbuf = "",
      eol = "\n", erase = "\8", intr = "\3", kill = "\28",
      quit = "", start = "\19", stop = "\17", susp = "\26"
    }, {__index=discipline})
    obj.discipline = new
    new.eolpat = string.format("%%%s[^%%%s]-$", new.eol, new.eol)
    new.eofpat = string.format("%%%s[^%%%s]-$", new.eof, new.eof)

    local proc = k.current_process()
    if not proc.tty then
      proc.tty = new
    end

    return new
  end

  local sub32_lookups = {
    [0]   = " ",
    [27]  = "[",
    [28]  = "\\",
    [29]  = "]",
    [30]  = "~",
    [31]  = "?"
  }

  for i=1, 26, 1 do sub32_lookups[i] = string.char(96 + i) end

  -- process new input from the stream - this is keyboard input
  function discipline:processInput(inp)
    self:flush()
    for c in inp:gmatch(".") do
      if c == self.erase then
        if #self.rbuf > 0 then
          local last = self.rbuf:sub(-1)
          if self.echo then
            if last:byte() < 32 then
              self.obj:write("\27[2B  \27[2B")
            else
              self.obj:write("\27[B \27[B")
            end
          end
          if last ~= self.eol and last ~= self.eof then
            self.rbuf = self.rbuf:sub(1, -2)
          end
        end
      elseif c == self.eof then
        if self.rbuf:sub(-1) == self.eol then
          self.rbuf = self.rbuf .. c
          if self.echo then
            local byte = string.byte(c)
            if sub32_lookups[byte] then
              self.obj:write("^"..sub32_lookups[byte])
            else
              self.obj:write(c)
            end
          end
        end

      elseif c == self.intr then
        local pids = find_procs(self)

      elseif c == self.kill then

      elseif c == self.quit then

      elseif c == self.start then

      elseif c == self.stop then

      elseif c == self.susp then

      else
        self.rbuf = self.rbuf .. c

        if self.echo then
          local byte = string.byte(c)

          if sub32_lookups[byte] then
            self.obj:write("^"..sub32_lookups[byte])
          else
            self.obj:write(c)
          end
        end
      end
    end
  end

  local function s(se,k,v)
    se[k] = v[k] or se[k]
  end

  function discipline:ioctl(method, args)
    if method ~= "stty" then return nil, k.errno.ENOTTY end
    checkArg(2, args, "table")

    s(self, "eol", args)
    s(self, "erase", args)
    s(self, "intr", args)
    s(self, "kill", args)
    s(self, "quit", args)
    s(self, "start", args)
    s(self, "stop", args)
    s(self, "susp", args)
    -- One of those rare cases where comparing against nil
    -- directly is the correct thing to do.
    if args.echo ~= nil then self.echo = not not args.echo end
    if args.raw ~= nil then self.raw = not not args.raw end
    self.eolpat = string.format("%%%s[^%%%s]-$", self.eol, self.eol)
    self.eofpat = string.format("%%%s[^%%%s]-$", self.eof, self.eof)

    return true
  end

  function discipline:read(n)
    checkArg(1, n, "number")

    if self.last_eof then
      self.last_eof = false
      return nil
    end

    while #self.rbuf < n do
      coroutine.yield()
      if self.rbuf:find("%"..self.eof) then break end
    end
    if self.mode == "line" then
      while (self.rbuf:find(self.eolpat) or 0) < n do
        coroutine.yield()
        if self.rbuf:find("%"..self.eof) then break end
      end
    end

    local eof = self.rbuf:find("%"..self.eof)
    n = math.min(n, eof or math.huge)

    self.last_eof = not not eof

    local data = self.rbuf:sub(1, n)
    self.rbuf = self.rbuf:sub(#data + 1)
    return data
  end

  function discipline:write(text)
    checkArg(1, text, "string")

    self.wbuf = self.wbuf .. text

    local last_eol = self.wbuf:find(self.eolpat)
    if last_eol then
      local data = self.wbuf:sub(1, last_eol)
      self.wbuf = self.wbuf:sub(#data + 1)
      self.obj:write(data)
    end

    return true
  end

  function discipline:flush()
    local data = self.wbuf
    self.wbuf = ""
    self.obj:write(data)
  end

  function discipline:close()
  end

  k.disciplines.tty = discipline
end

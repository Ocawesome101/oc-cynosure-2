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
  local discipline = { default_mode = "line" }

  local eolpat = "\n[^\n]-$"

  function discipline.wrap(obj)
    checkArg(1, obj, "table")

    local new
    if obj.discipline then
      new = obj.discipline

    else
      new = setmetatable({
        obj = obj,
        mode = "line", rbuf = "", wbuf = "",
        erase = "\8", intr = "\3", kill = "\21",
        quit = "\28", start = "\19", stop = "\17",
        susp = "\26", eof = "\4", raw = false,
        stopped = false, echo = true,
        override_setvbuf = true
      }, {__index=discipline})
      obj.discipline = new
      new.eofpat = string.format("%%%s[^%%%s]-$", new.eof, new.eof)
    end

    local proc = k.current_process()
    if proc and not new.session and not proc.tty then
      proc.tty = new
      new.session = proc.sid
      new.pgroup = proc.pgroup
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

  local sub32_lookups_notraw = {
    [10] = "\n"
  }

  for i=1, 26, 1 do sub32_lookups[i] = string.char(64 + i) end

  local function send(obj, sig)
    local pids = k.get_pids()
    printk(k.L_DEBUG, "sending %s to pgroup %d", sig, obj.pgroup or -1)

    for i=1, #pids, 1 do
      local proc = k.get_process(pids[i])

      if proc.pgid == obj.pgroup then
        printk(k.L_DEBUG, "sending %s to %d", sig, pids[i])
        table.insert(proc.sigqueue, sig)
      end
    end
  end

  local function pchar(self, c)
    if self.echo then
      local byte = string.byte(c)

      if (not self.raw) and sub32_lookups_notraw[byte] then
        self.obj:write(sub32_lookups_notraw[byte])

      elseif sub32_lookups[byte] then
        self.obj:write("^"..sub32_lookups[byte])

      elseif byte < 126 then
        self.obj:write(c)
      end
    end
  end

  local function wchar(self, c)
    if (not self.raw) and c == "\r" then c = "\n" end
    self.rbuf = self.rbuf .. c
    pchar(self, c)
  end

  -- process new input from the stream - this is keyboard input
  function discipline:processInput(inp)
    self:flush()
    for c in inp:gmatch(".") do
      if not self.raw then
        if c == self.erase then
          if #self.rbuf > 0 then
            local last = self.rbuf:sub(-1)
            if last ~= self.eol and last ~= self.eof then
              if self.echo then
                if last:byte() < 32 then
                  self.obj:write("\27[2D  \27[2D")

                else
                  self.obj:write("\27[D \27[D")
                end
              end
              self.rbuf = self.rbuf:sub(1, -2)
            end
          end

        elseif c == self.eof then
          wchar(self, c)

        elseif c == self.intr then
          send(self, "SIGINT")
          pchar(self, self.intr)

        -- kill (erase current line) not implemented; this
        -- implementation does not provide line editing

        elseif c == self.quit then
          send(self, "SIGQUIT")
          pchar(self, self.quit)

        elseif c == self.start then
          self.stopped = false

        elseif c == self.stop then
          self.stopped = true

        elseif c == self.susp then
          send(self, "SIGSTOP")
          pchar(self, self.susp)

        else
          wchar(self, c)
        end

      else
        wchar(self, c)
      end
    end
  end

  local function s(se,k,v)
    se[k] = v[k] or se[k]
  end

  function discipline:ioctl(method, args)
    if method == "stty" then
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

      self.eofpat = string.format("%%%s[^%%%s]-$", self.eof, self.eof)

      return true

    elseif method == "getattrs" then
      return {
        eol = self.eol,
        erase = self.erase,
        intr = self.intr,
        kill = self.kill,
        quit = self.quit,
        start = self.start,
        stop = self.stop,
        susp = self.susp,
        echo = self.echo,
        raw = self.raw
      }

    elseif method == "setpg" then
      local current = k.current_process()
      if self.pgroup and current.pgid ~= self.pgroup then
        current:signal("SIGTTOU", true)
      end

      self.pgroup = args
      return true

    elseif method == "getpg" then
      return self.pgroup or math.huge

    elseif method == "ttyname" then
      return self.obj.name

    elseif method == "setvbuf" then
      if args == "line" or args == "none" then
        self.mode = args

      else
        return nil, k.errno.EINVAL
      end

    elseif method == "setlogin" then
      checkArg(3, args, "number")
      self.login = args

    elseif method == "getlogin" then
      return self.login

    else
      return nil, k.errno.ENOSYS
    end
  end

  function discipline:read(n)
    checkArg(1, n, "number")

    self:flush()

    local current = k.current_process()
    if self.pgroup and current.pgid ~= self.pgroup and
        k.is_pgroup(self.pgroup) then
      current:signal("SIGTTIN", true)
    end

    while #self.rbuf < n do
      coroutine.yield()
      if self.rbuf:find(self.eof, nil, true) and not self.raw then break end
    end

    if self.mode == "line" then
      while (self.rbuf:find(eolpat) or 0) < n do
        coroutine.yield()
        if self.rbuf:find(self.eof, nil, true) and not self.raw then break end
      end
    end

    if not self.raw then
      local eof = self.rbuf:find(self.eof, nil, true)
      n = math.min(n, eof or math.huge)
    end

    local data = self.rbuf:sub(1, n)
    self.rbuf = self.rbuf:sub(#data + 1)

    if not self.raw then
      if data == self.eof then return nil end
      if data:sub(-1) == self.eof then return data:sub(1, -2) end
    end

    return data
  end

  function discipline:write(text)
    checkArg(1, text, "string")

    while self.stopped and #self.wbuf >= @[{bconf.BUFFER_SIZE or 1024}] do
      coroutine.yield()
    end

    self.wbuf = self.wbuf .. text

    local last_eol = self.wbuf:find(eolpat)
    if last_eol then
      local data = self.wbuf:sub(1, last_eol)
      self.wbuf = self.wbuf:sub(#data + 1)
      self.obj:write(data)
    end

    return true
  end

  function discipline:flush()
    if #self.wbuf == 0 then return end
    local data = self.wbuf
    self.wbuf = ""
    self.obj:write(data)
  end

  function discipline:close()
    local proc = k.current_process()
    if proc.tty == self then
      proc.tty = false
    end

    return true
  end

  k.disciplines.tty = discipline
end

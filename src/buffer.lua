--[[
    Stream buffering implementation.
    Copyright (C) 2022 ULOS Developers

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

printk(k.L_INFO, "buffer")

do
  -- this tonumber() is so my LSP will stop yelling at me
  local bufsize = tonumber(k.cmdline["io.bufsize"])
    or tonumber("@[{bconf.BUFFER_SIZE or 512}]")

  local buffer = {}
  local buffers = {}

  -- read a line from the buffer
  function buffer:readline()
    -- slow cop-out for non-buffered streams...
    if self.bufmode == "none" then
      -- ...unless, that is, the stream provides an optimized readline
      -- implementation (e.g. if it does its own buffering).  a TTY,
      -- for example, will generally provide this.
      if self.stream.readline then
        return self.stream:readline()

      else
        -- if it does *not*, then go the slow way.
        -- XXX never use the "l" or "L" format on an unbuffered file stream
        -- XXX unless it points to the TTY, because it will NOT perform well.
        -- (...unless the filesystem driver implements a buffer, in which case
        -- it'd *probably* be fine)
        local dat = ""

        repeat
          local n = self.stream:read(1)
          dat = dat .. (n or "")
        until n == "\n" or not n

        if #dat == 0 then return nil end
        return dat
      end

    else
      -- if we don't have a newline in the buffer, we haven't read a full line,
      -- so just keep reading
      while not self.rbuf:match("\n") do
        local chunk = self.stream:read(bufsize)
        if not chunk then break end

        self.rbuf = self.rbuf .. chunk
      end

      if #self.rbuf == 0 then return nil end

      -- find the first newline in the read buffer;  if there is none, then
      -- return the whole buffer
      local n = self.rbuf:find("\n") or #self.rbuf

      local dat = self.rbuf:sub(1, n)
      self.rbuf = self.rbuf:sub(n + 1)

      return dat
    end
  end

  -- read a number from the stream
  function buffer:readnum()
    local dat = ""

    if self.bufmode == "none" then
      -- this function depends on buffered mode, and will not work when
      -- bufmode="none".  there are ways around this and i'll implement
      -- them if it becomes an issue, but i only see that happening if
      -- e.g. someone needs to use this with a TTY stream.  also they
      -- would probably massively increase code complexity.
      error(
        "bad argument to 'read' (format 'n' not supported in unbuffered mode)",
        0)
    end

    -- this function will happily read an arbitrary amount of whitespace
    -- before getting to the number
    local breakonwhitespace = false
    while true do
      local ch = self:readn(1)

      if not ch then
        -- oh no, we've run out of data
        break
      end

      if ch:match("[%s]") then
        -- if we've already read some number, then
        if breakonwhitespace then
          -- put 'ch' back on the read buffer and break
          self.rbuf = ch .. self.rbuf
          break
        end

      else
        -- we've read a number now, so break on whitespace
        breakonwhitespace = true

        -- this allows reading decimals and hex numbers
        if not tonumber(dat .. ch .. "0") then
          self.rbuf = ch .. self.rbuf
          break
        end

        dat = dat .. ch
      end
    end

    -- return a number :)
    return tonumber(dat)
  end

  -- read a number of bytes from the read buffer
  function buffer:readn(n)
    -- if we don't have enough, then repeatedly concatenate into the
    -- read buffer whatever the file descriptor spits out in order to
    -- have enough data - but if we run out, then just return what we
    -- have
    while #self.rbuf < n do
      local chunk = self.stream:read(n - #self.rbuf)

      -- if we've reached EOF, then
      if not chunk then
        -- return nothing if we've got nothing in the buffer
        if #self.rbuf == 0 then return nil end
        break
      end

      -- add chunk to read buffer
      self.rbuf = self.rbuf .. chunk
    end

    -- deal with math.huge
    n = math.min(n, #self.rbuf)

    -- pop data from beginning of the read buffer
    local data = self.rbuf:sub(1, n)
    self.rbuf = self.rbuf:sub(#data + 1)

    -- return it
    return data
  end

  function buffer:readfmt(fmt)
    if type(fmt) == "number" then
      -- just read this number of bytes
      return self:readn(fmt)

    else
      -- support 5.2-style formats
      fmt = fmt:gsub("%*", "")

      if fmt == "a" then -- read whatever's left
        return self:readn(math.huge)

      elseif fmt == "l" then -- read a line without the trailing newline
        local line = self:readline()
        if not line then return nil end
        return line:gsub("\n$", "")

      elseif fmt == "L" then -- read a line WITH the trailing newline
        return self:readline()

      elseif fmt == "n" then -- read a number
        return self:readnum()

      else -- ???
        error("bad argument to 'read' (format '"..fmt.."' not supported)", 0)
      end
    end
  end

  local function chvarargs(...)
    local args = table.pack(...)

    for i=1, args.n, 1 do
      checkArg(i, args[i], "string", "number")
    end

    return args
  end

  function buffer:read(...)
    local args = chvarargs(...)
    local ret = {}

    for i=1, args.n, 1 do
      ret[#ret+1] = self:readfmt(args[i])
    end

    return table.unpack(ret, 1, args.n)
  end

  function buffer:write(...)
    local args = chvarargs(...)

    for i=1, args.n, 1 do
      self.wbuf = self.wbuf .. tostring(args[i])
    end

    local dat
    if self.bufmode == "full" then
      -- full buffering: write the whole buffer, but only if it's oversize
      if #self.wbuf <= bufsize then
        return self
      end

      dat = self.wbuf
      self.wbuf = ""

    elseif self.bufmode == "line" then
      -- line buffering: write to the last newline
      local lastnl = #self.wbuf - (self.wbuf:reverse():find("\n") or 0)

      dat = self.wbuf:sub(1, lastnl)
      self.wbuf = self.wbuf:sub(lastnl + 1)

    else
      -- no buffering: unconditionally write the whole thing
      dat = self.wbuf
      self.wbuf = ""
    end

    -- write it
    self.stream:write(dat)

    return self
  end

  function buffer:seek(whence, offset)
    checkArg(1, whence, "string", "nil")
    checkArg(2, offset, "number", "nil")

    self:flush()
    if self.stream.seek then
      return self.stream:seek(whence or "cur", offset or 0)
    end

    return nil, k.errno.EBADF
  end

  function buffer:flush()
    if #self.wbuf > 0 then
      self.stream:write(self.wbuf)
      self.wbuf = ""
    end

    if self.stream.flush then
      self.stream:flush()
    end

    return true
  end

  function buffer:close()
    self.closed = true
    buffers[self] = nil
    if self.stream.close then
      self.stream:close()
    end
  end

  local modes = { full = true, line = true, none = true }
  function buffer:ioctl(op, mode, ...)
    checkArg(1, op, "string")

    if op ~= "setvbuf" or (self.stream.proxy
        and self.stream.proxy.override_setvbuf) then

      if self.stream.proxy and self.stream.proxy.ioctl then
        return self.stream.proxy.ioctl(self.stream.fd, op, mode, ...)

      elseif self.stream.ioctl then
        return self.stream.ioctl(self.stream, op, mode, ...)

      else
        return nil, k.errno.ENOSYS
      end
    end

    checkArg(2, mode, "string")
    if not modes[mode] then return nil, k.errno.EINVAL end

    self.bufmode = mode
    return true
  end

  local function split_chars(s)
    local cs = {}
    for c in s:gmatch(".") do cs[c] = true end
    return cs
  end

  function k.buffer_from_stream(stream, mode)
    checkArg(1, stream, "table")
    checkArg(2, mode, "string")

    local buf = setmetatable({
      stream = stream,
      mode = split_chars(mode),
      rbuf = "",
      wbuf = "",
      bufmode = stream.proxy and stream.proxy.override_setvbuf
        and "none" or "full"
    }, {__index = buffer})
    buffers[buf] = true

    return buf
  end

  function k.sync_buffers()
    for buffer in pairs(buffers) do
      buffer:flush()
    end
  end
end

--[[
    File descriptor support code
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

printk(k.L_INFO, "filedesc")

do
  local function fread(self, n)
    if not self.proxy.read then return nil, k.errno.ENOTSUP end
    return self.proxy:read(self.fd, n)
  end

  local function fwrite(self, d)
    if not self.proxy.write then return nil, k.errno.ENOTSUP end
    return self.proxy:write(self.fd, d)
  end

  local function fseek(self, w, o)
    if not self.proxy.seek then return nil, k.errno.ENOTSUP end
    return self.proxy:seek(self.fd, w, o)
  end
  
  local function fflush(self)
    if not self.proxy.flush then return nil, k.errno.ENOTSUP end
    return self.proxy:flush(self.fd)
  end

  local function fclose(self)
    if not self.proxy.close then return nil, k.errno.ENOTSUP end
    return self.proxy:close(self.fd)
  end

  --- Create a buffered file descriptor.
  ---@param proxy table
  ---@param fd number
  ---@param mode string
  ---@overload fun(proxy: table, fd: userdata, mode: string): table
  function k.fd_from_node(proxy, fd, mode)
    checkArg(1, proxy, "table")
    -- ocvm returns userdata rather than a table
    checkArg(2, fd, "table", "userdata")
    checkArg(3, mode, "string")

    local new = k.buffer_from_stream({
      read = fread, write = fwrite, seek = fseek,
      flush = fflush, close = fclose,
      fd = fd, proxy = proxy
    }, mode)

    return new
  end

  local function ebadf()
    return nil, k.errno.EBADF
  end

  --- Create a file descriptor from a reader and/or writer function, with an
  --- optional close function
  ---@param read function TODO: Annotate arguments
  ---@param write function TODO: Annotate arguments
  ---@param close function
  function k.fd_from_rwf(read, write, close)
    checkArg(1, read, "function", write and "nil")
    checkArg(2, write, "function", read and "nil")
    checkArg(3, close, "function", "nil")

    return {
      read = read or ebadf, write = write or ebadf,
      close = close or function() end
    }
  end
end

--[[
  HTTP support
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

printk(k.L_INFO, "net/http")

do
  local protocol = {}

  local request = {}

  function request:read(n)
    local data = self.fd.read(n)
    if not data then
      return nil, k.errno.EBADF
    end
    return data
  end

  function request:write()
    return nil, k.errno.EBADF
  end

  function request:close()
    self.fd.close()
  end

  function protocol.request(parts)
    local http = table.remove(parts, 1)
    local url = http .. "://" .. table.concat(parts, "/")

    local internet = component.list("internet")()
    if not internet then
      return nil, k.errno.ENODEV
    end

    printk(k.L_DEBUG, url)
    local handle, err = component.invoke(internet, "request", url)
    if not handle then
      return nil, k.errno.ENOENT, err
    end

    while not handle.finishConnect() do
      coroutine.yield(0)
    end

    return setmetatable({fd = handle}, {__index = request})
  end

  k.protocols.http = protocol.request
  k.protocols.https = protocol.request
end

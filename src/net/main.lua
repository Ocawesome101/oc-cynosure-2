--[[
  Networking bits
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

printk(k.L_INFO, "net/main")

do
  local hostname = "localhost"
  k.protocols = {}

  function k.gethostname()
    return hostname
  end

  function k.sethostname(name)
    checkArg(1, name, "string")
    hostname = name
    return hostname
  end

  local function separate(path)
    local proto = path:match("([^:/]+)://")
    if not proto then return end

    local segments = { proto }

    for part in path:sub(#proto+3):gmatch("[^/]+") do
      segments[#segments+1] = part
    end

    return segments
  end

  -- Takes a network path and returns a file descriptor.
  -- e.g. request("cnet://4bef8d/ulos/dev/packages/list.upl")
  function k.request(path)
    checkArg(1, path, "string")

    local parts = separate(path)
    if not parts then
      return nil, k.errno.EINVAL
    end

    local protocol = k.protocols[parts[1]]
    if not protocol then
      return nil, k.errno.ENOPROTOOPT
    end

    local request, errno, detail = protocol(parts)
    if not request then
      return nil, errno, detail
    end

    local stream = k.buffer_from_stream(request, "rw")
    return { fd = stream, node = stream, refs = 1 }
  end
end

--@[{depend("HTTP/TCP support", "COMPONENT_INTERNET", "NET_TCP", "NET_HTTP")}]
--@[{depend("Minitel/GERTi support", "COMPONENT_MODEM", "NET_MTEL", "NET_GERT")}]
--@[{includeif("NET_HTTP", "src/net/http.lua")}]
--@[{includeif("NET_TCP", "src/net/tcp.lua")}]
--@[{includeif("NET_MTEL", "src/net/minitel.lua")}]
--@[{includeif("NET_GERT", "src/net/gerti.lua")}]

--[[
  Lua loader
  Copyright (C) 2022 ULOS Developers, Atirut

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

printk(k.L_INFO, "exec/lua")

do
  k.register_executable_format("lua", function(header)--, extension)
    return header:sub(1, 6) == "--!lua"-- or extension == "lua"
  end, function(fd, env, name)
    local data = k.read(fd, math.huge)
    k.close(fd)

    local chunk, err = k.load(data, "="..name, "t", env)
    if not chunk then
      printk(k.L_DEBUG, "load failed - %s", tostring(err))
      return nil, k.errno.ENOEXEC
    end

    return function(args)
      local result = table.pack(xpcall(chunk, debug.traceback, args))

      if not result[1] then
        printk(k.L_NOTICE, "Lua error: %s", result[2])
        k.syscalls.exit(1)

      else
        k.syscalls.exit(0)
      end
    end
  end)
end

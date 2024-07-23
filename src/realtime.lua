--[[
  Get the real-world time from the tmpfs
  Copyright (C) 2023 ULOS Developers

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

printk(k.L_INFO, "realtime")

do
  function k.realtime()
    local tmpfs = component.proxy(computer.tmpAddress())
    tmpfs.close(tmpfs.open("realtime","w"))
    local time = tmpfs.lastModified("realtime")
    tmpfs.remove("realtime")
    return time
  end
end

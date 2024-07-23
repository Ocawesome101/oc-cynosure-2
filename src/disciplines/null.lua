--[[
  null line discipline; just pass data straight through
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

printk(k.L_INFO, "disciplines/null")

do
  local discipline = {}

  function discipline.wrap(obj)
    return setmetatable({obj=obj}, {__index=discipline})
  end

  function discipline:read(n)
    checkArg(1, n, "number")

    if self.obj.read then return self.obj:read(n) end
    return nil, k.errno.ENOSYS
  end

  function discipline:write(data)
    checkArg(1, data, "string")

    if self.obj.write then return self.obj:write(data) end
    return nil, k.errno.ENOSYS
  end

  function discipline:flush() end

  function discipline:close() end

  k.disciplines.null = discipline
end

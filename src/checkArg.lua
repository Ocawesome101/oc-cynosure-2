--[[
    A wrapper for the checkArg function.
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

printk(k.L_INFO, "checkArg")

do
  function _G.checkArg(n, have, ...)
    have = type(have)

    local function check(want, ...)
      if not want then
        return false

      else
        return have == want or check(...)
      end
    end

    if type(n) == "number" then n = string.format("#%d", n)
    else n = "'"..tostring(n).."'" end

    if not check(...) then
      local name = debug.getinfo(3, 'n').name
      local msg

      if name then
         msg = string.format("bad argument %s to '%s' (%s expected, got %s)",
          n, name, table.concat(table.pack(...), " or "), have)

      else
        msg = string.format("bad argument %s (%s expected, got %s)", n,
          table.concat(table.pack(...), " or "), have)
      end

      error(debug.traceback(msg, 2), 2)
    end
  end
end

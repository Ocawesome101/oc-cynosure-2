--[[
    Kernel command line parsing.
    Copyright (C) 2021 ULOS Developers

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

do
  k.cmdline = {}

  local _args = table.pack(...)
  k.original_cmdline = table.concat(_args, " ", 1, _args.n)

  for _, arg in ipairs(_args) do
    local key, val = arg, true
    if arg:find("=") then
      key, val = arg:match("^(.-)=(.+)$")

      if val == "true" then val = true
      elseif val == "false" then val = false
      else val = tonumber(val) or val end
    end

    local ksegs = {}
    for ent in key:gmatch("[^%.]+") do
      ksegs[#ksegs+1] = ent
    end

    local cur = k.cmdline
    for i=1, #ksegs-1, 1 do
      k.cmdline[ksegs[i]] = k.cmdline[ksegs[i]] or {}
      cur = k.cmdline[ksegs[i]]
    end

    cur[ksegs[#ksegs]] = val
  end
end

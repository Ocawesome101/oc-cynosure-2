--[[
    Utilities for working with permissions
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

printk(k.L_INFO, "fs/permissions")

do
  local order = {
    0x001,
    0x002,
    0x004,
    0x008,
    0x010,
    0x020,
    0x040,
    0x080,
    0x100,
  }

  --- Takes a permissions string and returns its bitmap representation.
  --- e.g. rwxr-xr-x
  ---@param permstr string Permissions string in the format output by ls
  function k.perm_string_to_bitmap(permstr)
    checkArg(1, permstr, "string")

    if not permstr:match("[r%-][w%-][x%-][r%-][w%-][x%-][r%-][w%-][x%-]") then
      return nil, k.errno.EINVAL
    end

    local bitmap = 0

    for i=#order, 1, -1 do
      local index = #order - i + 1
      if permstr:sub(index, index) ~= "-" then
        bitmap = (bitmap | order[i])
      end
    end

    return bitmap
  end

  --- Check if the specified owner/group/other has the specified r, w, or x
  --- permission(s) in the provided mode.
  ---@param ogo number Owner=3/Group=2/Other=1
  ---@param mode number The mode (e.g. file mode) to check
  ---@param perm string The combination of "r", "w", or "x" to check
  function k.has_permission(ogo, mode, perm)
    checkArg(1, ogo, "number")
    checkArg(2, mode, "number")
    checkArg(3, perm, "string")

    local val_check = 0

    local base_index = ogo * 3
    for c in perm:gmatch(".") do
      if c == "r" then
        val_check = (val_check | order[base_index])

      elseif c == "w" then
        val_check = (val_check | order[base_index - 1])

      elseif c == "x" then
        val_check = (val_check | order[base_index - 2])
      end
    end

    return (mode & val_check) == val_check
  end

  function k.process_has_permission(proc, stat, perm)
    checkArg(1, proc, "table")
    checkArg(2, stat, "table")
    checkArg(3, perm, "string")

    -- TODO: more fine-grained rules for precisely when root can do certain
    --       things
    if proc.euid == 0 and perm ~= "x" then return true end

    local ogo = (proc.euid == stat.uid and 3) or (proc.egid == stat.gid and 2)
      or 1
    return k.has_permission(ogo, stat.mode, perm)
  end
end

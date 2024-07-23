--[[
  EEPROM block device support
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

printk(k.L_INFO, "blockdev/eeprom")

do
  local present = false

  k.devfs.register_blockdev("eeprom", {
    init = function(addr)
      if not present then
        present = true
        local eeprom = component.proxy(addr)
        local romdata = eeprom.get()
        local romsize = eeprom.getSize()

        return "eeprom", {
          stat = function()
            return {
              dev = -1,
              ino = -1,
              mode = 0x6000 | k.perm_string_to_bitmap("rw-rw----"),
              nlink = 1,
              uid = 0,
              gid = 0,
              rdev = -1,
              size = romsize,
              blksize = 4096,
              atime = 0,
              ctime = 0,
              mtime = 0
            }
          end,

          open = function(_, _, mode)
            local pos = 0
            if mode == "w" then
              romdata = ""
            end
            return {pos = pos, mode = mode}
          end,

          read = function(_, fd, len)
            -- printk(k.L_DEBUG, tostring(fd.pos))
            if fd.pos < romsize then
              local data = romdata:sub(fd.pos+1, math.min(romsize, fd.pos+len))
              fd.pos = fd.pos + len
              return data

            else
              return nil
            end
          end,

          write = function(_, fd, data)
            if fd.mode == "w" then
              romdata = (romdata .. data):sub(1, romsize)
              eeprom.set(romdata)
            end
          end,
        }
      end
    end,

    destroy = function(_)
      if present then
        present = false
        return "eeprom"
      end
    end,
  })
end

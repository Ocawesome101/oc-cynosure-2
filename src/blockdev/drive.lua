--[[
  Unmanaged drive block device support
  Copyright (C) 2022 Ocawesome101, Atirut-W

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

printk(k.L_INFO, "blockdev/drive")

do
  local drives = {}
  local byaddress = {}

  k.devfs.register_blockdev("drive", {
    init = function(addr)
      local index = 0

      while drives[index] do
        index = index + 1
      end

      local letter = string.char(string.byte("a") + index)
      local proxy = component.proxy(addr)
      drives[index] = true
      byaddress[addr] = index

      local size = proxy.getCapacity()

      return ("hd%s"):format(letter), {
        stat = function()
          return {
            dev = -1,
            ino = -1,
            mode = 0x6000 | k.perm_string_to_bitmap("rw-rw----"),
            nlink = 1,
            uid = 0,
            gid = 0,
            rdev = -1,
            size = size,
            blksize = 512,
            atime = 0,
            ctime = 0,
            mtime = 0
          }
        end,

        open = function(_, _, mode)
          return { pos = 0, mode = mode }
        end,

        read = function(_, fd, len)
          if not fd.mode:match("[ra]") then
            return nil, k.errno.EBADF
          end

          if fd.pos < size then
            len = math.min(len, size - fd.pos)
            local offset = fd.pos % 512
            local data = ""

            repeat
              local sectorID = math.ceil((fd.pos+1) / 512)
              local sector = proxy.readSector(sectorID)
              local read = sector:sub(offset, offset+len)
              data = data .. read
              offset = 0
              fd.pos = fd.pos + #read
              len = len - #read
            until len <= 0

            return data
          end
        end,

        write = function(_, fd, data)
          if not fd.mode:match("[wa]") then
            return nil, k.errno.EBADF
          end

          local offset = fd.pos % 512

          repeat
            local sectorID = math.ceil((fd.pos+1) / 512)
            local sector = proxy.readSector(sectorID)
            local write = data:sub(1, 512 - offset)
            data = data:sub(#write + 1)
            if #write == #sector then
              sector = write
            else
              sector = sector:sub(0, offset) .. write ..
                sector:sub(offset + #write)
            end
            proxy.writeSector(sectorID, sector)
          until #data == 0

          return true
        end,

        seek = function(_, fd, whence, offset)
          whence = (whence == "set" and 0) or (whence == "cur" and fd.pos)
              or (whence == "end" and size)
          fd.pos = math.max(0, math.min(size, whence + offset))
          return fd.pos
        end
      }
    end,

    destroy = function(addr)
      local letter = string.char(string.byte("a") + byaddress[addr])
      drives[byaddress[addr]] = nil
      byaddress[addr] = nil
      return ("hd%s"):format(letter)
    end,
  })
end
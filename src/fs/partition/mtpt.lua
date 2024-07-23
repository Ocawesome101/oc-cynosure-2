--[[
  Minitel partition table support
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

printk(k.L_INFO, "fs/partition/mtpt")

do
  local format = "c20c4>I4>I4"
  k.register_partition_type("mtpt", function(drive)
    local sector = drive.readSector(drive.getCapacity()/drive.getSectorSize())
    local meta = {format:unpack(sector)}
    if meta[2] ~= "mtpt" then return end -- invalid, don't continue
    local partitions = {}
    repeat
      sector = sector:sub(33)
      meta = {format:unpack(sector)}
      meta[1] = meta[1]:gsub("\0", "")
      if #meta[1] > 0 then
        partitions[#partitions+1] = {start = meta[3], size = meta[4]}
      end
    until #sector <= 32
    return partitions
  end)
end

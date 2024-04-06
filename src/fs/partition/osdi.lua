--[[
  Open Simple Disk Info partition table support
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

printk(k.L_INFO, "fs/partition/osdi")

do
  local magic = "OSDI\xAA\xAA\x55\x55"
  local format = "<I4I4c8c3c13"
  k.register_partition_type("osdi", function(drive)
    local sector = drive.readSector(1)
    local meta = {format:unpack(sector)}
    -- conditions:
    --  version (start) == 1
    --  size == 0
    --  type == magic
    if meta[1] ~= 1 or meta[2] ~= 0 or meta[3] ~= magic then return end
    local partitions = {}
    repeat
      sector = sector:sub(33)
      meta = {format:unpack(sector)}
      meta[3] = meta[3]:gsub("\0", "")
      meta[5] = meta[5]:gsub("\0", "")
      if #meta[5] > 0 then
        partitions[#partitions+1] = {start=meta[1], size=meta[2]}
      end
    until #sector <= 32
    return partitions
  end)
end

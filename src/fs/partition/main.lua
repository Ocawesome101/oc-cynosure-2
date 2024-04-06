--[[
  Support various partitioning schemes
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

printk(k.L_INFO, "fs/partition/main")

do
  k.partition_types = {}

  function k.register_partition_type(name, reader)
    checkArg(1, name, "string")
    checkArg(2, reader, "function")

    if k.partition_types[name] then
      panic("attempted to double-register partition type " .. name)
    end

    k.partition_types[name] = reader
    return true
  end

  -- take a drive and split it into sub-"drive"s based on partition table
  -- when we read a partition table we need to register the sub-block device
  -- "hdXY" (or "tapeXY" if i ever get around to supporting that) for each
  -- partition
  local drives = {}
  local function read_partitions(drive)
    for name, reader in pairs(k.partition_types) do
      local partitions = reader(drive)
      if partitions then return partitions end
    end
  end

  local function create_subdrive(drive, start, size)
    local sub = {}
    local sector, byte = start, (start - 1) * drive.getSectorSize()
    local byteSize = size * drive.getSectorSize()
    function sub.readSector(n)
      if n < 1 or n > size then
        error("invalid offset, not in a usable sector", 0)
      end
      return drive.readSector(sector + n)
    end
    function sub.writeSector(n, d)
      if n < 1 or n > size then
        error("invalid offset, not in a usable sector", 0)
      end
      return drive.writeSector(sector + n, d)
    end
    function sub.readByte(n)
      if n < 1 or n > byteSize then return 0 end
      return drive.readByte(n + byteOffset)
    end
    function sub.writeByte(n, i)
      if n < 1 or n > byteSize then return 0 end
      return drive.writeByte(n + byteOffset, i)
    end
    sub.getSectorSize = drive.getSectorSize
    function sub.getCapacity()
      return drive.getSectorSize() * size
    end
    sub.type = "drive"
    return sub
  end

  k.devfs.register_device_handler("blkdev",
    function(path, device) -- registrar
      -- only accept 'drive' devices
      -- TODO maybe support tape drives?
      if not device.fs then return end

      local drive = device.fs
      local partitions = read_partitions(drive)
      if (not partitions) or #partitions == 0 then return end

      drives[drive] = {address=device.address,count=#partitions}
      for i=1, #partitions do
        local spec = partitions[i]
        local subdrive = create_subdrive(drive, spec.start, spec.size)
        local _, subdevice = k.devfs.get_blockdev_handlers()
          .drive.init(subdrive, true)
        subdevice.address = device.address..i
        subdevice.type = "blkdev"
        k.devfs.register_device(device.address..i, subdevice)
      end
    end,
    function(path, device) -- deregistrar
      if not device.fs then return end

      local drive = device.fs
      local info = drives[drive]
      if info then
        for i=1, info.count do
          k.devfs.unregister_device(device.address..i)
        end
      end
      drives[drive] = nil
    end)
end

--@[{includeif("PART_OSDI", "src/fs/partition/osdi.lua")}]
--@[{includeif("PART_MTPT", "src/fs/partition/mtpt.lua")}]

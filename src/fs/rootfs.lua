--[[
    Root filesystem detection and mounting
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

printk(k.L_INFO, "fs/rootfs")

do
  -- There are a few methods we can use to find the root filesystem.
  -- 1) Use the provided root= argument. This is the simplest, and prioritized.
  -- 2) Use computer.getBootAddress() if it's available. It might not be.
  -- 3) Use the first available component. This prioritizes filesystem
  --    components.

  local function panic_with_err(dev, err)
    panic("Cannot mount root filesystem from " .. tostring(dev)
      .. ": " .. ((err == k.errno.ENODEV and "No such device") or
      (err == k.errno.EUNATCH and "Protocol driver not attached") or
      "Unknown error " .. tostring(err)))
  end

  local address

  -- Method 1.
  if k.cmdline.root then
    address = k.cmdline.root

  elseif computer.getBootAddress then -- Method 2.
    address = computer.getBootAddress()

  else -- Method 3.
    local mounted

    for addr in component.list("filesystem") do
      if addr ~= computer.tmpAddress() then
        address = addr
        mounted = true
        break
      end
    end

    if not mounted then
      for addr in component.list("drive") do
        address = addr
        break
      end
    end
  end

  if not address then
    panic("No valid root filesystem found")
  end

  -- allow e.g. 523bc4,1
  if address:sub(-2,-2) == "," then
    local addr, part = address:sub(1, -3), address:sub(-1)
    local matches = k.devfs.get_by_type("blkdev")

    for i=1, #matches do
      local match = matches[i]
      if match.device.fs and match.device.fs.address and
          match.device.fs.address:sub(1,#addr) == addr then
        -- e.g. hda2
        address = match.device.address..part
        printk(k.L_NOTICE, "resolved rootfs=%s from %s",
          match.device.address..part, address)
        break
      end
    end
  end

  if address == "mtar" then
    address = k.fstypes.managed(_G.mtarfs)
    _G.mtarfs = nil
  end

  local success, err = k.mount(address, "/")
  if not success then
    panic_with_err((component.type(address) or "unknown").." "..address, err)
  end
end

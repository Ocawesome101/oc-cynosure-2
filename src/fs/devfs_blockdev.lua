--[[
  Block device support
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

printk(k.L_INFO, "fs/devfs_blockdev")

do
  local handlers = {}

  function k.devfs.register_blockdev(devtype, callbacks)
    printk(k.L_DEBUG, "registered block device type %s", devtype)
    handlers[devtype] = callbacks
  end

  function k.devfs.get_blockdev_handlers()
    return handlers
  end

  local function comp_added(_, addr, t)
    printk(k.L_DEBUG, "component_added: %s %s", addr, t)

    if handlers[t] then
      printk(k.L_DEBUG, "intializing device %s", addr)
      local name, device = handlers[t].init(addr)
      device.type = device.type or "blkdev"

      if name then
        k.devfs.register_device(name, device)
      end
    end
  end

  local function comp_removed(_, addr, t)
    printk(k.L_DEBUG, "component_removed: %s %s", addr, t)

    if handlers[t] then
      local name = handlers[t].destroy(addr)
      if name then
        k.devfs.unregister_device(name)
      end
    end
  end

--@[{includeif("COMPONENT_EEPROM", "src/blockdev/eeprom.lua")}]
--@[{includeif("COMPONENT_DRIVE", "src/blockdev/drive.lua")}]

  k.blacklist_signal("component_added")
  k.blacklist_signal("component_removed")

  k.add_signal_handler("component_added", comp_added)
  k.add_signal_handler("component_removed", comp_removed)

  for addr, ctype in component.list() do
    comp_added(nil, addr, ctype)
  end
end

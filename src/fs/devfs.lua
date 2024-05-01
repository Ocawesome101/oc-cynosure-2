--[[
  Device fs implementation
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

--#include "src/fs/wrapper.lua"

printk(k.L_INFO, "fs/devfs")

do
  local provider = {}
  -- A table of path -> node.  Doesn't scale super well for lots
  -- of subdirectories, but better than maintaining an N-deep table,
  -- particularly since it supports sub-pseudo-filesystems e.g.
  -- componentfs - and I don't see large devfs trees being common.
  local devices = {}
  -- Each device type can have one or more "handlers" associated with it.
  -- Each handler must have a register() and deregister() function.
  -- Programs can ioctl() these devices with "reregister" to rerun those
  -- handlers for e.g. if userspace changes a partition table.
  local handlers = {}

  k.devfs = {}

  function k.devfs.register_device_handler(devtype, registrar, deregistrar)
    checkArg(1, devtype, "string")
    checkArg(2, registrar, "function")
    checkArg(3, deregistrar, "function")

    handlers[devtype] = handlers[devtype] or {}
    local id = math.random(0, 999999)
    handlers[devtype][id] = {register = registrar, deregister = deregistrar}

    return id
  end

  function k.devfs.register_device(path, device)
    checkArg(1, path, "string")
    checkArg(2, device, "table")

    local segments = k.split_path(path)
    if #segments > 1 then
      error("cannot register device in subdirectory '"..path.."' of devfs", 2)
    end

    if not device.type then
      printk(k.L_WARNING, "device '%s' has no 'type' field!", path)
      device.type = "unknown"
    end

    devices[path] = device
    if handlers[device.type] then
      for _, handler in pairs(handlers[device.type]) do
        handler.register(path, device)
      end
    end

    if path:sub(1,1) ~= "/" then path = "/" .. path end
    printk(k.L_INFO, "devfs: registered device at %s type=%s", path,
      device.type)
  end

  function k.devfs.unregister_device(path)
    checkArg(1, path, "string")

    local segments = k.split_path(path)
    if #segments > 1 then
      error("cannot unregister device in subdirectory '"..path.."' of devfs", 2)
    end

    devices[path] = nil

    if path:sub(1,1) ~= "/" then path = "/" .. path end
    printk(k.L_INFO, "devfs: unregistered device at %s", path)
  end

  k.devfs.register_device("/", {
    opendir = function()
      local devs = {}
      for k in pairs(devices) do if k ~= "/" then devs[#devs+1] = k end end
      return { devs = devs, i = 0 }
    end,

    readdir = function(_, fd)
      fd.i = fd.i + 1
      if fd.devs and fd.devs[fd.i] then
        return { inode = -1, name = fd.devs[fd.i] }

      else
        fd.devs = nil
      end
    end,

    stat = function()
      return { dev = -1, ino = -1, mode = 0x41ED, nlink = 1,
        uid = 0, gid = 0, rdev = -1, size = 0, blksize = 2048,
        atime = 0, ctime = 0, mtime = 0 }
    end
  })

  local function path_to_node(path)
    local segments = k.split_path(path)

    if path == "/" or path == "" then
      return devices[path]
    end

    if not devices[segments[1]] then
      return nil, k.errno.ENOENT

    else
      return devices[segments[1]], table.concat(segments, "/", 2, segments.n)
    end
  end

  k.devfs.lookup = path_to_node
  -- get devices by type
  function k.devfs.get_by_type(dtype)
    checkArg(1, dtype, "string")
    local matches = {}

    for path, dev in pairs(devices) do
      if dev.type == dtype then
        matches[#matches+1] = {path=path, device=dev}
      end
    end

    return matches
  end

  local function check_fd(fd, dir)
    assert((not not fd.dir) == (not not dir),
      "Bad argument (file descriptor expected)")
  end

  -- The checks for open, opendir, and ioctl are needed to
  -- work properly with the kernel's buffering implementation.
  local fds = {}
  local function autocall(calling, pathorfd, ...)
    if type(pathorfd) == "string" then
      local device, path = path_to_node(pathorfd)

      if not device then return nil, k.errno.ENOENT end
      if not device[calling] then return nil, k.errno.ENOSYS end

      local result, err = device[calling](device, path, ...)

      if not result then return nil, err end

      if result and (calling == "open" or calling == "opendir") then
        return { node = device, fd = result,
          default_mode = result.default_mode }

      else
        return result, err
      end

    else
      if not (pathorfd.node and pathorfd.fd) then
        return nil, k.errno.EBADF
      end

      local device, fd = pathorfd.node, pathorfd.fd

      local result, err
      if calling == "ioctl" and (...) == "reregister" then
        if handlers[device.type] then
          for _, handler in pairs(handlers[device.type]) do
            handler.deregister(path, device)
          end
          for _, handler in pairs(handlers[device.type]) do
            handler.register(path, device)
          end
          result = true
        end
      else
        if not device[calling] then return nil, k.errno.ENOSYS end
        if calling == "ioctl" and not device.is_dev then
          result, err = device[calling](fd, ...)

        else
          result, err = device[calling](device, fd, ...)
        end
      end

      return result, err
    end
  end

  provider.default_mode = "none"

  setmetatable(provider, {__index = function(_, k)
    if k ~= "ioctl" then
      return function(_, ...)
        return autocall(k, ...)
      end

    else
      return function(...)
        return autocall(k, ...)
      end
    end
  end})

  provider.address = "devfs"
  provider.type = "root"

  provider = k.wrap_fs(provider)

  k.register_fstype("devfs", function(x)
    return x == "devfs" and provider
  end)
end

-- include this here because it registers blockdev handlers and
-- devfs/blockdev registers block devices.  alternative is extra logic.
--@[{depend("Partition table support", "COMPONENT_DRIVE", "PART_ENABLE")}]
--@[{includeif("PART_ENABLE", "src/fs/partition/main.lua")}]
--#include "src/fs/devfs_chardev.lua"
--#include "src/fs/devfs_blockdev.lua"

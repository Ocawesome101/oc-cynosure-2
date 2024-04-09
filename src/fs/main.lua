--[[
    Main file system code
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

printk(k.L_INFO, "fs/main")

---@alias fs_recognizer fun(component: table): table
--#include "src/fs/permissions.lua"

do
  ---@type fs_recognizer[]
  k.fstypes = {}

  -- fs mode constants
  k.FS_FIFO   = 0x1000 -- FIFO
  k.FS_CHRDEV = 0x2000 -- character device
  k.FS_DIR    = 0x4000 -- directory
  k.FS_BLKDEV = 0x6000 -- block device
  k.FS_REG    = 0x8000 -- regular file
  k.FS_SYMLNK = 0xA000 -- symbolic link
  k.FS_SOCKET = 0xC000 -- socket

  k.FS_SETUID = 0x0800 -- setuid bit
  k.FS_SETGID = 0x0400 -- setgid bit
  k.FS_STICKY = 0x0200 -- sticky bit

  --- Registers a filesystem type
  ---@param name string
  ---@param recognizer fs_recognizer
  function k.register_fstype(name, recognizer)
    checkArg(1, name, "string")
    checkArg(2, recognizer, "function")

    if k.fstypes[name] then
      panic("attempted to double-register fstype " .. name)
    end

    k.fstypes[name] = recognizer
    return true
  end

  local function recognize_filesystem(component)
    for fstype, recognizer in pairs(k.fstypes) do
      local fs = recognizer(component)
      if fs then fs.mountType = fstype return fs end
    end

    return nil
  end

  local mounts = {}

  function k.split_path(path)
    checkArg(1, path, "string")

    local segments = {}
    for piece in path:gmatch("[^/\\]+") do
      if piece == ".." then
        segments[#segments] = nil

      elseif piece ~= "." then
        segments[#segments+1] = piece
      end
    end

    return segments
  end

  function k.clean_path(path)
    checkArg(1, path, "string")
    return "/" .. table.concat(k.split_path(path), "/")
  end

  function k.check_absolute(path)
    checkArg(1, path, "string")

    if path:sub(1, 1) == "/" then
      return "/" .. table.concat(k.split_path(path), "/")

    else
      local current = k.current_process()
      local cwd = current and current.cwd or "/"
      return "/" .. table.concat(k.split_path(cwd .. "/" .. path),
        "/")

    end
  end

  local function path_to_node(path, symlink, links)
    links = links or 0
    if links > 16 then
      return nil, k.errno.ELOOP
    end
    path = k.check_absolute(path)

    local current = k.current_process()
    if current then
      path = k.clean_path(current.root .. "/" .. path)
    end

    local mnt, rem = "/", path
    for m in pairs(mounts) do
      if path:sub(1, #m) == m and #m > #mnt then
        mnt, rem = m, path:sub(#m+1)
      end
    end

    if #rem == 0 then rem = "/" end

    --printk(k.L_DEBUG, "path_to_node(%s) = %s, %s",
    --  path, tostring(mnt), tostring(rem))

    local node, rem = mounts[mnt], rem or "/"
    if node.islink and not nosymlink then
      local components = k.split_path(rem)
      local _path = node:islink(rem)
      if _path then
        return path_to_node(_path, false, links + 1)
      end
      local segments = k.split_path(rem)
      for i, segment in ipairs(segments) do
        local part = table.concat(segments, "/", 1, i)
        local _path = node:islink(part)
        if _path then
          return path_to_node(_path, false, links + 1)
        end
      end
    end

    return mounts[mnt], rem or "/"
  end

  k.lookup_file = path_to_node

  local default_proc = {euid = 0, gid = 0}
  local function cur_proc()
    return k.current_process and k.current_process() or default_proc
  end

  local empty = {}

  --- Mounts a drive or filesystem at the given path.
  ---@param node table|string The component proxy or address to mount
  ---@param path string The path at which to mount it
  function k.mount(node, path)
    checkArg(1, node, "table", "string")
    checkArg(2, path, "string")

    if cur_proc().euid ~= 0 then return nil, k.errno.EACCES end

    if path ~= "/" then
      local stat = k.stat(path)
      if (not stat) then
        return nil, k.errno.ENOENT

      elseif (stat.mode & 0xF000) ~= 0x4000 then
        return nil, k.errno.ENOTDIR
      end
    end

    path = k.check_absolute(path)
    if mounts[path] then
      return nil, k.errno.EBUSY
    end

    local proxy = node
    if type(node) == "string" then
      if node:find("/", nil, true) then
        local absolute = k.check_absolute(node)
        local node, rem = k.lookup_file(node)
        if (not node) then
          return nil, k.errno.ENOENT
        elseif (node.address ~= "devfs") then
          return nil, k.errno.ENODEV
        end

        local dentry, drem = k.devfs.lookup(rem)

        if (not dentry) then
          return nil, drem
        end

        if dentry.address == "components" then
          local hand, err = dentry:open(drem)
          if not hand then
            return nil, err
          end

          if hand.proxy.type ~= "filesystem" and
              hand.proxy.type ~= "drive" then
            return nil, k.errno.ENOTBLK
          end
          proxy = recognize_filesystem(hand.proxy)

        elseif dentry.type == "blkdev" then
          proxy = dentry.fs
        else
          return nil, k.errno.ENOTBLK
        end

        if proxy then proxy = recognize_filesystem(proxy) end
        if not proxy then return nil, k.errno.EUNATCH end

      else
        node = component.proxy(node) or k.devfs.lookup(node) or node
        if node.type == "blkdev" and node.fs then node = node.fs end
        proxy = recognize_filesystem(node)
        if not proxy then return nil, k.errno.EUNATCH end
      end
    end
    if not node then return nil, k.errno.ENODEV end

    proxy.mountType = proxy.mountType or "managed"

    mounts[path] = proxy

    if proxy.mount then proxy:mount(path) end

    return true
  end

  --- Unmounts something from the given path
  ---@param path string
  function k.unmount(path)
    checkArg(1, path, "string")

    if cur_proc().euid ~= 0 then return nil, k.errno.EACCES end

    path = k.clean_path(path)
    if not mounts[path] then
      return nil, k.errno.EINVAL
    end

    local node = mounts[path]
    if node.unmount then node:unmount(path) end

    mounts[path] = nil
    return true
  end

  local opened = {}

  local function count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
  end

  function k.open(file, mode)
    checkArg(1, file, "string")
    checkArg(2, mode, "string")

    local node, remain = path_to_node(file)
    if not node.open then return nil, k.errno.ENOSYS end

    local exists = node:exists(remain)

    if mode ~= "w" and mode ~= "a" and not exists then
      return nil, k.errno.ENOENT
    end

    local segs = k.split_path(remain)
    local dir = "/" .. table.concat(segs, "/", 1, #segs - 1)
    local base = segs[#segs]

    local stat, err
    if not exists then
      stat, err = node:stat(dir)

    else
      stat, err = node:stat(remain)
    end

    if not stat then
      return nil, err
    end

    if not k.process_has_permission(cur_proc(), stat, mode) then
      return nil, k.errno.EACCES
    end

    local umask = (cur_proc().umask or 0) ~ 511
    local fd, err = node:open(remain, mode, stat.mode & umask)
    if not fd then return nil, err end

    local stream = k.fd_from_node(node, fd, mode)
    if node.default_mode then
      stream:ioctl("setvbuf", node.default_mode)
    end

    if type(fd) == "table" and fd.default_mode then
      stream:ioctl("setvbuf", fd.default_mode)
    end

    local ret = { fd = stream, node = stream, refs = 1 }
    opened[ret] = true
    return ret
  end

  local function verify_fd(fd, dir)
    checkArg(1, fd, "table")

    if not (fd.fd and fd.node) then
      error("bad argument #1 (file descriptor expected)", 2)
    end

    -- Casts both sides to booleans to ensure correctness when comparing
    if (not not fd.dir) ~= (not not dir) then
      error("bad argument #1 (cannot supply dirfd where fd is required, or vice versa)", 2)
    end
  end

  function k.ioctl(fd, op, ...)
    verify_fd(fd)
    checkArg(2, op, "string")

    if op == "setcloexec" then
      fd.cloexec = not not ...
      return true
    end

    if not fd.node.ioctl then return nil, k.errno.ENOSYS end
    return fd.node.ioctl(fd.fd, op, ...)
  end

  function k.read(fd, fmt)
    verify_fd(fd)
    checkArg(2, fmt, "string", "number")

    if not fd.node.read then return nil, k.errno.ENOSYS end
    return fd.node.read(fd.fd, fmt)
  end

  function k.write(fd, data)
    verify_fd(fd)
    checkArg(2, data, "string")

    if not fd.node.write then return nil, k.errno.ENOSYS end
    return fd.node.write(fd.fd, data)
  end

  function k.seek(fd, whence, offset)
    verify_fd(fd)
    checkArg(2, whence, "string")
    checkArg(3, offset, "number")

    return fd.node.seek(fd.fd, whence, offset)
  end

  function k.flush(fd)
    if fd.dir then return end -- cannot flush dirfd
    verify_fd(fd)

    if not fd.node.flush then return nil, k.errno.ENOSYS end
    return fd.node.flush(fd.fd)
  end

  function k.opendir(path)
    checkArg(1, path, "string")

    path = k.check_absolute(path)

    local node, remain = path_to_node(path)
    if not node.opendir then return nil, k.errno.ENOSYS end
    if not node:exists(remain) then return nil, k.errno.ENOENT end

    local stat = node:stat(remain)
    if not k.process_has_permission(cur_proc(), stat, "r") then
      return nil, k.errno.EACCES
    end

    local fd, err = node:opendir(remain)
    if not fd then return nil, err end

    local ret = { fd = fd, node = node, dir = true, refs = 1 }
    opened[ret] = true
    return ret
  end

  function k.readdir(dirfd)
    verify_fd(dirfd, true)
    if not dirfd.node.readdir then return nil, k.errno.ENOSYS end
    return dirfd.node:readdir(dirfd.fd)
  end

  function k.close(fd)
    verify_fd(fd, fd.dir) -- can close either type of fd

    fd.refs = fd.refs - 1
    if fd.node.flush then fd.node:flush(fd.fd) end

    if fd.refs <= 0 then
      opened[fd] = nil
      if not fd.node.close then return nil, k.errno.ENOSYS end
      if fd.dir then return fd.node:close(fd.fd) end
      return fd.node.close(fd.fd)
    end
  end

  local stat_defaults = {
    dev = -1, ino = -1, mode = 0x81FF, nlink = 1,
    uid = 0, gid = 0, rdev = -1, size = 0, blksize = 2048,
    atime = 0, ctime = 0, mtime = 0
  }

  function k.stat(path)
    checkArg(1, path, "string")

    local node, remain = path_to_node(path)
    if not node.stat then return nil, k.errno.ENOSYS end

    local statx, errno = node:stat(remain)
    if not statx then return nil, errno end

    for key, val in pairs(stat_defaults) do
      statx[key] = statx[key] or val
    end

    return statx
  end

  function k.mkdir(path, mode)
    checkArg(1, path, "string")
    checkArg(2, mode, "number", "nil")

    local node, remain = path_to_node(path)
    if not node.mkdir then return nil, k.errno.ENOSYS end
    if node:exists(remain) then return nil, k.errno.EEXIST end

    local segments = k.split_path(remain)
    local parent = "/" .. table.concat(segments, "/", 1, #segments - 1)
    local stat = node:stat(parent)

    if not stat then return nil, k.errno.ENOENT end
    if not k.process_has_permission(cur_proc(), stat, "w") then
      return nil, k.errno.EACCES
    end

    local umask = (cur_proc().umask or 0) ~ 511

    local done, failed = node:mkdir(remain, (mode or stat.mode) & umask)
    if not done then return nil, failed end
    return not not done
  end

  function k.link(source, dest)
    checkArg(1, source, "string")
    checkArg(2, dest, "string")

    local node, sremain = path_to_node(source)
    local _node, dremain = path_to_node(dest)

    if _node ~= node then return nil, k.errno.EXDEV end
    if not node.link then return nil, k.errno.ENOSYS end
    if node:exists(dremain) then return nil, k.errno.EEXIST end

    local segments = k.split_path(dremain)
    local parent = "/" .. table.concat(segments, "/", 1, #segments - 1)
    local stat = node:stat(parent)

    if not k.process_has_permission(cur_proc(), stat, "w") then
      return nil, k.errno.EACCES
    end

    return node:link(sremain, dremain)
  end

  function k.symlink(target, linkpath)
    checkArg(1, target, "string")
    checkArg(2, linkpath, "string")

    local node, remain = path_to_node(file)
    if not node.symlink then return nil, k.errno.ENOSYS end
    if not node:exists(remain) then return nil, k.errno.ENOENT end

    local segs = k.split_path(remain)
    local dir = "/" .. table.concat(segs, "/", 1, #segs - 1)
    local base = segs[#segs]

    local stat, err = node:stat(dir)
    if not stat then
      return nil, err
    end

    if not k.process_has_permission(cur_proc(), stat, mode) then
      return nil, k.errno.EACCES
    end

    local umask = (cur_proc().umask or 0) ~ 511
    return node:symlink(remain, mode, stat.mode & umask)
  end

  function k.unlink(path)
    checkArg(1, path, "string")

    local node, remain = path_to_node(path)
    if not node.unlink then return nil, k.errno.ENOSYS end
    if not node:exists(remain) then return nil, k.errno.ENOENT end

    -- TODO: look at the sticky bit to see exactly what we should do for perms
    -- checks
    local stat = node:stat(remain)

    if not k.process_has_permission(cur_proc(), stat, "w") then
      return nil, k.errno.EACCES
    end

    return node:unlink(remain)
  end

  function k.chmod(path, mode)
    checkArg(1, path, "string")
    checkArg(2, mode, "number")

    local node, remain = path_to_node(path)
    if not node.chmod then return nil, k.errno.ENOSYS end
    if not node:exists(remain) then return nil, k.errno.ENOENT end

    local stat = node:stat(remain)
    if not k.process_has_permission(cur_proc(), stat, "w") then
      return nil, k.errno.EACCES
    end

    -- only preserve the lower 12 bits
    mode = (mode & 0xFFF)
    return node:chmod(remain, mode)
  end

  function k.chown(path, uid, gid)
    checkArg(1, path, "string")
    checkArg(2, uid, "number")
    checkArg(3, gid, "number")

    local node, remain = path_to_node(path)
    if not node.chown then return nil, k.errno.ENOSYS end
    if not node:exists(remain) then return nil, k.errno.ENOENT end

    local stat = node:stat(remain)
    if not k.process_has_permission(cur_proc(), stat, "w") then
      return nil, k.errno.EACCES
    end

    return node:chown(remain, uid, gid)
  end

  function k.mounts()
    return mounts
  end

  function k.sync_fs()
    for _, node in pairs(mounts) do
      if node.sync then node:sync("dummy") end
    end
  end

  k.add_signal_handler("shutdown", function()
    k.sync_buffers()
    k.sync_fs()

    for fd in pairs(opened) do
      fd.refs = 1
      k.close(fd)
    end

    for path in pairs(mounts) do
      k.unmount(path)
    end
  end)
end

--#include "src/fs/devfs.lua"
--@[{depend("Managed filesystem support", "COMPONENT_FILESYSTEM", "FS_MANAGED")}]
--@[{includeif("FS_MANAGED", "src/fs/managed.lua")}]
--@[{depend("SimpleFS support", "COMPONENT_DRIVE", "FS_SFS")}]
--@[{includeif("FS_SFS", "src/fs/simplefs.lua")}]
--#include "src/fs/rootfs.lua"
--#include "src/fs/tty.lua"
--@[{includeif("FS_COMPONENT", "src/fs/component.lua")}]
--@[{includeif("FS_PROC", "src/fs/proc.lua")}]

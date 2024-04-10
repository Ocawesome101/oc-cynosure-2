--[[
    Managed filesystem driver
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

printk(k.L_INFO, "fs/managed")

do
  local _node = {}

  -- file attributes are stored as 'key:value' pairs
  -- these are:
  --  uid:number
  --  gid:number
  --  mode:number
  --  devmaj:number present if file is block/chardev
  --  devmin:number present if file is block/chardev
  --  created:number
  --  symtarget:string present if file is a link

  -- take the attribute file data and return a table
  local function load_attributes(data)
    local attributes = {}

    for line in data:gmatch("[^\n]+") do
      local key, val = line:match("^(.-):(.+)$")
      attributes[key] = tonumber(val)
    end

    return attributes
  end

  -- take a table of attributes and return file data
  local function dump_attributes(attributes)
    local data = ""

    for key, val in pairs(attributes) do
      data = data .. key .. ":" .. math.floor(val) .. "\n"
    end

    return data
  end

  -- Check if a path points to an attribute file
  local function is_attribute(path)
    checkArg(1, path, "string")

    return not not path:match("%.[^/]+%.attr$")
  end

  local function attr_path(path)
    local segments = k.split_path(path)
    if #segments == 0 then return "/.attr" end

    return "/" .. table.concat(segments, "/", 1, #segments - 1) .. "/." ..
      segments[#segments] .. ".attr"
  end

  -- This is an ugly hack that will only work for about 250 years
  -- (specifically, until 2286-11-20 at 12:46:39).  I leave it up
  -- to my successors to fix this, if anybody cares at that point.
  function _node:lastModified(file)
    local last = self.fs.lastModified(file)

    if last > 9999999999 then
      return math.floor(last / 1000)
    end

    return last
  end

  -- get the attributes of a specific file
  function _node:get_attributes(file)
    checkArg(1, file, "string")

    if is_attribute(file) then return nil, k.errno.EACCES end
    local isdir = self.fs.isDirectory(file)

    local fd = self.fs.open(attr_path(file), "r")
    if not fd then
      -- default to root/root, rw-r--r-- permissions
      -- directories: rwxr-xr-x
      return {
        uid = k.syscalls and k.syscalls.geteuid() or 0,
        gid = k.syscalls and k.syscalls.getegid() or 0,
        mode = isdir and 0x41ED or 0x81A4,
        created = self:lastModified(file)
      }
    end

    local data = self.fs.read(fd, 2048)
    self.fs.close(fd)

    local attributes = load_attributes(data or "")
    attributes.uid = attributes.uid or 0
    attributes.gid = attributes.gid or 0
    -- default to root/root, rwxrwxrwx permissions
    attributes.mode = attributes.mode or
      (isdir and 0x4000 or 0x8000) + (0x1FF ~ k.current_process().umask)
    -- fix incorrect directory modes when we find them
    -- checks if
    if (isdir and (attributes.mode & 0x4000 == 0)) then
      --  1) IS a directory and directory bit is NOT set
      attributes.mode = attributes.mode | 0x4000
      if attributes.mode & 0x8000 ~= 0 then
        attributes.mode = attributes.mode ~ 0x8000
      end
    elseif (not isdir) and (attributes.mode & 0x4000 ~= 0) then
      --  2) is NOT a directory and directory bit IS set
      attributes.mode = attributes.mode ~ 0x4000
      if attributes.mode & 0x4000 ~= 0 then
        attributes.mode = attributes.mode ~ 0x4000
      end
    end
    attributes.created = attributes.created or self:lastModified(file)

    return attributes
  end

  -- set the attributes of a specific file
  function _node:set_attributes(file, attributes)
    checkArg(1, file, "string")
    checkArg(2, attributes, "table")

    if is_attribute(file) then return nil, k.errno.EACCES end

    local fd = self.fs.open(attr_path(file), "w")
    if not fd then return nil, k.errno.EROFS end

    self.fs.write(fd, dump_attributes(attributes))
    self.fs.close(fd)
    return true
  end

  --== BEGIN OPTIONAL FILESYSTEM NODE FUNCTIONS ==--

  -- Takes a file path and, if that path is a symbolic link, returns
  -- only the path to which the link points.
  function _node:islink(path)
    checkArg(1, path, "string")
    if is_attribute(path) then return nil, k.errno.EACCES end
    if not self:exists(path) then return nil, k.errno.ENOENT end

    local attributes = self:get_attributes(path)
    if attributes.mode & 0xF000 == k.FS_SYMLNK then
      return attributes.symtarget
    end
  end

  --== BEGIN REQUIRED FILESYSTEM NODE FUNCTIONS ==--

  -- Takes a file path and returns only whether that path exists.  Similar to
  -- stat(), but faster since there's no attribute checking.
  function _node:exists(path)
    checkArg(1, path, "string")
    -- this is a couple lines of code compressed into one.
    return self.fs.exists(path)
  end

  -- Returns attributes about the given file.
  function _node:stat(path)
    checkArg(1, path, "string")

    if is_attribute(path) then return nil, k.errno.EACCES end
    if not self:exists(path) then return nil, k.errno.ENOENT end

    local attributes = self:get_attributes(path)
    -- TODO: populate the 'dev' and 'rdev' fields?
    local stat = {
      dev = -1,
      ino = -1,
      mode = attributes.mode,
      nlink = 1,
      uid = attributes.uid,
      gid = attributes.gid,
      rdev = -1,
      size = self.fs.isDirectory(path) and 512 or self.fs.size(path),
      blksize = 2048,
      ctime = attributes.created,
      atime = math.floor(computer.uptime() * 1000),
      mtime = self:lastModified(path)*1000
    }

    stat.blocks = math.ceil(stat.size / 512)

    return stat
  end

  function _node:chmod(path, mode)
    checkArg(1, path, "string")
    checkArg(2, mode, "number")

    if is_attribute(path) then return nil, k.errno.EACCES end
    if not self:exists(path) then return nil, k.errno.ENOENT end

    local attributes = self:get_attributes(path)
    -- userspace can't change the file type of a file
    attributes.mode = ((attributes.mode & 0xF000) | (mode & 0xFFF))
    return self:set_attributes(path, attributes)
  end

  function _node:chown(path, uid, gid)
    checkArg(1, path, "string")
    checkArg(2, uid, "number")
    checkArg(3, gid, "number")

    if is_attribute(path) then return nil, k.errno.EACCES end
    if not self:exists(path) then return nil, k.errno.ENOENT end

    local attributes = self:get_attributes(path)
    attributes.uid = uid
    attributes.gid = gid

    return self:set_attributes(path, attributes)
  end

  function _node:link()
    -- supporting hard links on managed fs is too much work
    return nil, k.errno.ENOTSUP
  end

  function _node:symlink(target, linkpath, mode)
    checkArg(1, target, "string")
    checkArg(2, linkpath, "string")

    if self:exists(linkpath) then return nil, k.errno.EEXIST end
    self.fs.close(self.fs.open(linkpath, "w"))

    local attributes = {}
    attributes.mode = (k.FS_SYMLNK | (mode & 0xFFF))
    attributes.uid = k.syscalls and k.syscalls.geteuid() or 0
    attributes.gid = k.syscalls and k.syscalls.getegid() or 0
    attributes.symtarget = target
    self:set_attributes(linkpath, attributes)

    return true
  end

  function _node:unlink(path)
    checkArg(1, path, "string")

    if is_attribute(path) then return nil, k.errno.EACCES end
    if not self:exists(path) then return nil, k.errno.ENOENT end

    self.fs.remove(path)
    self.fs.remove(attr_path(path))

    return true
  end

  function _node:mkdir(path, mode)
    checkArg(1, path, "string")
    checkArg(2, mode, "number")

    local result = (not is_attribute(path)) and self.fs.makeDirectory(path)
    if not result then return result end

    local attributes = {}
    attributes.mode = (k.FS_DIR | (mode & 0xFFF))
    attributes.uid = k.syscalls and k.syscalls.geteuid() or 0
    attributes.gid = k.syscalls and k.syscalls.getegid() or 0
    self:set_attributes(path, attributes)

    return result
  end

  function _node:opendir(path)
    checkArg(1, path, "string")

    if is_attribute(path) then return nil, k.errno.EACCES end
    if not self:exists(path) then return nil, k.errno.ENOENT end
    if not self.fs.isDirectory(path) then return nil, k.errno.ENOTDIR end

    local files = self.fs.list(path)
    for i=#files, 1, -1 do
      if is_attribute(files[i]) then table.remove(files, i) end
    end

    return { index = 0, files = files }
  end

  function _node:readdir(dirfd)
    checkArg(1, dirfd, "table")

    if not (dirfd.index and dirfd.files) then
      error("bad argument #1 to 'readdir' (expected dirfd)")
    end

    dirfd.index = dirfd.index + 1
    if dirfd.files and dirfd.files[dirfd.index] then
      return { inode = -1, name = dirfd.files[dirfd.index]:gsub("/", "") }
    end
  end

  function _node:open(path, mode, permissions)
    checkArg(1, path, "string")
    checkArg(2, mode, "string")

    if is_attribute(path) then return nil, k.errno.EACCES end

    if self.fs.isDirectory(path) then
      return nil, k.errno.EISDIR
    end

    local fd = self.fs.open(path, mode)
    if not fd then
      return nil, k.errno.ENOENT
    else
      if mode == "w" then
        local attributes = {}
        attributes.mode = (k.FS_REG | (permissions & 0xFFF))
        attributes.uid = k.syscalls and k.syscalls.geteuid() or 0
        attributes.gid = k.syscalls and k.syscalls.getegid() or 0
        self:set_attributes(path, attributes)
      end
      return fd
    end
  end

  function _node:read(fd, count)
    checkArg(1, fd, "table")
    checkArg(2, count, "number")

    return self.fs.read(fd, count)
  end

  function _node:write(fd, data)
    checkArg(1, fd, "table")
    checkArg(2, data, "string")

    return self.fs.write(fd, data)
  end

  function _node:seek(fd, whence, offset)
    checkArg(1, fd, "table")
    checkArg(2, whence, "string")
    checkArg(3, offset, "number")

    return self.fs.seek(fd, whence, offset)
  end

  -- this function does nothing
  function _node:flush() end

  function _node:close(fd)
    checkArg(1, fd, "table")

    if fd.index then return true end
    return self.fs.close(fd)
  end

  local fs_mt = { __index = _node }

  -- register the filesystem type with the kernel
  k.register_fstype("managed", function(comp)
    if type(comp) == "table" and comp.type == "filesystem" then
      return setmetatable({fs = comp,
        address = comp.address:sub(1,8)}, fs_mt)

    elseif type(comp) == "string" and component.type(comp) == "filesystem" then
      return setmetatable({fs = component.proxy(comp),
        address = comp:sub(1,8)}, fs_mt)
    end
  end)

  k.register_fstype("tmpfs", function(t)
    if t == "tmpfs" then
      local node = k.fstypes.managed(computer.tmpAddress())
      node.address = "tmpfs"
      return node
    end
  end)
end

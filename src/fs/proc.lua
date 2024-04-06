--[[
  procfs
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

printk(k.L_INFO, "fs/proc")

do
  local provider = {}

  local files = {self = true}

  files.meminfo = { data = function()
    local avgfree = 0

    for i=1, 10, 1 do avgfree = avgfree + computer.freeMemory() end
    avgfree = avgfree / 10

    local total, free = math.floor(computer.totalMemory() / 1024),
      math.floor(avgfree / 1024)

    local used = total - free
    return string.format(
      "MemTotal: %d kB\nMemUsed: %d kB\nMemAvailable: %d kB\n",
      total, used, free)
  end }

  files.filesystems = { data = function()
    local result = {}

    for fs, rec in pairs(k.fstypes) do
      if rec(fs) then fs = fs .. " (nodev)" end
      result[#result+1] = fs
    end

    return table.concat(result, "\n") .. "\n"
  end }

  files.cmdline = { data = k.original_cmdline .. "\n" }
  files.uptime = { data = function()
    return tostring(computer.uptime()) .. "\n"
  end }

  files.mounts = { data = function()
    local result = {}
    for path, node in pairs(k.mounts()) do
      result[#result+1] = string.format("%s %s %s", node.address, path,
        node.mountType)
    end

    return table.concat(result, "\n") .. "\n"
  end }

  --@[{includeif("PROCFS_CONFIG", "src/fs/proc_config.lua")}]
  --@[{includeif("PROCFS_EVENT", "src/fs/proc_events.lua")}]
  --@[{includeif("PROCFS_BINFMT", "src/fs/proc_binfmt.lua")}]

  local function path_to_node(path, narrow)
    local segments = k.split_path(path)

    if #segments == 0 then
      local flist = {}

      for _, pid in pairs(k.get_pids()) do
        flist[#flist+1] = pid
      end

      for k in pairs(files) do
        flist[#flist+1] = k
      end

      return flist
    end

    if segments[1] == "self" then
      segments[1] = k.current_process().pid
    end

    -- disallow reading greater than /N/fds/N for security
    if segments[2] == "fds" then
      if #segments > 3 then
        return nil, k.errno.ENOENT

      elseif #segments == 3 then
        if narrow == 1 then return nil, k.errno.ENOTDIR end
      end
    end

    if files[segments[1]] then
      if narrow == 1 then return nil, k.errno.ENOTDIR end

      if #segments > 1 then return nil, k.errno.ENOENT end
      return files[segments[1]], nil, true

    elseif tonumber(segments[1]) then
      local proc = k.get_process(tonumber(segments[1]))
      local field = proc

      for i=2, #segments, 1 do
        field = field[tonumber(segments[i]) or segments[i]]
        if field == nil then return nil, k.errno.ENOENT end
      end

      return field, proc
    end

    return nil, k.errno.ENOENT
  end

  function provider:exists(path)
    checkArg(1, path, "string")
    return path_to_node(path) ~= nil
  end

  function provider:stat(path)
    checkArg(1, path, "string")

    local node, proc, isf = path_to_node(path)
    if node == nil then return nil, proc end

    if type(node) == "table" and not isf then
      return {
        dev = -1, ino = -1, mode = 0x41A4, nlink = 1, uid = 0, gid = 0,
        rdev = -1, size = 0, blksize = 2048
      }
    end

    return {
      dev = -1, ino = -1, mode = 0x61A4, nlink = 1,
      uid = proc and proc.uid or 0, gid = proc and proc.gid or 0,
      rdev = -1, size = 0, blksize = 2048
    }
  end

  local function to_fd(dat)
    dat = tostring(dat)
    local idx = 0

    return k.fd_from_rwf(function(_, n)
      local nidx = math.min(#dat + 1, idx + n)
      local chunk = dat:sub(idx, nidx)
      idx = nidx
      return #chunk > 0 and chunk
    end)
  end

  function provider:open(path)
    checkArg(1, path, "string")

    local node, proc = path_to_node(path, 0)
    if node == nil then return nil, proc end

    if (not proc) and type(node) == "table" and node.data then
      local data = type(node.data) == "function" and node.data() or node.data
      return { file = to_fd(data), ioctl = node.ioctl }

    elseif type(node) ~= "table" then
      return { file = to_fd(node), ioctl = function()end }

    else
      return nil, k.errno.EISDIR
    end
  end

  function provider:opendir(path)
    checkArg(1, path, "string")

    local node, proc = path_to_node(path, 1)
    if node == nil then return nil, proc end

    if type(node) == "table" then
      if not proc then return { i = 0, files = node } end

      local flist = {}

      for k in pairs(node) do
        flist[#flist+1] = tostring(k)
      end

      return { i = 0, files = flist }

    else
      return nil, k.errno.ENOTDIR
    end
  end

  function provider:readdir(dirfd)
    checkArg(1, dirfd, "table")

    if dirfd.closed then return nil, k.errno.EBADF end
    if not (dirfd.i and dirfd.files) then return nil, k.errno.EBADF end

    dirfd.i = dirfd.i + 1

    if dirfd.files[dirfd.i] then
      return { inode = -1, name = tostring(dirfd.files[dirfd.i]) }
    end
  end

  function provider:read(fd, n)
    checkArg(1, fd, "table")
    checkArg(1, n, "number")

    if fd.closed then return nil, k.errno.EBADF end
    if not fd.file then return nil, k.errno.EBADF end

    return fd.file:read(n)
  end

  function provider:close(fd)
    checkArg(1, fd, "table")
    fd.closed = true
  end

  function provider.ioctl(fd, method, ...)
    checkArg(1, fd, "table")
    checkArg(2, method, "string")

    if fd.closed then return nil, k.errno.EBADF end
    if not fd.file then return nil, k.errno.EBADF end
    if not fd.ioctl then return nil, k.errno.ENOSYS end

    return fd.ioctl(method, ...)
  end

  provider.address = "procfs"

  k.register_fstype("procfs", function(x)
    return x == "procfs" and provider
  end)
end

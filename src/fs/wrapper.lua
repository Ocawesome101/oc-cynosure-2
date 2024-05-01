--[[
  Wrap old filesystem APIs (pre-a2a6e899) to match the new one
  Copyright (C) 2024 ULOS Developers

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

printk(k.L_INFO, "fs/wrapper")

do
  local _wrapper = {}

  function k.wrap_fs(provider)
    printk(k.L_INFO, "Wrapping filesystem provider '%s'", provider.type)
    local wrapper = setmetatable({}, {__index = provider})

    local fds = {}
    local function check_fd(fd, dir)
      assert(fds[fd] and (not not fd.dir) == (not not dir),
        "Bad argument (file descriptor expected)")
    end

    local function wrap_fd(fd, path, dir)
      local wf = {dir = dir, fd = fd, path = path}
      fds[wf] = true
      return wf
    end

    function wrapper:open_root()
      return wrap_fd(provider:opendir("/"), "/", true)
    end

    -- fstat, fstatat: Returns attributes about the given file.
    function wrapper:fstat(fd)
      check_fd(fd, fd.dir)
      return provider:stat(fd.path)
    end

    function wrapper:fstatat(dfd, name)
      check_fd(dfd, true)
      checkArg(2, name, "string")

      local path = dfd.path.."/"..name
      return provider:stat(path)
    end

    -- fchmod, fchmodat: Change file mode
    function wrapper:fchmod(fd, mode)
      check_fd(fd, fd.dir)
      checkArg(2, mode, "number")

      return provider:chmod(fd.path, mode)
    end

    function wrapper:fchmodat(dfd, name, mode)
      check_fd(dfd, true)
      checkArg(2, name, "string")
      checkArg(3, mode, "number")

      return provider:chmod(dfd.path.."/"..name, mode)
    end

    function wrapper:fchown(fd, uid, gid)
      check_fd(fd, fd.dir)
      checkArg(2, uid, "number")
      checkArg(3, gid, "number")
      return provider:chown(fd.path, uid, gid)
    end

    function wrapper:fchownat(dfd, name, uid, gid)
      check_fd(dfd, true)
      checkArg(2, name, "string")
      checkArg(3, uid, "number")
      checkArg(4, gid, "number")
      return provider:chown(dfd.path.."/"..name, uid, gid)
    end

    function wrapper:linkat()
      -- TODO: hard links?
      return nil, k.errno.ENOTSUP
    end

    -- symlinkat: Create symbolic links
    function wrapper:symlinkat(tdfd, tname, ldfd, lname, mode)
      check_dirfd(tdfd)
      checkArg(2, tname, "string")
      check_dirfd(ldfd, 3)
      checkArg(4, lname, "string")
      checkArg(5, mode, "number")

      return provider:symlink(
        tdfd.path.."/"..tname,
        ldfd.path.."/"..lname, mode)
    end

    -- unlinkat: Unlink files
   function wrapper:unlinkat(dfd, name)
      check_fd(dfd, true)
      checkArg(2, name, "string")

      return provider:unlink(dfd.path.."/"..name)
    end

    -- mkdirat: Create a directory
   function wrapper:mkdirat(dfd, name, mode)
      check_fd(dfd, true)
      checkArg(2, name, "string")
      checkArg(3, mode, "number")

      return provider:mkdir(dfd.path.."/"..name, mode)
    end

    -- readlinkat: Read symbolic link
    function wrapper:readlinkat(dfd, name)
      check_fd(dfd, true)
      checkArg(2, name, "string")

      local path = dfd.path.."/"..name
      return provider:readlink(path)
    end

    -- opendirat: Open a directory
   function wrapper:opendirat(dfd, name)
      check_fd(dfd, true)
      checkArg(2, name, "string")
  
      local path = dfd.path.."/"..name
      return wrap_fd(provider:opendir(path), path, true)
    end

    function wrapper:readdir(dfd)
      check_fd(dfd, true)

      dfd.index = dfd.index + 1
      if dfd.files and dfd.files[dfd.index] then
        return { inode = -1, name = dfd.files[dfd.index]:gsub("/", "") }
      end
    end

    -- openat, read, write, seek, flush, close: file I/O
    function wrapper:openat(dfd, name, mode, permissions)
      check_fd(dfd, true)
      checkArg(2, name, "string")
      checkArg(3, mode, "string")

      local path = dfd.path.."/"..name
      return wrap_fd(provider:open(path, mode, permissions), path, false)
    end

    function wrapper:read(fd, count)
      check_fd(fd, false)
      checkArg(2, count, "number")

      return provider:read(fd.fd, count)
    end

    function wrapper:write(fd, data)
      check_fd(fd, false)
      checkArg(2, data, "string")

      return provider:write(fd.fd, data)
    end

    function wrapper:seek(fd, whence, offset)
      check_fd(fd, false)
      checkArg(2, whence, "string")
      checkArg(3, offset, "number")

      return provider:seek(fd.fd, whence, offset)
    end

    function wrapper:flush(fd)
      check_fd(fd, false)
      return provider:flush(fd.fd)
    end

    function wrapper:close(fd)
      check_fd(fd, fd.dir)
      fds[fd] = nil
      provider:close(fd.fd)
    end

    return wrapper
  end
end

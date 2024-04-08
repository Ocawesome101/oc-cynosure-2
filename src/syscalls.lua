--[[
    Provides core system calls
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
--- System calls.
-- @module syscalls
-- @alias k.syscalls

printk(k.L_INFO, "syscalls")

do
  k.syscalls = {}

  function k.perform_system_call(name, ...)
    checkArg(1, name, "string")

    if not k.syscalls[name] then
      return nil, k.errno.ENOSYS
    end

    local result = table.pack(pcall(k.syscalls[name], ...))

    --[[ Uncomment for debugging purposes.
    local args = {}
    for _, arg in ipairs(table.pack(...)) do
      if type(arg) == "string" then
        args[#args+1] = string.format("%q",
          arg:gsub("\n", "\\n"):gsub("\t", "\\t"))
      else
        args[#args+1] = tostring(arg)
      end
    end
    local current = k.current_process()
    --
if current.pid ~= 1 then
      local a, b
      if result[1] then
        a, b = result[2], result[3]
      else
        a, b = result[1], result[2]
      end

      printk(k.L_DEBUG, "%s[%d]: syscall %s(%s) => %s, %s", current.cmdline[0],
        current.pid, name, table.concat(args, ", "),
        (type(a) == "string" and string.format("%q", a) or tostring(a)):gsub("\n", "n"),
        (type(b) == "string" and string.format("%q", b) or tostring(b)):gsub("\n", "n"))
    --
end
    --]]
    return table.unpack(result, result[1] and 2 or 1, result.n)
  end

  --[[
  -- Also for debugging!
  function k.profile(name, func, ...)
    local mem = computer.freeMemory()
    local result = table.pack(func(...))
    local used = mem - computer.freeMemory()
    printk(k.L_DEBUG, "%s() used %d bytes - %d free", name, used, computer.freeMemory())
    return table.unpack(result, 1, result.n)
  end--]]

  ------
  -- This page contains all the system calls available under Cynosure 2.  Wrapper functions with identical functionality are provided by the `syscalls` library.
  -- All system calls return `nil` and an errno value on failure.
  -- System calls are made using `coroutine.yield` like this: `coroutine.yield("syscall", "isatty", 2)`.

  --- Open a file with the given mode.
  -- Returns a file descriptor.
  -- @function open
  -- @tparam string file The file to open
  -- @tparam string mode The mode, similar to those given to `io`
  -- @treturn number The file descriptor
  function k.syscalls.open(file, mode)
    checkArg(1, file, "string")
    checkArg(2, mode, "string")

    local fd, err = k.open(file, mode)
    if not fd then
      return nil, err
    end

    local current = k.current_process()
    local n = #current.fds + 1
    current.fds[n] = fd

    return n
  end

  if k.request then
    --- Request a given network path.
    -- Uses any protocol supported by the kernel.  Returns a file descriptor.
    -- Paths must be standard URLs, i.e. `https://example.com/404.html` or `mtel://upm/packages/list`
    -- @function request
    -- @tparam string path The path to request
    -- @treturn number The file descriptor
    function k.syscalls.request(path)
      checkArg(1, path, "string")

      local fd, err, detail = k.request(path)
      if not fd then
        return nil, err, detail
      end

      local current = k.current_process()
      local n = #current.fds + 1
      current.fds[n] = fd

      return n
    end
  end

  --- Perform some operation on a file descriptor.
  -- Not all file descriptors support all ioctls.
  -- @function ioctl
  -- @tparam number fd The file descriptor
  -- @tparam string operation The operation to perform
  -- @tparam any ... Any remaining arguments
  function k.syscalls.ioctl(fd, operation, ...)
    checkArg(1, fd, "number")
    checkArg(2, operation, "string")

    local current = k.current_process()
    if current.fds[fd] and current.fds[fd].refs <= 0 then
      current.fds[fd] = nil
    end

    if not current.fds[fd] then
      return nil, k.errno.EBADF
    end

    return k.ioctl(current.fds[fd], operation, ...)
  end

  --- Read some data from a file descriptor.
  -- Returns the data that was read.  Any format valid for `io` is valid when passed to this function.
  -- @function read
  -- @tparam number fd The file descriptor
  -- @tparam string|number fmt The format to use when reading
  -- @treturn string The data that was read
  function k.syscalls.read(fd, fmt)
    checkArg(1, fd, "number")
    checkArg(2, fmt, "string", "number")

    local current = k.current_process()
    if current.fds[fd] and current.fds[fd].refs <= 0 and not current.fds[fd].pipe then
      current.fds[fd] = nil
    end

    if not current.fds[fd] then
      return nil, k.errno.EBADF
    end

    return k.read(current.fds[fd], fmt)
  end

  --- Write some data to a file descriptor.
  -- @function write
  -- @tparam number fd The file descriptor
  -- @tparam string data The data to write
  -- @treturn boolean Whether the operation succeeded
  function k.syscalls.write(fd, data)
    checkArg(1, fd, "number")
    checkArg(2, data, "string")

    local current = k.current_process()
    if current.fds[fd] and current.fds[fd].refs <= 0 then
      current.fds[fd] = nil
    end

    if not current.fds[fd] then
      return nil, k.errno.EBADF
    end

    local ok, err = k.write(current.fds[fd], data)
    return not not ok, err
  end

  --- Seek to some position in a given file relative to the start position.
  -- Returns the new position.  Not all file descriptors support this.
  -- @function seek
  -- @tparam number fd The file descriptor
  -- @tparam string whence Where to start
  -- @tparam offset number|nil The offset to seek
  -- @treturn number The new position
  function k.syscalls.seek(fd, whence, offset)
    checkArg(1, fd, "number")
    checkArg(2, whence, "string")
    checkArg(3, offset, "number", "nil")

    local current = k.current_process()
    if current.fds[fd] and current.fds[fd].refs <= 0 then
      current.fds[fd] = nil
    end

    if not current.fds[fd] then
      return nil, k.errno.EBADF
    end

    return k.seek(current.fds[fd], whence, offset or 0)
  end

  --- Flush read and write buffers.
  -- Only does something on some file descriptors, and then only if the file descriptor is buffered.
  -- @function flush
  -- @tparam number fd The file descriptor
  function k.syscalls.flush(fd)
    checkArg(1, fd, "number")

    local current = k.current_process()
    if current.fds[fd] and current.fds[fd].refs <= 0 then
      current.fds[fd] = nil
    end

    if not current.fds[fd] then
      return nil, k.errno.EBADF
    end

    return k.flush(current.fds[fd])
  end

  --- Open a directory.
  -- Opens the given directory for reading and returns a directory descriptor.
  -- @function opendir
  -- @tparam string file The directory to open
  -- @treturn number The resulting directory descriptor
  function k.syscalls.opendir(file)
    checkArg(1, file, "string")

    local fd, err = k.opendir(file)
    if not fd then return nil, err end

    local current = k.current_process()
    local n = #current.fds + 1
    current.fds[n] = fd

    return n
  end

  --- Read from a directory.
  -- @function readdir
  -- @tparam number fd The directory descriptor
  -- @treturn table @{dirent}
  function k.syscalls.readdir(fd)
    checkArg(1, fd, "number")

    local current = k.current_process()
    if current.fds[fd] and current.fds[fd].refs <= 0 then
      current.fds[fd] = nil
    end

    if not current.fds[fd] then
      return nil, k.errno.EBADF
    end

    return k.readdir(current.fds[fd])
  end

  ------
  -- Returned by @{readdir}.
  -- @tfield number inode The inode on which the file is stored
  -- @tfield string name The name of the file
  -- @table dirent

  --- Close a file or directory descriptor.
  -- @function close
  -- @tparam number fd The file descriptor
  function k.syscalls.close(fd)
    checkArg(1, fd, "number")

    local current = k.current_process()
    if not current.fds[fd] then
      return nil, k.errno.EBADF
    end

    k.close(current.fds[fd])

    if current.fds[fd] and current.fds[fd].refs <= 0 then
      current.fds[fd] = nil
    end

    return true, not current.fds[fd]
  end

  --- Check if a file descriptor refers to a TTY.
  -- @function isatty
  -- @tparam number fd The file descriptor
  -- @treturn boolean Whether the file descriptor is a TTY
  function k.syscalls.isatty(fd)
    checkArg(1, fd, "number")

    local current = k.current_process()
    if current.fds[fd] and current.fds[fd].refs <= 0 then
      current.fds[fd] = nil
    end

    if not current.fds[fd] then
      return nil, k.errno.EBADF
    end

    local fdt = current.fds[fd]
    return not not (
      fdt.fd.stream and
      fdt.fd.stream.proxy and
      fdt.fd.stream.proxy.eofpat
    )
  end

  --- Duplicate a file descriptor.
  -- Returns the new file descriptor.
  -- @function dup
  -- @tparam number fd The descriptor to duplicate
  -- @treturn number The new file descriptor
  function k.syscalls.dup(fd)
    checkArg(1, fd, "number")

    local current = k.current_process()
    if current.fds[fd] and current.fds[fd].refs <= 0 then
      current.fds[fd] = nil
    end

    if not current.fds[fd] then
      return nil, k.errno.EBADF
    end

    local nfd = #current.fds + 1
    current.fds[nfd] = current.fds[fd]
    current.fds[fd].refs = current.fds[fd].refs + 1

    return nfd
  end

  --- Duplicate a file descriptor to the given new one.
  -- Returns the new file descriptor.  If the provided new file descriptor exists and is open, it will be silently closed.
  -- @function dup2
  -- @tparam number fd The file descriptor to duplicate
  -- @tparam number nfd The new file descriptor
  -- @treturn number The new file descriptor
  function k.syscalls.dup2(fd, nfd)
    checkArg(1, fd, "number")
    checkArg(2, nfd, "number")

    local current = k.current_process()
    if current.fds[fd] and current.fds[fd].refs <= 0 then
      current.fds[fd] = nil
    end

    if not current.fds[fd] then
      return nil, k.errno.EBADF
    end

    if fd == nfd then return nfd end

    if current.fds[nfd] then
      k.syscalls.close(nfd)
    end

    current.fds[nfd] = current.fds[fd]
    current.fds[fd].refs = current.fds[fd].refs + 1

    return nfd
  end

  --- Create a directory.
  -- @function mkdir
  -- @tparam string path The directory to create
  -- @tparam number mode The permissions to set on it
  k.syscalls.mkdir = k.mkdir

  --- Returns some information about a file.
  -- @function stat
  -- @tparam string path The file to query
  -- @treturn @{statx} The information
  k.syscalls.stat = k.stat

  ------
  -- The information returned by @{stat}.
  -- @tfield number ino The inode on which the file is located
  -- @tfield number mode The POSIX file mode (type and permissions)
  -- @tfield number nlink How many times the file's inode is referenced (hard linked)
  -- @tfield number uid The user ID of the file's owner
  -- @tfield number gid The group ID of the file's owner
  -- @tfield number size The file size in bytes
  -- @tfield number blksize The block size used for file I/O
  -- @tfield number atime File access time
  -- @tfield number ctime File creation time
  -- @tfield number mtime File modification time
  -- @table statx

  --- Create a hard link.
  -- Not supported by any filesystems at this time.
  -- @function link
  -- @tparam string source The source file
  -- @tparam string dest The location of the new link
  k.syscalls.link = k.link

  --- Create a symbolic link.
  -- Presently only supported by managed filesystems.
  -- @function symlink
  -- @tparam string target The link target
  -- @tparam string linkpath The path to the new link
  k.syscalls.symlink = k.symlink

  --- Remove a link.
  -- Removes the file when its link count reaches 0.
  -- @function unlink
  -- @tparam string path The file to unlink
  k.syscalls.unlink = k.unlink

  --- Change file permissions.
  -- Takes a standard POSIX file mode and applies the permissions to the given file.
  -- @function chmod
  -- @tparam string path The file to modify
  -- @tparam number mode The mode to set
  k.syscalls.chmod = k.chmod

  --- Change a file's owner.
  -- Changes the `uid` and `gid` fields for the given file.
  -- @function chown
  -- @tparam string path The file to modify
  -- @tparam number uid The new owning UID
  -- @tparam number gid The new owning GID
  k.syscalls.chown = k.chown

  --- Change the process's root directory.
  -- This behaves very similarly to chroot(2).  Only root may do this.
  -- @function chroot
  -- @tparam string path The new root path.
  function k.syscalls.chroot(path)
    checkArg(1, path, "string")

    if k.current_process().euid ~= 0 then
      return nil, k.errno.EPERM
    end

    local clean = k.check_absolute(path)
    local stat, err = k.stat(clean)

    if not stat then
      return nil, err

    elseif (stat.mode & 0xF000) ~= 0x4000 then
      return nil, k.errno.ENOTDIR
    end

    clean = k.clean_path(k.current_process().root .. "/" .. clean)

    k.current_process().root = clean .. "/"

    return true
  end

  --- Mount a filesystem.
  -- The given directory must exist or the operation will fail.
  -- @function mount
  -- @tparam table|string node The filesystem node
  -- @tparam string path The path at which to mount it
  k.syscalls.mount = k.mount

  --- Unmount a filesystem.
  -- @function unmount
  -- @tparam string path The path to unmount
  k.syscalls.unmount = k.unmount

  --- Flush all open file buffers and filesystem metadata
  -- @function sync
  function k.syscalls.sync()
    k.sync_buffers()
    k.sync_fs()
    return true
  end


  -- Process-related system calls --

  --- Create a new process.
  -- This function creates a new process from the given function.  Its behavior is nonstandard due to Lua limitations.
  -- @function fork
  -- @tparam function func The function to use
  -- @treturn number The PID of the new process
  function k.syscalls.fork(func)
    checkArg(1, func, "function")

    local proc = k.get_process(k.add_process())
    proc:add_thread(k.thread_from_function(func))

    return proc.pid
  end

  --- Replace the current process.
  -- Takes the path to an executable file and loads it as a replacement for the current process.
  -- @function execve
  -- @tparam string path The executable to load
  -- @tparam table args Any arguments to pass
  -- @tparam[opt] table env Environment variables, if any
  function k.syscalls.execve(path, args, env)
    checkArg(1, path, "string")
    checkArg(2, args, "table")
    checkArg(3, env, "table", "nil")

    args[0] = args[0] or path

    local current = k.current_process()

    local func, err = k.load_executable(path, current.env)
    if not func then return nil, err end

    local stat = k.stat(path)
    if (stat.mode & k.FS_SETUID) ~= 0 then
      current.euid = stat.uid
      current.suid = stat.uid
    end

    if (stat.mode & k.FS_SETGID) ~= 0 then
      current.egid = stat.egid
      current.sgid = stat.egid
    end

    current.threads = {}
    current.thread_count = 0
    current.environ = env or current.environ
    current.cmdline = args

    current:add_thread(k.thread_from_function(function()
      return func(args)
    end))

    for f, v in pairs(current.fds) do
      if f > 2 and v.cloexec then
        k.close(v)
        v.refs = v.refs - 1
        current.fds[k] = nil
      end
    end

    coroutine.yield()

    return true
  end

  --- Wait for a process.
  -- If a process has exited, it will not be removed until @{wait} is called on it.
  -- @function wait
  -- @tparam number pid The process ID for which to wait
  -- @tparam[opt] boolean nohang Whether to block while waiting
  -- @tparam[opt] boolean untraced Whether to report stopped children, not just dead ones
  -- @treturn string The exit reason
  -- @treturn number The exit status
  function k.syscalls.wait(pid, nohang, untraced)
    checkArg(1, pid, "number")
    checkArg(2, nohang, "boolean", "nil")
    checkArg(3, untraced, "boolean", "nil")

    if not k.get_process(pid) then
      return nil, k.errno.ESRCH
    end

    if k.get_process(pid).ppid ~= k.current_process().pid then
      return nil, k.errno.ECHILD
    end

    local process = k.get_process(pid)
    if not ((process.stopped and untraced) or nohang or process.is_dead) then
      repeat
        local sig, id = coroutine.yield()
      until ((sig == "proc_stopped" and untraced) or sig == "proc_dead") and id == pid
    end
    if process.stopped and untraced then
      return "stopped", proc.status
    end

    local reason, status = process.reason, process.status or 0

    if k.cmdline.log_process_deaths then
      printk(k.L_DEBUG, "process died: %d, %s, %d", pid, reason, status or 0)
    end

    k.remove_process(pid)

    return reason, status
  end

  --- Wait for any child process.
  -- Optionally blocks.  Otherwise returns immediately if there are no child processes that have not been waited for.
  -- @function waitany
  -- @tparam[opt] boolean block Whether to block indefinitely while waiting
  -- @tparam[opt] boolean untraced Whether to report stopped children
  -- @treturn number The PID of the process that was waited for
  -- @treturn string The exit reason
  -- @treturn number The exit status
  function k.syscalls.waitany(block, untraced)
    checkArg(1, block, "boolean", "nil")
    checkArg(2, untraced, "boolean", "nil")

    local cur = k.current_process().pid
    repeat
      for _, pid in ipairs(k.get_pids()) do
        local process = k.get_process(pid)
        if process.is_dead and process.ppid == cur then
          return pid, k.syscalls.wait(pid)
        end
      end

      if block then
        repeat
          local sig = coroutine.yield()
        until sig == "proc_dead"
      end
    until not block

    return nil
  end

  --- Terminate the current process.
  -- Takes an exit status, which is returned to the parent from a call to @{wait}.
  -- @function exit
  -- @tparam number status The exit status to use
  function k.syscalls.exit(status)
    checkArg(1, status, "number")

    local current = k.current_process()
    current.status = status
    current.threads = {}
    current.thread_count = 0
    current.is_dead = true

    coroutine.yield()
  end

  --- Get the current working directory.
  -- @function getcwd
  -- @treturn string The current process's working directory
  function k.syscalls.getcwd()
    return k.current_process().cwd
  end

  --- Set the current process's working directory.
  -- Does nothing if the given path does not exist.  The given path may be relative.
  -- @function chdir
  -- @tparam string path The new working directory
  function k.syscalls.chdir(path)
    checkArg(1, path, "string")
    path = k.check_absolute(path)

    local stat, err = k.stat(path)
    if not stat then
      return nil, err
    end

    if (stat.mode & 0xF000) ~= k.FS_DIR then
      return nil, k.errno.ENOTDIR
    end

    local current = k.current_process()
    current.cwd = path

    return true
  end

  --- Modify the current process's identity.
  -- @see setuid(2)
  -- @function setuid
  -- @tparam number uid The new user ID
  function k.syscalls.setuid(uid)
    checkArg(1, uid, "number")

    local current = k.current_process()
    if current.euid == 0 then
      current.suid = uid
      current.euid = uid
      current.uid = uid
      return true

    elseif uid==current.uid or uid==current.euid or uid==current.suid then
      current.euid = uid
      return true

    else
      return nil, k.errno.EPERM
    end
  end

  --- Modify the current process's identity.
  -- @see seteuid(2)
  -- @function seteuid
  -- @tparam number uid The new user ID
  function k.syscalls.seteuid(uid)
    checkArg(1, uid, "number")

    local current = k.current_process()
    if current.euid == 0 then
      current.euid = uid
      current.suid = 0

    elseif uid==current.uid or uid==current.euid or uid==current.suid then
      current.euid = uid

    else
      return nil, k.errno.EPERM
    end
  end

  --- Get the current process's user ID.
  -- @function getuid
  -- @treturn number The user ID
  function k.syscalls.getuid()
    local cur = k.current_process()
    return cur and cur.uid or 0
  end

  --- Get the current process's effective user ID.
  -- @function geteuid
  -- @treturn number The effective user ID
  function k.syscalls.geteuid()
    local cur = k.current_process()
    return cur and cur.euid or 0
  end

  --- Modify the current process's identity.
  -- @see setgid(2)
  -- @function setgid
  -- @tparam number uid The new group ID
  function k.syscalls.setgid(gid)
    checkArg(1, gid, "number")

    local current = k.current_process()
    if current.egid == 0 then
      current.sgid = gid
      current.egid = gid
      current.gid = gid

    elseif gid==current.gid or gid==current.egid or gid==current.sgid then
      current.egid = gid

    else
      return nil, k.errno.EPERM
    end
  end

  --- Modify the current process's identity.
  -- @see setegid(2)
  -- @function setegid
  -- @tparam number uid The new group ID
  function k.syscalls.setegid(gid)
    checkArg(1, gid, "number")

    local current = k.current_process()
    if current.egid == 0 then
      current.sgid = gid
      current.egid = gid

    elseif gid==current.gid or gid==current.egid or gid==current.sgid then
      current.egid = gid

    else
      return nil, k.errno.EPERM
    end
  end

  --- Get the current process's group ID.
  -- @function getgid
  -- @treturn number The group ID
  function k.syscalls.getgid()
    local cur = k.current_process()
    return cur and cur.gid or 0
  end

  --- Get the current process's effective group ID.
  -- @function getegid
  -- @treturn number The effective group ID
  function k.syscalls.getegid()
    local cur = k.current_process()
    return cur and cur.egid or 0
  end

  --- Get the ID of the current process.
  -- @function getpid
  -- @treturn number The process's ID
  function k.syscalls.getpid()
    return k.current_process().pid
  end

  --- Get the parent PID of the current process.
  -- @function getpid
  -- @treturn number The parent PID
  function k.syscalls.getppid()
    return k.current_process().ppid
  end

  --- Set the session ID of the current process.
  -- Does not work if the current process is the leader of its process group.
  -- @function setsid
  -- @treturn number The new session ID
  function k.syscalls.setsid()
    local current = k.current_process()

    if current.pgid == current.pid then
      return nil, k.errno.EPERM
    end

    current.pgid = current.pid
    current.sid = current.pid

    if current.tty then
      current.tty.session = current.sid
      current.tty.pgroup = current.pgid
    end

    return current.sid
  end

  --- Get the session ID of a process.
  -- @function getsid
  -- @tparam[opt] number pid The process to query
  -- @treturn number The session ID of the process
  function k.syscalls.getsid(pid)
    checkArg(1, pid, "number", "nil")

    if pid == 0 or not pid then
      return k.current_process().sid
    end

    local proc = k.get_process(pid)
    if not proc then
      return nil, k.errno.ESRCH
    end

    return proc.sid
  end

  --- Set a process's process group.
  -- A PID of 0 will affect the current process.  A process group ID of 0 will use the current process's ID.
  -- @function setpgrp
  -- @tparam number pid The process to modify
  -- @tparam number pg The process group ID
  function k.syscalls.setpgrp(pid, pg)
    checkArg(1, pid, "number")
    checkArg(2, pg, "number")

    local current = k.current_process()
    if pid == 0 then pid = current.pid end
    if pg  == 0 then pg  = pid end
    local proc = k.get_process(pid)

    if proc.pid ~= current.pid and proc.ppid ~= current.pid then
      return nil, k.errno.EPERM
    end

    if pg ~= proc.pid and not k.is_pgroup(pg) then
      return nil, k.errno.EPERM
    end

    if k.is_pgroup(pg) and k.pgroup_sid(pg) ~= proc.sid then
      return nil, k.errno.EPERM
    end

    proc.pgid = pg

    return true
  end

  --- Get the process group of a process.
  -- @function getpgrp
  -- @tparam[opt] number pid The process ID to query
  -- @treturn number The process group ID of that process
  function k.syscalls.getpgrp(pid)
    checkArg(1, pid, "number", "nil")

    if pid == 0 or not pid then
      return k.current_process().pgid
    end

    local proc = k.get_process(pid)
    if not proc then
      return nil, k.errno.ESRCH
    end

    return proc.pgid
  end

  k.syscalls.setpgid = k.syscalls.setpgrp
  k.syscalls.getpgid = k.syscalls.getpgrp

  -- Handlers of signals whose value here is 'false' can't be
  -- overwritten, but those signals can still be sent by kill(2).
  local valid_signals = {
    SIGHUP  = true,
    SIGINT  = true,
    SIGQUIT = true,
    SIGKILL = false,
    SIGPIPE = true,
    SIGTERM = true,
    SIGCONT = false,
    SIGTSTP = true,
    SIGSTOP = false,
    SIGTTIN = true,
    SIGTTOU = true
  }

  --- Set a handler for some POSIX signal.
  -- Signals are represented by their constant names rather than by numbers.
  -- If `handler` is not provided the signal handler will be reset.
  -- @function sigaction
  -- @tparam string name The signal name
  -- @tparam[opt] handler function The handler function to set
  function k.syscalls.sigaction(name, handler)
    checkArg(1, name, "string")
    checkArg(2, handler, "function", "nil")

    if not valid_signals[name] then return nil, k.errno.EINVAL end

    local current = k.current_process()

    printk(k.L_DEBUG, "%d (%s): replacing signal handler for %s with %s",
      current.pid, current.cmdline[0], name, tostring(handler))

    local old = current.signal_handlers[name]
    current.signal_handlers[name] = handler or k.default_signal_handlers[name]

    return old
  end

  --- Signal a process.
  -- Differs from the standard slightly: SIGEXIST, rather than 0, is used to check if a process exists - since signals don't have numeric IDs under Cynosure 2.
  -- If `pid` is positive, the given signal is sent to that process.
  -- If `pid` is `0`, the signal is sent to every process in the process group of the current process.
  -- If `pid` is `-1`, the signal is sent to every process the calling process has permission to signal.
  -- If `pid` is negative, the signal is sent to every process in the process group whose id is `abs(pid)`.
  -- @function kill
  -- @tparam number pid What to kill
  -- @tparam string name The signal to send
  function k.syscalls.kill(pid, name)
    checkArg(1, pid, "number")
    checkArg(2, name, "string")

    local current = k.current_process()

    local pids
    if pid > 0 then
      pids = {pid}

    elseif pid == 0 then
      pids = k.pgroup_pids(current.pgid)

    elseif pid == -1 then
      pids = k.get_pids()

    elseif pid < -1 then
      if not k.is_pgroup(-pid) then
        return nil, k.errno.ESRCH
      end

      pids = k.pgroup_pids(-pid)
    end

    if valid_signals[name] == nil and name ~= "SIGEXIST" then
      return nil, k.errno.EINVAL
    end

    local signaled = 0

    for i=1, #pids, 1 do
      local proc = k.get_process(pids[i])

      if (not proc) and #pids == 1 then
        return nil, k.errno.ESRCH

      else
        if current.uid == 0 or current.euid == 0 or current.uid == proc.uid or
            current.euid == proc.uid or current.uid == proc.suid or
            current.euid == proc.suid then
          signaled = signaled + 1

          if name ~= "SIGEXIST" then
            table.insert(proc.sigqueue, name)
          end
        end
      end
    end

    if signaled == 0 then
      return nil, k.errno.EPERM
    end

    return true
  end


  -- Networking system calls --

  --- Get the system hostname.
  -- @function gethostname
  -- @treturn string The hostname
  function k.syscalls.gethostname()
    return k.gethostname and k.gethostname() or
      "@[{bconf.DEFAULT_HOSTNAME or 'localhost'}]"
  end

  --- Set the system hostname.
  -- @function sethostname
  -- @tparam string name The new hostname
  function k.syscalls.sethostname(name)
    checkArg(1, name, "string")
    return k.sethostname and k.sethostname(name)
  end


  -- Miscellaneous system calls --

  --- Get the process environment.
  -- Returns the current process's environment table.
  -- @function environ
  -- @treturn table The environment
  function k.syscalls.environ()
    return k.current_process().environ
  end

  --- Set the umask.
  -- Only uses the permissions bits.  Returns the previous umask.
  -- @function umask
  -- @tparam number num The new umask
  -- @treturn number The old umask
  function k.syscalls.umask(num)
    checkArg(1, num, "number")

    local cur = k.current_process()
    local old = cur.umask

    if tonumber(num) then
      cur.umask = (math.floor(num) & 511)
    end

    return old
  end

  --- Create a pipe.
  -- Returns a pair of file descriptors.
  -- @function pipe
  -- @treturn number The read end
  -- @treturn number The write end
  function k.syscalls.pipe()
    local buf = ""
    local closed = false

    local instream = k.fd_from_rwf(function(_, _, n)
      while #buf < n and not closed do coroutine.yield(0) end
      local data = buf:sub(1, math.min(n, #buf))
      buf = buf:sub(#data + 1)

      if #data == 0 and closed then
        k.syscalls.kill(0, "SIGPIPE")
        return nil, k.errno.EBADF
      end

      return data
    end, nil, function() closed = true end)

    local outstream = k.fd_from_rwf(nil, function(_, _, data)
      if closed then
        k.syscalls.kill(0, "SIGPIPE")
        return nil, k.errno.EBADF
      end

      buf = buf .. data
      return true
    end, function() closed = true end)

    local into, outof = k.fd_from_node(instream, instream, "r"),
      k.fd_from_node(outstream, outstream, "w")

    into:ioctl("setvbuf", "none")
    outof:ioctl("setvbuf", "none")

    local current = k.current_process()

    local infd = #current.fds + 1
    current.fds[infd] = { fd = into, node = into, refs = 1, pipe = true }

    local outfd = #current.fds + 1
    current.fds[outfd] = { fd = outof, node = outof, refs = 1, pipe = true }

    return infd, outfd
  end

  --- Restart the system.
  -- Does not function unless the effective user ID is 0 (root).
  -- The given action must be one of: `halt`, `poweroff`, `reboot`
  -- @function reboot
  -- @tparam string cmd The action to perform
  function k.syscalls.reboot(cmd)
    checkArg(1, cmd, "string")

    if k.current_process().euid ~= 0 then
      return nil, k.errno.EPERM
    end

    if cmd == "halt" then
      k.shutdown()
      printk(k.L_SYSTEM, "System halted.")

      while true do
        computer.pullSignal()
      end

    elseif cmd == "poweroff" then
      printk(k.L_SYSTEM, "Power down.")
      k.shutdown()
      computer.shutdown()

    elseif cmd == "restart" then
      printk(k.L_SYSTEM, "Restarting system.")
      k.shutdown()
      computer.shutdown(true)
    end

    return nil, k.errno.EINVAL
  end

  --- Return some system information.
  -- @function uname
  -- @treturn @{unameinfo} The system information
  function k.syscalls.uname()
    return {
      sysname = "Cynosure",
      nodename = k.syscalls.gethostname() or "localhost",
      release = "$[{lua scripts/version.lua}]",
      version = "@[{os.date('%Y-%m-%d')}]",
      machine = "oc-".._VERSION:match("Lua (.+)")
    }
  end

  ------
  -- Table containing system information.
  -- @tfield string sysname The system name
  -- @tfield string nodename The nodename (hostname)
  -- @tfield string release The kernel release
  -- @tfield string version The day this kernel was built
  -- @tfield string machine The machine the kernel is running on
  -- @table unameinfo

  --- Return the system uptime.
  -- @function uptime
  -- @treturn number The uptime
  function k.syscalls.uptime()
    return computer.uptime()
  end

  local saved_loglevel
  --- Perform some action on the system log.
  -- All actions except `read_all` and `log` require root.  Valid `action`s are:
  --
  -- - `read`: Wait until there are messages in the kernel log buffer, then read up to `second` of them and clear the read ones.
  -- - `read_all`: Read all messages currently in the log buffer.
  -- - `read_clear`: Read and clear all messages currently in the log buffer.
  -- - `clear`: Clear all messages currently in the log buffer.
  -- - `console_off`: Saves the current loglevel, then sets the loglevel to 1.
  -- - `console_on`: Either restores the saved loglevel, or sets the loglevel to 7.
  -- - `console_level`: Sets the console loglevel to anywhere between 1 and 8, inclusive.  `second` will be silently constrained to this range.
  -- - `log`: Write a message to the system log using `second` as the loglevel and `format` + any remaining arguments as arguments to `printk`
  -- @function klogctl
  -- @tparam string action What to do
  -- @tparam string|number second The second argument
  -- @tparam[opt] string format Format to use for `log`
  -- @treturn[1] table The read log messages in an array
  -- @treturn[2] boolean If the write operation succeeded
  function k.syscalls.klogctl(action, second, format, ...)
    checkArg(1, action, "string")
    local ret = {}

    if k.current_process().euid ~= 0 and action ~= "read_all" then
      return nil, k.errno.EPERM
    end

    if action == "read" then
      checkArg(2, second, "number")
      while #k.log_buffer == 0 do coroutine.yield() end

      for i=1, second, 1 do
        ret[i] = table.remove(k.log_buffer, i)
      end

    elseif action == "read_all" then
      for i=1, #k.log_buffer, 1 do
        ret[i] = k.log_buffer[i]
      end

    elseif action == "read_clear" then
      for i=1, #k.log_buffer, 1 do
        ret[i] = k.log_buffer[i]
        k.log_buffer[i] = nil
      end

    elseif action == "clear" then
      for i=1, #k.log_buffer, 1 do
        k.log_buffer[i] = nil
      end

    elseif action == "console_off" then
      saved_loglevel = saved_loglevel or k.cmdline.loglevel
      k.cmdline.loglevel = 1

    elseif action == "console_on" then
      k.cmdline.loglevel = saved_loglevel or 7
      saved_loglevel = nil

    elseif action == "console_level" then
      checkArg(2, second, "number")
      k.cmdline.loglevel = math.max(1, math.min(8, second))

    elseif action == "log" then
      checkArg(2, second, "number")
      checkArg(3, format, "string")

      printk(math.max(1, math.min(8, second)), format, ...)

      return true

    else
      return nil, k.errno.EINVAL
    end

    return ret
  end
end

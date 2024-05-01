--[[
    Main process implementation
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

printk(k.L_INFO, "scheduler/process")

do
  local sigtonum = {
    SIGEXIST  = 0,
    SIGHUP    = 1,
    SIGINT    = 2,
    SIGQUIT   = 3,
    SIGKILL   = 9,
    SIGPIPE   = 13,
    SIGTERM   = 15,
    SIGCHLD   = 17,
    SIGCONT   = 18,
    SIGSTOP   = 19,
    SIGTSTP   = 20,
    SIGTTIN   = 21,
    SIGTTOU   = 22
  }

  k.sigtonum = {}
  for key,v in pairs(sigtonum) do
    k.sigtonum[key] = v
    k.sigtonum[v] = key
  end

  -- Default signal handlers
  k.default_signal_handlers = setmetatable({
    SIGTSTP = function(p)
      p.stopped = true
    end,

    SIGSTOP = function(p)
      p.stopped = true
    end,

    SIGCONT = function(p)
      p.stopped = false
    end,

    SIGTTIN = function(p)
      printk(k.L_DEBUG, "process %d (%s) got SIGTTIN", p.pid, p.cmdline[0])
      p.stopped = true
    end,

    SIGTTOU = function(p)
      printk(k.L_DEBUG, "process %d (%s) got SIGTTOU", p.pid, p.cmdline[0])
      p.stopped = true
    end}, {__index = function(t, sig)
      t[sig] = function(p)
        p.threads = {}
        p.thread_count = 0
      end

      return t[sig]
    end})


  -- Much of the heavy lifting is done in scheduler/thread.lua in
  -- thread:resume().  The process's job is to act like a mini-scheduler of
  -- sorts.
  local process = {}
  local default = {n = 0}

  function process:resume(sig, ...)
    -- We handle user-provided signals this way because otherwise
    -- a signal handler calling exit() would make the sending process
    -- exit, not the receiving one.  And we handle them here because
    -- otherwise processes wouldn't respond to SIGCONT.
    while #self.sigqueue > 0 do
      local psig = table.remove(self.sigqueue, 1)
      if sigtonum[psig] then
        self.status = sigtonum[psig]
        self:signal(psig)
      end
    end

    if self.stopped then return end

    sig = table.pack(sig, ...)

    local resumed = false
    if sig and #sig > 0 and #self.queue < 256 then
      self.queue[#self.queue + 1] = sig
    end

    local signal = default
    if #self.queue > 0 then
      signal = table.remove(self.queue, 1)

    elseif self:deadline() > computer.uptime() then
      return
    end

    for i, thread in pairs(self.threads) do
      self.current_thread = i
      local result = thread:resume(table.unpack(signal, 1, signal.n))
      resumed = resumed or not not result

      if result == 1 then
        self.threads[i] = nil
        self.thread_count = self.thread_count - 1
        table.insert(self.queue, {"thread_died", i})
      end
    end

    return resumed
  end

  function process:add_thread(thread)
    self.threads[self.pid + self.thread_count] = thread
    self.thread_count = self.thread_count + 1
  end

  function process:deadline()
    local deadline = math.huge
    for _, thread in pairs(self.threads) do
      if thread.deadline < deadline then
        deadline = thread.deadline
      end

      if thread.status == "y" then
        return -1
      end

      if thread.status == "w" and #self.queue > 0 then
        return -1
      end
    end

    return deadline
  end

  function process:signal(sig, imm)
    if self.signal_handlers[sig] then
      printk(k.L_DEBUG, "%d: using custom signal handler for %s", self.pid, sig)
      pcall(self.signal_handlers[sig], sigtonum[sig])

    else
      printk(k.L_DEBUG, "%d: using default signal handler for %s", self.pid, sig)
      pcall(k.default_signal_handlers[sig], self)
    end

    if self.thread_count == 0 then
      self.reason = "signal"
    end

    if imm and (self.stopped or self.thread_count == 0) then
      coroutine.yield(0)
    end
  end

  local process_mt = { __index = process }

  local default_parent = {handles = {}, _G = {}, pid = 0,
    environ = {TERM = "cynosure-2"}}

  local function t(T) return type(T) == "table" end

  -- check for fds[n].fd.stream.fd.fd.fd)
  -- no, i can't be bothered to figure out why it goes that deep
  local function istty(T)
    return T and T.fd and t(T.fd.stream) and T.fd.stream.fd and
      T.fd.stream.fd.fd and T.fd.stream.fd.fd.fd
  end

  function k.create_process(pid, parent)
    parent = parent or default_parent

    local root = parent.root
    if not root then
      local err
      root, err = k.opendir("/")
      if not root then
        panic("could not open rootfs: " .. err)
      end
    end

    local new = setmetatable({
      -- local event queue
      queue = {},
      -- whether this process is stopped
      stopped = false,
      -- all the threads
      threads = {},
      -- how many threads?
      thread_count = 0,
      -- which thread?
      current_thread = 0,

      -- command line
      cmdline = {[0]=parent.cmdline and parent.cmdline[0] or "nil"},

      -- exit status
      status = 0,

      -- exit reason
      reason = "exit",

      -- process ID
      pid = pid,
      -- parent process ID
      ppid = parent.pid,

      -- process group ID
      pgid = parent.pgid or 0,
      -- session ID
      sid = parent.sid or 0,

      -- real user ID
      uid = parent.uid or 0,
      -- real group ID
      gid = parent.gid or 0,
      -- effective user/group ID
      euid = parent.euid or 0,
      egid = parent.egid or 0,
      -- saved user/group ID
      suid = parent.uid or 0,
      sgid = parent.gid or 0,

      -- working directory
      cwd = parent.cwd or root,
      -- root directory
      root = parent.root or root,

      -- file descriptors
      fds = {},

      -- event handler IDs
      handlers = {},

      -- signal handler IDs
      signal_handlers = {},

      -- signal queue
      sigqueue = {},

      -- environment
      env = k.create_env(parent.env),

      umask = parent.umask or 0,

      -- environment variables (e.g. $TERM)
      environ = setmetatable({}, {__index=parent.environ,
        __pairs = function(tab)
          local t = {}
          for k, v in pairs(parent.environ) do
            t[k] = v
          end

          for k,v in next, tab, nil do
            t[k] = v
          end

          return next, t, nil
        end, __metatable = {}})
    }, process_mt)

    -- file descriptors are shared across fork(2), but not across execve(2)
    -- (except file descriptors 0, 1, and 2, or if a file descriptor's cloexec
    -- flag is set through the ioctl(2) call "setcloexec")
    if parent.fds then
      for k, v in pairs(parent.fds) do
        new.fds[k] = v
        v.refs = v.refs + 1
      end
    end

    local e, o, i = new.fds[0], new.fds[1], new.fds[2]
    new.tty = istty(i) or istty(o) or istty(e)

    return new
  end
end

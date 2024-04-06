--[[
    Thread implementation
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

printk(k.L_INFO, "scheduler/thread")

do
  -- This is the string returned from coroutine.resume when a thread is
  -- forcibly yielded.
  -- It is also what the preemption function is named when it is injected into
  -- user programs;  the random name prevents programs from overwriting it and
  -- breaking the forced yield system.  Or, at least, it greatly increases the
  -- effort required to do so.
  local sysyield_string = ""

  for i=1, math.random(3, 5), 1 do
    sysyield_string = sysyield_string .. string.format("%02x",
      math.random(0, 255))
  end

  local function rand_char()
    local area = math.random(1, 3)
    if area == 1 then -- number
      return string.char(math.random(48, 57))

    elseif area == 2 then -- uppercase letter
      return string.char(math.random(65, 90))

    elseif area == 3 then -- lowercase letter
      return string.char(math.random(97, 122))
    end
  end

  -- Add some alphanumeric characters
  for i=1, math.random(3, 5), 1 do
    sysyield_string = sysyield_string .. rand_char()
  end

  k.sysyield_string = sysyield_string

  -- Now for the actual thread implementation.
  -- A thread can have a few different states:
  --  * [r]unning
  --  * [w]aiting (the thread is waiting for a signal, or for a timeout)
  --  * [s]topped (got SIGSTOP)
  --  * [y]ielded (forcibly pre-empted)
  -- Each thread maintains a queue of signals up to 256 items long.
  local thread = {}

  function thread:resume(sig, ...)
    if sig and #self.queue < 256 then
      table.insert(self.queue, table.pack(sig, ...))
    end

    local resume_args

    -- if we were forcibly yielded, we do *not* pass anything to .resume().
    -- if status is "w", then only resume if either the timeout has been
    -- exceeded or there is a signal in the queue.
    if self.status == "w" then
      if computer.uptime() <= self.deadline and #self.queue == 0 then return end

      if #self.queue > 0 then
        resume_args = table.remove(self.queue, 1)
      end

    -- if status is "s", then don't resume, ever, until the status is no longer
    -- "s".  See thread:stop() and thread:continue().
    elseif self.status == "s" then
      return false
    end

    local result
    self.status = "r"

    if resume_args then
      result = table.pack(coroutine.resume(self.coro, table.unpack(resume_args,
        1, resume_args.n)))

    else
      result = table.pack(coroutine.resume(self.coro))
    end

    -- first return is a boolean, we don't need that
    if type(result[1]) == "boolean" then
      table.remove(result, 1)
      result.n = result.n - 1
    end

    if coroutine.status(self.coro) == "dead" then
      if k.cmdline.log_process_deaths then
        printk(k.L_DEBUG, "thread died: %s", result[1])
      end

      return 1
    end

    -- the coroutine can return one of a couple of things:
    --  * the randomized "sysyield" string generated at runtime, indicating a
    --    forced yield, e.g.: "4b2cda328f92c82e34a8tj2bvksdp30fasd"
    --  * a number, to wait either for a signal or until that much time has
    --    elapsed.
    --  * nothing, to wait indefinitely for a signal
    -- The if/else chain here isn't ordered quite like that for speed reasons.
    if result[1] == sysyield_string then
      self.status = "y"

    elseif result.n == 0 then
      self.deadline = math.huge
      self.status = "w"

    elseif type(result[1]) == "number" then
      self.deadline = computer.uptime() + result[1]
      self.status = "w"

    else
      self.deadline = math.huge
      self.status = "w"
    end

    -- yes, we did resume the thread
    return true
  end

  local thread_mt = { __index = thread }

  -- Create a thread from a function
  function k.thread_from_function(func)
    checkArg(1, func, "function")

    return setmetatable({
      coro = coroutine.create(func),
      queue = {},
      status = "w",
      deadline = 0, -- make sure it gets resumed at least once
    }, thread_mt)
  end
end

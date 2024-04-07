--[[
    Simple scheduler main loop
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

printk(k.L_INFO, "scheduler/loop")

do
  local processes = {}
  local pid = 0
  local current = 0

  -- return whether the given session ID exists
  function k.is_sid(id)
    return not not (processes[id] and processes[id].sid == id)
  end

  -- return whether the given process group exists (i.e. has a leader)
  function k.is_pgroup(id)
    return not not (processes[id] and processes[id].pgid == id)
  end

  -- return all the PIDs in a process group
  function k.pgroup_pids(id)
    local result = {}
    if not k.is_pgroup(id) then return result end

    for pid, proc in pairs(processes) do
      if proc.pgid == id then
        result[#result+1] = pid
      end
    end
    return result
  end

  -- return the session ID associated with a process group
  function k.pgroup_sid(id)
    if k.is_pgroup(id) then
      return processes[id].sid
    end

    return 0
  end

  function collectgarbage()
    local missed = {}

    for i=1, 10, 1 do
      local sig = table.pack(computer.pullSignal(0.05))
      if sig.n > 0 then missed[#missed+1] = sig end
    end

    for i=1, #missed, 1 do
      computer.pushSignal(table.unpack(missed[i], 1, missed[i].n))
    end
  end

  --[[
    Scheduler main loop:
      * Go through all processes and find their deadlines.
      * If one of the deadlines is -1 (the process needs to
        be resumed immediately for maximum responsiveness),
        then we resume it if we can.  If it has been more
        than 4 seconds since the last yield, we pullSignal(0)
        first.  This is for maximum responsiveness during
        pre-emption and system calls.
      * For yielding, we pull a signal and resume processes
        with it.
  --]]
  local default = {n=0}
  function k.scheduler_loop()
    local last_yield = 0

    while processes[1] do
      local deadline = math.huge
      for _, process in pairs(processes) do
        local proc_deadline = process:deadline()

        if proc_deadline < deadline then
          deadline = proc_deadline
          if deadline < 0 then break end
        end
      end

      local signal = default
      if deadline < 0 then
        if computer.uptime() - last_yield > 4 then
          last_yield = computer.uptime()
          signal = table.pack(k.pullSignal(0))
        end

      else
        last_yield = computer.uptime()
        signal = table.pack(k.pullSignal(deadline - computer.uptime()))
      end

      for cpid, process in pairs(processes) do
        if not process.is_dead then
          current = cpid
          local stop = process.stopped

          if computer.uptime() >= process:deadline() or #signal > 0 then
            process:resume(table.unpack(signal, 1, signal.n))
            if not next(process.threads) then
              process.is_dead = true

              -- close all open files
              for _, fd in pairs(process.fds) do
                k.close(fd)
              end

              -- remove all signal handlers
              for id in pairs(process.handlers) do
                k.remove_signal_handler(id)
              end

              -- queue event to parent
              table.insert(processes[process.ppid].queue, {"proc_dead", cpid})
            end
          end

          if stop ~= process.stopped then
            -- queue event to parent
            table.insert(processes[process.ppid].queue, {"proc_stopped", cpid})
          end

        else
          if not processes[process.ppid] then
            process.ppid = 1
          end
        end
      end

      -- if less than MEM_THRESHOLD memory free, collect some garbage
      if computer.freeMemory() < @[{bconf.MEM_THRESHOLD or 1024}] then
        printk(k.L_DEBUG, "low free memory - collecting garbage")
        collectgarbage()
      end
    end
  end

  function k.add_process()
    pid = pid + 1
    processes[pid] = k.create_process(pid, processes[current])
    return pid
  end

  function k.current_process()
    return processes[current]
  end

  function k.get_process(rpid)
    checkArg(1, rpid, "number")
    return processes[rpid]
  end

  function k.remove_process(pid)
    checkArg(1, pid, "number")
    processes[pid] = nil
    return true
  end

  function k.get_pids()
    local procs = {}
    for ppid in pairs(processes) do
      procs[#procs + 1] = ppid
    end
    return procs
  end
end

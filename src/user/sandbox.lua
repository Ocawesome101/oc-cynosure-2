--[[
    Sandboxing
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

printk(k.L_INFO, "user/sandbox")

do
  -- from https://lua-users.org/wiki/CopyTable
  local function deepcopy(orig, copies)
    copies = copies or {}
    local orig_type = type(orig)
    local copy

    if orig_type == 'table' then
      if copies[orig] then
        copy = copies[orig]

      else
        copy = {}
        copies[orig] = copy

        for orig_key, orig_value in next, orig, nil do
          copy[deepcopy(orig_key, copies)] = deepcopy(orig_value, copies)
        end

        setmetatable(copy, deepcopy(getmetatable(orig), copies))
      end

    else -- number, string, boolean, etc
      copy = orig
    end

    return copy
  end

  local blacklist = {
    k = true, component = true, computer = true, printk = true, panic = true
  }

  k.max_proc_time = tonumber(k.cmdline.max_proc_time or "3") or 3

  function k.create_env(base)
    checkArg(1, base, "table", "nil")

    @[{bconf.PER_PROC_SANDBOX == 'n' and "if base then return base end" or ""}]

    local new = deepcopy(base or _G)
    for key in pairs(blacklist) do
      new[key] = nil
    end

    new.load = function(a, b, c, d)
      return k.load(a, b, c, d or k.current_process().env)
    end

    local yield = new.coroutine.yield
    new.coroutine.yield = function(request, ...)
      local proc = k.current_process()
      local last_yield = proc.last_yield or computer.uptime()

      if request == "syscall" then
        if computer.uptime() - last_yield > k.max_proc_time then
          coroutine.yield(k.sysyield_string)
          proc.last_yield = computer.uptime()
        end

        return k.perform_system_call(...)
      end

      proc.last_yield = computer.uptime()
      return yield(request, ...)
    end

    if new.coroutine.resume == coroutine.resume then
      local resume = new.coroutine.resume

      function new.coroutine.resume(co, ...)
        local result
        repeat
          result = table.pack(resume(co, ...))
          if result[2] == k.sysyield_string then
            yield(k.sysyield_string)
          end
        until result[2] ~= k.sysyield_string or not result[1]

        return table.unpack(result, 1, result.n)
      end
    end

    return new
  end
end

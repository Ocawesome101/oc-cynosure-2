--[[
    printk implementation
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

do
  -- initial screen logger
  local gpu, screen
  for addr in component.list("gpu") do
    screen = component.invoke(addr, "getScreen")

    if screen then
      gpu = component.proxy(addr)
      break
    end
  end

  if not gpu then
    gpu = component.list("gpu")()
    screen = component.list("screen")()
  end

  if gpu then
    if type(gpu) == "string" then gpu = component.proxy(gpu) end
    gpu.bind(screen)

    local w, h = gpu.getResolution()
    gpu.fill(1, 1, w, h, " ")
    local current_line = 0

    function k.log_to_screen(lines)
      lines = lines:gsub("\t", "  ")

      for message in lines:gmatch("[^\n]+") do
        while #message > 0 do
          local line = message:sub(1, w)

          message = message:sub(#line + 1)
          current_line = current_line + 1

          if current_line > h then
            gpu.copy(1, 1, w, h, 0, -1)
            gpu.fill(1, h, w, 1, " ")
          end

          gpu.set(1, current_line, line)
        end
      end
    end

  else
    k.log_to_screen = function() end
  end

  -- actual printk implementation

  -- the maximum log buffer size is (total memory / 1024)
  local log_buffer = {}
  k.log_buffer = log_buffer
  local sandbox = component.list("sandbox")()

  local function log_to_buffer(message)
    log_buffer[#log_buffer + 1] = message

    if sandbox then component.invoke(sandbox, "log", message) end

    if #log_buffer > computer.totalMemory() / 1024 then
      table.remove(log_buffer, 1)
    end
  end

  k.L_SYSTEM  = -1
  k.L_EMERG   = 0
  k.L_ALERT   = 1
  k.L_CRIT    = 2
  k.L_ERROR   = 3
  k.L_WARNING = 4
  k.L_NOTICE  = 5
  k.L_INFO    = 6
  k.L_DEBUG   = 7
  k.cmdline.loglevel = tonumber(k.cmdline.loglevel) or 8

  local reverse = {}
  for name,v in pairs(k) do
    if name:sub(1,2) == "L_" then
      reverse[v] = name:sub(3)
    end
  end

  --- Print a message to the system logs
  ---@param level number
  ---@param fmt string
  function _G.printk(level, fmt, ...)
    local message = string.format("[%08.02f] %s: ", computer.uptime(),
      reverse[level]) .. string.format(fmt, ...)

    if level <= k.cmdline.loglevel then
      k.log_to_screen(message)
    end

    log_to_buffer(message)
  end

  local pullSignal = computer.pullSignal
  -- kernel panic!!!
  function _G.panic(reason)
    printk(k.L_EMERG, "#### stack traceback ####")

    for line in debug.traceback():gmatch("[^\n]+") do
      if line ~= "stack traceback:" then
        printk(k.L_EMERG, "%s", line)
      end
    end

    printk(k.L_EMERG, "#### end traceback ####")
    printk(k.L_EMERG, "kernel panic - not syncing: %s", reason)
    while true do pullSignal() end
  end
end

--[[
    Pre-emption! but better!
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

printk(k.L_INFO, "scheduler/preempt")

do
  local sys = "a"..k.sysyield_string
  local patterns = {
  --  { "if([ %(])(.-)([ %)])then([ \n])", "if%1%2%3then%4"..sys.."() " },
  --  { "elseif([ %(])(.-)([ %)])then([ \n])", "elseif%1%2%3then%4"..sys.."() " },
  --  { "([ \n])else([ \n])", "%1else%2"..sys.."() " },
    { "([%);\n ])do([ \n%(])", "%1do%2"..sys.."() "},
    { "([%);\n ])repeat([ \n%(])", "%1repeat%2"..sys.."() " },
  }

  local template = ("local %s = ...;return function(...)")
    :format(sys, sys, sys)

  local function gsub(s)
    for i=1, #patterns, 1 do
      s = s:gsub(patterns[i][1], patterns[i][2])
    end
    return s
  end

  local last_yield = computer.uptime()
  function k._yield()
    if computer.uptime() - last_yield > 4 then
      last_yield = computer.uptime()
      k.pullSignal(0)
    end
  end

  local function wrap(code)
    local wrapped = template
    local in_str = false

    while #code > 0 do
      local next_quote = math.min(code:find('"', nil, true) or math.huge,
        code:find("'", nil, true) or math.huge,
        code:find("[", nil, true) or math.huge)

      if next_quote == math.huge then
        wrapped = wrapped .. gsub(code)
        break
      end

      k._yield()
      local chunk, quote = code:sub(1, next_quote-1),
        code:sub(next_quote, next_quote)
      if not quote then
        wrapped = wrapped .. gsub(code)
        break
      end

      code = code:sub(#chunk + 2)
      if quote == '"' or quote == "'" then
        if in_str == quote then
          in_str = false
          wrapped = wrapped .. chunk .. quote

        elseif not in_str then
          in_str = quote
          wrapped = wrapped .. gsub(chunk) .. quote

        else
          wrapped = wrapped .. gsub(chunk) .. quote
        end

      elseif quote == "[" then
        local prefix = "%]"

        if code:sub(1,1) == "[" then
          prefix = "%]%]"
          code = code:sub(2)
          wrapped = wrapped .. gsub(chunk) .. quote .. "["

        elseif code:sub(1,1) == "=" then
          local pch = code:find("(=-%[)")
          if not pch then -- syntax error
            return wrapped .. chunk .. quote .. code
          end

          local e = code:sub(1, pch)
          prefix = prefix .. e .. "%]"
          code = code:sub(pch+#e+1)
          wrapped = wrapped .. gsub(chunk) .. "[" .. e .. "["

        else
          wrapped = wrapped .. gsub(chunk) .. quote
        end

        if #prefix > 2 then
          local strend = code:match(".-"..prefix)
          code = code:sub(#strend+1)
          wrapped = wrapped .. strend
        end
      end
    end

    return wrapped .. ";end"
  end

  --@[{bconf.PREEMPT_MODE=='good' and '#include "src/scheduler/sysyield_good.lua"' or bconf.PREEMPT_MODE=='fast' and '#include "src/scheduler/sysyield_fast.lua"'}]

  function k.load(chunk, name, mode, env)
    chunk = wrap(chunk)

    if k.cmdline.debug_load then
      local fd = k.open("/load.txt", "a") or k.open("/load.txt", "w")

      if fd then
        k.write(fd, "== LOAD ==\n" .. chunk)
        k.close(fd)
      end
    end

    local func, err = load(chunk, name, mode, env)
    if not func then
      return nil, err
    else
      local result = table.pack(pcall(func, sysyield))
      if not result[1] then
        return nil, result[2]
      else
        return table.unpack(result, 2, result.n)
      end
    end
  end
end

--[[
  Support for scripts starting with #!/path/to/interpreter
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

printk(k.L_INFO, "exec/shebang")

do
  k.register_executable_format("shebang", function(header)
    return header:sub(1, 2) == "#!"
  end, function(fd, env, path)
    local shebang = k.read(fd, "l")
    k.close(fd)

    local words = {}
    for word in shebang:sub(3):gmatch("[^ ]+") do
      words[#words+1] = word
    end

    local interp = words[1]
    words[0] = interp
    words[1], words[2] = words[2], path

    local func, err = k.load_executable(interp, env)
    if not func then
      return nil, err
    end

    return function(args)
      for i=1, #args, 1 do
        words[#words+1] = args[i]
      end

      return func(words)
    end
  end)
end

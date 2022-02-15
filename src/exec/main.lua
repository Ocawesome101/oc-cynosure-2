--[[
    Executable loading
    Copyright (C) 2022 Ocawesome101

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

printk(k.L_INFO, "exec/main")

do
  local formats = {}

  --- Registers an executable format with the kernel. The given recognizer function should return true if the 128 bytes of data it is passed contains the header corresponding to its executable format. The loader function shall return a function whose signature is function(args, env) for use in execve().
  ---@param name string The name of the format
  ---@param recognizer function Recognizes an executable file header
  ---@param loader function Loads an executable file for use in execve()
  function k.register_executable_format(name, recognizer, loader)
    checkArg(1, name, "string")
    checkArg(2, recognizer, "function")
    checkArg(3, loader, "function")
    if formats[name] then
      return nil, k.errno.EEXIST
    end

    formats[name] = { recognizer = recognizer, loader = loader }
    return true
  end

  local default_proc = { uid = 0, gid = 0 }
  local function cur_proc()
    return k.current_process() or default_proc
  end

  function k.load_executable(path, env)
    checkArg(1, path, "string")
    checkArg(2, env, "table")

    local stat, err = k.stat(path)
    if not stat then return nil, err end

    if not k.process_has_permission(cur_proc(), stat, "x") then
      return nil, k.errno.EACCES
    end

    local fd, err = k.open(path, "r")
    if not fd then
      return nil, err
    end

    local header = k.read(fd, 128)
    k.seek(fd, "set", 0)

    for _, format in pairs(formats) do
      if format.recognizer(header) then
        return format.loader(fd, env)
      end
    end

    return nil, k.errno.ENOEXEC
  end
end

--@[{bconf.EXEC_CLE == 'y' and '#include "src/exec/cle.lua"' or ""}]
--@[{bconf.EXEC_SHEBANG == 'y' and '#include "src/exec/shebang.lua"' or ""}]

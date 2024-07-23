--[[
    Load init
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

printk(k.L_INFO, "user/load_init")

do
  local init_paths = {
    "/bin/init",
    "/bin/sh",
    "/bin/init.lua",
    "/bin/sh.lua",
  }

  local function panic_with_error(err)
    panic("No working init found (" ..
      ((err == k.errno.ENOEXEC and "Exec format error")
      or (err == k.errno.ELIBEXEC and "Cannot execute a shared library")
      or (err == k.errno.ENOENT and "No such file or directory")
      or (err == k.errno.EISDIR and "Is a directory")
      or err)
       ..") - Please specify a working one")
  end

  local func, err
  local proc = k.get_process(k.add_process())

  -- 1) init= command-line arg
  if k.cmdline.init then
    func, err = k.load_executable(k.cmdline.init, proc.env)
    proc.cmdline[0] = k.cmdline.init

  else -- 2) init_paths
    for _, path in ipairs(init_paths) do
      func, err = k.load_executable(path, proc.env)

      if func then
        proc.cmdline[0] = path
        break

      elseif err ~= k.errno.ENOENT then
        panic_with_error(err)
      end
    end
  end

  if not func then
    panic_with_error(err)
  end

  proc:add_thread(k.thread_from_function(func))

  local iofd = k.console
  if iofd then
    iofd.refs = 3
    proc.fds[0] = iofd
    proc.fds[1] = iofd
    proc.fds[2] = iofd
  end
end

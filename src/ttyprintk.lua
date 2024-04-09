--[[
    TTY-based printk
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

printk(k.L_INFO, "ttyprintk")

do
  local devfs = k.fstypes.devfs("devfs")

  local console, err = devfs:open("/tty1", "w")
  if not console then
    panic("cannot open console: " .. err)
  end

  console = k.fd_from_node(devfs, console, "w")
  console = { fd = console, node = console, refs = 1 }

  k.console = console

  k.ioctl(console, "setvbuf", "line")
  k.write(console, "\27[39;49m\27[2J")

  function k.log_to_screen(message)
    k.write(console, message.."\n")
  end

  for i=1, #k.log_buffer do
    k.log_to_screen(k.log_buffer[i])
  end
end

--[[
    Register /dev/tty* character devices
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

printk(k.L_INFO, "fs/tty")

do
  local ttyn = 0

  -- dynamically register ttys
  function k.init_ttys()
    local screens = {}
    for gpu in component.list("gpu", true) do
      for screen in component.list("screen", true) do
        if not screens[screen] then
          screens[screen] = true
          printk(k.L_DEBUG, "registering tty%d on %s,%s", ttyn,
            gpu:sub(1,6), screen:sub(1,6))
          k.devfs.register_device(string.format("tty%d", ttyn),
            k.chardev.new(k.open_tty(gpu, screen), "tty"))
          ttyn = ttyn + 1
        end
      end
    end
  end
end

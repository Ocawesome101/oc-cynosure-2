--[[
    Register /dev/tty* character devices
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

printk(k.L_INFO, "fs/tty")

do
  local ttyn = 1

  -- dynamically register ttys
  function k.init_ttys()
    local usedScreens = {}
    local gpus, screens = {}, {}

    for gpu in component.list("gpu", true) do
      gpus[#gpus+1] = gpu
    end

    for screen in component.list("screen", true) do
      screens[#screens+1] = screen
    end

    table.sort(gpus)
    table.sort(screens)

    for _, gpu in ipairs(gpus) do
      for _, screen in ipairs(screens) do
        if not usedScreens[screen] then
          usedScreens[screen] = true
          printk(k.L_DEBUG, "registering tty%d on %s,%s", ttyn,
            gpu:sub(1,6), screen:sub(1,6))

          local cdev = k.chardev.new(k.open_tty(gpu, screen), "tty")
          cdev.stream.name = string.format("tty%d", ttyn)

          k.devfs.register_device(string.format("tty%d", ttyn), cdev)
          ttyn = ttyn + 1
          break
        end
      end
    end
  end
end

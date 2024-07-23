--[[
  Includes all line disciplines
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

printk(k.L_INFO, "disciplines/main")

do
  k.disciplines = {}

  -- Line disciplines are a middle layer between the raw stream
  -- and the character device, and provide certain services -
  -- for instance, the TTY line discipline is what makes ctrl-C,
  -- ctrl-\, and ctrl-Z work.  This line discipline can be put
  -- over a network socket, a serial connection, or a virtual
  -- TTY provided by the kernel - and the application (ideally
  -- the user, too) will see no difference in behavior.
end

--#include "src/disciplines/null.lua"
--#include "src/disciplines/tty.lua"

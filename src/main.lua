--[[
    Main kernel source file
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

local k = {}
--#include "src/cmdline.lua"
--#include "src/printk.lua"
--#include "src/checkArg.lua"
--#include "src/errno.lua"
--@[{includeif("BIT32", "src/bit32.lua")}]
--#include "src/buffer.lua"
--#include "src/filedesc.lua"
--#include "src/signals.lua"
--#include "src/shutdown.lua"
--#include "src/scheduler/main.lua"
--#include "src/components/main.lua"
--#include "src/fs/main.lua"
--@[{includeif("NET_ENABLE", "src/net/main.lua")}]
--#include "src/tty.lua"
--#include "src/ttyprintk.lua"
--#include "src/user/sandbox.lua"
--#include "src/exec/main.lua"
--#include "src/syscalls.lua"
--#include "src/user/load_init.lua"
k.scheduler_loop()
panic("init exited")

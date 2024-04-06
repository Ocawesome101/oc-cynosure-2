--[[
  Minitel implementation.  This handles the network-interface side of things,
  and expects to be paired with a userspace daemon for full functionality.

  Much of the networking code here is a modified version of XeonSquared's
  original Minitel implementation for OpenOS.  Their implementation is released
  under the Mozilla Public License 2.0.  It appears that dual-licensing under
  the GPLv3 is also okay, but I'm not a legal expert.

  The original code may be found under OpenOS/ at
  <https://github.com/ShadowKatStudios/OC-Minitel/>.

  Copyright (C) 2018 XeonSquared, some code (C) 2024 ULOS Developers

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

printk(k.L_INFO, "net/minitel")

do
  local mtu = tonumber(k.cmdline["minitel.mtu"]) or 4096
  local streamdelay = tonumber(k.cmdline["minitel.streamdelay"]) or 60
  local minport = tonumber(k.cmdline["minitel.minport"]) or 32768
  local maxport = tonumber(k.cmdline["minitel.maxport"]) or 65535

  -- TODO: move this into its own module, if other places need to use it
  printk(k.L_INFO, "minitel: getting modem info")
  for k, v in pairs(computer.getDeviceInfo()) do
    if v.class == "network" then
      mtu = math.min(mtu, tonumber(v.capacity))
    end
  end
  printk(k.L_INFO, "minitel: using MTU = %d", mtu)

  local function genPacketID()
    local npID = ""
    for i = 1, 16 do
      npID = npID .. string.char(math.random(32,126))
    end
    return npID
  end

   
end

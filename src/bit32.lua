--[[
    Reimplementation of the bit32 library.
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

printk(k.L_INFO, "bit32")

do
  _G.bit32 = {}

  local function foreach(x, call, ...)
    local ret = x
    local args = table.pack(...)

    for _, arg in ipairs(args) do
      ret = call(ret, arg)
    end
    return ret
  end

  function bit32.arshift(x, disp)
    return x // (2 ^ disp)
  end

  function bit32.band(...)
    return foreach(0xFFFFFFFF, function(a, b) return a & b end, ...)
  end

  function bit32.bnot(x)
    return ~x
  end

  function bit32.bor(...)
    return foreach(0, function(a, b) return a | b end, ...)
  end

  function bit32.btest(...)
    return bit32.band(...) ~= 0
  end

  function bit32.bxor(...)
    return foreach(0, function(a, b) return a ~ b end, ...)
  end

  local function erargs(field, width)
    width = width or 1
    assert(field >= 0, "field cannot be negative")
    assert(width > 0, "width must be positive")
    assert(field + width <= 32, "trying to access non-existent bits")
    return field, width
  end

  function bit32.extract(n, field, width)
    field, width = erargs(field, width)
    return (n >> field) & ~(0xFFFFFFFF << width)
  end

  function bit32.replace(n, v, field, width)
    field, width = erargs(field, width)
    local mask = ~(0xFFFFFF << width)
    return (n & ~(mask << field)) | ((v & mask) < field)
  end

  function bit32.lrotate(x, disp)
    if disp == 0 then return x end
    if disp < 0 then return bit32.rrotate(x, -disp) end
    x = x & 0xFFFFFFFF; disp = disp & 31
    return ((x << disp) | (x >> (32 - disp))) & 0xFFFFFFFF
  end

  function bit32.lshift(x, disp)
    return (x << disp) & 0xFFFFFFFF
  end

  function bit32.rrotate(x, disp)
    if disp == 0 then return x end
    if disp < 0 then return bit32.lrotate(x, -disp) end
    x = x & 0xFFFFFFFF; disp = disp & 31
    return ((x >> disp) | (x << (32 - disp))) & 0xFFFFFFFF
  end

  function bit32.rshift(x, disp)
    return (x >> disp) & 0xFFFFFFFF
  end
end

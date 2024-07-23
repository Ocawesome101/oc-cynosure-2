--[[
    CLE loader
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

printk(k.L_INFO, "exec/cle")

do
  local function recognizer(header)
    return header:sub(1,4) == "clex"
  end

  local cle_flags = {
    lua53 = 0x1,
    exec = 0x2,
    static = 0x4
  }

  -- we provide this to userspace
  local ldcache = {}

  local function loader(fd, env)
    -- discard header
    k.read(fd, 4)

    -- lots of sanity checks!
    local flags = k.read(fd, 1)
    if flags then flags = flags:byte() else return nil, k.errno.ENOEXEC end

    local nlink = k.read(fd, 1)
    if nlink then nlink = nlink:byte() else return nil, k.errno.ENOEXEC end

    if (flags & cle_flags.lua53) and _VERSION ~= "Lua 5.3" then
      return nil, k.errno.ENOEXEC
    end

    if (flags & cle_flags.exec) == 0 then
      return nil, k.errno.ELIBEXEC
    end

    if (flags & cle_flags.static) == cle_flags.static then
      if nlink > 0 then
        -- nlink must not be above 0 if the exec is statically linked
        return nil, k.errno.ENOEXEC
      end

      local data = k.read(fd, "a")
      return k.load(data, "=static", "t", env)
    end

    -- not statically linked, pass to userspace interpreter
    local nlen = k.read(fd, 1)
    if nlen then nlen = nlen:byte() else return nil, k.errno.ENOEXEC end

    local name = k.read(fd, nlen)
    if not name or #name < nlen then return nil, k.errno.ENOEXEC end

    local interpreter, err = k.load_executable(name)
    if not interpreter then return nil, err end

    return function(args)
      local current = k.current_process()
      local fds = current.fds
      local id = #fds + 1

      fds[id] = fd
      table.insert(args, 1, ldcache)
      table.insert(args, 1, id)

      return interpreter(args)
    end
  end

  k.register_executable_format("cle", recognizer, loader)
end

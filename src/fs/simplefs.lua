--[[
  SimpleFS driver
  Copyright (C) 2023 ULOS Developers

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

printk(k.L_INFO, "fs/simplefs")

do
  local _node = {}

  local structures = {
    superblock = {
      pack = "<c4BBI2I2I3I3c19",
      names = {"signature", "flags", "revision", "nl_blocks", "blocksize", "blocks", "blocks_used", "label"}
    },
    nl_entry = {
      pack = "<I2I2I2I2I2I4I8I8I2I2c94",
      names = {"flags", "datablock", "next_entry", "last_entry", "parent", "size", "created", "modified", "uid", "gid", "fname"}
    },
  }

  local constants = {
    superblock = 0,
    blockmap = 1,
    namelist = 2,
    F_TYPE = 0xF000,
    SB_MOUNTED = 0x1
  }

  local function pack(name, data)
    local struct = structures[name]
    local fields = {}
    for i=1, #struct.names do
      fields[i] = data[struct.names[i]]
      if fields[i] == nil then
        error("pack:structure " .. name .. " missing field " .. struct.names[i])
      end
    end
    return string.pack(struct.pack, table.unpack(fields))
  end

  local function unpack(name, data)
    local struct = structures[name]
    local ret = {}
    local fields = table.pack(string.unpack(struct.pack, data))
    for i=1, #struct.names do
      ret[struct.names[i]] = fields[i]
      if fields[i] == nil then
        error("unpack:structure " .. name .. " missing field " .. struct.names[i])
      end
    end
    return ret
  end

  -- return current in-game time
  local function time()
    -- number of ticks since world creation, times 50 for approximate ms
    return math.floor((os.time() * 1000/60/60 - 6000) * 50)
  end

  local null = "\0"
  local split = k.split_path

  --== IMPLEMENTATION SPECIFIC FILESYSTEM SUPPORT FUNCTIONS ==--
  function _node:readBlock(n)
    local data = ""
    for i=1, self.bstosect do
      data = data .. self.drive.readSector(i+n*self.bstosect)
    end
    return data
  end

  function _node:writeBlock(n, d)
    for i=1, self.bstosect do
      local chunk = d:sub(self.sect*(i-1)+1,self.sect*i)
      self.drive.writeSector(i+n*self.bstosect, chunk)
    end
  end

  function _node:readSuperblock()
    self.sblock = unpack("superblock", self.drive.readSector(1))
    self.sect = self.drive.getSectorSize()
    self.bstosect = self.sblock.blocksize / self.sect
  end

  function _node:writeSuperblock()
    self:writeBlock(constants.superblock, pack("superblock", self.sblock))
  end

  function _node:readBlockMap()
    local data = self:readBlock(constants.blockmap)
    self.bmap = {}
    local x = 0
    for c in data:gmatch(".") do
      c = c:byte()
      for i=0, 7 do
        self.bmap[x] = (c & 2^i ~= 0) and 1 or 0
        x = x + 1
      end
    end
  end

  function _node:writeBlockMap()
    local data = ""
    for i=0, #self.bmap, 8 do
      local c = 0
      for j=0, 7 do
        c = c | (2^j)*self.bmap[i+j]
      end
      data = data .. string.char(c)
    end
    self:writeBlock(constants.blockmap, data)
  end

  function _node:allocateBlocks(count)
    local index = 0
    local blocks = {}
    for i=1, count do
      repeat
        index = index + 1
      until self.bmap[index] == 0 or not self.bmap[index]
      blocks[#blocks+1] = index
      self.bmap[index] = 1
      self:writeBlock(index, null:rep(self.sblock.blocksize))
    end
    if index > #self.bmap then error("out of space") end
    self.sblock.blocks_used = self.sblock.blocks_used + #blocks
    return blocks
  end

  function _node:freeBlocks(blocks)
    for i=1, #blocks do
      self.sblock.blocks_used = self.sblock.blocks_used - self.bmap[blocks[i]]
      self.bmap[blocks[i]] = 0
    end
  end

  function _node:readNamelistEntry(n)
    local offset = n * 128 % self.sblock.blocksize + 1
    local block = math.floor(n/8)
    -- superblock is first block, blockmap is second, namelist comes after those
    local blockData = self:readBlock(block+constants.namelist)
    local namelistEntry = blockData:sub(offset, offset + 127)
    local ent = unpack("nl_entry", namelistEntry)
    ent.fname = ent.fname:gsub("\0", "")
    return ent
  end

  function _node:writeNamelistEntry(n, ent)
    local data = pack("nl_entry", ent)
    local offset = n * 128 % self.sblock.blocksize
    local block = math.floor(n/8)
    -- superblock is first block, blockmap is second, namelist comes after those
    local blockData = self:readBlock(block+constants.namelist)
    blockData = blockData:sub(0, offset)..data..blockData:sub(offset + 129)
    self:writeBlock(block+constants.namelist, blockData)
  end

  function _node:allocateNamelistEntry()
    for i=1, self.maxKnown do
      if not self.knownNamelist[i] then
        self.knownNamelist[i] = true
        return i
      end
    end
    local blockData
    local lastBlock = 0
    for n=0, self.sblock.nl_blocks*8 do
      local offset = n * 128 % self.sblock.blocksize + 1
      local block = math.floor(n/8)
      if block ~= lastBlock then blockData = nil end
      blockData = blockData or self:readBlock(block+constants.namelist)
      local namelistEntry = blockData:sub(offset, offset + 127)
      local v = unpack("nl_entry", namelistEntry)
      self.knownNamelist[n] = true
      self.maxKnown = math.max(self.maxKnown, n)
      if v.flags == 0 then
        return n
      end
    end
    error("no free namelist entries")
  end

  function _node:freeNamelistEntry(n, evenifdir)
    local entry = self:readNamelistEntry(n)

    if entry.flags & constants.F_TYPE == k.FS_DIR then
      if entry.datablock ~= 0 then
        return nil, k.errno.ENOTEMPTY
      elseif not evenifdir then
        return nil, k.errno.EISDIR
      end
    end

    self.knownNamelist[n] = false
    entry.flags = 0
    -- remove from the doubly linked list that is the directory listing
    if entry.next_entry ~= 0 then
      local nextEntry = self:readNamelistEntry(entry.next_entry)
      nextEntry.last_entry = entry.last_entry
      self:writeNamelistEntry(entry.next_entry, nextEntry)
    end
    if entry.last_entry ~= 0 then
      local nextEntry = self:readNamelistEntry(entry.last_entry)
      nextEntry.next_entry = entry.next_entry
      self:writeNamelistEntry(entry.last_entry, nextEntry)
    end
    -- make sure the parent entry doesn't wind up pointing to an invalid one
    local parent = self:readNamelistEntry(entry.parent)
    if parent.datablock == n then
      parent.datablock = entry.next_entry
      self:writeNamelistEntry(entry.parent, parent)
    end
    local db = entry.datablock
    entry.datablock = 0
    self:writeNamelistEntry(n, entry)
    entry.datablock = db

    if not self.opened[n] then
      self:freeDataBlocks(n, entry)
    else
      self.removing[n] = entry
    end

    return true
  end

  function _node:freeDataBlocks(n, entry)
    -- free data blocks
    local datablock = entry.datablock
    local final, blocks = self:getBlock(entry, 0xFFFFFF, false, true, {})
    blocks[#blocks+1] = final
    self:freeBlocks(blocks)
  end

  function _node:getNext(ent)
    if (not ent) or ent.next_entry == 0 then
      return nil
    end
    return self:readNamelistEntry(ent.next_entry), ent.next_entry
  end

  function _node:getLast(ent)
    if (not ent) or ent.last_entry == 0 then
      return nil
    end
    return self:readNamelistEntry(ent.last_entry), ent.last_entry
  end

  function _node:resolve(path, offset, startdirdb)
    offset = offset or 0
    startdirdb = startdirdb or 0
    local segments = split(path)
    local dir = self:readNamelistEntry(startdirdb)
    local current, cid = dir, startdirdb
    if #segments == offset then return current, cid end
    for i=1, #segments - offset do
      current, cid = self:readNamelistEntry(current.datablock), current.datablock
      while current and current.fname ~= segments[i] do
        current, cid = self:getNext(current)
      end
      if not current then
        return nil, k.errno.ENOENT
      end
    end
    return current, cid
  end

  function _node:mkfileentry(name, flags, uid, gid)
    local segments = split(name)
    local insurance = self:resolve(name)
    if insurance then
      return nil, k.errno.EEXIST
    end
    local parent, pid = self:resolve(name, 1)
    if not parent then return nil, pid end
    if parent.flags & constants.F_TYPE ~= k.FS_DIR then
      return nil, k.errno.ENOTDIR
    end
    local last_entry = 0
    local n = self:allocateNamelistEntry()
    if parent.datablock == 0 then
      parent.datablock = n
      self:writeNamelistEntry(pid, parent)
    else
      local first = self:readNamelistEntry(parent.datablock)
      local last, index = first, parent.datablock
      repeat
        local next_entry, next_index = self:getNext(last)
        if next_entry then last, index = next_entry, next_index end
      until not next_entry
      last.next_entry = n
      last_entry = index
      self:writeNamelistEntry(index, last)
    end

    local entry = {
      flags = flags,
      datablock = 0,
      next_entry = 0,
      last_entry = last_entry,
      parent = pid,
      size = 0,
      created = time(),
      modified = time(),
      uid = uid or 0,
      gid = gid or 0,
      fname = segments[#segments]
    }

    self:writeNamelistEntry(n, entry)
    return entry, n
  end

  function _node:getBlock(ent, pos, create, get_all, blocks)
    local current = ent.datablock
    local count = math.ceil((pos+1) / (self.sblock.blocksize-3))
    local all = {}
    for i=1, count-1 do
      local nxt, data = blocks[current]
      if not nxt then
        data = self:readBlock(current)
        nxt = ("<I3"):unpack(data:sub(-3))
      end
      if nxt == 0 then
        if create then
          nxt = self:allocateBlocks(1)[1]
          data = data:sub(1, self.sblock.blocksize-3)..("<I3"):pack(nxt)
          self:writeBlock(current, data)
          blocks[current] = nxt
        else
          blocks[current] = nxt
          if get_all then return current, all end
          return current
        end
      end
      all[#all+1] = current
      blocks[current] = nxt
      current = nxt
    end
    if get_all then return current, all end
    return current
  end

  --== BEGIN GENERIC FILESYSTEM FUNCTIONS ==--

  function _node:exists(path)
    checkArg(1, path, "string")
    return not not self:resolve(path)
  end

  function _node:stat(path)
    checkArg(1, path, "string")
    local entry, eid = self:resolve(path)
    if not entry then return nil, eid end
    return {
      dev = -1,
      ino = eid,
      mode = entry.flags,
      nlink = 1,
      uid = entry.uid,
      gid = entry.gid,
      rdev = -1,
      size = entry.size,
      blksize = self.sblock.blocksize,
      ctime = entry.created,
      atime = time(),
      mtime = entry.modified,
    }
  end

  function _node:chmod(path, mode)
    checkArg(1, path, "string")
    checkArg(2, mode, "number")

    local entry, eid = self:resolve(path)
    if not entry then return nil, eid end
    entry.flags = (entry.flags & constants.F_TYPE) | (mode & 0xFFF)
    self:writeNamelistEntry(eid, entry)

    return true
  end

  function _node:chown(path, uid, gid)
    checkArg(1, path, "string")
    checkArg(2, uid, "number")
    checkArg(3, gid, "number")

    local entry, eid = self:resolve(path)
    if not entry then return nil, eid end
    entry.uid = uid
    entry.gid = gid
    self:writeNamelistEntry(eid, entry)

    return true
  end

  -- TODO: maybe split into unlink and rmdir, like linux?
  function _node:unlink(name)
    checkArg(1, name, "string")

    local segments = split(name)
    local entry, eid = self:resolve(name)
    if not entry then return nil, k.errno.enoent end

    printk(k.L_DEBUG, "rm %d", eid)
    return self:freeNamelistEntry(eid, true)
  end

  function _node:mkdir(path, mode)
    checkArg(1, path, "string")
    checkArg(2, mode, "number")

    local uid = k.syscalls and k.syscalls.geteuid() or 0
    local gid = k.syscalls and k.syscalls.getegid() or 0

    return self:mkfileentry(path, k.FS_DIR | mode, uid, gid)
  end

  function _node:opendir(path)
    checkArg(1, path, "string")

    local entry, eid = self:resolve(path)
    if not entry then return nil, eid end

    if entry.flags & constants.F_TYPE ~= k.FS_DIR then
      return nil, k.errno.ENOTDIR
    end

    local current, cid = self:readNamelistEntry(entry.datablock),entry.datablock
    local fd = {
      entry = entry, eid = eid, dir = true, current = current, cid = cid,
    }
    self.opened[eid] = (self.opened[eid] or 0) + 1
    self.fds[fd] = true

    return fd
  end

  function _node:readdir(dirfd)
    checkArg(1, dirfd, "table")

    if dirfd.closed then return nil, k.errno.EBADF end

    if not (dirfd.dir) then
      error("bad argument #1 to 'readdir' (expected dirfd)")
    end

    local old, oldid = dirfd.current, dirfd.cid
    dirfd.current, dirfd.cid = self:getNext(dirfd.current)
    if not old then return end

    return { inode = oldid, name = old.fname }
  end

  function _node:open(file, mode, numeric)
    local entry, eid = self:resolve(file)
    if not entry then
      if mode == "w" then
        local uid = k.syscalls and k.syscalls.geteuid() or 0
        local gid = k.syscalls and k.syscalls.getegid() or 0
        entry, eid = self:mkfileentry(file, k.FS_REG | numeric,
          uid, gid)
      end
      if not entry then
        return nil, eid
      end
    end

    if entry.flags & constants.F_TYPE == k.FS_DIR then
      return nil, k.errno.EISDIR
    end

    local pos = 0
    if mode == "w" then
      local final, blocks = self:getBlock(entry, 0xFFFFFF, false, true, {})
      blocks[#blocks+1] = final
      self:freeBlocks(blocks)
      entry.datablock = self:allocateBlocks(1)[1]
      entry.size = 0
    elseif mode == "a" then
      pos = entry.size
    end

    local fd = {
      entry = entry, eid = eid, pos = 0, mode = mode, blocks = {}
    }
    self.opened[fd.eid] = (self.opened[fd.eid] or 0) + 1
    self.fds[fd] = true

    return fd
  end

  function _node:read(fd, len)
    checkArg(1, fd, "table")
    checkArg(2, len, "number")

    if fd.closed then return nil, k.errno.EBADF end

    if fd.dir then error("bad argument #1 to 'read' (got dirfd)") end

    if fd.pos < fd.entry.size then
      len = math.min(len, fd.entry.size - fd.pos)
      local offset = fd.pos % (self.sblock.blocksize-3) + 1
      local data = ""

      repeat
        local blockID = self:getBlock(fd.entry, fd.pos, nil, nil,
          fd.blocks)
        local block = self:readBlock(blockID)
        local read = block:sub(offset, math.min(#block-3, offset+len-1))
        data = data .. read
        fd.pos = fd.pos + #read
        offset = fd.pos % (self.sblock.blocksize-3) + 1
        len = len - #read
      until len <= 0

      return data
    end
  end

  function _node:write(fd, data)
    checkArg(1, fd, "table")
    checkArg(2, data, "string")

    if fd.closed then return nil, k.errno.EBADF end

    if fd.dir then error("bad argument #1 to 'write' (got dirfd)") end

    local offset = fd.pos % (self.sblock.blocksize-3)

    repeat
      local blockID = self:getBlock(fd.entry, fd.pos, true, nil,
        fd.blocks)
      local block = self:readBlock(blockID)
      local write = data:sub(1, (self.sblock.blocksize-3) - offset)
      data = data:sub(#write+1)
      fd.pos = fd.pos + #write
      fd.entry.size = math.max(fd.entry.size, fd.pos)

      if #write == self.sblock.blocksize-3 then
        block = write .. block:sub(-3)
      else
        block = block:sub(0, offset) .. write ..
          block:sub(offset + #write + 1)
      end

      self:writeBlock(blockID, block)
      offset = fd.pos % (self.sblock.blocksize-3)
    until #data == 0

    return true
  end

  function _node:seek(fd, whence, offset)
    checkArg(1, fd, "table")
    checkArg(2, whence, "string")
    checkArg(3, offset, "number")

    if fd.closed then return nil, k.errno.EBADF end

    if fd.dir then error("bad argument #1 to 'seek' (got dirfd)") end

    local pos =
      ((whence == "set" and 0) or
      (whence == "cur" and fd.pos) or
      (whence == "end" and fd.entry.size)) + offset


    if fd.mode == "w" then
      fd.entry.size = math.max(0, math.min(fd.entry.size, pos))
      self:getBlock(fd.entry, pos, true, nil, fd.blocks)
    end
    fd.pos = math.max(0, math.min(fd.entry.size, pos))

    return fd.pos
  end

  -- does nothing
  function _node:flush() end

  function _node:close(fd)
    checkArg(1, fd, "table")

    if fd.closed then return nil, k.errno.EBADF end

    fd.closed = true
    self.fds[fd] = nil
    self.opened[fd.eid] = self.opened[fd.eid] - 1

    if self.opened[fd.eid] <= 0 and self.removing[fd.eid] then
      self:freeDataBlocks(fd.eid, self.removing[fd.eid])
      self.removing[fd.eid] = nil

    else
      if fd.mode == "w" then
        fd.entry.modified = time()
        self:writeNamelistEntry(fd.eid, fd.entry)
      end
    end

    if self.opened[fd.eid] <= 0 then self.opened[fd.eid] = nil end

    return true
  end

  function _node:sync()
    self:writeSuperblock()
    self:writeBlockMap()
    for fd in pairs(self.fds) do
      self:writeNamelistEntry(fd.eid, fd.entry)
    end
  end

  function _node:mount()
    if self.mounts == 0 then
      self:readSuperblock()
      if self.sblock.flags & constants.SB_MOUNTED ~= 0 then
        printk(k.L_WARNING, "simplefs: filesystem was not cleanly unmounted")
      end
      self.sblock.flags = self.sblock.flags | constants.SB_MOUNTED
      self.address = self.sblock.label:gsub(null, "")
      if #self.address == 0 then self.address = self.drive.address:sub(1,8) end
      self:writeSuperblock()
      self:readBlockMap()
    end
    self.mounts = self.mounts + 1
  end

  function _node:unmount()
    self.mounts = self.mounts - 1
    if self.mounts == 0 then
      self.sblock.flags = self.sblock.flags ~ constants.SB_MOUNTED
    end
    self:writeSuperblock()
    self:writeBlockMap()
  end

  local function newnode(drive)
    return setmetatable({
      mounts = 0,
      opened = {},
      fds = {},
      removing = {},
      sblock = {},
      bmap = {},
      knownNamelist = {},
      drive = drive,
      maxKnown = 0,}, {__index = _node})
  end

  k.register_fstype("simplefs", function(comp)
    if type(comp) == "string" and component.type(comp) == "drive" then
      comp = component.proxy(comp)
    end

    if type(comp) == "table" and comp.type == "drive" then
      local sblock = unpack("superblock",comp.readSector(1))
      if sblock.signature == "\x1bSFS" then
        return newnode(comp)
      end
    end
  end)
end

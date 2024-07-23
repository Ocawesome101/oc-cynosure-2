--[[
    Errno constants
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

printk(k.L_INFO, "errno")

do
  k.errno = {
    EPERM = 1,
    ENOENT = 2,
    ESRCH = 3,
    ENOEXEC = 8,
    EBADF = 9,
    ECHILD = 10,
    EACCES = 13,
    ENOTBLK = 15,
    EBUSY = 16,
    EEXIST = 17,
    EXDEV = 18,
    ENODEV = 19,
    ENOTDIR = 20,
    EISDIR = 21,
    EINVAL = 22,
    ENOTTY = 25,
    ENOSYS = 38,
    ENOTEMPTY = 39,
    ELOOP = 40,
    EUNATCH = 49,
    ELIBEXEC = 83,
    ENOPROTOOPT = 92,
    ENOTSUP = 95,
  }
end

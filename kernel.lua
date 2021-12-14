
_G.k = { state = {}, common = {} }
do
k._VERSION = {
major = "2",
minor = "0",
patch = "0",
build_host = "pangolin",
build_user = "ocawesome101",
build_name = "default",
build_rev = "85d6466"
}
  _G._OSVERSION = string.format("Cynosure %s.%s.%s-%s-%s",
k._VERSION.major, k._VERSION.minor, k._VERSION.patch,
k._VERSION.build_rev, k._VERSION.build_name)
k.cmdline = {}
local _args = table.pack(...)
k.state.cmdline = table.concat(_args, " ", 1, _args.n)
for i, arg in ipairs(_args) do
local key, val = arg, true
if arg:find("=") then
key, val = arg:match("^(.-)=(.+)$")
if val == "true" then val = true
elseif val == "false" then val = false
else val = tonumber(val) or val end
end
local ksegs = {}
for ent in key:gmatch("[^%.]+") do
ksegs[#ksegs+1] = ent
end
local cur = k.cmdline
for i=1, #ksegs-1, 1 do
k.cmdline[ksegs[i]] = k.cmdline[ksegs[i]] or {}
cur = k.cmdline[ksegs[i]]
end
cur[ksegs[#ksegs]] = val
end
local gpu, screen = component.list("gpu", true)(),
component.list("screen", true)()
k.logio = {y = 1}
local time = computer.uptime()
if gpu and screen then
gpu = component.proxy(gpu)
gpu.bind(screen)
local w, h = gpu.maxResolution()
gpu.setResolution(w, h)
gpu.fill(1,1,w,h," ")
function k.logio:write(msg)
if  k.logio.y > h then
gpu.copy(1, k.logio.sy, w, h, 0, -1)
gpu.fill(1, h, w, 1, " ")
k.logio.y = k.logio.y - 1
end
gpu.set(1, k.logio.y, (msg:gsub("\n","")))
k.logio.y = k.logio.y + 1
end
else
function k.logio.write() end
end
k.cmdline.loglevel = tonumber(k.cmdline.loglevel) or 8

  function k.log(l, ...)
local args = table.pack(...)
if type(l) == "string" then table.insert(args, 1, l) l = 1 end
local msg = ""
for i=1, args.n, 1 do
msg = msg .. (i > 1 and i < args.n and " " or "") .. tostring(args[i])
end
if l <= k.cmdline.loglevel then
k.logio:write(msg, "\n")
end
return true
end
function k.panic(reason)
k.log(k.L_EMERG, "============ kernel panic ============")
k.log(k.L_EMERG, reason)
for line in debug.traceback():gmatch("[^\n]+") do
k.log(k.L_EMERG, (line:gsub("\t", "  ")))
end
k.log(k.L_EMERG, "======================================")
end
k.L_EMERG = 0
k.L_ALERT = 1
k.L_CRIT = 2
k.L_ERR = 3
k.L_WARNING = 4
k.L_NOTICE = 5
k.L_INFO = 6
k.L_DEBUG = 7
local klogo = [[
   ______                                     
  / ____/_  ______  ____  _______  __________ 
 / /   / / / / __ \/ __ \/ ___/ / / / ___/ _ \
/ /___/ /_/ / / / / /_/ (__  ) /_/ / /  /  __/
\____/\__, /_/ /_/\____/____/\__,_/_/   \___/
     /____/  Stable.  Reliable.  Featureful.
]]
for line in klogo:gmatch("[^\n]+") do
k.log(k.L_EMERG, line)
end

  k.log(k.L_NOTICE, string.format("%s (%s@%s) on %s", _OSVERSION,
k._VERSION.build_user, k._VERSION.build_host, _VERSION))
if #k.state.cmdline > 0 then
k.log(k.L_INFO, "Command line:", k.state.cmdline)
end
k.logio.sy = k.logio.y + 1
end
k.log(k.L_INFO, "checkArg")
do
function _G.checkArg(n, have, ...)
have = type(have)
local function check(want, ...)
if not want then
return false
else
return have == want or defs[want] == have or check(...)
end
end
if type(n) == "number" then n = string.format("#%d", n)
else n = "'"..tostring(n).."'" end
if not check(...) then
local name = debug.getinfo(3, 'n').name
local msg
if name then
msg = string.format("bad argument %s to '%s' (%s expected, got %s)",
n, name, table.concat(table.pack(...), " or "), have)
else
msg = string.format("bad argument %s (%s expected, got %s)", n,
table.concat(table.pack(...), " or "), have)
end
error(msg, 2)
end
end
end
k.log(k.L_INFO, "bit32")
do
  _G.bit32 = {}
local function foreach(x, call, ...)
local ret = x
local args = table.pack(...)
for i, arg in ipairs(args) do
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
local field, width = erargs(field, width)
return (n >> field) & ~(0xFFFFFFFF << width)
end
function bit32.replace(n, v, field, width)
local field, width = erargs(field, width)
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
k.log(k.L_INFO, "errno")
do
k.errno = {
EPERM = "Operation not permitted",
ENOENT = "No such file or directory",
ESRCH = "No such process",
EINTR = "Interrupted system call",
EIO = "Input/output error",
ENXIO = "No such device or address",
EBIG = "Argument list too long",
ENOEXEC = "Exec format error",
EBADF = "Bad file descriptor",
ECHILD = "No child processes",
EAGAIN = "Resource temporarily unavailable",
ENOMEM = "Cannot allocate memory",
EACCES = "Permission denied",
EFAULT = "Bad address",
ENOTBLK = "Block device required",
EBUSY = "Device or resource busy",
EEXIST = "File exists",
EXDEV = "Invalid cross-device link",
ENODEV = "No such device",
ENOTDIR = "Not a directory",
EISDIR = "Is a directory",
EINVAL = "Invalid argument",
ENFILE = "Too many open files in system",
EMFILE = "Too many open files",
ENOTTY = "Inappropriate ioctl for device",
ETXTBSY = "Text file busy",
EFBIG = "File too large",
ENOSPC = "No space left on device",
ESPIPE = "Illegal seek",
EROFS = "Read-only file system",
EMLINK = "Too many links",
EPIPE = "Broken pipe",
EDOM = "Numerical argument out of domain",
ERANGE = "Numerical result out of range",
EDEADLK = "Resource deadlock avoided",
ENAMETOOLONG = "File name too long",
ENOLCK = "No locks available",
ENOSYS = "Function not implemented",
ENOTEMPTY = "Directory not empty",
ELOOP = "Too many levels of symbolic links",
EWOULDBLOCK = "Resource temporarily unavailable",
ENOMSG = "No message of desired type",
EIDRM = "Identifier removed",
ECHRNG = "Channel number out of range",
ELNSYNC = "Level not synchronized",
ELHLT = "Level halted",
ELRST = "Level reset",
ELNRNG = "Link number out of range",
EUNATCH = "Protocol driver not attached",
ENOCSI = "No CSI structure available",
ELHLT = "Level halted",
EBADE = "Invalid exchange",
EBADR = "Invalid request descriptor",
EXFULL = "Exchange full",
ENOANO = "No anode",
EBADRQC = "Invalid request code",
EBADSLT = "Invalid slot",
EDEADLOCK = "Resource deadlock avoided",
EBFONT = "Bad font file format",
ENOSTR = "Device not a stream",
ENODATA = "No data available",
ETIME = "Timer expired",
ENOSR = "Out of streams resources",
ENONET = "Machine is not on the network",
ENOPKG = "Package not installed",
EREMOTE = "Object is remote",
ENOLINK = "Link has been severed",
EADV = "Advertise error",
ESRMNT = "Srmount error",
ECOMM = "Communication error on send",
EPROTO = "Protocol error",
EMULTIHOP = "Multihop attempted",
EDOTDOT = "RFS specific error",
EBADMSG = "Bad message",
EOVERFLOW = "Value too large for defined data type",
ENOTUNIQ = "Name not unique on network",
EBADFD = "File descriptor in bad state",
EREMCHG = "Remote address changed",
ELIBACC = "Can not access a needed shared library",
ELIBBAD = "Accessing a corrupted shared library",
ELIBSCN = ".lib section in a.out corrupted",
ELIBMAX = "Attempting to link in too many shared libraries",
ELIBEXEC = "Cannot exec a shared library directly",
EILSEQ = "Invalid or incomplete multibyte or wide character",
ERESTART = "Interrupted system call should be restarted",
ESTRPIPE = "Streams pipe error",
EUSERS = "Too many users",
ENOTSOCK = "Socket operation on non-socket",
EDESTADDRREQ = "Destination address required",
EMSGSIZE = "Message too long",
EPROTOTYPE = "Protocol wrong type for socket",
ENOPROTOOPT = "Protocol not available",
EPROTONOSUPPORT = "Protocol not supported",
ESOCKTNOSUPPORT = "Socket type not supported",
EOPNOTSUPP = "Operation not supported",
EPFNOSUPPORT = "Protocol family not supported",
EAFNOSUPPORT = "Address family not supported by protocol",
EADDRINUSE = "Address already in use",
EADDRNOTAVAIL = "Cannot assign requested address",
ENETDOWN = "Network is down",
ENETUNREACH = "Network is unreachable",
ENETRESET = "Network dropped connection on reset",
ECONNABORTED = "Software caused connection abort",
ECONNRESET = "Connection reset by peer",
ENOBUFS = "No buffer space available",
EISCONN = "Transport endpoint is already connected",
ENOTCONN = "Transport endpoint is not connected",
ESHUTDOWN = "Cannot send after transport endpoint shutdown",
ETOOMANYREFS = "Too many references: cannot splice",
ETIMEDOUT = "Connection timed out",
ECONNREFUSED = "Connection refused",
EHOSTDOWN = "Host is down",
EHOSTUNREACH = "No route to host",
EALREADY = "Operation already in progress",
EINPROGRESS = "Operation now in progress",
ESTALE = "Stale file handle",
EUCLEAN = "Structure needs cleaning",
ENOTNAM = "Not a XENIX named type file",
ENAVAIL = "No XENIX semaphores available",
EISNAM = "Is a named type file",
EREMOTEIO = "Remote I/O error",
EDQUOT = "Disk quota exceeded",
ENOMEDIUM = "No medium found",
EMEDIUMTYPE = "Wrong medium type",
ECANCELED = "Operation canceled",
ENOKEY = "Required key not available",
EKEYEXPIRED = "Key has expired",
EKEYREVOKED = "Key has been revoked",
EKEYREJECTED = "Key was rejected by service",
EOWNERDEAD = "Owner died",
ENOTRECOVERABLE = "State not recoverable",
ERFKILL = "Operation not possible due to RF-kill",
EHWPOISON = "Memory page has hardware error",
ENOTSUP = "Operation not supported",
}
end
k.log(k.L_INFO, "signals")
k.log(k.L_INFO, "platform/oc/signals")
do
k.pullSignal = computer.pullSignal
end
k.log(k.L_INFO, "syscalls")
do
k.syscall = {}
k.log(k.L_INFO, "safety/mutex")
do
local mutexes = {}
function k.syscall.newmutex()
local mtxid = math.random(0, 999999)
while mutexes[mtxid] do
mtxid = math.random(0, 999999)
end
mutexes[mtxid] = true
return mtxid
end
function k.syscall.lockmutex(mtxid)
checkArg(1, mtxid, "number")
if not mutexes[mtxid] then
return nil, k.errno.EIDRM
end
if type(mutexes[mtxid]) == "number" and
mutexes[mtxid] ~= k.syscall.getpid() then
return nil, k.errno.EWOULDBLOCK
end
mutexes[mtxid] = k.syscall.getpid()
return true
end
function k.syscall.unlockmutex(mtxid)
checkArg(1, mtxid, "number")
if not mutexes[mtxid] then
return nil, k.errno.EIDRM
end
if type(mutexes[mtxid]) == "boolean" then
return true
end
if mutexes[mtxid] ~= k.syscall.getpid() then
return nil, k.errno.EPERM
end
mutexes[mtxid] = true
end
function k.syscall.removemutex(mtxid)
checkArg(1, mtxid, "number")
if not mutexes[mtxid] then
return nil, k.errno.EIDRM
end
if mutexes[mtxid] ~= true then
return nil, k.errno.EBUSY
end
mutexes[mtxid] = nil
end
end
end
k.log(k.L_INFO, "scheduler/main")

do
k.log(k.L_INFO, "scheduler/process")
do
local _proc = {}
k.state.pid = 0
k.state.cpid = 0
k.state.ctid = 0
k.state.processes = {[0] = {fds = {}}}
function _proc:resume(...)
for i, thd in ipairs(self.threads) do
local ok, err = coroutine.resume(thd)
if not ok then
end
end
end
function _proc:new(parent, func)
parent = parent or {}
k.state.pid = k.state.pid + 1
local new = setmetatable({
cmdline = {},
pid = k.state.pid,
ppid = parent.pid or 0,
handles = {
[0] = parent.handles[0],
[1] = parent.handles[1],
[2] = parent.handles[2]
},
cputime = 0,
stopped = false,
dead = false,
sid = parent.sid or 0,
pgid = parent.pgid or 0,
uid = parent.uid or 0,
gid = parent.gid or 0,
euid = parent.euid or 0,
egid = parent.egid or 0,
suid = parent.suid or 0,
sgid = parent.sgid or 0,
umask = 255,
cwd = parent.cwd or "/",
root = parent.root or "/",
nice = 0,
signals = {},
threads = {
[1] = {
errno = 0,
sigmask = {},
tid = 1,
wait = 0,
coroutine = coroutine.create(func)
}
},
}, {__index = _proc, __call = _proc.resume})

    k.state.processes[k.state.pid] = new
return new
end
function k.syscall.fork(func)
checkArg(1, func, "function")
local nproc = _proc:new(k.state.processes[k.state.cpid], func)
func(nproc.pid)
return 0
end
function k.syscall.nice(num)
checkArg(1, num, "number")
local cproc = k.state.processes[k.state.cpid]
cproc.nice = math.min(19, math.max(-20, cproc.nice + num))
end
end
function k.syscall.execve(file, args, env)
checkArg(1, file, "string")
checkArg(2, args, "table")
checkArg(3, env, "table")
end
function k.syscall.getpid()
return k.state.cpid
end
function k.syscall.getppid()
return k.state.processes[k.state.cpid].uid
end
function k.syscall.getuid()
return k.state.processes[k.state.cpid].uid
end
function k.syscall.geteuid()
return k.state.processes[k.state.cpid].euid
end
function k.syscall.getgid()
return k.state.processes[k.state.cpid].gid
end
function k.syscall.getegid()
return k.state.processes[k.state.cpid].egid
end
local lastYield = 0
local function shouldYield(procs)
end
local emptySignal = {n = 0}
function k.schedloop()
while k.state.processes[1] do
local to_run = {}
for k, v in pairs(k.state.processes) do
if k ~= 0 and not (v.stopped or v.dead) then
to_run[#to_run+1] = v
end
end
table.sort(to_run, function(a, b)
return a.nice > b.nice
end)
local signal = emptySignal
if shouldYield(to_run) then
signal = table.pack(k.pullSignal())
end
for i, proc in ipairs(to_run) do
local ok, err = proc:resume(sig)
end
end
k.shutdown()
end
end
k.log(k.L_INFO, "vfs/main")
k.log(k.L_INFO, "buffer")
do
local buffer = {}
local bufsize = k.cmdline["io.bufsize"] or 512
function buffer:readline()
if self.bufmode == "none" then
if self.stream.readline then
if self.call == "." then return self.stream.readline()
else return self.stream:readline() end
else
local dat = ""

        repeat
local n = self.stream:read(1) dat = dat .. (n or "")
until n == "\n" or not n

        return dat
end

    else

      while not self.rbuf:match("\n") do
local chunk
if self.call == "." then chunk = self.stream.read(bufsize)
else chunk = self.stream:read(bufsize) end
if not chunk then break end
self.rbuf = self.rbuf .. chunk
end
local n = self.rbuf:find("\n") or #self.rbuf

      local dat = self.rbuf:sub(1, n)
self.rbuf = self.rbuf:sub(n + 1)

      return dat
end
end
function buffer:readnum()
local dat = ""
if self.bufmode == "none" then
error(
"bad argument to 'read' (format 'n' not supported in unbuffered mode)",
0)
end

    local breakonwhitespace = false
while true do
local ch = self:readn(1)
if not ch then
break
end
if ch:match("[%s]") then
if breakonwhitespace then
self.rbuf = ch .. self.rbuf
break
end
else
breakonwhitespace = true

        if not tonumber(dat .. ch .. "0") then
self.rbuf = ch .. self.rbuf
break
end
dat = dat .. ch
end
end
return tonumber(dat)
end
function buffer:readn(n)
while #self.rbuf < n do
local chunk

      if self.call == "." then chunk = self.stream.read(n)
else chunk = self.stream:read(n) end
if not chunk then break end

      self.rbuf = self.rbuf .. chunk
n = n - #chunk
end
local data = self.rbuf:sub(1, n)
self.rbuf = self.rbuf:sub(n + 1)
return data
end
function buffer:readfmt(fmt)
if type(fmt) == "number" then
return self:readn(fmt)
else
fmt = fmt:gsub("%*", "")
if fmt == "a" then        return self:readn(math.huge)
elseif fmt == "l" then        local line = self:readline()
return line:gsub("\n$", "")
elseif fmt == "L" then        return self:readline()
elseif fmt == "n" then        return self:readnum()
else        error("bad argument to 'read' (format '"..fmt.."' not supported)", 0)
end
end
end
local function chvarargs(...)
local args = table.pack(...)
for i=1, args.n, 1 do
checkArg(i, args[i], "string", "number")
end
return args
end
function buffer:read(...)
local args = chvarargs(...)
local ret = {}
for i=1, args.n, 1 do
ret[#ret+1] = self:readfmt(args[i])
end
return table.unpack(ret, 1, args.n)
end
function buffer:write(...)
local args = chvarargs(...)
for i=1, args.n, 1 do
self.wbuf = self.wbuf .. tostring(args[i])
end
local dat
if self.bufmode == "full" then
if #self.wbuf <= bufsize then
return self
end

      dat = self.wbuf
self.wbuf = ""

    elseif self.bufmode == "line" then
local lastnl = #self.wbuf - (self.wbuf:reverse():find("\n") or 0)

      dat = self.wbuf:sub(1, lastnl)
self.wbuf = self.wbuf:sub(lastnl + 1)

    else
dat = self.wbuf
self.wbuf = ""
end
if self.call == "." then self.stream.write(dat)
else self.stream:write(dat) end
return self
end
function buffer:seek(whence, offset)
end
function buffer:flush()
end
function buffer:close()
end
function k.common.fncreatebuffer(read, write, seek, flush, close, mode)
checkArg(1, read, "function")
checkArg(2, write, "function")
checkArg(3, seek, "function")
checkArg(4, flush, "function")
checkArg(5, close, "function")
checkArg(6, mode, "string")
return setmetatable({
stream = {
read = read,
write = write,
seek = seek,
flush = flush,
close = close
},
call = ".",
mode = k.common.charize(mode),
rbuf = "",
wbuf = "",
bufmode = "full"
}, {__index = buffer})
end
function k.common.screatebuffer(stream, mode)
checkArg(1, stream, "table")
checkArg(2, mode, "string")
return setmetatable({
stream = stream,
call = ":",
mode = k.common.charize(mode),
rbuf = "",
wbuf = "",
bufmode = "full"
}, {__index = buffer})
end
k.common.fsmodes = {
f_socket = 0xC000,
f_symlink = 0xA000,
f_regular = 0x8000,
f_blkdev = 0x6000,
f_directory = 0x2000,
f_fifo = 0x1000,
setuid = 0x800,
setgid = 0x400,
sticky = 0x200,
owner_r = 0x100,
owner_w = 0x80,
owner_x = 0x40,
group_r = 0x20,
group_w = 0x10,
group_x = 0x8,
other_r = 0x4,
other_w = 0x2,
other_x = 0x1
}
k.common.inodetypes = {
unknown = 0,
reg_file = 1,
dir = 2,
chrdev = 3,
blkdev = 4,
fifo = 5,
sock = 6,
symlink = 7
}
local mounts = {}
k.state.mounts = mounts
local function split_path(path)
local segments = {}
for part in path:gmatch("[^/]+") do
if part == ".." then
segments[#segments] = nil
elseif part ~= "." then
segments[#segments + 1] = part
end
end
return segments
end
local function clean_path(path)
if path:sub(1,1) ~= "/" then
path = k.syscall.getcwd() .. "/" .. path
end
return "/" .. table.concat(split_path(path), "/")
end
local function fsgetpid()
if not k.state.from_proc then
return 0
else
return k.state.cpid
end
end
local fshand = {
read = function(self, n)
return self.node:read(self.fd, n)
end,
write = function(self, dat)
return self.node:write(self.fd, dat)
end,
seek = function(self, whence, offset)
return self.node:seek(self.fd, whence, offset)
end,
flush = function() end,
close = function(self)
return self.node:close(self.fd)
end
}
k.common.split_path = split_path
k.common.clean_path = clean_path
local find_node
find_node = function(path)
path = clean_path(path)
local rpath = ""
local node, longest, __path = nil, 0, nil
for _path, _node in pairs(mounts) do
if path:sub(1, #_path) == _path and #_path > longest then
longest = #_path
if type(_node) == "string" then
node, rpath = find_node(_node)
else
node = _node
end
        __path = path:sub(#_path + 1)
end
end
if not node then
return nil, k.errno.ENOENT
end
return node, clean_path(rpath .. "/" .. __path)
end
function k.syscall.creat(path, mode)
checkArg(1, path, "string")
checkArg(2, mode, "number")
return k.syscall.open(path, {
creat = true,
wronly = true,
trunc = true
}, mode)
end
function k.syscall.mkdir(path)
checkArg(1, path, "string")
local node, rpath = find_node(path)
if not node then
return nil, rpath
end
return node:mkdir(rpath)
end
function k.syscall.link(path, new)
checkArg(1, path, "string")
checkArg(2, new, "string")
local node, rpath = find_node(path)
if not node then
return nil, rpath
end
local _node, _rpath = find_node(new)
if not _node then
return nil, _rpath
end
if node ~= _node then
return nil, k.errno.EXDEV
end
return node:link(rpath, _rpath)
end
function k.syscall.open(path, flags, mode)
checkArg(1, path, "string")
checkArg(2, flags, "table")
local fds = k.state.processes[fsgetpid()].fds
local node, rpath = find_node(path)
if node and flags.creat and flags.excl then
return nil, k.errno.EEXIST
end
if not node then
if flags.creat then
checkArg(3, mode, "number")
local parent, _rpath = find_node(path:match("(.+)/..-$"))
if not parent then
return nil, _rpath
end
local fd, err = parent:creat(clean_path(_rpath .. "/"
.. path:match(".+/(..-)$")), mode)
if not fd then
return nil, err
end
local n = #fds + 1
fds[n] = k.common.screatebuffer(
setmetatable({fd = fd, node = parent, references = 1},
{__index = fshand}), mode)
return n
else
return nil, rpath
end
end
local fd, err = node:open(rpath, flags, mode)
if not fd then
return nil, err
end
local n = #fds + 1
fds[n] = k.common.screatebuffer(
setmetatable({fd = fd, node = node, references = 1}, {__index = fshand}),
mode)
return n
end
function k.syscall.read(fd, count)
checkArg(1, fd, "number")
checkArg(2, count, "number")
local fds = k.state.processes[fsgetpid()].fds
if not fds[fd] then
return nil, k.errno.EBADF
end
local read = ""
for chunk in function() return
(count > 0 and fds[fd]:read(count)) end do
count = count - #chunk
read = read .. chunk
end
return read
end
function k.syscall.write(fd, data)
checkArg(1, fd, "number")
checkArg(2, data, "string")
local fds = k.state.processes[fsgetpid()].fds
if not fds[fd] then
return nil, k.errno.EBADF
end
return fds[fd]:write(data)
end
function k.syscall.seek(fd, whence, offset)
checkArg(1, fd, "number")
checkArg(2, whence, "string")
checkArg(3, offset, "number")
local fds = k.state.processes[fsgetpid()].fds
if not fds[fd] then
return nil, k.errno.EBADF
end
if whence == "set" or whence == "cur" or whence == "end" then
return nil, k.errno.EINVAL
end
return fds[fd]:seek(whence, offset)
end
function k.syscall.dup(fd)
checkArg(1, fd, "number")
local fds = k.state.processes[fsgetpid()].fds
if not fds[fd] then
return nil, k.errno.EBADF
end
fds[fd].references = fds[fd].references + 1
local n = #fds + 1
fds[n] = fds[fd]
return n
end
function k.syscall.dup2(fd, nfd)
checkArg(1, fd, "number")
checkArg(2, nfd, "number")
local fds = k.state.processes[fsgetpid()].fds
if not fds[fd] then
return nil, k.errno.EBADF
end
if nfd == fd then
return nfd
end
if fds[nfd] then
k.syscall.close(nfd)
end
fds[nfd] = fds[fd]
return true
end
function k.syscall.close(fd)
checkArg(1, fd, "number")
local fds = k.state.processes[fsgetpid()].fds
if not fds[fd] then
return nil, k.errno.EBADF
end
fds[fd].references = fds[fd].references - 1
if fds[fd].references == 0 then
fds[fd]:close()
end
fds[fd] = nil
return true
end
function k.syscall.listdir(path)
checkArg(1, path, "string")
local node, rpath = find_node(path)
if not node then
return nil, rpath
end
return node:list(rpath)
end
k.state.mount_sources = {}
k.state.fs_types = {}
function k.syscall.mount(source, target, fstype, mountflags, fsopts)
checkArg(1, source, "string")
checkArg(2, target, "string")
checkArg(3, fstype, "string")
checkArg(4, mountflags, "table", "nil")
checkArg(5, fsopts, "table", "nil")
if k.syscall.getuid() ~= 0 then
return nil, k.errno.EACCES
end
mountflags = mountflags or {}
if source:find("/") then source = clean_path(source) end
target = clean_path(target)

    if mountflags.move then
if mounts[source] and source ~= "/" then
mounts[target] = mounts[source]
mounts[source] = nil
return true
else
return nil, k.errno.EINVAL
end

    else

      if k.state.mount_sources[source] then
local _source, err = k.state.source_handlers[source]()

        if not _source then
return nil, err
end

        source = _source
elseif k.state.fs_types[fstype] then
local node, err = k.lookup_device(source)
if not node then
return nil, err
end
local _source, err = k.state.fs_types[fstype].create(node)
if not _source then
return nil, err
end
source = _source
else
return nil, k.errno.EINVAL
end
if mounts[target] then
if mountflags.remount then
mounts[target] = source
else
return nil, k.errno.EBUSY
end
end

      local node, rest = find_node(target)
if not node then
return nil, k.errno.ENOENT
end
mounts[target] = source
return true
end
end
function k.syscall.umount(target)
checkArg(1, target, "string")
if k.syscall.getuid() ~= 0 then
return nil, k.errno.EACCES
end
target = clean_path(target)
if mounts[target] then
for pid, process in pairs(k.state.processes) do
if clean_path(process.root
.. "/" .. process.cwd):sub(1, #target) == target then
return nil, k.errno.EBUSY
end
end
mounts[target] = nil
return true
end
return nil, k.errno.EINVAL
end
end
k.log(k.L_INFO, "fs/main")
k.log(k.L_INFO, "fs/managed")
do
k.cmdline["fs.managed.blocksize"] =
k.cmdline["fs.managed.blocksize"] or
2048
local node = {}
local blocksize = k.state.cmdline["fs.managed.blocksize"]
local attr = "<I2I2I2LLLL"
function node:_readpfile(file)
local fd = self.fs.open(file:gsub("([^/]+)/?$", ".%1.attr"), "r")
if not fd then
return nil
end
local data = self.fs.read(fd, math.huge)
self.fs.close(fd)
return data
end

  function node:_writepfile(file, data)
local fd = self.fs.open(file:gsub("([^/]+)/?$", ".%1.attr"), "w")
self.fs.write(fd, data)
self.fs.close(fd)
end
function node:_attributes(file, new, raw)
local data = self:_readpfile(file)
local mode, uid, gid, ctime, atime, mtime, size, nlink
if data then
mode, uid, gid, ctime, atime, mtime, size = attr:unpack(data)
end
if new then
mode, uid, gid, ctime, atime, mtime, size =
new.mode or mode, new.uid or uid, new.gid or gid,
new.ctime or ctime, new.atime or atime, new.mtime or mtime,
new.size or size
self:_writepfile(file, attr:pack(mode, uid, gid, ctime, atime, mtime,
size) .. (new.path or ""))
end
if raw then
return mode, uid, gid, ctime, atime, mtime, size,
#data > 72 and data:sub(73), file
else
return {
mode = mode,
uid = uid,
gid = gid,
ctime = ctime,
atime = atime,
mtime = mtime,
size = size,
file = file,
path = #data > 72 and data:sub(73)
}
end
end
function node:stat(file)
local attr = self:_attributes(file)
return {
ino = -1,
mode = attr.mode,
nlink = 1,
uid = attr.uid,
gid = attr.gid,
size = attr.size,
blksize = blocksize,
blocks = math.ceil(attr.size / blocksize),
atime = attr.atime,
mtime = attr.mtime,
ctime = attr.ctime
}
end
local function parent(path)
local s = k.common.split_path(path)
return "/" .. table.concat(s, "/", 1, s.n - 1)
end

  function node:_create(path, mode)
local p = parent(path)
if not (self.fs.exists(p) and self.fs.isDir(p)) then
return nil, k.errno.ENOENT
end
if mode & 0xF000 == k.common.fsmodes.f_directory then
self.fs.makeDirectory(path)
else
self.fs.close(self.fs.open(path, "w"))
end
local parent = self:_attributes(p)
self:_attributes(path, {
mode = mode,
uid = k.syscall.getuid(),
gid = (mode & k.common.fsmodes.setgid ~= 0) and parent.gid or
k.syscall.getgid(),
ctime = os.time(),
mtime = os.time(),
atime = os.time(),
size = 0,
})
return true
end
function node:mkdir(path, mode)
return self:_create(path, mode | k.common.fsmodes.f_directory)
end
function node:open(file, flags, mode)
if not self.fs.exists(file) then
if not flags.creat then
return nil
else
local ok, err = self:_create(file, mode)
if not ok and err then
return nil, err
end
end
end
local attr = self:_attributes(file)
if attr.mode & 0xF000 == k.common.fsmodes.f_directory then
return nil, k.errno.EISDIR
end
local mode = ""
if flags.rdonly then mode = "r" end
if flags.wronly then mode = "w" end
if flags.rdwr then mode = "rw" end
local fd = self.fs.open(file, mode)
if not fd then
return nil, k.errno.ENOENT
end
local n = #self.fds+1
self.fds[n] = fd
return n
end
function node:read(fd, count)
local data = ""
repeat
local chunk = self.fs.read(fds[fd], count)
data = data .. chunk
count = count - #chunk
until count <= 0
return data
end
function node:write(fd, data)
return self.fs:write(self.fds[fd], data)
end
function node:seek(fd, whence, offset)
return self.fs:seek(self.fds[fd], whence, offset)
end
function node:close(fd)
if self.fds[fd] then
self.fs:close(self.fds[fd])
end
end
function node:unlink(path)
self.fs.remove(path)
end
k.state.fs_types.managed = {
create = function(fsnode)
return setmetatable({fs = fsnode, }, {__index = node})
end
}
end
k.log(k.L_INFO, "permissions")
do
local modes = k.common.fsmodes
local checks = {
r = {modes.owner_r, modes.group_r, modes.other_r},
w = {modes.owner_w, modes.group_w, modes.other_w},
x = {modes.owner_x, modes.group_x, modes.other_x}
}
function k.common.has_permission(info, perm)
local uid = k.syscall.geteuid()
local gid = k.syscall.getegid()
local level = (info.uid == uid and 1) or (info.gid == gid and 2) or 3
return info.mode & checks[perm][level] ~= 0
end
end
k.log(k.L_INFO, "src/ramfs")
do
local _ramfs = {}
function _ramfs:_resolve(path, parent)
local segments = k.common.split_path(path)
local current = self.tree

    for i=1, #segments - (parent and 1 or 0), 1 do
if not current.children then
return nil, k.errno.ENOTDIR
elseif current.children[segments[i]] then
current = current.children[segments[i]]
else
return nil, k.errno.ENOENT
end
end

    return current, parent and segments[#segments]
end
function _ramfs:stat(path)
checkArg(1, path, "string")

    local fblk, err = self:_resolve(path)
if not fblk then
return nil, err
end

    return {
ino = -1,
mode = fblk.mode,
nlink = fblk.nlink,
uid = fblk.uid,
gid = fblk.gid,
size = fblk.size or #fblk.data,
blksize = -1,
blocks = math.ceil(fblk.size / 512),
atime = fblk.atime,
mtime = fblk.mtime,
ctime = fblk.ctime
}
end
function _ramfs:_create(file, ftmode)
checkArg(1, file, "string")
checkArg(2, ftmode, "number")
local parent, name = self:_resolve(file, true)
if not parent then
return nil, name
end
if parent.children[name] then
return nil, k.errno.EEXIST
end
parent.children[name] = {
mode = bit32.bor(ftmode,
k.common.fsmodes.owner_r,
k.common.fsmodes.owner_w,
k.common.fsmodes.group_r,
k.common.fsmodes.other_r),
uid = k.syscall.getuid() or 0,
gid = k.syscall.getgid() or 0,
ctime = os.time(),
mtime = os.time(),
atime = os.time(),
nlink = 1
}
if ftmode == k.common.fsmodes.f_directory then
parent.children[name].children = {}
else
parent.children[name].data = ""
end
return parent.children[name]
end
local fds = {}
function _ramfs:open(file, flags, mode)
checkArg(1, file, "string")
checkArg(2, flags, "table")
checkArg(3, mode, "number", "nil")

    local node, err = self:_resolve(file)
if not node then
if flags.creat then
checkArg(3, mode, "number")

        node, err = self:_create(file, k.common.fsmodes.f_regular)
if not node then
return nil, err
end
else
return nil, err
end
end

    local n = #fds + 1
fds[n] = {
ptr = 0,
node = node,
flags = flags,
read = (flags.rdwr or flags.rdonly) and node.reader and node.reader(n),
write = (flags.rdwr or flags.wronly) and node.writer and node.writer(n),
}

    return n
end
function _ramfs:read(fd, count)
checkArg(1, fd, "number")
checkArg(2, count, "number")

    local _fd = fds[fd]
if not (_fd and (_fd.flags.rdwr or fd.flags.rdonly)) then
return nil, k.errno.EBADF
end

    if _fd.read then
return _fd.read(fd, _fd.ptr, count)
end

    if fd.ptr < #fd.data then
local n = math.min(#fd.data, fd.ptr + count)
local ret = fd.data:sub(fd.ptr, n)
fd.ptr = n + 1
return ret
end
return nil
end
function _ramfs:write(fd, data)
checkArg(1, fd, "number")
checkArg(2, data, "string")

    local _fd = fds[fd]
if not (_fd and (_fd.flags.rdwr or fd.flags.wronly)) then
return nil, k.errno.EBADF
end

    if _fd.write then
return _fd.write(fd, _fd.ptr, data)
end

    if fd.ptr == #fd.data then
fd.data = fd.data .. data
fd.ptr = #fd.data
else
fd.data = fd.data:sub(0, fd.ptr) .. data .. fd.data:sub(fd.ptr+1)
end

    return true
end
function _ramfs:seek(fd, whence, offset)
checkArg(1, fd, "number")
checkArg(2, whence, "string")
checkArg(3, offset, "number")

    local _fd = fds[fd]
if not _fd then
return nil, k.errno.EBADF
end

    if _fd.seek then
return _fd.seek(fd, _fd.ptr, whence, offset)
end

    whence = (whence == "set" and 0)
or (whence == "cur" and _fd.ptr)
or (whence == "end" and #_fd.data)

    if whence + offset > #_fd.data then
return nil, k.errno.EOVERFLOW
end

    _fd.ptr = whence + offset
return _fd.ptr
end
function _ramfs:close(fd)
checkArg(1, fd, "number")

    if not fds[fd] then
return nil, k.errno.EBADF
end

    if fds[fd].close then
fds[fd].close(fd, fds[fd].ptr)
end

    fds[fd] = nil
return true
end
function _ramfs:mkdir(path, mode)
checkArg(1, path, "string")
checkArg(2, mode, "number")
return self:_create(path, bit32.bor(mode, k.common.fsmodes.f_directory))
end
function _ramfs:link(old, new)
checkArg(1, old, "string")
checkArg(2, new, "string")

    local node, err = self:_resolve(old)
if not node then
return nil, err
end

    local newnode, name = self:_resolve(new, true)
if not newnode then
return nil, err
end

    if not newnode.children then
return nil, k.errno.ENOTDIR
end

    if newnode.children[name] then
return nil, k.errno.EEXIST
end

    newnode.children[name] = node
node.nlink = node.nlink + 1
return true
end
function _ramfs:unlink(path)
checkArg(1, path, "string")

    local parent, name = self:_resolve(path, true)
if not parent then
return nil, name
end

    if not parent.children then
return nil, k.errno.ENOTDIR
end

    if not parent.children[name] then
return nil, k.errno.ENOENT
end

    parent.children[name].nlink = parent.children[name].nlink - 1
if parent.children[name].nlink == 0 then
parent.children[name] = nil
end

    return true
end
function _ramfs:list(path)
checkArg(1, path, "string")
local node, err = self:_resolve(path)
if not node then
return nil, err
end
local flist = {}
for k, v in pairs(node.children) do
flist[#flist+1] = k
end
return flist
end
function _ramfs.new(label)
return setmetatable({
tree = {children = {}},
label = label or "ramfs",
}, {__index = _ramfs})
end
k.common.ramfs = _ramfs
end
k.log(k.L_INFO, "tmpfs/soft")
do
k.state.mount_sources.tmpfs = k.common.ramfs.new("tmpfs")
end
k.log(k.L_INFO, "sysfs/main")
do
k.state.sysfs = k.common.ramfs.new("sysfs")
k.state.mount_sources.sysfs = k.state.sysfs
end
k.log(k.L_INFO, "procfs/main")
do
local procfs = k.common.ramfs.new("procfs")
k.state.procfs = procfs
k.state.mount_sources.procfs = procfs
function procfs.registerStaticFile(path, data)
local ent = procfs:_create(path, k.common.fsmodes.f_regular)
ent.writer = function() end
ent.data = k.state.cmdline
end
local function mkdblwrap(func)
return function(n)
return function(...)
return func(n, ...)
end
end
end
function procfs.registerDynamicFile(path, reader, writer)
local ent = procfs:_create(path, k.common.fsmodes.f_regular)
ent.reader = mkdblwrap(reader)
ent.writer = mkdblwrap(writer)
end
end
k.log(k.L_INFO, "devfs/main")
do
k.state.devfs = k.common.ramfs.new("devfs")
k.state.mount_sources.devfs = k.state.devfs
end
k.log(k.L_INFO, "exec/cyx")
do
local magic = 0x43796e6f
local flags = {
lua53 = 0x1,
static = 0x2,
bootable = 0x4,
executable = 0x8,
library = 0x10
}
local _flags = {
lua53 = 0x1,
static = 0x2,
boot = 0x4,
exec = 0x8,
library = 0x10,
}
local accepted = {[0] = true, [5] = true}
local function parse_cyx(fd)
local header = k.syscall.read(fd, 4)
if header ~= "onyC" then
return nil, k.errno.ENOEXEC
end
local version = k.syscall.read(fd, 1):byte()
local flags = k.syscall.read(fd, 1):byte()
local osid = k.syscall.read(fd, 1):byte()
if not accepted[osid] then
return nil, k.errno.ENOEXEC
end
local _
if flags & flags.static == 0 then
local nlink = k.syscall.read(fd, 1):byte()
if nlink == 0 then
return nil, k.errno.ENOEXEC
end
local nlib = k.syscall.read(fd, 1):byte()
local itpfile = k.syscall.read(fd, nlib)
local func, err = k.load_executable(itpfile)
if not func then
k.syscall.close(fd)
return nil, err
end
k.syscall.seek(fd, "set", 0)
return function(...)
local fds = k.state.processes[k.state.cpid].fds
local n = #fds + 1
fds[n] = k.state.processes[0].fds[fd]
k.state.processes[0].fds[fd] = nil
return func(fd, ...)
end
else
local nlink = k.syscall.read(fd, 1):byte()
if nlink > 0 then
return nil, k.errno.ENOEXEC
end
local str = k.syscall.read(fd, math.huge)
k.syscall.close(fd)
return load(str)
end
end
function k.load_cyx(fd)
return parse_cyx(fd)
end
end
k.log(k.L_INFO, "exec/binfmt")
do
local procfs = k.state.procfs
k.state.binfmt = {
cyx = {
type = "CYX",
magic = "onyC",
offset = 0,
interpreter = k.load_cyx,
flags = {P = true, C = true, O = true}
}
}

  procfs.registerDynamicFile("/binfmt", function()end, function(_, data)
local name, mtype, offset, magic, mask, interpreter, flags = data:match(
":([^;]+):([^:]+):(%d-):([^:]+):(0x[%x]-):([^:]+):(.-)")
if not name then return nil, k.errno.EINVAL end
if mtype ~= "E" and mtype ~= "M" then return nil, k.errno.EINVAL end
k.state.binfmt[name] = {
type = mtype,
extension = mtype == "E" and magic,
magic = mtype == "M" and magic,
offset = tonumber(offset) or 0,
interpreter = interpreter,
flags = {}
}
for c in flags:gmatch(".") do k.state.binfmt[name].flags[c] = true end
if k.state.binfmt[name].flags.F then
local err
k.state.binfmt[name].interpreter, err = k.load_executable(interpreter)
if not k.state.binfmt[name].interpreter then
return nil, err
end
end
if k.state.binfmt[name].flags.C then
k.state.binfmt[name].flags.O = true
end
return true
end)
end
k.log(k.L_INFO, "exec/main")
do
local function ld_exec(file, data, fd)
local interp, istat
if type(data.interpreter) == "function" then
interp, istat = data.interpreter, {}
else
interp, istat = k.load_executable(data.interpreter)
if not interp then
k.syscall.close(fd)
return nil, istat
end
end
if data.flags.C then
istat = file
end
if not k.common.has_permission(
{mode = istat.mode, uid = istat.uid, gid = istat.gid}, "x") then
k.syscall.close(fd)
return nil, k.errno.EACCES
end
if data.flags.O then
return function(...)
return interp(fd, ...)
end
else
k.syscall.close(fd)
return function(...)
return interp(file.name, ...)
end
end
end
function k.load_executable(file)
local info, err = k.syscall.stat(file)
if not info then
return nil, err
end
info.name = file
local fd, err = k.syscall.open(file, {rdonly = true})
if not fd then
return nil, err
end
local extension = file:match(".(^%.)+$")
local magic = k.syscall.read(fd, 128)
k.syscall.seek(fd, "set", 0)
for name, data in pairs(k.state.binfmt) do
if data.type == "E" then        if data.extension == extension then
return ld_exec(info, data, fd)
end
elseif data.type == "M" then        local maybe = magic:sub(data.offset, data.offset + #data.magic)
if data.magic == maybe then
return ld_exec(info, data, fd)
end
else
k.syscall.close(fd)
return nil, k.errno.EINVAL
end
end
end
end
k.log(k.L_INFO, "tty")
do
local _tty = {}
function _tty:write(str)
checkArg(1, str, "string")
self.wbuf = self.wbuf .. str
repeat
local idx = self.wbuf:find("\n")
if idx then
local chunk = self.wbuf:sub(1, idx)
self.wbuf = self.wbuf:sub(#chunk + 1)
self:internalwrite(chunk)
end
until not idx
end
function k.opentty(gpu, screen)
end
end
k.log(k.L_INFO, "entering idle loop")
while true do k.pullSignal() end

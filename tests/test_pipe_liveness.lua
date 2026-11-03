-- Liveness test for the persistent pipes: a peer that goes away must be
-- dropped from the live set without waiting for a write to fail. Uses a real
-- socket; no OMP process required.
--
-- The transport is platform-dependent: an AF_UNIX file on Unix, a Win32 named
-- pipe on Windows, where libuv cannot bind or connect an AF_UNIX path at all
-- (bind and connect both fail with EACCES). The behaviour under test — EOF
-- dropping the peer, reconnects succeeding, and a stale handle not evicting a
-- fresh one — is identical either way, so the test follows the platform.
local uv = vim.uv
local is_windows = package.config:sub(1, 1) == "\\"

local function assert_true(cond, msg)
  if not cond then
    print("FAIL: " .. msg)
    os.exit(1)
  end
end

print("Running OMP pipe-liveness tests...")

local omp = require("omp")
local real_cwd = uv.fs_realpath(vim.fn.getcwd()) or vim.fn.getcwd()

local dir = vim.fn.tempname()
vim.fn.mkdir(dir, "p")
-- On Windows the pipe name is the transport and lives in the payload, so the
-- .info file cannot be `${sock}.info`; the plugin reads `pipe` instead.
local sock = is_windows and ("\\\\.\\pipe\\omp-pipe-liveness-" .. tostring(vim.fn.getpid())) or (dir .. "/1.sock")
local info = is_windows and (dir .. "/1.info") or (sock .. ".info")

local server = uv.new_pipe(false)
assert_true(server:bind(sock) ~= nil, "Could not bind test socket")
local accepted
assert_true(server:listen(4, function()
  accepted = uv.new_pipe(false)
  server:accept(accepted)
end) ~= nil, "Could not listen on test socket")

local f = io.open(info, "w")
assert_true(f ~= nil, "Could not write info file")
f:write(vim.json.encode(is_windows and { cwd = real_cwd, pipe = sock } or { cwd = real_cwd }))
f:close()

-- Discovery connects and stores the live pipe handle
omp._check_and_add_socket(info)
vim.wait(2000, function()
  local entry = omp._active_sockets[sock]
  return entry ~= nil and entry ~= true
end, 10)
assert_true(omp._active_sockets[sock] ~= nil, "Socket should still be registered")
assert_true(omp._active_sockets[sock] ~= true, "Connect should replace the placeholder with a pipe handle")

-- A live peer must not be dropped
vim.wait(100)
assert_true(omp._active_sockets[sock] ~= nil, "A live peer must stay registered")

-- Peer goes away: EOF alone must drop it, with no write attempted
accepted:close()
local dropped = vim.wait(2000, function()
  return omp._active_sockets[sock] == nil
end, 10)
assert_true(dropped, "Peer close (EOF) should drop the socket without waiting for a failed write")

-- A dropped socket must be reconnectable (the mtime cache entry was
-- invalidated), and no late callback from the dead pipe may evict the fresh
-- one: drop_socket only removes the handle it was given.
omp._check_and_add_socket(info)
vim.wait(2000, function()
  local entry = omp._active_sockets[sock]
  return entry ~= nil and entry ~= true
end, 10)
assert_true(omp._active_sockets[sock] ~= nil, "A returning peer should reconnect after EOF")
assert_true(omp._active_sockets[sock] ~= true, "Reconnect should store a pipe handle")
vim.wait(200)
assert_true(omp._active_sockets[sock] ~= nil, "The reconnected pipe must not be evicted by the dead pipe's callbacks")

-- Identity guard, forced directly: EOF and a queued write callback are two
-- async drop triggers for the same path, so a stale handle's late error can
-- land after a reconnect. drop_socket must remove only the handle it was given.
local live = omp._active_sockets[sock]
local stale = uv.new_pipe(false)
omp._drop_socket(sock, stale)
assert_true(omp._active_sockets[sock] == live, "drop_socket must not evict a different handle for the same path")

server:close()
vim.fn.delete(dir, "rf")

print("PASS: All pipe-liveness tests passed!")

-- A selection must outlive visual mode, or it is gone before it can be used.
-- `updatetime` fires CursorHold ~1s after Esc, which re-ran update_active_path()
-- in normal mode and republished the collapsed `file:<line>` — so the range a
-- user picked died while they were still reaching for the keybind. The sticky
-- range replays it while the cursor stays inside; leaving the range ends it.
--
-- Driven through the real autocmds rather than update_active_path(), which is
-- local: the bug lived in the CursorHold handler, so that is what must be
-- exercised.
local omp = require("omp")

local function assert_true(cond, msg)
  if not cond then
    print("FAIL: " .. msg)
    os.exit(1)
  end
end

local function assert_eq(expected, actual, msg)
  if expected ~= actual then
    print(string.format("FAIL: %s | Expected: '%s', Got: '%s'", msg, expected, actual))
    os.exit(1)
  end
end

print("Running OMP sticky-selection tests...")

-- Keep the suite off a real OMP session's sockets.
vim.env.XDG_RUNTIME_DIR = vim.fn.tempname()
omp.setup()

local dir = vim.fn.tempname()
vim.fn.mkdir(dir, "p")
-- `fnamemodify(":.")` only shortens paths under the cwd, and the payload is
-- asserted in that relative form, so make the temp dir the cwd.
vim.cmd.cd(vim.fn.fnameescape(dir))
local file = "sample.lua"
local fh = assert(io.open(file, "w"))
for i = 1, 40 do
  fh:write(("line %d\n"):format(i))
end
fh:close()
vim.cmd("edit! " .. vim.fn.fnameescape(file))

local function fire(event)
  vim.api.nvim_exec_autocmds(event, {})
end

local function state()
  return (omp._broadcast_state())
end

local function move_to(line)
  vim.api.nvim_win_set_cursor(0, { line, 0 })
  fire("CursorMoved")
end

-- Select 10..15, then leave visual mode: Esc alone changes nothing, and the
-- CursorHold that follows must keep the range instead of collapsing it.
vim.api.nvim_win_set_cursor(0, { 10, 0 })
vim.cmd("normal! V5j")
fire("CursorMoved")
assert_eq("sample.lua:10-15", state(), "visual selection should publish a range")

vim.cmd("normal! \27")
fire("CursorHold")
fire("CursorHoldI")
assert_eq("sample.lua:10-15", state(), "CursorHold after Esc must not collapse the range")

-- Inside the range the range is replayed, not the cursor line.
move_to(12)
assert_eq("sample.lua:10-15", state(), "moving inside the range should keep the range")
move_to(15)
assert_eq("sample.lua:10-15", state(), "the last line of the range is inside it")

-- Leaving ends the selection for good.
move_to(16)
assert_eq("sample.lua:16", state(), "leaving the range should collapse to the cursor line")
move_to(17)
assert_eq("sample.lua:17", state(), "the collapse must not be reverted by further motion")

-- A collapsed selection still reports as a range, and survives the same way.
vim.api.nvim_win_set_cursor(0, { 20, 0 })
vim.cmd("normal! V")
fire("CursorMoved")
assert_eq("sample.lua:20-20", state(), "a single-line selection should be a collapsed range")
vim.cmd("normal! \27")
fire("CursorHold")
assert_eq("sample.lua:20-20", state(), "a collapsed range should survive CursorHold too")

-- Switching buffers drops it: the range belongs to the buffer that made it.
vim.cmd("edit! " .. vim.fn.fnameescape("other.lua"))
fire("BufEnter")
assert_eq("other.lua:1", state(), "switching buffers should drop the sticky range")

vim.fn.delete(dir, "rf")
print("PASS: All sticky-selection tests passed!")

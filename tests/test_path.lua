local omp = require("omp")

local function assert_eq(expected, actual, msg)
  if expected ~= actual then
    print(string.format("FAIL: %s | Expected: '%s', Got: '%s'", msg, expected, actual))
    os.exit(1)
  end
end

-- `fnamemodify(":.")` yields host separators, so on Windows the payload reads
-- `src\main.lua:42`. The separators are not what these tests assert, so they are
-- normalized rather than pinned per platform.
local function norm(value)
  return (value:gsub("\\", "/"))
end

local function assert_path(expected, actual, msg)
  assert_eq(expected, norm(actual), msg)
end

print("Running OMP tests...")

-- Test: Ignores special buffers
assert_eq("", omp._get_display_path("term://foo", "terminal", 10, 10, "n"), "Should ignore terminal buffers")
assert_eq("", omp._get_display_path("nofile", "nofile", 1, 1, "n"), "Should ignore nofile buffers")

-- Test: Ignores empty buffer names
assert_eq("", omp._get_display_path("", "", 10, 10, "n"), "Should ignore empty buffer names")

-- Test: Formats normal mode correctly
assert_path(
  "src/main.lua:42",
  omp._get_display_path("src/main.lua", "", 42, 42, "n"),
  "Should format single line in normal mode"
)

-- Test: Formats visual mode ranges
assert_path(
  "src/main.lua:40-45",
  omp._get_display_path("src/main.lua", "", 45, 40, "v"),
  "Should format visual selection bottom-up"
)
assert_path(
  "src/main.lua:40-45",
  omp._get_display_path("src/main.lua", "", 40, 45, "v"),
  "Should format visual selection top-down"
)
assert_path(
  "src/main.lua:40-45",
  omp._get_display_path("src/main.lua", "", 45, 40, "V"),
  "Should format line visual selection"
)

-- A collapsed selection must still be a range. `file:642-642` is the only thing
-- that distinguishes "the user selected this line" from "the cursor is parked
-- here"; without it both payloads are byte-identical and the intent is lost.
assert_path(
  "src/main.lua:42-42",
  omp._get_display_path("src/main.lua", "", 42, 42, "V"),
  "Should report a single-line linewise selection as a collapsed range"
)
assert_path(
  "src/main.lua:42-42",
  omp._get_display_path("src/main.lua", "", 42, 42, "v"),
  "Should report a single-line characterwise selection as a collapsed range"
)
assert_path(
  "src/main.lua:42-42",
  omp._get_display_path("src/main.lua", "", 42, 42, "\22"),
  "Should report a single-line blockwise selection as a collapsed range"
)

-- …while normal mode stays plain, so the two remain distinguishable.
assert_path(
  "src/main.lua:42",
  omp._get_display_path("src/main.lua", "", 42, 42, "n"),
  "Normal mode must not use a range"
)

print("PASS: All tests passed!")

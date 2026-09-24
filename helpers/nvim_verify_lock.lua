-- Verify every plugin in a lazy.nvim lockfile is checked out at its locked commit.
--
--   nvim -l helpers/nvim_verify_lock.lua <lockfile> [<lazy_dir>]
--
-- <lazy_dir> defaults to stdpath("data")/lazy, so it follows the same XDG / Windows
-- %LOCALAPPDATA%\nvim-data rules as the nvim that runs it. Shared by
-- helpers/install_nvim.sh (macOS + Linux) and windows/install_nvim.ps1, and runs
-- inside nvim itself so the check needs no python3 (on Windows `python3` is often
-- the Microsoft Store stub) and no shell heredoc.
--
-- Fails closed: a plugin that is missing, at another commit, has modified or
-- deleted tracked files, or has a missing/out-of-sync submodule is a failure.
-- `nvim --headless +qa` exits 0 even on a broken config, so this is the real check.

local lockfile, lazy_dir = arg[1], arg[2]
if not lockfile then
  io.stderr:write("usage: nvim -l nvim_verify_lock.lua <lockfile> [<lazy_dir>]\n")
  os.exit(2)
end
lazy_dir = lazy_dir or (vim.fn.stdpath("data") .. "/lazy")

-- print() under `nvim -l` drops the final newline; write whole lines instead.
local function say(s)
  io.stdout:write(s, "\n")
end

local f = io.open(lockfile, "r")
local ok, lock = false, nil
if f then
  ok, lock = pcall(vim.json.decode, f:read("*a"))
  f:close()
end
if not ok or type(lock) ~= "table" then
  say("  lockfile unreadable: " .. lockfile)
  os.exit(2)
end

local function git(dir, ...)
  local r = vim.system({ "git", "-C", dir, ... }, { text = true }):wait()
  if r.code ~= 0 then
    return nil
  end
  return r.stdout or ""
end

local names = vim.tbl_keys(lock)
table.sort(names)
local miss, bad, good = {}, {}, 0
for _, name in ipairs(names) do
  local want = type(lock[name]) == "table" and lock[name].commit or nil
  local dir = lazy_dir .. "/" .. name
  local head = vim.uv.fs_stat(dir .. "/.git") and git(dir, "rev-parse", "HEAD")
  if not head then
    table.insert(miss, name)
  else
    -- Right HEAD is not enough: a corrupt checkout (modified/deleted tracked files)
    -- or a dirty submodule also fails.
    local dirty = git(dir, "status", "--porcelain", "--untracked-files=no")
    local subm = git(dir, "submodule", "status", "--recursive")
    local subm_bad = subm == nil
    for line in (subm or ""):gmatch("[^\n]+") do
      if line:match("^[-+U]") then
        subm_bad = true
      end
    end
    if (want and vim.trim(head) ~= want) or dirty == nil or vim.trim(dirty) ~= "" or subm_bad then
      table.insert(bad, name)
    else
      good = good + 1
    end
  end
end

say(("  %d/%d plugins at their locked commit (clean checkout)"):format(good, #names))
if #miss > 0 then
  say("  missing:  " .. table.concat(miss, " "))
end
if #bad > 0 then
  say("  mismatch/dirty: " .. table.concat(bad, " "))
end
os.exit((#miss == 0 and #bad == 0) and 0 or 1)

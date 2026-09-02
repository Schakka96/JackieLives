-- tools/tcheck.lua — the one assertion helper every offline suite in this repo uses.
--
-- There used to be fifteen copies of this, one per test file, in four slightly different shapes:
-- check(name, ok, detail), ok(cond, msg) with the arguments the other way round, check(name, cond,
-- extra), and check(name, got, want). Three different footers printed three different summaries, and
-- two of them exited 0 on failure formats nobody was reading. That is a lot of surface for something
-- whose whole job is to print a line and count it.
--
-- Usage:
--     local T     = dofile("tools/tcheck.lua")
--     local check = T.check                       -- check(name, ok, detail)
--     local ok    = T.ok                          -- ok(cond, msg)      -- arguments reversed
--     local eq    = T.eq                          -- eq(name, got, want)
--     ...
--     T.finish()                                  -- prints "N checks, M failed" and exits 1 on any
--
-- `T.checks` / `T.fails` stay readable, because a few suites branch on the running count.
local T = { checks = 0, fails = 0 }

function T.check(name, cond, detail)
  T.checks = T.checks + 1
  if cond then
    print("  ok   " .. name)
  else
    T.fails = T.fails + 1
    print("  FAIL " .. name .. (detail and ("\n         " .. tostring(detail)) or ""))
  end
  return cond and true or false
end

-- Same thing with the arguments the other way round.
function T.ok(cond, msg, detail) return T.check(msg, cond, detail) end

-- Value comparison: prints what it got when it disagrees, which is the whole point of the shape.
function T.eq(name, got, want)
  return T.check(name, got == want,
                 got ~= want and ("got=" .. tostring(got) .. "  want=" .. tostring(want)) or nil)
end

function T.section(s) print("\n" .. s) end

function T.finish()
  print(("\n%d checks, %d failed"):format(T.checks, T.fails))
  os.exit(T.fails == 0 and 0 or 1)
end

return T

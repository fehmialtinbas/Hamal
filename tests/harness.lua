-- Tiny test runner; works on Lua 5.1 (the game's version) and newer.
local T = { passed = 0, failed = 0, failures = {} }
local group = ""

function T.describe(name, fn)
  group = name
  fn()
end

function T.it(name, fn)
  local ok, err = pcall(fn)
  if ok then
    T.passed = T.passed + 1
  else
    T.failed = T.failed + 1
    T.failures[#T.failures + 1] = group .. " > " .. name .. "\n    " .. tostring(err)
  end
end

function T.eq(actual, expected, label)
  if actual ~= expected then
    error(("%sexpected %s, got %s"):format(label and (label .. ": ") or "", tostring(expected), tostring(actual)), 2)
  end
end

function T.truthy(value, label)
  if not value then error(label or "expected a truthy value", 2) end
end

function T.report()
  for _, failure in ipairs(T.failures) do
    print("FAIL " .. failure)
  end
  print(("%d passed, %d failed"):format(T.passed, T.failed))
  return T.failed == 0
end

return T

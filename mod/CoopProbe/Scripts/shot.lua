-- F1 (both windows): ask the engine itself for a screenshot of what it renders.
-- Files go to %LOCALAPPDATA%\Genesis_EGS\Saved\Screenshots\WindowsNoEditor
local M = {}
function M.take(log, role)
  local pc
  for _, x in ipairs(FindAllOf("PlayerController") or {}) do
    local ok, loc = pcall(function() return x:IsValid() and x:IsLocalController() end)
    if ok and loc then pc = x end
  end
  if not pc then log("shot: no local PC"); return end
  local ksl = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
  for _, c in ipairs({ "shot", "HighResShot 1" }) do
    local ok, err = pcall(function() ksl:ExecuteConsoleCommand(pc, c, pc) end)
    log("shot (" .. tostring(role) .. "): exec '" .. c .. "' -> " .. (ok and "ok" or tostring(err)))
  end
end
return M

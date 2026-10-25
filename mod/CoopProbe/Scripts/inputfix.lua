-- F2: guest input/movement diagnosis (1st press) and fix attempts (2nd press). Works in any window.
local M = {}
local function safe(f, d) local ok, v = pcall(f); if ok then return v end; return d end
local function nm(o) return safe(function() return o:GetFName():ToString() end, "?") end
local function v3(v) return v and string.format("%.0f,%.0f,%.0f", v.X, v.Y, v.Z) or "?" end
M.pressed = 0
local KEYWORDS = { "load", "input", "block", "lock", "enable", "disable", "spawn", "ready", "init", "start", "busy", "menu", "pause", "frozen", "freeze", "dead", "alive", "control", "move", "walk", "intro", "tutorial", "cine" }

local function interesting(n)
  local l = n:lower()
  for _, k in ipairs(KEYWORDS) do if l:find(k, 1, true) then return true end end
  return false
end

local function dump_bools(log, obj, label)
  local cls = safe(function() return obj:GetClass() end)
  if not cls then return end
  local out = {}
  local c = cls
  for _ = 1, 6 do
    if not c or not safe(function() return c:IsValid() end, false) then break end
    local cname = nm(c)
    safe(function()
      c:ForEachProperty(function(prop)
        local pn = prop:GetFName():ToString()
        if interesting(pn) then
          local v = safe(function() return obj[pn] end)
          local t = type(v)
          if t == "boolean" or t == "number" then table.insert(out, pn .. "=" .. tostring(v)) end
        end
      end)
    end)
    if cname == "PlayerController" or cname == "Character" then break end
    c = safe(function() return c:GetSuperStruct() end)
  end
  log(label .. " " .. nm(obj) .. ": " .. table.concat(out, " "))
end

local function local_pc()
  for _, x in ipairs(FindAllOf("PlayerController") or {}) do
    if x:IsValid() and safe(function() return x:IsLocalController() end, false) then return x end
  end
end

function M.press(log)
  M.pressed = M.pressed + 1
  local pc = local_pc()
  if not pc then log("input: no local PC"); return end
  local pawn = pc.Pawn
  if M.pressed % 2 == 1 then
    log("---- input dump ----")
    log("PC " .. nm(pc) .. " moveIgnored=" .. tostring(safe(function() return pc:IsMoveInputIgnored() end, "?"))
      .. " lookIgnored=" .. tostring(safe(function() return pc:IsLookInputIgnored() end, "?"))
      .. " cursor=" .. tostring(safe(function() return pc.bShowMouseCursor end, "?")))
    dump_bools(log, pc, "PC vars")
    if pawn and pawn:IsValid() then
      local cm = safe(function() return pawn.CharacterMovement end)
      log("PAWN " .. nm(pawn) .. " loc=" .. v3(safe(function() return pawn:K2_GetActorLocation() end))
        .. " vel=" .. v3(safe(function() return pawn:GetVelocity() end))
        .. " inputEnabled=" .. tostring(safe(function() return pawn:InputEnabled() end, "?"))
        .. " role=" .. tostring(safe(function() return pawn.Role end, "?")))
      if cm then
        log("  movement mode=" .. tostring(safe(function() return cm.MovementMode end, "?"))
          .. " gravity=" .. tostring(safe(function() return cm.GravityScale end, "?"))
          .. " maxWalk=" .. tostring(safe(function() return cm.MaxWalkSpeed end, "?"))
          .. " active=" .. tostring(safe(function() return cm:IsActive() end, "?")))
      end
      dump_bools(log, pawn, "PAWN vars")
    else
      log("PAWN none")
    end
    -- what the other side thinks: every player character location
    for _, ch in ipairs(FindAllOf("Eden_PlayerCharacter_C") or {}) do
      if ch:IsValid() then log("CHAR " .. nm(ch) .. " loc=" .. v3(safe(function() return ch:K2_GetActorLocation() end)) .. " role=" .. tostring(safe(function() return ch.Role end, "?"))) end
    end
    log("---- end (press F2 again to try the fixes) ----")
  else
    log("---- input fixes ----")
    log("ResetIgnoreInputFlags -> " .. tostring(pcall(function() pc:ResetIgnoreInputFlags() end)))
    log("SetIgnoreMoveInput(false) -> " .. tostring(pcall(function() pc:SetIgnoreMoveInput(false) end)))
    log("SetIgnoreLookInput(false) -> " .. tostring(pcall(function() pc:SetIgnoreLookInput(false) end)))
    if pawn and pawn:IsValid() then
      log("pawn EnableInput -> " .. tostring(pcall(function() pawn:EnableInput(pc) end)))
      local cm = safe(function() return pawn.CharacterMovement end)
      if cm then log("SetMovementMode(Walking) -> " .. tostring(pcall(function() cm:SetMovementMode(1, 0) end))) end
    end
    local wbl = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
    log("SetInputMode_GameOnly -> " .. tostring(pcall(function() wbl:SetInputMode_GameOnly(pc) end)))
    log("---- end fixes: try to move, switch weapon, open the map ----")
  end
end
return M

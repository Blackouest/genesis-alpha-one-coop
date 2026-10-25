-- Deep dump for diagnosing two-player state (read-only, plus F6 camera recover)
local M = {}
local function safe(f, d) local ok, v = pcall(f); if ok then return v end; return d end
local function name(o) return safe(function() return (o and o:IsValid()) and o:GetFullName() or "none" end, "err") end
local function short(o) return safe(function() return (o and o:IsValid()) and o:GetFName():ToString() or "none" end, "err") end

function M.dump(log)
  log("---- deep dump ----")
  for _, pc in ipairs(FindAllOf("PlayerController") or {}) do
    if pc:IsValid() then
      local loc = safe(function() return pc:IsLocalController() end, "?")
      log(string.format("PC %s local=%s pawn=%s", short(pc), tostring(loc), short(pc.Pawn)))
      local cm = safe(function() return pc.PlayerCameraManager end)
      if cm and cm:IsValid() then
        log(string.format("   cam viewtarget=%s fadeAmount=%s enableFading=%s",
          short(safe(function() return cm.ViewTarget.Target end)),
          tostring(safe(function() return cm.FadeAmount end, "?")),
          tostring(safe(function() return cm.bEnableFading end, "?"))))
      else log("   cam: none") end
      log("   hud=" .. short(safe(function() return pc.MyHUD end)))
    end
  end
  for _, ch in ipairs(FindAllOf("Eden_PlayerCharacter_C") or {}) do
    if ch:IsValid() then
      local l = safe(function() return ch:K2_GetActorLocation() end)
      log(string.format("CHAR %s controller=%s role=%s remote=%s loc=%s",
        short(ch), short(safe(function() return ch.Controller end)),
        tostring(safe(function() return ch.Role end, "?")), tostring(safe(function() return ch.RemoteRole end, "?")),
        l and string.format("%.0f,%.0f,%.0f", l.X, l.Y, l.Z) or "?"))
    end
  end
  local pc0 = FindFirstOf("PlayerController")
  local world = pc0 and pc0:IsValid() and pc0:GetWorld()
  if world then
    local n = safe(function() return world.StreamingLevels:GetArrayNum() end, "?")
    log("StreamingLevels: " .. tostring(n))
    safe(function()
      world.StreamingLevels:ForEach(function(i, e)
        local sl = e:get()
        log(string.format("   [%d] %s loaded=%s", i, safe(function() return sl:GetWorldAssetPackageName():ToString() end, short(sl)),
          short(safe(function() return sl:GetLoadedLevel() end))))
      end)
    end)
  end
  local shown = 0
  for _, w in ipairs(FindAllOf("UserWidget") or {}) do
    if w:IsValid() and safe(function() return w:IsInViewport() end, false) then
      log("WIDGET in viewport: " .. short(w) .. " class=" .. short(w:GetClass())); shown = shown + 1
    end
  end
  log("widgets in viewport: " .. shown)
  for _, w in ipairs(FindAllOf("UserWidget") or {}) do
    local cn = w:IsValid() and short(w:GetClass()) or ""
    if cn:lower():find("load") or cn:lower():find("fade") or cn:lower():find("black") or cn:lower():find("transit") or cn:lower():find("screen") then
      log("WIDGET (any) " .. short(w) .. " class=" .. cn .. " vis=" .. tostring(safe(function() return w:GetVisibility() end, "?")))
    end
  end
  log("---- end ----")
end

-- F6: on this window's local controller, stop camera fade and view own pawn
function M.recover(log)
  for _, pc in ipairs(FindAllOf("PlayerController") or {}) do
    if pc:IsValid() and safe(function() return pc:IsLocalController() end, false) then
      local cm = pc.PlayerCameraManager
      if cm and cm:IsValid() then
        -- StopCameraFade in 4.23 jumps to the fade TARGET (black). Force the fade amount to 0 instead.
        local ok1, e1 = pcall(function() cm:SetManualCameraFade(0.0, { R = 0.0, G = 0.0, B = 0.0, A = 1.0 }, false) end)
        log("SetManualCameraFade(0) on " .. short(pc) .. " -> " .. (ok1 and "ok" or tostring(e1)))
      end
      local p = pc.Pawn
      if p and p:IsValid() then safe(function() pc:SetViewTargetWithBlend(p, 0.0, 0, 0.0, false) end); log("ViewTarget -> " .. short(p)) end
    end
  end
end
return M

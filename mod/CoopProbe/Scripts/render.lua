-- F2: dump what can make the whole screen black (read-only)
local M = {}
local function safe(f, d) local ok, v = pcall(f); if ok then return v end; return d end
local function short(o) return safe(function() return (o and o:IsValid()) and o:GetFName():ToString() or "none" end, "err") end
local function num(v) if type(v) == "number" then return string.format("%.3f", v) end; return tostring(v) end

function M.dump(log)
  log("---- render dump ----")
  local pc
  for _, x in ipairs(FindAllOf("PlayerController") or {}) do
    if x:IsValid() and safe(function() return x:IsLocalController() end, false) then pc = x end
  end
  if not pc then log("no local PC"); return end
  local world = pc:GetWorld()
  -- 1) Material parameter collections: global, shared by every player in the world
  local kml = StaticFindObject("/Script/Engine.Default__KismetMaterialLibrary")
  for _, mpc in ipairs(FindAllOf("MaterialParameterCollection") or {}) do
    if mpc:IsValid() and not short(mpc):find("^Default__") then
      local parts = {}
      safe(function()
        mpc.ScalarParameters:ForEach(function(i, e)
          local p = e:get()
          local n = p.ParameterName
          local cur = safe(function() return kml:GetScalarParameterValue(pc, mpc, n) end, "?")
          table.insert(parts, n:ToString() .. "=" .. num(cur) .. "(def " .. num(safe(function() return p.DefaultValue end, "?")) .. ")")
        end)
      end)
      log("MPC " .. mpc:GetFullName() .. ": " .. table.concat(parts, ", "))
    end
  end
  -- 2) Camera on the local pawn
  local pawn = pc.Pawn
  for _, cam in ipairs(FindAllOf("CameraComponent") or {}) do
    if cam:IsValid() and safe(function() return cam:GetOwner() == pawn end, false) then
      log(string.format("pawn camera %s active=%s ppWeight=%s",
        short(cam), tostring(safe(function() return cam:IsActive() end, "?")), num(safe(function() return cam.PostProcessBlendWeight end, "?"))))
    end
  end
  local cm = pc.PlayerCameraManager
  local loc = safe(function() return cm:GetCameraLocation() end)
  log("camera location: " .. (loc and string.format("%.0f,%.0f,%.0f", loc.X, loc.Y, loc.Z) or "?"))
  -- 3) Post-process volumes
  for _, v in ipairs(FindAllOf("PostProcessVolume") or {}) do
    if v:IsValid() then
      log(string.format("PPV %s enabled=%s unbound=%s weight=%s", short(v),
        tostring(safe(function() return v.bEnabled end, "?")), tostring(safe(function() return v.bUnbound end, "?")),
        num(safe(function() return v.BlendWeight end, "?"))))
    end
  end
  -- 4) Pawn visibility and the HUD widget
  log("pawn hidden=" .. tostring(safe(function() return pawn.bHidden end, "?")))
  for _, w in ipairs(FindAllOf("PlayerHudWidget_C") or {}) do
    if w:IsValid() then log("PlayerHudWidget " .. short(w) .. " vis=" .. tostring(safe(function() return w:GetVisibility() end, "?")) .. " opacity=" .. num(safe(function() return w:GetRenderOpacity() end, "?"))) end
  end
  log("---- end render ----")
end
return M

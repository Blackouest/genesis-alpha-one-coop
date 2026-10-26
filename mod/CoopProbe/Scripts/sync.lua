-- v28: small host -> guest state sync over the message channel
--   ammo|n0,n1,...   the host's PlayerState.Ammunition (a shared pool; the guest's local fire checks it)
--   hp|health|max    the guest pawn's real health, computed on the host
local M = {}
local function safe(f, d) local ok, v = pcall(f); if ok then return v end; return d end
local function valid(o) return o ~= nil and safe(function() return o:IsValid() end, false) end
M.last_ammo, M.last_hp = nil, nil

local function players()
  local host, guest
  for _, ch in ipairs(FindAllOf("Eden_PlayerCharacter_C") or {}) do
    if valid(ch) and safe(function() return ch.Role end, 0) == 3 then
      if safe(function() return ch:IsLocallyControlled() end, false) then host = ch else guest = ch end
    end
  end
  return host, guest
end

local function ammo_list(ps)
  local t = {}
  safe(function() ps.Ammunition:ForEach(function(i, e) table.insert(t, tostring(e:get())) end) end)
  return table.concat(t, ",")
end

-- host, every tick of the auto loop
function M.host_tick(log)
  local ch = package.loaded["channel"]; if not ch then return end
  local host, guest = players()
  if not (valid(host) and valid(guest)) then return end
  local pc = safe(function() return guest:GetController() end)
  if not valid(pc) then return end
  local a = ammo_list(safe(function() return host.PlayerState end))
  if a ~= "" and a ~= M.last_ammo then ch.to_guest(log, pc, "ammo|" .. a); M.last_ammo = a end
  local h, mx = safe(function() return guest.Health end), safe(function() return guest.HealthMax end)
  local hp = tostring(h) .. "|" .. tostring(mx)
  if type(h) == "number" and hp ~= M.last_hp then ch.to_guest(log, pc, "hp|" .. hp); M.last_hp = hp end
end

local function me()
  for _, ch in ipairs(FindAllOf("Eden_PlayerCharacter_C") or {}) do
    if valid(ch) and safe(function() return ch:IsLocallyControlled() end, false) then return ch end
  end
end

-- guest: the game's own hit feedback (camera shake + red post-process), which only ran on the host copy
local SHAKE = "/Game/EdenAlpha1/Blueprints/Player/Camera/BP_CameraShake_Player%s.BP_CameraShake_Player%s_C"
function M.hit_effect(log, p, dmg)
  local kind = dmg < 20 and "HitVeryLight" or (dmg < 40 and "HitLight" or "HitMelee")
  local path = SHAKE:format(kind, kind)
  local cls = safe(function() return StaticFindObject(path) end)
  if not valid(cls) then cls = safe(function() return LoadAsset(path) end) end
  local pc = safe(function() return p:GetController() end)
  local a = valid(cls) and valid(pc) and pcall(function() pc:ClientPlayCameraShake(cls, 10, 0, {Pitch=0, Yaw=0, Roll=0}) end)
  local b = pcall(function() p.Timeline_HitPostprocess:PlayFromStart() end)
  log("sync: hit effect -" .. tostring(dmg) .. " shake(" .. kind .. ")=" .. tostring(a) .. " postprocess=" .. tostring(b))
end

-- guest, on a message from the host
function M.on_host_message(log, body)
  local list = body:match("^ammo|(.*)$")
  if list then
    local p = me(); local ps = p and safe(function() return p.PlayerState end)
    if not valid(ps) then log("sync: no local PlayerState"); return true end
    local t = {}
    for v in list:gmatch("[^,]+") do table.insert(t, tonumber(v)) end
    local ok, err = pcall(function() ps.Ammunition = t end)
    log("sync: ammo (" .. #t .. " entries) -> " .. (ok and "set" or tostring(err)) .. ", local now " .. ammo_list(ps))
    return true
  end
  local h, mx = body:match("^hp|([^|]+)|([^|]+)$")
  if h then
    local p = me(); if not p then return true end
    h, mx = tonumber(h), tonumber(mx)
    local before = M.guest_hp
    M.guest_hp = h
    if before and h and h < before then M.hit_effect(log, p, before - h) end
    safe(function() p.Health = h end)
    if mx then safe(function() p.HealthMax = mx end) end
    local hud = safe(function() return p.PlayerHud end)
    if valid(hud) and not M.hud_shown then
      M.hud_shown = true
      local huds = FindAllOf("PlayerHudWidget_C") or {}
      log("sync: hud " .. hud:GetFName():ToString() .. " IsHudVisible=" .. tostring(safe(function() return hud.IsHudVisible end))
        .. " inViewport=" .. tostring(safe(function() return hud:IsInViewport() end)) .. " (" .. #huds .. " hud widgets)")
      local a = pcall(function() hud:UpdateShowPlayerHud(true) end)
      local b = pcall(function() hud:ShowFPSHud() end)
      local c = pcall(function() hud.PlayerHealthWidget:SetVisibility(4) end)
      log("sync: hud shown: UpdateShowPlayerHud=" .. tostring(a) .. " ShowFPSHud=" .. tostring(b) .. " healthWidget=" .. tostring(c))
    end
    local ok = valid(hud) and pcall(function() hud:UpdatePlayerHealth(h, mx or 100) end)
    log("sync: health " .. tostring(h) .. "/" .. tostring(mx) .. " hud=" .. tostring(ok))
    return true
  end
  return false
end
return M

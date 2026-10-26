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

-- host: the guest's death runs on the host copy of its pawn. Keep the death screen off the host HUD,
-- tell the guest, and revive it next to the host after a few seconds (the game's own revive leaves it dead).
M.dead_ticks = 0
function M.death_tick(log, host, guest, pc)
  local gh, hh = safe(function() return guest.PlayerHud end), safe(function() return host.PlayerHud end)
  if valid(gh) and valid(hh) and gh:GetFullName() == hh:GetFullName() then
    safe(function() guest.PlayerHud = nil end); log("sync: guest pawn pointed at the host HUD again -> cleared")
  end
  local dead = safe(function() return guest.IsDead end, false)
  local h = safe(function() return guest.Health end, 1)
  if dead or (type(h) == "number" and h <= 0) then
    M.dead_ticks = M.dead_ticks + 1
    if M.dead_ticks == 1 then
      log("sync: guest died (IsDead=" .. tostring(dead) .. " health=" .. tostring(h) .. " block=" .. tostring(safe(function() return guest.BlockActionFPSPlayerInput end)) .. ")")
      local ch = package.loaded["channel"]; if ch then ch.to_guest(log, pc, "dead|") end
    elseif M.promo_done or M.dead_ticks >= 8 then
      local soft = M.promo_done
      M.promo_done = false
      M.dead_ticks = 0
      local r = {}
      r[#r+1] = pcall(function() guest.IsDead = false end)
      r[#r+1] = pcall(function() guest.BlockActionFPSPlayerInput = false end)
      r[#r+1] = pcall(function() guest.Health = guest.HealthMax end)
      r[#r+1] = pcall(function() guest.CharacterMovement:SetActive(true, false) end)
      r[#r+1] = pcall(function() guest.Temp_bool_IsClosed_Variable_6 = false end)
      local loc = (not soft) and safe(function() return host:K2_GetActorLocation() end)
      if loc then
        r[#r+1] = pcall(function() guest:K2_SetActorLocation({X = loc.X + 120, Y = loc.Y, Z = loc.Z + 20}, false, {}, true) end)
      end
      r[#r+1] = pcall(function() pc:SetViewTargetWithBlend(guest, 0, 0, 0, false) end)
      for _, cam in ipairs(FindAllOf("BP_DeathCamera_C") or {}) do pcall(function() cam:K2_DestroyActor() end) end
      local t = {}; for _, v in ipairs(r) do t[#t+1] = tostring(v) end
      log("sync: guest revived " .. (soft and "as the promoted crew member" or "next to the host (no promotion)") .. " (" .. table.concat(t, ",") .. ")")
      local ch = package.loaded["channel"]; if ch then ch.to_guest(log, pc, "revive|") end
    end
  else
    if M.dead_ticks > 0 then log("sync: guest alive again by itself (health=" .. tostring(h) .. ")") end
    M.dead_ticks = 0
  end
end

-- host: the guest pawn's Blueprint feedback (camera shake, red post-process, death fade, promotion screen)
-- targets player 0, i.e. the host. Undo it on the host right after the game runs it.
local function host_fix(log, why)
  local host = players()
  if not valid(host) then return end
  local pc = safe(function() return host:GetController() end)
  local pcm = valid(pc) and safe(function() return pc.PlayerCameraManager end)
  if valid(pcm) then pcall(function() pcm:StopAllCameraShakes(true) end) end
  local hud = safe(function() return host.PlayerHud end)
  if why == "death" or why == "promotion" then
    for _, d in ipairs({ 100, 700, 1500, 3000, 4500 }) do
      ExecuteWithDelay(d, function() ExecuteInGameThread(function()
        if valid(hud) then pcall(function() hud:StartFadeIn() end) end
        if why == "promotion" and valid(hud) then pcall(function() hud:OnPromotionEnded() end) end
        if valid(pc) then pcall(function() pc:SetViewTargetWithBlend(host, 0, 0, 0, false) end) end
      end) end)
    end
  end
end

function M.install_host(log)
  if M.host_hooks then return end
  local host = players()
  local path = host and safe(function() return host:GetClass():GetFullName():match("^%S+%s+(.+)$") end)
  if not path then return end
  M.host_hooks = true
  local function on(fname, why)
    local ok, err = pcall(function()
      RegisterHook(path .. ":" .. fname, function(ctx)
        local o = safe(function() return ctx:get() end)
        if not valid(o) or safe(function() return o:IsLocallyControlled() end, true) then return end
        -- guest pawn on the host
        safe(function() o.PlayerDamagePostProcess.bEnabled = false end)
        host_fix(log, why)
        M.last_evt = os.time(); M.last_why = why
        if why ~= "damage" then M.last_death = os.time() end
        if why == "promotion" then
          M.promo_done = true
          local gpc = safe(function() return o:GetController() end)
          local ch = package.loaded["channel"]
          if ch and valid(gpc) then ch.to_guest(log, gpc, "promoend|") end
        end
        M.fixes = M.fixes or {}
        M.fixes[fname] = (M.fixes[fname] or 0) + 1
        if M.fixes[fname] <= 2 then log("sync: host undid guest feedback after " .. fname) end
      end)
    end)
    log("sync: hook " .. fname .. " -> " .. (ok and "ok" or tostring(err)))
  end
  on("ReceiveDamage", "damage")
  on("ReceivePointDamage", "damage")
  on("ReceiveRadialDamage", "damage")
  on("PlayerDies", "death")
  on("OnPromotionFinished", "promotion")
  -- host HUD: hints and the promotion panel that the guest's pawn put there
  local hud = safe(function() return host.PlayerHud end)
  local hpath = valid(hud) and safe(function() return hud:GetClass():GetFullName():match("^%S+%s+(.+)$") end)
  local function host_busy() return safe(function() return host.IsDead or host.IsInPromotion end, false) end
  if hpath then
    local ok1 = pcall(function()
      RegisterHook(hpath .. ":ShowTutorialWarning", function(ctx, w)
        if not M.last_evt or os.time() - M.last_evt > 3 or host_busy() then return end
        local v = safe(function() return w:get() end)
        local h = safe(function() return ctx:get() end)
        pcall(function() h:HideTutorialWarning() end)
        local _, guest = players()
        local gpc = guest and safe(function() return guest:GetController() end)
        local ch = package.loaded["channel"]
        if ch and valid(gpc) and v ~= nil then ch.to_guest(log, gpc, "warn|" .. tostring(v)) end
        log("sync: guest hint " .. tostring(v) .. " moved from the host HUD to the guest")
      end)
    end)
    local ok2 = pcall(function()
      RegisterHook(hpath .. ":StartShowPromotion", function(ctx, cid, tier, hp, name, alien)
        if not M.last_death or os.time() - M.last_death > 20 or host_busy() then return end
        local function g(x) return safe(function() return x:get() end) end
        local n = g(name)
        local ns = n and (safe(function() return n:ToString() end) or tostring(n)) or ""
        local _, guest = players()
        local gpc = guest and safe(function() return guest:GetController() end)
        local ch = package.loaded["channel"]
        local msg = "promo|" .. tostring(g(cid)) .. "|" .. tostring(g(tier)) .. "|" .. tostring(g(hp)) .. "|" .. tostring(g(alien)) .. "|" .. ns:gsub("|", "/")
        if ch and valid(gpc) then ch.to_guest(log, gpc, msg) end
        log("sync: promotion panel sent to the guest: " .. msg)
        local h = safe(function() return ctx:get() end)
        for _, d in ipairs({ 0, 500, 1500, 3000, 5000, 8000 }) do
          ExecuteWithDelay(d + 1, function() ExecuteInGameThread(function()
            pcall(function() h.PlayerHudWriteCrewStats:SetVisibility(2) end)
          end) end)
        end
        log("sync: guest promotion panel hidden on the host")
      end)
    end)
    log("sync: hud hooks ShowTutorialWarning=" .. tostring(ok1) .. " StartShowPromotion=" .. tostring(ok2))
  end
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
  M.install_host(log)
  safe(function() guest.PlayerDamagePostProcess.bEnabled = false end)
  M.death_tick(log, host, guest, pc)
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
  local pcm = valid(pc) and safe(function() return pc.PlayerCameraManager end)
  local vt = valid(pcm) and safe(function() return pcm:GetViewTarget():GetFName():ToString() end)
  -- camera shake straight on the camera manager (no RPC)
  local a, ea = false, "no class/pcm"
  if valid(cls) and valid(pcm) then a, ea = pcall(function() return pcm:PlayCameraShake(cls, 3, 0, {Pitch=0, Yaw=0, Roll=0}) end) end
  -- red flash: drive the post-process blend weight ourselves, then fade it out
  local pp = safe(function() return p.PlayerDamagePostProcess end)
  local info = valid(pp) and ("pp enabled=" .. tostring(safe(function() return pp.bEnabled end)) .. " unbound=" .. tostring(safe(function() return pp.bUnbound end))
    .. " weight=" .. tostring(safe(function() return pp.BlendWeight end))) or "no pp component"
  local b = valid(pp) and pcall(function() pp.bEnabled = true; pp.BlendWeight = 1.0 end)
  local steps = 10
  for i = 1, steps do
    ExecuteWithDelay(60 * i, function()
      ExecuteInGameThread(function() pcall(function() pp.BlendWeight = 1.0 - i / steps end) end)
    end)
  end
  M.fx = (M.fx or 0) + 1
  if M.fx <= 3 then
    log("sync: hit effect -" .. tostring(dmg) .. " class=" .. tostring(valid(cls)) .. " pcm=" .. tostring(valid(pcm)) .. " viewtarget=" .. tostring(vt)
      .. " shake=" .. tostring(a) .. (a and "" or (" " .. tostring(ea))) .. " | " .. info .. " flash=" .. tostring(b))
  end
end

-- guest, on a message from the host
function M.on_host_message(log, body)
  for _, o in ipairs(FindAllOf("Eden_PlayerCharacter_C") or {}) do
    if valid(o) and not safe(function() return o:IsLocallyControlled() end, true) then
      safe(function() o.PlayerDamagePostProcess.bEnabled = false end)
    end
  end
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
  if body:match("^promo|") then
    local cid, tier, hp, alien, name = body:match("^promo|([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.*)$")
    local p = me(); local hud = p and safe(function() return p.PlayerHud end)
    if not valid(hud) then log("sync: promo, no hud"); return true end
    local a = { tonumber(cid) or 0, tonumber(tier) or 0, tonumber(hp) or 100 }
    local ok, err = pcall(function() hud:StartShowPromotion(a[1], a[2], a[3], FText(name or ""), tonumber(alien) or 0) end)
    if not ok then ok, err = pcall(function() hud:StartShowPromotion(a[1], a[2], a[3], name or "", tonumber(alien) or 0) end) end
    log("sync: promotion panel shown: " .. (ok and "ok" or tostring(err)))
    return true
  end
  if body == "promoend|" then
    local p = me(); local hud = p and safe(function() return p.PlayerHud end)
    local ok = valid(hud) and pcall(function() hud:OnPromotionEnded() end)
    log("sync: promotion ended " .. tostring(ok))
    return true
  end
  local wv = body:match("^warn|(.+)$")
  if wv then
    local p = me(); local hud = p and safe(function() return p.PlayerHud end)
    local ok, err = false, "no hud"
    if valid(hud) then ok, err = pcall(function() hud:ShowTutorialWarning(tonumber(wv) or wv) end) end
    log("sync: hint " .. wv .. " shown: " .. (ok and "ok" or tostring(err)))
    return true
  end
  if body == "dead|" or body == "revive|" then
    local p = me(); if not p then return true end
    local hud = safe(function() return p.PlayerHud end)
    if body == "dead|" then
      local a = valid(hud) and pcall(function() hud:StartFadeOut() end)
      log("sync: I died -> fade out " .. tostring(a))
    else
      local r = {}
      r[#r+1] = pcall(function() p.IsDead = false end)
      r[#r+1] = pcall(function() p.BlockActionFPSPlayerInput = false end)
      r[#r+1] = pcall(function() p.CharacterMovement:SetActive(true, false) end)
      r[#r+1] = pcall(function() p:GetController():SetViewTargetWithBlend(p, 0, 0, 0, false) end)
      r[#r+1] = valid(hud) and pcall(function() hud:StartFadeIn() end)
      M.guest_hp = nil
      local t = {}; for _, v in ipairs(r) do t[#t+1] = tostring(v) end
      log("sync: revived (" .. table.concat(t, ",") .. ")")
    end
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

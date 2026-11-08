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
    if M.dead_ticks == 1 and not dead then
      -- the game's death sits behind a DoOnce that our Lua write does not reopen reliably: if the guest
      -- is at 0 health but the game did not start its death, start it ourselves (PlayerDies is after the gate)
      local ok, err = pcall(function() guest:PlayerDies() end)
      log("sync: guest at " .. tostring(h) .. " health but not dead -> PlayerDies(): " .. (ok and "ok" or tostring(err)))
      local ch = package.loaded["channel"]; if ch then ch.to_guest(log, pc, "dead|") end
    elseif M.dead_ticks == 1 then
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
      log("sync: death gate reopened? IsClosed_6=" .. tostring(safe(function() return guest.Temp_bool_IsClosed_Variable_6 end, "unreadable")))
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
    if M.dead_ticks > 0 then
      local r = pcall(function() guest.Temp_bool_IsClosed_Variable_6 = false end)
      log("sync: guest alive again by itself (health=" .. tostring(h) .. "), death gate reopened=" .. tostring(r)
        .. " IsClosed_6=" .. tostring(safe(function() return guest.Temp_bool_IsClosed_Variable_6 end, "unreadable")))
    end
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
  if valid(pcm) then
    pcall(function() pcm:StopAllCameraShakes(true) end)
    -- the shake can start a few frames after the damage event: keep stopping it for 1.5 s
    for i = 1, 30 do
      GT_delay(50 * i, function() ExecuteInGameThread(function()
        pcall(function() pcm:StopAllCameraShakes(true) end)
      end) end)
    end
  end
  local hud = safe(function() return host.PlayerHud end)
  -- the guest's hit also calls GetPlayerHud().FlickerHud(): close the HUD's flicker gate again
  if valid(hud) then
    -- v43 wrote the material directly and crashed the host. Instead push the flicker timer past its
    -- 0.2 s end: the HUD's own Tick then takes its normal "flicker finished" path.
    -- v45: only for a hit, and only while the flicker is running (v44 also did it at death: host crash)
    -- v47: as in v44 (worked for hits), but never on the fatal hit or during the death sequence
    if why == "damage" then
      local _, guest = players()
      local gh = valid(guest) and safe(function() return guest.Health end)
      local dead = valid(guest) and safe(function() return guest.IsDead end, false)
      if type(gh) == "number" and gh > 0 and not dead then pcall(function() hud.HudDistorionTimer = 1.0 end) end
    end
  end
  if why == "death" or why == "promotion" then
    for _, d in ipairs({ 100, 700, 1500, 3000, 4500 }) do
      GT_delay(d, function() ExecuteInGameThread(function()
        if valid(hud) then pcall(function() hud:StartFadeIn() end) end
        if why == "promotion" and valid(hud) then pcall(function() hud:OnPromotionEnded() end) end
        if valid(pc) then pcall(function() pc:SetViewTargetWithBlend(host, 0, 0, 0, false) end) end
      end) end)
    end
  end
end

-- The game's promotion camera (BP_PromotedCaptain) ends by calling GetPlayerCharacter(0).OnPromotionFinished,
-- i.e. on the HOST's pawn. For a guest death, remove the camera before that and finish the promotion on the guest pawn.
function M.watch_promotion(log, guest)
  -- one watch per death: PlayerDies can be reported several times while the guest is dying
  if M.promo_watching then return end
  if M.promo_done_at and os.time() - M.promo_done_at < 4 then return end
  M.promo_watching, M.promo_cam_handled = true, false
  local n = 0
  GT_loop(200, function()
    n = n + 1
    if M.promo_cam_handled then M.promo_watching = false; return true end
    if n > 100 then
      if not M.promo_timeout_logged then log("sync: no promotion camera within 20 s"); M.promo_timeout_logged = true end
      M.promo_watching = false; return true
    end
    ExecuteInGameThread(function()
      if M.promo_cam_handled then return end
      local cams = FindAllOf("BP_PromotedCaptain_C") or {}
      for _, cam in ipairs(cams) do
        if valid(cam) and not M.promo_cam_handled then
          M.promo_cam_handled = true
          local crew = safe(function() return cam.CrewCharacter end)
          log("sync: promotion camera for the guest found, crew=" .. tostring(valid(crew) and crew:GetFName():ToString()))
          M.promo_done_at = os.time()
          GT_delay(1500, function() ExecuteInGameThread(function()
            pcall(function() cam:K2_DestroyActor() end)
            local ok, err = pcall(function() guest:OnPromotionFinished(false) end)
            log("sync: promotion camera removed, OnPromotionFinished on the guest pawn: " .. (ok and "ok" or tostring(err)))
            -- the game's post-promotion init may point the guest pawn at player 0's HUD and re-enable its
            -- damage post-process: undo both and repaint the host's own health
            local host = players()
            safe(function() guest.PlayerDamagePostProcess.bEnabled = false end)
            local hh = valid(host) and safe(function() return host.PlayerHud end)
            local gh = safe(function() return guest.PlayerHud end)
            if valid(gh) and valid(hh) and gh:GetFullName() == hh:GetFullName() then
              safe(function() guest.PlayerHud = nil end); log("sync: guest pawn was pointed at the host HUD after promotion -> cleared")
            end
            if valid(hh) then pcall(function() hh:UpdatePlayerHealth(host.Health, host.HealthMax) end) end
            -- the game puts the player on the crew member's exact spot (often inside a workstation):
            -- let the engine's teleport find the nearest free spot
            GT_delay(300, function() ExecuteInGameThread(function()
              local l = safe(function() return guest:K2_GetActorLocation() end)
              local r = safe(function() return guest:K2_GetActorRotation() end)
              if not l then return end
              local before = string.format("%.0f,%.0f,%.0f", l.X, l.Y, l.Z)
              local ok2, moved = pcall(function() return guest:K2_TeleportTo({X = l.X, Y = l.Y, Z = l.Z + 30}, r) end)
              local a = safe(function() return guest:K2_GetActorLocation() end)
              log("sync: free spot after promotion: " .. before .. " -> " .. (a and string.format("%.0f,%.0f,%.0f", a.X, a.Y, a.Z) or "?")
                .. " teleport=" .. tostring(ok2) .. "/" .. tostring(moved))
            end) end)
          end) end)
        end
      end
    end)
    return done
  end)
end

-- v52: host-side 20 Hz poll, no hooks: a drop in the guest's health = a guest hit -> undo its feedback on
-- the host and repaint the host's own health bar; after a guest death keep the world out of slow motion.
function M.fast_poll(log)
  if M.polling then return end
  M.polling = true
  local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
  GT_loop(50, function()
    ExecuteInGameThread(function()
      local host, guest = players()
      if not (valid(host) and valid(guest)) then return end
      local gh = safe(function() return guest.Health end)
      local last = M.poll_hp
      M.poll_hp = gh
      if type(gh) == "number" and type(last) == "number" and gh < last then
        M.last_evt = os.time(); M.last_why = "damage"
        if gh > 0 then
          host_fix(log, "damage")
        end
        safe(function() guest.PlayerDamagePostProcess.bEnabled = false end)
        local hud = safe(function() return host.PlayerHud end)
        if valid(hud) then pcall(function() hud:UpdatePlayerHealth(host.Health, host.HealthMax) end) end
        M.hits = (M.hits or 0) + 1
        if M.hits <= 3 then log("sync: guest hit seen by poll (" .. tostring(last) .. " -> " .. tostring(gh) .. "), host feedback undone") end
      end
      -- slow motion from the guest's death: the game runs "slomo 0.15" on the (shared) world
      if M.last_death and os.time() - M.last_death < 15 and not safe(function() return host.IsDead end, false) then
        local td = valid(gs) and safe(function() return gs:GetGlobalTimeDilation(host) end)
        if type(td) == "number" and math.abs(td - 1) > 0.01 then
          pcall(function() gs:SetGlobalTimeDilation(host, 1.0) end)
          M.slomo_fix = (M.slomo_fix or 0) + 1
          if M.slomo_fix <= 3 then log("sync: world time dilation " .. tostring(td) .. " after a guest death -> 1") end
        end
      end
    end)
    return false
  end)
  log("sync: host fast poll started (50 ms)")
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
        -- v50: do as little as possible inside a script hook (several host crashes came from work done
        -- inside these callbacks): identify the guest pawn by name, then do the work on the next frame
        local o = safe(function() return ctx:get() end)
        local nm = o and safe(function() return o:GetFullName() end)
        if not nm or nm ~= M.guest_full then return end
        GT_delay(1, function() ExecuteInGameThread(function() M.on_guest_event(log, o, fname, why) end) end)
      end)
    end)
    log("sync: hook " .. fname .. " -> " .. (ok and "ok" or tostring(err)))
  end
  M.on_guest_event = function(log, o, fname, why)
        if not valid(o) then return end
        safe(function() o.PlayerDamagePostProcess.bEnabled = false end)
        host_fix(log, why)
        M.last_evt = os.time(); M.last_why = why
        if why ~= "damage" then M.last_death = os.time() end
        if why == "death" then M.watch_promotion(log, o) end
        if why == "promotion" then
          M.promo_done = true
          local gpc = safe(function() return o:GetController() end)
          local ch = package.loaded["channel"]
          if ch and valid(gpc) then ch.to_guest(log, gpc, "promoend|") end
        end
        M.fixes = M.fixes or {}
        M.fixes[fname] = (M.fixes[fname] or 0) + 1
        if M.fixes[fname] <= 2 then log("sync: host undid guest feedback after " .. fname) end
  end
  -- v52: no ReceiveDamage hook (hits are frequent; script hooks crashed the host intermittently even
  -- with near-empty callbacks). Hits are detected by M.fast_poll instead.
  on("PlayerDies", "death")
  on("OnPromotionFinished", "promotion")
  -- host HUD: hints and the promotion panel that the guest's pawn put there
  local hud = safe(function() return host.PlayerHud end)
  local hpath = valid(hud) and safe(function() return hud:GetClass():GetFullName():match("^%S+%s+(.+)$") end)
  local function host_busy() return safe(function() return host.IsDead or host.IsInPromotion end, false) end
  if hpath then
    local ok1 = pcall(function()
      RegisterHook(hpath .. ":ShowTutorialWarning", function(ctx, w)
        local v = safe(function() return w:get() end)
        local h = safe(function() return ctx:get() end)
        -- 150 ms: let fast_poll register the guest hit first
        GT_delay(150, function() ExecuteInGameThread(function()
        if not M.last_evt or os.time() - M.last_evt > 3 or host_busy() then return end
        pcall(function() h:HideTutorialWarning() end)
        local _, guest = players()
        local gpc = guest and safe(function() return guest:GetController() end)
        local ch = package.loaded["channel"]
        if ch and valid(gpc) and v ~= nil then ch.to_guest(log, gpc, "warn|" .. tostring(v)) end
        log("sync: guest hint " .. tostring(v) .. " moved from the host HUD to the guest")
        end) end)
      end)
    end)
    local ok2 = pcall(function()
      RegisterHook(hpath .. ":StartShowPromotion", function(ctx, cid, tier, hp, name, alien)
        local function g(x) return safe(function() return x:get() end) end
        local n = g(name)
        local ns = n and (safe(function() return n:ToString() end) or tostring(n)) or ""
        local vc, vt, vh, va = g(cid), g(tier), g(hp), g(alien)
        local h = safe(function() return ctx:get() end)
        GT_delay(1, function() ExecuteInGameThread(function()
        if not M.last_death or os.time() - M.last_death > 20 or host_busy() then return end
        local _, guest = players()
        local gpc = guest and safe(function() return guest:GetController() end)
        local ch = package.loaded["channel"]
        local msg = "promo|" .. tostring(vc) .. "|" .. tostring(vt) .. "|" .. tostring(vh) .. "|" .. tostring(va) .. "|" .. ns:gsub("|", "/")
        if ch and valid(gpc) then ch.to_guest(log, gpc, msg) end
        log("sync: promotion panel sent to the guest: " .. msg)
        for _, d in ipairs({ 0, 500, 1500, 3000, 5000, 8000 }) do
          GT_delay(d + 1, function() ExecuteInGameThread(function()
            pcall(function() h.PlayerHudWriteCrewStats:SetVisibility(2) end)
          end) end)
        end
        log("sync: guest promotion panel hidden on the host")
        end) end)
      end)
    end)
    local ok3 = "off (v52: repaint done by fast_poll)"
    local ok4 = "off (v46 hook crashed the host)"
    log("sync: hud hooks ShowTutorialWarning=" .. tostring(ok1) .. " StartShowPromotion=" .. tostring(ok2) .. " UpdatePlayerHealth=" .. tostring(ok3) .. " FlickerHud=" .. tostring(ok4))
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
  M.guest_full = safe(function() return guest:GetFullName() end, M.guest_full)
  M.install_host(log)
  M.fast_poll(log)
  M.host_hp_seen = safe(function() return host.Health end, M.host_hp_seen)
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
  local hudg = safe(function() return p.PlayerHud end)
  if valid(hudg) then pcall(function() hudg:FlickerHud() end) end
  local steps = 10
  for i = 1, steps do
    GT_delay(60 * i, function()
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
    GT_delay(12000, function() ExecuteInGameThread(function() pcall(function() hud:OnPromotionEnded() end) end) end)
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

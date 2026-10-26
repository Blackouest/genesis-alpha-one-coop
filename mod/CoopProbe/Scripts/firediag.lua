-- v29 (guest): find where the local fire stops, and force the local shot if the game's gate blocks it.
local M = {}
local function safe(f, d) local ok, v = pcall(f); if ok then return v end; return d end
local function valid(o) return o ~= nil and safe(function() return o:IsValid() end, false) end
M.installed, M.count, M.last_force = false, {}, 0
M.shot_seen = false

local function me()
  for _, ch in ipairs(FindAllOf("Eden_PlayerCharacter_C") or {}) do
    if valid(ch) and safe(function() return ch:IsLocallyControlled() end, false) then return ch end
  end
end

local function classpath(obj)
  local cls = obj and safe(function() return obj:GetClass() end)
  return cls and safe(function() return cls:GetFullName():match("^%S+%s+(.+)$") end)
end

local function hook(log, path, fname, tag)
  local ok, err = pcall(function()
    RegisterHook(path .. ":" .. fname, function(ctx)
      local o = safe(function() return ctx:get() end)
      local mine = true
      if tag == "pawn" then mine = o and safe(function() return o:IsLocallyControlled() end, false) end
      if not mine then return end
      M.count[fname] = (M.count[fname] or 0) + 1
      if fname == "PlayerShootsWeapon" or fname == "ShootWeapon" then M.shot_seen = true end
      if M.count[fname] <= 2 then log("firediag: " .. fname .. " #" .. M.count[fname]) end
    end)
  end)
  log("firediag: hook " .. fname .. " -> " .. (ok and "ok" or tostring(err)))
end

local function snapshot(p)
  local names = { "BlockActionFPSPlayerInput", "IsMenuModeActive", "PrimaryActionIsPressed", "SecondaryActionIsPressed",
    "IsWeaponEquiped", "IsDead", "IsChangingWeapon", "IsObjectAheadOfPlayer", "IsLostInSpace", "IsAutoFireing" }
  local t = {}
  for _, n in ipairs(names) do table.insert(t, n .. "=" .. tostring(safe(function() return p[n] end))) end
  local w = safe(function() return p.CurrentWeaponInUse end)
  local wid = valid(w) and safe(function() return w.WeaponID end)
  table.insert(t, "weapon=" .. (valid(w) and w:GetFName():ToString() or "none") .. " id=" .. tostring(wid))
  if wid then
    local a = safe(function() return p.PlayerState.Ammunition[wid + 1] end)
    table.insert(t, "ammo[id]=" .. tostring(a))
    table.insert(t, "owner=" .. tostring(safe(function() return w.WeaponOwner:GetFName():ToString() end)))
  end
  return table.concat(t, " ")
end

function M.install(log)
  if M.installed then return end
  local p = me(); if not p then return end
  local pp = classpath(p)
  local w = safe(function() return p.CurrentWeaponInUse end)
  if not pp then return end
  for _, f in ipairs({ "AttemptToUpdatePrimaryAction", "PlayerHoldsWeaponTrigger", "PlayerShootsWeapon" }) do hook(log, pp, f, "pawn") end
  local wp = "/Game/EdenAlpha1/Blueprints/Weapons/BP_Weapon_CLASS.BP_Weapon_CLASS_C"
  if not valid(StaticFindObject(wp)) then wp = (pp:match("^(/Game/[^/]+/)") or "/Game/") .. "Blueprints/Weapons/BP_Weapon_CLASS.BP_Weapon_CLASS_C" end
  log("firediag: weapon base class " .. wp .. " found=" .. tostring(valid(StaticFindObject(wp))))
  for _, f in ipairs({ "ShootWeapon", "ReduceAmmo", "ShootProjectile", "WeaponShotEffects" }) do hook(log, wp, f, "weapon") end
  M.installed = true
end

-- called by actions.lua for every local Fire action on the guest
function M.on_fire(log, name)
  local p = me(); if not p then return end
  local press = name:find("_24$") ~= nil
  M.presses = (M.presses or 0) + (press and 1 or 0)
  if press and M.presses <= 2 then log("firediag: press | " .. snapshot(p)) end
  if not press then return end
  M.shot_seen = false
  ExecuteWithDelay(150, function()
    ExecuteInGameThread(function()
      if M.shot_seen then return end
      local w = safe(function() return p.CurrentWeaponInUse end)
      if not valid(w) then log("firediag: no local weapon in hand, nothing to force"); return end
      local ok, err = pcall(function() p:PlayerShootsWeapon() end)
      M.forced = (M.forced or 0) + 1
      if M.forced <= 3 or not ok then log("firediag: local shot forced #" .. M.forced .. ": " .. (ok and "ok" or tostring(err))) end
    end)
  end)
end
return M

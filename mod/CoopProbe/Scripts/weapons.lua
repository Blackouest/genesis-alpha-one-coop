-- v26 (host): give the guest's pawn its own weapons with the game's own AddEquipmentToInventory(WeaponID, Slot),
-- read from the Blueprint bytecode: it spawns the weapon, attaches it to Mesh2P at the weapon's PlayerSocket,
-- sets WeaponOwner = the pawn (the shot direction comes from WeaponOwner's control rotation) and initializes it.
-- Also detach the guest pawn from the host's HUD (PlayerHud), which single-player code would otherwise drive.
local M = {}
local function safe(f, d) local ok, v = pcall(f); if ok then return v end; return d end
local function nm(o) return safe(function() return o:GetFName():ToString() end, "?") end
local function valid(o) return o ~= nil and safe(function() return o:IsValid() end, false) end
-- EInventorySlot order used by AddEquipmentToInventory
local SLOTS = { { "NoWeapon", 0 }, { "WeaponSlot1", 1 }, { "WeaponSlot2", 2 }, { "SentryGun", 3 },
                { "EnergyBarrier", 4 }, { "SampleCollector", 5 }, { "MultiTool", 6 } }

local function pawns()
  local host, guests = nil, {}
  for _, ch in ipairs(FindAllOf("Eden_PlayerCharacter_C") or {}) do
    if valid(ch) and safe(function() return ch.Role end, 0) == 3 then
      if safe(function() return ch:IsLocallyControlled() end, false) then host = ch else table.insert(guests, ch) end
    end
  end
  return host, guests
end

local function slots(log, ch, label)
  local parts = {}
  for _, s in ipairs(SLOTS) do
    local w = safe(function() return ch[s[1]] end)
    table.insert(parts, s[1] .. "=" .. (valid(w) and (nm(w) .. "#" .. tostring(safe(function() return w.WeaponID end, "?")) .. " owner=" .. (valid(safe(function() return w.WeaponOwner end)) and nm(w.WeaponOwner) or "none")) or "none"))
  end
  log(label .. " " .. nm(ch) .. ": " .. table.concat(parts, " | "))
end

function M.give(log)
  local host, guests = pawns()
  if not host then log("weapons: no host pawn"); return end
  slots(log, host, "host")
  for _, g in ipairs(guests) do
    slots(log, g, "guest before")
    for _, s in ipairs(SLOTS) do
      local hw = safe(function() return host[s[1]] end)
      if valid(hw) and not valid(safe(function() return g[s[1]] end)) then
        local id = safe(function() return hw.WeaponID end)
        if type(id) == "number" then
          local ok, err = pcall(function() g:AddEquipmentToInventory(id, s[2]) end)
          log("AddEquipmentToInventory(" .. id .. ", " .. s[1] .. ") -> " .. (ok and "ok" or tostring(err)))
        end
      end
    end
    -- start with empty hands, like the host after a load
    if not valid(safe(function() return g.CurrentWeaponInUse end)) and valid(safe(function() return g.NoWeapon end)) then
      safe(function() g.CurrentWeaponInUse = g.NoWeapon end)
      safe(function() g.NoWeapon:SetActorHiddenInGame(false) end)
    end
    safe(function() g.PlayerHud = nil end)
    slots(log, g, "guest after")
    local ids = {}
    for _, s in ipairs(SLOTS) do
      local w = safe(function() return g[s[1]] end)
      local id = valid(w) and safe(function() return w.WeaponID end) or nil
      if type(id) == "number" then table.insert(ids, s[2] .. ":" .. id) end
    end
    local ch = package.loaded["channel"]
    local pc = safe(function() return g:GetController() end)
    if ch and valid(pc) then ch.to_guest(log, pc, "weap|" .. table.concat(ids, ",")) end
  end
end

function M.give_local(log, list)
  local me
  for _, ch in ipairs(FindAllOf("Eden_PlayerCharacter_C") or {}) do
    if valid(ch) and safe(function() return ch:IsLocallyControlled() end, false) then me = ch end
  end
  if not me then log("weap: no local pawn"); return end
  for pair in list:gmatch("[^,]+") do
    local slot, id = pair:match("^(%d+):(%-?%d+)$")
    slot, id = tonumber(slot), tonumber(id)
    if slot and id then
      local name = nil
      for _, s in ipairs(SLOTS) do if s[2] == slot then name = s[1] end end
      if name and not valid(safe(function() return me[name] end)) then
        local ok, err = pcall(function() me:AddEquipmentToInventory(id, slot) end)
        log("local AddEquipmentToInventory(" .. id .. ", " .. name .. ") -> " .. (ok and "ok" or tostring(err)))
      end
    end
  end
  if not valid(safe(function() return me.CurrentWeaponInUse end)) and valid(safe(function() return me.NoWeapon end)) then
    safe(function() me.CurrentWeaponInUse = me.NoWeapon end)
  end
  slots(log, me, "guest local")
end
return M

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
    safe(function() p.Health = h end)
    if mx then safe(function() p.HealthMax = mx end) end
    local hud = safe(function() return p.PlayerHud end)
    local ok = valid(hud) and pcall(function() hud:UpdatePlayerHealth(h, mx or 100) end)
    log("sync: health " .. tostring(h) .. "/" .. tostring(mx) .. " hud=" .. tostring(ok))
    return true
  end
  return false
end
return M

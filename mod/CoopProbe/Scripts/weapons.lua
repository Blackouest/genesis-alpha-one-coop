-- v23 (host): give the guest's pawn its own weapons, and detach it from the host's HUD.
local M = {}
local function safe(f, d) local ok, v = pcall(f); if ok then return v end; return d end
local function nm(o) return safe(function() return o:GetFName():ToString() end, "?") end
local function valid(o) return o ~= nil and safe(function() return o:IsValid() end, false) end
local SLOTS = { "WeaponSlot1", "WeaponSlot2", "NoWeapon", "Multitool" }

local function pawns()
  local host, guests = nil, {}
  for _, ch in ipairs(FindAllOf("Eden_PlayerCharacter_C") or {}) do
    if valid(ch) and safe(function() return ch.Role end, 0) == 3 then
      if safe(function() return ch:IsLocallyControlled() end, false) then host = ch else table.insert(guests, ch) end
    end
  end
  return host, guests
end

local function attach_info(w)
  local root = safe(function() return w.RootComponent end)
  local parent = root and safe(function() return root:GetAttachParent() end)
  local sock = root and safe(function() return root:GetAttachSocketName():ToString() end, "?")
  local pact = safe(function() return w:GetAttachParentActor() end)
  local hidden = safe(function() return w.bHidden end, "?")
  return parent, sock, string.format("parentActor=%s parentComp=%s socket=%s hidden=%s owner=%s",
    valid(pact) and nm(pact) or "none", valid(parent) and nm(parent) or "none", tostring(sock), tostring(hidden),
    valid(safe(function() return w:GetOwner() end)) and nm(w:GetOwner()) or "none")
end

local function slots(log, ch, label)
  local parts = {}
  for _, s in ipairs(SLOTS) do
    local w = safe(function() return ch[s] end)
    table.insert(parts, s .. "=" .. (valid(w) and nm(w) or "none"))
  end
  local cur = safe(function() return ch.CurrentWeaponInUse end)
  table.insert(parts, "Current=" .. (valid(cur) and nm(cur) or "none"))
  local hud = safe(function() return ch.PlayerHud end)
  table.insert(parts, "PlayerHud=" .. (valid(hud) and nm(hud) or "none"))
  log(label .. " " .. nm(ch) .. ": " .. table.concat(parts, " "))
end

local function errtext(e)
  if type(e) == "function" then
    local info = (debug and debug.getinfo) and debug.getinfo(e, "S") or nil
    local where = info and (tostring(info.what) .. " " .. tostring(info.short_src) .. ":" .. tostring(info.linedefined)) or "no debug info"
    return "error value is a function (" .. where .. ")"
  end
  return tostring(e)
end

local function params(log, cls, fname)
  log("params: looking for " .. tostring(fname) .. " in " .. nm(cls))
  local found = false
  safe(function()
    cls:ForEachFunction(function(fn)
      if fn:GetFName():ToString() == fname then
        found = true
        local ps = {}
        fn:ForEachProperty(function(p)
          table.insert(ps, p:GetFName():ToString() .. ":" .. safe(function() return p:GetClass():GetFName():ToString() end, "?"))
        end)
        log("params " .. nm(cls) .. ":" .. fname .. " (" .. table.concat(ps, ", ") .. ")")
      end
    end)
  end)
  if not found then log("params " .. nm(cls) .. ":" .. fname .. " not found") end
end

-- summon fallback: the CheatManager's summon spawns next to the host's pawn; adopt the newest actor of that class
local function summon(log, host_pc, cls)
  local before = {}
  for _, a in ipairs(FindAllOf(nm(cls)) or {}) do before[nm(a)] = true end
  local ksl = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
  local ok = pcall(function() ksl:ExecuteConsoleCommand(host_pc, "summon " .. nm(cls), host_pc) end)
  for _, a in ipairs(FindAllOf(nm(cls)) or {}) do
    if valid(a) and not before[nm(a)] then return a end
  end
  log("summon " .. nm(cls) .. " exec=" .. tostring(ok) .. " -> no new actor")
end

function M.give(log)
  local host, guests = pawns()
  if not host then log("weapons: no host pawn"); return end
  slots(log, host, "host")
  for _, s in ipairs(SLOTS) do
    local w = safe(function() return host[s] end)
    if valid(w) then local _, _, info = attach_info(w); log("  host " .. s .. " " .. nm(w) .. " class=" .. nm(w:GetClass()) .. " " .. info) end
  end
  for _, g in ipairs(guests) do
    slots(log, g, "guest before")
    -- 1) the game's own init, with the real error text this time
    local ok, err = xpcall(function() g:InitWeaponsFromSave() end, function(e) local tb = (debug and debug.traceback) and debug.traceback() or ""; return tostring(e) .. " | " .. tb end)
    log("InitWeaponsFromSave -> " .. (ok and "ok" or ("ERROR " .. errtext(err))))
    -- control calls in the same context
    log("control K2_GetActorLocation -> " .. tostring(pcall(function() return g:K2_GetActorLocation() end)))
    log("control IsLocallyControlled -> " .. tostring(pcall(function() return g:IsLocallyControlled() end)))
    local fnref = safe(function() return g.InitWeaponsFromSave end)
    log("InitWeaponsFromSave lookup type=" .. type(fnref))
    params(log, g:GetClass(), "InitWeaponsFromSave")
    params(log, StaticFindObject("/Script/Engine.GameplayStatics"), "BeginDeferredActorSpawnFromClass")
    params(log, StaticFindObject("/Script/Engine.GameplayStatics"), "FinishSpawningActor")
    slots(log, g, "guest after init")
    -- 2) if still empty, spawn copies of the host's weapon classes for the guest
    local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
    local loc = safe(function() return g:K2_GetActorLocation() end) or { X = 0, Y = 0, Z = 0 }
    local xf = { Rotation = { X = 0, Y = 0, Z = 0, W = 1 }, Translation = { X = loc.X, Y = loc.Y, Z = loc.Z }, Scale3D = { X = 1, Y = 1, Z = 1 } }
    for _, s in ipairs(SLOTS) do
      if not valid(safe(function() return g[s] end)) then
        local hw = safe(function() return host[s] end)
        if valid(hw) then
          local cls = hw:GetClass()
          local a = nil
          local ok2, e2 = pcall(function()
            a = gs:BeginDeferredActorSpawnFromClass(g, cls, xf, 1, g)
            if valid(a) then a = gs:FinishSpawningActor(a, xf) end
          end)
          if not valid(a) then
            log("deferred spawn " .. s .. " failed: " .. errtext(e2) .. "; trying summon")
            a = summon(log, host:GetController() or FindFirstOf("PlayerController"), cls)
          end
          if valid(a) then
            safe(function() a:SetOwner(g) end)
            safe(function() a.Instigator = g end)
            -- attach like the host's weapon: same component name on the guest pawn, same socket
            local parent, sock = attach_info(hw)
            local comp = valid(parent) and safe(function() return g[nm(parent)] end)
            local okA = false
            if valid(comp) then
              okA = pcall(function() a:K2_AttachToComponent(comp, FName(sock or "None"), 2, 2, 2, true) end)
            end
            safe(function() g[s] = a end)
            local _, _, info = attach_info(a)
            log("spawned " .. s .. " " .. nm(a) .. " attach=" .. tostring(okA) .. " " .. info)
          else
            log("spawn " .. s .. " failed: " .. tostring(e2))
          end
        end
      end
    end
    if not valid(safe(function() return g.CurrentWeaponInUse end)) then
      safe(function() g.CurrentWeaponInUse = g.NoWeapon end)
    end
    -- 3) on the host the guest must not drive the host's HUD
    safe(function() g.PlayerHud = nil end)
    slots(log, g, "guest final")
  end
end
return M

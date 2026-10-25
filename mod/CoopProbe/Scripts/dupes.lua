-- Experiment (host): the guest's arrival spawns a second set of per-player helper actors.
-- Each F1 press destroys the next duplicate, oldest instance kept, so we can see which one blacks out the host.
local M = {}
local function safe(f, d) local ok, v = pcall(f); if ok then return v end; return d end
local function nm(o) return safe(function() return o:GetFName():ToString() end, "?") end
local ORDER = { "BP_PlayerRemoteCamera_C", "BuilderCharacter_C", "BP_PlayerInventoryAvatar_C", "CameraActor" }
M.step = 0

local function owner_info(a)
  local own = safe(function() return a:GetOwner() end)
  local inst = safe(function() return a.Instigator end)
  return "owner=" .. ((own and safe(function() return own:IsValid() end, false)) and nm(own) or "none")
      .. " instigator=" .. ((inst and safe(function() return inst:IsValid() end, false)) and nm(inst) or "none")
end

function M.list(log)
  for _, c in ipairs(ORDER) do
    for _, a in ipairs(FindAllOf(c) or {}) do
      if a:IsValid() then
        local l = safe(function() return a:K2_GetActorLocation() end)
        log(string.format("DUPE %s %s %s loc=%s", c, nm(a), owner_info(a), l and string.format("%.0f,%.0f,%.0f", l.X, l.Y, l.Z) or "?"))
      end
    end
  end
end

function M.next(log)
  M.list(log)
  M.step = M.step + 1
  local c = ORDER[M.step]
  if not c then log("dupes: nothing left to try"); return end
  local all = {}
  for _, a in ipairs(FindAllOf(c) or {}) do if a:IsValid() then table.insert(all, a) end end
  if #all < 2 then log("dupes step " .. M.step .. ": only " .. #all .. " " .. c .. ", nothing to remove"); return end
  -- Object index suffixes count down as objects are created, so the newest has the smallest number.
  table.sort(all, function(x, y) return (tonumber(nm(x):match("(%d+)$")) or 0) < (tonumber(nm(y):match("(%d+)$")) or 0) end)
  local victim = all[1]
  local n = nm(victim)
  local ok, err = pcall(function() victim:K2_DestroyActor() end)
  log("dupes step " .. M.step .. ": destroyed newest " .. c .. " " .. n .. " -> " .. (ok and "ok" or tostring(err)) .. ". LOOK AT THE HOST SCREEN NOW")
end
return M

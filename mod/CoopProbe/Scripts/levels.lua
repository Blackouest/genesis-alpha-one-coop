-- Experiment: copy the host's dynamic streaming levels (ship modules) to the client.
-- Same-PC only: goes through Mods/CoopProbe/levels.txt. A real mod will send this over the network.
local M = {}
local FILE = "Mods/CoopProbe/levels.txt"
local function safe(f, d) local ok, v = pcall(f); if ok then return v end; return d end

local function quat_to_rot(q)  -- same math as FQuat::Rotator
  local X, Y, Z, W = q.X, q.Y, q.Z, q.W
  local sp = Z * X - W * Y
  local yawY, yawX = 2 * (W * Z + X * Y), 1 - 2 * (Y * Y + Z * Z)
  local R2D = 180 / math.pi
  local pitch, yaw, roll
  yaw = math.atan(yawY, yawX) * R2D
  if sp < -0.4999995 then pitch = -90; roll = -yaw - 2 * math.atan(X, W) * R2D
  elseif sp > 0.4999995 then pitch = 90; roll = yaw - 2 * math.atan(X, W) * R2D
  else pitch = math.asin(2 * sp) * R2D
       roll = math.atan(-2 * (W * X + Y * Z), 1 - 2 * (X * X + Y * Y)) * R2D end
  return pitch, yaw, roll
end

local function world_of_local_pc()
  for _, pc in ipairs(FindAllOf("PlayerController") or {}) do
    if pc:IsValid() and safe(function() return pc:IsLocalController() end, false) then return pc, pc:GetWorld() end
  end
end

function M.export(log, nowrite)
  local pc, world = world_of_local_pc()
  if not world then log("export: no world"); return end
  local out, n = {}, 0
  world.StreamingLevels:ForEach(function(i, e)
    local sl = e:get()
    local pkg = safe(function() return sl.PackageNameToLoad:ToString() end, "")
    local asset = safe(function() return sl.WorldAsset:ToString() end, "")
    local lvl = safe(function() return sl:GetLoadedLevel() end)
    local lvlpkg = safe(function() return lvl:GetOuter():GetOuter():GetFName():ToString() end, "?")
    local inst = lvlpkg:match("([^/]+)$") or ""
    local t = sl.LevelTransform
    local loc, rot = t.Translation, t.Rotation
    local p, y, r = quat_to_rot(rot)
    local name = (pkg ~= "" and pkg ~= "None") and pkg or asset
    log(string.format("  [%d] pkg=%s asset=%s loadedPkg=%s loc=%.1f,%.1f,%.1f rot=%.1f,%.1f,%.1f",
      i, pkg, asset, lvlpkg, loc.X, loc.Y, loc.Z, p, y, r))
    table.insert(out, string.format("%s|%f|%f|%f|%f|%f|%f|%s", name, loc.X, loc.Y, loc.Z, p, y, r, inst))
    n = n + 1
  end)
  if nowrite then log("levels listed: " .. n); return end
  local f = io.open(FILE, "w"); f:write(table.concat(out, "\n")); f:close()
  log("export: wrote " .. n .. " levels to " .. FILE)
end

local function lli_params()
  local fn = StaticFindObject("/Script/Engine.LevelStreamingDynamic:LoadLevelInstance")
  local names = {}
  if fn and fn:IsValid() then
    fn:ForEachProperty(function(prop) table.insert(names, prop:GetFName():ToString()) end)
  end
  return names
end

function M.import(log)
  local pc, world = world_of_local_pc()
  if not world then log("import: no world"); return end
  local params = lli_params()
  log("LoadLevelInstance params: " .. table.concat(params, ", "))
  local has_override = false
  for _, n in ipairs(params) do if n == "OptionalLevelNameOverride" then has_override = true end end
  if not has_override then
    log("import: this engine build has no OptionalLevelNameOverride; NOT loading (it would get us kicked). Need plan B.")
    return
  end
  local f = io.open(FILE, "r"); if not f then log("import: no " .. FILE .. " (press F5 on host first)"); return end
  local cdo = StaticFindObject("/Script/Engine.Default__LevelStreamingDynamic")
  local n, okn = 0, 0
  for line in f:lines() do
    local name, x, y, z, p, yw, r, inst = line:match("^([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]*)$")
    if name then
      n = n + 1
      local ok, res = pcall(function()
        return cdo:LoadLevelInstance(pc, name,
          { X = tonumber(x), Y = tonumber(y), Z = tonumber(z) },
          { Pitch = tonumber(p), Yaw = tonumber(yw), Roll = tonumber(r) }, {}, inst)
      end)
      local good = ok and res and safe(function() return res:IsValid() end, false)
      if good then okn = okn + 1 end
      log(string.format("  load %s as %s -> %s", name, inst, ok and (good and "ok" or "nil") or ("error: " .. tostring(res))))
    end
  end
  f:close()
  log(string.format("import: %d/%d level instances requested; listing in 4 s", okn, n))
  LoopAsync(4000, function() ExecuteInGameThread(function() M.export(log, true) end); return true end)
end
return M

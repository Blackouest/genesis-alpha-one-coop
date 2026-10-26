-- CoopProbe: read-only checks for co-op feasibility (Genesis Alpha One, UE 4.23)
local ROLE = nil  -- "host" or "client", fixed on first F9/F8 in this instance
local LOGFILE = "Mods/CoopProbe/probe_" .. os.date("%H%M%S") .. ".log"  -- one file per game instance
local function log(s)
  local line = "[CoopProbe] " .. tostring(s)
  print(line .. "\n")
  local f = io.open(LOGFILE, "a"); if f then f:write(os.date("%H:%M:%S "), line, "\n"); f:close() end
end

local function probe()
  local classes = {
    "/Script/OnlineSubsystemUtils.IpNetDriver",
    "/Script/OnlineSubsystemUtils.IpConnection",
    "/Script/Engine.NetDriver",
    "/Script/Engine.DemoNetDriver",
    "/Script/OnlineSubsystemUtils.OnlineBeaconHost",
    "/Script/OnlineSubsystemSteam.SteamNetDriver",
    "/Script/OnlineSubsystemSteam.SteamNetConnection",
  }
  for _, path in ipairs(classes) do
    local c = StaticFindObject(path)
    log(path .. " -> " .. ((c and c:IsValid()) and "FOUND" or "missing"))
  end
  local engine = FindFirstOf("GameEngine")
  if engine and engine:IsValid() then
    local ok, defs = pcall(function() return engine.NetDriverDefinitions end)
    if ok and defs then
      log("NetDriverDefinitions count: " .. defs:GetArrayNum())
      defs:ForEach(function(i, e)
        local d = e:get()
        log(string.format("  def %d: %s -> %s", i, d.DefName:ToString(), d.DriverClassName:ToString()))
      end)
    else
      log("NetDriverDefinitions not readable")
    end
  end
  local pc = FindFirstOf("PlayerController")
  if pc and pc:IsValid() then
    local world = pc:GetWorld()
    log("Role lock: " .. tostring(ROLE)); log("World: " .. world:GetFullName())
    local ok, nd = pcall(function() return world.NetDriver end)
    log("World.NetDriver: " .. ((ok and nd and nd:IsValid()) and nd:GetFullName() or "none"))
    if ok and nd and nd:IsValid() then
      local sc = nd.ServerConnection
      log("  role: " .. ((sc and sc:IsValid()) and "CLIENT (connected to a server)" or "SERVER/listen"))
      local okc, n = pcall(function() return nd.ClientConnections:GetArrayNum() end)
      log("  client connections: " .. (okc and tostring(n) or "?"))
    end
    local pcs = FindAllOf("PlayerController") or {}
    log("PlayerControllers in world: " .. #pcs)
    local pawns = FindAllOf("Eden_PlayerCharacter_C") or {}
    log("Player characters in world: " .. #pawns)
    local gm = FindFirstOf("GameModeBase")
    log("GameMode: " .. ((gm and gm:IsValid()) and gm:GetFullName() or "none"))
    local pawn = pc.Pawn
    log("Pawn: " .. ((pawn and pawn:IsValid()) and pawn:GetFullName() or "none"))
  else
    log("No PlayerController yet (press F7 again in-game)")
  end
end

RegisterKeyBind(Key.F7, function() ExecuteInGameThread(probe) end)
local function console(cmd)
  local ksl = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
  local pc = FindFirstOf("PlayerController")
  if not (ksl and ksl:IsValid() and pc and pc:IsValid()) then log("console: missing KSL or PC"); return end
  log("exec: " .. cmd)
  ksl:ExecuteConsoleCommand(pc, cmd, pc)
end

-- In-memory only: point GameNetDriver at IpNetDriver (SteamNetDriver is not shipped in the Epic build)
local function use_ip_driver()
  local engine = FindFirstOf("GameEngine")
  if not (engine and engine:IsValid()) then log("no GameEngine"); return end
  local defs = engine.NetDriverDefinitions
  defs:ForEach(function(i, e)
    local d = e:get()
    if d.DefName:ToString() == "GameNetDriver" then
      d.DriverClassName = FName("/Script/OnlineSubsystemUtils.IpNetDriver")
      d.DriverClassNameFallback = FName("/Script/OnlineSubsystemUtils.IpNetDriver")
      log("GameNetDriver now -> " .. d.DriverClassName:ToString())
    end
  end)
end

-- F9: switch to IpNetDriver, then reopen the current map as a listen server
RegisterKeyBind(Key.F9, function()
  if ROLE == "client" then log("F9 ignored: this window is the client"); return end
  ROLE = "host"
  _G.COOP_ROLE = "host"
  if not AUTO_STARTED and package.loaded["auto"] then AUTO_STARTED = true; package.loaded["auto"].start_host(log, package.loaded["levels"]) end
  if package.loaded["hooks"] then package.loaded["hooks"].armed = true end
  ExecuteInGameThread(function()
    local pc = FindFirstOf("PlayerController")
    if not (pc and pc:IsValid()) then log("no PC"); return end
    local path = pc:GetWorld():GetFullName():match("(/Game/[^%.%s]+)")
    use_ip_driver()
    log("Reopening as listen server: " .. tostring(path))
    if path then console("open " .. path .. "?listen") end
  end)
end)
-- F8: join a host. Address in Mods/CoopProbe/host.txt (default 127.0.0.1)
RegisterKeyBind(Key.F8, function()
  if ROLE == "host" then log("F8 ignored: this window is the host"); return end
  ROLE = "client"
  _G.COOP_ROLE = "client"
  if not AUTO_STARTED and package.loaded["auto"] then AUTO_STARTED = true; package.loaded["auto"].start_client(log, package.loaded["levels"], package.loaded["reveal"]) end
  if package.loaded["hooks"] then package.loaded["hooks"].armed = true end
  ExecuteInGameThread(function()
    local addr = "127.0.0.1"
    local f = io.open("Mods/CoopProbe/host.txt", "r")
    if f then local l = f:read("*l"); f:close(); if l and #l > 0 then addr = l:gsub("%s+", "") end end
    use_ip_driver()
    console("open " .. addr)
  end)
end)
local deep = require("deep")
RegisterKeyBind(Key.F7, function() ExecuteInGameThread(function() deep.dump(log) end) end)
-- (old F6 camera recover removed in v20)
local levels = require("levels")
RegisterKeyBind(Key.F5, function()
  if ROLE ~= "host" then return end
  ExecuteInGameThread(function() levels.export(log) end)
end)
RegisterKeyBind(Key.F4, function()
  if ROLE ~= "client" then return end
  ExecuteInGameThread(function() levels.import(log) end)
end)
local hooks = require("hooks")
hooks.install(log)
hooks.install_watchers(log)
local reveal = require("reveal")
RegisterKeyBind(Key.F3, function()
  if ROLE ~= "client" then return end
  ExecuteInGameThread(function() reveal.run(log) end)
end)
local render = require("render")
local initfix = require("initfix")
RegisterKeyBind(Key.F2, function() ExecuteInGameThread(function() initfix.press(log) end) end)
local dupes = require("dupes")
local shot = require("shot")
local overlay = require("overlay")
RegisterKeyBind(Key.F1, function()
  ExecuteInGameThread(function() overlay.press(log) end)
end)
local auto = require("auto")
local channel = require("channel")
channel.install(log)
local actions = require("actions")
RegisterKeyBind(Key.F6, function()
  ExecuteInGameThread(function()
    actions.install(log)
    if ROLE == "client" then channel.to_host(log, "ping " .. os.date("%H:%M:%S")) end
  end)
end)
local weapons = require("weapons")
log("loaded v23: F2 x2 on the host gives the guest its own weapons and detaches it from the host HUD")
log("loaded v22: F2 = player + gear dump; F2 again on the host = InitWeaponsFromSave for the guest")
log("loaded v21: guest actions forwarded to the host (act|<InpActEvt>), action hooks auto-installed")
log("loaded v20: auto init, F6 = hook input actions + guest pings host")
log("loaded v19: F2 = player init dump, F2 again = initialize uninitialized player characters")
log("loaded v18: F2 = guest input/movement dump, F2 again = input fixes")
log("loaded v17b: automatic flow (fade watch fixed for several HUD copies). Host: F9 only. Guest: F8 only.")
log("loaded v16: F1 = list dark HUD overlays, F1 again = hide them")
log("loaded v15b: F1 = engine screenshots, host now, client +4 s")
log("loaded v14: F1 (host) destroys the next duplicate per-player helper actor")
log("loaded v13: safe watchers (BeginPlay, new widgets, console exec) armed on F9/F8; v12 native hooks removed (crash)")
log("loaded v9: F2 = render dump (MPC, camera, post-process)")
log("loaded v8: F3 (client) = force ship levels visible + hide loading screen")
log("loaded v7b: names logged, RPC hooks")
log("loaded v6: F5 (host) exports ship levels, F4 (client) loads them")
log("loaded v5 (deep dump on F7, F6 = recover camera)")
log("loaded v4 (role lock). F7 = probe, F8 = join, F9 = host. Keys reach every game window; first F9 makes a window host, first F8 makes it client.")

-- v20: log which input-action Blueprint events fire, to find what the guest's actions call.
-- Script hooks on Blueprint functions named InpActEvt_* of the player character, controller and builder.
local M = {}
local function safe(f, d) local ok, v = pcall(f); if ok then return v end; return d end
local CLASSES = {
  "/Game/Blueprints/Player/Eden_PlayerCharacter.Eden_PlayerCharacter_C",
}
M.installed = false

function M.install(log)
  if M.installed then return end
  local n, total = 0, 0
  for _, short in ipairs({ "Eden_PlayerCharacter_C", "BP_PlayerController_EdenAlpha_C", "BuilderCharacter_C" }) do
    local obj = FindFirstOf(short)
    local cls = obj and safe(function() return obj:GetClass() end)
    if cls then
      local path = safe(function() return cls:GetFullName():match("^%S+%s+(.+)$") end)
      safe(function()
        cls:ForEachFunction(function(fn)
          local name = fn:GetFName():ToString()
          total = total + 1
          if name:find("^InpActEvt_") and path then
            local full = path .. ":" .. name
            local ok = pcall(function()
              RegisterHook(full, function(self) log("ACTION " .. short .. "." .. name) end)
            end)
            if ok then n = n + 1 end
          end
        end)
      end)
      log("actions: " .. short .. " (" .. tostring(path) .. ")")
    else
      log("actions: no " .. short .. " yet")
    end
  end
  log("actions: hooked " .. n .. " input action events (of " .. total .. " functions)")
  M.installed = n > 0
end
return M

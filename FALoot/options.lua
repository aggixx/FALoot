local A = FALoot;
local PD = A.pData;

--[[ ==========================================================================
     Persistent Data
     ========================================================================== --]]

local eventFrame, events = CreateFrame("Frame"), {}

function events:ADDON_LOADED(name)
  if name == A.NAME then
    local s = FALoot_pData or {};
    
    -- Saved Variables
    PD.debugOn = s.debugOn or 0;    -- Debug threshold
    PD.expTime = s.expTime or 15;   -- Amount of time before an ended item is removed from the window, in seconds.
    PD.autolootToggle = s.autolootToggle or GetCVar("autoLootDefault");
    PD.autolootKey = s.autolootKey or GetModifiedClick("AUTOLOOTTOGGLE");
    
    -- Hard-coded options
    PD.maxIcons = s.maxIcons or 11;
    PD.postRequestMaxWait = s.postRequestMaxWait or 3; -- Amount of time to wait for a response from the raid leader before posting a request anyway, in seconds.
    PD.itemHistorySyncMinInterval = s.itemHistorySyncMinInterval or 60 * 5; -- Minimum amount of time between item history sync attempts, in seconds.
    PD.cacheInterval = s.cacheInterval or 200;  -- Amount of time between attempts to check for item data, in milliseconds.
    PD.foodItemId = s.foodItemId or 101618;
  end
end

function events:PLAYER_LOGOUT(...)
  --[[ Probably not necessary but just to make sure its value didn't get changed by
       accident. --]]
  FALoot_pData = PD;
end

eventFrame:SetScript("OnEvent", function(self, event, ...)
  events[event](self, ...) -- call one of the functions above
end)
for k, v in pairs(events) do
  eventFrame:RegisterEvent(k) -- Register all events for which handlers have been defined
end
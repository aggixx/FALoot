local A = FALoot;
local PD = A.pData;

--[[ =======================================================
     Option Variables
     ======================================================= --]]

-- Saved Variables
PD.debugOn = 5;    -- Debug threshold
PD.expTime = 15;   -- Amount of time before an ended item is removed from the window, in seconds.
PD.autolootToggle = nil;
PD.autolootKey = nil;

-- Hard-coded options
PD.maxIcons = 11;
PD.postRequestMaxWait = 3; -- Amount of time to wait for a response from the raid leader before posting a request anyway, in seconds.
PD.itemHistorySyncMinInterval = 60 * 5; -- Minimum amount of time between item history sync attempts, in seconds.
PD.cacheInterval = 200;  -- Amount of time between attempts to check for item data, in milliseconds.
PD.foodItemId = 101618;
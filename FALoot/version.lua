--[[
  In this file:
  Version Check slash cmd
  Update reminders
--]]

local A = FALoot;
local U = A.util;
local C = A.commands;
local AM = A.addonMessages;
local F = A.functions;

-- Helper function
local function versionCompare(aM, aR, bM, bR)
  -- Returns 1 if a < b, 0 if a = b, -1 if a > b
  if aM > bM then
    return -1;
  elseif bM > aM then
    return 1;
  else
    if aR > bR then
      return -1;
    elseif bR > aR then
      return 1;
    else
      return 0;
    end
  end
end

-- Version Check
do
  local ticker;
  local responseCount = 0;
  local responses = {};

  C.Register("vc", function()
    -- Send trigger message to raid group
    F.sendMessage("GUILD", nil, false, "vcGo");
    
    ticker = C_Timer.NewTicker(1, function()
      if responseCount == 0 then
        local s = "Your guild members are using the following version(s):";
        for i=#responses,1,-1 do
	  for j=#responses[i],1,-1 do
	    if #responses[i][j] > 0 then
	      s = s .. "\n";
	      s = s .. "v" .. i .. "r" .. j .. ": ";
	      for k=1,#responses[i][j] do
	        if k > 1 then
	          s = s .. ", ";
	        end
	        s = s .. responses[i][j][k];
	      end
	    end
	  end
	end
	
        U.debug(s);
      
	ticker:Cancel();
	ticker = nil;
	responses = {};
      end
      responseCount = 0;
    end);
  end, "-- view the versions of FALoot in use by other guild members.");
  
  AM.Register("vcGo", function(channel, sender)
    F.sendMessage("WHISPER", sender, false, "vcResponse", A.MVERSION, A.REVISION);
  end);
  
  AM.Register("vcResponse", function(channel, sender, m, r)
    if not ticker then
      return;
    end
    
    for i=0,m do
      responses[i] = responses[i] or {};
    end
    for i=0,r do
      responses[m][i] = responses[m][i] or {};
    end
    
    sender = string.match(sender, "^[^-]+");
    table.insert(responses[m][r], sender);
    
    responseCount = responseCount + 1;
  end);
end

-- Update Reminder
do
  local newestMajor = A.MVERSION;
  local newestRev = A.REVISION;
  local lastMsg = GetTime();
  local reminding;
  
  local function getRemindInterval()
    local h, m = GetGameTime();
    if h*60+m >= 1050 and h*60+m <= 1105 then -- 5:30pm to 6:25pm
      local weekday = CalendarGetDate();
      if weekday >= 3 and weekday <= 5 then -- Tuesday through Thursday
        return 5 * 60;
      end
    end
    return 30 * 60;
  end
  
  local function remind()
    U.debug("Your version of FA Loot is out of date, please update at " .. A.DOWNLOAD_URL);

    C_Timer.After(getRemindInterval(), remind);
  end
  
  AM.Register("newestVersion", function(channel, sender, major, rev)
    local state = versionCompare(newestMajor, newestRev, major, rev);
    U.debug("Compare state is "..state, 3);
    if state > 0 then
      newestMajor = major;
      newestRev = rev;
      if not reminding then
        reminding = true;
        remind();
      end
    elseif state < 0 then
      F.sendMessage("GUILD", nil, false, "newestVersion", newestMajor, newestRev);
    end
    
    lastMsg = GetTime();
  end);
  
  local updateTicker = C_Timer.NewTicker(300, function()
    if GetTime() - lastMsg > 299 then
      F.sendMessage("GUILD", nil, false, "newestVersion", newestMajor, newestRev);
    end
  end);
end




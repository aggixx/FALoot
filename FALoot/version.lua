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
        local s = "Your guild members are using the following version:";
        for i,v in pairs(responses) do
	  s = s .. "\n";
	  s = s .. i .. ": ";
	  for j=1,#v do
	    if j > 1 then
	      s = s .. ", ";
	    end
	    s = s .. v[j];
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
  
  AM.Register("vcResponse", function(channel, sender, major, rev)
    if not ticker then
      return;
    end
    
    local v = "v" .. major .. "r" .. rev;
    responses[v] = responses[v] or {};
    sender = string.match(sender, "^[^-]+");
    table.insert(responses[v], sender);
    responseCount = responseCount + 1;
  end);
end
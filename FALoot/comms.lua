local A = FALoot;
local F = A.functions;
local SD = A.sData;
local PD = A.pData;
local U = A.util;
local E = A.events;
local AM = A.addonMessages;
local CM = A.chatMessages;

-- Load libraries
local libSerialize = LibStub:GetLibrary("AceSerializer-3.0");
local libCompress = LibStub:GetLibrary("LibCompress");
local libEncode = libCompress:GetAddonEncodeTable();

local messagePriority = {
  ["newestVersion"] = "BULK",
};

local selfBlacklist = {
  ["loot"] = true,
  ["end"] = true,
  ["newestVersion"] = true,
};

--[[ ==========================================================================
     Communication Functions
     ========================================================================== --]]
     
F.sendMessage = function(dist, target, reqSameVersion, mType, ...)
  -- Determine priority
  local priority = messagePriority[mType] or "NORMAL";
  
  -- Prep data in table form
  local data = {...};
  
  -- Assign message type
  data["type"] = mType;
  
  -- Specify version, if necessary
  if reqSameVersion then
    data["version"] = A.MVERSION;
  end
  
  -- Serialize the data
  local serialized, msg = libSerialize:Serialize(data);
  if serialized then
    data = serialized;
  else
    error("Serialization of data failed!");
  end
  
  -- Encode the data
  local encoded, msg = libEncode:Encode(data);
  if encoded then
    data = encoded;
  else
    error("Encoding of data failed!");
  end
  
  -- Validate whisper target to prevent errors for the user.
  if string.upper(dist) == "WHISPER" then
    local groupType = (IsInRaid() and "raid") or "party";
    for i=1,GetNumGroupMembers() do
      if U.UnitName(groupType..i, true) == target then
        if not UnitIsConnected(groupType..i) then
          U.debug("The target of message type "..(mType or "unknown")..' "'..target..'" is offline.', 2);
          return false, "target of message is offline";
        end
        break;
      end
    end
  end
  
  -- Send the prepared message
  A.stub:SendCommMessage(A.MSG_PREFIX, data, dist, target, priority)
  return true;
end

--[[ ==========================================================================
     FALoot Events
     ========================================================================== --]]

-- === Enable Incoming Messages  ==============================================

E.Register("PLAYER_LOGIN", function()
	RegisterAddonMessagePrefix(A.MSG_PREFIX);
end);

--[[ ==========================================================================
     API Events
     ========================================================================== --]]

local eventFrame, events = CreateFrame("Frame"), {}

function events:CHAT_MSG_RAID(msg, author)
  CM.Trigger("RAID", author, msg);
end
function events:CHAT_MSG_RAID_LEADER(msg, author)
  CM.Trigger("RAID", author, msg);
end
function events:CHAT_MSG_CHANNEL(msg, author, _, _, _, _, _, _, channelName)
  CM.Trigger("CHANNEL", author, msg, channelName);
end
function events:CHAT_MSG_WHISPER(msg, author)
  CM.Trigger("WHISPER", author, msg);
end
function events:CHAT_MSG_ADDON(prefix, msg, channel, sender)
  if prefix == A.MSG_PREFIX then
    -- Decode the data
    local msg = libEncode:Decode(msg);
	
    -- Deserialize the data
    local success, deserialized = libSerialize:Deserialize(msg);
    if success then
      msg = deserialized;
    else
      error("Deserialization of incoming addon message failed.");
    end
    
    -- Constrain sender to Name-Realm format
    if not string.match(sender, "-") then
      sender = sender.."-"..SD.PLAYER_REALM;
    end
    
    -- If required by the sender, validate that the reciever has the correct version
    if msg["version"] and msg["version"] ~= A.MVERSION then
      return;
    end
    
    msg["version"] = nil;
    
    local mType = msg["type"];
    msg["type"] = nil;
    
    if not mType then
      return;
    end

    -- Check if this message type is blacklisted when sent from self
    if selfBlacklist[mType] and sender == SD.PLAYER_NAME then
      return;
    end
    
    U.debug('Recieved "'..mType..'" message from '..(sender or "Unknown")..".", 1);
    
    AM.Trigger(mType, channel, sender, unpack(msg));
  end
end
function events:BN_CHAT_MSG_ADDON(prefix, msg, _, sender)
  events:CHAT_MSG_ADDON(prefix, msg, "BN_WHISPER", sender);
end

eventFrame:SetScript("OnEvent", function(self, event, ...)
  events[event](self, ...) -- call one of the functions above
end)
for k, v in pairs(events) do
  eventFrame:RegisterEvent(k) -- Register all events for which handlers have been defined
end
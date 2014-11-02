local A = FALoot;
local F = A.functions;
local SD = A.sData;
local PD = A.pData;
local U = A.util;
local E = A.events;
local M = A.messages;

-- Load libraries
local libSerialize = LibStub:GetLibrary("AceSerializer-3.0");
local libCompress = LibStub:GetLibrary("LibCompress");
local libEncode = libCompress:GetAddonEncodeTable();

local bulkMessages = {};

--[[ ==========================================================================
     Communication Functions
     ========================================================================== --]]
     
F.sendMessage = function(dist, target, reqSameVersion, mType, ...)
  -- Determine priority
  local priority = "NORMAL";
  for i=1,#bulkMessages do
    if mType == bulkMessages[i] then
      priority = "BULK";
      break;
    end
  end
  
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
  FALoot:parseChat(msg, author)
end
function events:CHAT_MSG_RAID_LEADER(msg, author)
  FALoot:parseChat(msg, author)
end
function events:CHAT_MSG_CHANNEL(msg, author, _, _, _, _, _, _, channelName)
  if channelName == "aspects" then
    if not msg then
      return;
    end
    local itemLink = string.match(msg, SD.HYPERLINK_PATTERN);
    if not itemLink then
      return;
    end
    local itemString = U.ItemLinkStrip(itemLink);
    local msg = string.match(msg, SD.HYPERLINK_PATTERN.."(.+)"); -- now remove the link
    if not msg or msg == "" then
      return;
    end
    local msg = string.lower(msg) -- put in lower case
    local msg = " "..string.gsub(msg, "[/,]", " ").." "
    if string.match(msg, " d%s?e ") or string.match(msg, " disenchant ") then
      if UnitIsGroupAssistant("PLAYER") or UnitIsGroupLeader("PLAYER") then
        FALoot:sendMessage(ADDON_MSG_PREFIX, {
          ["reqVersion"] = ADDON_MVERSION,
          ["end"] = itemString,
        }, "RAID")
      end
      FALoot:itemEnd(itemString);
    end
  end
end
function events:CHAT_MSG_WHISPER(msg, author)
  if tellsInProgress then
    FALoot:parseWhisper(msg, author);
  end
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
      error("Deserialization of data failed.");
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
    
    U.debug('Recieved "'..mType..'" message from '..(sender or "Unknown")..".", 1);
    
    M.Trigger(mType, channel, sender, unpack(msg));
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
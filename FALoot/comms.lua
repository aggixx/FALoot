local A = FALoot;
local F = A.functions;

-- Load libraries
local libSerialize = LibStub:GetLibrary("AceSerializer-3.0");
local libEncode = libCompress:GetAddonEncodeTable();

local bulkMessages = {};

--[[ ==========================================================================
     Communication Functions
     ========================================================================== --]]
     
F.sendMessage = function(dist, target, mType, ...)
  -- Determine priority
  local priority = "NORMAL";
  for i=1,#bulkMessages do
    if mType == bulkMessages[i] then
      priority = "BULK";
    end
  end
  
  -- Prep data in table form
  local data = {...};
  data["type"] = mType;
  
  -- Serialize the data
  local serialized, msg = libSerialize:Serialize(data)
  if serialized then
    data = serialized
  else
    U.debug("Serialization of data failed!");
    return false, "serialization of data failed";
  end
  
  -- Encode the data
  local encoded, msg = libEncode:Encode(data)
  if encoded then
    data = encoded
  else
    U.debug("Encoding of data failed!");
    return false, "encoding of data failed";
  end
  
  -- Validate whisper target to prevent errors for the user.
  if string.upper(dist) == "WHISPER" then
    local groupType = ("raid" and IsInRaid()) or "party";
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
  A.stub:SendCommMessage(A.MESSAGE_PREFIX, data, dist, target, prio)
  return true;
end
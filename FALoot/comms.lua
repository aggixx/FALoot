local A = FALoot;
local F = A.functions;

-- Load libraries
local libSerialize = LibStub:GetLibrary("AceSerializer-3.0");
local libEncode = libCompress:GetAddonEncodeTable();

--[[ ==========================================================================
     Communication Functions
     ========================================================================== --]]
     
F.sendMessage = function(prefix, text, distribution, target, prio, validateTarget)
  --serialize
  local serialized, msg = libSerialize:Serialize(text)
  if serialized then
    text = serialized
  else
    U.debug("Serialization of data failed!");
    return false, "serialization of data failed";
  end
  
  --encode
  local encoded, msg = libEncode:Encode(text)
  if encoded then
    text = encoded
  else
    U.debug("Encoding of data failed!");
    return false, "encoding of data failed";
  end
  
  -- make sure target is valid
  if validateTarget and string.lower(distribution) == "WHISPER" then
    local groupType = ("raid" and IsInRaid()) or "party";
    for i=1,GetNumGroupMembers() do
      if U.UnitName(groupType..i, true) == target then
        if not UnitIsConnected(groupType..i) then
          local mType;
          for i,v in pairs(text) do
            mType = i;
            break;
          end
          U.debug("The target of message type "..(mType or "unknown")..' "'..target..'" is offline.', 2);
          return false, "target of message is offline";
        end
        break;
      end
    end
  end
  
  A.stub:SendCommMessage(prefix, text, distribution, target, prio)
  return true;
end
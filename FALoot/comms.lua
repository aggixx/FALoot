local A = FALoot;
local F = A.functions;

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






local eventFrame, events = CreateFrame("Frame"), {}

function events:LOOT_OPENED(...)
  if not A.isEnabled() then
    return;
  end
  local loot = {} -- create a temporary table to organize the loot on the mob
  for i=1,GetNumLootItems() do -- loop through all items in the window
    local sourceInfo = {GetLootSourceInfo(i)}
    for j=1,#sourceInfo/2 do
      local mobID = sourceInfo[j*2-1] -- retrieve GUID of the mob that holds the item
      if mobID and not hasBeenLooted[mobID] and not string.match(mobID, "0x4") then -- ignore items from sources that have already been looted or from item-based sources
        if not loot[mobID] then
          loot[mobID] = {};
        end
        
        local itemString = U.ItemLinkStrip(GetLootSlotLink(i));
        if itemString and U.checkFilters(itemString) then
          for l=1,max(sourceInfo[j*2], 1) do -- repeat the insert if there is multiple of the item in that slot.
            -- max() is there to remedy the bug with GetLootSourceInfo returning incorrect (0) values.
            -- GetLootSourceInfo may also return multiple quantity when there is actually only
            -- one of the item, but there's not much we can do about that.
            table.insert(loot[mobID], itemString);
          end
        end
      end
    end
  end
  
  -- prune enemies with no loot
  for i, v in pairs(loot) do
    if #v == 0 then
      loot[i] = nil;
    end
  end
  
  -- stop now if there's no loot
  if loot == {} then
    U.debug("There is no loot on this mob!", 1);
    return;
  end
  
  -- add an item count for each GUID so that other clients may verify data integrity
  for i, v in pairs(loot) do
    loot[i]["checkSum"] = #v;
  end
  
  U.debug(loot, 2);
  
  -- check data integrity
  for i, v in pairs(loot) do
    if not (v["checkSum"] and v["checkSum"] == #v) then
      U.debug("Self assembled loot data failed the integrity check.");
      return;
    end
    if #v == 0 then
      loot[i] = nil;
    end
  end
  
  -- send addon message to tell others to add this to their window
  FALoot:sendMessage(ADDON_MSG_PREFIX, {
    ["reqVersion"] = ADDON_MVERSION,
    ["loot"] = loot,
  }, "RAID", nil, "BULK");
  
  for i, v in pairs(loot) do
    for j=1,#v do
      -- we can assume that everything in the table is not on the HBL
      itemAdd(v[j])
    end
    hasBeenLooted[i] = true;
  end
  
  FALoot:itemTableUpdate();
end
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
    local itemLink = string.match(msg, HYPERLINK_PATTERN);
    if not itemLink then
      return;
    end
    local itemString = U.ItemLinkStrip(itemLink);
    local msg = string.match(msg, HYPERLINK_PATTERN.."(.+)"); -- now remove the link
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

eventFrame:SetScript("OnEvent", function(self, event, ...)
  events[event](self, ...) -- call one of the functions above
end)
for k, v in pairs(events) do
  eventFrame:RegisterEvent(k) -- Register all events for which handlers have been defined
end
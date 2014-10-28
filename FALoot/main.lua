--[[ =======================================================
	Bugs // To-do
     -------------------------------------------------------
	== Bugs to fix ==
	Button responsiveness
	Items posted to aspects

	== Features to implement / finish implementing ==
	More exact flag counter (MS items)
	Item history in tooltips

	More robust/expandable item tracking
	Ability to toggle skinning
	Make reminders exclusive to the person in the cart (and automated?)
	Add table dumps to debug log
	Rework addon message code to be register/unregister based to better support modularization

	== Must construct additional DATAZ ==
	Inconsistency with autoloot disable: must check addonEnabled on PLAYER_ENTERING_WORLD in a raid group with debug off
	Bids that don't go through (user error?)

	== Verify fixed/working ==
	Loot history tracking & sync
     ======================================================= --]]

-- Declare strings
local ADDON_NAME = "FALoot";

--[[ =======================================================
	Versioning
     ======================================================= --]]

local ADDON_MVERSION = 6; -- Addons only communicate with users of the same major version.
local ADDON_REVISION = 3; -- Specific code revision for identification purposes.

--[[ =======================================================
	Libraries
     ======================================================= --]]
     
FALoot = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME);
LibStub("AceComm-3.0"):Embed(FALoot);

local ScrollingTable = LibStub("ScrollingTable");
local libSerialize = LibStub:GetLibrary("AceSerializer-3.0");
local libCompress = LibStub:GetLibrary("LibCompress");
local libEncode = libCompress:GetAddonEncodeTable();
local libGraph = LibStub("LibGraph-2.0");

--[[ =======================================================
	Local Constants
     ======================================================= --]]

local ADDON_COLOR = "FFF9CC30";
local ADDON_CHAT_HEADER  = "|c" .. ADDON_COLOR .. "FA Loot:|r ";
local ADDON_MSG_PREFIX = "FALoot";
local ADDON_DOWNLOAD_URL = "https://github.com/aggixx/FALoot";

local HYPERLINK_PATTERN = "\124c%x+\124Hitem:%d+:%d+:%d+:%d+:%d+:%d+:%-?%d+:%-?%d+:?%d*:?%d*:?%d*:?%d*:?%d*:?%d*:?%d*\124h.-\124h\124r";
-- |c COLOR    |H linkType : itemId : enchantId : gemId1 : gemId2 : gemId3 : gemId4 : suffixId : uniqueId  : linkLevel : reforgeId :      :      :      :      :      |h itemName            |h|r
-- |c %x+      |H item     : %d+    : %d+       : %d+    : %d+    : %d+    : %d+    : %-?%d+   : %-?%d+    : ?%d*      : ?%d*      : ?%d* : ?%d* : ?%d* : ?%d* : ?%d* |h .-                  |h|r"
-- |c ffa335ee |H item     : 94775  : 4875      : 4609   : 0      : 0      : 0      : 65197    : 904070771 : 89        : 166       : 465                              |h [Beady-Eye Bracers] |h|r"
-- |c ffa335ee |H item     : 96740  : 0         : 0      : 0      : 0      : 0      : 0        : 0         : 90        : 0         : 0                                |h[ Sign of the Bloodied God] |h|r 30
local THUNDERFORGED_COLOR = "FFFF8000";
local PLAYER_REALM = GetRealmName();
local PLAYER_NAME = UnitName("player") .. "-" .. PLAYER_REALM;

--[[ =======================================================
	Option Variables
     ======================================================= --]]

-- Saved Variables
local debugOn = 0;		-- Debug threshold
local expTime = 15;		-- Amount of time before an ended item is removed from the window, in seconds.
local autolootToggle;
local autolootKey;

-- Hard-coded options
local maxIcons = 11;
local postRequestMaxWait = 3; -- Amount of time to wait for a response from the raid leader before posting a request anyway, in seconds.
local itemHistorySyncMinInterval = 60 * 5; -- Minimum amount of time between item history sync attempts, in seconds.
local cacheInterval = 200;	-- Amount of time between attempts to check for item data, in milliseconds.
local foodItemId = 101618;

-- Session Variables
local _;
local table_items = {};
local table_itemQuery = {};
local table_itemHistory = {};
local table_icons = {};
local table_who = {};
local hasBeenLooted = {};
local showAfterCombat;
local iconSelect;
local endPrompt;
local bidPrompt;
local promptBidValue;
local updateMsg;
local oldSelectStatus = 0;
local tellsInProgress;
local tellsGreenThreshold;
local tellsYellowThreshold;
local tellsRankThreshold;
local debugData = {};
local postRequestTimer;
local hasItemHistorySynced = false;
local itemHistorySync = {};
local foodCount = 0;
local raidFoodCount = {};
local foodUpdateTo = {};
local lastCartSummon = -120;

--[[ =======================================================
	GUI Elements
     ======================================================= --]]

local frame;
local iconFrame;
local scrollingTable;
local tellsButton;
local closeButton;
local bidButton;
local statusText;

local tellsFrame;
local tellsTitleText;
local tellsTable;
local tellsFrameAwardButton;
local tellsFrameActionButton;
local tellsTitleBg;

local foodFrame;
local foodFrameGraph;
local foodFrameMsg;
local foodColorKey = {};

local debugFrame;
local debugFrameEditbox;

--[[ =======================================================
	Helper Functions
     ======================================================= --]]

local function formatDebugData()
	local s = ""
	for i=1,#debugData do
		if i > 1 then
			s = s .. "\n";
		end
		s = s .. "[" .. date("%c", debugData[i].time) .. "]<" .. debugData[i].threshold .. "> " .. debugData[i].msg;
	end
	return s;
end;

local function debug(msg, verbosity)
	local output;
	if type(msg) == "string" or type(msg) == "number" or type(msg) == nil then
		output = msg or "nil";
	elseif type(msg) == "boolean" then
		output = msg;
	elseif type(msg) == "table" then
		if DevTools_Dump then
			if not verbosity or debugOn >= verbosity then
				DevTools_Dump(msg);
			end
			return;
		else
			output = "DevTools not found.";
		end
	else
		return;
	end
	table.insert(debugData, {
		["msg"] = output,
		["time"] = time(),
		["threshold"] = verbosity or 0,
	});
	if not verbosity or debugOn >= verbosity then
		print(ADDON_CHAT_HEADER..output);
	end
end

local function str_split(delimiter, text)
	local list = {}
	local pos = 1
	if strfind("", delimiter, 1) then -- this would result in endless loops
		error("delimiter matches empty string!")
	end
	while 1 do
		local first, last = strfind(text, delimiter, pos)
		if first then -- found?
			tinsert(list, strsub(text, pos, first-1))
			pos = last+1
		else
			tinsert(list, strsub(text, pos))
			break
		end
	end
	return list
end

local function deepcopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[deepcopy(orig_key)] = deepcopy(orig_value)
        end
        setmetatable(copy, deepcopy(getmetatable(orig)))
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

function deepCompare(t1, t2, ignore_mt)
	local ty1 = type(t1)
	local ty2 = type(t2)
	if ty1 ~= ty2 then return false end
	-- non-table types can be directly compared
	if ty1 ~= 'table' and ty2 ~= 'table' then return t1 == t2 end
	-- as well as tables which have the metamethod __eq
	local mt = getmetatable(t1)
	if not ignore_mt and mt and mt.__eq then return t1 == t2 end
	for k1,v1 in pairs(t1) do
		local v2 = t2[k1]
		if v2 == nil or not deepCompare(v1,v2) then return false end
	end
	for k2,v2 in pairs(t2) do
		local v1 = t1[k2]
		if v1 == nil or not deepCompare(v1,v2) then return false end
	end
	return true
end

-- hook GetUnitName
local UnitName_orig = UnitName;
local function UnitName(unit, showServer)
	local name = UnitName_orig(unit, showServer);
	if showServer and name and not string.match(name, "-") then
		name = name .. "-" .. PLAYER_REALM;
	end
	return name;
end

-- hook GetRaidRosterInfo
local GetRaidRosterInfo_orig = GetRaidRosterInfo;
local function GetRaidRosterInfo(index)
	local name, rank, subgroup, level, class, fileName, zone, online, isDead, role, isML = GetRaidRosterInfo_orig(index);
	return (UnitName("raid"..index, true) or name), rank, subgroup, level, class, fileName, zone, online, isDead, role, isML;
end

-- Get current server timestamp
local function GetCurrentServerTime()
	local _, hours, minutes = GameTime_GetGameTime(true);
	local _, month, day, year = CalendarGetDate();
	local currentServerTime = time({
		["hour"] = hours,
		["min"] = minutes,
		["month"] = month,
		["day"] = day,
		["year"] = year,
	});
	return currentServerTime;
end

local function ItemLinkStrip(itemLink)
	if itemLink then
		local _, _, linkColor, linkType, itemId, enchantId, gemId1, gemId2, gemId3, gemId4, suffixId, uniqueId, linkLevel, reforgeId, itemName =
		string.find(itemLink, "|?c?f?f?(%x*)|?H?([^:]*):?(%d+):?(%d*):?(%d*):?(%d*):?(%d*):?(%d*):?(%-?%d*):?(%-?%d*):?(%d*):?(%d*):%d+|?h?%[?([^%[%]]*)%]?|?h?|?r?")
		if itemId and suffixId then
			suffixId = tonumber(suffixId);
			-- super hacky workaround for blizzard's weird suffixId system
			if suffixId > 60000 then
				suffixId = suffixId - 65536;
			end
			local s = itemId..":"..suffixId;
			debug(s, 3);
			return s;
		end
	else
		debug("ItemLinkStrip was passed a nil value!", 1);
		return;
	end
end

local function ItemLinkAssemble(itemString)
	if string.match(itemString, "^%d+:%-?%d+") then
		local itemId, suffixId, srcGUID = string.match(itemString, "^(%d+):(%-?%d+)");
		local fullItemString = "item:"..itemId..":0:0:0:0:0:"..suffixId;
		local _, link = GetItemInfo(fullItemString);
		if not link then
			return;
		end
		debug(link, 3);
		return link;
	end
end

local function isNameInGuild(name)
	local showOffline = GetGuildRosterShowOffline();
	SetGuildRosterShowOffline(false);
	local _, onlineguildies = GetNumGuildMembers();
	for j=1,onlineguildies do
		local jname = GetGuildRosterInfo(j);
		if jname == name then
			return true;
		end
	end
	SetGuildRosterShowOffline(showOffline);
end

local function isGuildGroup(threshold)
	GuildRoster()
	local groupType
	if IsInRaid() then
		groupType = "raid"
	else
		groupType = "party"
	end
	local numguildies = 0
	local numOffline = 0
	for i=1,GetNumGroupMembers() do
		local iname = GetRaidRosterInfo(i)
		if iname then
			if isNameInGuild(iname) then
				numguildies = numguildies + 1
			end
			if not UnitIsConnected(groupType..i) then
				numOffline = numOffline + 1
			end
		end
	end
	local ratio = numguildies / ( GetNumGroupMembers() - numOffline );
	
	if threshold then
  	return ratio >= threshold;
  else
    return ratio;
  end
end

local function isMainRaid()
	-- Refresh guild roster
	GuildRoster()
	
	-- Set some variables
	local groupType = (IsInRaid() and "raid") or "party";
	local officers, drakes = 0, 0;
	
	-- Filter to only online players & save current setting for later restoration
	local showOffline = GetGuildRosterShowOffline(); 
	
	-- Loop through the raid and count the number of drakes and aspects
	for i=1,40 do
		if UnitExists(groupType..i) then
			local uName = GetRaidRosterInfo(i)
			
			-- Set Show Offline bool appropriately
			local numOnline;
			if UnitIsConnected(groupType..i) then
				SetGuildRosterShowOffline(false);
				numOnline = select(2, GetNumGuildMembers());
			else
				SetGuildRosterShowOffline(true);
				numOnline = GetNumGuildMembers();
			end
			
			for j=1,numOnline do
				local gName, rank = GetGuildRosterInfo(j)
				if uName == gName then
					-- Increment appropriate counter
					if rank == "Aspect" or rank == "Aspects" or rank == "Dragon" then
						officers = officers + 1;
					elseif rank == "Drake" then
						drakes = drakes + 1;
					end
					
					-- Move on to the next unit
					break;
				end
			end
		end
	end

	-- Restore show offline setting
	SetGuildRosterShowOffline(showOffline);
	
	return officers >= 2 and drakes >= 4;
end

function FALoot:addonEnabled(overrideDebug)
	if not overrideDebug and debugOn > 0 then
		return 1;
	end
	
	if not isGuildGroup(0.60) then
		return nil, "not guild group";
	elseif not isMainRaid() then
		return nil, "not enough officers";
	end
	
	local _, iType, iDifficulty = GetInstanceInfo()
	
	if iType ~= "raid" then
		return nil, "wrong instance type";
	elseif not ( iDifficulty == 15 or iDifficulty == 16 ) then -- Heroic or Mythic
		return nil, "wrong instance difficulty";
	elseif GetNumGroupMembers() < 15 then
		return nil, "not enough group members";
	end
	
	return 1;
end

function FALoot:checkFilters(itemString, checkItemLevel)
	-- itemString must be a string!
	if type(itemString) ~= "string" then
		debug("checkFilters was passed a non-string value!", 1);
		return;
	end

	--this is the function that determines if an item should or shouldn't be added to the window and/or announced
	local itemLink = ItemLinkAssemble(itemString);
	
	if not itemLink then
		debug("checkFilters: Unable to retrieve itemLink! itemString = "..itemString..", itemLink = "..(itemLink or ""), 1);
		return false;
	end
	
	if debugOn > 0 then
		return true
	end
	
	-- check properties of item
	local _, _, quality, ilevel, _, class, subClass = GetItemInfo(itemLink)
	
	-- check if the quality of the item is high enough
	if quality ~= 4 then -- TODO: Add customizable quality filters
		debug("Quality of "..itemLink.." is too low.", 1);
		return false
	end
		
	-- check if the class of the item is appropriate
	if not (class == "Armor" or class == "Weapon" or (class == "Miscellaneous" and subClass == "Junk")) then
		debug("Class of "..itemLink.." is incorrect.", 1)
		return false
	end
	
	-- check if the item level of the item is high enough
	if checkItemLevel then
		local playerTotal = GetAverageItemLevel()
		if playerTotal - ilevel > 60 then -- if the item is more than 60 levels below the player
			debug("Item Level of "..itemLink.." is too low.", 1);
			return false
		end
	end
	
	return true
end

local function StaticDataSave(data)
	promptBidValue = data
end

--[[ =======================================================
	Main Functions
     ======================================================= --]]

local function itemAdd(itemString, checkCache)
	debug("itemAdd(), itemString = "..itemString, 1);
	-- itemString must be a string!
	if type(itemString) ~= "string" then
		debug("itemAdd was passed a non-string value!", 1);
		return;
	end
	
	local itemLink = ItemLinkAssemble(itemString);
	
	-- caching stuff
	if itemLink then
		debug("Item is cached, continuing.", 1);
		for i=1,#table_itemQuery do
			if table_itemQuery[i] == itemString then
				table.remove(table_itemQuery, i)
				break
			end
		end
	else
		if not checkCache then
			debug("Item is not cached, requesting item info from server.", 1);
			table.insert(table_itemQuery, itemString);
		else
			debug("Item is not cached, aborting.", 1);
		end
		return;
	end
	
	-- check if item passes the filter
	if not FALoot:checkFilters(itemString, true) then
		debug(itemString.." did not pass the item filter.", 2);
		return;
	end
	
	-- Workaround for random suffix items with broken item links
	local tooltipItemLink = itemLink;
	itemString = string.gsub(itemString, "%-?%d+$", "0");
	itemLink = ItemLinkAssemble(itemString);
	
	if table_items[itemString] then
		table_items[itemString]["quantity"] = table_items[itemString]["quantity"] + 1;
		local _, _, _, iLevel, _, _, _, _, _, texture = GetItemInfo(itemLink);
		local displayName = itemLink
		if FALoot:isThunderforged(iLevel) then
			displayName = string.gsub(displayName, "|c%x+|", "|c"..THUNDERFORGED_COLOR.."|");
		end
		if table_items[itemString]["quantity"] > 1 then
			displayName = displayName .. " x" .. table_items[itemString]["quantity"];
		end
		table_items[itemString]["displayName"] = displayName;
	else
		local _, _, _, iLevel, _, _, _, _, _, texture = GetItemInfo(itemLink);
		local displayName = itemLink
		if FALoot:isThunderforged(iLevel) then
			displayName = string.gsub(displayName, "|c%x+|", "|c"..THUNDERFORGED_COLOR.."|");
		end
		table_items[itemString] = {
			["quantity"] = 1,
			["displayName"] = displayName,
			["itemLink"] = itemLink,
			["texture"] = texture,
			["currentValue"] = 30,
			["winners"] = {},
			["tooltipItemLink"] = tooltipItemLink,
		}
	end
	
	if not frame:IsShown() then
		if UnitAffectingCombat("PLAYER") then
			showAfterCombat = true
			debug(itemLink.." was found but the player is in combat.");
		else
			frame:Show()
		end
	end
	
	return true
end

function FALoot:itemAdd(itemString, checkCache)
	itemAdd(itemString, checkCache);
	FALoot:itemTableUpdate();
end

function FALoot:itemTakeTells(itemString)
	debug("itemTakeTells(), itemString = "..itemString, 1);
	-- itemString must be a string!
	if type(itemString) ~= "string" then
		debug("itemTakeTells was passed a non-string value!", 1);
		return;
	end
	
	if table_items[itemString] and not table_items[itemString]["status"] then
		table_items[itemString]["tells"] = {};
		tellsInProgress = itemString;
		tellsTitleText:SetText(table_items[itemString]["displayName"]);
		tellsTitleBg:SetWidth((tellsTitleText:GetWidth() or 0) + 10);
		FALoot:tellsTableUpdate();
		SendChatMessage(table_items[itemString]["itemLink"].." 30", "RAID");
		tellsButton:Disable();
	else
		debug("Item does not exist or is already in progress!", 1);
	end
end

function FALoot:itemRequestTakeTells(itemString)
	debug("itemRequestTakeTells("..itemString..")", 1);

	-- Make sure that this is an item we can actually take tells on before trying to submit a request
	if not table_items[itemString] or table_items[itemString]["status"] or table_items[itemString]["host"] then
		debug("Invalid itemString, aborting.", 1);
		return;
	end
	-- Acquire name of raid leader
	local raidLeader, raidLeaderUnitID;
	if IsInRaid() then
		for i=1,GetNumGroupMembers() do
			if UnitIsGroupLeader("raid"..i) and UnitIsConnected("raid"..i) then
				raidLeader = UnitName("raid"..i, true);
				raidLeaderUnitID = "raid"..i;
				break;
			end
		end
	elseif debugOn > 0 then
		-- For testing purposes, let's let the player act as the raid leader.
		raidLeader = PLAYER_NAME;
	else
		return;
	end
	if raidLeader and raidLeader == "Unknown" then
		debug("Raid leader was found, but returned name Unknown. Aborting.", 1);
		return;
	elseif raidLeader then
		-- Set itemString to become the active tells item
		tellsInProgress = itemString;
		if (raidLeaderUnitID and UnitIsConnected(raidLeaderUnitID)) or (not IsInRaid() and debugOn > 0) then
			-- Ask raid leader for permission to start item
			debug('Asking Raid leader "' .. raidLeader .. '" for permission to post item (' .. itemString .. ').', 1);
			FALoot:sendMessage(ADDON_MSG_PREFIX, {
				["postRequest"] = itemString,
			}, "WHISPER", raidLeader);
			-- Set request timer
			postRequestTimer = GetTime();
		else
			-- Leader is offline, so let's just go ahead post the item.
			debug('Raid leader "' .. raidLeader .. '" is offline, skipping redundancy check.', 1);
			FALoot:itemTakeTells(itemString);
		end
	else
		debug("Raid leader not found. Aborting.", 1);
		return;
	end
end

function FALoot:sendMessage(prefix, text, distribution, target, prio, validateTarget)
	--serialize
	local serialized, msg = libSerialize:Serialize(text)
	if serialized then
		text = serialized
	else
		debug("Serialization of data failed!");
		return false, "serialization of data failed";
	end
	
	--[[
	--compress
	local compressed, msg = libCompress:CompressHuffman(text)
	if compressed then
		text = compressed
	else
		debug("Compression of data failed!");
		return false, "compression of data failed";
	end
	--]]
	
	--encode
	local encoded, msg = libEncode:Encode(text)
	if encoded then
		text = encoded
	else
		debug("Encoding of data failed!");
		return false, "encoding of data failed";
	end
	
	-- make sure target is valid
	if validateTarget and string.lower(distribution) == "WHISPER" then
		local groupType = ("raid" and IsInRaid()) or "party";
		for i=1,GetNumGroupMembers() do
			if UnitName(groupType..i, true) == target then
				if not UnitIsConnected(groupType..i) then
					local mType;
					for i,v in pairs(text) do
						mType = i;
						break;
					end
					debug("The target of message type "..(mType or "unknown")..' "'..target..'" is offline.', 2);
					return false, "target of message is offline";
				end
				break;
			end
		end
	end
	
	FALoot:SendCommMessage(prefix, text, distribution, target, prio)
	return true;
end

local function updatePieChart()
	local groupType, members = "raid", GetNumGroupMembers();
	if not IsInRaid() then
		groupType = "party";
		members = members - 1;
	end
	for i,v in pairs(raidFoodCount) do
		local found;
		for j=1,members do
			if i == GetUnitName(groupType..j, true) then
				found = true;
				break;
			end
		end
		if not found then
			raidFoodCount[i] = nil;
		end
	end

	foodFrameGraph:ResetPie();
	for i=1,#foodColorKey do
		foodColorKey[i][3]:SetText("");
	end
	
	local t = {};
	for i, v in pairs(raidFoodCount) do
		t[v] = (t[v] or 0) + 1;
	end
	
	local total = 0;
	for i, v in pairs(t) do
		local color;
		if i >= 5 then
			color = {0, 1, 0};
		elseif i == 4 then
			color = {1/2, 1, 0};
		elseif i == 3 then
			color = {1, 1, 0};
		elseif i == 2 then
			color = {1, 2/3, 0};
		elseif i == 1 then
			color = {1, 1/3, 0};
		else
			color = {1, 0, 0};
		end
		foodFrameGraph:AddPie(v/GetNumGroupMembers()*100, color);
		
		for j=1,#foodColorKey do
			if foodColorKey[j][2]:GetText() == tostring(i) then
				foodColorKey[j][3]:SetText(v);
				break
			end
		end
		
		total = total + v;
	end
	
	foodFrameGraph:CompletePie({1/5, 1/5, 1/5})
	for j=1,#foodColorKey do
		if foodColorKey[j][2]:GetText() == "?" then
			foodColorKey[j][3]:SetText(GetNumGroupMembers()-total);
			break
		end
	end
end

function FALoot:OnCommReceived(prefix, text, distribution, sender)
	if prefix ~= ADDON_MSG_PREFIX or not text then
		return;
	end
	debug("Recieved addon message from "..(sender or "Unknown")..".", 1);
	
	-- Decode the data
	local t = libEncode:Decode(text)
	
	-- Deserialize the data
	local success, deserialized = libSerialize:Deserialize(t)
	if success then
		t = deserialized
	else
		debug("Deserialization of data failed.");
		return
	end
	
	-- Constrain sender to Name-Realm format
	if not string.match(sender, "-") then
		sender = sender.."-"..PLAYER_REALM;
	end
	
	-- List of whitelisted message types
	-- Add an entry here to allow the player to recieve messages from themself of that type.
	local whitelisted = {
		"who",
		"postRequest",
		"postReply",
	};
	
	-- Block messages from very old versions
	if t["ADDON_VERSION"] then
		return;
	end
	
	-- Block all messages from self that are not of a type included in the whitelist
	if sender == PLAYER_NAME then
		local allow = false;
		for i=1,#whitelisted do
			if t[whitelisted[i]] ~= nil then
				allow = true;
				break;
			end
		end
		if not allow then
			debug("Message from self and not of a whitelisted type, discarding.", 1);
			return;
		end
	end
	
	debug(t, 2);
	
	-- If the message is version-specific and from a different version then block it.
	if t["reqVersion"] and t["reqVersion"] ~= ADDON_MVERSION then
		return;
	end
	
	if t["loot"] then
		if FALoot:addonEnabled() then
			local loot = t["loot"]
			
			-- check data integrity
			for i, v in pairs(loot) do
				if not (v["checkSum"] and v["checkSum"] == #v) then
					debug("Loot data recieved via an addon message failed the integrity check.");
					return;
				end
			end
			
			debug("Loot data is valid.", 2);
			
			for i, v in pairs(loot) do
				if not hasBeenLooted[i] then
					for j=1,#v do
						debug("Added "..v[j].." to the loot window via addon message.", 2);
						itemAdd(v[j]);
					end
					hasBeenLooted[i] = true;
				else
					debug(i.." has already been looted.", 2);
				end
			end
			
			FALoot:itemTableUpdate();
		end
	elseif t["end"] then
		FALoot:itemEnd(t["end"])
	elseif t["who"] then
		if distribution == "WHISPER" then
			local senderRev = t["who"]
			
			table_who = table_who or {}
			if senderRev then
				-- Remove realm suffix
				sender = string.match(sender, "^(.-)%-.+");
				debug("Who response recieved from "..sender..".", 1);
				if not table_who[senderRev] then
					table_who[senderRev] = {}
					table.insert(table_who, senderRev)
				end
				table.insert(table_who[senderRev], sender)
			end
			table_who["time"] = GetTime()
		elseif distribution == "GUILD" then
			FALoot:sendMessage(ADDON_MSG_PREFIX, {
				["who"] = "r"..ADDON_REVISION,
			}, "WHISPER", sender)
		end
	elseif t["update"] then
		if distribution == "WHISPER" then
			if not updateMsg then
				debug("Your current version of "..ADDON_NAME.." is not up to date! Please go to "..ADDON_DOWNLOAD_URL.." to update.");
				updateMsg = true
			end
		elseif distribution == "RAID" or distribution == "GUILD" then
			local senderRev = t["update"]
			if senderRev < ADDON_REVISION then
				FALoot:sendMessage(ADDON_MSG_PREFIX, {
					["update"] = true,
				}, "WHISPER", sender, nil, distribution == "RAID");
			elseif not updateMsg and ADDON_REVISION < senderRev then
				debug("Your current version of "..ADDON_NAME.." is not up to date! Please go to "..ADDON_DOWNLOAD_URL.." to update.");
				updateMsg = true
			end
		end
	elseif t["itemWinner"] then
		FALoot:itemAddWinner(
			t["itemWinner"]["itemString"],
			t["itemWinner"]["winner"],
			t["itemWinner"]["bid"],
			t["itemWinner"]["time"]
		);
	elseif t["foodTrackOn"] then
		if foodCount then
			FALoot:sendMessage(ADDON_MSG_PREFIX, {
				["foodCount"] = foodCount,
			}, "WHISPER", sender, nil, true)
		end
		foodUpdateTo[sender] = true;
		debug("foodTrackOn recieved from "..sender, 1);
	elseif t["foodTrackOff"] then
		foodUpdateTo[sender] = nil;
		debug("foodTrackOff recieved from "..sender, 1);
	elseif t["foodCount"] and type(t["foodCount"]) == "number" then
		raidFoodCount[sender] = t["foodCount"];
		debug("foodCount recieved from "..sender..": "..t["foodCount"], 1);
		
		updatePieChart();
	elseif t["postRequest"] then
		local requestedItem = t["postRequest"];
		-- validate input
		if requestedItem then
			debug('Received postRequest from "' .. sender .. '" on item "' .. requestedItem .. '".', 1);
		else
			debug("Received postRequest with no itemString, aborting.", 1);
			return;
		end
		
		if not table_items[requestedItem] then
			debug("Item does not exist, denying request.", 1);
			FALoot:sendMessage(ADDON_MSG_PREFIX, {
				["postReply"] = false,
			}, "WHISPER", sender, nil, true);
		elseif table_items[requestedItem]["status"] then
			debug("Item is already in progress, denying request.", 1);
			FALoot:sendMessage(ADDON_MSG_PREFIX, {
				["postReply"] = false,
			}, "WHISPER", sender, nil, true);
		elseif table_items[requestedItem]["host"] then
			debug('Item has already been claimed for posting by "' .. table_items[requestedItem]["host"] .. '", denying request.', 1);
			FALoot:sendMessage(ADDON_MSG_PREFIX, {
				["postReply"] = false,
			}, "WHISPER", sender, nil, true);
		else
			debug('Request granted.', 1);
			table_items[requestedItem]["host"] = sender;
			FALoot:sendMessage(ADDON_MSG_PREFIX, {
				["postReply"] = true,
			}, "WHISPER", sender, nil, true);
		end
	elseif t["postReply"] ~= nil and tellsInProgress and postRequestTimer then
		if t["postReply"] == true then
			debug('Request to post item "' .. tellsInProgress .. '" has been granted. Posting...', 1);
			FALoot:itemTakeTells(tellsInProgress);
		elseif t["postReply"] == false then
			debug('Request to post item "' .. tellsInProgress .. '" has been denied. Item abandoned.', 1);
			-- cancel the item in progress
			tellsInProgress = nil;
			-- force a button state update
			FALoot:onTableSelect(scrollingTable:GetSelection());
		end
		
		postRequestTimer = nil;
	elseif t["historySyncRequest"] or t["historySyncRequestFull"] then
		local mType;
		if t["historySyncRequest"] then
			mType = "historySyncRequest";
		else
			mType = "historySyncRequestFull";
		end
		
		-- Count our current number of applicable entries
		local count = 0;
		if mType == "historySyncRequestFull" then
			count = #table_itemHistory;
		else
			for i=#table_itemHistory,1,-1 do
				if GetCurrentServerTime()-table_itemHistory[i].time <= 60*60*12 then
					count = count + 1;
				else
					break;
				end
			end
		end
		
		if count > t[mType] then
			debug("Recieved "..mType..", replying with count "..count..".", 1);
			FALoot:sendMessage(ADDON_MSG_PREFIX, {
				["historySyncCount"] = count,
			}, "WHISPER", sender, nil, true);
		else
			debug("Recieved "..mType.." but count is equal or lower.", 2);
		end
	elseif t["historySyncCount"] and itemHistorySync.p1 and not itemHistorySync.p2 then
		debug("Recieved historySyncCount of "..t["historySyncCount"].." from "..sender..".", 2);
		table.insert(itemHistorySync.p1, {sender, t["historySyncCount"]});
	elseif t["historySyncStart"] ~= nil then
		debug("Recieved historySyncStart from "..sender..", commencing info dump!", 1);
		local items = {};
		if t["historySyncStart"] then
			items = deepcopy(table_itemHistory);
		else
			for i=#table_itemHistory,1,-1 do
				if GetCurrentServerTime()-table_itemHistory[i].time <= 60*60*12 then
					table.insert(items, 1, table_itemHistory[i]);
				else
					break;
				end
			end
		end
		FALoot:sendMessage(ADDON_MSG_PREFIX, {
			["historySyncData"] = items,
		}, "WHISPER", sender, "BULK", true);
	elseif t["historySyncData"] and itemHistorySync.p2 then
		debug("Received historySyncData from "..sender..", parsing...", 1);
		
		-- Shorten things up a tad
		local t = t["historySyncData"];
		
		for i=1,#t do
			local foundMatch = false;
			for j=#table_itemHistory,1,-1 do
				if t[i] == table_itemHistory[j] then
					foundMatch = true;
					break;
				end
			end
			if not foundMatch then
				debug('Sending historySyncVerifyRequest for item "'..t[i].itemString..'".', 2);
				FALoot:sendMessage(ADDON_MSG_PREFIX, {
					["historySyncVerifyRequest"] = t[i],
				}, "RAID", nil, "BULK");
				t[i].verifies = 0;
				table.insert(itemHistorySync.p2, t[i]);
			end
		end
		
		itemHistorySync.p2.time = GetTime();
	elseif t["historySyncVerifyRequest"] then
		debug("Recieved historySyncVerifyRequest from "..sender..".", 1);
		debug(t["historySyncVerifyRequest"], 3);

		for i=#table_itemHistory,1,-1 do
			if deepCompare(t["historySyncVerifyRequest"], table_itemHistory[i]) then
				local success, reason = FALoot:sendMessage(ADDON_MSG_PREFIX, {
					["historySyncVerify"] = t["historySyncVerifyRequest"],
				}, "WHISPER", sender, nil, true);
				if success then
					debug("Verified request.", 1);
				else
					debug("Attempted to verify request, but "..reason..".", 1);
				end
				break;
			end
		end
	elseif t["historySyncVerify"] and itemHistorySync.p2 then
		debug("Received historySyncVerify from "..sender..".", 1);
		for i=1,#itemHistorySync.p2 do
			local compare = deepcopy(itemHistorySync.p2[i]);
			compare.verifies = nil;
		
			if deepCompare(t["historySyncVerify"], compare) then
				itemHistorySync.p2[i].verifies = itemHistorySync.p2[i].verifies + 1;
				
				-- if we have enough verifies, let's go ahead and insert it now
				if itemHistorySync.p2[i].verifies >= 5 or (debugOn > 0 and itemHistorySync.p2[i].verifies >= 1) then
					debug("Entry has received enough verifies, adding to itemHistory.", 1);
					for j=#table_itemHistory,1,-1 do
						if table_itemHistory[j].time < compare.time then
							table.insert(table_itemHistory, j+1, compare);
							table.remove(itemHistorySync.p2, i);
							break
						end
					end
				end
				break;
			end
		end
	end
end

function FALoot:createGUI()
	-- Create the main frame
	frame = CreateFrame("frame", "FALootFrame", UIParent)
	frame:EnableMouse(true);
	frame:SetMovable(true);
	frame:SetMovable(true);
	frame:SetFrameStrata("FULLSCREEN_DIALOG");
	frame:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = { left = 8, right = 8, top = 8, bottom = 8 }
	});
	frame:SetBackdropColor(0, 0, 0, 1);
	frame:SetToplevel(true);
	frame:SetWidth(500);
	frame:SetHeight(270);
	frame:SetPoint("CENTER");

	-- Create the frame that holds the icons
	iconFrame = CreateFrame("frame", frame:GetName().."IconFrame", frame);
	iconFrame:SetHeight(40);
	iconFrame:SetWidth(500);
	iconFrame:SetPoint("TOP", frame, "TOP", 0, -30);
	iconFrame:Show();
	
	-- Populate the iconFrame with icons
	for i=1,maxIcons do
		table_icons[i] = CreateFrame("frame", iconFrame:GetName().."Icon"..tostring(i), iconFrame)
		table_icons[i]:SetWidth(40)
		table_icons[i]:SetHeight(40)
		table_icons[i]:Hide()
	end

	-- Create the scrollingTable
	scrollingTable = ScrollingTable:CreateST({
		{
			["name"] = "Item",
			["width"] = 207,
			["align"] = "LEFT",
			["color"] = { ["r"] = 1.0, ["g"] = 1.0, ["b"] = 1.0, ["a"] = 1.0 },
			["defaultsort"] = "asc",
		},
		{
			["name"] = "Status",
			["width"] = 60,
			["align"] = "LEFT",
			["color"] = { ["r"] = 1.0, ["g"] = 1.0, ["b"] = 1.0, ["a"] = 1.0 },
			["defaultsort"] = "dsc",
		},
		{
			["name"] = "Winner(s)",
			["width"] = 140,
			["align"] = "LEFT",
			["color"] = { ["r"] = 1.0, ["g"] = 1.0, ["b"] = 1.0, ["a"] = 1.0 },
			["defaultsort"] = "dsc",
		}
	}, 8, nil, {["r"] = 0, ["g"] = 1, ["b"] = 0, ["a"] = 0.3}, frame);
	scrollingTable:EnableSelection(true);
	scrollingTable.frame:SetPoint("TOP", iconFrame, "BOTTOM", 0, -20);
	scrollingTable.frame:SetScale(1.1);

	-- Create the "Close" button
	closeButton = CreateFrame("Button", frame:GetName().."CloseButton", frame, "UIPanelButtonTemplate")
	closeButton:SetPoint("BOTTOMRIGHT", -27, 17)
	closeButton:SetHeight(20)
	closeButton:SetWidth(80)
	closeButton:SetText(CLOSE)
	closeButton:SetScript("OnClick", function(self)
		self:GetParent():Hide();
	end);
	
	-- Create the "Bid" button
	bidButton = CreateFrame("Button", frame:GetName().."BidButton", frame, "UIPanelButtonTemplate")
	bidButton:SetPoint("BOTTOMRIGHT", closeButton, "BOTTOMLEFT", -5, 0)
	bidButton:SetHeight(20)
	bidButton:SetWidth(80)
	bidButton:SetText("Bid")
	bidButton:SetScript("OnClick", function(self, event)
		local id = scrollingTable:GetSelection()
		local j, itemLink, itemString = 0;
		for i, v in pairs(table_items) do
			j = j + 1;
			if j == id then
				itemLink, itemString = v["itemLink"], i;
				break;
			end
		end
		bidPrompt = coroutine.create(function(self)
			debug("Bid recieved, resuming coroutine.", 1)
			local bid = tonumber(promptBidValue)
			if bid < 30 and bid ~= 10 and bid ~= 20 then
				debug("You must bid 10, 20, 30, or a value greater than 30. Your bid has been cancelled.")
				return
			end
			if bid % 2 ~= 0 then
				bid = math.floor(bid)
				if bid % 2 == 1 then
					bid = bid - 1
				end
				debug("You are not allowed to bid odd numbers or non-integers. Your bid has been rounded down to the nearest even integer.")
			end
			debug("Passed info onto FALoot:itemBid().", 1);
			FALoot:itemBid(itemString, bid)
		end)
		StaticPopupDialogs["FALOOT_BID"]["text"] = "How much would you like to bid for "..itemLink.."?";
		StaticPopup_Show("FALOOT_BID");
		debug("Querying for bid, coroutine paused.", 1);
	end);
	bidButton:Disable();

	-- Create the background of the Status Bar
	local statusbg = CreateFrame("Button", frame:GetName().."StatusBar", frame)
	statusbg:SetPoint("BOTTOMLEFT", 15, 15)
	statusbg:SetPoint("BOTTOMRIGHT", -197, 15)
	statusbg:SetHeight(24)
	statusbg:SetBackdrop({
		bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 3, right = 3, top = 5, bottom = 3 }
	})
	statusbg:SetBackdropColor(0.1,0.1,0.1)
	statusbg:SetBackdropBorderColor(0.4,0.4,0.4)

	-- Create the text of the Status Bar
	statusText = statusbg:CreateFontString(statusbg:GetName().."Text", "OVERLAY", "GameFontNormal")
	statusText:SetPoint("TOPLEFT", 7, -2)
	statusText:SetPoint("BOTTOMRIGHT", -7, 2)
	statusText:SetHeight(20)
	statusText:SetJustifyH("LEFT")
	statusText:SetText("")

	-- Create the background of the title
	local titlebg = frame:CreateTexture(frame:GetName().."TitleBackground", "OVERLAY")
	titlebg:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
	titlebg:SetTexCoord(0.31, 0.67, 0, 0.63)
	titlebg:SetPoint("TOP", 0, 12)
	titlebg:SetHeight(40)

	-- Create the title frame
	local title = CreateFrame("Frame", frame:GetName().."TitleMover", frame)
	title:EnableMouse(true)
	title:SetScript("OnMouseDown", function(frame)
		frame:GetParent():StartMoving()
	end)
	title:SetScript("OnMouseUp", function(frame)
		frame:GetParent():StopMovingOrSizing()
	end)
	title:SetAllPoints(titlebg)

	-- Create the text of the title
	local titletext = title:CreateFontString(frame:GetName().."TitleText", "OVERLAY", "GameFontNormal")
	titletext:SetPoint("TOP", titlebg, "TOP", 0, -14)
	titletext:SetText("FA Loot");
	
	titlebg:SetWidth((titletext:GetWidth() or 0) + 10)

	-- Create the title background left edge
	local titlebg_l = frame:CreateTexture(frame:GetName().."TitleEdgeLeft", "OVERLAY")
	titlebg_l:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
	titlebg_l:SetTexCoord(0.21, 0.31, 0, 0.63)
	titlebg_l:SetPoint("RIGHT", titlebg, "LEFT")
	titlebg_l:SetWidth(30)
	titlebg_l:SetHeight(40)

	-- Create the title background right edge
	local titlebg_r = frame:CreateTexture(frame:GetName().."TitleEdgeRight", "OVERLAY")
	titlebg_r:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
	titlebg_r:SetTexCoord(0.67, 0.77, 0, 0.63)
	titlebg_r:SetPoint("LEFT", titlebg, "RIGHT")
	titlebg_r:SetWidth(30)
	titlebg_r:SetHeight(40)
	
	-- //////////////////////
	-- Creation of Tells Frame
	-- //////////////////////
	
	-- Create the main tellsFrame
	tellsFrame = CreateFrame("frame", "FALootTellsFrame", UIParent)
	tellsFrame:EnableMouse(true);
	tellsFrame:SetMovable(true);
	tellsFrame:SetFrameStrata("FULLSCREEN_DIALOG");
	tellsFrame:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = { left = 8, right = 8, top = 8, bottom = 8 }
	});
	tellsFrame:SetBackdropColor(0, 0, 0, 1);
	tellsFrame:SetToplevel(true);
	tellsFrame:SetWidth(348);
	tellsFrame:SetHeight(184);
	tellsFrame:SetPoint("CENTER");
	tellsFrame:Hide();

	-- Create the background of the title
	tellsTitleBg = tellsFrame:CreateTexture(nil, "OVERLAY")
	tellsTitleBg:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
	tellsTitleBg:SetTexCoord(0.31, 0.67, 0, 0.63)
	tellsTitleBg:SetPoint("TOP", 0, 12)
	tellsTitleBg:SetHeight(40)
	
	-- Create the title frame
	local tellsTitle = CreateFrame("Frame", nil, tellsFrame)
	tellsTitle:EnableMouse(true)
	tellsTitle:SetScript("OnMouseDown", function(frame)
		frame:GetParent():StartMoving()
	end)
	tellsTitle:SetScript("OnMouseUp", function(frame)
		frame:GetParent():StopMovingOrSizing()
	end)
	tellsTitle:SetAllPoints(tellsTitleBg)

	-- Create the text of the title
	tellsTitleText = tellsTitle:CreateFontString(nil, "OVERLAY", "GameFontNormal");
	tellsTitleText:SetPoint("TOP", tellsTitleBg, "TOP", 0, -14);
	
	tellsTitleBg:SetWidth((tellsTitleText:GetWidth() or 0) + 10)

	-- Create the title background left edge
	local tellsTitleBg_l = tellsFrame:CreateTexture(nil, "OVERLAY")
	tellsTitleBg_l:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
	tellsTitleBg_l:SetTexCoord(0.21, 0.31, 0, 0.63)
	tellsTitleBg_l:SetPoint("RIGHT", tellsTitleBg, "LEFT")
	tellsTitleBg_l:SetWidth(30)
	tellsTitleBg_l:SetHeight(40)

	-- Create the title background right edge
	local tellsTitleBg_r = tellsFrame:CreateTexture(nil, "OVERLAY")
	tellsTitleBg_r:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
	tellsTitleBg_r:SetTexCoord(0.67, 0.77, 0, 0.63)
	tellsTitleBg_r:SetPoint("LEFT", tellsTitleBg, "RIGHT")
	tellsTitleBg_r:SetWidth(30)
	tellsTitleBg_r:SetHeight(40)
	
	-- Create the scrollingTable
	tellsTable = ScrollingTable:CreateST({
		{
			["name"] = "Name",
			["width"] = 90,
			["align"] = "LEFT",
			["color"] = { ["r"] = 1.0, ["g"] = 1.0, ["b"] = 1.0, ["a"] = 1.0 },
		},
		{
			["name"] = "Rank",
			["width"] = 60,
			["align"] = "LEFT",
			["color"] = { ["r"] = 1.0, ["g"] = 1.0, ["b"] = 1.0, ["a"] = 1.0 },
		},
		{
			["name"] = "Bid",
			["width"] = 40,
			["align"] = "LEFT",
			["color"] = { ["r"] = 1.0, ["g"] = 1.0, ["b"] = 1.0, ["a"] = 1.0 },
		},
		{
			["name"] = "Roll",
			["width"] = 40,
			["align"] = "LEFT",
			["color"] = { ["r"] = 1.0, ["g"] = 1.0, ["b"] = 1.0, ["a"] = 1.0 },
		},
		{
			["name"] = "Flags",
			["width"] = 40,
			["align"] = "LEFT",
			["color"] = { ["r"] = 1.0, ["g"] = 1.0, ["b"] = 1.0, ["a"] = 1.0 },
		},
	}, 6, nil, {["r"] = 0, ["g"] = 1, ["b"] = 0, ["a"] = 0.3}, tellsFrame);
	tellsTable:EnableSelection(true);
	tellsTable.frame:SetPoint("TOP", tellsTitleBg, "BOTTOM", 0, -10);
	tellsTable.frame:SetScale(1.1);
	
	-- Create the flag count mouseover frames
	local flagMouseovers = {};
	for i=1,6 do
		flagMouseovers[i] = CreateFrame("frame", tellsFrame:GetName().."STFlagOverlay"..tostring(i), tellsTable.frame)
		flagMouseovers[i]:SetWidth(66)
		flagMouseovers[i]:SetHeight(14.5)
		flagMouseovers[i]:SetFrameLevel(flagMouseovers[i]:GetFrameLevel() + 1);
		if i == 1 then
			flagMouseovers[i]:SetPoint("TOPRIGHT", tellsTable.frame, "TOPRIGHT", -3, -5);
		else
			flagMouseovers[i]:SetPoint("TOP", flagMouseovers[i-1], "BOTTOM", 0, -1);
		end
		
		flagMouseovers[i]:SetScript("OnEnter", function(self)
			local num = tonumber(string.match(self:GetName(), "%d$"));
			if tellsInProgress and table_items[tellsInProgress].tells[num] and (table_items[tellsInProgress].tells[num][5] or 0) > 0 then
				GameTooltip:SetOwner(self, "ANCHOR_CURSOR");
				local player = table_items[tellsInProgress]["tells"][num][1];
				local currentServerTime = GetCurrentServerTime();
				
				GameTooltip:AddLine("Possible MS items won this raid: \n");
				
				for j=#table_itemHistory,1,-1 do
					if currentServerTime-table_itemHistory[j].time <= 60*60*12 then
						if table_itemHistory[j].winner == player and table_itemHistory[j].bid ~= 20 then
							-- Calculate and format time elapsed
							local eSecs = currentServerTime-table_itemHistory[j].time;
							local eMins = math.ceil(eSecs/60);
							local eHrs  = math.floor(eMins/60);
							eMins       = eMins - 60*eHrs;
							local eStr = eMins.."m ago";
							if eHrs > 0 then
								eStr = eHrs .. "h" .. eStr;
							end
							eStr = "~" .. eStr;
							
							GameTooltip:AddDoubleLine(ItemLinkAssemble(table_itemHistory[j].itemString), eStr);
							GameTooltip:AddLine("  - Cost: " .. table_itemHistory[j].bid .. " DKP");
						else
							debug("Entry is not from the appropriate player.", 1);
						end
					else
						break;
					end
				end
				
				GameTooltip:Show();
			end
		end);
		flagMouseovers[i]:SetScript("OnLeave", function()
			GameTooltip:Hide();
		end);
		
		flagMouseovers[i]:SetBackdrop({
			bgFile = "Interface/Tooltips/UI-Tooltip-Background",
			tile = true, tileSize = 32,
		});
		flagMouseovers[i]:SetBackdropColor(1, 1, 1, 0);
	end
	
	-- Create the Tell Window Award button
	tellsFrameAwardButton = CreateFrame("Button", tellsFrame:GetName().."AwardButton", tellsFrame, "UIPanelButtonTemplate")
	tellsFrameAwardButton:SetPoint("BOTTOMLEFT", 15, 15)
	tellsFrameAwardButton:SetHeight(20)
	tellsFrameAwardButton:SetWidth(154)
	tellsFrameAwardButton:SetText("Award Item")
	tellsFrameAwardButton:SetScript("OnClick", function(frame)
		local selection = tellsTable:GetSelection();
		if selection and tellsInProgress then
			-- Send an addon message for those with the addon
			local cST = GetCurrentServerTime();
			FALoot:sendMessage(ADDON_MSG_PREFIX, {
				["itemWinner"] = {
					["itemString"] = tellsInProgress,
					["winner"] = table_items[tellsInProgress]["tells"][selection][1],
					["bid"] = table_items[tellsInProgress]["tells"][selection][3],
					["time"] = cST,
				},
			}, "RAID");
			
			-- Calling the next function fucks up the value for some reason I don't understand so lets save a copy here
			local tellsInProgressCopy = tellsInProgress;
			
			FALoot:itemAddWinner(tellsInProgress, table_items[tellsInProgress]["tells"][selection][1], table_items[tellsInProgress]["tells"][selection][3], cST);
			
			-- Restore the copy
			tellsInProgress = tellsInProgressCopy;
			
			-- Announce winner and bid amount to aspects chat
			local channels, channelNum = {GetChannelList()};
			for i=1,#channels do
				if string.lower(channels[i]) == "aspects" then
					channelNum = channels[i-1];
					break;
				end
			end
			
			if channelNum then
				local link = table_items[tellsInProgress]["itemLink"];
				local winner = string.match(table_items[tellsInProgress]["tells"][selection][1], "^(.-)%-.+");
				local bid = table_items[tellsInProgress]["tells"][selection][3];
				SendChatMessage(link.." "..winner.." "..bid, "CHANNEL", nil, channelNum);
			end
			
			-- Send a chat message with the winner for those that don't have the addon
			local winnerNoRealm = string.match(table_items[tellsInProgress]["tells"][selection][1], "^(.-)%-.+");
			SendChatMessage(table_items[tellsInProgress]["itemLink"].." "..winnerNoRealm, "RAID");
			
			table.remove(table_items[tellsInProgress]["tells"], selection);
		end
	end);
	
	-- Create the Tell Window Action button
	tellsFrameActionButton = CreateFrame("Button", tellsFrame:GetName().."ActionButton", tellsFrame, "UIPanelButtonTemplate")
	tellsFrameActionButton:SetPoint("BOTTOMRIGHT", -15, 15)
	tellsFrameActionButton:SetHeight(20)
	tellsFrameActionButton:SetWidth(154)
	tellsFrameActionButton:SetText("Lower to 20")
	tellsFrameActionButton:SetScript("OnClick", function(frame)
		--frame:GetParent():Hide();
	end);

	-- Create the "Take Tells" button
	tellsButton = CreateFrame("Button", frame:GetName().."TellsButton", frame, "UIPanelButtonTemplate");
	tellsButton:SetScript("OnClick", function(self, event)
		local id = scrollingTable:GetSelection()
		local j = 0;
		for i, v in pairs(table_items) do
			j = j + 1;
			if j == id then
				-- We've figured out the item string of the corresponding item (i), so now let's ask for permission to post it.
				FALoot:itemRequestTakeTells(i);
				-- While we're waiting for a request to our response, let's make sure the user can't take tells on any more items.
				FALoot:onTableSelect(scrollingTable:GetSelection());
				break;
			end
		end
	end)
	tellsButton:SetPoint("BOTTOM", bidButton, "TOP");
	tellsButton:SetHeight(20);
	tellsButton:SetWidth(80);
	tellsButton:SetText("Take Tells");
	tellsButton:SetFrameLevel(scrollingTable.frame:GetFrameLevel()+1);
	tellsButton:Disable();
	tellsButton:Hide(); -- hide by default, we can reshow it later if we need to
	
	foodFrame = CreateFrame("Frame", "FALootFoodFrame", UIParent);
	foodFrame:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = { left = 8, right = 8, top = 8, bottom = 8 }
	});
	foodFrame:SetBackdropColor(0, 1, 0, 0.5);
	foodFrame:Hide();
	foodFrame:SetScript("OnShow", function()
		if IsInRaid() then
			FALoot:sendMessage(ADDON_MSG_PREFIX, {
				["foodTrackOn"] = true,
			}, "RAID");
			debug("Food tracking enabled.", 1);
		end
	end);
	foodFrame:SetScript("OnHide", function()
		if IsInRaid() then
			FALoot:sendMessage(ADDON_MSG_PREFIX, {
				["foodTrackOff"] = true,
			}, "RAID");
		end
		debug("Food tracking disabled.", 1);
	end);
	foodFrame:SetWidth(280);
	foodFrame:SetHeight(200);
	foodFrame:SetPoint("CENTER");
	foodFrame:SetMovable(true);
	foodFrameGraph = libGraph:CreateGraphPieChart("FALootFoodFrameChart", foodFrame, "LEFT", "LEFT", 15, 0, 170, 170);
	
	foodFrameGraph:AddPie(2/25*100, {0, 1, 0});
	foodFrameGraph:AddPie(5/25*100, {1/2, 1, 0});
	foodFrameGraph:AddPie(12/25*100, {1, 1, 0});
	foodFrameGraph:AddPie(4/25*100, {1, 2/3, 0});
	foodFrameGraph:CompletePie({1/5, 1/5, 1/5});
	
	for i=5,-1,-1 do
		local key = CreateFrame("Frame", "FALootFoodFrameColor"..(-i+6), foodFrame);
		key:SetWidth(19);
		key:SetHeight(19);
		if #foodColorKey > 0 then
			key:SetPoint("TOP", foodColorKey[#foodColorKey][1], "BOTTOM", 0, -3);
		else
			key:SetPoint("CENTER", foodFrame, "TOPRIGHT", -60, -32);
		end
		key:SetBackdrop({
			bgFile = "Interface/Tooltips/UI-Tooltip-Background",
			tile = true, tileSize = 32,
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			insets = { left = 1, right = 1, top = 1, bottom = 1 }, edgeSize = 1
		});
		if i == 5 then
			key:SetBackdropColor(0, 1, 0, 1);
		elseif i == 4 then
			key:SetBackdropColor(1/2, 1, 0, 1);
		elseif i == 3 then
			key:SetBackdropColor(1, 1, 0, 1);
		elseif i == 2 then
			key:SetBackdropColor(1, 2/3, 0, 1);
		elseif i == 1 then
			key:SetBackdropColor(1, 1/3, 0, 1);
		elseif i == 0 then
			key:SetBackdropColor(1, 0, 0, 1);
		elseif i == -1 then
			key:SetBackdropColor(1/5, 1/5, 1/5, 1);
		end
		
		-- Create left text
		local leftText = key:CreateFontString(key:GetName().."LeftText", "OVERLAY", "GameFontNormal")
		leftText:SetPoint("RIGHT", key, "LEFT", -4, 0)
		if i >= 0 then
			leftText:SetText(i);
		else
			leftText:SetText("?");
		end
		
		-- Create right text
		local rightText = key:CreateFontString(key:GetName().."RightText", "OVERLAY", "GameFontNormal")
		rightText:SetPoint("LEFT", key, "RIGHT", 4, 0)
		
		table.insert(foodColorKey, {key, leftText, rightText});
	end
	
	local foodFrameClose = CreateFrame("Button", foodFrame:GetName().."Button", foodFrame, "UIPanelButtonTemplate");
	foodFrameClose:SetPoint("RIGHT", foodFrame, "BOTTOMRIGHT", -20, 2);
	foodFrameClose:SetHeight(20);
	foodFrameClose:SetWidth(80);
	foodFrameClose:SetText("Close");
	foodFrameClose:SetScript("OnClick", function(self)
		self:GetParent():Hide();
	end);
	-- Fix edges of parent clipping over button
	foodFrameClose:SetFrameLevel(foodFrameClose:GetFrameLevel()+1);
	
	foodFrameMsg = CreateFrame("Button", foodFrame:GetName().."Button2", foodFrame, "UIPanelButtonTemplate");
	foodFrameMsg:SetPoint("LEFT", foodFrame, "BOTTOMLEFT", 20, 2);
	foodFrameMsg:SetHeight(20);
	foodFrameMsg:SetWidth(80);
	foodFrameMsg:SetText("Reminder");
	foodFrameMsg:SetScript("OnClick", function(self)
		if UnitIsRaidOfficer("player") or UnitIsGroupLeader("player") then
			for i,v in pairs(raidFoodCount) do
				if v < 5 then
					SendChatMessage("Get your damn food!", "WHISPER", nil, i);
				end
			end
		else
			debug("You must have raid assist to do that!");
		end
	end);
	-- Fix edges of parent clipping over button
	foodFrameMsg:SetFrameLevel(foodFrameMsg:GetFrameLevel()+1);
	foodFrameMsg:Hide();
	
	-- make some fancy-ass title that takes way too much time to code
	local foodTitleBg = foodFrame:CreateTexture(foodFrame:GetName().."TitleBackground", "OVERLAY")
	foodTitleBg:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
	foodTitleBg:SetTexCoord(0.31, 0.67, 0, 0.63)
	foodTitleBg:SetPoint("TOP", 0, 12)
	foodTitleBg:SetHeight(40)

	-- Create the title frame
	local foodTitle = CreateFrame("Frame", foodFrame:GetName().."TitleMover", foodFrame)
	foodTitle:EnableMouse(true)
	foodTitle:SetScript("OnMouseDown", function(self)
		self:GetParent():StartMoving()
	end)
	foodTitle:SetScript("OnMouseUp", function(self)
		self:GetParent():StopMovingOrSizing()
	end)
	foodTitle:SetAllPoints(foodTitleBg)

	-- Create the text of the title
	local foodTitletext = foodTitle:CreateFontString(foodFrame:GetName().."TitleText", "OVERLAY", "GameFontNormal")
	foodTitletext:SetPoint("TOP", foodTitleBg, "TOP", 0, -14)
	foodTitletext:SetText("Food Count");
	
	foodTitleBg:SetWidth((foodTitletext:GetWidth() or 0) + 10)

	-- Create the title background left edge
	local foodTitleBg_l = foodFrame:CreateTexture(foodFrame:GetName().."TitleEdgeLeft", "OVERLAY")
	foodTitleBg_l:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
	foodTitleBg_l:SetTexCoord(0.21, 0.31, 0, 0.63)
	foodTitleBg_l:SetPoint("RIGHT", foodTitleBg, "LEFT")
	foodTitleBg_l:SetWidth(30)
	foodTitleBg_l:SetHeight(40)

	-- Create the title background right edge
	local foodTitleBg_r = foodFrame:CreateTexture(foodFrame:GetName().."TitleEdgeRight", "OVERLAY")
	foodTitleBg_r:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
	foodTitleBg_r:SetTexCoord(0.67, 0.77, 0, 0.63)
	foodTitleBg_r:SetPoint("LEFT", foodTitleBg, "RIGHT")
	foodTitleBg_r:SetWidth(30)
	foodTitleBg_r:SetHeight(40)
	
	debugFrame = CreateFrame("Frame", "FALootDebugFrame", UIParent);
	debugFrame:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = { left = 8, right = 8, top = 8, bottom = 8 }
	});
	debugFrame:SetBackdropColor(0, 1, 0, 0.5);
	debugFrame:SetScript("OnShow", nil);
	debugFrame:SetScript("OnHide", nil);
	debugFrame:SetWidth(400);
	debugFrame:SetHeight(250);
	debugFrame:SetPoint("CENTER");
	debugFrame:SetMovable(true);
	debugFrame:Hide();
	
	local debugFrameRefresh = CreateFrame("Button", debugFrame:GetName().."RefreshButton", debugFrame, "UIPanelButtonTemplate");
	debugFrameRefresh:SetPoint("CENTER", debugFrame, "BOTTOM", -55, 2);
	debugFrameRefresh:SetHeight(20);
	debugFrameRefresh:SetWidth(100);
	debugFrameRefresh:SetText("Refresh");
	
	local debugFrameClose = CreateFrame("Button", debugFrame:GetName().."CloseButton", debugFrame, "UIPanelButtonTemplate");
	debugFrameClose:SetPoint("CENTER", debugFrame, "BOTTOM", 55, 2);
	debugFrameClose:SetHeight(20);
	debugFrameClose:SetWidth(100);
	debugFrameClose:SetText("Close");
	debugFrameClose:SetScript("OnClick", function(self)
		self:GetParent():Hide();
	end);
	
	-- make some fancy-ass title that takes way too much time to code
	local debugTitleBg = debugFrame:CreateTexture(debugFrame:GetName().."TitleBackground", "OVERLAY")
	debugTitleBg:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
	debugTitleBg:SetTexCoord(0.31, 0.67, 0, 0.63)
	debugTitleBg:SetPoint("TOP", 0, 12)
	debugTitleBg:SetHeight(40)

	-- Create the title frame
	local debugTitle = CreateFrame("Frame", debugFrame:GetName().."TitleMover", debugFrame)
	debugTitle:EnableMouse(true)
	debugTitle:SetScript("OnMouseDown", function(self)
		self:GetParent():StartMoving()
	end)
	debugTitle:SetScript("OnMouseUp", function(self)
		self:GetParent():StopMovingOrSizing()
	end)
	debugTitle:SetAllPoints(debugTitleBg)

	-- Create the text of the title
	local debugTitletext = debugTitle:CreateFontString(debugFrame:GetName().."TitleText", "OVERLAY", "GameFontNormal")
	debugTitletext:SetPoint("TOP", debugTitleBg, "TOP", 0, -14)
	debugTitletext:SetText("Debug Info");
	
	debugTitleBg:SetWidth((debugTitletext:GetWidth() or 0) + 10)

	-- Create the title background left edge
	local debugTitleBg_l = debugFrame:CreateTexture(debugFrame:GetName().."TitleEdgeLeft", "OVERLAY")
	debugTitleBg_l:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
	debugTitleBg_l:SetTexCoord(0.21, 0.31, 0, 0.63)
	debugTitleBg_l:SetPoint("RIGHT", debugTitleBg, "LEFT")
	debugTitleBg_l:SetWidth(30)
	debugTitleBg_l:SetHeight(40)

	-- Create the title background right edge
	local debugTitleBg_r = debugFrame:CreateTexture(debugFrame:GetName().."TitleEdgeRight", "OVERLAY")
	debugTitleBg_r:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
	debugTitleBg_r:SetTexCoord(0.67, 0.77, 0, 0.63)
	debugTitleBg_r:SetPoint("LEFT", debugTitleBg, "RIGHT")
	debugTitleBg_r:SetWidth(30)
	debugTitleBg_r:SetHeight(40)
	
	debugTitleBg:SetWidth((debugTitletext:GetWidth() or 0) + 10)
	
	-- Create description text
	local debugDescText = debugFrame:CreateFontString(debugFrame:GetName().."DescText", "OVERLAY", "GameFontNormal")
	debugDescText:SetPoint("TOPLEFT", debugFrame, "TOPLEFT", 15, -20)
	debugDescText:SetText("Please copy and paste the text below to pastebin.com and provide the resulting link to Pawkets.");
	debugDescText:SetWidth(debugFrame:GetWidth()-30);
	debugDescText:SetJustifyH("LEFT");
	
	-- Create scroll frame for editbox
	local debugScroll = CreateFrame("ScrollFrame", debugFrame:GetName().."Scroll", debugFrame, "UIPanelScrollFrameTemplate");
	debugScroll:SetPoint("LEFT", debugFrame, "LEFT", 16, 0);
	debugScroll:SetPoint("RIGHT", debugFrame, "RIGHT", -16-25, 0);
	debugScroll:SetPoint("TOP", debugDescText, "BOTTOM", 0, -6);
	debugScroll:SetPoint("BOTTOM", debugFrameClose, "TOP", 0, 6);
	debugScroll:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 32, edgeSize = 8,
		insets = { left = 0, right = 0, top = 0, bottom = 0 }
	});
	
	-- Create editbox
	debugEditBox = CreateFrame("EditBox", debugFrame:GetName().."EditBox");
	debugEditBox:SetWidth(debugScroll:GetWidth());
	debugEditBox:SetHeight(debugScroll:GetHeight());
	debugEditBox:SetTextInsets(4, 4, 4, 4);
	debugEditBox:SetScript("OnTextChanged", function(self)
		self:SetText(formatDebugData());
	end);
	debugEditBox:SetScript("OnEscapePressed", function(self)
		debugFrame:Hide();
	end);
	debugEditBox:SetFontObject("GameFontNormal");
	debugEditBox:SetAutoFocus(false);
	debugEditBox:SetMultiLine(true);
	debugEditBox:Enable();
	
	debugScroll:SetScrollChild(debugEditBox);
	
	debugFrameRefresh:SetScript("OnClick", function(self)
		debugEditBox:SetText(formatDebugData());
	end);
	
	debugFrame:SetScript("OnShow", function()
		debugEditBox:SetText(formatDebugData());
	end);
end

function FALoot:isThunderforged(iLevel)
	return iLevel == 572 or iLevel == 559 or iLevel == 541 or iLevel == 528;
end

function FALoot:generateIcons()
	local lasticon = nil -- reference value for anchoring to the most recently constructed icon
	local firsticon = nil -- reference value for anchoring the first constructed icon
	local k = 0 -- this variable contains the number of the icon we're currently constructing, necessary because we need to be able to create multiple icons per entry in the table
	for i=1,maxIcons do -- loop through the table of icons and reset everything
		table_icons[i]:Hide()
		table_icons[i]:ClearAllPoints()
		table_icons[i]:SetBackdrop({
				bgFile = nil,
		})
		table_icons[i]:SetScript("OnEnter", nil)
		table_icons[i]:SetScript("OnLeave", nil)
	end
	for i, v in pairs(table_items) do -- loop through each row of data
		for j=1,v["quantity"] do
			if k < #table_icons then -- if we're constructing an icon number that's higher than what we're setup to display then just skip it
				k = k + 1 -- increment k by 1 before starting to construct
				table_icons[k]:SetBackdrop({ -- set the texture of the icon
					bgFile = v["texture"],
				})
				table_icons[k]:SetScript("OnEnter", function(self, button) -- set code that triggers on mouse enter
					-- store what row was selected so we can restore it later
					iconSelect = scrollingTable:GetSelection() or 0;
					
					-- retrieve the row id that corresponds to the icon we're mousedover
					local row = 0;
					for l, w in pairs(table_items) do
						row = row + 1;
						if i == l then
							-- select the row that correlates to the icon
							scrollingTable:SetSelection(row);
							break;
						end
					end
					
					--tooltip stuff
					GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
					GameTooltip:SetHyperlink(v["tooltipItemLink"])
					GameTooltip:Show()
				end)
				table_icons[k]:SetScript("OnLeave", function(self, button) -- set code that triggers on mouse exit
					-- restore the row that was selected before we mousedover this icon
					scrollingTable:SetSelection(iconSelect);
					iconSelect = nil;
					
					GameTooltip:Hide()
				end)
				table_icons[k]:SetScript("OnMouseUp", function(self, button) -- set code that triggers on clicks
					if button == "LeftButton" then -- left click: Selects the clicked row
						if IsModifiedClick("CHATLINK") then
							ChatEdit_InsertLink(v["itemLink"])
						elseif IsModifiedClick("DRESSUP") then
							DressUpItemLink(v["itemLink"])
						else
							-- retrieve the row id that corresponds to the icon we're mousedover
							local row = 0;
							for l, w in pairs(table_items) do
								row = row + 1;
								if i == l then
									-- set iconSelect so that after the user finishes mousing over icons
									-- the row corresponding to this one gets selected
									iconSelect = row;
									break;
								end
							end
						end
					elseif button == "RightButton" then -- right click: Ends the item, for everyone in raid if you have assist, otherwise only locally.
						endPrompt = coroutine.create( function()
							debug("Ending item "..v["itemLink"]..".", 1);
							if UnitIsGroupAssistant("PLAYER") or UnitIsGroupLeader("PLAYER") then
								FALoot:sendMessage(ADDON_MSG_PREFIX, {
									["reqVersion"] = ADDON_MVERSION, 
									["end"] = i,
								}, "RAID")
							end
							FALoot:itemEnd(i)
						end)
						if UnitIsGroupAssistant("PLAYER") or UnitIsGroupLeader("PLAYER") then
							StaticPopupDialogs["FALOOT_END"]["text"] = "Are you sure you want to manually end "..v["itemLink"].." for all players in the raid?"
						else
							StaticPopupDialogs["FALOOT_END"]["text"] = "Are you sure you want to manually end "..v["itemLink"].."?"
						end
						StaticPopup_Show("FALOOT_END")
					end
				end)
				if lasticon then -- if this isn't the first icon then anchor it to the previous icon
					table_icons[k]:SetPoint("LEFT", lasticon, "RIGHT", 1, 0)
				end
				table_icons[k]:Show() -- show the icon we just constructed
				lasticon = table_icons[k] -- set the icon we just constructed as the most recently constructed icon
			end
		end
	end
	table_icons[1]:SetPoint("LEFT", iconFrame, "LEFT", (501-(k*(40+1)))/2, 0) -- anchor the first icon in the row so that the row is centered in the window
end

--[[ =======================================================
	Slash Commands
     ======================================================= --]]
	
SLASH_RT1 = "/rt";
SLASH_FALOOT1 = "/faloot";
SLASH_FA1 = "/fa";
local function slashparse(msg, editbox)
	local msgLower = string.lower(msg);
	if msg == "" then
		frame:Show();
		return;
	elseif string.match(msg, "^dump .+") then
		msg = string.match(msg, "^dump (.+)");
		if msg == "table_items" then
			debug(table_items);
		elseif msg == "table_itemQuery" then
			debug(table_itemQuery);
		elseif msg == "table_itemHistory" then
			debug(table_itemHistory);
		elseif msg == "hasBeenLooted" then
			debug(hasBeenLooted);
		elseif msg == "tellsTable" and tellsInProgress then
			debug(table_items[tellsInProgress].tells);
		end
		return;
	elseif string.match(msg, "^debug %d") then
		debugOn = tonumber(string.match(msg, "^debug (%d+)"));
		if debugOn > 0 then
			debug("Debug is now ON ("..debugOn..").");
		else
			debug("Debug is now OFF.");
		end
		
		FALoot:setLeaderUIVisibility();
		return;
	elseif msgLower == "debuginfo" then
		debugFrame:Show();
		debugEditBox:SetText(formatDebugData());
	elseif msgLower == "who" or msgLower == "vc" or msgLower == "versioncheck" then
		FALoot:sendMessage(ADDON_MSG_PREFIX, {
			["who"] = "query",
		}, "GUILD");
		return;
	elseif msgLower == "food" then
		if IsInRaid() or debugOn > 0 then
			if foodFrame:IsShown() then
				debug("Food frame is already shown, doing nothing", 1);
				foodFrame:Hide();
			else
				debug("Showing food frame...", 1);
				foodFrame:Show();
			end
		else
			debug("You must be in a raid group to do that!");
		end
	elseif msgLower == "history sync" or msgLower == "history synchronize" then
		if IsInRaid() then
			FALoot:itemHistorySync(true);
		else
			debug("You must be in a raid group to do that!");
		end
	elseif msgLower == "history clear" then
		table_itemHistory = {};
		debug("Your item history has been cleared.");
	else
		debug("The following are valid slash commands:");
		print("/fa debug <threshold> -- set debugging threshold");
		print("/fa who -- see who is running the addon and what version");
		print("/fa -- shows the loot window");
		print("/fa food -- displays # of food remaining for each raid member via a pie chart");
		print("/faroll <value> -- does a FA roll for the designated DKP amount");
	end
end
SlashCmdList["RT"] = slashparse
SlashCmdList["FALOOT"] = slashparse
SlashCmdList["FA"] = slashparse

SLASH_FAROLL1 = "/faroll"
local function FARoll(value)
	value = tonumber(value)
	if value % 2 ~= 0 then
		debug("You are not allowed to bid odd numbers or non-integers. Your bid has been rounded down to the nearest even integer.")
		value = math.floor(value)
		if value % 2 == 1 then
			value = value - 1
		end
	end
	if value > 30 then
		RandomRoll((value-30)/2, ((value-30)/2)+30)
	elseif value == 30 or value == 20 or value == 10 then
		RandomRoll(1, value)
	else
		debug("Invalid roll value!")
	end
end
SlashCmdList["FAROLL"] = FARoll

--[[ =======================================================
	Static Popup Dialogs
     ======================================================= --]]

StaticPopupDialogs["FALOOT_BID"] = {
	text = "How much would you like to bid?",
	button1 = "Bid",
	button2 = CANCEL,
	timeout = 0,
	whileDead = true,
	OnAccept = function(self)
		StaticDataSave(self.editBox:GetText())
		coroutine.resume(bidPrompt)
	end,
	OnShow = function(self)
		self.editBox:SetText("")
		self.editBox:SetScript("OnEnterPressed", function(self)
			StaticDataSave(self:GetText())
			coroutine.resume(bidPrompt)
			StaticPopup_Hide("FALOOT_BID");
		end);
		self.editBox:SetScript("OnEscapePressed", function(self)
			StaticPopup_Hide("FALOOT_BID");
		end);
	end,
	hasEditBox = true,
	preferredIndex = STATICPOPUPS_NUMDIALOGS,
}

StaticPopupDialogs["FALOOT_END"] = {
	text = "Are you sure you want to manually end this item for all players in the raid?",
	button1 = YES,
	button2 = CANCEL,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	OnAccept = function()
		coroutine.resume(endPrompt)
	end,
	enterClicksFirstButton = 1,
	preferredIndex = STATICPOPUPS_NUMDIALOGS,
}

--[[ =======================================================
	Main Functions
     ======================================================= --]]

function FALoot:itemTableUpdate()
	local t = {};
	
	for i, v in pairs(table_items) do
		-- create status string
		local statusString, statusColor = "", {["r"] = 1, ["g"] = 1, ["b"] = 1, ["a"] = 1};
		if v["status"] == "Ended" then
			statusString = v["status"];
			statusColor = {["r"] = 0.5, ["g"] = 0.5, ["b"] = 0.5, ["a"] = 1};
		elseif v["status"] == "Tells" then
			statusString = v["currentValue"].." ("..v["status"]..")";
			statusColor = {["r"] = 0, ["g"] = 1, ["b"] = 0, ["a"] = 1}
		elseif v["status"] == "Rolls" then
			statusString = v["currentValue"].." ("..v["status"]..")";
			statusColor = {["r"] = 1, ["g"] = 0, ["b"] = 0, ["a"] = 1};
		elseif not v["status"] or v["status"] == "" then
			statusString = v["currentValue"];
			statusColor = {["r"] = 0.5, ["g"] = 0.5, ["b"] = 0.5, ["a"] = 1};
		end
		
		-- create winner string
		local winnerString = "";
		for j, w in pairs(v["winners"]) do
			if winnerString ~= "" then
				winnerString = winnerString .. ", ";
			end
			local subString = "";
			for k=1,#w do
				if subString ~= "" then
					subString = subString .. " & ";
				end
				subString = subString .. w[k];
			end
			winnerString = winnerString .. subString .. " (" .. j .. ")";
		end
		
		-- insert assembled data into table
		table.insert(t, {
			["cols"] = {
				{
					["value"] = v["displayName"],
					["color"] = { ["r"] = 1.0, ["g"] = 1.0, ["b"] = 1.0, ["a"] = 1.0 },
				},
				{
					["value"] = statusString,
					["color"] = statusColor,
				},
				{
					["value"] = winnerString,
					["color"] = { ["r"] = 1.0, ["g"] = 1.0, ["b"] = 1.0, ["a"] = 1.0 },
				},
			},
			["color"] = { ["r"] = 1.0, ["g"] = 1.0, ["b"] = 1.0, ["a"] = 1.0 },
		})
	end

	scrollingTable:SetData(t, false)
	FALoot:generateIcons()
	
	if #t >= 8 then
		tellsButton:ClearAllPoints();
		tellsButton:SetPoint("TOP", bidButton, "BOTTOM");
	else
		tellsButton:ClearAllPoints();
		tellsButton:SetPoint("BOTTOM", bidButton, "TOP");
	end
end

function FALoot:tellsTableUpdate()
	if tellsInProgress and table_items[tellsInProgress] and table_items[tellsInProgress]["status"] ~= "Ended" then
		-- Set rank data
		GuildRoster()
		local showOffline = GetGuildRosterShowOffline();
		SetGuildRosterShowOffline(true);
		
		for i=1,#table_items[tellsInProgress]["tells"] do
			local name, rank = table_items[tellsInProgress]["tells"][i][1], table_items[tellsInProgress]["tells"][i][2];
			
			if not rank then
				table_items[tellsInProgress]["tells"][i][2] = "";
				for j=1,GetNumGuildMembers() do
					local currentName, rankName = GetGuildRosterInfo(j)
					if currentName == name then
						if rankName == "Aspect" or rankName == "Aspects" or rankName == "Dragon" or rankName == "Drake" then
							table_items[tellsInProgress]["tells"][i][2] = "Drake";
						elseif rankName == "Titan" or rankName == "Wyrm" then
							table_items[tellsInProgress]["tells"][i][2] = "Wyrm";
						end
						break;
					end
				end
			end
		end
		
		SetGuildRosterShowOffline(showOffline);
		
		-- Count flags
		local currentServerTime = GetCurrentServerTime();
		for i=1,#table_items[tellsInProgress].tells do
			local flags = 0;
			for j=#table_itemHistory,1,-1 do
				if currentServerTime-table_itemHistory[j].time <= 60*60*12 then
					if table_itemHistory[j].winner == table_items[tellsInProgress].tells[i][1] and table_itemHistory[j].bid ~= 20 then
						flags = flags + 1;
					end
				else
					break;
				end
			end
			table_items[tellsInProgress].tells[i][5] = flags;
		end
		
		-- Sort table
		table.sort(table_items[tellsInProgress]["tells"], function(a, b)
			if a[2] ~= b[2] then
				if a[2] == "Drake" then
					return true;
				elseif b[2] == "Drake" then
					return false;
				else
					if a[2] == "Whelp" then
						return true;
					else
						return false;
					end
				end
			elseif (tonumber(a[4]) or 0) ~= (tonumber(b[4]) or 0) then
				return (tonumber(a[4]) or 0) > (tonumber(b[4]) or 0);
			else				
				return a[3] > b[3];
			end
		end)
		
		-- Make a copy of the item entry so we can make our modifications without affecting the original
		local t = deepcopy(table_items[tellsInProgress]);
		
		--[[-- Purge any entries that are lower than what we want to display right now
		local limit = #t["tells"];
		for i=0,limit-1 do
			if t["tells"][limit-i][3] < t["currentValue"] then
				table.remove(t["tells"], limit-i);
			end
		end--]]
		
		-- Set name color
		for i=1,#t["tells"] do
			if not string.match(t["tells"][i][1], "|c%x+.|r") then
				local groupType;
				if IsInRaid() then
					groupType = "raid";
				else
					groupType = "party";
				end
				for j=1,GetNumGroupMembers() do
					if t["tells"][i][1] == UnitName(groupType..j, true) then
						local _, class = UnitClass(groupType..j);
						t["tells"][i][1] = "|c" .. RAID_CLASS_COLORS[class]["colorStr"] .. UnitName(groupType..j, false) .. "|r";
						break;
					end
				end
			end
		end
		
		local isCompetition;
		local numWinners = 0;
		for i, v in pairs(table_items[tellsInProgress]["winners"]) do
			numWinners = numWinners + #v;
		end
		
		-- Colorize bid values
		if #t["tells"] <= t["quantity"] - numWinners then -- If there's enough items for everyone then just set everything to green
			for i=1,#t["tells"] do
				t["tells"][i][3] = "|cFF00FF00" .. t["tells"][i][3] .. "|r";
			end
		else
			local tellsByRank, currentRank, j = {}, nil, 0;
			if t["currentValue"] > 10 then
				for i=1,#t["tells"] do
					if not currentRank or currentRank ~= t["tells"][i][2] then
						currentRank = t["tells"][i][2];
						j = j + 1;
						tellsByRank[j] = {};
					end
					table.insert(tellsByRank[j], t["tells"][i][1]);
				end
			else
				tellsByRank[1] = {}
				for i=1,#t["tells"] do
					table.insert(tellsByRank[1], t["tells"][i][1]);
				end
			end
			
			local itemsLeft = t["quantity"] - numWinners;
			for i=1,#tellsByRank do
				if #tellsByRank[i] <= itemsLeft then
					for j=1,#tellsByRank[i] do
						for k=1,#t["tells"] do
							if t["tells"][k][1] == tellsByRank[i][j] then
								t["tells"][k][3] = "|cFF00FF00" .. t["tells"][k][3] .. "|r"
								break;
							end
						end
					end
					
					itemsLeft = itemsLeft - #tellsByRank[i];
				elseif itemsLeft == 0 then
					for j=1,#tellsByRank[i] do
						for k=1,#t["tells"] do
							if t["tells"][k][1] == tellsByRank[i][j] then
								t["tells"][k][3] = "|cFFFF0000" .. t["tells"][k][3] .. "|r"
								break;
							end
						end
					end
				else
					-- Find the green threshold
					for j=1,#t["tells"] do
						if t["tells"][j][1] == tellsByRank[i][itemsLeft+1] then
							tellsGreenThreshold = t["tells"][j][3] + 60;
							break;
						end
					end
					
					-- Find the yellow threshold
					for j=1,#t["tells"] do
						if t["tells"][j][1] == tellsByRank[i][itemsLeft] then
							tellsYellowThreshold = max(t["tells"][j][3] - 58, t["currentValue"]);
							break;
						end
					end
					
					-- Colorize items based on green and yellow thresholds
					for j=1,#tellsByRank[i] do
						for k=1,#t["tells"] do
							if t["tells"][k][1] == tellsByRank[i][j] then
								tellsRankThreshold = t["tells"][k][2];
								if t["tells"][k][3] >= tellsGreenThreshold then
									t["tells"][k][3] = "|cFF00FF00" .. t["tells"][k][3] .. "|r";
								elseif t["tells"][k][3] >= tellsYellowThreshold then
									t["tells"][k][3] = "|cFFFFFF00" .. t["tells"][k][3] .. "|r";
									isCompetition = true;
								else
									t["tells"][k][3] = "|cFFFF0000" .. t["tells"][k][3] .. "|r";
								end
								break;
							end
						end
					end
					
					itemsLeft = 0;
				end
			end
		end
		
		tellsTable:SetData(t["tells"], true);
		
		-- Set button text and script
		if isCompetition and table_items[tellsInProgress]["tells"][1][3] >= t["currentValue"] then
			if tellsFrameActionButton:GetButtonState() ~= "DISABLED" then
				tellsFrameActionButton:Enable();
				tellsFrameActionButton:SetText("Roll!");
				tellsFrameActionButton:SetScript("OnClick", function(self)
					SendChatMessage(table_items[tellsInProgress]["itemLink"].." roll", "RAID");
					self:SetText("Waiting for rolls...");
					self:Disable();
				end)
			end
		elseif table_items[tellsInProgress]["currentValue"] > 10 then
			tellsFrameActionButton:Enable();
			tellsFrameActionButton:SetText("Lower to "..table_items[tellsInProgress]["currentValue"]-10);
			tellsFrameActionButton:SetScript("OnClick", function()
				SendChatMessage(table_items[tellsInProgress]["itemLink"].." "..table_items[tellsInProgress]["currentValue"]-10, "RAID");
			end)
		else
			tellsFrameActionButton:Enable();
			tellsFrameActionButton:SetText("Disenchant");
			tellsFrameActionButton:SetScript("OnClick", function()
				local channels, channelNum = {GetChannelList()};
				for i=1,#channels do
					if string.lower(channels[i]) == "aspects" then
						channelNum = channels[i-1];
						break;
					end
				end
				if channelNum then
					SendChatMessage(table_items[tellsInProgress]["itemLink"].." disenchant", "CHANNEL", nil, channelNum);
				end
			end)
		end
		
		tellsFrame:Show();
	else
		tellsInProgress = nil;
		tellsFrame:Hide();
	end
end

function FALoot:itemBid(itemString, bid)
	bid = tonumber(bid)
	debug("FALoot:itemBid("..itemString..", "..bid..")", 1)
	if not table_items[itemString] then
		debug("Item not found! Aborting.", 1);
		return;
	end
	
	table_items[itemString]["bid"] = bid;
	table_items[itemString]["bidStatus"] = "Bid";
	debug("FALoot:itemBid(): Queued bid for "..table_items[itemString]["itemLink"]..".", 1);
	
	FALoot:checkBids();
end

function FALoot:itemAddWinner(itemString, winner, bid, time)
	debug("itemAddWinner("..(itemString or "")..", "..(winner or "")..", "..(bid or "")..", "..(time or "")..")", 1);
	if not itemString or not winner or not bid or not time then
		debug("Input not valid, aborting.", 1);
		return;
	end
	if not table_items[itemString] then
		debug(itemString.." is not a valid active item!", 1);
		return;
	end
	
	local entry = table_items[itemString];
		
	-- check if the player was the winner of the item
	if winner == PLAYER_NAME then
		debug("The player won an item!", 1);
		LootWonAlertFrame_ShowAlert(entry["itemLink"], 1, LOOT_ROLL_TYPE_NEED, bid.." DKP");
	end
	
	-- create a table entry for that pricepoint
	entry["winners"][bid] = entry["winners"][bid] or {};
	
	-- insert this event into the winners table
	table.insert(entry["winners"][bid], winner);
	
	-- insert into item history
	table.insert(table_itemHistory, {
		["itemString"] = itemString,
		["winner"] = winner,
		["bid"] = bid,
		["time"] = time,
	});
	
	-- if # of winners >= item quantity then auto end the item
	local numWinners = 0;
	for j, v in pairs(entry["winners"]) do
		numWinners = numWinners + #v;
	end
	debug("numWinners = "..numWinners, 3);
	if numWinners >= entry["quantity"] then
		FALoot:itemEnd(itemString);
	end
end

function FALoot:itemEnd(itemString) -- itemLink or ID
	if table_items[itemString] then
		table_items[itemString]["status"] = "Ended";
		table_items[itemString]["expirationTime"] = GetTime();
		FALoot:itemTableUpdate();
		FALoot:generateStatusText();
		if itemString == tellsInProgress then
			FALoot:tellsTableUpdate();
		end
	end
end

function FALoot:itemRemove(itemString)
	table_items[itemString] = nil;
	FALoot:itemTableUpdate();
end

function FALoot:checkBids()
	for itemString, v in pairs(table_items) do
		if table_items[itemString]["bidStatus"] and table_items[itemString]["host"] and ((v["currentValue"] == 30 and v["bid"] >= 30) or v["currentValue"] == v["bid"]) then
			if v["bidStatus"] == "Bid" and v["status"] == "Tells" then
				SendChatMessage(tostring(v["bid"]), "WHISPER", nil, v["host"]);
				table_items[itemString]["bidStatus"] = "Roll";
				debug("FALoot:itemBid(): Bid and queued roll for "..table_items[itemString]["itemLink"]..".", 1);
			elseif v["bidStatus"] == "Roll" and v["status"] == "Rolls" then
				FARoll(v["bid"]);
				table_items[itemString]["bidStatus"] = nil;
				debug("FALoot:itemBid(): Rolled for "..table_items[itemString]["itemLink"]..".", 1);
			end
		end
	end
	FALoot:generateStatusText();
end

function FALoot:generateStatusText()
	local bidding, rolling, only = 0, 0;
	for itemString, v in pairs(table_items) do
		if table_items[itemString]["bidStatus"] and table_items[itemString]["status"] ~= "Ended" then
			only = itemString;
			if table_items[itemString]["bidStatus"] == "Bid" then
				bidding = bidding + 1;
			elseif table_items[itemString]["bidStatus"] == "Roll" then
				rolling = rolling + 1;
			end
		end
	end
	
	if bidding + rolling == 0 then
		statusText:SetText("");
	elseif bidding + rolling == 1 then
		local verb = "";
		if bidding > 0 then
			verb = "bid"
		else
			verb = "roll"
		end
		statusText:SetText("Waiting to " .. verb .. " on " .. table_items[only]["displayName"] .. ".")
	else
		if bidding > 0 and rolling > 0 then
			local plural1, plural2 = "", "";
			if bidding > 1 then
				plural1 = "s";
			end
			if rolling > 1 then
				plural2 = "s";
			end
			statusText:SetText("Waiting to bid on " .. bidding .. " item" .. plural1 .. " and roll on " .. rolling .. " item" .. plural2 .. ".");
		elseif bidding > 0 then
			statusText:SetText("Waiting to bid on " .. bidding .. " items.");
		else
			statusText:SetText("Waiting to roll on " .. rolling .. " items.");
		end
	end
end

function FALoot:setLeaderUIVisibility()
	-- enable/disable UI elements
	if UnitIsGroupAssistant("PLAYER") or UnitIsGroupLeader("PLAYER") or debugOn > 0 then
		tellsButton:Show();
		foodFrameMsg:Show();
	else
		tellsButton:Hide();
		foodFrameMsg:Hide();
	end
end

function FALoot:onTableSelect(id)
	local j = 0;
	for i, v in pairs(table_items) do
		j = j + 1;
		if j == id then
			if (not v["status"] or v["status"] == "") and not tellsInProgress then
				--debug("Status of entry #"..id..' is "'..(v["status"] or "")..'".', 1);
				tellsButton:Enable();
			else
				tellsButton:Disable();
			end
			break;
		end
	end
	bidButton:Enable();
end

function FALoot:onTableDeselect()
	--window:SetDisabled(true);
	if not tellsInProgress then
		tellsButton:Disable();
	end
	bidButton:Disable();
end

local function onUpdate(self,elapsed)
	local currentTime = GetTime() -- get the time and put it in a variable so we don't have to call it a billion times throughout this function
	
	--check if it's time to remove any expired items
	for i, v in pairs(table_items) do
		if v["expirationTime"] and v["expirationTime"] + expTime <= currentTime then
			debug(v["itemLink"].." has expired, removing.", 1);
			FALoot:itemRemove(i);
			oldSelectStatus = nil; -- clear stored select status to force button state refresh
		end
	end
	
	-- trigger select events
	local selectStatus;
	if iconSelect then
		if iconSelect > 0 then
			selectStatus = iconSelect;
		end
	else
		local realSelect = scrollingTable:GetSelection();
		if realSelect and realSelect > 0 then
			selectStatus = realSelect;
		end
	end
	if selectStatus ~= oldSelectStatus then
		--debug("New selectStatus value is "..(selectStatus or "nil")..".", 1);
		if selectStatus then
			FALoot:onTableSelect(selectStatus);
		else
			FALoot:onTableDeselect();
		end
		oldSelectStatus = selectStatus;
	end
	
	-- FIXME: not terribly efficient, but this isnt going to be running in combat so fuck it.
	if tellsInProgress and tellsTable then
		if not tellsTable:GetSelection() and tellsFrameAwardButton:GetText() == "Award Item" then
			tellsFrameAwardButton:Disable();
		else
			tellsFrameAwardButton:Enable();
		end
	end
	
	-- who stuff
	if table_who and table_who["time"] and table_who["time"]+1 <= currentTime then
		for i=1,#table_who do
			local s = table_who[i]..": "
			for j=1,#table_who[table_who[i]] do
				if j > 1 then
					s = s..", "
				end
				s = s..table_who[table_who[i]][j]
			end
			debug(s)
		end
		table_who = {}
	end
	
	-- Post request timer
	-- If we've been waiting more than postRequestMaxWait seconds for a response from the raid leader, then go ahead and post the item anyway.
	if postRequestTimer and currentTime - postRequestTimer >= postRequestMaxWait then
		debug(postRequestMaxWait .. " seconds have elapsed with no response from raid leader, posting item (" .. tellsInProgress .. ") anyway.", 1);
		FALoot:itemTakeTells(tellsInProgress);
		postRequestTimer = nil;
	end
	
	-- Item history sync
	if itemHistorySync.p1 and not itemHistorySync.p2 and currentTime-itemHistorySync.p1.time >= 3 then
		if itemHistorySync.p1[1] then
			table.sort(itemHistorySync.p1, function(a,b) return a[2]>b[2] end);
			debug("Sending historySyncStart command to "..itemHistorySync.p1[1][1]..".", 1);
			local success, reason = FALoot:sendMessage(ADDON_MSG_PREFIX, {
				["historySyncStart"] = itemHistorySync.full,
			}, "WHISPER", itemHistorySync.p1[1][1], nil, true);
			if success then
				itemHistorySync.p2 = {};
			else
				debug("Attempted to send historySyncStart, but "..reason.."! Aborting synchronization.", 1);
				itemHistorySync = {};
			end
		else
			debug("Synchronization complete: no more complete data is available.", 1);
			itemHistorySync = {};
		end
	elseif itemHistorySync.p2 and itemHistorySync.p2.time and currentTime-itemHistorySync.p2.time >= 5 then
		debug("Sync verifies have been open for 5 seconds, ending synchronization.", 1);
		if #itemHistorySync.p2 > 0 then
			debug("Deleted "..#itemHistorySync.p2.." unverified sync entries.", 1);
		end
		itemHistorySync = {};
	end
end

local ouframe = CreateFrame("frame")
ouframe:SetScript("OnUpdate", onUpdate)

function FALoot:parseChat(msg, author)
	debug("Parsing a chat message.", 2);
	debug("Msg: "..msg, 3);
	local rank;
	if debugOn == 0 then
		for i=1,40 do
			local name, currentRank = GetRaidRosterInfo(i)
			if name == author then
				rank = currentRank
				break
			end
		end
	end
	if debugOn > 0 or (rank and rank > 0) then
		local linkless, replaces = string.gsub(msg, HYPERLINK_PATTERN, "")
		if replaces == 1 then -- if the number of item links in the message is exactly 1 then we should process it
			local itemLink = string.match(msg, HYPERLINK_PATTERN); -- retrieve itemLink from the message
			local itemString = ItemLinkStrip(itemLink);
			msg = string.gsub(msg, "x%d+", ""); -- remove any "x2" or "x3"s from the string
			if not msg then
				return;
			end
			local value = string.match(msg, "]|h|r%s*(.+)"); -- take anything else after the link and any following spaces as the value value
			if not value then
				return;
			end
			value = string.gsub(value, "%s+", " "); -- replace any double spaces with a single space
			if not value then
				return;
			end
			value = string.lower(value);
			
			if table_items[itemString] then
				if not table_items[itemString]["host"] then
					table_items[itemString]["host"] = author;
				end
				
				if string.match(value, "roll") then
					table_items[itemString]["status"] = "Rolls";
				elseif string.match(value, "[321]0") then
					table_items[itemString]["currentValue"] = tonumber(string.match(value, "[321]0"));
					table_items[itemString]["status"] = "Tells";
				end
				
				FALoot:itemTableUpdate();
				FALoot:checkBids();
				if tellsInProgress and tellsInProgress == itemString then
					FALoot:tellsTableUpdate();
				end
			else
				debug("Hyperlink is not in item table.", 2);
			end
		else
			debug("Message does not have exactly 1 hyperlink.", 2);
			debug("linkless = "..linkless, 3);
			debug("replaces = "..replaces, 3);
		end
	else
		debug("Author is not of sufficient rank.", 1);
	end
end

function FALoot:parseWhisper(msg, author)
	debug("Parsing a whisper.", 2);
	if not table_items[tellsInProgress] then
		debug("Item in progress does not exist.", 1);
		tellsInProgress = nil;
		return;
	end
	local bid, spec;
	if string.match(msg, "^%s*%d+%s*$") then
		bid = string.match(msg, "^%s*(%d+)%s*$");
	elseif string.match(msg, "^%s*%d+%s[MmOo][Ss]%s*$") then
		bid, spec = string.match(msg, "^%s*(%d+)%s([MmOo][Ss])%s*$");
	elseif string.match(msg, "^%s*"..HYPERLINK_PATTERN.."%s?%d+$") then
		bid = string.match(msg, "^%s*"..HYPERLINK_PATTERN.."%s?(%d+)$");
	elseif string.match(msg, "^%d+%s?"..HYPERLINK_PATTERN.."$") then
		bid = string.match(msg, "^(%d+)%s?"..HYPERLINK_PATTERN.."$");
	elseif string.lower(msg) == "pass" then
		for i=1,#table_items[tellsInProgress]["tells"] do
			if table_items[tellsInProgress]["tells"][i][1] == author then
				table.remove(table_items[tellsInProgress]["tells"], i);
				FALoot:tellsTableUpdate();
				break;
			end
		end
		return;
	else
		return;
	end
	bid = tonumber(bid);
	
	local groupType, inGroup;
	if IsInRaid() then
		groupType = "raid";
	else
		groupType = "party";
	end
	for i=1,GetNumGroupMembers() do
		if UnitName(groupType..i, true) == author then
			inGroup = true;
			break;
		end
	end
	if not inGroup then
		return;
	end
	
	local bidUpdated;
	for i=1,#table_items[tellsInProgress]["tells"] do
		if table_items[tellsInProgress]["tells"][i][1] == author then
			table_items[tellsInProgress]["tells"][i][3] = bid;
			SendChatMessage("<FA Loot> Updated your bid for "..table_items[tellsInProgress]["itemLink"]..".", "WHISPER", nil, author);
			bidUpdated = true;
			break;
		end
	end
	if not bidUpdated then
		table.insert(table_items[tellsInProgress]["tells"], {author, nil, bid, ""});
		SendChatMessage("<FA Loot> Bid for "..table_items[tellsInProgress]["itemLink"].." accepted.", "WHISPER", nil, author);
	end
	FALoot:tellsTableUpdate();
end

function FALoot:parseRoll(msg, author)
	if table_items[tellsInProgress]["status"] ~= "Rolls" then
		return;
	end
	local author, rollResult, rollMin, rollMax = string.match(msg, "(.+) rolls (%d+) %((%d+)-(%d+)%)");
	
	-- Constrain name to Player-Realm format
	if not string.match(author, "-") then
		author = author .. "-" .. PLAYER_REALM;
	end
	
	-- Convert roll values to integers
	rollResult = tonumber(rollResult);
	rollMin = tonumber(rollMin);
	rollMax = tonumber(rollMax);
	
	for i=1,#table_items[tellsInProgress]["tells"] do
		if table_items[tellsInProgress]["tells"][i][1] == author then
			if table_items[tellsInProgress]["tells"][i][4] == "" and table_items[tellsInProgress]["tells"][i][3] >= table_items[tellsInProgress]["currentValue"] then
				if (table_items[tellsInProgress]["tells"][i][3] <= 30 and rollMin == 1 and rollMax == table_items[tellsInProgress]["tells"][i][3]) or (rollMin + rollMax == table_items[tellsInProgress]["tells"][i][3] and rollMax - rollMin == 30) then
					table_items[tellsInProgress]["tells"][i][4] = rollResult;
					FALoot:tellsTableUpdate();
				end
			end
			break;
		end
	end
end

function FALoot:setAutoLoot()
	local toggle, key = GetCVar("autoLootDefault"), GetModifiedClick("AUTOLOOTTOGGLE");
	debug("toggle = "..(toggle or "nil")..", key = "..(key or "nil"), 3);
	debug({FALoot:addonEnabled(true)}, 3);
	if autolootToggle and autolootKey then
		if FALoot:addonEnabled(true) then
			if not (toggle == "0" and key == "NONE") and not (autolootToggle == "0" and autolootKey == "NONE") then
				SetCVar("autoLootDefault", 0);
				SetModifiedClick("AUTOLOOTTOGGLE", "NONE");
				debug("Your autoloot has been disabled.");
			end
		else
			if key == "NONE" then
				debug("Your loot settings have been restored.");
				SetModifiedClick("AUTOLOOTTOGGLE", autolootKey);
				if toggle == "0" then
					SetCVar("autoLootDefault", autolootToggle);
				end
			end
		end
	end
end

function FALoot:itemHistorySync(full)
	if not full then
		full = false;
	end
	
	-- Detemine type of syncronization (Full or 12hr)
	local syncType = "historySyncRequest";
	if full then
		syncType = "historySyncRequestFull";
		debug("Initiating FULL item history sync...");
	else
		debug("Initiating item history sync...");
	end
	
	-- Count our current number of applicable entries
	local count = 0;
	if full then
		count = #table_itemHistory;
	else
		for i=#table_itemHistory,1,-1 do
			if GetCurrentServerTime()-table_itemHistory[i].time <= 60*60*12 then
				count = count + 1;
			else
				break;
			end
		end
	end
	debug("Self count is "..count..".", 1);
	
	-- Send a sync request with our count
	-- We'll recieve replies back from people who have more entries than us.
	FALoot:sendMessage(ADDON_MSG_PREFIX, {
		[syncType] = count;
	}, "RAID");
	
	-- Prepare our table to get ready for replies
	itemHistorySync = {
		["full"] = full,
		["p1"] = {
			["time"] = GetTime(),
		},
	};
	
	hasItemHistorySynced = true;
end

--[[ =======================================================
	Event Triggers
     ======================================================= --]]
	
local eventFrame, events = CreateFrame("Frame"), {}
function events:ADDON_LOADED(name)
	if name == ADDON_NAME then
		FALoot_options = FALoot_options or {};
		debugOn = FALoot_options["debugOn"] or debugOn;
		expTime = FALoot_options["expTime"] or expTime;
		cacheInterval = FALoot_options["cacheInterval"] or cacheInterval;
		autolootToggle = FALoot_options["autolootToggle"];
		autolootKey = FALoot_options["autolootKey"];
		
		table_itemHistory = FALoot_itemHistory or table_itemHistory;
		
		FALoot:RegisterComm(ADDON_MSG_PREFIX);
	end
end
function events:PLAYER_LOGIN()
	FALoot:createGUI();
	FALoot:setLeaderUIVisibility();

	if debugOn > 0 then
		itemAdd("96379:0")
		itemAdd("96740:0")
		itemAdd("96740:0")
		itemAdd("96373:0")
		itemAdd(ItemLinkStrip("|cffa335ee|Hitem:94775:4875:4609:0:0:0:65197:904070771:89:166:465|h[Beady-Eye Bracers]|h|r"))
		itemAdd(ItemLinkStrip("|cffa335ee|Hitem:98177:0:0:0:0:0:-356:1744046834:90:0:465|h[Tidesplitter Britches of the Windstorm]|h|r"))
		itemAdd("96384:0")
		--FALoot:parseChat("|cffa335ee|Hitem:96740:0:0:0:0:0:0:0:0:0:445|h[Sign of the Bloodied God]|h|r 30", PLAYER_NAME)
		--FALoot:itemRequestTakeTells("96740:0");
		--[[
		table_items[tellsInProgress]["tells"] = {
			{"Dyrimar", nil, 30, ""},
			{"Demonicblade", nil, 30, ""},
			{"Pawkets", nil, 10, ""},
			{"Xaerlun", "Wyrm", 10, ""},
			{"Unbrewable", nil, 10, ""},
		}
		--]]
		tellsFrame:Show();
		FALoot:tellsTableUpdate();
		FALoot:itemTableUpdate();
	else
		frame:Hide();
	end
end
function events:PLAYER_LOGOUT(...)
	FALoot_options = {
		["debugOn"]        = debugOn,
		["expTime"]        = expTime,
		["cacheInterval"]  = cacheInterval,
		["autolootToggle"] = autolootToggle,
		["autolootKey"]    = autolootKey,
	};
	FALoot_itemHistory = table_itemHistory;
end
function events:PLAYER_ENTERING_WORLD()
	FALoot:setAutoLoot();
	
	-- Register event for food tracking
	eventFrame:RegisterEvent("BAG_UPDATE");
	
	-- Force a food count get
	events:BAG_UPDATE();
end
function events:VARIABLES_LOADED()
	if autolootToggle and autolootKey then
		FALoot:setAutoLoot();
	else
		local toggle;
		if GetCVar("autoLootDefault") == "1" then
			toggle = "On";
		else
			toggle = "Off";
		end
		local key;
		if GetModifiedClick("AUTOLOOTTOGGLE") == "CTRL" then
			key = "Control";
		elseif GetModifiedClick("AUTOLOOTTOGGLE") == "SHIFT" then
			key = "Shift";
		elseif GetModifiedClick("AUTOLOOTTOGGLE") == "ALT" then
			key = "Alt";
		else
			key = "None";
		end
		StaticPopupDialogs["FALOOT_AUTOLOOT"] = {
			text = "Would you like to save these settings as your default loot settings?\n|cFFFFD100Auto Loot:|r "..toggle.."\n|cFFFFD100Auto Loot Key:|r "..key,
			button1 = YES,
			button2 = NO,
			timeout = 0,
			whileDead = true,
			hideOnEscape = true,
			enterClicksFirstButton = true,
			OnAccept = function(self)
				autolootKey = GetModifiedClick("AUTOLOOTTOGGLE");
				autolootToggle = GetCVar("autoLootDefault");
				FALoot:setAutoLoot();
			end,
			preferredIndex = STATICPOPUPS_NUMDIALOGS,
		}
		StaticPopup_Show("FALOOT_AUTOLOOT");
	end
end
function events:LOOT_OPENED(...)
	if not FALoot:addonEnabled() then
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
				
				local itemString = ItemLinkStrip(GetLootSlotLink(i));
				if itemString and FALoot:checkFilters(itemString) then
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
		debug("There is no loot on this mob!", 1);
		return;
	end
	
	-- add an item count for each GUID so that other clients may verify data integrity
	for i, v in pairs(loot) do
		loot[i]["checkSum"] = #v;
	end
	
	debug(loot, 2);
	
	-- check data integrity
	for i, v in pairs(loot) do
		if not (v["checkSum"] and v["checkSum"] == #v) then
			debug("Self assembled loot data failed the integrity check.");
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
		local itemString = ItemLinkStrip(itemLink);
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
function events:CHAT_MSG_SYSTEM(msg, author)
	if tellsInProgress and string.match(msg, ".+ rolls %d+ %(%d+-%d+%)") then
		FALoot:parseRoll(msg, author);
	end
end
function events:GROUP_JOINED()
	if IsInRaid() then
		FALoot:sendMessage(ADDON_MSG_PREFIX, {
			["update"] = ADDON_REVISION,
		}, "RAID", nil, "BULK")
	end
end
function events:GROUP_ROSTER_UPDATE()
	FALoot:setAutoLoot();
	FALoot:setLeaderUIVisibility();
	
	if not IsInRaid() then
		foodFrame:Hide();
	end
	if FALoot:addonEnabled() and GetNumGroupMembers() >= 25 and not hasItemHistorySynced then
		FALoot:itemHistorySync();
	elseif GetNumGroupMembers() == 0 then
		hasItemHistorySynced = false;
	end
end
function events:RAID_ROSTER_UPDATE()
	FALoot:setAutoLoot();
	FALoot:setLeaderUIVisibility();
	
	if not IsInRaid() then
		foodFrame:Hide();
	end
	if FALoot:addonEnabled() and GetNumGroupMembers() >= 25 and not hasItemHistorySynced then
		FALoot:itemHistorySync();
	elseif GetNumGroupMembers() == 0 then
		hasItemHistorySynced = false;
	end
end
function events:PLAYER_REGEN_ENABLED()
	if showAfterCombat then
		frame:Show()
		showAfterCombat = false
	end
end
function events:GET_ITEM_INFO_RECEIVED()
	local limit, itemAdded = #table_itemQuery;
	for i=limit,1,-1 do
		local result = itemAdd(table_itemQuery[i], true);
		if result and not itemAdded then
			itemAdded = result;
		end
	end
	if itemAdded then
		FALoot:itemTableUpdate();
	end
end

eventFrame:SetScript("OnEvent", function(self, event, ...)
	events[event](self, ...) -- call one of the functions above
end)
for k, v in pairs(events) do
	eventFrame:RegisterEvent(k) -- Register all events for which handlers have been defined
end

-- Events that will be manually registered at a later time.

function events:BAG_UPDATE()
	-- Registered on PLAYER_ENTERING WORLD to avoid
	-- processing the event a zillion times when the UI loads.
	debug("BAG_UPDATE triggered.", 2);
	local count = GetItemCount(foodItemId) or 0;
	if foodCount ~= count then
		local groupType, members = "raid", GetNumGroupMembers();
		if not IsInRaid() then
			groupType = "party";
			members = members - 1;
		end
		for name,v in pairs(foodUpdateTo) do
			local sent;
			for i=1,members do
				if UnitName(groupType..i, true) == name then
					if UnitIsConnected(groupType..i) then
						FALoot:sendMessage(ADDON_MSG_PREFIX, {
							["foodCount"] = count,
						}, "WHISPER", name)
						sent = true;
					end
					break
				end
			end
			if not sent then
				foodUpdateTo[name] = nil;
			end
		end
		foodCount = count;
		raidFoodCount[PLAYER_NAME] = foodCount;
		updatePieChart();
	end
end
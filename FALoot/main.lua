--[[
	Announce winners to aspects chat when session ends
	Confirm that the award item button actually does nothing when you have nobody selected
-]]

-- Declare strings
local ADDON_NAME = "FALoot";
local ADDON_VERSION_FULL = "v4.2g";
local ADDON_VERSION = string.gsub(ADDON_VERSION_FULL, "[^%d]", "");

local ADDON_COLOR = "FFF9CC30";
local ADDON_CHAT_HEADER  = "|c" .. ADDON_COLOR .. "FA Loot:|r ";
local ADDON_MSG_PREFIX = "FALoot";
local ADDON_DOWNLOAD_URL = "https://github.com/aggixx/FALoot";

local HYPERLINK_PATTERN = "\124c%x+\124Hitem:%d+:%d+:%d+:%d+:%d+:%d+:%-?%d+:%-?%d+:?%d*:?%d*:?%d*:?%d*:?%d*:?%d*:?%d*\124h.-\124h\124r";
-- |c COLOR    |H linkType : itemId : enchantId : gemId1 : gemId2 : gemId3 : gemId4 : suffixId : uniqueId  : linkLevel : reforgeId :      :      :      :      :      |h itemName            |h|r
-- |c %x+      |H item     : %d+    : %d+       : %d+    : %d+    : %d+    : %d+    : %-?%d+   : %-?%d+    :? %d*      :? %d*      :? %d* :? %d* :? %d* :? %d* :? %d* |h .-                  |h|r"
-- |c ffa335ee |H item     : 94775  : 4875      : 4609   : 0      : 0      : 0      : 65197    : 904070771 : 89        : 166       : 465                              |h [Beady-Eye Bracers] |h|r"
local THUNDERFORGED_COLOR = "FFFF8000";

-- Load the libraries
FALoot = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME);
LibStub("AceComm-3.0"):Embed(FALoot);

local ScrollingTable = LibStub("ScrollingTable");
local libSerialize = LibStub:GetLibrary("AceSerializer-3.0");
local libCompress = LibStub:GetLibrary("LibCompress");
local libEncode = libCompress:GetAddonEncodeTable();

-- Declare local variables

-- SavedVariables options
local debugOn = 0;		-- Debug threshold
local expTime = 15;		-- Amount of time before an ended item is removed from the window, in seconds.
local cacheInterval = 200;	-- Amount of time between attempts to check for item data, in milliseconds.
local autolootToggle;
local autolootKey;

-- Hard-coded options
local maxIcons = 11;

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

-- GUI elements
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

-- 300 food track
local foodItemId = 101618;
local foodCount = GetItemCount(itemId) or 0;
local raidFoodCount = {};
local foodUpdateTo = {};

--helper functions

local function debug(msg, verbosity)
	if (not verbosity or debugOn >= verbosity) then
		if type(msg) == "string" or type(msg) == "number" or type(msg) == nil then
			print(ADDON_CHAT_HEADER..(msg or "nil"));
		elseif type(msg) == "boolean" then
			print(ADDON_CHAT_HEADER..msg);
		elseif type(msg) == "table" then
			if not DevTools_Dump then
				LoadAddOn("Blizzard UI Debug Tools");
			end
			DevTools_Dump(msg);
		end
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

function string.levenshtein(str1, str2)
	local len1 = string.len(str1)
	local len2 = string.len(str2)
	local matrix = {}
	local cost = 0
	
        -- quick cut-offs to save time
	if (len1 == 0) then
		return len2
	elseif (len2 == 0) then
		return len1
	elseif (str1 == str2) then
		return 0
	end
	
        -- initialise the base matrix values
	for i = 0, len1, 1 do
		matrix[i] = {}
		matrix[i][0] = i
	end
	for j = 0, len2, 1 do
		matrix[0][j] = j
	end
	
        -- actual Levenshtein algorithm
	for i = 1, len1, 1 do
		for j = 1, len2, 1 do
			if (str1:byte(i) == str2:byte(j)) then
				cost = 0
			else
				cost = 1
			end
			
			matrix[i][j] = math.min(matrix[i-1][j] + 1, matrix[i][j-1] + 1, matrix[i-1][j-1] + cost)
		end
	end
	
        -- return the last value - this is the Levenshtein distance
	return matrix[len1][len2]
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
	SetGuildRosterShowOffline(false)
	local _, onlineguildies = GetNumGuildMembers()
	for j=1,onlineguildies do
		local jname = GetGuildRosterInfo(j)
		if jname == name then
			return true
		end
	end
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
	for i=1,40 do
		if UnitExists(groupType..i) then
			local iname = GetRaidRosterInfo(i)
			if isNameInGuild(iname) then
				numguildies = numguildies + 1
			end
			if not UnitIsConnected(groupType..i) then
				numOffline = numOffline + 1
			end
		end
	end
	if (numguildies/(GetNumGroupMembers()-numOffline) > threshold) then
		return true
	else
		return false
	end
end

local function isMainRaid()
	GuildRoster()
	local groupType
	if IsInRaid() then
		groupType = "raid"
	else
		groupType = "party"
	end
	local aspects, drakes = 0, 0;
	local showOffline = GetGuildRosterShowOffline();
	SetGuildRosterShowOffline(false);
	for i=1,40 do
		if UnitExists(groupType..i) then
			local name = GetRaidRosterInfo(i)
			local _, onlineguildies = GetNumGuildMembers()
			for j=1,onlineguildies do
				local _, rankName, rankIndex = GetGuildRosterInfo(j)
				if string.match(rankName, "Aspect") then
					aspects = aspects + 1
				elseif  string.match(rankName, "Drake") then
					drakes = drakes + 1
				end
			end
		end
	end
	SetGuildRosterShowOffline(showOffline);
	if aspects >= 2 and drakes >= 5 then
		return true
	else
		return false
	end
end

function FALoot:findClosestGroupMember(name)
	local closestMatch, closestMatchName, groupType, numGroupMembers = math.huge;
	if IsInRaid() then
		groupType = "raid";
		numGroupMembers = GetNumGroupMembers();
	elseif GetNumGroupMembers() > 0 then
		groupType = "party";
		numGroupMembers = GetNumGroupMembers() + 1;
	else
		groupType = "player"
		numGroupMembers = GetNumGroupMembers() + 1;
	end
	for i=1,numGroupMembers do
		local unitId;
		if UnitExists(groupType..i) then
			unitId = groupType..i;
		else
			unitId = "player"
		end
		local name2 = UnitName(unitId)
		local distance = string.levenshtein(name, name2:lower())
		if distance and distance < closestMatch then
			closestMatch = distance;
			closestMatchName = name2;
		end
	end
	return closestMatchName or name;
end

function FALoot:addonEnabled(overrideDebug)
	if not overrideDebug and debugOn > 0 then
		return 1
	end
	
	local _, instanceType = IsInInstance()
	
	if not isGuildGroup(0.60) then
		return nil, "not guild group"
	elseif not isMainRaid() then
		return nil, "not enough officers"
	elseif instanceType ~= "raid" then
		return nil, "wrong instance type"
	elseif not (GetRaidDifficultyID() == 4 or GetRaidDifficultyID() == 6) then
		return nil, "wrong instance difficulty"
	elseif GetNumGroupMembers() < 20 then
		return nil, "not enough group members"
	else
		return 1
	end
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
	local playerTotal = GetAverageItemLevel()
	if checkItemLevel and playerTotal - ilevel > 20 then -- if the item is more than 20 levels below the player
		debug("Item Level of "..itemLink.." is too low.", 1);
		return false
	end
	
	return true
end

local function StaticDataSave(data)
	promptBidValue = data
end

-- Main Code

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
	if not FALoot:checkFilters(itemString) then
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

function FALoot:sendMessage(prefix, text, distribution, target, prio, needsCompress)
	--serialize
	local serialized, msg = libSerialize:Serialize(text)
	if serialized then
		text = serialized
	else
		debug("Serialization of data failed!");
		return
	end
	--compress
	if needsCompress and false then -- disabled
		local compressed, msg = libCompress:CompressHuffman(text)
		if compressed then
			text = compressed
		else
			debug("Compression of data failed!");
			return
		end
	end
	--encode
	local encoded, msg = libEncode:Encode(text)
	if encoded then
		text = encoded
	else
		debug("Encoding of data failed!");
		return
	end
	
	FALoot:SendCommMessage(prefix, text, distribution, target, prio)
end

function FALoot:OnCommReceived(prefix, text, distribution, sender)
	if prefix ~= ADDON_MSG_PREFIX or not text then
		return;
	end
	debug("Recieved addon message.", 1);
	
	-- Decode the data
	local t = libEncode:Decode(text)
	
	-- Deserialize the data
	local success, deserialized = libSerialize:Deserialize(t)
	if success then
		t = deserialized
	else
		debug("Deserialization of data failed: "..t);
		return
	end
	
	if sender == UnitName("player") and not t["who"] then
		return;
	end
	
	debug(t, 2);
	
	if t["ADDON_VERSION"] and t["ADDON_VERSION"] ~= ADDON_VERSION then
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
			local version = t["who"]
			
			table_who = table_who or {}
			if version then
				debug("Who response recieved from "..sender..".", 1);
				if not table_who[version] then
					table_who[version] = {}
					table.insert(table_who, version)
				end
				table.insert(table_who[version], sender)
			end
			table_who["time"] = GetTime()
		elseif distribution == "GUILD" then
			FALoot:sendMessage(ADDON_MSG_PREFIX, {
				["who"] = ADDON_VERSION_FULL,
			}, "WHISPER", sender)
		end
	elseif t["update"] then
		if distribution == "WHISPER" then
			if not updateMsg then
				debug("Your current version of "..ADDON_NAME.." is not up to date! Please go to "..ADDON_DOWNLOAD_URL.." to update.");
				updateMsg = true
			end
		elseif distribution == "RAID" or distribution == "GUILD" then
			local version = t["update"]
			if version < ADDON_VERSION_FULL then
				FALoot:sendMessage(ADDON_MSG_PREFIX, {
					["update"] = true,
				}, "WHISPER", sender)
			elseif not updateMsg and ADDON_VERSION_FULL < version then
				debug("Your current version of "..ADDON_NAME.." is not up to date! Please go to "..ADDON_DOWNLOAD_URL.." to update.");
				updateMsg = true
			end
		end
	elseif t["winAmount"] and t["itemString"] then
		if table_items[t["itemString"]] then
			for i, v in pairs(table_items[t["itemString"]]["winners"]) do
				for j=1,#v do
					if v[j] == sender then
						table.remove(table_items[t["itemString"]]["winners"][i], j);
						break
					end
				end
			end
		end
		table.insert(table_items[t["itemString"]]["winners"][t["winAmount"]], sender);
		FALoot:itemTableUpdate();
	elseif t["foodTrackOn"] then
		if foodCount then
			FALoot:sendMessage(ADDON_MSG_PREFIX, {
				["foodCount"] = foodCount,
			}, "WHISPER", sender)
		end
		foodUpdateTo[sender] = true;
	elseif t["foodTrackOff"] then
		foodUpdateTo[sender] = nil;
	elseif t["foodCount"] and type(t["foodCount"]) == "number" then
		raidFoodCount[sender] = t["foodCount"];
	end
end

function FALoot:createGUI()
	-- Create the main frame
	frame = CreateFrame("frame", "FALootFrame", UIParent)
	frame:EnableMouse(true);
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
	closeButton:SetScript("OnClick", function()
		frame:Hide();
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
	
	-- Create the Tell Window Award button
	tellsFrameAwardButton = CreateFrame("Button", tellsFrame:GetName().."AwardButton", tellsFrame, "UIPanelButtonTemplate")
	tellsFrameAwardButton:SetPoint("BOTTOMLEFT", 15, 15)
	tellsFrameAwardButton:SetHeight(20)
	tellsFrameAwardButton:SetWidth(154)
	tellsFrameAwardButton:SetText("Award Item")
	tellsFrameAwardButton:SetScript("OnClick", function(frame)
		local selection = tellsTable:GetSelection();
		if selection then
			SendChatMessage(table_items[tellsInProgress]["itemLink"].." "..table_items[tellsInProgress]["tells"][selection][1], "RAID");
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
		local j, itemLink, itemString = 0;
		for i, v in pairs(table_items) do
			j = j + 1;
			if j == id then
				FALoot:itemTakeTells(i);
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
									["ADDON_VERSION"] = ADDON_VERSION, 
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
		elseif msg == "hasBeenLooted" then
			debug(hasBeenLooted);
		elseif msg == "food" then
			local t = {};
			for i, v in pairs(raidFoodCount) do
				t[v] = (t[v] + 1) or 1;
			end
			debug(t);
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
	elseif msgLower == "who" or msgLower == "vc" or msgLower == "versioncheck" then
		FALoot:sendMessage(ADDON_MSG_PREFIX, {
			["who"] = "query",
		}, "GUILD");
		return;
	else
		debug("The following are valid slash commands:");
		print("/fa debug <threshold> -- set debugging threshold");
		print("/fa who -- see who is running the addon and what version");
		print("/fa -- shows the loot window");
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
					if t["tells"][i][1] == UnitName(groupType..j) then
						local _, class = UnitClass(groupType..j);
						t["tells"][i][1] = "|c" .. RAID_CLASS_COLORS[class]["colorStr"] .. t["tells"][i][1] .. "|r";
						break;
					end
				end
			end
		end
		
		-- Count flags
		local currentTime = time();
		for i=1,#t["tells"] do
			local flags = 0;
			if table_itemHistory[t["tells"][i][1]] then
				for j=1,#table_itemHistory[t["tells"][i][1]] do
					if currentTime-table_itemHistory[t["tells"][i][1]][j][2] <= 60*60*12 then
						flags = flags + 1;
					end
				end
			end
			table.insert(t["tells"][i], flags);
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
	else
		tellsButton:Hide();
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
end

local ouframe = CreateFrame("frame")
ouframe:SetScript("OnUpdate", onUpdate)

function FALoot:parseChat(msg, author)
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
				elseif tellsInProgress and tellsInProgress == itemString and table_items[itemString]["host"] ~= author then
					tellsInProgress = nil;
				end
				
				if string.match(value, "roll") then
					table_items[itemString]["status"] = "Rolls";
				elseif string.match(value, "[321]0") then
					table_items[itemString]["currentValue"] = tonumber(string.match(value, "[321]0"));
					table_items[itemString]["status"] = "Tells";
				else
					-- do some stuff to replace a bunch of ways that people could potentially list multiple winners with commas
					value = string.gsub(value, "%sand%s", ", ")
					value = string.gsub(value, "%s?&%s?", ", ")
					value = string.gsub(value, "%s?/%s?", ", ")
					value = string.gsub(value, "%s?\+%s?", ", ")
					
					local winners = str_split(", ", value);
					debug(winners, 1);
					for i=1, #winners do
						winners[i] = FALoot:findClosestGroupMember(winners[i]);
						
						-- check if the player was the winner of the item
						-- and if they are retrieve the amount of DKP they spent on it
						local cost;
						if winners[i] == UnitName("player"):lower() then
							debug("The player won an item!", 1)
							if table_items[itemString]["bid"] then
								cost = table_items[itemString]["bid"];
								LootWonAlertFrame_ShowAlert(table_items[itemString]["itemLink"], 1, LOOT_ROLL_TYPE_NEED, cost.." DKP");
								FALoot:sendMessage(ADDON_MSG_PREFIX, {
									["winAmount"] = cost,
									["itemString"] = itemString,
								}, "RAID")
							else
								LootWonAlertFrame_ShowAlert(table_items[itemString]["itemLink"], 1);
							end
						end
						
						-- if the player didn't win or if we don't know what they bid then create a placeholder value
						if not cost then
							if table_items[itemString]["currentValue"] == 30 then
								cost = table_items[itemString]["bid"] or "30+";
							else
								cost = tostring(table_items[itemString]["currentValue"]);
							end
						end
						
						-- create a table entry for that pricepoint
						if not table_items[itemString]["winners"][cost] then
							table_items[itemString]["winners"][cost] = {};
						end
						
						-- insert this event into the winners table
						table.insert(table_items[itemString]["winners"][cost], winners[i]);
						
						-- if # of winners >= item quantity then auto end the item
						local numWinners = 0;
						for j, v in pairs(table_items[itemString]["winners"]) do
							numWinners = numWinners + #v;
						end
						debug("numWinners = "..numWinners, 3);
						if numWinners >= table_items[itemString]["quantity"] then
							FALoot:itemEnd(itemString);
							break;
						end
					end
				end
				
				FALoot:itemTableUpdate();
				FALoot:checkBids();
				if tellsInProgress and tellsInProgress == itemString then
					FALoot:tellsTableUpdate();
				end
			end
		end
	end
end

function FALoot:parseWhisper(msg, author)
	if not table_items[tellsInProgress] then
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
		if UnitName(groupType..i) == author then
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
		--FALoot:parseChat("|cffa335ee|Hitem:96740:0:0:0:0:0:0:0:0:0:445|h[Sign of the Bloodied God]|h|r 30", UnitName("PLAYER"))
		FALoot:itemTakeTells("96740:0");
		table_items[tellsInProgress]["tells"] = {
			{"Dyrimar", nil, 30, ""},
			{"Demonicblade", nil, 30, ""},
			{"Pawkets", nil, 10, ""},
			{"Xaerlun", "Wyrm", 10, ""},
			{"Unbrewable", nil, 10, ""},
		}
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
		["ADDON_VERSION"] = ADDON_VERSION,
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
					["ADDON_VERSION"] = ADDON_VERSION,
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
			["update"] = ADDON_VERSION_FULL,
		}, "RAID", nil, "BULK")
	end
end
function events:GROUP_ROSTER_UPDATE()
	FALoot:setAutoLoot();
	FALoot:setLeaderUIVisibility();
end
function events:RAID_ROSTER_UPDATE()
	FALoot:setAutoLoot();
	FALoot:setLeaderUIVisibility();
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
function events:BAG_UPDATE_DELAYED()
	local count = GetItemCount(itemId) or 0;
	if foodCount ~= count then
		for i, v in pairs(foodUpdateTo) do
			FALoot:sendMessage(ADDON_MSG_PREFIX, {
				["foodCount"] = foodCount,
			}, "WHISPER", i)
		end
		foodCount = count;
	end
end

eventFrame:SetScript("OnEvent", function(self, event, ...)
	events[event](self, ...) -- call one of the functions above
end)
for k, v in pairs(events) do
	eventFrame:RegisterEvent(k) -- Register all events for which handlers have been defined
end
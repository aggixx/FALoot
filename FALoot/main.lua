--[[
	Fix setLoot on login
-]]

-- Declare strings
local ADDON_NAME = "FALoot"
local ADDON_VERSION_FULL = "v4.1e"
local ADDON_VERSION = string.gsub(ADDON_VERSION_FULL, "[^%d]", "")

local ADDON_COLOR = "FFF9CC30";
local ADDON_CHAT_HEADER  = "|c" .. ADDON_COLOR .. "FA Loot:|r ";
local ADDON_MSG_PREFIX = "FALoot";
local ADDON_DOWNLOAD_URL = "https://github.com/aggixx/FALoot"

local HYPERLINK_PATTERN = "\124c%x+\124Hitem:%d+:%d+:%d+:%d+:%d+:%d+:%-?%d+:%-?%d+:?%d*:?%d*:?%d*:?%d*:?%d*:?%d*:?%d*\124h.-\124h\124r"
local THUNDERFORGED_COLOR = "FFFF8000"

-- Load the libraries
FALoot = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME)
LibStub("AceComm-3.0"):Embed(FALoot)

local ScrollingTable = LibStub("ScrollingTable")
local libSerialize = LibStub:GetLibrary("AceSerializer-3.0")
local libCompress = LibStub:GetLibrary("LibCompress")
local libEncode = libCompress:GetAddonEncodeTable()
local AceGUI = LibStub("AceGUI-3.0");

-- Declare local variables

-- SavedVariables options
local debugOn = 0;		-- Debug threshold
local expTime = 15;		-- Amount of time before an ended item is removed from the window, in seconds.
local cacheInterval = 200;	-- Amount of time between attempts to check for item data, in milliseconds.
local table_aliases = {};
local autolootToggle;
local autolootKey;

-- Hard-coded options
local maxIcons = 11;

-- Session Variables
local _;
local table_items = {};
local table_itemQuery = {};
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

-- GUI elements
local frame;
local iconFrame;
local scrollingTable;
local tellsButton;
local closeButton;
local bidButton;

--helper functions

local function debug(msg, verbosity)
	if (not verbosity or debugOn >= verbosity) then
		if type(msg) == "string" or type(msg) == "number" then
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

local function ItemLinkStrip(itemLink)
	if itemLink then
		local _, _, linkColor, linkType, itemId, enchantId, gemId1, gemId2, gemId3, gemId4, suffixId, uniqueId, linkLevel, reforgeId, itemName =
		string.find(itemLink, "|?c?f?f?(%x*)|?H?([^:]*):?(%d+):?(%d*):?(%d*):?(%d*):?(%d*):?(%d*):?(%-?%d*):?(%-?%d*):?(%d*):?(%d*):%d+|?h?%[?([^%[%]]*)%]?|?h?|?r?")
		if itemId and suffixId then
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
	local aspects = 0
	local drakes = 0
	for i=1,40 do
		if UnitExists(groupType..i) then
			local name = GetRaidRosterInfo(i)
			SetGuildRosterShowOffline(false)
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
	if aspects >= 2 and drakes >= 5 then
		return true
	else
		return false
	end
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
						debug("Added "..v[j].."to the loot window via addon message.", 2);
						FALoot:itemAdd(v[j])
					end
					hasBeenLooted[i] = true;
				else
					debug(i.." has already been looted.", 2);
				end
			end
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
	end
end

function FALoot:createGUI()
	-- Create the main frame
	frame = CreateFrame("frame", "FALoot", UIParent)
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
	iconFrame = CreateFrame("frame", "FALootIcons", frame);
	iconFrame:SetHeight(40);
	iconFrame:SetWidth(500);
	iconFrame:SetPoint("TOP", frame, "TOP", 0, -30);
	iconFrame:Show();
	
	-- Populate the iconFrame with icons
	for i=1,maxIcons do
		table_icons[i] = CreateFrame("frame", "FALootIcon"..tostring(i), iconFrame)
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
	closeButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	closeButton:SetPoint("BOTTOMRIGHT", -27, 17)
	closeButton:SetHeight(20)
	closeButton:SetWidth(80)
	closeButton:SetText(CLOSE)
	closeButton:SetScript("OnClick", function()
		frame:Hide();
	end);
	
	-- Create the "Bid" button
	bidButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
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

	-- Create the "Take Tells" button
	tellsButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate");
	tellsButton:SetScript("OnClick", function(self, event)
		local id = scrollingTable:GetSelection()
		local j, itemLink, itemString = 0;
		for i, v in pairs(table_items) do
			j = j + 1;
			if j == id then
				itemLink, itemString = v["itemLink"], i;
				break;
			end
		end
		debug("This functionality is not yet implemented.");
	end)
	tellsButton:SetPoint("BOTTOM", bidButton, "TOP");
	tellsButton:SetHeight(20);
	tellsButton:SetWidth(80);
	tellsButton:SetText("Take Tells");
	tellsButton:SetFrameLevel(scrollingTable.frame:GetFrameLevel()+1);
	tellsButton:Hide(); -- hide by default, we can reshow it later if we need to

	-- Create the background of the Status Bar
	local statusbg = CreateFrame("Button", nil, frame)
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
	local statustext = statusbg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	statustext:SetPoint("TOPLEFT", 7, -2)
	statustext:SetPoint("BOTTOMRIGHT", -7, 2)
	statustext:SetHeight(20)
	statustext:SetJustifyH("LEFT")
	statustext:SetText("")

	-- Create the background of the title
	local titlebg = frame:CreateTexture(nil, "OVERLAY")
	titlebg:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
	titlebg:SetTexCoord(0.31, 0.67, 0, 0.63)
	titlebg:SetPoint("TOP", 0, 12)
	titlebg:SetHeight(40)

	-- Create the title frame
	local title = CreateFrame("Frame", nil, frame)
	title:EnableMouse(true)
	title:SetScript("OnMouseDown", function(frame)
		frame:GetParent():StartMoving()
	end)
	title:SetScript("OnMouseUp", function(frame)
		frame:GetParent():StopMovingOrSizing()
	end)
	title:SetAllPoints(titlebg)

	-- Create the text of the title
	local titletext = title:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	titletext:SetPoint("TOP", titlebg, "TOP", 0, -14)
	titletext:SetText("FA Loot");
	
	titlebg:SetWidth((titletext:GetWidth() or 0) + 10)

	-- Create the title background left edge
	local titlebg_l = frame:CreateTexture(nil, "OVERLAY")
	titlebg_l:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
	titlebg_l:SetTexCoord(0.21, 0.31, 0, 0.63)
	titlebg_l:SetPoint("RIGHT", titlebg, "LEFT")
	titlebg_l:SetWidth(30)
	titlebg_l:SetHeight(40)

	-- Create the title background right edge
	local titlebg_r = frame:CreateTexture(nil, "OVERLAY")
	titlebg_r:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
	titlebg_r:SetTexCoord(0.67, 0.77, 0, 0.63)
	titlebg_r:SetPoint("LEFT", titlebg, "RIGHT")
	titlebg_r:SetWidth(30)
	titlebg_r:SetHeight(40)
end

function FALoot:isThunderforged(iLevel)
	return iLevel == 541 or iLevel == 528;
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
					GameTooltip:SetHyperlink(v["itemLink"])
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
	elseif string.match(msgLower, "^alias add .+") then
		local alias = string.match(msgLower, "^alias add (.+)");
		table.insert(table_aliases, alias);
		debug(alias.." added as an alias.");
		return;
	elseif string.match(msgLower, "^alias remove .+") then
		local alias = string.match(msgLower, "^alias remove (.+)");
		for i=1,#table_aliases do
			if table_aliases[i] == alias then
				table.remove(table_aliases, i)
				debug('Alias "'..alias..'" removed.')
				return;
			end
		end
		debug(alias.." is not currently an alias.");
		return;
	elseif string.match(msgLower, "^alias list") then
		if #table_aliases == 0 then
			debug("You currently have no aliases.");
			return;
		end
		local s = "";
		for i=1,#table_aliases do
			if i > 1 then
				s = s..", ";
			end
			s = s .. table_aliases[i];
		end
		debug("Current aliases are: "..s);
		return;
	elseif msgLower == "resetpos" then
		frame:ClearAllPoints()
		frame:SetPoint("CENTER")
		return;
	else
		debug("The following are valid slash commands:");
		print("/faloot debug <threshold> -- set debugging threshold");
		print("/faloot who -- see who is running the addon and what version");
		print("/faloot alias add <name> -- add an alias for award detection");
		print("/faloot alias remove <name> -- remove an alias for award detection");
		print("/faloot alias list -- list aliases for award detection");
		print("/faloot resetpos -- resets the position of the RT window");
	end
end
SlashCmdList["RT"] = slashparse
SlashCmdList["FALOOT"] = slashparse
SlashCmdList["FA"] = slashparse

SLASH_FAROLL1 = "/faroll"
local function FARoll(value)
	value = tonumber(value)
	if value % 2 ~= 0 then
		print("You are not allowed to bid odd numbers or non-integers. Your bid has been rounded down to the nearest even integer.")
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
		print("Invalid roll value!")
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

--[[window:SetCallback("OnClick", ) -]]

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

function FALoot:itemAdd(itemString, checkCache)
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
		}
	end
	
	FALoot:itemTableUpdate();
	
	if not frame:IsShown() then
		if UnitAffectingCombat("PLAYER") then
			showAfterCombat = true
			debug(itemLink.." was found but the player is in combat.");
		else
			frame:Show()
		end
	end
end

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
	
	--[[if #t >= 8 then
		tellsButton:ClearAllPoints();
		tellsButton:SetPoint("TOP", window.bidButton, "BOTTOM");
	else
		tellsButton:ClearAllPoints();
		tellsButton:SetPoint("BOTTOM", window.bidButton, "TOP");
	end--]]
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
	return;
	
	--[[local bidding, rolling, only = 0, 0;
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
		window:SetStatusText("");
	elseif bidding + rolling == 1 then
		local verb = "";
		if bidding > 0 then
			verb = "bid"
		else
			verb = "roll"
		end
		window:SetStatusText("Waiting to " .. verb .. " on " .. table_items[only]["displayName"] .. ".")
	else
		if bidding > 0 and rolling > 0 then
			local plural1, plural2 = "", "";
			if bidding > 1 then
				plural1 = "s";
			end
			if rolling > 1 then
				plural2 = "s";
			end
			window:SetStatusText("Waiting to bid on " .. bidding .. " item" .. plural1 .. " and roll on " .. rolling .. " item" .. plural2 .. ".");
		elseif bidding > 0 then
			window:SetStatusText("Waiting to bid on " .. bidding .. " items.");
		else
			window:SetStatusText("Waiting to roll on " .. rolling .. " items.");
		end
	end--]]
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
	--window:SetDisabled(false);
	
	local j = 0;
	for i, v in pairs(table_items) do
		j = j + 1;
		if j == id then
			if not v["status"] or v["status"] == "" then
				--debug("Status of entry #"..id..' is "'..(v["status"] or "")..'".', 1);
				tellsButton:Enable();
			else
				tellsButton:Disable();
			end
			break;
		end
	end
end

function FALoot:onTableDeselect()
	--window:SetDisabled(true);
	tellsButton:Disable();
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
	
	--[[
	--enable/disable buttons
	if (iconSelect and iconSelect > 0) or (scrollingTable:GetSelection() and scrollingTable:GetSelection() > 0 and not iconSelect) then
		window:SetDisabled(false);
		tellsButton:Enable();
	else
		window:SetDisabled(true);
		tellsButton:Disable();
	end
	--]]
	
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
			print(s)
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
						local closestMatch, closestMatchId = math.huge;
						for j=1,GetNumGroupMembers() do
							local distance = string.levenshtein(winners[i], UnitName("raid"..j):lower())
							if distance and distance < closestMatch then
								closestMatch = distance;
								closestMatchId = j;
							end
						end
						if closestMatchId then
							winners[i] = UnitName("raid"..closestMatchId);
						end
						
						local cost;
						if string.match(winners[i], UnitName("player"):lower()) then -- if the player is one of the winners
							debug("The player won an item!", 1)
							LootWonAlertFrame_ShowAlert(table_items[itemString]["itemLink"], 1, LOOT_ROLL_TYPE_NEED, (table_items[itemString]["bid"] or "??").." DKP")
							if table_items[itemString]["bid"] then
								cost = table_items[itemString]["bid"];
								local t = {
									["winAmount"] = cost,
									["itemString"] = itemString,
								}
								debug(t, 1);
								FALoot:sendMessage(ADDON_MSG_PREFIX, t, "RAID")
							end
						else
							for j=1,#table_aliases do
								if string.match(winners[i], table_aliases[j]) then
									debug("The player won an item!", 1)
									LootWonAlertFrame_ShowAlert(table_items[itemString]["itemLink"], 1, LOOT_ROLL_TYPE_NEED, (table_items[itemString]["bid"] or "??").." DKP")
									if table_items[itemString]["bid"] then
										cost = table_items[itemString]["bid"];
									end
									break;
								end
							end
						end
						
						if not cost then
							if table_items[itemString]["currentValue"] == 30 then
								cost = table_items[itemString]["bid"] or "30+";
							else
								cost = tostring(table_items[itemString]["currentValue"]);
							end
						end
						if not table_items[itemString]["winners"][cost] then
							table_items[itemString]["winners"][cost] = {};
						end
						table.insert(table_items[itemString]["winners"][cost], winners[i]);
						
						local numWinners = 0;
						for j, v in pairs(table_items[itemString]["winners"]) do
							numWinners = numWinners + #v;
						end
						debug("numWinners = "..numWinners, 1);
						if numWinners >= table_items[itemString]["quantity"] then
							FALoot:itemEnd(itemString);
							break;
						end
					end
				end
				FALoot:itemTableUpdate();
				FALoot:checkBids();
			end
		end
	end
end

function FALoot:setAutoLoot()
	local toggle, key = GetCVar("autoLootDefault"), GetModifiedClick("AUTOLOOTTOGGLE");
	if FALoot:addonEnabled(true) then
		if not (toggle == "0" and key == "NONE") then
			SetCVar("autoLootDefault", 0);
			SetModifiedClick("AUTOLOOTTOGGLE", "NONE");
			debug("Your autoloot has been disabled.");
		end
	elseif autolootToggle and autolootKey then
		if key == "NONE" then
			debug("Your loot settings have been restored.");
			SetModifiedClick("AUTOLOOTTOGGLE", autolootKey);
			if toggle == "0" then
				SetCVar("autoLootDefault", autolootToggle);
			end
		end
	end
end
	
local frame, events = CreateFrame("Frame"), {}
function events:ADDON_LOADED(name)
	if name == ADDON_NAME then
		FALoot_options = FALoot_options or {};
		debugOn = FALoot_options["debugOn"] or debugOn;
		expTime = FALoot_options["expTime"] or expTime;
		cacheInterval = FALoot_options["cacheInterval"] or cacheInterval;
		table_aliases = FALoot_options["table_aliases"] or table_aliases;
		autolootToggle = FALoot_options["autolootToggle"];
		autolootKey = FALoot_options["autolootKey"];
		
		FALoot:RegisterComm(ADDON_MSG_PREFIX);
	end
end
function events:PLAYER_LOGIN()
	if not (autolootToggle and autolootKey) then
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
	else
		FALoot:setAutoLoot();
	end
	
	FALoot:createGUI();
	FALoot:setLeaderUIVisibility();

	if debugOn > 0 then
		FALoot:itemAdd("96379:0")
		FALoot:itemAdd("96753:0")
		FALoot:itemAdd("96740:0")
		FALoot:itemAdd("96740:0")
		FALoot:itemAdd("96373:0")
		FALoot:itemAdd("96377:0")
		FALoot:itemAdd("96384:0")
		FALoot:parseChat("|cffa335ee|Hitem:96740:0:0:0:0:0:0:0:0:0:445|h[Sign of the Bloodied God]|h|r 30", UnitName("PLAYER"))
	else
		window:Hide();
	end
end
function events:PLAYER_LOGOUT(...)
	FALoot_options = {
		["debugOn"]        = debugOn,
		["expTime"]        = expTime,
		["cacheInterval"]  = cacheInterval,
		["table_aliases"]  = table_aliases,
		["autolootToggle"] = autolootToggle,
		["autolootKey"]    = autolootKey,
	};
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
			if mobID and not hasBeenLooted[mobID] then
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
	
	-- add an item count for each GUID so that other clients may verify data integrity
	for i, v in pairs(loot) do
		loot[i]["checkSum"] = #v;
	end
	
	debug(loot, 2);
	
	-- check data integrity
	local count = 0;
	for i, v in pairs(loot) do
		if not (v["checkSum"] and v["checkSum"] == #v) then
			debug("Loot data recieved via an addon message failed the integrity check.");
			return;
		end
		if #v == 0 then
			loot[i] = nil;
		end
		count = count + 1;
	end
	
	if count == 0 then
		debug("There is no loot on this mob!", 1);
		return;
	end
	
	-- send addon message to tell others to add this to their window
	FALoot:sendMessage(ADDON_MSG_PREFIX, {
		["ADDON_VERSION"] = ADDON_VERSION,
		["loot"] = loot,
	}, "RAID", nil, "BULK");
	
	for i, v in pairs(loot) do
		for j=1,#v do
			-- we can assume that everything in the table is not on the HBL
			FALoot:itemAdd(v[j])
		end
		hasBeenLooted[i] = true;
	end
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
	local limit = #table_itemQuery
	for i=0,limit-1 do
		FALoot:itemAdd(table_itemQuery[limit-i], true)
	end
end
frame:SetScript("OnEvent", function(self, event, ...)
	events[event](self, ...) -- call one of the functions above
end)
for k, v in pairs(events) do
	frame:RegisterEvent(k) -- Register all events for which handlers have been defined
end
--[[
	DONE:
	ItemLinkStrip()
	ItemLinkAssemble()
	generateIcons()
	itemAdd()
	itemTableUpdate()
	itemEnd()
	itemRemove()
	parseChat()
	itemBid()
	checkBids()
	
	TODO:
	slashparse()
	OnCommRecieved()
	
-]]

-- Declare strings
local ADDON_NAME = "FARaidTools"
local ADDON_VERSION_FULL = "v4.0"
local ADDON_VERSION = string.gsub(ADDON_VERSION_FULL, "[^%d]", "")

local ADDON_COLOR = "FFF9CC30";
local ADDON_CHAT_HEADER  = "|c" .. ADDON_COLOR .. ADDON_NAME .. ":|r ";
local ADDON_MSG_PREFIX = "FA_RT";
local ADDON_DOWNLOAD_URL = "http://tinyurl.com/FARaidTools"

local HYPERLINK_PATTERN = "\124%x+\124Hitem:%d+:%d+:%d+:%d+:%d+:%d+:%-?%d+:%-?%d+:?%d*:?%d*:?%d*:?%d*:?%d*:?%d*:?%d*\124h.-\124h\124r"
local THUNDERFORGED = " |cFF00FF00(TF)|r"

-- Load the libraries
FARaidTools = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME)
LibStub("AceComm-3.0"):Embed(FARaidTools)

local ScrollingTable = LibStub("ScrollingTable")
local libSerialize = LibStub:GetLibrary("AceSerializer-3.0")
local libCompress = LibStub:GetLibrary("LibCompress")
local libEncode = libCompress:GetAddonEncodeTable()
local AceGUI = LibStub("AceGUI-3.0");

-- Declare local variables
local table_items = {}
local table_mainData = {}
local table_bids = {}
local table_itemQuery = {}
local table_expTimes = {}
local table_nameAssociations = {}
local table_icons = {}
local table_who = {}
local table_aliases = {}

local debugOn = 2
local hasBeenLooted = {}
local expTime = 15 -- TODO: Add this as an option
local cacheInterval = 200 -- this is how often we recheck for item data
local tableMode = 0
local lootSettings

local showAfterCombat
local iconSelect
local endPrompt
local bidPrompt
local promptBidValue
local updateMsg = nil

local _

--[[

-- Create a container frame
local frame = AceGUI:Create("Frame");
frame:SetCallback("OnClose", function(this)
  this:Hide();
end);
frame:SetTitle("FARaidTools");
--frame:SetStatusText("Status Bar");
frame:SetWidth(400);
frame:SetHeight(400);
--frame:EnableResize(false);
frame:SetLayout("Fill");

local iconGroup = AceGUI:Create("ScrollFrame");
frame:AddChild(iconGroup);

local function addIcon(link, texture)
	local path, size, flags = GameFontNormal:GetFont();
	
	local iconCallback = function(this, event, ...)
		if event == "OnEnter" then
			GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR");
			GameTooltip:SetHyperlink(link);
			
			-- Show the tooltip
			GameTooltip:Show();
		elseif event == "OnLeave" then
			GameTooltip:Hide();
		elseif event == "OnClick" then
			local button = ...;
			if button == "LeftButton" then
				if IsModifiedClick("CHATLINK") then
					ChatEdit_InsertLink(link)
				elseif IsModifiedClick("DRESSUP") then
					DressUpItemLink(link)
				end
			end
		end
	end

	local group = AceGUI:Create("SimpleGroup");
	iconGroup:AddChild(group);
	group:SetLayout("Flow");
	group:SetWidth(350);
	group:SetHeight(55);
	
	local subGroup1 = AceGUI:Create("SimpleGroup");
	group:AddChild(subGroup1);
	subGroup1:SetLayout("Fill");
	subGroup1:SetWidth(60);
	subGroup1:SetHeight(55);

	local icon = AceGUI:Create("Icon");
	subGroup1:AddChild(icon);
	icon:SetImage(texture);
	icon:SetImageSize(50, 50);
	icon:SetCallback("OnEnter", iconCallback);
	icon:SetCallback("OnLeave", iconCallback);
	icon:SetCallback("OnClick", iconCallback);

	local subGroup2 = AceGUI:Create("SimpleGroup");
	group:AddChild(subGroup2);
	subGroup2:SetLayout("Flow");
	subGroup2:SetWidth(200);
	subGroup2:SetHeight(55);

	local label1 = AceGUI:Create("InteractiveLabel");
	subGroup2:AddChild(label1);
	label1:SetText(link);
	label1:SetFont(path, 14, flags);
	label1:SetCallback("OnEnter", iconCallback);
	label1:SetCallback("OnLeave", iconCallback);
	label1:SetCallback("OnClick", iconCallback);

	local button1 = AceGUI:Create("Button");
	subGroup2:AddChild(button1);
	button1:SetText("Bid");
	button1:SetWidth(55)
	button1:SetCallback("OnClick", nil);

	local button2 = AceGUI:Create("Button");
	subGroup2:AddChild(button2);
	button2:SetText("Start");
	button2:SetWidth(55)
	button2:SetCallback("OnClick", nil);

	local button3 = AceGUI:Create("Button");
	subGroup2:AddChild(button3);
	button3:SetText("End");
	button3:SetWidth(55)
	button3:SetCallback("OnClick", nil);

	local subGroup3 = AceGUI:Create("SimpleGroup");
	group:AddChild(subGroup3);
	subGroup3:SetLayout("Fill");
	subGroup3:SetWidth(60);
	subGroup3:SetHeight(55);

	local label2 = AceGUI:Create("InteractiveLabel");
	subGroup3:AddChild(label2);
	label2:SetText("30");
	label2:SetFont(path, 28, flags);
end

local _, link, _, _, _, _, _, _, _, texture = GetItemInfo(96369);
addIcon(link, texture)
local _, link, _, _, _, _, _, _, _, texture = GetItemInfo(96376);
addIcon(link, texture)
local _, link, _, _, _, _, _, _, _, texture = GetItemInfo(96379);
addIcon(link, texture)
local _, link, _, _, _, _, _, _, _, texture = GetItemInfo(96387);
addIcon(link, texture)
local _, link, _, _, _, _, _, _, _, texture = GetItemInfo(96372);
addIcon(link, texture)
local _, link, _, _, _, _, _, _, _, texture = GetItemInfo(96382);
addIcon(link, texture)

--]]


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
	elseif debugOn then
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

local function addonEnabled()
	if debugOn then
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

function FARaidTools:addonEnabled()
	return addonEnabled()
end

function FARaidTools:checkFilters(link, checkItemLevel)
	--this is the function that determines if an item should or shouldn't be added to the window and/or announced
	
	if debugOn then
		return true
	end
	
	-- check properties of item
	local _, _, quality, ilevel, _, class, subClass = GetItemInfo(link)
	
	-- check if the quality of the item is high enough
	if quality ~= 4 then -- TODO: Add customizable quality filters
		if debugOn then print("Quality of "..link.." is too low.") end
		return false
	end
		
	-- check if the class of the item is appropriate
	if not (class == "Armor" or class == "Weapon" or (class == "Miscellaneous" and subClass == "Junk")) then
		if debugOn then print("Class of "..link.." is incorrect.") end
		return false
	end
	
	-- check if the item level of the item is high enough
	local playerTotal = GetAverageItemLevel()
	if checkItemLevel and playerTotal - ilevel > 20 then -- if the item is more than 20 levels below the player
		if debugOn then print("Item Level of "..link.." is too low.") end
		return false
	end
	
	return true
end

local function StaticDataSave(data)
	promptBidValue = data
end

function FARaidTools:sendMessage(prefix, text, distribution, target, prio, needsCompress)
	--serialize
	local serialized, msg = libSerialize:Serialize(text)
	if serialized then
		text = serialized
	else
		print("RT: Serialization of data failed!")
		return
	end
	--compress
	if needsCompress and false then -- disabled
		local compressed, msg = libCompress:CompressHuffman(text)
		if compressed then
			text = compressed
		else
			print("RT: Compression of data failed!")
			return
		end
	end
	--encode
	local encoded, msg = libEncode:Encode(text)
	if encoded then
		text = encoded
	else
		print("RT: Encoding of data failed!")
		return
	end
	
	FARaidTools:SendCommMessage(prefix, text, distribution, target, prio)
end

function FARaidTools:OnCommReceived(prefix, text, distribution, sender)
	if not text then
		return
	elseif sender == UnitName("PLAYER") and prefix ~= "FA_RTwho" then
		return
	end
	if debugOn then print("Recieved \""..prefix.."\" message.") end
	
	-- Decode the data
	local text = libEncode:Decode(text)
	
	-- Deserialize the data
	local success, deserialized = libSerialize:Deserialize(text)
	if success then
		text = deserialized
	else
		if debugOn then print("RT: Deserialization of data failed: "..text) end
		return
	end
	
	if debugOn and (prefix == "FA_RTwho" or prefix == "FA_RTupdate" or text[1] == ADDON_VERSION) then DevTools_Dump(text) end
	
	if prefix == "FA_RTreport" and text[1] == ADDON_VERSION then
		if addonEnabled() then
			local data = text[2]
			if data[2] == #data then -- check data integrity
				table.remove(data, 2)
				local mobID = table.remove(data, 1)
				
				-- check if the mob has been looted before
				for i=1,#hasBeenLooted do 
					if hasBeenLooted[i] == mobID then
						return
					end
				end
				
				for i=1,#data do
					if FARaidTools:checkFilters(data[i], true) then
						FARaidTools:itemAdd(data[i])
					end
				end
				table.insert(hasBeenLooted, mobID)
			end
		end
	elseif prefix == "FA_RTend" and text[1] == ADDON_VERSION then
		local itemLink = text[2]
		
		if itemLink then
			FARaidTools:itemEnd(itemLink)
		end
	elseif prefix == "FA_RTwho" then
		if distribution == "WHISPER" then
			local version = text[2]
			
			local table_who = table_who or {}
			if version then
				if debugOn then print("Who response recieved from "..sender..".") end
				if not table_who[version] then
					table_who[version] = {}
					table.insert(table_who, version)
				end
				table.insert(table_who[version], sender)
			end
			table_who["time"] = GetTime()
		elseif distribution == "GUILD" then
			FARaidTools:sendMessage("FA_RTwho", {"response", ADDON_VERSION_FULL}, "WHISPER", sender)
		end
	elseif prefix == "FA_RTupdate" then
		if distribution == "WHISPER" then
			if not updateMsg then
				print("Your current version of FARaidTools is not up to date! Please go to "..downloadUrl.." to update.")
				updateMsg = true
			end
		elseif distribution == "RAID" or distribution == "GUILD" then
			if not text[1] then return end
			local version = text[1]
			if version < ADDON_VERSION_FULL then
				FARaidTools:sendMessage("FA_RTupdate", {}, "WHISPER", sender)
			elseif not updateMsg then
				if ADDON_VERSION_FULL < version then
					print("Your current version of FARaidTools is not up to date! Please go to "..downloadUrl.." to update.")
					updateMsg = true
				end
			end
		end
	end
end

--Create GUI elements
local cols = {
	{
		["name"] = "Name",
		["width"] = 200,
		["align"] = "LEFT",
		["color"] = { 
			["r"] = 1.0, 
			["g"] = 1.0, 
			["b"] = 1.0, 
			["a"] = 1.0 
		},
		["colorargs"] = nil,
		["defaultsort"] = "asc",
		["DoCellUpdate"] = nil,
	},
	{
		["name"] = "Status",
		["width"] = 60,
		["align"] = "LEFT",
		["color"] = { 
			["r"] = 1.0, 
			["g"] = 1.0, 
			["b"] = 1.0, 
			["a"] = 1.0 
		},
		["colorargs"] = nil,
		["defaultsort"] = "dsc",
		["DoCellUpdate"] = nil,
	},
	{
		["name"] = "Winners",
		["width"] = 150,
		["align"] = "LEFT",
		["color"] = { 
			["r"] = 1.0, 
			["g"] = 1.0, 
			["b"] = 1.0, 
			["a"] = 1.0 
		},
		["colorargs"] = nil,
		["defaultsort"] = "dsc",
		["DoCellUpdate"] = nil,
	}
}
FA_RTframe = CreateFrame("frame", "FALoot")
FA_RTframe:SetBackdrop({
	bgFile = "Interface/Tooltips/UI-Tooltip-Background",
	tile = true, 
	tileSize = 16
})
FA_RTframe:SetBackdropColor(0, 0, 0, 0.6)
FA_RTframe:SetWidth(460)
FA_RTframe:SetHeight(235)
FA_RTframe:SetMovable(true)
FA_RTframe:SetScript("OnMouseDown", function(self, button)
	if button == "LeftButton" then
		self:StartMoving()
	end
end)
FA_RTframe:SetScript("OnMouseUp", function(self, button)
	if button == "LeftButton" then
		self:StopMovingOrSizing()
	end
end)
FA_RTframe:SetPoint("CENTER")
FA_RTframe:Hide()
FA_RTbutton1 = CreateFrame("button", "FA_RTbutton", FA_RTframe)
FA_RTbutton1:SetPoint("BOTTOMLEFT", FA_RTframe, "BOTTOMLEFT", 11, -2)
FA_RTbutton1:SetNormalTexture("Interface\\BUTTONS\\UI-DialogBox-Button-Up.png")
FA_RTbutton1:SetPushedTexture("Interface\\BUTTONS\\UI-DialogBox-Button-Down.png")
FA_RTbutton1:SetDisabledTexture("Interface\\BUTTONS\\UI-DialogBox-Button-Disabled.png")
FA_RTbutton1:SetHeight(25)
FA_RTbutton1:SetWidth(60)
FA_RTbutton1text = FA_RTbutton1:CreateFontString("FA_RTbutton_text")
FA_RTbutton1text:SetPoint("CENTER", FA_RTbutton1, "CENTER", 0, 4)
FA_RTbutton1text:SetFont(GameFontNormal:GetFont(), 10, "")
FA_RTbutton1text:SetText("History")
FA_RTbutton1text:SetTextColor(1, 1, 1)
FA_RTbutton1:Show()

FA_RTbutton2 = CreateFrame("button", "FA_RTbutton", FA_RTframe)
FA_RTbutton2:SetPoint("LEFT", FA_RTbutton1, "RIGHT", 5, 0)
FA_RTbutton2:SetNormalTexture("Interface\\BUTTONS\\UI-DialogBox-Button-Up.png")
FA_RTbutton2:SetPushedTexture("Interface\\BUTTONS\\UI-DialogBox-Button-Down.png")
FA_RTbutton2:SetDisabledTexture("Interface\\BUTTONS\\UI-DialogBox-Button-Disabled.png")
FA_RTbutton2:SetHeight(25)
FA_RTbutton2:SetWidth(60)
FA_RTbutton2text = FA_RTbutton2:CreateFontString("FA_RTbutton_text")
FA_RTbutton2text:SetPoint("CENTER", FA_RTbutton2, "CENTER", 0, 4)
FA_RTbutton2text:SetFont(GameFontNormal:GetFont(), 10, "")
FA_RTbutton2text:SetText("Bid")
FA_RTbutton2text:SetTextColor(1, 1, 1)
FA_RTbutton2:Show()

FA_RTbutton3 = CreateFrame("button", "FA_RTbutton", FA_RTframe)
FA_RTbutton3:SetPoint("LEFT", FA_RTbutton2, "RIGHT", 5, 0)
FA_RTbutton3:SetNormalTexture("Interface\\BUTTONS\\UI-DialogBox-Button-Up.png")
FA_RTbutton3:SetPushedTexture("Interface\\BUTTONS\\UI-DialogBox-Button-Down.png")
FA_RTbutton3:SetDisabledTexture("Interface\\BUTTONS\\UI-DialogBox-Button-Disabled.png")
FA_RTbutton3:SetHeight(25)
FA_RTbutton3:SetWidth(60)
FA_RTbutton3text = FA_RTbutton3:CreateFontString("FA_RTbutton_text")
FA_RTbutton3text:SetPoint("CENTER", FA_RTbutton3, "CENTER", 0, 4)
FA_RTbutton3text:SetFont(GameFontNormal:GetFont(), 10, "")
FA_RTbutton3text:SetText("Edit")
FA_RTbutton3text:SetTextColor(1, 1, 1)
FA_RTbutton3:Show()
FA_RTbutton3:SetScript("OnMouseUp", function(self, button)
	if button == "LeftButton" then
		if FA_RTscrollingtable:GetSelection() then
			StaticPopupDialogs["FA_RTTEXT_EDIT"]["text"] = "Edit Winners for "..table_mainData[FA_RTscrollingtable:GetSelection()]["cols"][1]["value"]..":"
			StaticPopup_Show("FA_RTTEXT_EDIT")
		end
	end
end) 

FA_RTbutton4 = CreateFrame("button", "FA_RTbutton", FA_RTframe)
FA_RTbutton4:SetPoint("TOPRIGHT", FA_RTframe, "TOPRIGHT", -12, -5)
FA_RTbutton4:SetNormalTexture("Interface\\BUTTONS\\UI-DialogBox-Button-Up.png")
FA_RTbutton4:SetPushedTexture("Interface\\BUTTONS\\UI-DialogBox-Button-Down.png")
FA_RTbutton4:SetDisabledTexture("Interface\\BUTTONS\\UI-DialogBox-Button-Disabled.png")
FA_RTbutton4:SetHeight(25)
FA_RTbutton4:SetWidth(15)
FA_RTbutton4text = FA_RTbutton3:CreateFontString("FA_RTbutton_text")
FA_RTbutton4text:SetPoint("CENTER", FA_RTbutton4, "CENTER", 0, 4)
FA_RTbutton4text:SetFont(GameFontNormal:GetFont(), 10, "")
FA_RTbutton4text:SetText("X")
FA_RTbutton4text:SetTextColor(1, 1, 1)
FA_RTbutton4:Show()
FA_RTbutton4:SetScript("OnMouseUp", function(self, button)
	self:GetParent():Hide()
end) 

FA_RTscrollingtable = ScrollingTable:CreateST(cols, 9, nil, {["r"] = 0, ["g"] = 1, ["b"] = 0, ["a"] = 0.3}, FA_RTframe)
FA_RTscrollingtable:EnableSelection(true)
FA_RTscrollingtable.frame:SetPoint("CENTER", FA_RTframe, "CENTER", 0, -22.5)
FA_RTicons = CreateFrame("frame", "FA_RTicons", FA_RTframe)
FA_RTicons:SetHeight(30)
FA_RTicons:SetWidth(400)
FA_RTicons:SetPoint("BOTTOM", FA_RTscrollingtable.frame, "TOP", 0, 22.5)
FA_RTicons:Show()
--
local cols2 = {
	{
		["name"] = "Date",
		["width"] = 105,
		["align"] = "LEFT",
		["color"] = { 
			["r"] = 1.0, 
			["g"] = 1.0, 
			["b"] = 1.0, 
			["a"] = 1.0 
		},
		["colorargs"] = nil,
		["defaultsort"] = "asc",
		["DoCellUpdate"] = nil,
	},
	{
		["name"] = "Name",
		["width"] = 155,
		["align"] = "LEFT",
		["color"] = { 
			["r"] = 1.0, 
			["g"] = 1.0, 
			["b"] = 1.0, 
			["a"] = 1.0 
		},
		["colorargs"] = nil,
		["defaultsort"] = "dsc",
		["DoCellUpdate"] = nil,
	},
	{
		["name"] = "Winners",
		["width"] = 150,
		["align"] = "LEFT",
		["color"] = { 
			["r"] = 1.0, 
			["g"] = 1.0, 
			["b"] = 1.0, 
			["a"] = 1.0 
		},
		["colorargs"] = nil,
		["defaultsort"] = "dsc",
		["DoCellUpdate"] = nil,
	}
}
FA_RTscrollingtable2 = ScrollingTable:CreateST(cols2, 9, nil, {["r"] = 0, ["g"] = 1, ["b"] = 0, ["a"] = 0.3}, FA_RTframe)
FA_RTscrollingtable2.frame:SetPoint("CENTER", FA_RTframe, "CENTER", 0, -22.5)
FA_RTscrollingtable2:Hide()
--
local cols3 = {
	{
		["name"] = "Name",
		["width"] = 150,
		["align"] = "LEFT",
		["color"] = { 
			["r"] = 1.0, 
			["g"] = 1.0, 
			["b"] = 1.0, 
			["a"] = 1.0 
		},
		["colorargs"] = nil,
		["defaultsort"] = "asc",
		["DoCellUpdate"] = nil,
	},
	{
		["name"] = "Bid",
		["width"] = 30,
		["align"] = "LEFT",
		["color"] = { 
			["r"] = 1.0, 
			["g"] = 1.0, 
			["b"] = 1.0, 
			["a"] = 1.0 
		},
		["colorargs"] = nil,
		["defaultsort"] = "dsc",
		["DoCellUpdate"] = nil,
	},
	{
		["name"] = "Status",
		["width"] = 80,
		["align"] = "LEFT",
		["color"] = { 
			["r"] = 1.0, 
			["g"] = 1.0, 
			["b"] = 1.0, 
			["a"] = 1.0 
		},
		["colorargs"] = nil,
		["defaultsort"] = "dsc",
		["DoCellUpdate"] = nil,
	}
}
FA_RTbidframe = CreateFrame("frame", "FALoot_bid", FA_RTframe)
FA_RTbidframe:SetBackdrop({
	bgFile = "Interface/Tooltips/UI-Tooltip-Background",
	tile = true, 
	tileSize = 16
})
FA_RTbidframe:SetBackdropColor(0, 0, 0, 0.6)
FA_RTbidframe:SetWidth(295)
FA_RTbidframe:SetHeight(75)
FA_RTbidframe:SetPoint("TOP", FA_RTframe, "BOTTOM", 0, 0)
FA_RTbidframe:Hide()
FA_RTscrollingtable3 = ScrollingTable:CreateST(cols3, 3, nil, {["r"] = 0, ["g"] = 1, ["b"] = 0, ["a"] = 0.3}, FA_RTbidframe)
FA_RTscrollingtable3.frame:SetPoint("CENTER", FA_RTbidframe, "CENTER", 0, -8)
FA_RTscrollingtable3:Show()
FA_RTscrollingtable3:SetData(table_bids, true)

for i=1,13 do
	table_icons[i] = CreateFrame("frame", "FA_RTicon"..tostring(i), FA_RTicons)
	table_icons[i]:SetWidth(30)
	table_icons[i]:SetHeight(30)
	table_icons[i]:Hide()
end

local function modeSet(num)
	if num == 0 then
		tableMode = 0
		FA_RTscrollingtable:Show()
		FA_RTscrollingtable2:Hide()
		FA_RTbutton1text:SetText("History")
	elseif num == 1 then
		tableMode = 1
		FA_RTscrollingtable2:Show()
		FA_RTscrollingtable:Hide()
		FA_RTbutton1text:SetText("Active Items")
	end
end

FA_RTbutton1:SetScript("OnMouseUp", function(self, button)
	if tableMode == 1 then
		modeSet(0)
	elseif tableMode == 0 then
		modeSet(1)
	end
end) 

function FARaidTools:isThunderforged(iLevel)
	return iLevel == 541 or iLevel == 528
end

function FARaidTools:generateIcons()
	local lasticon = nil -- reference value for anchoring to the most recently constructed icon
	local firsticon = nil -- reference value for anchoring the first constructed icon
	local k = 0 -- this variable contains the number of the icon we're currently constructing, necessary because we need to be able to create multiple icons per entry in the table
	for i=1,13 do -- loop through the table of icons and reset everything
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
					local iconNum = tonumber(string.match(self:GetName(), "%d+$"))
					
					--table select stuff
					iconSelect = FA_RTscrollingtable:GetSelection() or 0 -- store what row was selected so we can restore it later
					FA_RTscrollingtable:SetSelection(iconNum) -- select the row that correlates to the icon
					
					--tooltip stuff
					GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
					GameTooltip:SetHyperlink(v["itemLink"])
					GameTooltip:Show()
					end)
				table_icons[k]:SetScript("OnLeave", function(self, button) -- set code that triggers on mouse exit
					--table select stuff
					FA_RTscrollingtable:SetSelection(iconSelect) -- restore the row that was selected before we mousedover this icon
					iconSelect = nil
					
					--tooltip stuff
					GameTooltip:Hide()
				end)
				table_icons[k]:SetScript("OnMouseUp", function(self, button) -- set code that triggers on clicks
					if button == "LeftButton" then -- left click: Selects the clicked row
						-- retrieve the row id that corresponds to the icon we're mousedover
						local iconNum = tonumber(string.match(self:GetName(), "%d+$"))
						if IsModifiedClick("CHATLINK") or IsModifiedClick("DRESSUP") then
							local j = 0;
							for i, v in pairs(table_items) do
								j = j + 1;
								if j == iconNum then
									if IsModifiedClick("CHATLINK") then
										ChatEdit_InsertLink(v["itemLink"])
									elseif IsModifiedClick("DRESSUP") then
										DressUpItemLink(v["itemLink"])
									end
									break
								end
							end
						else
							-- set iconSelect so that after the user finishes mousing over icons
							-- the row corresponding to this one gets selected
							iconSelect = iconNum
						end
					elseif button == "RightButton" then -- right click: Ends the item, for everyone in raid if you have assist, otherwise only locally.
						--remove command stuff
						endPrompt = coroutine.create( function()
							local iconNum = tonumber(string.match(self:GetName(), "%d+$"))
							local j = 0;
							for i, v in pairs(table_items) do
								j = j + 1;
								if j == iconNum then
									if UnitIsGroupAssistant("PLAYER") or UnitIsGroupLeader("PLAYER") then
										StaticPopupDialogs["FA_RTEND_CONFIRM"]["text"] = "Are you sure you want to manually end "..v["itemLink"].." for all players in the raid?"
									else
										StaticPopupDialogs["FA_RTEND_CONFIRM"]["text"] = "Are you sure you want to manually end "..v["itemLink"].."?"
									end
									StaticPopup_Show("FA_RTEND_CONFIRM")
									coroutine.yield()
									debug("Ending item "..v["itemLink"]..".", 1);
									if UnitIsGroupAssistant("PLAYER") or UnitIsGroupLeader("PLAYER") then
										FARaidTools:sendMessage(ADDON_MSG_PREFIX, {
											["ADDON_VERSION"] = ADDON_VERSION, 
											["end"] = i,
										}, "RAID")
									end
									FARaidTools:itemEnd(i)
									break
								end
							end
						end)
						coroutine.resume(endPrompt)
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
	table_icons[1]:SetPoint("LEFT", FA_RTicons, "LEFT", (401-(k*31))/2, 0) -- anchor the first icon in the row so that the row is centered in the window
end
	
SLASH_RT1 = "/rt"
local function slashparse(msg, editbox)
	if msg == "" then
		FA_RTframe:Show()
	else
		local msg = str_split(" ", msg)
		if msg[1]:lower() == "debug" then
			if #msg == 2 then
				if msg[2]:lower() == "true" then
					debugOn = true
				elseif msg[2]:lower() == "false" then
					debugOn = false
				else
					print("Invalid syntax for /rt "..msg[1]:lower()..". Invalid value for parameter #2.")
				end
			else
				print("Invalid syntax for /rt "..msg[1]:lower()..". Incorrect number of parameters.")
			end
		elseif msg[1]:lower() == "who" then
			if #msg == 1 then
				FARaidTools:sendMessage("FA_RTwho", "query", "GUILD")
			else
				print("Invalid syntax for /rt "..msg[1]:lower()..". Incorrect number of parameters.")
			end
		elseif msg[1]:lower() == "alias" then
			if msg[2]:lower() == "add" then
				if #msg == 3 then
					table.insert(table_aliases, msg[3]:lower())
					print(msg[3].." added as an alias.")
				else
					print("Invalid syntax for /rt "..msg[1]:lower().." "..msg[2]:lower()..". Incorrect number of parameters.")
				end
			elseif msg[2]:lower() == "remove" then
				if #msg == 3 then
					local removed = false
					for i=1,#table_aliases do
						if table_aliases[i]:lower() == msg[3]:lower() then
							table.remove(table_aliases, i)
							print("Alias "..msg[3].." removed.")
							removed = true
							break
						end
					end
					if not removed then
						print(msg[3].." is not currently an alias.")
					end
				else
					print("Invalid syntax for /rt "..msg[1]:lower().." "..msg[2]:lower()..". Incorrect number of parameters.")
				end
			elseif msg[2]:lower() == "list" then
				if #msg == 2 then
					local list = ""
					for i=1,#table_aliases do
						if i > 1 then
							list = list..", "
						end
						list = list..table_aliases[i]
					end
					print("Current aliases are: "..list)
				else
					print("Invalid syntax for /rt "..msg[1]:lower().." "..msg[2]:lower()..". Incorrect number of parameters.")
				end
			else
				print("Invalid subcommand for /rt "..msg[1]:lower()..".")
			end
		elseif msg[1]:lower() == "resetpos" then
			FA_RTframe:ClearAllPoints()
			FA_RTframe:SetPoint("CENTER")
		else
			print("The following are valid commands for /rt:")
			print("/rt debug <true/false> -- set status of debug mode")
			print("/rt who -- see who is running the addon and what version")
			print("/rt alias add <name> -- add an alias for award detection")
			print("/rt alias remove <name> -- remove an alias for award detection")
			print("/rt alias list -- list aliases for award detection")
			print("/rt resetpos -- resets the position of the RT window")
		end
	end
end
SlashCmdList["RT"] = slashparse
SLASH_FAROLL1 = "/faroll"
local function faRoll(value)
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
SlashCmdList["FAROLL"] = faRoll

StaticPopupDialogs["BID_AMOUNT_QUERY"] = {
	text = "How much would you like to bid?",
	button1 = "Bid",
	button2 = CANCEL,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	enterClicksFirstButton = 1,
	OnShow = function (self, data)
		self.editBox:SetText("")
	end,
	OnAccept = function (self2, data, data2)
		StaticDataSave(self2.editBox:GetText())
		coroutine.resume(bidPrompt)
	end,
	hasEditBox = true
}

FA_RTbutton2:SetScript("OnMouseUp", function(self, button)
	if button == "LeftButton" then
		local id = FA_RTscrollingtable:GetSelection()
		local j, itemLink, itemString = 0;
		for i, v in pairs(table_items) do
			j = j + 1;
			if j == id then
				itemLink, itemString = v["itemLink"], i;
			end
		end
		bidPrompt = coroutine.create( function(self)
			StaticPopupDialogs["BID_AMOUNT_QUERY"]["text"] = "How much would you like to bid for "..itemLink.."?"
			StaticPopup_Show("BID_AMOUNT_QUERY")
			debug("Querying for bid, coroutine paused.", 1);
			coroutine.yield()
			debug("Bid recieved, resuming coroutine.", 1)
			bid = tonumber(promptBidValue)
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
			debug("Passed info onto FARaidTools:itemBid().", 1);
			FARaidTools:itemBid(itemString, bid)
		end)
		coroutine.resume(bidPrompt)
	end
end) 

StaticPopupDialogs["FA_RTEND_CONFIRM"] = {
	text = "Are you sure you want to manually end this item for all players in the raid?",
	button1 = YES,
	button2 = CANCEL,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	OnAccept = function()
		coroutine.resume(endPrompt)
	end,
	enterClicksFirstButton = 1
}
StaticPopupDialogs["FA_RTTEXT_EDIT"] = {
	text = "",
	button1 = ACCEPT,
	button2 = CANCEL,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	hasEditBox = true,
	OnShow = function(self)
		self.editBox:SetText(table_mainData[FA_RTscrollingtable:GetSelection()]["cols"][3]["value"] or "")
	end,
	OnAccept = function(self)
		table_mainData[FA_RTscrollingtable:GetSelection()]["cols"][3]["value"] = self.editBox:GetText()
		FA_RTscrollingtable:SetData(table_mainData, false)
	end,
	enterClicksFirstButton = 1
}

function FARaidTools:itemAdd(itemString, checkCache)
	debug("itemAdd(), itemString = "..itemString, 1);
	-- itemString must be a string!
	if type(itemString) ~= "string" then
		debug("itemAdd was passed a non-string value!", 1);
		return;
	end
	local itemLink = ItemLinkAssemble(itemString);
	
	-- caching stuff
	if itemLink then
		for i=1,#table_itemQuery do
			if table_itemQuery[i] == itemString then
				table.remove(table_itemQuery, i)
				break
			end
		end
	else
		if not checkCache then
			debug("Item is not cached, requesting item info from server.")
			table.insert(table_itemQuery, itemString);
		else
			
			debug("Item is not cached, aborting.")
		end
		return;
	end
	
	if table_items[itemString] then
		table_items[itemString]["quantity"] = table_items[itemString]["quantity"] + 1;
		local _, _, _, iLevel, _, _, _, _, _, texture = GetItemInfo(itemLink);
		local displayName = itemLink
		if FARaidTools:isThunderforged(iLevel) then
			displayName = displayName .. THUNDERFORGED;
		end
		if table_items[itemString]["quantity"] > 1 then
			displayName = displayName .. " x" .. table_items[itemString]["quantity"];
		end
		table_items[itemString]["displayName"] = displayName;
	else
		local _, _, _, iLevel, _, _, _, _, _, texture = GetItemInfo(itemLink);
		local displayName = itemLink
		if FARaidTools:isThunderforged(iLevel) then
			displayName = displayName .. THUNDERFORGED;
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
	
	debug(table_items, 2);
	
	FARaidTools:itemTableUpdate();
	
	if not FA_RTframe:IsShown() then
		if UnitAffectingCombat("PLAYER") then
			showAfterCombat = true
			debug(itemLink.." was found but the player is in combat.");
		else
			FA_RTframe:Show()
		end
	end
end

function FARaidTools:itemTableUpdate()
	local t = {};
	
	for i, v in pairs(table_items) do
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
		table.insert(t, {
			["cols"] = {
				{
					["value"] = v["displayName"],
					["args"] = nil,
					["color"] = {["r"] = 1.0, ["g"] = 1.0, ["b"] = 1.0, ["a"] = 1.0},
					["colorargs"] = nil,
					["DoCellUpdate"] = nil,
				},
				{
					["value"] = statusString,
					["args"] = nil,
					["color"] = statusColor,
					["colorargs"] = nil,
					["DoCellUpdate"] = nil,
				},
				{
					["value"] = winnerString,
					["args"] = nil,
					["color"] = {["r"] = 1.0, ["g"] = 1.0, ["b"] = 1.0, ["a"] = 1.0},
					["colorargs"] = wnil,
					["DoCellUpdate"] = nil,
				},
			},
			["color"] = {["r"] = 1.0, ["g"] = 0.0, ["b"] = 0.0, ["a"] = 1.0},
			["colorargs"] = nil,
			["DoCellUpdate"] = nil,
		})
	end

	FA_RTscrollingtable:SetData(t, false)
	FARaidTools:generateIcons()
	
	--[[
	local id
	for i=1,#table_mainData do
		local match = string.match(table_mainData[i]["cols"][1]["value"], HYPERLINK_PATTERN)
		if match == nil then
			print("Error: match returned nil. i="..i)
			DevTools_Dump(table_mainData[i])
			return
		end
		local link1 = ItemLinkStrip(match)
		local link2 = ItemLinkStrip(itemLink)
		if link1 == link2 then
			id = i
			if debugOn then print("addToLootWindow(): Found match in data table. ID #"..id) end
			break
		end
	end
	if id then
		local name = table_mainData[id]["cols"][1]["value"]
		local quantity = tonumber(string.match(name, "]\124h\124rx(%d+)")) or 1
		local thunderforged = ""
		if string.match(name, "Thunderforged") then
			thunderforged = " |cFF00FF00(Thunderforged)|r"
		end
		table_mainData[id]["cols"][1]["value"] = string.match(table_mainData[id]["cols"][1]["value"], HYPERLINK_PATTERN).."x"..tostring(quantity+1)..thunderforged
	else
		local thunderforged = ""
		if FARaidTools:isThunderforged(iLevel) then
			thunderforged = " |cFF00FF00(Thunderforged)|r"
		end
		
		local name = itemLink..thunderforged
	
		
	end
	FA_RTscrollingtable:SetData(t, false)
	FARaidTools:generateIcons()
	--]]
end

function FARaidTools:itemBid(itemString, bid)
	bid = tonumber(bid)
	debug("FARaidTools:itemBid("..itemString..", "..bid..")", 1)
	if not table_items[itemString] then
		debug("Item not found! Aborting.", 1);
		return;
	end
	
	if table_items[itemString]["host"] and table_items[itemString]["status"] == "Tells"
	and ((table_items[itemString]["currentValue"] == 30 and bid >= 30)
	or table_items[itemString]["currentValue"] == bid) then
		SendChatMessage(tostring(bid), "WHISPER", nil, table_items[itemString]["host"])
		table.insert(table_bids, {itemString, bid, "Waiting to roll..."});
		FA_RTscrollingtable3:SetData(table_bids, true);
		FA_RTbidframe:Show(); -- we know there's bids/rolls waiting now so let's show the frame
		debug("FARaidTools:itemBid(): Bid and queued roll for "..table_items[itemString]["itemLink"]..".", 1);
	else
		table.insert(table_bids, {itemString, bid, "Waiting to bid..."})
		FA_RTscrollingtable3:SetData(table_bids, true)
		FA_RTbidframe:Show() -- we know there's bids/rolls waiting now so let's show the frame
		debug("FARaidTools:itemBid(): Queued bid for "..table_items[itemString]["itemLink"]..".", 1);
	end
end

function FARaidTools:itemEnd(itemString) -- itemLink or ID
	if table_items[itemString] then
		table_items[itemString]["status"] = "Ended";
		table_items[itemString]["expirationTime"] = GetTime();
	end
	FARaidTools:itemTableUpdate();
end

function FARaidTools:itemRemove(itemString)
	table_items[itemString] = nil;
	FARaidTools:itemTableUpdate();
end

function FARaidTools:checkBids()
	local table_size = #table_bids
	for i=0,table_size-1 do
		local itemString, bid, status = table_bids[table_size-i][1], table_bids[table_size-i][2], table_bids[table_size-i][3]
		if table_items[itemString]["host"] and ((table_items[itemString]["currentValue"] == 30 and bid >= 30) or table_items[itemString]["currentValue"] == bid) then
			if status == "Waiting to bid..." and table_items[itemString]["status"] == "Tells" then
				SendChatMessage(tostring(bid), "WHISPER", nil, table_items[itemString]["host"]);
				table_bids[table_size-i][3] = "Waiting to roll...";
				FA_RTscrollingtable3:SetData(table_bids, true);
				debug("FARaidTools:itemBid(): Bid and queued roll for "..table_items[itemString]["itemLink"]..".", 1);
			elseif status == "Waiting to roll..." and table_items[itemString]["status"] == "Rolls" then
				faRoll(bid);
				table.remove(table_bids, table_size-i);
				debug("FARaidTools:itemBid(): Rolled for "..table_items[itemString]["itemLink"]..".", 1);
			end
		end
	end
	
	if #table_bids == 0 then -- if the table is empty now we need to hide it
		FA_RTbidframe:Hide()
	end
end

local function onUpdate(self,elapsed)
	local currentTime = GetTime() -- get the time and put it in a variable so we don't have to call it a billion times throughout this function
	
	--check if it's time to remove any expired items
	for i, v in pairs(table_items) do
		if v["expirationTime"] and v["expirationTime"] + expTime <= currentTime then
			debug(v["itemLink"].." has expired, removing.", 1);
			FARaidTools:itemRemove(i);
		end
	end
	
	--enable/disable buttons
	if FA_RTscrollingtable:GetSelection() == nil or FA_RTscrollingtable:GetSelection() == 0 or iconSelect == 0 then
		FA_RTbutton2:Disable()
		FA_RTbutton3:Disable()
	else
		FA_RTbutton2:Enable()
		if UnitIsGroupAssistant("PLAYER") or UnitIsGroupLeader("PLAYER") or debugOn then
			FA_RTbutton3:Enable()
		end
	end
	
	-- /rt who stuff
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

local function saveLootSettings()
	lootSettings = {GetCVar("autoLootDefault"), GetModifiedClick("AUTOLOOTTOGGLE")}
	return lootSettings
end

function FARaidTools:restoreLootSettings()
	SetCVar("autoLootDefault", lootSettings[1])
	SetModifiedClick("AUTOLOOTTOGGLE", lootSettings[2])
end

function FARaidTools:setAutoLoot(suppress)
	if (GetLootMethod() == "freeforall" and addonEnabled()) or debugOn then
		--if not UnitIsGroupAssistant("PLAYER") and not UnitIsGroupLeader("PLAYER") then
			if GetCVar("autoLootDefault") == "1" then
				SetModifiedClick("AUTOLOOTTOGGLE", "NONE")
				SetCVar("autoLootDefault", 0)
				if not suppress then print("RT: Autoloot is now off.") end
			end
		--end
	else
		if GetCVar("autoLootDefault") == "0" then
			FARaidTools:restoreLootSettings()
			if not suppress then print("RT: Autoloot has been restored to your previous settings.") end
		end
	end
end

local function setGeneralVis() -- currently not used
	if addonEnabled() then
		if IsResting() == false then
			ChatFrame_RemoveChannel(DEFAULT_CHAT_FRAME, "General")
		else
			ChatFrame_AddChannel(DEFAULT_CHAT_FRAME, "General")
		end
	else
		ChatFrame_AddChannel(DEFAULT_CHAT_FRAME, "General")
	end
end

function FARaidTools:parseChat(msg, author)
	if not debugOn then
		for i=1,40 do
			local name, rank_ = GetRaidRosterInfo(i)
			if name == author then
				rank = rank_
				break
			end
		end
	end
	if debugOn or (rank and rank > 0) then
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
					
					winners = str_split(", ", value);
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
						if table_items[itemString]["currentValue"] == 30 then
							cost = "30+"
						else
							cost = tostring(table_items[itemString]["currentValue"]);
						end
						if not table_items[itemString]["winners"][cost] then
							table_items[itemString]["winners"][cost] = {};
						end
						table.insert(table_items[itemString]["winners"][cost], winners[i]);
						
						if string.match(winners[i], UnitName("player"):lower()) then -- if the player is one of the winners
							debug("The player won an item!", 1)
							LootWonAlertFrame_ShowAlert(table_items[itemString]["itemLink"], 1--[[, LOOT_ROLL_TYPE_NEED, "xx DKP"--]]) -- TODO: Specify the exact amount the person bid as the need value
						else
							for j=1,#table_aliases do
								if string.match(winners[i], table_aliases[j]) then
									debug("The player won an item!", 1)
									LootWonAlertFrame_ShowAlert(table_items[itemString]["itemLink"], 1--[[, LOOT_ROLL_TYPE_NEED, "xx DKP"--]]) -- TODO: Specify the exact amount the person bid as the need value
								end
							end
						end
						
						local numWinners = 0;
						for j, v in pairs(table_items[itemString]["winners"]) do
							numWinners = numWinners + #v;
						end
						debug("numWinners = "..numWinners, 1);
						if numWinners >= table_items[itemString]["quantity"] then
							FARaidTools:itemEnd(itemString);
							break;
						end
					end
				end
				FARaidTools:itemTableUpdate();
				FARaidTools:checkBids();
			end
		end
	end
end

function FARaidTools:dataDump(name)
	if name == "hasBeenLooted" then
		DevTools_Dump(hasBeenLooted)
	elseif name == "mainData" then
		DevTools_Dump(table_mainData)
	elseif name == "itemQuery" then
		DevTools_Dump(table_itemQuery)
	elseif name == "bids" then
		DevTools_Dump(table_bids)
	elseif name == "expTimes" then
		DevTools_Dump(table_expTimes)
	elseif name == "nameAssociations" then
		DevTools_Dump(table_nameAssociations)
	end
end
	
local frame, events = CreateFrame("Frame"), {}
function events:ADDON_LOADED(name)
	if name == ADDON_NAME then
		if table_options then -- if options loaded, then load into local variables
			lootSettings = table_options[1] or saveLootSettings()
			history = history or {}
			table_aliases = table_options[2] or table_aliases
		else -- if not, set to default values
			saveLootSettings()
			history = {}
		end
		FA_RTscrollingtable2:SetData(history, true)
		FARaidTools:RegisterComm(ADDON_MSG_PREFIX);
	end
end
function events:PLAYER_LOGOUT(...)
	FARaidTools:restoreLootSettings()
	table_options = {lootSettings, table_aliases}
end
function events:PLAYER_ENTERING_WORLD(...)
	FARaidTools:setAutoLoot(1)
end
function events:RAID_ROSTER_UPDATE(...)
	FARaidTools:setAutoLoot()
end
function events:LOOT_OPENED(...)
	if not addonEnabled() then
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
				
				local link = GetLootSlotLink(i) -- retrieve link of item
				if link and FARaidTools:checkFilters(link) then
					for l=1,max(sourceInfo[j*2], 1) do -- repeat the insert if there is multiple of the item in that slot.
						-- max() is there to remedy the bug with GetLootSourceInfo returning incorrect (0) values.
						-- GetLootSourceInfo may also return multiple quantity when there is actually only
						-- one of the item, but there's not much we can do about that.
						table.insert(loot[mobID], ItemLinkStrip(link));
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
	for i, v in pairs(loot) do
		if not (v["checkSum"] and v["checkSum"] == #v) then
			debug("Loot data recieved via an addon message failed the integrity check.");
			return;
		end
	end
	
	-- send addon message to tell others to add this to their window
	FARaidTools:sendMessage(ADDON_MSG_PREFIX, {
		["ADDON_VERSION"] = ADDON_VERSION,
		["loot"] = loot,
	}, "RAID", nil, "BULK");
	
	for i, v in pairs(loot) do
		for j=1,#v do
			-- we can assume that everything in the table is not on the HBL
			
			if FARaidTools:checkFilters(v[j], true) then
				FARaidTools:itemAdd(v[j])
			end
		end
		hasBeenLooted[i] = true;
	end
end
function events:CHAT_MSG_RAID(msg, author)
	FARaidTools:parseChat(msg, author)
end
function events:CHAT_MSG_RAID_LEADER(msg, author)
	FARaidTools:parseChat(msg, author)
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
		if msg == "" then
			return;
		end
		local msg = string.lower(msg) -- put in lower case
		local msg = " "..string.gsub(msg, "[/,]", " ").." "
		if string.match(msg, " d%s?e ") or string.match(msg, " disenchant ") then
			if UnitIsGroupAssistant("PLAYER") or UnitIsGroupLeader("PLAYER") then
				FARaidTools:sendMessage(ADDON_MSG_PREFIX, {
					["ADDON_VERSION"] = ADDON_VERSION,
					["end"] = itemString,
				}, "RAID")
			end
			FARaidTools:itemEnd(itemString);
		end
	end
end
function events:GROUP_JOINED()
	if IsInRaid() then
		FARaidTools:sendMessage("FA_RTupdate", {ADDON_VERSION_FULL}, "RAID", nil, "BULK")
	end
end
function events:CVAR_UPDATE(glStr, value)
	if glStr == "AUTO_LOOT_DEFAULT_TEXT" and not addonEnabled() then
		if debugOn then print("Autoloot settings saved.") end
		saveLootSettings()
	end
end
function events:PLAYER_REGEN_ENABLED()
	if showAfterCombat then
		FA_RTframe:Show()
		showAfterCombat = false
	end
end
function events:GET_ITEM_INFO_RECEIVED()
	local limit = #table_itemQuery
	for i=0,limit-1 do
		FARaidTools:itemAdd(table_itemQuery[limit-i], true)
	end
end
frame:SetScript("OnEvent", function(self, event, ...)
	events[event](self, ...) -- call one of the functions above
end)
for k, v in pairs(events) do
	frame:RegisterEvent(k) -- Register all events for which handlers have been defined
end

if debugOn then
	FARaidTools:itemAdd("96379:0")
	FARaidTools:itemAdd("96753:0")
	FARaidTools:itemAdd("96740:0")
	FARaidTools:itemAdd("96373:0")
	FARaidTools:itemAdd("96377:0")
	FARaidTools:itemAdd("96384:0")
	FARaidTools:parseChat("|cffa335ee|Hitem:96740:0:0:0:0:0:0:0:0:0:445|h[Sign of the Bloodied God]|h|r 30", UnitName("PLAYER"))
end
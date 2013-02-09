-- Load the libraries
FARaidTools = LibStub("AceAddon-3.0"):NewAddon("FARaidTools")
LibStub("AceComm-3.0"):Embed(FARaidTools)

local ScrollingTable = LibStub("ScrollingTable")
local libSerialize = LibStub:GetLibrary("AceSerializer-3.0")
local libCompress = LibStub:GetLibrary("LibCompress")
local libEncode = libCompress:GetAddonEncodeTable()

-- Declare local variables
local hyperlinkPattern = "\124%x+\124Hitem:%d+:%d+:%d+:%d+:%d+:%d+:%-?%d+:%-?%d+:?%d*:?%d*:?%d*:?%d*:?%d*:?%d*:?%d*\124h.-\124h\124r"
--				"|cffa335ee|Hitem:71472:0:0:0:0:0:0:0:90:0:0|h[Flowform Choker]|h|r"
local downloadUrl = "http://tinyurl.com/FARaidTools"

local table_mainData = {}
local table_bids = {}
local table_itemQuery = {}
local table_expTimes = {}
local table_nameAssociations = {}
local table_icons = {}
local table_who = {}
local table_aliases = {}

local debugOn = false
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
local addonVersion
local addonVersionFull
local updateMsg = nil

--helper functions

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

local function stripItemData(itemLink)
	if itemLink then
		local _, _, Color, Ltype, Id, Enchant, Gem1, Gem2, Gem3, Gem4, Suffix, Unique, LinkLvl, reforging, Name = string.find(itemLink, "|?c?f?f?(%x*)|?H?([^:]*):?(%d+):?(%d*):?(%d*):?(%d*):?(%d*):?(%d*):?(%-?%d*):?(%-?%d*):?(%d*):?(%d*):%d+|?h?%[?([^%[%]]*)%]?|?h?|?r?")
		return "|"..Color.."|Hitem:"..Id..":"..Suffix.."|h["..Name.."]|h|r"
	elseif debugOn then
		print("stripItemData was passed a nil value!")
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
	local _, instanceType = IsInInstance()
	if isGuildGroup(0.60) and isMainRaid() and instanceType == "raid" and GetInstanceDifficulty() ~= 8 and GetNumGroupMembers() >= 20 then
		return 1
	elseif debugOn then
		return 1
	else
		if not isGuildGroup(0.60) then
			return nil, "not guild group"
		elseif not isMainRaid() then
			return nil, "not enough officers"
		elseif not instanceType == "raid" then
			return nil, "wrong instance type"
		elseif not GetInstanceDifficulty() ~= 8 then
			return nil, "wrong instance difficulty"
		elseif not GetNumGroupMembers() >= 20 then
			return nil, "not enough group members"
		end
	end
end

function FARaidTools:addonEnabled()
	return addonEnabled()
end

local function checkFilters(link, checkItemLevel)
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
	if class == "Armor" or class == "Weapon" then
		-- check if the item level of the item is high enough
		local playerTotal = GetAverageItemLevel()
		if checkItemLevel and playerTotal - ilevel > 20 then -- if the item is more than 20 levels below the player
			if debugOn then print("Item Level of "..link.." is too low.") end
			return false
		end
	elseif not class == "Miscellaneous" and subClass == "Junk" then
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
	
	if debugOn then DevTools_Dump(text) end
	
	if prefix == "FA_RTreport" and text[1] == addonVersion then
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
				if checkFilters(data[i], true) then
					FARaidTools:cacheItem(data[i])
				end
			end
			table.insert(hasBeenLooted, mobID)
		end
	elseif prefix == "FA_RTend" and text[1] == addonVersion then
		local itemLink = text[2]
		
		if itemLink then
			FARaidTools:endItem(itemLink)
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
			FARaidTools:sendMessage("FA_RTwho", {"response", addonVersionFull}, "WHISPER", sender)
		end
	elseif prefix == "FA_RTupdate" then
		if distribution == "WHISPER" then
			if not updateMsg then
				print("Your current version of FARaidTools is not up to date! Please go to "..downloadUrl.." to update.")
				updateMsg = true
			end
		elseif distribution == "RAID" or distribution == "GUILD" then
			local version = text[1]
			if version < addonVersionFull then
				FARaidTools:sendMessage("FA_RTupdate", {}, "WHISPER", sender)
			elseif not updateMsg then
				if addonVersionFull < version then
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
FA_RTbutton1text:SetText("Mode")
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
	elseif num == 1 then
		tableMode = 1
		FA_RTscrollingtable2:Show()
		FA_RTscrollingtable:Hide()
	end
end

FA_RTbutton1:SetScript("OnMouseUp", function(self, button)
	if tableMode == 1 then
		modeSet(0)
	elseif tableMode == 0 then
		modeSet(1)
	end
end) 

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
	for i=1,#table_mainData do -- loop through each row of data
		local itemIcon = GetItemIcon(table_mainData[i]["cols"][1]["value"]) -- retrieve path to item icon
		local itemCount = tonumber(string.match(table_mainData[i]["cols"][1]["value"], "]\124h\124rx(%d+)")) or 1 -- parse how many there are of this item so we know how many icons to create
		for j=1,itemCount do
			if k < #table_icons then -- if we're constructing an icon number that's higher than what we're setup to display then just skip it
				k = k + 1 -- increment k by 1 before starting to construct
				table_icons[k]:SetBackdrop({ -- set the texture of the icon
					bgFile = itemIcon,
				})
				table_icons[k]:SetScript("OnEnter", function(self, button) -- set code that triggers on mouse enter
					local iconNum = tonumber(string.match(self:GetName(), "%d+$"))
					local total = 0
					local id
					for i=1,#table_mainData do -- figure out what row of data associates to this icon by counting up the quanities of each row
						local quantity = tonumber(string.match(table_mainData[i]["cols"][1]["value"], "]\124h\124rx(%d+)")) or 1
						total = total + quantity
						if total >= iconNum then
							id = i
							break
						end
					end
					
					--table select stuff
					iconSelect = FA_RTscrollingtable:GetSelection() -- store what row was selected so we can restore it later
					FA_RTscrollingtable:SetSelection(id) -- select the row that correlates to the icon
					
					--tooltip stuff
					GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
					GameTooltip:SetHyperlink(string.match(table_mainData[id]["cols"][1]["value"], hyperlinkPattern))
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
						local iconNum = tonumber(string.match(self:GetName(), "%d+$"))
						local total = 0
						local id
						for i=1,#table_mainData do -- figure out what row of data associates to this icon by counting up the quanities of each row
							local quantity = tonumber(string.match(table_mainData[i]["cols"][1]["value"], "]\124h\124rx(%d+)")) or 1
							total = total + quantity
							if total >= iconNum then
								id = i
								break
							end
						end
						
						--table select stuff
						iconSelect = id
					end
					if button == "RightButton" then -- right click: Ends the item, for everyone in raid if you have assist, otherwise only locally.
						--remove command stuff
						endPrompt = coroutine.create( function()
							local iconNum = tonumber(string.match(self:GetName(), "%d+$"))
							local total = 0
							local id
							for i=1,#table_mainData do -- figure out what row of data associates to this icon by counting up the quantities of each row
								local quantity = tonumber(string.match(table_mainData[i]["cols"][1]["value"], "]\124h\124rx(%d+)")) or 1
								total = total + quantity
								if total >= iconNum then
									id = i
									break
								end
							end
							local msg = string.match(table_mainData[id]["cols"][1]["value"], hyperlinkPattern)
							if UnitIsGroupAssistant("PLAYER") or UnitIsGroupLeader("PLAYER") then
								StaticPopupDialogs["FA_RTEND_CONFIRM"]["text"] = "Are you sure you want to manually end "..msg.." for all players in the raid?"
							else
								StaticPopupDialogs["FA_RTEND_CONFIRM"]["text"] = "Are you sure you want to manually end "..msg.."?"
							end
							StaticPopup_Show("FA_RTEND_CONFIRM")
							coroutine.yield()
							if UnitIsGroupAssistant("PLAYER") or UnitIsGroupLeader("PLAYER") then
								FARaidTools:sendMessage("FA_RTend", {addonVersion, msg}, "RAID")
							end
							FARaidTools:endItem(id)
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

local function FA_RTbid(itemLink, bid)
	bid = tostring(bid)
	if debugOn then print("FA_RTbid("..itemLink..", "..bid..")") end
	local name = nil
	for i=1,#table_nameAssociations do
		if stripItemData(table_nameAssociations[i][1]) == stripItemData(itemLink) then
			name = table_nameAssociations[i][2]
			break
		end
	end
	local id = nil
	for i=1,#table_mainData do
		if stripItemData(string.match(table_mainData[i]["cols"][1]["value"], hyperlinkPattern)) == stripItemData(itemLink) then
			id = i
			break
		end
	end
	if id == nil then
		if debugOn then print("bid(): ID returned nil, aborting.") end
		return
	end
	local sent = true
	if name == nil then sent = false end
	if string.match(table_mainData[id]["cols"][2]["value"], "(Tells)") then
		local at = tonumber(string.match(table_mainData[id]["cols"][2]["value"], "^%d%d"))
		if at == tonumber(bid) or (at == 30 and tonumber(bid) > 30) then
			SendChatMessage(tostring(bid), "WHISPER", nil, name)
			table.insert(table_bids, {itemLink, bid, "Waiting to roll..."})
		else
			sent = false
		end
	else
		sent = false
	end
	if sent == false then
		table.insert(table_bids, {itemLink, bid, "Waiting to bid..."})
		FA_RTscrollingtable3:SetData(table_bids, true)
		if debugOn then print("FA_RTbid(): Queued bid.") end
	else
		if debugOn then print("FA_RTbid(): Sent bid.") end
	end
end

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
		local link = string.match(table_mainData[id]["cols"][1]["value"], hyperlinkPattern)
		bidPrompt = coroutine.create( function(self)
			StaticPopupDialogs["BID_AMOUNT_QUERY"]["text"] = "How much would you like to bid for "..string.match(table_mainData[FA_RTscrollingtable:GetSelection()]["cols"][1]["value"], hyperlinkPattern).."?"
			StaticPopup_Show("BID_AMOUNT_QUERY")
			if debugOn then print("Querying for bid, coroutine paused.") end
			coroutine.yield()
			if debugOn then print("Bid recieved, resuming coroutine.") end
			promptBidValue = tonumber(promptBidValue)
			if promptBidValue < 30 and promptBidValue ~= 10 and promptBidValue ~= 20 then
				print("You must bid 10, 20, 30, or a value greater than 30. Your bid has been cancelled.")
				return
			end
			if promptBidValue % 2 ~= 0 then
				print("You are not allowed to bid odd numbers or non-integers. Your bid has been rounded down to the nearest even integer.")
				promptBidValue = math.floor(promptBidValue)
				if promptBidValue % 2 == 1 then
					promptBidValue = promptBidValue - 1
				end
			end
			if debugOn then print("Passed info onto FA_RTbid().") end
			FA_RTbid(link, promptBidValue)
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

function FARaidTools:valueFormat(itemLink, value)
	if debugOn then print("valueFormat("..itemLink..", "..tostring(value)..")") end
	local id
	for i=1,#table_mainData do
		if stripItemData(string.match(table_mainData[i]["cols"][1]["value"], hyperlinkPattern)) == stripItemData(itemLink) then
			id = i
			if debugOn then print("valueFormat(): Found match in data table. ID #"..id) end
			break
		end
	end
	if not id then
		if debugOn then print("valueFormat(): No match found in data table. Aborting.") end
		return
	end
	local message_value = string.match(value, "[321]0")
	local table_value = string.match(table_mainData[id]["cols"][2]["value"], "[321]0")
	if message_value then
		table_mainData[id]["cols"][2]["value"] = message_value.." (Tells)"
		table_mainData[id]["cols"][2]["color"]["r"] = 0
		table_mainData[id]["cols"][2]["color"]["g"] = 1
		table_mainData[id]["cols"][2]["color"]["b"] = 0
		table_mainData[id]["cols"][2]["color"]["a"] = 1
	elseif string.match(string.lower(value), "roll") then
		if table_value then
			table_mainData[id]["cols"][2]["value"] = table_value.." (Rolls)"
		end
		table_mainData[id]["cols"][2]["color"]["r"] = 1
		table_mainData[id]["cols"][2]["color"]["g"] = 0
		table_mainData[id]["cols"][2]["color"]["b"] = 0
		table_mainData[id]["cols"][2]["color"]["a"] = 1
	else
		-- do some stuff to replace a bunch of ways that people could potentially list multiple winners with commas
		value = string.gsub(value, "%sand%s", ", ")
		value = string.gsub(value, "%s?&%s?", ", ")
		value = string.gsub(value, "%s?/%s?", ", ")
		value = string.gsub(value, "%s?\+%s?", ", ")
		
		if table_mainData[id]["cols"][3]["value"] ~= "" then -- if the winner list is not empty we need to add a comma before adding the name
			table_mainData[id]["cols"][3]["value"] = table_mainData[id]["cols"][3]["value"]..", " -- add a comma
		end
		if string.match(table_mainData[id]["cols"][2]["value"], "30") then
			table_mainData[id]["cols"][3]["value"] = table_mainData[id]["cols"][3]["value"]..string.gsub(value, ",", " (30+),").." (30+)" -- add name followed by 30+
		elseif string.match(table_mainData[id]["cols"][2]["value"], "20") then
			table_mainData[id]["cols"][3]["value"] = table_mainData[id]["cols"][3]["value"]..string.gsub(value, ",", " (20),").." (20)" -- add name followed by 20
		elseif string.match(table_mainData[id]["cols"][2]["value"], "10") then
			table_mainData[id]["cols"][3]["value"] = table_mainData[id]["cols"][3]["value"]..string.gsub(value, ",", " (10),").." (10)" -- add name followed by 10
		end
		
		if string.match(value:lower(), UnitName("player"):lower()) then -- if the player is one of the winners
			if debugOn then print("The player won an item!") end
			LootWonAlertFrame_ShowAlert(string.match(table_mainData[id]["cols"][1]["value"], hyperlinkPattern), 1--[[, LOOT_ROLL_TYPE_NEED, "xx DKP"--]]) -- TODO: Specify the exact amount the person bid as the need value
		else
			for i=1,#table_aliases do
				if string.match(value:lower(), table_aliases[i]) then
					if debugOn then print("The player won an item!") end
					LootWonAlertFrame_ShowAlert(string.match(table_mainData[id]["cols"][1]["value"], hyperlinkPattern), 1--[[, LOOT_ROLL_TYPE_NEED, "xx DKP"--]]) -- TODO: Specify the exact amount the person bid as the need value
				end
			end
		end
	end
	if table_mainData[id]["cols"][3]["value"] == "" then
		wincount = 0
	else
		wincount = #str_split(",", table_mainData[id]["cols"][3]["value"])
	end
	itemcount = string.match(table_mainData[id]["cols"][1]["value"], "x(%d+)$")
	if itemcount then
		itemcount = tonumber(itemcount)
	else
		itemcount = 1
	end
	if wincount >= itemcount then
		FARaidTools:endItem(id)
	else
		FA_RTscrollingtable:SetData(table_mainData, false) -- this is done in the endItem function so we only need to do it here
	end
end

function FARaidTools:addToLootWindow(itemLink)
	--if debugOn then print("addToLootWindow("..itemLink..")") end
	local id
	for i=1,#table_mainData do
		local match = string.match(table_mainData[i]["cols"][1]["value"], hyperlinkPattern)
		if match == nil then
			print("Error: match returned nil. i="..i)
			DevTools_Dump(table_mainData[i])
		end
		local link1 = stripItemData(match)
		local link2 = stripItemData(itemLink)
		if link1 == link2 then
			id = i
			if debugOn then print("addToLootWindow(): Found match in data table. ID #"..id) end
			break
		end
	end
	if id then
		local quantity = tonumber(string.match(table_mainData[id]["cols"][1]["value"], "]\124h\124rx(%d+)")) or 1
		table_mainData[id]["cols"][1]["value"] = string.match(table_mainData[id]["cols"][1]["value"], hyperlinkPattern).."x"..tostring(quantity+1)
	else
		local cell1 = {
		    ["value"] = itemLink,
		    ["args"] = nil,
		    ["color"] = {
			["r"] = 1.0,
			["g"] = 1.0,
			["b"] = 1.0,
			["a"] = 1.0,
		    },
		    ["colorargs"] = nil,
		    ["DoCellUpdate"] = nil,
		}
		local cell2 = {
		    ["value"] = "30",
		    ["args"] = nil,
		    ["color"] = {
			["r"] = 0.5,
			["g"] = 0.5,
			["b"] = 0.5,
			["a"] = 1.0,
		    },
		    ["colorargs"] = nil,
		    ["DoCellUpdate"] = nil,
		}
		local cell3 = {
		    ["value"] = "",
		    ["args"] = nil,
		    ["color"] = {
			["r"] = 1.0,
			["g"] = 1.0,
			["b"] = 1.0,
			["a"] = 1.0,
		    },
		    ["colorargs"] = nil,
		    ["DoCellUpdate"] = nil,
		}
		table.insert(table_mainData, {
		    ["cols"] = {cell1, cell2, cell3},
		    ["color"] = {
			["r"] = 1.0,
			["g"] = 0.0,
			["b"] = 0.0,
			["a"] = 1.0,
		    },
		    ["colorargs"] = nil,
		    ["DoCellUpdate"] = nil,
		})
	end
	FA_RTscrollingtable:SetData(table_mainData, false)
	FARaidTools:generateIcons()
	if not FA_RTframe:IsShown() then
		if UnitAffectingCombat("PLAYER") then
			showAfterCombat = true
			print("RT: "..itemLink.." was found but the player is in combat.")
		else
			FA_RTframe:Show()
		end
	end
end

function FARaidTools:cacheItem(itemLink)
	if debugOn then print("cacheItem("..itemLink..")") end
	itemName = GetItemInfo(itemLink)
	if itemName == nil then -- check if item is cached or if we need to query it from the server
		if debugOn then print("cacheItem(): Item info for item "..itemLink.." requested from server.") end
		if #table_itemQuery == 0 then
			table.insert(table_itemQuery, GetTime()+(cacheInterval/1000)) -- add a time so that it onupdate knows when to check if the data is ready yet
		end
		table.insert(table_itemQuery, itemLink) -- add to the query queue
	else
		if debugOn then print("cacheItem(): Item already cached, adding to loot window.") end
		FARaidTools:addToLootWindow(itemLink) -- item is already cached so we can just add it now
	end
end

function FARaidTools:endItem(input) -- itemLink or ID
	local id
	if type(input) == "string" then
		for i=1,#table_mainData do
			local link = stripItemData(string.match(table_mainData[i]["cols"][1]["value"], hyperlinkPattern))
			local link2 = stripItemData(input)
			if link == link2 then
				id = i
				break
			end
		end
	elseif type(input) == "number" then
		id = input
	end
	if id then
		table_mainData[id]["cols"][2]["value"] = "Ended"
		table_mainData[id]["cols"][2]["color"]["r"] = 0.5
		table_mainData[id]["cols"][2]["color"]["g"] = 0.5
		table_mainData[id]["cols"][2]["color"]["b"] = 0.5
		table_mainData[id]["cols"][2]["color"]["a"] = 1
		FA_RTscrollingtable:SetData(table_mainData, false)
		table.insert(table_expTimes, {string.match(table_mainData[id]["cols"][1]["value"], hyperlinkPattern), GetTime()})
	end
end

function FARaidTools:removeItem(itemLink)
	local id
	for i=1,#table_mainData do
		link1 = stripItemData(string.match(table_mainData[i]["cols"][1]["value"], hyperlinkPattern))
		link2 = stripItemData(itemLink)
		if link1 == link2 then
			id = i
			if debugOn then print("removeItem(): Found match in data table. ID #"..id) end
			break
		end
	end
	if id == nil then
		if debugOn then print("removeItem(): No match found in data table. Aborting.") end
		return
	end
	table.remove(table_mainData, id)
	FA_RTscrollingtable:SetData(table_mainData, false)
	
	--clear name association entries for this item
	local table_size = #table_nameAssociations
	for i=0,table_size-1 do
		if stripItemData(string.match(table_nameAssociations[table_size-i][1], hyperlinkPattern)) == stripItemData(itemLink) then
			table.remove(table_nameAssociations, table_size-i)
		end
	end
	
	--clear queued bids or rolls for this item
	local table_size = #table_bids
	for i=0,table_size-1 do
		if stripItemData(string.match(table_bids[table_size-i][1], hyperlinkPattern)) == stripItemData(itemLink) then
			table.remove(table_bids, table_size-i)
		end
	end
	FARaidTools:generateIcons()
end

local function onUpdate(self,elapsed)
	--check if it's time to remove any expired items
	local tableSize = #table_expTimes
	local currentTime = GetTime()
	for i=0,tableSize-1 do -- loop backwards through table of all expired items
		if currentTime >= table_expTimes[tableSize-i][2] + expTime then
			local id
			for j=1,#table_mainData do -- loop through data table
				if stripItemData(string.match(table_mainData[j]["cols"][1]["value"], hyperlinkPattern)) == stripItemData(table_expTimes[tableSize-i][1]) then
					id = j
					if debugOn then print("onUpdate/remove: Found match in data table. ID #"..id) end
					break
				end
			end
			if id then
				table.insert(history, 1, {date(), table_mainData[id]["cols"][1]["value"], table_mainData[id]["cols"][3]["value"]}) -- add entry to history table
				FA_RTscrollingtable2:SetData(history, true)
				
				FARaidTools:removeItem(table_expTimes[tableSize-i][1]) -- remove entry from data table
				FA_RTscrollingtable:SetData(table_mainData, false)
				
				table.remove(table_expTimes, tableSize-i)
			else
				table.remove(table_expTimes, tableSize-i)
				if debugOn then print("onUpdate/remove: Found and removed invalid table_expTimes entry. ID #"..tableSize-i) end
			end
		end
	end
	
	--enable/disable buttons
	-- TODO: Make this so it doesn't flash in interaction with iconSelect
	if FA_RTscrollingtable:GetSelection() and not iconSelect then
		FA_RTbutton2:Enable()
		if UnitIsGroupAssistant("PLAYER") or UnitIsGroupLeader("PLAYER") or not UnitInRaid("PLAYER") then
			FA_RTbutton3:Enable()
		end
	else
		FA_RTbutton2:Disable()
		FA_RTbutton3:Disable()
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
	
	-- table_bids stuff
	-- FIXME: cpu excessive
	-- TODO: fix
	FA_RTscrollingtable3:SetData(table_bids, true)
	if #table_bids == 0 then
		FA_RTbidframe:Hide()
	else
		FA_RTbidframe:Show()
	end
	local table_size = #table_bids
	for i=0,table_size-1 do
		local id = nil
		for j=1,#table_mainData do
			if stripItemData(table_bids[table_size-i][1]) == stripItemData(string.match(table_mainData[j]["cols"][1]["value"], hyperlinkPattern)) then
				id = j
			end
		end
		local name = nil
		for j=1,#table_nameAssociations do
			if stripItemData(table_nameAssociations[j][1]) == stripItemData(table_bids[table_size-i][1]) then
				name = table_nameAssociations[j][2]
				break
			end
		end
		local bid = table_bids[table_size-i][2]
		local executed = false
		if string.match(table_mainData[id]["cols"][2]["value"], "(Tells)") and table_bids[table_size-i][3] == "Waiting to bid..." then
			local at = tonumber(string.match(table_mainData[id]["cols"][2]["value"], "^%d%d"))
			if at == tonumber(bid) then
				SendChatMessage(tostring(bid), "WHISPER", nil, name)
				executed = 1
			elseif at == 30 and tonumber(bid) > 30 then
				SendChatMessage(tostring(bid), "WHISPER", nil, name)
				executed = 1
			end
		elseif string.match(table_mainData[id]["cols"][2]["value"], "(Rolls)") and table_bids[table_size-i][3] == "Waiting to roll..." then
			local at = tonumber(string.match(table_mainData[id]["cols"][2]["value"], "^%d%d"))
			if at == tonumber(bid) then
				faRoll(bid)
				executed = 2
			elseif at == 30 and tonumber(bid) > 30 then
				faRoll(bid)
				executed = 2
			end
		end
		if executed == 2 then
			table.remove(table_bids, table_size-i)
			FA_RTscrollingtable3:SetData(table_bids, true)
		elseif executed == 1 then
			table_bids[table_size-i][3] = "Waiting to roll..."
			FA_RTscrollingtable3:SetData(table_bids, true)
		end
	end
	
	-- Item caching stuff
	if table_itemQuery[1] and currentTime > table_itemQuery[1] then
		if debugOn then print("Checking for item info for "..(#table_itemQuery-1).." items...") end
		table_itemQuery[1] = currentTime+(cacheInterval/1000)
		
		local list_size = #table_itemQuery
		for i=0,list_size-2 do -- loop backwards through list of items waiting to be cached
			if GetItemInfo(table_itemQuery[list_size-i]) then -- check if this item in the list is cached yet
				if debugOn then print("Item info for "..table_itemQuery[list_size-i].." is ready, adding to loot window.") end
				FARaidTools:addToLootWindow(table_itemQuery[list_size-i]) -- it's ready so add it to the loot window
				table.remove(table_itemQuery, list_size-i) -- remove the entry from the query list
			--[[else
				if debugOn then print("Item info for "..table_itemQuery[list_size-i].." was not found.") end--]]
			end
		end
		
		if #table_itemQuery == 1 then
			table_itemQuery = {}
		elseif debugOn then
			print("Item info for "..(#table_itemQuery-1).." items is not ready. Checking again in "..cacheInterval.."ms.")
		end
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
		if not UnitIsGroupAssistant("PLAYER") and not UnitIsGroupLeader("PLAYER") then
			if GetCVar("autoLootDefault") == "1" then
				SetModifiedClick("AUTOLOOTTOGGLE", "NONE")
				SetCVar("autoLootDefault", 0)
				if not suppress then print("RT: Autoloot is now off.") end
			end
		end
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
	--if debugOn then print("parseChat("..msg..", "..tostring(author)..")") end
	local rank = 0
	if not debugOn then
		for i=1,40 do
			local name, rank_ = GetRaidRosterInfo(i)
			if name == author then
				rank = rank_
				break
			end
		end
	end
	if rank > 0 or debugOn then
		local _, replaces = string.gsub(msg, hyperlinkPattern, "")
		if replaces == 1 then -- if the number of item links in the message is exactly 1 then we should process it
			local link = string.match(msg, hyperlinkPattern)
			if debugOn then print("link: "..link) end
			msg = string.gsub(msg, hyperlinkPattern, "")
			if debugOn then print("msg after links removed: "..msg) end
			msg = link..msg
			if debugOn then print("reassembled msg: "..msg) end
			msg = string.gsub(msg, "x%d+", "") -- remove any "x2" or "x3"s from the string
			local note = string.match(msg, "]|h|r%s*(.+)") -- take anything else after the link and any following spaces as the note value
			note = string.gsub(note, "%s+", " ") -- replace any double spaces with a single space
			if debugOn then print("final note: "..note) end
			local shouldadd = true
			for i=1,#table_nameAssociations do
				if table_nameAssociations[i][1] == link then shouldadd = false end
			end
			if shouldadd == true then
				table.insert(table_nameAssociations, {link, author})
			end
			if debugOn then print(link) end
			if debugOn then print(note) end
			if note then
				FARaidTools:valueFormat(link, note)
			end
		end
	end
end

function FARaidTools:dumpHBL()
	DevTools_Dump(hasBeenLooted)
end
	
local frame, events = CreateFrame("Frame"), {}
function events:ADDON_LOADED(name)
	if name == "FARaidTools" then
		_, _, addonVersion = GetAddOnInfo("FARaidTools")
		addonVersionFull = GetAddOnMetadata("FARaidTools", "Version")
		if table_options then -- if options loaded, then load into local variables
			lootSettings = table_options[1] or saveLootSettings()
			history = history or {}
			table_aliases = table_options[2] or table_aliases
		else -- if not, set to default values
			saveLootSettings()
			history = {}
		end
		FA_RTscrollingtable2:SetData(history, true)
		FARaidTools:RegisterComm("FA_RTreport")
		FARaidTools:RegisterComm("FA_RTend")
		FARaidTools:RegisterComm("FA_RTwho")
		FARaidTools:RegisterComm("FA_RTupdate")
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
	if addonEnabled() then
		local loot = {} -- create a temporary table to organize the loot on the mob
		for i=1,GetNumLootItems() do -- loop through all items in the window
			local sourceInfo = {GetLootSourceInfo(i)}
			for j=1,#sourceInfo/2 do
				local mobID = sourceInfo[j*2-1] -- retrieve GUID of the mob that holds the item
				for k=1,#hasBeenLooted do
					if hasBeenLooted[k] == mobID then
						mobID = nil
						break
					end
				end
				if mobID then
					local id
					for k=1,#loot do
						if loot[k][1] == mobID then
							id = k
							break
						end
					end
					if not id then
						table.insert(loot, {mobID}) -- create an entry in table for the mobID
						id = #loot
					end
					
					local link = GetLootSlotLink(i) -- retrieve link of item
					if link and checkFilters(link) then
						for l=1,max(sourceInfo[j*2], 1) do -- repeat the insert if there is multiple of the item in that slot.
							-- max() is there to remedy the bug with GetLootSourceInfo returning incorrect (0) values.
							-- GetLootSourceInfo may also return multiple quantity when there is actually only
							-- one of the item, but there's not much we can do about that.
							table.insert(loot[id], link)
						end
					end
				end
			end
		end
		
		-- add an item count for each GUID so that other clients may verify data integrity
		for i=1,#loot do
			table.insert(loot[i], 2, 0) -- insert 0 as the second value in the table
			loot[i][2] = #loot[i] -- set the second value in the table to the size of the table
		end
		
		if #loot and debugOn then DevTools_Dump(loot) end
		
		for i=1,#loot do
			FARaidTools:sendMessage("FA_RTreport", {addonVersion, loot[i]}, "RAID", nil, "BULK") -- send addon message to tell others to add this to their window

			local data = loot[i]
			if data[2] == #data then
				table.remove(data, 2)
				local mobID = table.remove(data, 1)
				
				-- we can assume that everything in the table is not on the HBL
				
				for j=1, #data do
					if checkFilters(data[j], true) then
						FARaidTools:cacheItem(data[j])
					end
				end
				
				table.insert(hasBeenLooted, mobID)
			end
		end
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
		if not msg then return end
		local itemLink = string.match(msg, hyperlinkPattern) 
		if not itemLink then return end
		local msg = string.match(msg, hyperlinkPattern.."(.+)") -- now remove the link
		if msg == "" then return end
		local msg = string.lower(msg) -- put in lower case
		local msg = " "..string.gsub(msg, "[/,]", " ").." "
		if string.match(msg, " de ") or string.match(msg, " disenchant ") then
			if UnitIsGroupAssistant("PLAYER") or UnitIsGroupLeader("PLAYER") then
				FARaidTools:sendMessage("FA_RTend", {addonVersion, itemLink}, "RAID")
			end
			FARaidTools:endItem(itemLink)
		end
	end
end
function events:GROUP_JOINED()
	if IsInRaid() then
		FARaidTools:sendMessage("FA_RTupdate", {addonVersionFull}, "RAID", nil, "BULK")
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
frame:SetScript("OnEvent", function(self, event, ...)
	events[event](self, ...) -- call one of the functions above
end)
for k, v in pairs(events) do
	frame:RegisterEvent(k) -- Register all events for which handlers have been defined
end

if debugOn then
	FARaidTools:cacheItem("\124cffa335ee\124Hitem:71472:0:0:0:0:0:0:0:0\124h[Flowform Choker]\124h\124r")
	FARaidTools:cacheItem("\124cffa335ee\124Hitem:71466:0:0:0:0:0:0:0:0\124h[Fandral's Flamescythe]\124h\124r")
	FARaidTools:cacheItem("\124cffa335ee\124Hitem:71466:0:0:0:0:0:0:0:0\124h[Fandral's Flamescythe]\124h\124r")
	FARaidTools:cacheItem("\124cffa335ee\124Hitem:71781:0:0:0:0:0:0:0:0\124h[Zoid's Firelit Greatsword]\124h\124r")
	FARaidTools:cacheItem("\124cffa335ee\124Hitem:71469:0:0:0:0:0:0:0:0\124h[Breastplate of Shifting Visions]\124h\124r")
	FARaidTools:cacheItem("\124cffa335ee\124Hitem:71475:0:0:0:0:0:0:0:0\124h[Treads of the Penitent Man]\124h\124r")
	FARaidTools:cacheItem("\124cffa335ee\124Hitem:71673:0:0:0:0:0:0:0:0\124h[Shoulders of the Fiery Vanquisher]\124h\124r")
	FARaidTools:cacheItem("\124cffa335ee\124Hitem:71673:0:0:0:0:0:0:0:0\124h[Shoulders of the Fiery Vanquisher]\124h\124r")
	FARaidTools:cacheItem("\124cffa335ee\124Hitem:71687:0:0:0:0:0:0:0:0\124h[Shoulders of the Fiery Protector]\124h\124r")
	FARaidTools:parseChat("\124cffa335ee\124Hitem:71466:0:0:0:0:0:0:0:0\124h[Fandral's Flamescythe]\124h\124r 30", UnitName("PLAYER"))
end
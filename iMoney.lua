-----------------------------------
-- Setting up scope, upvalues and libs
-----------------------------------

local AddonName, iMoney = ...;
LibStub("AceEvent-3.0"):Embed(iMoney);

local L = LibStub("AceLocale-3.0"):GetLocale(AddonName);

local _G = _G;
local format = _G.string.format;

-------------------------------
-- Registering with iLib
-------------------------------

LibStub("iLib"):Register(AddonName, nil, iMoney);

------------------------------------------
-- Variables, functions and colors
------------------------------------------

local Gold = 0; -- This variable stores our current amount of gold
local OldGold = 0; -- When the gold changed, here the "old" amount is been saved. We need that to calcualte if we made more or less money.
local CharName = _G.GetUnitName("player", false); -- The charname doesn't change during a session. To prevent calling the function more than once, we simply store the name.

local COLOR_GOLD = "|cfffed100%s|r";
local COLOR_RED  = "|cffff0000%s|r";
local COLOR_GREEN= "|cff00ff00%s|r";

-----------------------------
-- Setting up the LDB
-----------------------------

iMoney.ldb = LibStub("LibDataBroker-1.1"):NewDataObject(AddonName, {
	type = "data source",
	text = AddonName,
});

iMoney.ldb.OnEnter = function(anchor)
	if( iMoney:IsTooltip("Main") ) then
		return;
	end
	
	iMoney:HideAllTooltips();
	
	local tip = iMoney:GetTooltip("Main", "UpdateTooltip");
	tip:SetAutoHideDelay(0.25, anchor);
	tip:SmartAnchorTo(anchor);
	tip:Show();
end

iMoney.ldb.OnLeave = function() end

----------------------
-- Initializing
----------------------

function iMoney:Boot()
	self.db = LibStub("AceDB-3.0"):New("iMoneyDB", {realm={today="",chars={}}}, true).realm;
	
	-- character currently missing in the table? no problem!
	if( not self.db.chars[CharName] ) then
		local _, class = _G.UnitClass("player");
		self.db.chars[CharName] = {
			gold = 0, -- current amount of gold
			gold_in = 0, -- amount of gold earned during session
			gold_out = 0, -- amount of gold spent during session
			class = class, -- unlocalized class name, e.g. PALADIN, PRIEST, ... this is important for displaying colored charnames
		};
	end
	
	local c = self.db.chars[CharName];
	local today = date("%y-%m-%d");
	
	-- if the day changed, iMoney sets gold_in and gold_out for all chars to 0
	-- here we can add other routines, like monthly wins/losses, at a later time.
	if( today ~= self.db.today ) then
		self.db.today = today;
		
		for k, v in pairs(self.db.chars) do
			v.gold_in = 0;
			v.gold_out = 0;
		end
	end
	
	self:RegisterEvent("PLAYER_MONEY", "UpdateMoney");
	self:UpdateMoney("", true); -- the argument tells iMoney that's the first run
end
iMoney:RegisterEvent("PLAYER_ENTERING_WORLD", "Boot");

function iMoney:DeleteChar(name)
	self.db.chars[name] = nil;
end

------------------------------------------
-- MoneyString and UpdateMoney
------------------------------------------

local ICON_GOLD   = "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:0:1|t";
local ICON_SILVER = "|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:0:1|t";
local ICON_COPPER = "|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:0:1|t";

local function money_string(money, encolor)
	local str;
	
	local isLoss, gold, silver, copper;
	
	isLoss = money < 0; -- determines if we gained or lost money
	money = abs(money); -- the number is forced to be > 0
	
	gold = floor(money / (100 * 100));
	silver = floor((money - (gold * 100 * 100)) / 100);
	copper = mod(money, 100);
	
  	str	= (gold > 0 and _G.BreakUpLargeNumbers(gold).." "..ICON_GOLD or "")..
				  ((silver > 0 and gold > 0) and " " or "")..
					(silver > 0 and (silver < 10 and "0" or "")..silver.." "..ICON_SILVER or "")..
					((copper > 0 and silver > 0) and " " or "")..
					(copper > 0 and (copper < 10 and "0" or "")..copper.." "..ICON_COPPER or "");
	
	-- this may happen, tricky one!			
	if( str == "" ) then
		str = copper.." "..ICON_COPPER;
	end
	
	if( isLoss ) then
		str = "-"..str;
	end
	
	if( encolor ) then
		if( isLoss ) then
			str = (COLOR_RED):format(str);
		else
			str = (COLOR_GREEN):format(str);
		end
	end

	return str;
end

function iMoney:UpdateMoney(event, firstRun)
	local money = _G.GetMoney();
	
	-- in an older version, iMoney did not have this feature. so we must check if the config values are there.
	if( self.db.chars[CharName].gold_in == nil ) then self.db.chars[CharName].gold_in = 0 end
	if( self.db.chars[CharName].gold_out == nil ) then self.db.chars[CharName].gold_out = 0 end
	
	if( not firstRun ) then
		if( money > Gold ) then
			self.db.chars[CharName].gold_in = self.db.chars[CharName].gold_in + (money - Gold);
		else
			self.db.chars[CharName].gold_out= self.db.chars[CharName].gold_out + (Gold - money);
		end
	end
	Gold = money;
	
	self.db.chars[CharName].gold = money;
	self.ldb.text = money_string(money);
end

------------------------------------------
-- UpdateTooltip
------------------------------------------

local queryName;
local function LineEnter(anchor, name)
	queryName = name;
	
	local tip = iMoney:GetTooltip("Hint", "UpdateTooltipQueryName");
	tip:SetPoint("TOPLEFT", anchor, "BOTTOMRIGHT", 10, anchor:GetHeight()+2);
	tip:Show();
end

local function LineLeave()
	iMoney:GetTooltip("Hint"):Release();
	queryName = nil;
end

local function LineClick(_, name, button)
	if( button == "RightButton" ) then
		_G.StaticPopupDialogs["IMONEY_DELETE"].text = ("%s\n%s: %s"):format(L["Confirm to delete from iMoney!"], _G.CHARACTER, name);
		
		local popup = _G.StaticPopup_Show("IMONEY_DELETE");
		if( popup ) then
			popup.data = name;
			iMoney:GetTooltip("Main"):Release();
		end
	end
end

local function iMoneySort(a, b, sortByName)
	if( sortByName ) then
		return a.name < b.name;
	else
		if( a.gold == b.gold ) then
			return iMoneySort(a, b, true);
		else
			return a.gold > b.gold;
		end
	end
end

function iMoney:UpdateTooltipQueryName(tip)
	self:UpdateTooltip(tip, queryName);
end

local SortingTable = {};
function iMoney:UpdateTooltip(tip, queryName)
	local name = queryName and queryName or CharName;
	local line;
	
	tip:Clear();
	tip:SetColumnLayout(2, "LEFT", "RIGHT");
	
	-- check for addon updates
	if( LibStub("iLib"):IsUpdate(AddonName) ) then
		line = tip:AddHeader(" ");
		tip:SetCell(line, 1, "|cffff0000Addon Update available!|r", nil, "CENTER", 0);
	end
	--------------------------
	
	if( queryName ) then
		tip:AddHeader(
			("|c%s%s|r"):format(_G.RAID_CLASS_COLORS[self.db.chars[name].class].colorStr, name)
		);
		tip:AddLine("");
	end
	
	tip:AddLine(
		(COLOR_GOLD):format(L["Today Session"]),
		money_string(self.db.chars[name].gold_in - self.db.chars[name].gold_out, true)
	);
	tip:AddSeparator(); -- my sister wanted it to bad! So here it is: a line in the tip. :D
	tip:AddLine(L["Gains"], money_string(self.db.chars[name].gold_in, true));
	tip:AddLine(L["Losses"], money_string(-self.db.chars[name].gold_out, true));
	tip:AddLine(" ");
	
	if( not queryName ) then
		local total = 0;
		
		for k, v in pairs(self.db.chars) do
			v.name = k;
			table.insert(SortingTable, v);
		end
		table.sort(SortingTable, iMoneySort);
		
		local isSelf;
		for i = 1, #SortingTable do
			isSelf = (SortingTable[i].name == CharName);
			
			line = tip:AddLine(
				("|c%s%s|r%s"):format(
					_G.RAID_CLASS_COLORS[SortingTable[i].class].colorStr,
					SortingTable[i].name,
					(isSelf and " |TInterface\\RAIDFRAME\\ReadyCheck-Ready:12:12|t" or "")
				),
				money_string(SortingTable[i].gold)
			);
			total = total + SortingTable[i].gold;
			
			if( not isSelf ) then
				tip:SetLineScript(line, "OnMouseDown", LineClick, SortingTable[i].name);
				tip:SetLineScript(line, "OnEnter", LineEnter, SortingTable[i].name);
				tip:SetLineScript(line, "OnLeave", LineLeave);
			end
		end
		
		_G.wipe(SortingTable);
		
		tip:AddLine(" ");
		tip:AddLine(
			(COLOR_GOLD):format(L["Total Gold"]),
			money_string(total)
		);
	else
		line = tip:AddLine("");
		tip:SetCell(line, 1, (COLOR_GOLD):format(L["Right-click to remove"]), nil, "LEFT", 0);
	end
end

---------------------
-- Final stuff
---------------------

_G.StaticPopupDialogs["IMONEY_DELETE"] = {
	preferredIndex = 3, -- apparently avoids some UI taint
	button1 = "Delete",
	button2 = "Cancel",
	showAlert = 1,
	timeout = 0,
	hideOnEscape = true,
	OnAccept = function(self, data)
		iMoney:DeleteChar(data);
	end,
};
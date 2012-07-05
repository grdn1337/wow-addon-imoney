-----------------------------------
-- Setting up scope, upvalues and libs
-----------------------------------

local AddonName = select(1, ...);
iMoney = LibStub("AceAddon-3.0"):NewAddon(AddonName, "AceEvent-3.0");

local L = LibStub("AceLocale-3.0"):GetLocale(AddonName);

local LibQTip = LibStub("LibQTip-1.0");

local _G = _G; -- upvalueing done here, since I call Globales with _G.func()...

------------------------------------------
-- Variables, functions and colors
------------------------------------------

local Tooltip; -- This is our QTip object
local HintTip; -- This is another QTip object

local Gold = 0; -- This variable stores our current amount of gold
local OldGold = 0; -- When the gold changed, here the "old" amount is been saved. We need that to calcualte if we made more or less money.
local CharName = _G.GetUnitName("player", false); -- The charname doesn't change during a session. To prevent calling the function more than once, we simply store the name.

local COLOR_GOLD = "|cfffed100%s|r";
local COLOR_RED  = "|cffff0000%s|r";
local COLOR_GREEN= "|cff00ff00%s|r";

local ICON_GOLD   = "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t";
local ICON_SILVER = "|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:2:0|t";
local ICON_COPPER = "|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:2:0|t";

local ClassColors = {};
for k in pairs(_G.LOCALIZED_CLASS_NAMES_MALE) do
	local c = _G.RAID_CLASS_COLORS[k];
	ClassColors[k] = ("|cff%02x%02x%02x"):format(c.r *255, c.g *255, c.b *255);
end

local function tclear(t, wipe)
	if( type(t) ~= "table" ) then return end;
	for k in pairs(t) do
		t[k] = nil;
	end
	t[''] = 1;
	t[''] = nil;
	if( wipe ) then
		t = nil;
	end
end

-----------------------------
-- Setting up the feed
-----------------------------

iMoney.Feed = LibStub("LibDataBroker-1.1"):NewDataObject(AddonName, {
	type = "data source",
	text = "",
});

iMoney.Feed.OnEnter = function(anchor)
	-- LibQTip is able to display more than one tooltips.
	-- Due to this behaviour we need to hide all other tips of the iAddons to prevent showing more LDB tips at once.
	for k, v in LibQTip:IterateTooltips() do
		if( type(k) == "string" and strsub(k, 1, 6) == "iSuite" ) then
			v:Release(k);
		end
	end
	
	Tooltip = LibQTip:Acquire("iSuite"..AddonName);
	Tooltip:SetColumnLayout(2, "LEFT", "RIGHT");
	Tooltip:SetAutoHideDelay(0.1, anchor);
	Tooltip:SmartAnchorTo(anchor);
	iMoney:UpdateTooltip();
	Tooltip:Show();
end

----------------------
-- Initializing
----------------------

function iMoney:OnInitialize()
	self.db = LibStub("AceDB-3.0"):New("iMoneyDB", {realm={today="",chars={}}}, true).realm;
	
	-- character currently missing in the table? no problem!
	if( not self.db.chars[CharName] ) then
		local _, class = _G.UnitClass("player");
		self.db.chars[CharName] = {
			gold = 0, -- current amount of gold
			gold_in = 0, -- amount of gold earned during session
			gold_out = 0, -- amount of gold spent during session
			class = class, -- unlocalized class name, e.g. PALADIN, PRIEST, MONK, ROGUE, ... this is important for displaying encolors charnames
		};
	end
	
	self:RegisterEvent("PLAYER_MONEY", "UpdateMoney", 1); -- the third argument tells iMoney if it's not the first Money Update
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "FirstRun");
end

function iMoney:FirstRun()
	self:UpdateMoney(); -- we just can call GetMoney() on Entering World, that's why this call is here
	
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
end

function iMoney:DeleteChar(name)
	self.db.chars[name] = nil;
end

------------------------------------------
-- MoneyString and UpdateMoney
------------------------------------------

local function CreateMoneyString(money, encolor)
	local str;
	local cfgStr___placeholder = 1; -- maybe I will add other display options in a later release
	
	local isLoss, gold, silver, copper;
	
	isLoss = money < 0; -- determines if we gained or lost money
	money = abs(money); -- the number is forced to be > 0
	
	gold = floor(money / (100 * 100));
	silver = floor((money - (gold * 100 * 100)) / 100);
	copper = mod(money, 100);
	
	if( cfgStr___placeholder == 1 ) then
		str =	(gold > 0 and _G.BreakUpLargeNumbers(gold)..ICON_GOLD or "")..
					((silver > 0 and gold > 0) and " " or "")..
					(silver > 0 and silver..ICON_SILVER or "")..
					((copper > 0 and silver > 0) and " " or "")..
					(copper > 0 and copper..ICON_COPPER or "");
		
		if( isLoss ) then
			str = "-"..str;
		end
		
		-- this may happen, tricky one!			
		if( str == "" ) then
			str = copper..ICON_COPPER;
		end
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

function iMoney:UpdateMoney(notFirst)
	local money = _G.GetMoney();
	
	-- in an older version, iMoney did not have this feature. so we must check if the config values are there.
	if( self.db.chars[CharName].gold_in == nil ) then self.db.chars[CharName].gold_in = 0 end
	if( self.db.chars[CharName].gold_out == nil ) then self.db.chars[CharName].gold_out = 0 end
	
	if( notFirst ) then
		if( money > Gold ) then
			self.db.chars[CharName].gold_in = self.db.chars[CharName].gold_in + (money - Gold);
		else
			self.db.chars[CharName].gold_out= self.db.chars[CharName].gold_out + (Gold - money);
		end
	end
	Gold = money;
	
	self.db.chars[CharName].gold = money;
	self.Feed.text = CreateMoneyString(money);
end

------------------------------------------
-- UpdateTooltip
------------------------------------------

local function LineLeave()
	HintTip:Hide();
	HintTip:Release();
end

local function LineClick(_, name, button)
	if( button == "RightButton" ) then
		_G.StaticPopupDialogs["IMONEY_DELETE"].text = ("%s\n%s: %s"):format(L["Confirm to delete from iMoney!"], _G.CHARACTER, name);
		
		local popup = _G.StaticPopup_Show("IMONEY_DELETE");
		if( popup ) then
			popup.data = name;
			Tooltip:Hide();
		end
	end
end

local function LineEnter(anchor, name)
	HintTip = LibQTip:Acquire("iSuite"..AddonName.."Hint");
	HintTip:SetColumnLayout(2, "LEFT", "RIGHT");
	HintTip:SetPoint("TOPLEFT", anchor, "BOTTOMRIGHT", 10, anchor:GetHeight()+2);
	iMoney:UpdateTooltip(name);
	HintTip:Show();
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

local SortingTable = {};
function iMoney:UpdateTooltip(queryName)
	local tip = Tooltip;
	local name = CharName;
	local line;
	
	if( queryName ) then
		tip = HintTip;
		name = queryName;
	end
	
	tip:Clear();
	
	if( queryName ) then
		tip:AddHeader(
			("%s%s|r"):format(ClassColors[self.db.chars[name].class], name)
		);
		tip:AddLine("");
	end
	
	tip:AddLine(
		(COLOR_GOLD):format(L["Today Session"]),
		CreateMoneyString(self.db.chars[name].gold_in - self.db.chars[name].gold_out, true)
	);
	tip:AddSeparator(); -- my sister wanted it to bad! So here it is: a line in the tip. :D
	tip:AddLine(L["Gains"], CreateMoneyString(self.db.chars[name].gold_in, true));
	tip:AddLine(L["Losses"], CreateMoneyString(-self.db.chars[name].gold_out, true));
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
				("%s%s|r%s"):format(
					ClassColors[SortingTable[i].class],
					SortingTable[i].name,
					(isSelf and " |TInterface\\RAIDFRAME\\ReadyCheck-Ready:12:12|t" or "")
				),
				CreateMoneyString(SortingTable[i].gold)
			);
			total = total + SortingTable[i].gold;
			
			if( not isSelf ) then
				tip:SetLineScript(line, "OnMouseDown", LineClick, SortingTable[i].name);
				tip:SetLineScript(line, "OnEnter", LineEnter, SortingTable[i].name);
				tip:SetLineScript(line, "OnLeave", LineLeave);
			end
		end
		
		tclear(SortingTable);
		
		tip:AddLine(" ");
		tip:AddLine(
			(COLOR_GOLD):format(L["Total Gold"]),
			CreateMoneyString(total)
		);
	else
		line = tip:AddLine("");
		tip:SetCell(line, 1, (COLOR_GOLD):format(L["Right-click to remove"]), nil, "LEFT", 2);
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
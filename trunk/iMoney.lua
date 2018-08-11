-----------------------------------
-- Setting up scope, upvalues and libs
-----------------------------------

local AddonName, iMoney = ...;
_G.iMoney = iMoney;

LibStub("AceEvent-3.0"):Embed(iMoney);

local L = LibStub("AceLocale-3.0"):GetLocale(AddonName);

local Dialog = LibStub("LibDialog-1.0");

local _G = _G;
local format = _G.string.format;

-------------------------------
-- Registering with iLib
-------------------------------

LibStub("iLib"):Register(AddonName, nil, iMoney);

local DialogTable = {
	text = "",
	buttons = {
		{text = _G.DELETE, on_click = function(self, data)
			iMoney:DeleteChar(data);
		end},
		{text = _G.CANCEL},
	},
};
Dialog:Register("iMoneyDelete", DialogTable);

------------------------------------------
-- Variables, functions and colors
------------------------------------------

local Gold = 0; -- This variable stores our current amount of gold
local CharName = _G.GetUnitName("player", false); -- The charname doesn't change during a session. To prevent calling the function more than once, we simply store the name.

local iconSize = 12;

local COLOR_GOLD = "|cfffed100%s|r";
local COLOR_RED  = "|cffff0000%s|r";
local COLOR_GREEN= "|cff00ff00%s|r";

local StoreRealm; -- realm db
local StoreCharacter; -- char db
local StoreDay; -- day db

local StoreDay_Date; -- which date the StoreDay table has

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

iMoney.ldb.OnClick = function(_, button)
	if( button == "LeftButton" ) then
		_G.ToggleAllBags();
	end
end

----------------------
-- Initializing
----------------------

function iMoney:Boot()
	--self.db = LibStub("AceDB-3.0"):New("iMoneyDB", {realm={today="",chars={}}}, true).realm;
	self.db = LibStub("AceDB-3.0"):New("iMoneyDBv2", {global={History = {}, Realms = {}, RealmCount = 0}}, true);
	self.ConfigData = self.db.keys;
	self.db = self.db.global;
	
	local cfg = self.ConfigData;
	cfg.charname = CharName;
	
	-- check if db realm already exists
	if( not self.db.Realms[cfg.realm] ) then
		self.db.Realms[cfg.realm] = {};
	end
	StoreRealm = self.db.Realms[cfg.realm];
	_G.IMR = StoreRealm;
	
	-- check if db character already exists
	if( not StoreRealm[cfg.charname] ) then
		StoreRealm[cfg.charname] = {
			gold = 0, -- current amount of gold
			earned = 0, -- amount of gold earned during session
			spent = 0, -- amount of gold spent during session
			faction = self.ConfigData.faction, -- we must store the faction for coloring
			class = self.ConfigData.class -- we must store the class for coloring
		};
	end
	StoreCharacter = StoreRealm[cfg.charname];
	
	-- count currently active realms and fill cumulated values
	do
		self.db.RealmCount = 0;
		local t = {};
		t[1] = 0;
		
		for rk, realm in pairs(self.db.Realms) do
			local countRealm;
			
			for _, char in pairs(realm) do
				if( char.gold ) then
					countRealm = true;
				end
				
				if( not t[rk] ) then
					t[rk] = {};
					t[rk][1] = 0;
				end
				t[rk][1] = t[rk][1] + (char.gold or 0);
				t[1] = t[1] + (char.gold or 0);
			end
			
			self.db.RealmCount = self.db.RealmCount + (countRealm and 1 or 0);
		end
		
		self.CumulatedGold = t;
	end
	
	-- check and select StoreDay table and set its Date
	self:SetCurrentOverallMoney();
	
	-- set update values metatable
	setmetatable(StoreCharacter, {
		__newindex = function(t, index, v) 
			if( index == "add" ) then
				-- Update StoreCharacter
				t.earned = t.earned + v;
				
				-- Update StoreDay
				StoreDay.gold = StoreDay.gold + v;
				StoreDay.earned = StoreDay.earned + v;
			elseif( index == "sub" ) then
				-- Update StoreCharacter
				t.spent = t.spent + v;
				
				-- Update StoreDay
				StoreDay.gold = StoreDay.gold - v;
				StoreDay.spent = StoreDay.spent + v;
			end
		end
	});
	
	self:RegisterEvent("PLAYER_MONEY", "UpdateMoney");
	self:UpdateMoney("", true); -- the argument tells iMoney that's the first run
end
iMoney:RegisterEvent("PLAYER_ENTERING_WORLD", "Boot");

function iMoney:DeleteChar(name)
	StoreRealm[name] = nil;
end

------------------------------------------
-- MoneyString and UpdateMoney
------------------------------------------

local ICON_GOLD   = "|TInterface\\MoneyFrame\\UI-GoldIcon:"..iconSize..":"..iconSize..":0:1|t";
local ICON_SILVER = "|TInterface\\MoneyFrame\\UI-SilverIcon:"..iconSize..":"..iconSize..":0:1|t";
local ICON_COPPER = "|TInterface\\MoneyFrame\\UI-CopperIcon:"..iconSize..":"..iconSize..":0:1|t";

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
	local prevmoney = StoreCharacter.gold;
	
	-- day change
	if( self:GetToday() ~= StoreDay_Date ) then
		self:SetCurrentOverallMoney();
	end
	
	if( not firstRun ) then
		if( money > prevmoney ) then
			StoreCharacter.add = (money - prevmoney);
		else
			StoreCharacter.sub = (prevmoney - money);
		end
	end
	
	StoreCharacter.gold = money;
	self.ldb.text = money_string(money);
end

function iMoney:SetCurrentOverallMoney()
	-- check money history
	StoreDay_Date = self:GetToday();
	if( not self.db.History[StoreDay_Date] ) then
		self.db.History[StoreDay_Date] = {
			gold = 0,
			earned = 0, -- amount of gold earned during day
			spent = 0, -- amount of gold spent during day
		};
		
		-- loop through all characters and reset earned/spent values
		for _, realm in pairs(self.db.Realms) do
			for _, char in pairs(realm) do
				char.earned = 0;
				char.spent = 0;
			end
		end
	end
	StoreDay = self.db.History[StoreDay_Date];
	
	local overallMoney = 0;
	
	-- loop through all characters
	for _, realm in pairs(self.db.Realms) do
		for _, char in pairs(realm) do
			overallMoney = overallMoney + char.gold;
		end
	end
	
	StoreDay.gold = overallMoney;
end

function iMoney:GetDayRangeMoney(day, range)
	local overallEarned, overallSpent, lastGold;
	overallEarned = 0;
	overallSpent = 0;
	lastGold = 0;
	
	local counter = 0;
	
	-- loop through days
	for i = day, (day - range), -1 do
		if( self.db.History[i] ) then
			overallEarned = overallEarned + self.db.History[i].earned or 0;
			overallSpent = overallSpent + self.db.History[i].spent or 0;
			
			-- only count last gold on days with actual gold value on first occurance
			if( self.db.History[i].gold ) then
				if( counter == 0 ) then
					lastGold = self.db.History[i].gold;
				end
				counter = counter + 1;
			end
		end
	end
	
	return overallEarned, overallSpent, maxGold;
end

function iMoney:GetAllRangeMoney()
	local overallEarned, overallSpent, lastGold;
	overallEarned = 0;
	overallSpent = 0;
	lastGold = 0;
	
	local lastGoldDay = 0;
	
	for k, v in pairs(self.db.History) do
		overallEarned = overallEarned + v.earned or 0;
		overallSpent = overallSpent + v.spent or 0;
		
		if( v.gold and k > lastGoldDay ) then
			lastGoldDay = k;
			lastGold = v.gold;
		end
	end
	
	return overallEarned, overallSpent, lastGold;
end

------------------------------------------
-- UpdateTooltip
------------------------------------------

local function LineClick(_, name, button)
	if( button == "RightButton" ) then
		Dialog:Dismiss("iMoneyDelete");
		
		DialogTable.text = ("%s\n%s: %s"):format(L["Confirm to delete from iMoney!"], _G.CHARACTER, name);
		Dialog:Spawn("iMoneyDelete", name);
	end
end


local function iMoneySort(a, b, sortByName)
	if( sortByName ) then
		return a < b;
	else
		if( (StoreRealm[a].gold or 0) == (StoreRealm[b].gold or 0) ) then
			return iMoneySort(a, b, true);
		else
			return (StoreRealm[a].gold or 0) > (StoreRealm[b].gold or 0);
		end
	end
end


local queryData;
local function LineEnter(anchor, query)
	queryData = query;
	
	local tip = iMoney:GetTooltip("Hint", "UpdateTooltipQuery");
	tip:SetPoint("TOPLEFT", anchor, "BOTTOMRIGHT", 10, anchor:GetHeight() + 2);
	tip:Show();
end

local function LineLeave()
	iMoney:GetTooltip("Hint"):Release();
	queryData = nil;
end

function iMoney:UpdateTooltipQuery(tip)
	local line;
	
	tip:Clear();
	tip:SetColumnLayout(3, "LEFT", "LEFT", "RIGHT");
	
	-- fetch query data
	local realm = self.db.Realms[queryData.queryRealm];
	
	tip:AddHeader((COLOR_GOLD):format(L["Today"]));
	
	for name, cfg in pairs(realm) do
		if( queryData.queryType == "realm" or (queryData.queryType == "char" and queryData.queryName == name) ) then
			tip:AddLine(" ");
			
			tip:AddLine(("%s |c%s%s|r"):format(
					"|TInterface\\FriendsFrame\\PlusManz-"..cfg.faction..":"..(iconSize + 2)..":"..(iconSize + 2).."|t",
					_G.RAID_CLASS_COLORS[cfg.class].colorStr,
					name
				), (COLOR_GOLD):format(L["Profit"]), money_string(cfg.earned - cfg.spent, true));
			tip:AddSeparator();
			tip:AddLine("", L["Gains"], money_string(cfg.earned, true));
			tip:AddLine("", L["Losses"], money_string(-cfg.spent, true));
			
			if( queryData.queryType == "realm" ) then
				tip:AddSeparator();
				tip:AddLine("", (COLOR_GOLD):format(L["Total Gold"]), money_string(cfg.gold));
			end
		end
	end
	
	if( queryData.queryType == "char" ) then
		tip:AddLine(" ");
		
		line = tip:AddLine("");
		tip:SetCell(line, 1, (COLOR_GOLD):format(L["Right-click to remove"]), nil, "LEFT", 3);
	end
end


local SortingTable = {};
function iMoney:UpdateTooltip(tip)
	local line;
	local earned, spent;
	
	tip:Clear();
	tip:SetColumnLayout(3, "LEFT", "LEFT", "RIGHT");
	
	-- check for addon updates
	if( LibStub("iLib"):IsUpdate(AddonName) ) then
		line = tip:AddHeader(" ");
		tip:SetCell(line, 1, "|cffff0000Addon Update available!|r", nil, "CENTER", 2);
	end
	--------------------------
	
	-- Today
	tip:AddLine((COLOR_GOLD):format(L["Today"]), (COLOR_GOLD):format(L["Profit"]), money_string(StoreDay.earned - StoreDay.spent, true));
	tip:AddSeparator();
	tip:AddLine("", L["Gains"], money_string(StoreDay.earned, true));
	tip:AddLine("", L["Losses"], money_string(-StoreDay.spent, true));
	tip:AddLine(" ");
	
	-- Week
	earned, spent = self:GetDayRangeMoney(StoreDay_Date, 7);
	
	tip:AddLine((COLOR_GOLD):format(L["Week"]), (COLOR_GOLD):format(L["Profit"]), money_string(earned - spent, true));
	tip:AddSeparator();
	tip:AddLine("", L["Gains"], money_string(earned, true));
	tip:AddLine("", L["Losses"], money_string(-spent, true));
	tip:AddLine(" ");
	
	-- Month
	earned, spent = self:GetDayRangeMoney(StoreDay_Date, 30);
	
	tip:AddLine((COLOR_GOLD):format(L["Month"]), (COLOR_GOLD):format(L["Profit"]), money_string(earned - spent, true));
	tip:AddSeparator();
	tip:AddLine("", L["Gains"], money_string(earned, true));
	tip:AddLine("", L["Losses"], money_string(-spent, true));
	tip:AddLine(" ");
	
	-- All
	earned, spent = self:GetAllRangeMoney();
	
	tip:AddLine((COLOR_GOLD):format(L["Overall"]), (COLOR_GOLD):format(L["Profit"]), money_string(earned - spent, true));
	tip:AddSeparator();
	tip:AddLine("", L["Gains"], money_string(earned, true));
	tip:AddLine("", L["Losses"], money_string(-spent, true));
	tip:AddLine(" ");
	
	-- This realms characters
	for k, v in pairs(StoreRealm) do
		table.insert(SortingTable, k);
	end
	table.sort(SortingTable, iMoneySort);
		
	tip:AddLine((COLOR_GOLD):format(L["Characters"]));
	tip:AddSeparator();
	
	for i = 1, #SortingTable do
		local name = SortingTable[i];
		local cfg = StoreRealm[name];
		
		line = tip:AddLine(
			("%s |c%s%s|r"):format(
				"|TInterface\\FriendsFrame\\PlusManz-"..cfg.faction..":"..(iconSize + 2)..":"..(iconSize + 2).."|t",
				_G.RAID_CLASS_COLORS[cfg.class].colorStr,
				name
			), "", money_string(cfg.gold)
		);
		
		-- Set scripts for line
		if( name ~= self.ConfigData.charname ) then
			tip:SetLineScript(line, "OnMouseDown", LineClick, name);
		end
		
		tip:SetLineScript(line, "OnEnter", LineEnter, {queryType = "char", queryRealm = self.ConfigData.realm, queryName = name});
		tip:SetLineScript(line, "OnLeave", LineLeave);
	end
	
	_G.wipe(SortingTable);
	
	tip:AddSeparator();
	tip:AddLine(
		(COLOR_GOLD):format(L["Total Gold"]), "" , money_string(self.CumulatedGold[self.ConfigData.realm][1])
	);
	
	-- Other Realms
	if( self.db.RealmCount > 1 ) then
		tip:AddLine(" ");
		tip:AddLine((COLOR_GOLD):format(L["Other Realms"]), "",
			money_string(self.CumulatedGold[1] - self.CumulatedGold[self.ConfigData.realm][1])
		);
	
		table.sort(self.db.Realms);
		for k, _ in pairs(self.db.Realms) do
			if( k ~= self.ConfigData.realm ) then
				line = tip:AddLine(k, "", money_string(self.CumulatedGold[k][1] or 0));
				
				tip:SetLineScript(line, "OnEnter", LineEnter, {queryType = "realm", queryRealm = k, queryName = ""});
				tip:SetLineScript(line, "OnLeave", LineLeave);
			end
		end
	end
end

------------------------------------------
-- Day Calculation
------------------------------------------

-- borrowed some snippets from MoneyFu

do
	local offset;
	local function GetServerOffset()
		if offset then
			return offset
		end
		local serverHour, serverMinute = _G.GetGameTime()
		local utcHour = tonumber(date("!%H"))
		local utcMinute = tonumber(date("!%M"))
		local ser = serverHour + serverMinute / 60
		local utc = utcHour + utcMinute / 60
		offset = floor((ser - utc) * 2 + 0.5) / 2
		if offset >= 12 then
			offset = offset - 24
		elseif offset < -12 then
			offset = offset + 24
		end
		return offset
	end

	function iMoney:GetToday()
		return floor((time() / 60 / 60 + GetServerOffset()) / 24);
	end
end
-- Radial Consumables: a ring of consumables opened at the mouse.
-- Root slices clockwise from twelve: eat & drink, drinks, food, health
-- potions, mana potions, first aid, other. Hovering a slice opens its own
-- items fanned outside the root, best to worst clockwise, and fades the
-- other slices. A slice with one item opens nothing.

local _, ns = ...

local SIZE, GAP, MARGIN, POOL = 40, 10, 12, 24
local MIN_RADIUS = 64
local ACTION = "CLICK RadialConsumablesToggle:LeftButton"
local DEFAULT_KEY = "ALT-F"
local CONSUMABLE = Enum.ItemClass and Enum.ItemClass.Consumable or 0

BINDING_HEADER_RADIALCONSUMABLES = "Radial Consumables"
_G["BINDING_NAME_" .. ACTION] = "Open Radial Consumables"

local CATEGORIES = { "drink", "food", "health", "mana", "firstaid", "misc" }
local LABELS = {
	combo = "Eat & Drink",
	drink = "Drinks",
	food = "Food",
	health = "Health",
	mana = "Mana",
	firstaid = "First aid",
	misc = "Other consumables",
}

---------------------------------------------------------------------------
-- Secure frames

local header = CreateFrame("Frame", "RadialConsumablesHeader", UIParent, "SecureHandlerBaseTemplate")
header:SetAllPoints(UIParent)
header:SetFrameStrata("DIALOG")
header:EnableMouse(false)

-- Full-screen catcher under the rings: releasing on it cancels, right
-- click goes back a level. Escape is bound to it while the ring is open.
local catcher = CreateFrame("Button", "RadialConsumablesCatcher", header, "SecureHandlerClickTemplate")
catcher:SetAllPoints(header)
catcher:SetFrameLevel(header:GetFrameLevel() + 1)
catcher:RegisterForClicks("AnyUp", "AnyDown")
catcher:Hide()
catcher:SetFrameRef("header", header)
catcher:SetAttribute("_onclick", [[
	local header = self:GetFrameRef("header")
	if button == "Escape" then
		header:RunAttribute("close")
	elseif not down then
		if button == "RightButton" then
			header:RunAttribute("back")
		else
			header:RunAttribute("close")
		end
	end
]])

-- The keybind target. Some clients send a binding click on press and
-- release, some once: act on the press, or on a release with no press.
local toggle = CreateFrame("Button", "RadialConsumablesToggle", UIParent, "SecureHandlerClickTemplate")
toggle:RegisterForClicks("AnyUp", "AnyDown")
toggle:EnableMouse(false)
toggle:SetSize(1, 1)
toggle:SetPoint("TOPLEFT")
toggle:SetFrameRef("header", header)
toggle:SetAttribute("_onclick", [[
	if down then
		self:SetAttribute("pressed", true)
	elseif self:GetAttribute("pressed") then
		self:SetAttribute("pressed", nil)
		return
	end
	local header = self:GetFrameRef("header")
	if header:GetAttribute("state") then
		header:RunAttribute("close")
	else
		header:RunAttribute("open")
	end
]])

local root = CreateFrame("Frame", nil, header, "SecureFrameTemplate")
root:SetSize(1, 1)
root:SetFrameLevel(catcher:GetFrameLevel() + 5)
root:Hide()

local subs = {}
for i = 1, #CATEGORIES do
	local sub = CreateFrame("Frame", nil, header, "SecureFrameTemplate")
	sub:SetSize(1, 1)
	sub:SetPoint("CENTER", root, "CENTER")
	sub:SetFrameLevel(catcher:GetFrameLevel() + 15)
	sub:Hide()
	subs[i] = sub
	header:SetFrameRef("sub" .. i, sub)
end
header:SetFrameRef("root", root)
header:SetFrameRef("catcher", catcher)

header:SetAttribute("clamp", [[
	local reach, x, y = ...
	local w, h = self:GetWidth(), self:GetHeight()
	if x < reach then x = reach elseif x > w - reach then x = w - reach end
	if y < reach then y = reach elseif y > h - reach then y = h - reach end
	return x, y
]])

header:SetAttribute("open", [[
	local root = self:GetFrameRef("root")
	if (root:GetAttribute("count") or 0) == 0 then return end
	local x, y = self:GetMousePosition()
	if not x then return end
	x, y = self:RunAttribute("clamp", root:GetAttribute("reach"), x * self:GetWidth(), y * self:GetHeight())
	root:ClearAllPoints()
	root:SetPoint("CENTER", self, "BOTTOMLEFT", x, y)
	root:Show()
	self:GetFrameRef("catcher"):Show()
	self:SetAttribute("state", "root")
	self:SetBindingClick(true, "ESCAPE", "RadialConsumablesCatcher", "Escape")
]])

-- With a sub-ring open, the slice that opened it stays as it is (a click
-- uses its best item); the other slices fade to half and only switch the
-- open sub-ring. No active slice: all back to full.
header:SetAttribute("dim", ([[
	local active = ...
	self:SetAttribute("active", active)
	for i = 1, %d do
		self:GetFrameRef("slot" .. i):SetAlpha((not active or i == active) and 1 or 0.5)
	end
]]):format(#CATEGORIES + 1))

header:SetAttribute("openSub", [[
	local index, slot = ...
	local state = self:GetAttribute("state")
	if state and state ~= "root" then
		self:GetFrameRef("sub" .. state):Hide()
	end
	self:GetFrameRef("sub" .. index):Show()
	self:RunAttribute("dim", slot)
	self:SetAttribute("state", index)
]])

header:SetAttribute("back", [[
	local state = self:GetAttribute("state")
	if state == "root" or not state then
		self:RunAttribute("close")
		return
	end
	self:GetFrameRef("sub" .. state):Hide()
	self:RunAttribute("dim", nil)
	self:SetAttribute("state", "root")
]])

header:SetAttribute("close", ([[
	self:RunAttribute("dim", nil)
	self:GetFrameRef("root"):Hide()
	for i = 1, %d do
		self:GetFrameRef("sub" .. i):Hide()
	end
	self:GetFrameRef("catcher"):Hide()
	self:ClearBindings()
	self:SetAttribute("state", nil)
]]):format(#CATEGORIES))

-- Right click on any icon goes back; any other click uses it and closes.
-- A release on a faded root slice cancels like empty space.
local USE_PRE = [[
	if button == "RightButton" then
		owner:RunAttribute("back")
		return false
	end
	local slot = self:GetAttribute("slot")
	if slot and owner:GetAttribute("state") ~= "root" and slot ~= owner:GetAttribute("active") then
		owner:RunAttribute("close")
		return false
	end
	return nil, "used"
]]
local USE_POST = [[ owner:RunAttribute("close") ]]

-- Entering a root slice opens its ring at once, replacing any open one;
-- a slice without a ring takes the root back. After "back" the slice under
-- the cursor opens again only once the mouse leaves and comes back.
local ENTER_SLICE = [[
	local index = self:GetAttribute("sub")
	local state = owner:GetAttribute("state")
	if index then
		if index ~= state then
			owner:RunAttribute("openSub", index, self:GetAttribute("slot"))
		end
	elseif state and state ~= "root" then
		owner:RunAttribute("back")
	end
]]

---------------------------------------------------------------------------
-- Buttons

local MASK_ATLAS = "CircleMaskScalable"
local MASK_FILE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local allButtons = {}
local wellFed = {} -- itemID -> true for food and drink that also buff
local hasAtlas = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(MASK_ATLAS)

local function circle(button, texture)
	local mask = button:CreateMaskTexture()
	if hasAtlas then
		mask:SetAtlas(MASK_ATLAS)
	else
		mask:SetTexture(MASK_FILE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
	end
	mask:SetAllPoints(texture)
	texture:AddMaskTexture(mask)
end

local function itemName(id)
	return C_Item.GetItemNameByID(id) or ("item:" .. id)
end

local function showTip(b)
	if not b.itemID then return end
	local slot = b:GetAttribute("slot")
	if slot and header:GetAttribute("state") ~= "root" and slot ~= header:GetAttribute("active") then return end
	GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
	if b.combo then
		GameTooltip:SetText(LABELS.combo)
		if b.foodID then GameTooltip:AddLine(itemName(b.foodID), 1, 1, 1) end
		if b.drinkID then GameTooltip:AddLine(itemName(b.drinkID), 1, 1, 1) end
	else
		GameTooltip:SetItemByID(b.itemID)
	end
	GameTooltip:Show()
end

-- Wrap before hooking: wrapping sets the script, which drops hooks.
local function newButton(parent, isSlice)
	local b = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate")
	b:SetSize(SIZE, SIZE)
	b:RegisterForClicks("AnyUp")
	-- With the ActionButtonUseKeyDown CVar on, secure buttons act only on
	-- the press unless told otherwise; ours act on the release.
	b:SetAttribute("useOnKeyDown", false)

	local disc = b:CreateTexture(nil, "BACKGROUND")
	disc:SetPoint("CENTER")
	disc:SetSize(SIZE + 8, SIZE + 8)
	disc:SetColorTexture(0, 0, 0, 0.65)
	circle(b, disc)

	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	circle(b, b.icon)

	local hl = b:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.3)
	circle(b, hl)

	b.extra = b:CreateTexture(nil, "OVERLAY")
	b.extra:SetSize(SIZE * 0.55, SIZE * 0.55)
	b.extra:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b.extra:SetPoint("CENTER", b, "TOPRIGHT", -4, -4)
	circle(b, b.extra)

	b.buff = b:CreateTexture(nil, "OVERLAY", nil, 2)
	b.buff:SetAtlas("bags-greenarrow")
	b.buff:SetSize(SIZE * 0.4, SIZE * 0.4)
	b.buff:SetPoint("CENTER", b, "TOPLEFT", 5, -5)
	b.buff:Hide()

	b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	b.count:SetPoint("BOTTOMRIGHT", 2, -2)

	header:WrapScript(b, "OnClick", USE_PRE, USE_POST)
	if isSlice then header:WrapScript(b, "OnEnter", ENTER_SLICE) end
	b:HookScript("OnEnter", showTip)
	b:HookScript("OnLeave", GameTooltip_Hide)
	allButtons[#allButtons + 1] = b
	return b
end

local function updateCount(b)
	if not b.itemID or b.combo then
		b.count:SetText("")
		return
	end
	local n = C_Item.GetItemCount(b.itemID)
	b.count:SetText(n)
	b.icon:SetDesaturated(n == 0)
end

local function setItem(b, id)
	b.itemID, b.combo, b.foodID, b.drinkID = id, nil, nil, nil
	b.icon:SetTexture(C_Item.GetItemIconByID(id))
	b.extra:Hide()
	b.buff:SetShown(wellFed[id] or false)
	b:SetAttribute("type", "item")
	b:SetAttribute("item", "item:" .. id)
	updateCount(b)
end

local function setCombo(b, foodID, drinkID)
	local main, second = foodID or drinkID, foodID and drinkID
	b.itemID, b.combo, b.foodID, b.drinkID = main, true, foodID, drinkID
	b.icon:SetTexture(C_Item.GetItemIconByID(main))
	if second then
		b.extra:SetTexture(C_Item.GetItemIconByID(second))
		b.extra:Show()
	else
		b.extra:Hide()
	end
	b.buff:SetShown((foodID and wellFed[foodID]) or (drinkID and wellFed[drinkID]) or false)
	local lines = {}
	if foodID then lines[#lines + 1] = "/use item:" .. foodID end
	if drinkID then lines[#lines + 1] = "/use item:" .. drinkID end
	b:SetAttribute("type", "macro")
	b:SetAttribute("macrotext", table.concat(lines, "\n"))
	updateCount(b)
end

local rootButtons = {}
for i = 1, #CATEGORIES + 1 do
	local b = newButton(root, true)
	b:SetAttribute("slot", i)
	header:SetFrameRef("slot" .. i, b)
	b:Hide()
	rootButtons[i] = b
end

local subButtons = {}
for i, sub in ipairs(subs) do
	subButtons[i] = {}
	for k = 1, POOL do
		local b = newButton(sub)
		b:Hide()
		subButtons[i][k] = b
	end
end

---------------------------------------------------------------------------
-- Bags

local pending, dirty, queued = false, false, false

local function spellName(id, fallback)
	return C_Spell.GetSpellName(id) or fallback
end

-- Spells the game data knows (Data.lua) are sorted by spell ID, the same
-- in every client language; an item that both feeds and waters lands in
-- both lists. Spells newer than the data fall back to the spell names the
-- client gives in its own language ("Food", "Drink", "First Aid") and to
-- English descriptions for potions and buff food.
local function guess(spell, spellID)
	if spell == spellName(746, "First Aid") then return "firstaid" end
	local isDrink = spell == spellName(430, "Drink")
	local isFood = spell == spellName(433, "Food")
	local desc = C_Spell.GetSpellDescription(spellID)
	if not desc or desc == "" then
		pending = true
		C_Spell.RequestLoadSpellData(spellID)
		return isDrink and "drink" or isFood and "food" or "misc"
	end
	desc = desc:lower()
	if isDrink or isFood then
		local buff = desc:find(spellName(19705, "Well Fed"):lower(), 1, true) or desc:find("well fed", 1, true)
		return isDrink and "drink" or "food", buff ~= nil
	end
	if desc:find("restor") then
		if desc:find("health") or desc:find("life") then return "health" end
		if desc:find("mana") then return "mana" end
	end
	return "misc"
end

local function classify(id)
	local name, _, _, itemLevel, minLevel, _, _, _, _, _, _, classID = C_Item.GetItemInfo(id)
	if not name then
		pending = true
		return
	end
	if classID ~= CONSUMABLE or (minLevel or 0) > UnitLevel("player") then return end
	local spell, spellID = C_Item.GetItemSpell(id)
	if not spell then return end
	local entry = { id = id, level = itemLevel or 0, minLevel = minLevel or 0 }
	if not ns.KNOWN[spellID] then
		local cat, buff = guess(spell, spellID)
		wellFed[id] = buff or nil
		return { cat }, entry
	end
	wellFed[id] = ns.BUFF[spellID]
	local cats = {}
	if ns.DRINK[spellID] then cats[#cats + 1] = "drink" end
	if ns.FOOD[spellID] then cats[#cats + 1] = "food" end
	if ns.FIRSTAID[spellID] then cats[#cats + 1] = "firstaid" end
	if #cats == 0 then
		cats[1] = ns.HEALTH[spellID] and "health" or ns.MANA[spellID] and "mana" or "misc"
	end
	return cats, entry
end

local function better(a, b)
	if a.level ~= b.level then return a.level > b.level end
	if a.minLevel ~= b.minLevel then return a.minLevel > b.minLevel end
	return a.id > b.id
end

local function scan()
	local lists, seen = {}, {}
	for _, cat in ipairs(CATEGORIES) do lists[cat] = {} end
	for bag = 0, NUM_BAG_SLOTS do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local id = C_Container.GetContainerItemID(bag, slot)
			if id and not seen[id] then
				seen[id] = true
				local cats, entry = classify(id)
				for _, cat in ipairs(cats or {}) do table.insert(lists[cat], entry) end
			end
		end
	end
	for _, list in pairs(lists) do table.sort(list, better) end
	return lists
end

---------------------------------------------------------------------------
-- Layout

local function radiusFor(n)
	return math.max(MIN_RADIUS, n * (SIZE + GAP) / (2 * math.pi))
end

-- Offset of slot i (0-based) of n, clockwise from twelve.
local function polar(i, n, radius)
	local a = math.pi / 2 - i / n * 2 * math.pi
	return radius * math.cos(a), radius * math.sin(a)
end

-- Fans a slice's items outside the root ring, centred on the slice's
-- direction, clockwise best to worst. An orbit holds up to a half circle;
-- the rest goes on the next orbit out. Returns the outer orbit's radius.
local function layoutSub(index, list, angle, rootRadius)
	local sub, buttons = subs[index], subButtons[index]
	local n = math.min(#list, POOL)
	local step = SIZE + GAP
	local k, radius = 0, rootRadius
	while k < n do
		radius = radius + step
		local m = math.min(n - k, math.floor(math.pi * radius / step) + 1)
		local da = step / radius
		local first = angle + (m - 1) / 2 * da
		for j = 0, m - 1 do
			local b = buttons[k + j + 1]
			local a = first - j * da
			b:ClearAllPoints()
			b:SetPoint("CENTER", sub, "CENTER", radius * math.cos(a), radius * math.sin(a))
			setItem(b, list[k + j + 1].id)
			b:Show()
		end
		k = k + m
	end
	for j = n + 1, POOL do
		buttons[j].itemID = nil
		buttons[j]:Hide()
	end
	return radius
end

local function rebuild()
	queued = false
	if InCombatLockdown() then
		dirty = true
		return
	end
	dirty, pending = false, false
	local lists = scan()

	local slices = {}
	if #lists.food > 0 or #lists.drink > 0 then
		slices[1] = { combo = true }
	end
	for i, cat in ipairs(CATEGORIES) do
		if #lists[cat] > 0 then
			slices[#slices + 1] = { index = i, list = lists[cat] }
		end
	end

	local n = #slices
	local radius = radiusFor(n)
	local outer = radius
	for i, b in ipairs(rootButtons) do
		local slice = slices[i]
		if slice then
			local x, y = polar(i - 1, n, radius)
			b:ClearAllPoints()
			b:SetPoint("CENTER", root, "CENTER", x, y)
			if slice.combo then
				local food, drink = lists.food[1], lists.drink[1]
				setCombo(b, food and food.id, drink and drink.id)
				b:SetAttribute("sub", nil)
			else
				setItem(b, slice.list[1].id)
				-- One item: its sub-ring would only repeat the slice.
				if #slice.list > 1 then
					b:SetAttribute("sub", slice.index)
					local angle = math.pi / 2 - (i - 1) / n * 2 * math.pi
					outer = math.max(outer, layoutSub(slice.index, slice.list, angle, radius))
				else
					b:SetAttribute("sub", nil)
				end
			end
			b:Show()
		else
			b.itemID = nil
			b:Hide()
		end
	end
	-- The margin holds for the widest fan, so no sub-ring leaves the screen.
	root:SetAttribute("count", n)
	root:SetAttribute("reach", outer + SIZE / 2 + MARGIN)
end

local function queueRebuild()
	if queued then return end
	queued = true
	C_Timer.After(0.2, rebuild)
end

---------------------------------------------------------------------------
-- Events

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
events:RegisterEvent("SPELL_DATA_LOAD_RESULT")
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		RadialConsumablesDB = RadialConsumablesDB or {}
		if not RadialConsumablesDB.defaultKeySet then
			RadialConsumablesDB.defaultKeySet = true
			if not GetBindingKey(ACTION) then
				local taken = GetBindingAction(DEFAULT_KEY)
				if taken and taken ~= "" then
					print("|cffffd200Radial Consumables:|r Alt+F is taken by " .. taken .. "; set a key in Key Bindings > Radial Consumables.")
				else
					SetBinding(DEFAULT_KEY, ACTION)
					SaveBindings(GetCurrentBindingSet())
				end
			end
		end
		queueRebuild()
	elseif event == "BAG_UPDATE_DELAYED" then
		for _, b in ipairs(allButtons) do updateCount(b) end
		queueRebuild()
	elseif event == "PLAYER_REGEN_ENABLED" then
		if dirty then queueRebuild() end
	elseif event == "GET_ITEM_INFO_RECEIVED" or event == "SPELL_DATA_LOAD_RESULT" then
		if pending then queueRebuild() end
	else
		queueRebuild()
	end
end)

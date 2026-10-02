-- PogRaid UI kit: flat panels, buttons, edit boxes, a popup menu and a
-- text prompt. Built from plain textures so nothing depends on Blizzard
-- templates that may differ on this client.
local _, ns = ...

local UI = {}
ns.UI = UI

UI.FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
UI.BG = { 0.06, 0.06, 0.07, 0.96 }
UI.BORDER = { 0.24, 0.24, 0.27, 1 }
UI.BUTTON = { 0.15, 0.15, 0.17, 0 }   -- buttons are outlines; only selected / primary ones fill
UI.CARD = { 0.09, 0.095, 0.11, 1 }     -- cards: a lighter fill instead of an outline
UI.TITLE = { 0.55, 0.56, 0.62 }        -- small capital section titles
UI.BUTTON_BORDER = { 0.30, 0.30, 0.34, 1 }
UI.ACCENT = { 0.40, 0.80, 1.00 }

function UI.Border(f, color, layer)
    local c = color or UI.BORDER
    local function edge(a, b, horizontal)
        local e = f:CreateTexture(nil, layer or "BORDER")
        e:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
        e:SetPoint(a)
        e:SetPoint(b)
        if horizontal then e:SetHeight(1) else e:SetWidth(1) end
        return e
    end
    f.edges = {
        edge("TOPLEFT", "TOPRIGHT", true), edge("BOTTOMLEFT", "BOTTOMRIGHT", true),
        edge("TOPLEFT", "BOTTOMLEFT", false), edge("TOPRIGHT", "BOTTOMRIGHT", false),
    }
end

function UI.SetBorderColor(f, c)
    for _, e in ipairs(f.edges) do e:SetColorTexture(c[1], c[2], c[3], c[4] or 1) end
end

-- A card: filled, no outline. Edges stay empty so SetBorderColor is harmless.
function UI.Card(f, color)
    local c = color or UI.CARD
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    f.edges = {}
end

-- Small, dim, capitalised label for a section ("MESSAGE BOARD").
function UI.SectionTitle(parent, text)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(UI.FONT, 10, "")
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 0.8)
    fs:SetTextColor(UI.TITLE[1], UI.TITLE[2], UI.TITLE[3])
    if text then fs:SetText(text:upper()) end
    return fs
end

-- A thin bar on the right edge of a scrolling list, shown only when the list
-- has more rows than fit. hint:Set(offset, visible, total).
function UI.ScrollHint(frame, top, bottom)
    local tex = frame:CreateTexture(nil, "OVERLAY")
    tex:SetWidth(2)
    tex:SetColorTexture(1, 1, 1, 0.22)
    tex:Hide()
    local hint = { tex = tex, frame = frame, top = top or 4, bottom = bottom or 4 }
    function hint:Set(offset, visible, total)
        if visible <= 0 or total <= visible then
            self.tex:Hide()
            return
        end
        local h = self.frame:GetHeight() - self.top - self.bottom
        local th = math.max(14, h * visible / total)
        local y = (h - th) * math.min(1, math.max(0, offset / (total - visible)))
        self.tex:ClearAllPoints()
        self.tex:SetHeight(th)
        self.tex:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -2, -(self.top + y))
        self.tex:Show()
    end
    return hint
end

function UI.Panel(f, bg, border)
    local c = bg or UI.BG
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    UI.Border(f, border)
end

function UI.Text(parent, size, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    fs:SetFont(UI.FONT, size or 12, "")
    fs:SetTextColor(0.92, 0.92, 0.94)
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 0.8)
    return fs
end

function UI.Button(parent, text, w, h, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)
    UI.Panel(b, UI.BUTTON, UI.BUTTON_BORDER)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.07)
    b.label = UI.Text(b, 11)
    b.label:SetPoint("LEFT", 6, 0)
    b.label:SetPoint("RIGHT", -6, 0)
    b.label:SetJustifyH("CENTER")
    b.label:SetWordWrap(false)
    b.label:SetText(text or "")
    b:RegisterForClicks("LeftButtonUp")
    if onClick then b:SetScript("OnClick", onClick) end

    function b:SetLabel(t) self.label:SetText(t) end
    function b:SetSelected(on)
        self.selected = on
        if on then
            self.bg:SetColorTexture(0.12, 0.26, 0.34, 1)
            UI.SetBorderColor(self, { UI.ACCENT[1], UI.ACCENT[2], UI.ACCENT[3], 1 })
        else
            self.bg:SetColorTexture(UI.BUTTON[1], UI.BUTTON[2], UI.BUTTON[3], UI.BUTTON[4])
            UI.SetBorderColor(self, UI.BUTTON_BORDER)
        end
    end
    function b:SetPrimary()
        self.bg:SetColorTexture(0.10, 0.36, 0.52, 1)
        UI.SetBorderColor(self, { 0.30, 0.62, 0.82, 1 })
    end
    function b:SetEnabledState(on)
        self:SetEnabled(on)
        self.label:SetAlpha(on and 1 or 0.4)
    end
    return b
end

-- Two-click confirm for destructive buttons: the first click turns the
-- label into "Sure?", a second click within 3 seconds does it.
function UI.ConfirmClick(btn, action)
    local label = btn.baseLabel or btn.label:GetText()
    btn.baseLabel = label
    if btn.armed then
        btn.armed = nil
        btn:SetLabel(label)
        action()
        return
    end
    btn.armed = true
    btn:SetLabel("Sure?")
    C_Timer.After(3, function()
        if btn.armed then
            btn.armed = nil
            btn:SetLabel(label)
        end
    end)
end

-- Square button holding a texture (raid markers, colour swatches).
function UI.IconButton(parent, size, onClick)
    local b = UI.Button(parent, "", size, size, onClick)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 3, -3)
    b.icon:SetPoint("BOTTOMRIGHT", -3, 3)
    return b
end

function UI.EditBox(parent, w, h)
    local e = CreateFrame("EditBox", nil, parent)
    e:SetSize(w, h)
    e:SetAutoFocus(false)
    e:SetFont(UI.FONT, 12, "")
    e:SetTextColor(1, 1, 1)
    e:SetTextInsets(7, 7, 0, 0)
    UI.Panel(e, { 0.02, 0.02, 0.03, 1 }, UI.BUTTON_BORDER)
    e:SetScript("OnEscapePressed", e.ClearFocus)
    e:SetScript("OnEditFocusGained", function(self) UI.SetBorderColor(self, UI.ACCENT) end)
    e:SetScript("OnEditFocusLost", function(self) UI.SetBorderColor(self, UI.BUTTON_BORDER) end)
    return e
end

function UI.MakeMovable(f, handle, onStop)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    handle:SetScript("OnDragStart", function() f:StartMoving() end)
    handle:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        if onStop then onStop() end
    end)
end

-- Save/restore a frame's centre as an offset from UIParent's centre, in
-- UIParent units (GetPoint is unreliable after StartMoving).
function UI.SavePosition(f, key)
    local x, y = f:GetCenter()
    local ux, uy = UIParent:GetCenter()
    local s = f:GetScale()
    if not x or not ux then return end
    ns.db.frames[key] = { x = x * s - ux, y = y * s - uy }
end

function UI.RestorePosition(f, key, defaultY)
    local p = ns.db.frames[key]
    local s = f:GetScale()
    f:ClearAllPoints()
    if p then
        f:SetPoint("CENTER", UIParent, "CENTER", p.x / s, p.y / s)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, (defaultY or 0) / s)
    end
end

------------------------------------------------------------------------
-- Popup menu: UI.ShowMenu(anchor, entries)
-- entry = { text, func, color = {r,g,b}, disabled = bool, header = bool }
------------------------------------------------------------------------
local ROW_H, ROWS_PER_COL, MENU_PAD = 20, 20, 4
local menu

local function hideMenu()
    if menu then menu:Hide() end
end
UI.HideMenu = hideMenu

local function buildMenu()
    menu = CreateFrame("Frame", nil, UIParent)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    UI.Panel(menu, { 0.05, 0.05, 0.06, 0.98 }, UI.BORDER)
    menu.rows = {}
    menu:Hide()
    menu:SetScript("OnEvent", function(self)
        if self:IsShown() and not self:IsMouseOver() and not (self.anchor and self.anchor:IsMouseOver()) then
            self:Hide()
        end
    end)
    pcall(menu.RegisterEvent, menu, "GLOBAL_MOUSE_DOWN")
end

function UI.ShowMenu(anchor, entries)
    if not menu then buildMenu() end
    if menu:IsShown() and menu.anchor == anchor then
        menu:Hide()
        return
    end
    menu.anchor = anchor
    local widest = anchor:GetWidth() - 2 * MENU_PAD
    for i, entry in ipairs(entries) do
        local row = menu.rows[i]
        if not row then
            row = CreateFrame("Button", nil, menu)
            row:SetHeight(ROW_H)
            local hl = row:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0.08)
            row.label = UI.Text(row, 11)
            row.label:SetPoint("LEFT", 6, 0)
            row.label:SetJustifyH("LEFT")
            row:SetScript("OnClick", function(self)
                hideMenu()
                if self.func then self.func() end
            end)
            menu.rows[i] = row
        end
        row.func = entry.func
        row.label:SetText(entry.text)
        local c = entry.color or (entry.header and { 0.55, 0.55, 0.6 }) or { 0.92, 0.92, 0.94 }
        row.label:SetTextColor(c[1], c[2], c[3])
        row:SetEnabled(not (entry.disabled or entry.header))
        row.label:SetAlpha(entry.disabled and 0.45 or 1)
        widest = math.max(widest, row.label:GetStringWidth() + 16)
        row:Show()
    end
    for i = #entries + 1, #menu.rows do menu.rows[i]:Hide() end

    local cols = math.max(1, math.ceil(#entries / ROWS_PER_COL))
    local rows = math.min(#entries, ROWS_PER_COL)
    local colW = math.ceil(widest)
    for i = 1, #entries do
        local row = menu.rows[i]
        local col = math.floor((i - 1) / ROWS_PER_COL)
        local r = (i - 1) % ROWS_PER_COL
        row:ClearAllPoints()
        row:SetWidth(colW)
        row:SetPoint("TOPLEFT", menu, "TOPLEFT", MENU_PAD + col * colW, -MENU_PAD - r * ROW_H)
    end
    menu:SetSize(cols * colW + 2 * MENU_PAD, math.max(1, rows) * ROW_H + 2 * MENU_PAD)
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    menu:Show()
end

------------------------------------------------------------------------
-- Picker: a grid of icons or colour swatches under a button.
-- items = { { tex = file, color = {r,g,b}, tip = text, selected = bool } },
-- or plain textures (long icon lists stay light): then `selected` is an index
-- and `tips` maps texture -> tooltip. onPick(index). Clicking the same button
-- again closes it. With `rows`, longer lists get pages (< > under the grid,
-- or the mouse wheel), opening on the page with the selected item.
------------------------------------------------------------------------
local picker
local PICK_GAP, PICK_PAD, PICK_NAV = 3, 6, 26

local function pickerCell(i, size)
    local b = picker.cells[i]
    if not b then
        b = UI.IconButton(picker, size, function(self)
            picker:Hide()
            if picker.onPick then picker.onPick(self.index) end
        end)
        b:SetScript("OnEnter", function(self)
            if not self.tip or not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.tip, 1, 1, 1)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        picker.cells[i] = b
    end
    return b
end

local function pickerPage()
    local p = picker
    local per = p.cols * p.rows
    local pages = math.max(1, math.ceil(#p.items / per))
    p.page = math.max(1, math.min(p.page, pages))
    local first = (p.page - 1) * per
    local shownCells = math.min(per, #p.items)
    for i = 1, shownCells do
        local b = pickerCell(i, p.size)
        local it = p.items[first + i]
        if it then
            local plain = type(it) ~= "table"
            local tex = plain and it or it.tex
            b.index, b.tip = first + i, plain and p.tips and p.tips[it] or (not plain and it.tip) or nil
            b:SetSize(p.size, p.size)
            if not plain and it.color then
                b.icon:SetColorTexture(it.color[1], it.color[2], it.color[3], 1)
            else
                b.icon:SetTexture(tex)
                b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            end
            b:SetSelected((not plain and it.selected) or first + i == p.selected)
            local col, row = (i - 1) % p.cols, math.floor((i - 1) / p.cols)
            b:ClearAllPoints()
            b:SetPoint("TOPLEFT", p, "TOPLEFT", PICK_PAD + col * (p.size + PICK_GAP), -(PICK_PAD + row * (p.size + PICK_GAP)))
            b:Show()
        else
            b:Hide()
        end
    end
    for i = shownCells + 1, #p.cells do p.cells[i]:Hide() end
    p.nav:SetShown(pages > 1)
    p.pageText:SetText(("Page %d of %d"):format(p.page, pages))
    p.prev:SetEnabledState(p.page > 1)
    p.next:SetEnabledState(p.page < pages)
    p.pages = pages
end

function UI.Picker(anchor, items, cols, size, onPick, rows, selected, tips)
    if not picker then
        picker = CreateFrame("Frame", nil, UIParent)
        picker:SetFrameStrata("FULLSCREEN_DIALOG")
        picker:SetClampedToScreen(true)
        picker:EnableMouse(true)
        UI.Panel(picker, { 0.05, 0.05, 0.06, 0.98 }, UI.BORDER)
        picker.cells = {}
        picker:Hide()
        picker:SetScript("OnEvent", function(self)
            if self:IsShown() and not self:IsMouseOver() and not (self.anchor and self.anchor:IsMouseOver()) then
                self:Hide()
            end
        end)
        pcall(picker.RegisterEvent, picker, "GLOBAL_MOUSE_DOWN")
        local nav = CreateFrame("Frame", nil, picker)
        nav:SetPoint("BOTTOMLEFT", PICK_PAD, PICK_PAD)
        nav:SetPoint("BOTTOMRIGHT", -PICK_PAD, PICK_PAD)
        nav:SetHeight(PICK_NAV - PICK_GAP)
        picker.nav = nav
        local function turn(d)
            picker.page = picker.page + d
            pickerPage()
        end
        picker.prev = UI.Button(nav, "<", 30, 20, function() turn(-1) end)
        picker.prev:SetPoint("LEFT", 0, 0)
        picker.next = UI.Button(nav, ">", 30, 20, function() turn(1) end)
        picker.next:SetPoint("RIGHT", 0, 0)
        picker.pageText = UI.Text(nav, 11)
        picker.pageText:SetPoint("CENTER", 0, 0)
        picker.pageText:SetTextColor(0.7, 0.7, 0.75)
        picker:EnableMouseWheel(true)
        picker:SetScript("OnMouseWheel", function(_, d) turn(-d) end)
        UI.pickerFrame = picker
    end
    if picker:IsShown() and picker.anchor == anchor then
        picker:Hide()
        return
    end
    picker.anchor = anchor
    picker.onPick = onPick
    picker.items, picker.cols, picker.size, picker.selected, picker.tips = items, cols, size, selected, tips
    picker.rows = rows or math.max(1, math.ceil(#items / cols))
    picker.page = 1
    if not selected then
        for i, it in ipairs(items) do
            if type(it) == "table" and it.selected then selected = i end
        end
    end
    if selected then picker.page = math.floor((selected - 1) / (cols * picker.rows)) + 1 end
    pickerPage()
    local shownRows = math.min(picker.rows, math.max(1, math.ceil(#items / cols)))
    local shownCols = math.min(cols, #items)
    picker:SetSize(2 * PICK_PAD + shownCols * size + (shownCols - 1) * PICK_GAP,
        2 * PICK_PAD + shownRows * size + (shownRows - 1) * PICK_GAP + (picker.pages > 1 and PICK_NAV or 0))
    picker:ClearAllPoints()
    picker:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    picker:Show()
end

------------------------------------------------------------------------
-- Text prompt: a small edit box that floats where you need it.
------------------------------------------------------------------------
local prompt

function UI.Prompt(anchorFrame, x, y, label, initial, onAccept)
    if not prompt then
        prompt = CreateFrame("Frame", nil, UIParent)
        prompt:SetFrameStrata("FULLSCREEN_DIALOG")
        prompt:SetSize(220, 52)
        prompt:EnableMouse(true)
        UI.Panel(prompt, { 0.05, 0.05, 0.06, 0.98 }, UI.ACCENT)
        prompt.label = UI.Text(prompt, 11)
        prompt.label:SetPoint("TOPLEFT", 8, -6)
        prompt.label:SetTextColor(0.7, 0.7, 0.75)
        prompt.box = UI.EditBox(prompt, 204, 22)
        prompt.box:SetPoint("BOTTOMLEFT", 8, 7)
        prompt.box:SetScript("OnEnterPressed", function(self)
            local text = self:GetText()
            local cb = prompt.onAccept
            prompt:Hide()
            if cb then cb(text) end
        end)
        prompt.box:SetScript("OnEscapePressed", function() prompt:Hide() end)
        prompt.box:HookScript("OnEditFocusLost", function() prompt:Hide() end)
        UI.promptFrame = prompt
    end
    prompt.onAccept = onAccept
    prompt.label:SetText(label)
    prompt:ClearAllPoints()
    prompt:SetPoint("TOPLEFT", anchorFrame, "TOPLEFT", x, y)
    prompt:Show()
    prompt.box:SetText(initial or "")
    prompt.box:SetFocus()
    prompt.box:HighlightText()
end

------------------------------------------------------------------------
-- Copy box: read-only multi-line text, pre-selected for Ctrl+C.
------------------------------------------------------------------------
local copy

function UI.CopyBox(title, text)
    if not copy then
        copy = CreateFrame("Frame", "PogRaidCopy", UIParent)
        copy:SetSize(460, 340)
        copy:SetFrameStrata("FULLSCREEN_DIALOG")
        copy:SetPoint("CENTER")
        copy:EnableMouse(true)
        UI.Panel(copy)
        tinsert(UISpecialFrames, "PogRaidCopy")
        UI.MakeMovable(copy, copy)
        copy.title = UI.Text(copy, 12)
        copy.title:SetPoint("TOPLEFT", 12, -10)
        local close = UI.Tab(copy, "X", 28, 30, function() copy:Hide() end)
        close:SetPoint("TOPRIGHT", -4, 0)
        local hint = UI.Text(copy, 10)
        hint:SetPoint("BOTTOMLEFT", 12, 10)
        hint:SetTextColor(0.55, 0.55, 0.6)
        hint:SetText("Ctrl+C to copy, Esc to close")

        local area = CreateFrame("ScrollFrame", nil, copy)
        area:SetPoint("TOPLEFT", 12, -36)
        area:SetPoint("BOTTOMRIGHT", -12, 30)
        local bg = area:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.02, 0.02, 0.03, 1)
        local edit = CreateFrame("EditBox", nil, area)
        edit:SetMultiLine(true)
        edit:SetAutoFocus(false)
        edit:SetFont(UI.FONT, 12, "")
        edit:SetTextColor(1, 1, 1)
        edit:SetWidth(436)
        edit:SetTextInsets(6, 6, 6, 6)
        area:SetScrollChild(edit)
        area:EnableMouseWheel(true)
        area:SetScript("OnMouseWheel", function(self, delta)
            local max = math.max(0, edit:GetHeight() - self:GetHeight())
            self:SetVerticalScroll(math.min(max, math.max(0, self:GetVerticalScroll() - delta * 36)))
        end)
        edit:SetScript("OnEscapePressed", function() copy:Hide() end)
        -- read-only: typing puts the original text back
        edit:SetScript("OnTextChanged", function(self, userInput)
            if userInput then
                self:SetText(copy.text)
                self:HighlightText()
            end
        end)
        copy.edit = edit
    end
    copy.text = text
    copy.title:SetText(title)
    copy:Show()
    copy.edit:SetText(text)
    copy.edit:SetFocus()
    copy.edit:HighlightText()
end

------------------------------------------------------------------------
-- Compose: a small dialog with up to two one-line fields and a text area.
-- opts = { heading, label1, labelMid, label2, max1, maxMid, max2, text1,
-- textMid, text2, button, optional, noArea }. onSubmit(text1, text2, textMid).
-- Enter moves to the next box; Enter in the last one submits. `noArea`: only
-- the one-line fields.
------------------------------------------------------------------------
local compose

function UI.Compose(opts, onSubmit)
    if not compose then
        compose = CreateFrame("Frame", "PogRaidCompose", UIParent)
        compose:SetSize(400, 250)
        compose:SetFrameStrata("FULLSCREEN_DIALOG")
        compose:SetPoint("CENTER", 0, 80)
        compose:EnableMouse(true)
        UI.Panel(compose, { 0.05, 0.05, 0.06, 0.98 }, UI.ACCENT)
        tinsert(UISpecialFrames, "PogRaidCompose")
        UI.MakeMovable(compose, compose)
        compose.heading = UI.Text(compose, 13)
        compose.heading:SetPoint("TOPLEFT", 12, -10)
        compose.label1 = UI.Text(compose, 11)
        compose.label1:SetPoint("TOPLEFT", 12, -34)
        compose.label1:SetTextColor(0.6, 0.6, 0.65)
        compose.field1 = UI.EditBox(compose, 376, 24)
        compose.field1:SetPoint("TOPLEFT", 12, -50)
        compose.labelMid = UI.Text(compose, 11)
        compose.labelMid:SetTextColor(0.6, 0.6, 0.65)
        compose.fieldMid = UI.EditBox(compose, 376, 24)
        compose.label2 = UI.Text(compose, 11)
        compose.label2:SetTextColor(0.6, 0.6, 0.65)
        local area = CreateFrame("Frame", nil, compose)
        area:SetSize(376, 96)
        UI.Panel(area, { 0.02, 0.02, 0.03, 1 }, UI.BUTTON_BORDER)
        compose.area = area
        local body = CreateFrame("EditBox", nil, area)
        body:SetMultiLine(true)
        body:SetAutoFocus(false)
        body:SetFont(UI.FONT, 12, "")
        body:SetTextColor(1, 1, 1)
        body:SetPoint("TOPLEFT", 6, -6)
        body:SetPoint("BOTTOMRIGHT", -6, 6)
        compose.field2 = body
        area:EnableMouse(true)
        area:SetScript("OnMouseDown", function() body:SetFocus() end)
        compose.count = UI.Text(compose, 10)
        compose.count:SetPoint("TOPRIGHT", area, "BOTTOMRIGHT", 0, -6)
        compose.count:SetTextColor(0.5, 0.5, 0.55)
        compose.submit = UI.Button(compose, "Post", 90, 24)
        compose.submit:SetPoint("BOTTOMRIGHT", -12, 12)
        compose.submit:SetPrimary()
        local cancel = UI.Button(compose, "Cancel", 80, 24, function() compose:Hide() end)
        cancel:SetPoint("RIGHT", compose.submit, "LEFT", -6, 0)

        local function submit()
            local a, b = compose.field1:GetText(), compose.field2:GetText()
            -- `optional`: empty boxes are fine (they clear what was there)
            if not compose.opts.optional then
                if compose.opts.label1 and a:gsub("%s", "") == "" then
                    compose.field1:SetFocus()
                    return
                end
                if not compose.opts.label1 and b:gsub("%s", "") == "" then return end
            end
            local mid = compose.fieldMid:GetText()
            local cb = compose.onSubmit
            compose:Hide()
            if cb then cb(a, b, mid) end
        end
        compose.submit:SetScript("OnClick", submit)
        compose.field1:SetScript("OnEnterPressed", function()
            if compose.fieldMid:IsShown() then
                compose.fieldMid:SetFocus()
            elseif compose.opts.noArea then
                submit()
            else
                body:SetFocus()
            end
        end)
        compose.field1:SetScript("OnEscapePressed", function() compose:Hide() end)
        compose.fieldMid:SetScript("OnEnterPressed", function()
            if compose.opts.noArea then submit() else body:SetFocus() end
        end)
        compose.fieldMid:SetScript("OnEscapePressed", function() compose:Hide() end)
        body:SetScript("OnEnterPressed", submit)
        body:SetScript("OnEscapePressed", function() compose:Hide() end)
        local function limit(box, max)
            box:SetScript("OnTextChanged", function(self)
                local t = self:GetText()
                if #t > max then self:SetText(t:sub(1, max)) end
                if self == body then compose.count:SetText(("%d / %d"):format(#self:GetText(), max)) end
            end)
        end
        compose.limit = limit
        UI.composeFrame = compose
    end
    compose.opts = opts
    compose.onSubmit = onSubmit
    compose.heading:SetText(opts.heading or "")
    compose.submit:SetLabel(opts.button or "Post")
    -- stack the boxes: each one-line field takes 50px, then the text area
    local has1, hasMid = opts.label1 ~= nil, opts.labelMid ~= nil
    local y = -34
    local function place(label, box, shown)
        label:SetShown(shown)
        box:SetShown(shown)
        if not shown then return end
        label:ClearAllPoints()
        label:SetPoint("TOPLEFT", 12, y)
        box:ClearAllPoints()
        box:SetPoint("TOPLEFT", 12, y - 16)
        y = y - 50
    end
    place(compose.label1, compose.field1, has1)
    place(compose.labelMid, compose.fieldMid, hasMid)
    compose.label1:SetText(opts.label1 or "")
    compose.labelMid:SetText(opts.labelMid or "")
    compose.label2:ClearAllPoints()
    compose.label2:SetPoint("TOPLEFT", 12, y)
    compose.label2:SetText(opts.label2 or "")
    compose.area:ClearAllPoints()
    compose.area:SetPoint("TOPLEFT", 12, y - 16)
    local area = not opts.noArea
    compose.label2:SetShown(area)
    compose.area:SetShown(area)
    compose.count:SetShown(area)
    compose:SetHeight(area and (-y + 16 + 96 + 54) or (-y + 50))
    compose.limit(compose.field1, opts.max1 or 60)
    compose.limit(compose.fieldMid, opts.maxMid or 60)
    compose.limit(compose.field2, opts.max2 or 300)
    compose.fieldMid:SetText(opts.textMid or "")
    compose.field1:SetText(opts.text1 or "")
    compose.field2:SetText(opts.text2 or "")
    compose.count:SetText(("%d / %d"):format(#(opts.text2 or ""), opts.max2 or 300))
    compose:Show()
    if has1 then compose.field1:SetFocus() else compose.field2:SetFocus() end
end

------------------------------------------------------------------------
-- Tab: navigation text with an underline when selected, no box, so it
-- reads differently from the action buttons on each page.
------------------------------------------------------------------------
UI.TAB_TEXT = { 0.62, 0.62, 0.68 }
UI.TAB_HOVER = { 0.88, 0.88, 0.92 }

function UI.Tab(parent, text, w, h, onClick, size)
    local t = CreateFrame("Button", nil, parent)
    t:SetSize(w, h)
    t.label = t:CreateFontString(nil, "OVERLAY")
    t.label:SetFont(UI.FONT, size or 13, "")
    t.label:SetShadowOffset(1, -1)
    t.label:SetShadowColor(0, 0, 0, 0.8)
    t.label:SetPoint("CENTER", 0, 1)
    t.label:SetText(text)
    t.label:SetTextColor(UI.TAB_TEXT[1], UI.TAB_TEXT[2], UI.TAB_TEXT[3])
    t.underline = t:CreateTexture(nil, "OVERLAY")
    t.underline:SetHeight(2)
    t.underline:SetPoint("BOTTOM", 0, 0)
    t.underline:SetWidth(math.min(w, t.label:GetStringWidth() + 16))
    t.underline:SetColorTexture(UI.ACCENT[1], UI.ACCENT[2], UI.ACCENT[3], 1)
    t.underline:Hide()
    t:SetScript("OnClick", onClick)
    t:SetScript("OnEnter", function(self)
        if not self.selected then self.label:SetTextColor(UI.TAB_HOVER[1], UI.TAB_HOVER[2], UI.TAB_HOVER[3]) end
    end)
    t:SetScript("OnLeave", function(self)
        if not self.selected then self.label:SetTextColor(UI.TAB_TEXT[1], UI.TAB_TEXT[2], UI.TAB_TEXT[3]) end
    end)
    function t:SetSelected(on)
        self.selected = on
        self.underline:SetShown(on)
        local c = on and { 1, 1, 1 } or UI.TAB_TEXT
        self.label:SetTextColor(c[1], c[2], c[3])
    end
    return t
end

------------------------------------------------------------------------
-- Check: a small box and a label. get() -> bool, set(bool). Call
-- :Update() to re-read the value; :SetEnabledState(on) greys it out.
------------------------------------------------------------------------
function UI.Check(parent, label, get, set)
    local c = CreateFrame("Button", nil, parent)
    c:SetSize(300, 22)
    c.box = CreateFrame("Frame", nil, c)
    c.box:SetSize(14, 14)
    c.box:SetPoint("LEFT", 0, 0)
    UI.Panel(c.box, { 0.02, 0.02, 0.03, 1 }, UI.BUTTON_BORDER)
    c.mark = c.box:CreateTexture(nil, "ARTWORK")
    c.mark:SetPoint("TOPLEFT", 3, -3)
    c.mark:SetPoint("BOTTOMRIGHT", -3, 3)
    c.mark:SetColorTexture(UI.ACCENT[1], UI.ACCENT[2], UI.ACCENT[3], 1)
    c.label = UI.Text(c, 12)
    c.label:SetPoint("LEFT", c.box, "RIGHT", 8, 0)
    c.label:SetText(label)
    c.enabled = true
    function c:Update()
        self.checked = get() and true or false
        self.mark:SetShown(self.checked)
    end
    function c:SetEnabledState(on)
        self.enabled = on
        self:SetAlpha(on and 1 or 0.45)
    end
    c:SetScript("OnClick", function(self)
        if not self.enabled then return end
        set(not self.checked)
        self:Update()
    end)
    c:SetScript("OnEnter", function(self) if self.enabled then UI.SetBorderColor(self.box, UI.ACCENT) end end)
    c:SetScript("OnLeave", function(self) UI.SetBorderColor(self.box, UI.BUTTON_BORDER) end)
    c:Update()
    return c
end

-- PogRaid headless tests. Run via run_tests.py.
local ADDON_DIR = ...
local results = { pass = 0, fail = 0, failures = {} }

local function check(cond, name)
    if cond then
        results.pass = results.pass + 1
    else
        results.fail = results.fail + 1
        table.insert(results.failures, name)
    end
end

local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-6) end

local function lastPrint()
    return STUB.printed[#STUB.printed] or ""
end

local function printedContains(s)
    for _, m in ipairs(STUB.printed) do
        if m:find(s, 1, true) then return true end
    end
    return false
end

-- Load the addon in .toc order --------------------------------------------
local ns = {}
local toc = {}
for line in io.lines(ADDON_DIR .. "/PogRaid.toc") do
    if line:match("%.lua$") then toc[#toc + 1] = line end
end
for _, file in ipairs(toc) do
    local chunk = assert(loadfile(ADDON_DIR .. "/" .. file))
    chunk("PogRaid", ns)
end
ns.DEV = nil -- (the tests run a release build; the dev build has its own checks)
STUB.Fire("ADDON_LOADED", "PogRaid")
STUB.Fire("PLAYER_LOGIN")

check(ns.db ~= nil and #ns.db.order == 1, "load: first board created")
check(STUB.prefix == "PogRaid", "load: addon prefix registered")
check(SlashCmdList.POGRAID ~= nil, "load: slash command registered")
check(ns.On("NOT_A_REAL_EVENT", function() end) == false, "events: unknown event fails quietly")
do
    local title
    for line in io.lines(ADDON_DIR .. "/PogRaid.toc") do title = title or line:match("^## Title: (.+)$") end
    ns.Print("hello")
    check(title == "Pog Guild Tools" and STUB.printed[#STUB.printed] == "|cff66ccffPog Guild Tools|r: hello",
        "name: Pog Guild Tools in the AddOns list and in chat")
end

-- Codec ---------------------------------------------------------------------
local Codec = ns.Codec
do
    local board = {
        name = "Boss; 100% | hard", map = 2001, zoom = 2.5, cx = 0.31, cy = 0.62,
        items = {
            { t = "mark", i = 8, x = 0.1, y = 0.2 },
            { t = "dot", name = "Jake", class = "HUNTER", x = 0.5, y = 0.5 },
            { t = "dot", name = "Nameless", x = 0.9, y = 0.9 },
            { t = "group", g = "H", x = 0.25, y = 0.75 },
            { t = "arrow", c = 3, x1 = 0, y1 = 0, x2 = 1, y2 = 1 },
            { t = "circle", c = 1, x = 0.4, y = 0.4, r = 0.12 },
            { t = "text", c = 2, x = 0.6, y = 0.3, s = "Soak;here %20 |cffff0000x" },
        },
    }
    local s = Codec.Encode(board)
    check(not s:find("|", 1, true), "codec: no pipe characters on the wire")
    local out = assert(Codec.Decode(s))
    check(out.name == "Boss; 100% / hard", "codec: name escapes round trip")
    check(out.map == 2001 and near(out.zoom, 2.5) and near(out.cx, 0.31, 1 / 4095) and near(out.cy, 0.62, 1 / 4095),
        "codec: header round trip")
    check(#out.items == 7, "codec: all items decode")
    local m = out.items[1]
    check(m.t == "mark" and m.i == 8 and near(m.x, 0.1, 1 / 4095) and near(m.y, 0.2, 1 / 4095), "codec: marker")
    check(out.items[2].class == "HUNTER" and out.items[2].name == "Jake", "codec: player dot with class")
    check(out.items[3].class == nil and out.items[3].name == "Nameless", "codec: player dot without class")
    check(out.items[4].t == "group" and out.items[4].g == "H", "codec: group dot")
    local a = out.items[5]
    check(a.t == "arrow" and a.c == 3 and a.x1 == 0 and a.y2 == 1, "codec: arrow")
    local c = out.items[6]
    check(c.t == "circle" and near(c.r, 0.12, 1 / 4095), "codec: circle")
    check(out.items[7].s == "Soak;here %20 /cffff0000x", "codec: text escapes round trip, pipes neutralised")

    check(Codec.Decode("nope") == nil, "codec: rejects unknown format")
    check(Codec.Decode("KR1;0;100") == nil, "codec: rejects truncated header")
    local junk = assert(Codec.Decode("KR1;0;100;gAgA;X;M9AAAA;Zzz;A1AAAA;M1AAAA"))
    check(#junk.items == 1 and junk.items[1].i == 1, "codec: drops invalid items, keeps valid ones")
    check(junk.map == nil, "codec: map 0 means blank board")

    local many = { name = "Big", items = {} }
    for i = 1, 200 do many.items[i] = { t = "mark", i = 1, x = 0.5, y = 0.5 } end
    check(#Codec.Decode(Codec.Encode(many)).items == Codec.MAX_ITEMS, "codec: item cap enforced")
    check(Codec.CleanText("a\nb\tc", 60) == "a b c", "codec: control characters stripped")
end

-- Canvas layout ---------------------------------------------------------------
do
    local c = ns.CreateCanvas(UIParent, 600, 400)
    c.frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 100, -100)
    c:SetMap(1453)
    check(c.hasArt and c.numTiles == 12, "canvas: 4x3 tiles for a 1002x668 map")
    check(near(c.mw, 600, 1e-6) and near(c.mh, 600 * 668 / 1002, 1e-6), "canvas: zoom 1 fits map width")
    check(near(c.oy, (400 - c.mh) / 2, 1e-6), "canvas: letterboxed map is centred vertically")
    local wide = ns.CreateCanvas(UIParent, 800, 400)
    wide:SetMap(1453)
    check(near(wide.mh, 400, 1e-6) and near(wide.ox, (800 - wide.mw) / 2, 1e-6) and wide.ox > 0,
        "canvas: pillarboxed map is centred horizontally")
    -- zoom around a point keeps it under the cursor
    local nx, ny = 0.3, 0.6
    local sx, sy = c.ox + nx * c.mw, c.oy + ny * c.mh
    c:ZoomAt(2, nx, ny)
    check(c.zoom > 1.5, "canvas: wheel zooms in")
    check(near(c.ox + nx * c.mw, sx, 1e-6) and near(c.oy + ny * c.mh, sy, 1e-6), "canvas: zoom keeps the cursor point fixed")
    c:Pan(10000, -10000)
    check(near(c.ox, 0) and near(c.oy, 0), "canvas: pan clamps at the map's top-left edge")
    c:SetMap(nil)
    check(not c.hasArt and #c.gridLines > 0, "canvas: blank board draws a grid")
    c:SetView(1, 0.5, 0.5)
    c:SetItems({
        { t = "mark", i = 1, x = 0.5, y = 0.5 },
        { t = "arrow", c = 1, x1 = 0.1, y1 = 0.1, x2 = 0.3, y2 = 0.1 },
        { t = "circle", c = 2, x = 0.8, y = 0.5, r = 0.1 },
    })
    check(c:HitTest(0.5, 0.5) == 1, "canvas: hit marker")
    check(c:HitTest(0.2, 0.1) == 2, "canvas: hit arrow shaft")
    check(c:HitTest(0.9, 0.5) == 3, "canvas: hit circle edge")
    check(c:HitTest(0.8, 0.5) == 3, "canvas: hit circle centre")
    check(c:HitTest(0.83, 0.45) == 3, "canvas: hit anywhere inside a circle")
    check(c:HitTest(0.65, 0.2) == nil, "canvas: miss on empty space")
    -- a marker drawn before a circle, sitting inside it, still wins
    c:SetItems({
        { t = "mark", i = 1, x = 0.5, y = 0.5 },
        { t = "circle", c = 1, x = 0.5, y = 0.5, r = 0.2 },
        { t = "circle", c = 2, x = 0.55, y = 0.5, r = 0.05 },
    })
    check(c:HitTest(0.5, 0.5) == 1, "canvas: marker inside a circle beats the circle")
    check(c:HitTest(0.56, 0.5) == 3, "canvas: smaller of two overlapping circles wins")
    check(c:HitTest(0.4, 0.5) == 2, "canvas: big circle still hit outside the small one")
    local function shown(pool)
        local n = 0
        for i = 1, #pool do if pool[i]:IsShown() then n = n + 1 end end
        return n
    end
    check(shown(c.pools.line) > 16, "canvas: circle outlines drawn")
    c:SetItems({ { t = "mark", i = 1, x = 0.5, y = 0.5 } })
    check(shown(c.pools.line) == 0 and shown(c.pools.tex) == 1, "canvas: deleted circles leave nothing behind")
    c:SetHighlight("Jake", nil)
    c:SetItems({ { t = "dot", name = "Jake", class = "HUNTER", x = 0.5, y = 0.5 } })
    check(#c.pulsing == 1 and c.frame.__scripts.OnUpdate ~= nil, "canvas: own dot pulses")
    c:SetItems({})
    check(c.frame.__scripts.OnUpdate == nil, "canvas: pulse stops when nothing to highlight")
end

-- Solo send: board goes to yourself and opens the viewer -----------------------
local Editor, Viewer, Comm = ns.Editor, ns.Viewer, ns.Comm
do
    SlashCmdList.POGRAID("")
    check(PogRaidEditor and PogRaidEditor:IsShown() and Editor.currentTab == "home", "window: /pog opens on Home")
    SlashCmdList.POGRAID("boards")
    check(Editor.currentTab == "boards", "window: /pog boards switches tab")
    local b = ns.db.boards[Editor.id]
    b.items = { { t = "mark", i = 2, x = 0.5, y = 0.5 } }
    Editor.canvas:SetItems(b.items)
    Editor:SendCurrent()
    check(#STUB.sent == 1 and STUB.sent[1].channel == "WHISPER" and STUB.sent[1].target == "Jake", "send: solo sends a self whisper")
    STUB.Deliver("Jake-Realm")
    check(PogRaidViewer and PogRaidViewer:IsShown(), "viewer: solo test opens the viewer")
    check(#Viewer.canvas.items == 1 and Viewer.canvas.items[1].i == 2, "viewer: shows the sent items")
    PogRaidViewer:Hide()
end

-- Chunking, out-of-order and duplicate chunks ------------------------------------
do
    local big = { name = "Big", items = {} }
    for i = 1, 60 do big.items[i] = { t = "text", c = 5, x = i / 60, y = 0.5, s = ("label number %02d"):format(i) } end
    local ok, channel, parts = Comm.SendBoard(big)
    check(ok and parts > 3 and #STUB.sent == parts, "comm: large board splits into chunks")
    local order = {}
    for i = parts, 1, -1 do order[#order + 1] = i end
    order[#order + 1] = 1 -- duplicate of the first chunk, must be ignored
    STUB.Deliver("Jake-Realm", order)
    check(PogRaidViewer:IsShown() and #Viewer.canvas.items == 60, "comm: chunks reassemble out of order")
    PogRaidViewer:Hide()
end

-- Trust: raid boards only from leader/assistants ----------------------------------
do
    STUB.roster = {
        { name = "Jake", rank = 2, class = "HUNTER" },
        { name = "Mira-OtherRealm", rank = 1, class = "MAGE" },
        { name = "Bob", rank = 0, class = "WARRIOR" },
    }
    Comm.SendBoard({ name = "From Bob", items = {} })
    check(STUB.sent[1].channel == "RAID", "comm: raid channel when in raid")
    STUB.Deliver("Bob-Realm")
    check(not PogRaidViewer:IsShown(), "trust: board from a regular member is ignored")
    Comm.SendBoard({ name = "From Mira", items = {} })
    STUB.Deliver("Mira-OtherRealm")
    check(PogRaidViewer:IsShown() and Viewer.title:GetText() == "From Mira", "trust: board from an assistant is shown")
    check(Viewer.from:GetText() == "from Mira", "viewer: shows who sent it")
    -- close from someone else does nothing, close from Mira closes it
    Comm.Send("X", "RAID")
    STUB.Deliver("Bob-Realm")
    check(PogRaidViewer:IsShown(), "trust: close from a regular member is ignored")
    Comm.Send("X", "RAID")
    STUB.Deliver("Mira-OtherRealm")
    check(not PogRaidViewer:IsShown(), "viewer: close on raid hides it")
    -- our own RAID echo does not pop the viewer
    Comm.SendBoard({ name = "Echo", items = {} })
    STUB.Deliver("Jake-Realm")
    check(not PogRaidViewer:IsShown(), "comm: own raid echo does not open the viewer")
end

-- Restricted messaging: queue and send later ----------------------------------------
do
    STUB.printed = {}
    STUB.restricted = true
    Comm.SendBoard({ name = "Held", items = { { t = "mark", i = 1, x = 0.5, y = 0.5 } } })
    check(#STUB.sent == 0 and Comm.QueueLength() == 1, "lockdown: nothing sent while restricted")
    check(printedContains("locked"), "lockdown: player is told the board is waiting")
    STUB.Advance(1)
    STUB.Advance(1)
    check(#STUB.sent == 0, "lockdown: still holding")
    STUB.restricted = false
    STUB.Advance(1)
    check(#STUB.sent == 1 and Comm.QueueLength() == 0, "lockdown: sends once unlocked")
    check(printedContains("unlocked"), "lockdown: player is told it went out")
    STUB.sent = {}

    STUB.throttleNext = 1
    Comm.SendBoard({ name = "Throttled", items = {} })
    check(#STUB.sent == 0 and Comm.QueueLength() == 1, "throttle: first attempt throttled")
    STUB.Advance(1)
    check(#STUB.sent == 1, "throttle: retried after a second")
    STUB.sent = {}

    -- guild sync waits behind a raid plan and keeps a few sends in reserve
    STUB.Advance(20)
    STUB.realThrottle, STUB.allowance, STUB.allowanceAt = true, 10, STUB.now
    Comm.SendChunked("Y", ("x"):rep(240 * 12), "GUILD", nil, true)
    local bulkSent = #STUB.sent
    check(bulkSent == Comm.ALLOWANCE - Comm.RESERVE, "priority: background sync leaves a reserve (" .. bulkSent .. ")")
    Comm.SendBoard({ name = "Urgent", items = {} }, "RAID")
    check(#STUB.sent == bulkSent + 1 and STUB.sent[#STUB.sent].text:sub(1, 1) == "B", "priority: a raid plan goes straight out")
    for _ = 1, 30 do STUB.Advance(1) end
    check(#STUB.sent == 13 and Comm.QueueLength() == 0, "priority: background sync finishes at the client's pace")
    STUB.realThrottle, STUB.allowance, STUB.allowanceAt = false, nil, nil
    STUB.sent = {}
end

-- Raid check ---------------------------------------------------------------------------
do
    STUB.printed = {}
    Comm.CheckRaid()
    check(STUB.sent[1].text == "Q", "check: query sent")
    STUB.sent = {}
    STUB.Fire("CHAT_MSG_ADDON", "PogRaid", "R0.1.0", "WHISPER", "Mira-OtherRealm")
    STUB.Advance(3)
    check(printedContains("has it (2): ") and printedContains("missing (1): Bob"), "check: reports who is missing")
    -- answering someone else's query
    STUB.Fire("CHAT_MSG_ADDON", "PogRaid", "Q", "RAID", "Mira-OtherRealm")
    check(STUB.sent[1] and STUB.sent[1].text == "R" .. ns.VERSION and STUB.sent[1].target == "Mira-OtherRealm", "check: replies to others")
    STUB.sent = {}
    STUB.roster = nil
end

-- Editor interaction ----------------------------------------------------------------------
do
    local c = Editor.canvas
    local b = ns.db.boards[Editor.id]
    Editor:SetMap(1453)
    b.items = {}
    c:SetItems(b.items)
    local function cursorAt(nx, ny)
        STUB.cursorX = c.map:GetLeft() + nx * c.mw
        STUB.cursorY = c.map:GetTop() - ny * c.mh
    end
    local function click(button, nx, ny)
        cursorAt(nx, ny)
        STUB.mouseDown[button] = true
        STUB.Script(c.frame, "OnMouseDown", button)
        STUB.mouseDown[button] = false
        STUB.Script(c.frame, "OnMouseUp", button)
    end
    local function drag(button, x1, y1, x2, y2)
        cursorAt(x1, y1)
        STUB.mouseDown[button] = true
        STUB.Script(c.frame, "OnMouseDown", button)
        cursorAt(x2, y2)
        STUB.Script(Editor.frame, "OnUpdate")
        STUB.mouseDown[button] = false
        STUB.Script(c.frame, "OnMouseUp", button)
    end

    Editor:SetTool("mark")
    Editor.markIcon = 7
    click("LeftButton", 0.25, 0.4)
    check(#b.items == 1 and b.items[1].i == 7 and near(b.items[1].x, 0.25, 1e-9) and near(b.items[1].y, 0.4, 1e-9),
        "editor: marker lands where clicked")

    Editor:SetTool("arrow")
    Editor.color = 4
    drag("LeftButton", 0.1, 0.1, 0.5, 0.2)
    local a = b.items[2]
    check(a and a.t == "arrow" and a.c == 4 and near(a.x2, 0.5, 1e-9), "editor: arrow drawn by dragging")
    check(c.preview == nil, "editor: arrow preview cleared")
    drag("LeftButton", 0.6, 0.6, 0.601, 0.6)
    check(#b.items == 2, "editor: tiny drag makes no arrow")

    Editor:SetTool("circle")
    drag("LeftButton", 0.7, 0.5, 0.8, 0.5)
    local circ = b.items[3]
    check(circ and circ.t == "circle" and near(circ.r, 0.1, 1e-6), "editor: circle radius from drag")

    Editor:SetTool("group")
    Editor.group = "R"
    click("LeftButton", 0.4, 0.8)
    check(b.items[4].t == "group" and b.items[4].g == "R", "editor: group dot")

    Editor:SetTool("dot")
    Editor.dotName = nil
    click("LeftButton", 0.2, 0.2)
    check(#b.items == 4, "editor: player tool without a pick opens the picker instead")
    local entries = Editor:RosterEntries()
    check(entries[1].text == "Jake" and entries[#entries].text == "Type a name...", "editor: roster picker lists you")
    entries[1].func()
    click("LeftButton", 0.2, 0.2)
    check(b.items[5].t == "dot" and b.items[5].name == "Jake" and b.items[5].class == "HUNTER", "editor: player dot")

    Editor:SetTool("text")
    Editor.color = 2
    click("LeftButton", 0.5, 0.9)
    local prompt = ns.UI.promptFrame
    check(prompt and prompt:IsShown() and prompt.box:HasFocus(), "editor: text tool opens a prompt")
    prompt.box:SetText("Soak here")
    STUB.Script(prompt.box, "OnEnterPressed")
    local t = b.items[6]
    check(t and t.t == "text" and t.s == "Soak here" and t.c == 2 and near(t.y, 0.9, 1e-9), "editor: text label added")
    check(not prompt:IsShown(), "editor: prompt closes after Enter")

    Editor:SetTool("move")
    drag("LeftButton", 0.25, 0.4, 0.35, 0.45)
    check(near(b.items[1].x, 0.35, 1e-9) and near(b.items[1].y, 0.45, 1e-9), "editor: move drags an item")
    local undoDepth = #Editor.undo
    Editor:Undo()
    check(near(b.items[1].x, 0.25, 1e-9) and #Editor.undo == undoDepth - 1, "editor: undo reverts a move")

    local count = #b.items
    click("RightButton", 0.25, 0.4)
    check(#b.items == count - 1 and b.items[1].t == "arrow", "editor: right-click deletes an item")
    Editor:Undo()
    check(#b.items == count and b.items[1].t == "mark", "editor: undo restores a delete")

    -- right-drag on empty space pans (needs zoom so there is room to pan)
    c:SetView(3, 0.5, 0.5)
    local cx0 = c.cx
    drag("RightButton", 0.5, 0.5, 0.45, 0.5)
    check(c.cx > cx0 and near(b.cx, c.cx, 1e-9), "editor: right-drag pans and saves the view")

    -- arrows moved near the edge keep their shape
    b.items = { { t = "arrow", c = 1, x1 = 0.8, y1 = 0.5, x2 = 0.95, y2 = 0.5 } }
    c:SetView(1, 0.5, 0.5)
    c:SetItems(b.items)
    Editor:SetTool("move")
    drag("LeftButton", 0.85, 0.5, 0.99, 0.5)
    check(near(b.items[1].x2, 1, 1e-9) and near(b.items[1].x2 - b.items[1].x1, 0.15, 1e-9), "editor: arrow stops at the edge without squashing")
end

-- Map, boss, boards -----------------------------------------------------------------------
do
    local b = ns.db.boards[Editor.id]
    Editor:SetMap(2001)
    check(b.map == 2001 and Editor.mapBtn.label:GetText() == "Map: Skyreach Hall", "maps: map button shows the map")
    b.name = "Board 3"
    Editor:FocusBoss("Stormcaller Vael", 0.3, 0.4)
    check(b.name == "Stormcaller Vael" and b.zoom == 2.5, "boss: zooms in and names a default-named board")
    b.name = "My plan"
    Editor:FocusBoss("Stormcaller Vael", 0.3, 0.4)
    check(b.name == "My plan", "boss: never renames a board you named")
    -- the boss menu lists the map's bosses, and copes with a client without the Encounter Journal
    local shown
    local realShow = ns.UI.ShowMenu
    ns.UI.ShowMenu = function(_, e) shown = e end
    Editor:BossMenu()
    check(shown and shown[1].text == "Stormcaller Vael" and not shown[1].disabled, "boss: the menu lists the map's bosses")
    local ej, ejInfo = C_EncounterJournal, EJ_GetEncounterInfo
    C_EncounterJournal, EJ_GetEncounterInfo = nil, nil
    local okMenu = pcall(Editor.BossMenu, Editor)
    check(okMenu and shown[1].disabled, "boss: no Encounter Journal on this client: an empty menu, no error")
    C_EncounterJournal = ej
    Editor:BossMenu()
    check(shown[1].text == "Encounter 3001", "boss: a boss the journal can't name still shows")
    EJ_GetEncounterInfo = ejInfo
    ns.UI.ShowMenu = realShow

    local before = #ns.db.order
    Editor:NewBoard()
    check(#ns.db.order == before + 1 and ns.db.boards[Editor.id].map == 2001, "boards: new board keeps the raid map")
    Editor.nameBox:SetText("Phase 2")
    STUB.Script(Editor.nameBox, "OnTextChanged", true)
    check(ns.db.boards[Editor.id].name == "Phase 2", "boards: typing renames the board")
    Editor:DeleteCurrent()
    check(#ns.db.order == before, "boards: delete removes it")
    while #ns.db.order > 1 do Editor:DeleteCurrent() end
    Editor:DeleteCurrent()
    check(#ns.db.order == 1 and ns.db.boards[ns.db.order[1]].name == "First plan", "boards: deleting the last one leaves a fresh plan")
end

-- Layout: columns and rows line up -------------------------------------------------------
do
    local f = Editor.frame
    local fl, ft, fw = STUB.rect(f)
    local cl, ct, cw, ch = STUB.rect(Editor.canvas.frame)
    check(near((fl + fw) - (cl + cw), 12), "layout: canvas right margin equals the left margin")
    check(near(cl - fl, 12 + 170 + 12), "layout: canvas starts after the left column")
    local nl, nt = STUB.rect(Editor.nameBox)
    check(near(nl - fl, 12), "layout: left column margin")
    local ml, mt = STUB.rect(Editor.mapBtn)
    check(near(ml, cl), "layout: map button aligned with canvas left")
    check(near(ct - ch - mt, 8), "layout: bottom row sits one gap below the canvas")
    local first = STUB.rect(Editor.toolButtons.move)
    local ll, lt, lw = STUB.rect(Editor.toolButtons.text)
    local _, firstTop = STUB.rect(Editor.toolButtons.move)
    check(near(first, cl) and near(ll + lw, cl + cw), "layout: tool row spans exactly the canvas width")
    check(near(firstTop, nt), "layout: tool row lines up with the board name")
    Editor:SetTool("rect")
    local col, colTop, colW = STUB.rect(Editor.options.color)
    local sl = STUB.rect(Editor.options.style)
    check(near(col, cl) and near(sl, col + colW + 16), "layout: colour then style strips on the options row")
    check(near(firstTop - colTop, 26 + 8), "layout: options row one gap under the tools")
    check(near(colTop - ct, 26 + 8), "layout: canvas one gap under the options row")
    Editor:SetTool("group")
    local gl, _, gw = STUB.rect(Editor.options.group)
    check(gl + gw <= cl + cw - 200, "layout: group buttons leave room for the hint")
    Editor:SetTool("move")
end

-- Drawing tools for rooms ----------------------------------------------------------------
do
    local c = Editor.canvas
    local b = ns.db.boards[Editor.id]
    Editor:SetMap(nil)
    b.items = {}
    c:SetItems(b.items)
    local function cursorAt(nx, ny)
        STUB.cursorX = c.map:GetLeft() + nx * c.mw
        STUB.cursorY = c.map:GetTop() - ny * c.mh
    end
    local function stroke(button, path)
        cursorAt(path[1][1], path[1][2])
        STUB.mouseDown[button] = true
        STUB.Script(c.frame, "OnMouseDown", button)
        for i = 2, #path do
            cursorAt(path[i][1], path[i][2])
            STUB.Script(Editor.frame, "OnUpdate")
        end
        STUB.mouseDown[button] = false
        STUB.Script(c.frame, "OnMouseUp", button)
    end

    -- rectangle, style and colour carried through, corners normalised
    Editor:SetTool("rect")
    Editor.color, Editor.style = 7, 2
    stroke("LeftButton", { { 0.6, 0.6 }, { 0.2, 0.3 } })
    local r = b.items[1]
    check(r and r.t == "rect" and r.c == 7 and r.s == 2 and near(r.x1, 0.2, 1e-9) and near(r.y2, 0.6, 1e-9),
        "rect: drawn from any corner")
    stroke("LeftButton", { { 0.5, 0.5 }, { 0.501, 0.7 } })
    check(#b.items == 1, "rect: too thin to keep")
    STUB.shift = true
    stroke("LeftButton", { { 0.7, 0.1 }, { 0.8, 0.13 } })
    STUB.shift = false
    local sq = b.items[2]
    check(near((sq.x2 - sq.x1) * c.mw, (sq.y2 - sq.y1) * c.mh, 1e-6), "rect: shift makes a square on screen")

    -- line: shift straightens, ends snap to existing corners
    Editor:SetTool("line")
    Editor.color = 5
    STUB.shift = true
    stroke("LeftButton", { { 0.1, 0.8 }, { 0.4, 0.81 } })
    STUB.shift = false
    local ln = b.items[3]
    check(ln and ln.t == "line" and ln.y2 == ln.y1, "line: shift locks it horizontal")
    STUB.shift = true
    stroke("LeftButton", { { 0.1, 0.9 }, { 0.2, 0.9 - 0.1 * c.mw / c.mh + 0.004 } })
    STUB.shift = false
    local diag = b.items[4]
    check(near((diag.x2 - diag.x1) * c.mw, (diag.y1 - diag.y2) * c.mh, 1e-6), "line: shift locks it to 45 degrees")
    -- start near the rectangle's corner (0.2, 0.3), end near the line's end
    cursorAt(0.2 + 5 / c.mw, 0.3 + 4 / c.mh)
    STUB.mouseDown.LeftButton = true
    STUB.Script(c.frame, "OnMouseDown", "LeftButton")
    cursorAt(0.4 + 6 / c.mw, 0.8 - 3 / c.mh)
    STUB.Script(Editor.frame, "OnUpdate")
    check(c.snapMark and c.snapMark.x == ln.x2 and c.snapMark.y == ln.y2, "line: snap point is marked while dragging")
    STUB.mouseDown.LeftButton = false
    STUB.Script(c.frame, "OnMouseUp", "LeftButton")
    local wall = b.items[5]
    check(wall.x1 == r.x1 and wall.y1 == r.y1 and wall.x2 == ln.x2 and wall.y2 == ln.y2,
        "line: both ends snap onto existing corners")
    check(c.snapMark == nil, "line: snap mark cleared after drawing")

    -- pen: points collected while dragging, straight runs simplified
    Editor:SetTool("pen")
    local path = {}
    for i = 0, 40 do path[#path + 1] = { 0.1 + i * 0.01, 0.5 } end
    for i = 1, 20 do path[#path + 1] = { 0.5, 0.5 + i * 0.01 } end
    stroke("LeftButton", path)
    local pen = b.items[6]
    check(pen and pen.t == "pen" and #pen.pts == 6, "pen: an L-shaped stroke keeps just its 3 corners")
    check(near(pen.pts[3], 0.5, 1e-9) and near(pen.pts[4], 0.5, 1e-9), "pen: corner point kept exactly")
    local wiggle = {}
    for i = 0, 300 do
        local a = i / 300 * 2 * math.pi * 6
        wiggle[#wiggle + 1] = { 0.5 + 0.3 * math.cos(a / 6) + 0.01 * math.sin(a * 5), 0.5 + 0.3 * math.sin(a / 6) }
    end
    stroke("LeftButton", wiggle)
    local long = b.items[7]
    check(long and #long.pts / 2 <= Codec.MAX_PEN and #long.pts / 2 > 10, "pen: long wiggly stroke capped at the point limit")
    stroke("LeftButton", { { 0.3, 0.3 }, { 0.3005, 0.3 } })
    check(#b.items == 7, "pen: a click without a stroke draws nothing")

    -- all of it survives the wire
    local out = Codec.Decode(Codec.Encode(b))
    check(#out.items == 7, "wire: every room shape decodes")
    check(out.items[1].t == "rect" and out.items[1].s == 2 and out.items[1].c == 7, "wire: rect keeps colour and style")
    check(out.items[3].t == "line" and out.items[3].y1 == out.items[3].y2, "wire: straight line stays straight")
    check(out.items[6].t == "pen" and #out.items[6].pts == 6 and near(out.items[6].pts[3], 0.5, 1 / 4095), "wire: pen points")
    local old = Codec.Decode("KR1;0;100;gAgA;Old;C1gAgAgA")
    check(old.items[1].t == "circle" and old.items[1].s == 1, "wire: circles from 0.1.0 read as zones")
    check(#Codec.Decode("KR1;0;100;gAgA;X;P1gAgAgAgA").items == 1 and #Codec.Decode("KR1;0;100;gAgA;X;P1gAgA").items == 0,
        "wire: pen needs at least two points")
    local copy = Codec.CopyItems(b.items)
    copy[6].pts[1] = 0.99
    check(b.items[6].pts[1] ~= 0.99, "undo: pen points are copied, not shared")

    -- hit testing and moving the new shapes
    check(c:HitTest(0.3, 0.4) == 1, "hit: inside a rectangle")
    check(c:HitTest(0.3, 0.5) == 6, "hit: a pen stroke inside a rectangle wins")
    Editor:SetTool("move")
    stroke("LeftButton", { { 0.45, 0.5 }, { 0.45, 0.45 } })
    check(near(b.items[6].pts[2], 0.45, 1e-9) and near(b.items[6].pts[6], 0.65, 1e-9), "move: pen stroke moves as a whole")
    stroke("LeftButton", { { 0.58, 0.32 }, { 0.38, 0.32 } })
    check(near(b.items[1].x1, 0, 1e-9) and near(b.items[1].x2 - b.items[1].x1, 0.4, 1e-9), "move: rectangle stops at the edge, same size")
    check(c:HitTest(0.95, 0.05) == nil, "hit: empty corner")

    -- style swatches follow the colour
    Editor:SetTool("circle")
    Editor.color = 1
    Editor:RefreshOptions()
    local solid = Editor.styleButtons[2]
    check(solid.icon.__color[1] == ns.COLORS[1][1] and solid.icon.__color[4] == ns.STYLES[2].fill, "styles: swatches preview the colour")
    check(Editor.styleButtons[3].icon.__color[4] == 0, "styles: outline swatch has no fill")
    Editor:SetTool("move")
end

-- Roster builder ------------------------------------------------------------------------
do
    local Roster = ns.Roster
    -- a guild: 4 officers/raiders per class spread, a trial, a social, a level 59
    local classes = { "WARRIOR", "PRIEST", "MAGE", "ROGUE", "HUNTER", "DRUID", "WARLOCK", "PALADIN", "SHAMAN" }
    STUB.guild = {}
    for i = 1, 27 do
        local class = classes[(i - 1) % #classes + 1]
        STUB.guild[i] = { name = ("Raider%02d-Realm"):format(i), rankIndex = (i <= 2) and 1 or 2, level = 60,
            online = i % 3 == 0, class = class }
    end
    table.insert(STUB.guild, { name = "Trialguy-Realm", rankIndex = 3, level = 60, online = true, class = "MAGE" })
    table.insert(STUB.guild, { name = "Socialite-Realm", rankIndex = 4, level = 60, online = false, class = "ROGUE" })
    table.insert(STUB.guild, { name = "Levelling-Realm", rankIndex = 2, level = 59, online = true, class = "HUNTER" })
    table.insert(STUB.guild, { name = "Jake-Realm", rankIndex = 0, level = 60, online = true, class = "HUNTER" })

    SlashCmdList.POGRAID("roster")
    local rosterTab
    for _, t in ipairs(Editor.tabs) do if t.key == "roster" then rosterTab = t end end
    local boardsTab
    for _, t in ipairs(Editor.tabs) do if t.key == "boards" then boardsTab = t end end
    local order = {}
    for i, t in ipairs(Editor.tabs) do order[i] = t.key end
    check(table.concat(order, ",") == "home,profiles,lfg,wishlist,roster,attendance,loot,crafting,games,boards,settings",
        "tabs: Home, Profiles ... Crafting, Games, Raid Plans, then Settings")
    do
        -- every gap between tab labels (and before the X) is the same: text
        -- edges from each tab's centre and its label width
        local fl, _, fw = STUB.rect(Editor.frame)
        local edges = {}
        for _, b in ipairs(Editor.topButtons) do
            local l, _, w = STUB.rect(b)
            local tw = b.label:GetStringWidth()
            edges[#edges + 1] = { l + w / 2 - tw / 2, l + w / 2 + tw / 2 }
        end
        local lo, hi = math.huge, -math.huge
        for i = 2, #edges do
            local g = edges[i][1] - edges[i - 1][2]
            lo, hi = math.min(lo, g), math.max(hi, g)
        end
        -- the X is up in the frame's strip: the tabs sit centred in the window
        local mid = (edges[1][1] + edges[#edges][2]) / 2
        check(hi - lo <= 1 and lo >= 20 and math.abs(mid - (fl + fw / 2)) <= 1,
            ("tabs: evenly spaced, centred in the window (gaps %.1f to %.1f)"):format(lo, hi))
        local sel = Editor.tabButtons.roster
        check(near(sel.underline:GetWidth(), sel.label:GetStringWidth() + 16), "tabs: underline is the label plus 8px each side")
    end
    -- the raid tools share one tab, "Raid"; a panel docked to the window's left
    -- edge switches between them
    local labels = {}
    for i, b in ipairs(Editor.topButtons) do labels[i] = b.label:GetText() end
    check(table.concat(labels, ",") == "Home,Profiles,LFG,Wishlist,Raid,Crafting,Games,Settings",
        "tabs: Home, Profiles, LFG, Wishlist, Raid, Crafting, Games, Settings")
    local rt = Editor.tabButtons.roster
    check(rt == Editor.tabButtons.attendance and rt == Editor.tabButtons.loot and rt == Editor.tabButtons.boards,
        "tabs: Roster, Attendance, Loot and Raid Plans share the Raid tab")
    check(rt.bg == nil and rt.edges == nil, "tabs: plain text, no button box")
    check(rt.underline:IsShown() and not Editor.tabButtons.crafting.underline:IsShown(), "tabs: selected tab underlined")
    local sub = Editor.groups.raid.sub
    local subText = {}
    for i, t in ipairs(sub.tabs) do subText[i] = t.label:GetText() end
    check(sub:IsShown() and table.concat(subText, "|") == "Roster|Attendance|Loot|Raid Plans" and sub.tabs[1].selected
        and not sub.tabs[2].selected, "tabs: raid pages have a row of sub-tabs, the open one marked")
    local wl, wt = STUB.rect(Editor.frame)
    local sl, stop, _, sh = STUB.rect(sub)
    local _, ptop = STUB.rect(Editor.tabs[1].page or Editor.frame)
    local rosterPage
    for _, t in ipairs(Editor.tabs) do if t.key == "roster" then rosterPage = t.page end end
    local _, rpt = STUB.rect(rosterPage)
    check(near(wt - stop, 36 + 10) and near(sh, 26) and near((stop - sh) - (rpt - 30), 8),
        "tabs: the sub-tabs sit 10px under the band, 8px above the page's first row")
    do
        -- the classic look: the talent window's tabs, side by side from the page margin
        local fl0 = STUB.rect(Editor.frame)
        local t1, t2 = sub.tabs[1], sub.tabs[2]
        local l1, _, w1, h1 = STUB.rect(t1)
        local l2 = STUB.rect(t2)
        local C = ns.UI.SUBTAB_COLORS
        check(near(l1, fl0 + 12) and near(l2, l1 + w1 + ns.UI.SUBTAB_GAP) and h1 == 26
            and w1 == math.max(ns.UI.SUBTAB_MIN, math.floor(t1.label:GetStringWidth() + 28 + 0.5)),
            "tabs: sub-tabs are the talent window's tabs, side by side from the page margin")
        check(t1.glow:IsShown() and t1.bg.__color[1] == C.selFill[1] and t1.edges[1].__color[1] == C.selEdge[1]
            and t1.label.__textColor[1] == C.selText[1] and not t2.glow:IsShown() and t2.bg.__color[1] == C.fill[1]
            and t2.label.__textColor[1] == C.text[1], "tabs: the open one is warm gold with a bright edge, the others dark")
        STUB.Script(t2, "OnEnter")
        local hoverEdge = t2.edges[1].__color[1]
        STUB.Script(t2, "OnLeave")
        check(hoverEdge == C.hoverEdge[1] and t2.edges[1].__color[1] == C.edge[1], "tabs: hovering a closed tab brightens its edge")
    end
    STUB.Script(sub.tabs[3], "OnClick")
    check(Editor.currentTab == "loot" and rt.label:GetText() == "Raid" and sub.tabs[3].selected and not sub.tabs[1].selected,
        "tabs: a sub-tab switches pages, the Raid tab keeps its name")
    Editor:ShowTab("crafting")
    check(not sub:IsShown(), "tabs: the sub-tabs only show on the raid pages")
    STUB.Script(rt, "OnClick")
    check(Editor.currentTab == "loot" and sub:IsShown() and ns.db.frames.groupTabs.raid == "loot", "tabs: Raid opens the raid page used last")
    ns.db.frames.groupTabs.raid = nil
    Editor:ShowTab("crafting")
    STUB.Script(rt, "OnClick")
    check(Editor.currentTab == "attendance", "tabs: Attendance is the default")
    Editor:ShowTab("roster")
    local lootTab = Editor.tabButtons.crafting
    STUB.Script(lootTab, "OnEnter")
    local hoverText = lootTab.label.__textColor
    STUB.Script(lootTab, "OnLeave")
    local function lum(c) return c[1] + c[2] + c[3] end
    check(hoverText and lum(hoverText) > lum(lootTab.label.__textColor) + 0.2, "tabs: hover brightens a tab")
    local fl0, ft0, fw0, fh0 = STUB.rect(Editor.frame)
    local bl0, bt0, bw0, bh0 = STUB.rect(Editor.band)
    local ul, ut, uw, uh = STUB.rect(rt)
    check(near(bh0, 36) and near(ut - uh, bt0 - bh0), "tabs: sit on the band's bottom edge")
    local pgl, pgt = STUB.rect(rosterTab.page)
    check(near(ft0 - pgt, 16 + ns.SUB_H) and near(fh0, 16 + ns.PAGE_H), "band: raid pages start under their sub-tabs, window grown to fit")
    local _, nameTop = STUB.rect(Roster.nameBox)
    check(near((bt0 - bh0) - nameTop, 10 + ns.SUB_H), "band: a raid page's first row sits under the sub-tab row")
    check(rosterTab.page and rosterTab.page:IsShown() and not boardsTab.page:IsShown(), "tabs: roster tab replaces the boards page")
    check(Editor.tabButtons.roster.selected and not Editor.tabButtons.crafting.selected, "tabs: roster tab button selected")
    local r = Roster:Current()
    check(r and r.size == 20 and r.id and r.rev and r.by == "Jake", "roster: first roster made, with sync fields")

    local pool = Roster:PoolNames()
    check(#pool == 31, "pool: every guild member by default, whatever their level")
    local lvlRow
    Roster.search = "Levelling"
    Roster:RefreshPool()
    Roster.search = nil
    for _, row in ipairs(Roster.poolRows) do if row.player == "Levelling-Realm" then lvlRow = row end end
    check(lvlRow and not lvlRow.name:GetText():find("59", 1, true), "pool: no level after names, even below the cap")
    check(not Roster.poolRows[1].name:GetText():find("60", 1, true), "pool: no level shown at the cap")
    ns.db.guild.maxLevelOnly = true
    pool = Roster:PoolNames()
    local inPool = {}
    for _, n in ipairs(pool) do inPool[n] = true end
    check(#pool == 30 and not inPool["Levelling-Realm"], "pool: max level filter")
    local lvlEntry = Roster:RankEntries()
    check(lvlEntry[#lvlEntry].text == "[x] Max level only (60)", "pool: filter menu names the level")

    -- everyone filtered out: the pool says why
    ns.db.guild.maxLevelOnly = true
    local saveGuild = STUB.guild
    for _, m in ipairs(STUB.guild) do m.level = m.level - 45 end
    Roster:ScanGuild()
    Roster:Refresh()
    check(Roster.poolEmpty:IsShown() and Roster.poolEmpty:GetText():find("Open Ranks", 1, true), "pool: empty pool explains the filters")
    for _, m in ipairs(STUB.guild) do m.level = m.level + 45 end
    Roster:ScanGuild()
    Roster:Refresh()
    check(not Roster.poolEmpty:IsShown(), "pool: message goes away once raiders match")

    -- saves from 0.2.0 had the filter on by default: reset once
    PogRaidDB.version = 1
    PogRaidDB.guild.maxLevelOnly = true
    STUB.Fire("ADDON_LOADED", "PogRaid")
    check(ns.db.guild.maxLevelOnly == false and ns.db.version == 5, "migration: old default filter turned off")
    ns.db.guild.maxLevelOnly = true
    STUB.Fire("ADDON_LOADED", "PogRaid")
    check(ns.db.guild.maxLevelOnly == true, "migration: a filter you turn on stays on")
    Roster:ToggleRank(4, 5)
    pool = Roster:PoolNames()
    inPool = {}
    for _, n in ipairs(pool) do inPool[n] = true end
    check(#pool == 29 and not inPool["Socialite-Realm"], "pool: rank filter drops socials")
    check(Roster:RoleOf(pool[1]) == nil, "pool: nobody has a role until one is set (no class guessing)")
    check(Roster.poolInfo == nil, "pool: no summary line (0.16 dropped it)")

    -- clicking pool rows fills the first open slots
    -- find a pool row the way a player would: type the name in search
    local function rowFor(name)
        Roster.search = name:match("^[^-]+")
        Roster:RefreshPool()
        Roster.search = nil
        for _, row in ipairs(Roster.poolRows) do if row.player == name then return row end end
    end
    local function click(row, button, from)
        Roster:Press(row, button or "LeftButton")
        Roster:Release(row, button or "LeftButton", from or "pool")
    end
    local function drag(row, target, from)
        STUB.cursorX, STUB.cursorY = 100, 100
        Roster:Press(row, "LeftButton")
        STUB.cursorX, STUB.cursorY = 160, 130
        STUB.Script(Roster.page, "OnUpdate")
        STUB.hover = target
        Roster:Release(row, "LeftButton", from)
        STUB.hover = nil
    end
    click(rowFor("Raider01-Realm"))
    click(rowFor("Raider02-Realm"))
    check(r.groups[1][1] == "Raider01-Realm" and r.groups[1][2] == "Raider02-Realm", "roster: click adds to the first open slot")
    check(Roster.slots[1][1].player == "Raider01-Realm" and Roster.groupBoxes[1].count:GetText() == "2/5", "roster: group shows its players")
    check(Roster.slots[1][1].name:GetText() == "Raider01", "roster: names shown without realm")
    check(Roster.slots[1][1].role == nil and Roster.poolRows[1].role == nil, "roster: no role letter on rows")
    check(Roster.poolRows[1].name.__justifyH == "LEFT" and Roster.slots[1][1].name.__justifyH == "LEFT", "roster: names left aligned")
    local pr = Roster.poolRows[1]
    local nl = STUB.rect(pr.name)
    local rl0 = STUB.rect(pr)
    check(near(nl - rl0, 8), "roster: names start 8px in, where the role letter used to be")
    Roster:Add("Raider01-Realm")
    check(r.groups[1][3] == nil, "roster: adding a rostered player does not add them twice")

    -- drag pool player onto an occupied slot: occupant goes back to the pool
    drag(rowFor("Raider03-Realm"), Roster.slots[1][1], "pool")
    check(r.groups[1][1] == "Raider03-Realm" and not Roster:Locate("Raider01-Realm"), "drag: pool onto a slot replaces the occupant")
    -- slot to slot swaps
    Roster:Drop("Raider04-Realm", { kind = "slot", g = 3, s = 5 })
    drag(Roster.slots[1][1], Roster.slots[3][5], "slot")
    check(r.groups[3][5] == "Raider03-Realm" and r.groups[1][1] == "Raider04-Realm", "drag: slot onto slot swaps")
    -- slot to bench, bench to a group box, group to pool
    drag(Roster.slots[1][2], Roster.benchBox, "slot")
    check(r.bench[1] == "Raider02-Realm" and r.groups[1][2] == nil, "drag: slot to bench")
    drag(Roster.benchSlots[1], Roster.groupBoxes[2], "bench")
    check(r.groups[2][1] == "Raider02-Realm" and #r.bench == 0, "drag: bench to a group's first open slot")
    drag(Roster.slots[2][1], Roster.poolPanel, "slot")
    check(not Roster:Locate("Raider02-Realm"), "drag: back to the pool removes")
    -- a short press is a click, not a drag
    STUB.cursorX, STUB.cursorY = 100, 100
    Roster:Press(rowFor("Raider05-Realm"), "LeftButton")
    STUB.cursorX = 103
    STUB.Script(Roster.page, "OnUpdate")
    Roster:Release(rowFor("Raider05-Realm"), "LeftButton", "pool")
    check(Roster:Locate("Raider05-Realm") == "group", "drag: tiny movement still counts as a click")
    -- right-click a slot removes
    local where, g, sl = Roster:Locate("Raider05-Realm")
    click(Roster.slots[g][sl], "RightButton", "slot")
    check(not Roster:Locate("Raider05-Realm"), "roster: right-click removes from the roster")

    -- fill 20 + 2 bench, full group handling
    Roster:Clear()
    for i = 1, 22 do Roster:Add(("Raider%02d-Realm"):format(i)) end
    check(r.groups[4][5] == "Raider20-Realm" and r.bench[2] == "Raider22-Realm", "roster: overflow goes to the bench")
    STUB.printed = {}
    Roster:Drop("Raider21-Realm", { kind = "group", g = 1 })
    check(printedContains("group 1 is full") and r.bench[1] == "Raider21-Realm", "roster: full group refuses a drop")

    -- roles, marks, composition
    Roster:SetRole("Raider01-Realm", "T")
    Roster:SetRole("Raider10-Realm", "T")
    local roles, cls, total = Roster:Composition()
    Roster:SetRole("Raider02-Realm", "H")
    check(total == 20 and roles.T == 2 and roles.H == 0 and roles.M == nil, "composition: only tanks and healers, from marks")
    roles = Roster:Composition()
    check(roles.H == 1, "composition: healer mark counted")
    local _, gT, sT = Roster:Locate("Raider01-Realm")
    local tankSlot = Roster.slots[gT][sT]
    check(tankSlot.roleBar:IsShown() and tankSlot.roleBar.__color[3] == ns.GROUPS.T.color[3], "roles: tank stripe on the row")
    local _, gN, sN = Roster:Locate("Raider03-Realm")
    check(not Roster.slots[gN][sN].roleBar:IsShown(), "roles: no stripe without a role")
    Roster.search = "Raider01"
    Roster:RefreshPool()
    Roster.search = nil
    local pm = Roster:PlayerEntries("Raider01-Realm")
    local labels = {}
    for _, x in ipairs(pm) do labels[#labels + 1] = x.text end
    local joined = table.concat(labels, "|")
    check(joined:find("> Tank", 1, true) and joined:find("   Healer", 1, true) and joined:find("   No role", 1, true)
        and not joined:find("Melee", 1, true), "roles: menu offers Tank, Healer, No role")
    pm[#pm].func()
    check(Roster:RoleOf("Raider01-Realm") == nil, "roles: No role clears it")
    Roster:SetRole("Raider01-Realm", "T")
    STUB.Script(tankSlot, "OnEnter")
    check(GameTooltip.lines[2] == "Tank", "roles: tooltip names the role")
    STUB.Script(tankSlot, "OnLeave")
    Roster:SetRole("Raider25-Realm", "H")
    pool = Roster:PoolNames()
    check(pool[1] == "Raider25-Realm", "roles: a marked healer sorts to the top of the unrostered pool")
    Roster:SetRole("Raider25-Realm", nil)
    check(cls.WARRIOR == 3 and cls.PRIEST == 3 and cls.MAGE == 2, "composition: class counts")
    check(Roster.compRoles.T:GetText() == "Tanks 2" and Roster.compRoles.H:GetText() == "Healers 1"
        and Roster.compRoles.M == nil and Roster.compTotal:GetText() == "20 / 20", "composition: shown")
    Roster:SetMark("Raider07-Realm", "out")
    Roster:SetMark("Raider08-Realm", "tent")
    local _, g7, s7 = Roster:Locate("Raider07-Realm")
    check(Roster.slots[g7][s7].note:GetText() == "out", "marks: shown on the slot")
    pool = Roster:PoolNames()
    check(pool[#pool] == "Raider07-Realm", "marks: players marked out sort to the bottom of the pool")
    local menu = Roster:PlayerEntries("Raider08-Realm")
    local marked
    for _, x in ipairs(menu) do if x.text:find("> ", 1, true) == 1 then marked = marked or x.text end end
    check(marked == "> Tentative", "marks: menu shows the current mark")

    -- size change moves extra groups to the bench
    Roster:SetSize(10)
    check(r.size == 10 and #r.bench == 12 and Roster.groupBoxes[3]:IsShown() == false, "size: 20 to 10 benches groups 3 and 4")
    Roster:SetSize(20)
    check(Roster.groupBoxes[3]:IsShown() and #r.bench == 12, "size: growing leaves the bench alone")
    for i = 11, 20 do Roster:Drop(("Raider%02d-Realm"):format(i), { kind = "group", g = math.floor((i - 11) / 5) + 3 }) end
    check(r.groups[4][5] == "Raider20-Realm" and #r.bench == 2, "size: benched players dragged back")

    -- Discord text
    local text = Roster:DiscordText()
    check(text:find("Group 1: Raider01, Raider02", 1, true) and text:find("Bench: Raider21, Raider22", 1, true)
        and text:find("Tanks 2, Healers 1", 1, true) and not text:find("Melee", 1, true) and not text:find("-Realm", 1, true),
        "discord: groups, bench, roles, short names")

    -- invites: solo invites 4, converts on first join, then the rest
    STUB.invites, STUB.converts = {}, 0
    STUB.party, STUB.roster = nil, nil
    local wasLeader, wasAssist = STUB.isLeader, STUB.isAssist
    STUB.isLeader, STUB.isAssist = true, false -- (whoever invites leads once the first one accepts)
    Roster:Invite()
    check(#STUB.invites == 4 and #Roster.pendingInvites == 15, "invite: 4 now while solo (one marked out is skipped)")
    for _, n in ipairs(STUB.invites) do check(n ~= "Raider07-Realm", "invite: skips players marked out") end
    STUB.party = { { name = "Raider01", class = "WARRIOR" } }
    STUB.Fire("GROUP_ROSTER_UPDATE")
    check(STUB.converts == 1 and #STUB.invites == 4, "invite: converts to raid after the first accept")
    STUB.party = nil
    STUB.roster = { { name = "Jake", rank = 2, class = "HUNTER" }, { name = "Raider01", class = "WARRIOR" } }
    STUB.Fire("GROUP_ROSTER_UPDATE")
    check(#STUB.invites == 19 and Roster.pendingInvites == nil, "invite: the rest go out once in a raid")
    STUB.invites = {}
    Roster:Invite()
    check(#STUB.invites == 18, "invite: again only invites who is missing")
    -- 0.16.2: someone who can't invite is told so, and nothing waits
    STUB.invites, STUB.printed = {}, {}
    STUB.isLeader = false
    Roster:Invite()
    check(#STUB.invites == 0 and printedContains("only the raid leader or an assistant can invite"),
        "invite: a raider who isn't leader or assist is told, nothing sent")
    STUB.roster, STUB.party = nil, { { name = "Raider01", class = "WARRIOR" } }
    STUB.converts = 0
    Roster:Invite()
    check(STUB.converts == 0 and Roster.pendingInvites == nil and printedContains("only the party leader can invite"),
        "invite: in someone else's party, no convert and nothing waiting")
    -- invites waiting for a raid are dropped if nobody accepts for two minutes
    STUB.party, STUB.isLeader = nil, true
    Roster:Invite()
    check(Roster.pendingInvites and #Roster.pendingInvites > 0, "invite: (solo: the rest wait for the raid)")
    STUB.Advance(Roster.PENDING_FOR + 1)
    STUB.invites = {}
    STUB.roster = { { name = "Jake", rank = 2, class = "HUNTER" }, { name = "Raider01", class = "WARRIOR" } }
    STUB.Fire("GROUP_ROSTER_UPDATE")
    check(Roster.pendingInvites == nil and #STUB.invites == 0, "invite: and don't go out hours later in some other raid")
    STUB.isLeader, STUB.isAssist = wasLeader, wasAssist

    -- arrange: build a raid of the 19 invited (+ Jake, not rostered), all in wrong groups
    STUB.roster = { { name = "Jake", rank = 2, class = "HUNTER", sub = 1 } }
    local k = 0
    for g = 1, 4 do
        for s = 1, 5 do
            local n = r.groups[g][s]
            if n and n ~= "Raider07-Realm" then
                k = k + 1
                table.insert(STUB.roster, { name = n:match("^[^-]+"), class = "MAGE", sub = (k % 5) + 4 })
            end
        end
    end
    -- groups 4..8 are over-full on purpose: sub (k%5)+4 puts 4 people each in 4-8
    STUB.isLeader = true
    STUB.printed = {}
    Roster:Arrange()
    local guard = 0
    while Roster.arranging and guard < 200 do
        guard = guard + 1
        STUB.Fire("GROUP_ROSTER_UPDATE")
    end
    local ok = true
    for _, m in ipairs(STUB.roster) do
        local want
        for g = 1, 4 do for s = 1, 5 do
            if r.groups[g][s] and r.groups[g][s]:match("^[^-]+") == m.name then want = g end
        end end
        if want and m.sub ~= want then ok = false end
    end
    check(ok and printedContains("groups arranged"), "arrange: everyone ends up in their planned group")
    check(guard < 60, "arrange: one move per roster update, finishes quickly")
    STUB.isLeader = false
    STUB.printed = {}
    Roster:Arrange()
    check(printedContains("needs leader or assistant"), "arrange: refuses without lead/assist")
    STUB.roster = nil

    -- rosters: duplicate is independent, delete leaves a tombstone
    local copy = Roster:New(r)
    check(copy.id ~= r.id and copy.groups[1][1] == r.groups[1][1] and copy.name:find("(copy)", 1, true), "rosters: duplicate copies groups")
    copy.groups[1][1] = nil
    check(r.groups[1][1] ~= nil, "rosters: duplicate does not share tables")
    local copyId = copy.id
    local del = Roster.deleteBtn
    STUB.Script(del, "OnClick")
    check(not ns.db.guild.rosters[copyId].deleted and del.label:GetText() == "Sure?", "rosters: first Delete click only asks")
    STUB.Advance(3)
    check(del.label:GetText() == "Delete", "rosters: the ask times out back to Delete")
    STUB.Script(del, "OnClick")
    STUB.Script(del, "OnClick")
    check(ns.db.guild.rosters[copyId].deleted and ns.db.guild.rosters[copyId].rev, "rosters: delete keeps a tombstone for sync")
    check(#Roster:List() == 1 and Roster:Current().id == r.id, "rosters: deleted roster hidden, previous selected")
    local entries = Roster:RosterEntries()
    check(entries[1].text == r.name and entries[#entries].text == "Duplicate this roster", "rosters: picker lists rosters and actions")
    local dl, _, dw = STUB.rect(del)
    local nbl, _, nbw = STUB.rect(Roster.nameBox)
    local s10 = STUB.rect(Roster.sizeButtons[10])
    check(near(dl, nbl + nbw + 8) and near(dl + dw + 8, s10), "layout: Delete sits one gap from the name and the sizes")

    -- manual players (pugs)
    local pug = Roster:AddManual("pugwizard", "MAGE")
    check(pug == "Pugwizard" and ns.db.guild.players.Pugwizard.manual, "pool: pugs can be added by name")
    Roster:ScanGuild()
    check(ns.db.guild.players.Pugwizard ~= nil, "pool: a guild rescan keeps pugs")

    -- layout: right column matches the boards grid, rows line up
    local page = rosterTab.page
    local pl, pt = STUB.rect(page)
    local g1l, g1t, g1w = STUB.rect(Roster.groupBoxes[1])
    local g4l, _, g4w = STUB.rect(Roster.groupBoxes[4])
    local bl, bt, bw = STUB.rect(Roster.benchBox)
    local cl2, ct2, cw2, ch2 = STUB.rect(Roster.compBox or Roster.benchBox)
    local pooll, poolt, poolw, poolh = STUB.rect(Roster.poolPanel)
    check(near(g1l - pl, 12 + 262 + 12) and near(g4l + g4w, pl + 902 - 12), "layout: group grid spans the right column")
    check(near(bl, g1l) and near(bl + bw, g4l + g4w), "layout: bench as wide as the group grid")
    local b5l = STUB.rect(Roster.benchSlots[2])
    local s2l = STUB.rect(Roster.slots[2][1])
    check(near(b5l, s2l), "layout: bench columns line up with group columns")
    check(near(pooll - pl, 12) and near(pooll + poolw, pl + 12 + 262), "layout: pool fills the left column")
    local nl, nt = STUB.rect(Roster.nameBox)
    local _, groupTop = STUB.rect(Roster.groupBoxes[1])
    check(near(nt - groupTop, 26 + 8), "layout: groups one gap under the top row")
    local _, poolTop = STUB.rect(Roster.poolPanel)
    check(near(groupTop - poolTop, 26 + 8), "layout: pool list starts one row below the groups' top")
    local L = Roster.layout
    check(near(L.COMP_Y + L.COMP_H, L.LIST_Y + L.LIST_H), "layout: composition box ends level with the pool list")
    check(L.COMP_H >= 80, "layout: composition box has room for two class rows")
    Editor:ShowTab("boards")
    check(boardsTab.page:IsShown() and not rosterTab.page:IsShown(), "tabs: back to boards")
end

-- Attendance ----------------------------------------------------------------------------
do
    local Att = ns.Attendance
    local Roster = ns.Roster
    local r = Roster:Current()
    local G = ns.db.guild
    -- raid of Jake + Raider01..10 (raid roster names have no realm), Raider10 offline
    local function raid(list)
        STUB.roster = { { name = "Jake", rank = 2, class = "HUNTER" } }
        for _, i in ipairs(list) do
            table.insert(STUB.roster, { name = ("Raider%02d"):format(i), class = "MAGE", online = i ~= 10 })
        end
    end
    local all10 = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 }
    raid(all10)
    STUB.instance = { "Skyreach Spire", "raid" }
    STUB.isLeader, STUB.isAssist = false, false
    Att:Check()
    check(Att:Active() == nil, "attendance: raiders who don't lead or assist don't record")
    STUB.isLeader = true
    STUB.printed = {}
    Att:Check()
    local s = Att:Active()
    check(s and s.name == "Skyreach Spire" and s.snaps == 1 and printedContains("recording"), "attendance: starts in a raid instance when leading")
    check(s.id and s.rev and s.by == "Jake" and s.rosterId == r.id, "attendance: session has sync fields and links the roster")
    check(s.present["Raider01-Realm"] == 1 and s.present["Raider10-Realm"] == nil, "attendance: raid names map to guild records, offline not counted")
    check(s.present["Jake-Realm"] == 1, "attendance: the recorder counts too")

    -- 5-minute snapshots via the timer; Raider09 leaves after the second
    STUB.Advance(300)
    check(s.snaps == 2, "attendance: snapshot every 5 minutes")
    raid({ 1, 2, 3, 4, 5, 6, 7, 8, 10 })
    STUB.Advance(300)
    STUB.Advance(300)
    check(s.snaps == 4 and s.present["Raider09-Realm"] == 2, "attendance: leaving stops the count")
    check(s.firstAt["Raider01-Realm"] == s.start and s.lastAt["Raider09-Realm"] == s.start + 300,
        "attendance: when each player was first and last seen")
    check(Att:Credit(s, "Raider01-Realm") == 1 and Att:Status(s, "Raider09-Realm") == "present",
        "attendance: no one is early until the night is over")

    -- a boss kill logs and snapshots
    STUB.Fire("ENCOUNTER_END", 3001, "Stormcaller Vael", 14, 20, 1)
    STUB.Fire("ENCOUNTER_END", 3002, "The Gale", 14, 20, 0)
    check(#s.bosses == 2 and s.bosses[1].success and not s.bosses[2].success and s.snaps == 6, "attendance: kills and wipes logged with a snapshot each")

    -- bench credit from the linked roster (Raider21/22 are on its bench)
    check(Att:Status(s, "Raider21-Realm") == "bench" and Att:Credit(s, "Raider21-Realm") == 1, "attendance: bench earns credit")
    G.benchCredit = false
    Att.cache = nil
    check(Att:Credit(s, "Raider21-Realm") == 0, "attendance: bench credit can be turned off")
    G.benchCredit = nil
    -- rostered but never came
    local names = Att:SessionNames(s)
    local seen = {}
    for _, n in ipairs(names) do seen[n] = true end
    check(seen["Raider15-Realm"] and Att:Status(s, "Raider15-Realm") == "absent", "attendance: rostered no-shows listed as absent")
    check(names[1] ~= nil and Att:Credit(s, names[1]) >= Att:Credit(s, names[#names]), "attendance: night sorted by credit")

    -- overrides
    Att:SetOverride(s, "Raider10-Realm", 1)
    check(Att:Credit(s, "Raider10-Realm") == 1 and Att:Status(s, "Raider10-Realm") == "set present", "attendance: override to present")
    local menu = Att:PlayerMenu(s, "Raider10-Realm")
    menu[#menu].func()
    check(Att:Credit(s, "Raider10-Realm") == 0, "attendance: override can be cleared")

    -- leaving the raid ends the night after 10 minutes, at the last snapshot
    local lastSnap = s.lastSnap
    STUB.roster = nil
    STUB.Fire("GROUP_ROSTER_UPDATE")
    STUB.Advance(300)
    check(Att:Active() == s, "attendance: a short break keeps the night open")
    STUB.Advance(330)
    check(Att:Active() == nil and s.stop == lastSnap, "attendance: night ends 10 minutes after leaving")

    -- two more nights for the summary; Raider01 misses one
    STUB.instance = { "Skyreach Spire", "raid" }
    raid({ 2, 3 })
    Att:Check()
    local s2 = Att:Active()
    STUB.Advance(300)
    Att:End()
    raid({ 1, 2 })
    STUB.Advance(60)
    Att:Check()
    local s3 = Att:Active()
    Att:End()
    check(s2 and s3 and s2 ~= s3 and #Att:Sessions() == 3, "attendance: separate nights")
    local sum = Att:Summary()
    local r1, r2 = sum.byName["Raider01-Realm"], sum.byName["Raider02-Realm"]
    check(sum.weeks == 1 and sum.nights == 3 and r1.last8 == 1 and r1.attended == 1,
        "summary: missing one night of the week still counts the week (best night)")
    check(r2.last8 == 1 and r2.all == 1, "summary: perfect attendance")
    check(ns.Sync:Store("nights")[s3.id] and ns.Sync:Store("nights")[s3.id].seen:find("Raider01-Realm:1:0:0", 1, true),
        "sharing: a night we recorded is shared with the officers")
    check(Att:Percent("Raider01-Realm") == r1.last8 and Att:Percent("Nobody") == 0, "summary: percent lookup")

    -- the roster pool shows it
    SlashCmdList.POGRAID("roster")
    Roster.search = "Raider01"
    Roster:RefreshPool()
    Roster.search = nil
    local row
    for _, rw in ipairs(Roster.poolRows) do if rw.player == "Raider01-Realm" then row = rw end end
    check(row and row.att == nil, "roster: no attendance column in the pool")
    STUB.Script(row, "OnEnter")
    check(table.concat(GameTooltip.lines, "|"):find("Attendance, weeks (4 / 8 / all) | 100% / 100% / 100%", 1, true) ~= nil,
        "roster: weekly attendance in the hover tooltip")
    STUB.Script(row, "OnLeave")

    -- tab UI
    SlashCmdList.POGRAID("attendance")
    check(Att.page and Att.page:IsShown(), "attendance: tab opens")
    check(Att.listRows[1].label:GetText() == "Summary" and Att.listRows[2].sessionId == s3.id, "attendance: summary first, newest night next")
    check(Att:Viewing() == s3, "attendance: opens on the night last recorded")
    STUB.Script(Att.listRows[1], "OnClick")
    check(Att.headCells[3].text:GetText():find("Last 8 wks", 1, true) and Att.tableRows[1].player ~= nil
        and Att.info:GetText() == "" and Att.listRows[2].count:GetText() == "", "attendance: summary table, by week, no counts")
    STUB.Script(Att.headCells[1], "OnClick")
    check(Att.sortCol == "name" and Att.tableRows[1].player < Att.tableRows[2].player, "attendance: header click sorts")
    Att.sortCol = nil
    STUB.Script(Att.listRows[4], "OnClick")
    check(Att:Viewing() == s and Att.headCells[2].text:GetText() == "Status", "attendance: clicking a night shows its players")
    check(Att.info:GetText():find("1 kill, 1 wipe", 1, true), "attendance: night info line")
    check(Att.startBtn:IsEnabled() ~= false, "attendance: start enabled when not recording")

    -- export
    local csv = Att:CSV()
    check(csv:find("^Player,Last 4 weeks,Last 8 weeks,All weeks,Weeks attended\n") and csv:find("\nRaider01,100,100,100,1", 1, true),
        "export: CSV")
    check(Att:DiscordText():find("Raider02 100%", 1, true), "export: Discord text")

    -- delete a night (two clicks), tombstone kept
    STUB.Script(Att.deleteBtn, "OnClick")
    STUB.Script(Att.deleteBtn, "OnClick")
    check(G.sessions[s.id].deleted and #Att:Sessions() == 2 and Att:Viewing() == nil, "attendance: delete night leaves a tombstone")
    check(ns.Sync:Store("nights")[s.id] == nil or ns.Sync:Store("nights")[s.id].deleted, "sharing: and the delete is shared")

    -- stale session closed on sight (e.g. logged out mid-raid overnight)
    raid({ 1 })
    Att:Check()
    local s4 = Att:Active()
    STUB.now = STUB.now + 5 * 3600
    Att:Check()
    check(s4.stop ~= nil and Att:Active() ~= s4, "attendance: stale night closed, not continued")
    if Att:Active() then Att:End() end

    -- a benched player who is called in stops earning bench time
    local r2 = Roster:Current()
    table.insert(r2.bench, "Raider05-Realm")
    raid({ 1 })
    Att:Check()
    local sb = Att:Active()
    STUB.Advance(1200) -- called in 20 minutes into the night
    raid({ 1, 5 })
    Att:Snapshot(sb)
    check(sb.benchSnaps["Raider05-Realm"] == 2 and sb.present["Raider05-Realm"] == 1, "attendance: bench time only while not in the raid")
    check(sb.firstAt["Raider05-Realm"] - sb.start >= 1200 and Att:Credit(sb, "Raider05-Realm") == 1
        and Att:Status(sb, "Raider05-Realm") == "present", "attendance: called in from the bench isn't late")
    Att:End()
    table.remove(r2.bench)
    Att:DeleteSession(sb)

    -- windows: ten raid weeks, Raider03 only came in the two oldest
    local saved = {}
    for id, x in pairs(G.sessions) do saved[id] = x end
    wipe(G.sessions)
    local base = 2900 * 604800 + 5 * 86400 + 15 * 3600 + 86400 -- a Wednesday
    local function night(id, start, present, snaps)
        G.sessions[id] = { id = id, name = id, start = start, stop = start + 7200, snaps = snaps or 1,
            present = present, benchSnaps = {}, bosses = {}, overrides = {} }
    end
    for i = 1, 10 do
        local present = { ["Raider02-Realm"] = 1 }
        if i <= 2 then present["Raider03-Realm"] = 1 end
        night("n" .. i, base + i * 604800, present)
    end
    Att:Changed()
    local w = Att:Summary().byName["Raider03-Realm"]
    check(w.last4 == 0 and w.last8 == 0 and math.abs(w.all - 0.2) < 1e-9 and w.attended == 2, "summary: last 4 / last 8 / all weeks")
    G.sessions["n9"].present["Raider03-Realm"] = 1
    Att:Changed()
    w = Att:Summary().byName["Raider03-Realm"]
    check(w.last4 == 0.25 and w.last8 == 0.125, "summary: a recent week counts in both windows")
    -- the other raid team's night that week: raiding either counts, never twice
    night("team2", base + 9 * 604800 + 86400, { ["Raider03-Realm"] = 1, ["Raider04-Realm"] = 1 })
    night("team2b", base + 10 * 604800 + 86400, { ["Raider03-Realm"] = 1, ["Raider04-Realm"] = 1 })
    Att:Changed()
    w = Att:Summary().byName["Raider03-Realm"]
    check(w.last4 == 0.5 and Att:Summary().byName["Raider02-Realm"].last4 == 1 and Att:Summary().weeks == 10,
        "summary: two teams, a week counts once either way")
    -- two officers recorded the same raid: listed once (the fuller one)
    night("dupA", base + 3 * 604800 + 3600, { ["Raider02-Realm"] = 5, ["Raider05-Realm"] = 5 }, 5)
    night("dupB", base + 3 * 604800 + 3900, { ["Raider02-Realm"] = 4, ["Raider05-Realm"] = 4 }, 4)
    night("other", base + 3 * 604800 + 3600, { ["Raider11-Realm"] = 5, ["Raider12-Realm"] = 5 }, 5)
    Att:Changed()
    local listed = {}
    for _, x in ipairs(Att:Sessions()) do listed[x.id] = true end
    check(listed.dupA and not listed.dupB and listed.other, "summary: one raid recorded twice shows once, two raids at once both show")
    wipe(G.sessions)
    for id, x in pairs(saved) do G.sessions[id] = x end
    Att:Changed()

    -- late, left early, said so: a two-hour night
    local function mins(n) for _ = 1, n / 5 do STUB.Advance(300) end end
    ns.Sync:Apply(ns.Sync.collections.notice, { id = "Raider04-Realm:" .. ns.RaidDay(), rev = ns.Now(), by = "Raider04-Realm",
        author = "Raider04-Realm", t = ns.Now(), day = ns.RaidDay(), late = true })
    raid({ 1, 2, 3, 5 })
    Att:Check()
    local sl = Att:Active()
    mins(10)
    raid({ 1, 2, 3, 5, 7 })
    mins(10)
    raid({ 1, 2, 3, 5, 7, 6 })
    mins(10)
    raid({ 1, 2, 3, 5, 7, 6, 4 })
    mins(30)
    raid({ 1, 2, 5, 7, 6, 4 })
    mins(55)
    raid({ 1, 2, 7, 6, 4 })
    mins(5)
    Att:End()
    local function cs(n) return Att:Credit(sl, n), Att:Status(sl, n) end
    local c, st = cs("Raider07-Realm")
    check(c == 1 and st == "present", "late: 15 minutes in still counts as on time")
    c, st = cs("Raider06-Realm")
    check(c == 0.5 and st == "late", "late: later than that is 50%, marked late")
    c, st = cs("Raider04-Realm")
    check(c == 1 and st == "late (said so)", "late: saying so ahead of time is full credit")
    c, st = cs("Raider03-Realm")
    check(c == 0.5 and st == "left early", "late: leaving more than 15 minutes early is 50%")
    c, st = cs("Raider05-Realm")
    check(c == 1 and st == "present", "late: leaving in the last 15 minutes is fine")
    Att:DeleteSession(sl)

    -- 0.16.2: late and early count from when the raid gathered and broke up, not from when the
    -- recorder zoned in or left (here they're in 30 minutes early and stay 40 minutes after)
    raid({ 1 })
    Att:Check()
    local sg = Att:Active()
    mins(30)
    raid({ 1, 2, 3, 4, 5, 6 })
    mins(10)
    raid({ 1, 2, 3, 4, 5, 6, 7 })
    mins(15)
    raid({ 1, 2, 3, 4, 5, 6, 7, 8 })
    mins(80)
    raid({ 1, 2, 3, 4, 5, 6, 7 })
    mins(15)
    raid({ 1 })
    mins(40)
    Att:End()
    local function cg(n) return Att:Credit(sg, n), Att:Status(sg, n) end
    local from, to = Att:Times(sg)
    -- (each change shows at the next 5-minute snapshot: the raid is first seen at +35, gone after +150)
    check(from == sg.start + 35 * 60 and to == sg.start + 150 * 60, "gathered: when half the raid had arrived, and left")
    c, st = cg("Raider02-Realm")
    check(c == 1 and st == "present", "gathered: arriving with the raid is on time, though the recorder zoned in 30 minutes earlier")
    c, st = cg("Raider07-Realm")
    check(c == 1 and st == "present", "gathered: 10 minutes after it gathered is still on time")
    c, st = cg("Raider08-Realm")
    check(c == 0.5 and st == "late", "gathered: 25 minutes after is late (leaving 15 before it broke up is fine)")
    c, st = cg("Raider03-Realm")
    check(c == 1 and st == "present", "gathered: leaving with the raid isn't early, though the recorder stayed 40 minutes")
    Att:DeleteSession(sg)

    -- 0.16.2: the night is shared as it goes (after each boss, every 15 minutes), so a crash or
    -- disconnect doesn't lose it
    local nights = ns.Sync:Store("nights")
    raid({ 1, 2, 3, 4, 5 })
    Att:Check()
    local sv = Att:Active()
    check(nights[sv.id] == nil, "live: nothing shared the moment recording starts")
    STUB.Fire("ENCOUNTER_END", 3001, "Stormcaller Vael", 14, 20, 1)
    check(nights[sv.id] and nights[sv.id].stop == nil and nights[sv.id].bosses:find("Stormcaller Vael", 1, true),
        "live: shared after a boss, still open")
    local rev1 = nights[sv.id].rev
    mins(15)
    check(nights[sv.id].rev > rev1 and nights[sv.id].snaps == sv.snaps, "live: and again every 15 minutes")
    -- the game crashes: everything since the last /reload is gone, but another officer has the night
    local liveRec = {}
    for k, v in pairs(nights[sv.id]) do liveRec[k] = v end
    G.sessions[sv.id], G.activeSession, nights[sv.id] = nil, nil, nil
    Att:Changed()
    check(ns.Sync:Apply(ns.Sync.collections.nights, liveRec), "live: (it comes back from another officer)")
    local back = G.sessions[sv.id]
    check(back and back.live and back.stop == nil and back.lastSnap > back.start and Att:Active() == nil,
        "live: a night still going arrives open, with when it was last seen")
    check(not select(2, Att:LateEarly(back, "Raider05-Realm")), "live: nobody has left early from a night still going")
    STUB.printed = {}
    Att:Check()
    check(Att:Active() == back and printedContains("carrying on recording") and not back.live and #Att:Sessions() >= 1,
        "live: back in the raid, the recorder carries on with that night instead of starting another")
    local snapsBefore = back.snaps
    mins(5)
    check(back.snaps == snapsBefore + 1, "live: and keeps snapshotting it")
    Att:End()
    check(back.stop and nights[sv.id].stop == back.stop, "live: ending it shares the finished night")
    Att:DeleteSession(back)

    -- one error mustn't stop recording for the rest of the night
    local realCheck, calls = Att.Check, 0
    Att.Check = function() calls = calls + 1 error("boom") end
    pcall(STUB.Advance, Att.CHECK_EVERY + 1)
    pcall(STUB.Advance, Att.CHECK_EVERY + 1)
    Att.Check = realCheck
    check(calls >= 2, "attendance: an error in one check doesn't stop the next")

    -- "I'll be late / leave early": one click, shared, and the leaders hear it
    STUB.printed = {}
    Att:NoticeMenu()[2].func()
    local nl, ne = Att:MyNotice()
    check(nl and not ne and ns.Sync:Store("notice")["Jake-Realm:" .. ns.RaidDay()].late and printedContains("noted: you'll be late tonight"),
        "notice: I'll be late, shared")
    SlashCmdList.POGRAID("early")
    nl, ne = Att:MyNotice()
    check(nl and ne, "notice: /pog early adds leaving early")
    SlashCmdList.POGRAID("ontime")
    nl, ne = Att:MyNotice()
    check(not nl and not ne and ns.Sync:Store("notice")["Jake-Realm:" .. ns.RaidDay()].deleted, "notice: /pog ontime clears it")
    STUB.printed = {}
    local today = ns.RaidDay()
    local nrec = { id = "Raider08-Realm:" .. today, rev = ns.Now(), by = "Raider08-Realm", author = "Raider08-Realm",
        t = ns.Now(), day = today, early = true }
    ns.Sync:Apply(ns.Sync.collections.notice, nrec)
    check(printedContains("Raider08 will leave early tonight"), "notice: raid leaders hear about it")
    STUB.printed = {}
    Att:OnNotice(nrec)
    check(not printedContains("Raider08"), "notice: once")
    check(not ns.Sync:Apply(ns.Sync.collections.notice, { id = "Raider09-Realm:" .. today, rev = ns.Now(), by = "Raider08-Realm",
        author = "Raider09-Realm", t = ns.Now(), day = today, late = true }), "notice: nobody posts one for someone else")

    -- nights recorded before sharing existed stay on this computer
    G.sessions["old-local"] = { id = "old-local", name = "Old night", start = ns.Now() - 90000, stop = ns.Now() - 86400,
        snaps = 2, present = { ["Raider02-Realm"] = 2 }, benchSnaps = {}, bosses = {}, overrides = {} }
    Att:SetOverride(G.sessions["old-local"], "Raider03-Realm", 1)
    check(ns.Sync:Store("nights")["old-local"] == nil, "sharing: nights from before sharing aren't shared")
    G.sessions["old-local"] = nil
    Att:Changed()

    -- shared nights from another officer arrive; members can't share nights
    local nightRec = { id = "officer-night", rev = ns.Now(), by = "Raider01-Realm", author = "Raider01-Realm", t = ns.Now() - 7200,
        name = "Team two", start = ns.Now() - 7200, stop = ns.Now(), snaps = 24,
        seen = "Raider11-Realm:24:0:7200/Raider12-Realm:10:2400:7200", bench = "Raider13-Realm:24", over = "Raider14-Realm:0.5",
        bosses = "Stormcaller Vael:1:1500" }
    check(ns.Sync:Apply(ns.Sync.collections.nights, nightRec), "sharing: an officer's night arrives")
    local on = G.sessions["officer-night"]
    check(on and on.name == "Team two" and on.present["Raider11-Realm"] == 24 and Att:Credit(on, "Raider11-Realm") == 1
        and Att:Status(on, "Raider12-Realm") == "late" and Att:Credit(on, "Raider13-Realm") == 1
        and Att:Credit(on, "Raider14-Realm") == 0.5 and on.bosses[1].success and on.bosses[1].name == "Stormcaller Vael",
        "sharing: with who came when, the bench, overrides and bosses")
    local forged = {}
    for k, v in pairs(nightRec) do forged[k] = v end
    forged.id, forged.by, forged.author = "member-night", "Raider05-Realm", "Raider05-Realm"
    check(not ns.Sync:Apply(ns.Sync.collections.nights, forged), "sharing: members can't share nights")
    ns.Sync:Apply(ns.Sync.collections.nights, { id = "officer-night", rev = ns.Now() + 1, by = "Raider01-Realm",
        author = "Raider01-Realm", t = nightRec.t, start = nightRec.start, snaps = 0, deleted = true })
    check(G.sessions["officer-night"].deleted, "sharing: an officer's delete reaches us")
    Att:Changed()

    -- layout: same grid as the roster tab
    local page = Att.page
    local pl, pt = STUB.rect(page)
    local tl, tt, tw, th = STUB.rect(Att.table)
    local ll, lt, lw, lh = STUB.rect(Att.listRows[1]:GetParent() or Att.table)
    check(near(tl - pl, 12 + 262 + 12) and near(tl + tw, pl + 902 - 12), "layout: table fills the right column")
    check(near(pt - tt, 98) and near(th, 464), "layout: table on the list rows of the grid")
    local nl2, nt2, nw2, nh2 = STUB.rect(Att.noticeBtn)
    check(near(nl2 + nw2, pl + 12 + 262) and near(pt - nt2, 30 + 26 + 8) and near(nh2, 26),
        "layout: Late / early lines up with the left column, on row 2")
    STUB.roster = nil
    STUB.isLeader = false
    STUB.instance = { "Stormwind", "none" }
    Editor:ShowTab("boards")
end

-- Loot log ------------------------------------------------------------------------------
do
    local Loot, Att, Roster = ns.Loot, ns.Attendance, ns.Roster
    local G = ns.db.guild
    local sword = STUB.Link(19019, "Thunderfury")
    local ring = STUB.Link(17063, "Band of Accuria")
    local blue = STUB.Link(18000, "Rare Belt", "0070dd")
    local green = STUB.Link(18001, "Green Boots", "1eff00")

    -- nothing is logged outside a recording night
    STUB.Fire("CHAT_MSG_LOOT", "Raider01 receives loot: " .. sword .. ".")
    check(#Loot:Entries() == 0, "loot: not logged when attendance isn't recording")

    STUB.roster = { { name = "Jake", rank = 2, class = "HUNTER" }, { name = "Raider01", class = "WARRIOR" },
        { name = "Raider02", class = "PRIEST" } }
    STUB.instance = { "Skyreach Spire", "raid" }
    STUB.isLeader = true
    Att:Check()
    local s = Att:Active()
    check(s ~= nil, "loot: night recording for the loot tests")

    -- chat messages, localized formats
    STUB.Fire("ENCOUNTER_END", 3001, "Stormcaller Vael", 14, 20, 1)
    STUB.Fire("CHAT_MSG_LOOT", "Raider01 receives loot: " .. sword .. ".")
    local e = Loot:Entries()[1]
    check(e and e.player == "Raider01-Realm" and e.itemID == 19019 and e.boss == "Stormcaller Vael" and e.sessionId == s.id,
        "loot: chat loot logged with player, item, boss and night")
    check(e.tag == "ms" and e.quality == 4 and e.id and e.rev and e.by == "Jake", "loot: epic, main spec by default, sync fields")
    STUB.Fire("CHAT_MSG_LOOT", "You receive loot: " .. ring .. ".")
    check(Loot:Entries()[1].player == "Jake-Realm" and Loot:Entries()[1].itemID == 17063, "loot: your own loot")
    STUB.Fire("CHAT_MSG_LOOT", "Raider02 receives loot: " .. blue .. "x2.")
    check(Loot:Entries()[1].link == blue and Loot:Entries()[1].player == "Raider02-Realm", "loot: stacked item message keeps a clean link")
    STUB.Fire("CHAT_MSG_LOOT", "Raider02 receives loot: " .. green .. ".")
    check(#Loot:Entries() == 3, "loot: below Rare skipped by default")
    local seenBeforeQuest = #G.seenLoot
    STUB.Fire("CHAT_MSG_LOOT", "You receive item: " .. STUB.Link(18000, "Quest Reward Blue", "0070dd") .. ".")
    STUB.Fire("CHAT_MSG_LOOT", "You receive item: " .. STUB.Link(18001, "Bought Blue", "0070dd") .. "x2.")
    check(#Loot:Entries() == 3 and #G.seenLoot == seenBeforeQuest,
        "loot: quest rewards and vendor buys ('You receive item') aren't raid loot or a drop")
    -- pugs in the raid (added to the pool by the attendance snapshot) are not guild members
    G.players["Pugsley"] = { manual = true, class = "ROGUE" }
    check(G.scanned and G.players["Raider01-Realm"].inGuild, "loot: (guild roster read for these)")
    STUB.Fire("CHAT_MSG_LOOT", "Pugsley receives loot: " .. STUB.Link(18002, "Pug Epic") .. ".")
    STUB.Fire("ENCOUNTER_LOOT_RECEIVED", 3001, 18003, STUB.Link(18003, "Pug Blade"), 1, "Strangerdanger", "MAGE")
    check(#Loot:Entries() == 3, "loot: loot for players outside the guild is not logged")
    check(Loot:AddManual("Pugsley", STUB.Link(18004, "Pug Ring")) ~= nil, "loot: Add loot still takes a pug")
    Loot:Delete(Loot:Entries()[1])
    G.players["Pugsley"] = nil
    STUB.Fire("CHAT_MSG_LOOT", { __secret = true })
    check(#Loot:Entries() == 3, "loot: hidden (secret) messages ignored safely")

    -- the same drop reported twice (chat + boss loot event) is one entry
    STUB.Fire("ENCOUNTER_LOOT_RECEIVED", 3001, 19019, sword, 1, "Raider01", "WARRIOR")
    check(#Loot:Entries() == 3, "loot: duplicate from a second source merged")
    STUB.Advance(200)
    STUB.Fire("ENCOUNTER_LOOT_RECEIVED", 3001, 19019, sword, 1, "Raider01", "WARRIOR")
    check(#Loot:Entries() == 4 and Loot:Entries()[1].boss == "Stormcaller Vael", "loot: a second copy later is its own entry, boss from the event")
    -- loot roll history
    C_LootHistory = {
        GetSortedInfoForDrop = function(enc, id) return { itemHyperlink = STUB.Link(19100, "Tier Helm"), winner = { playerName = "Raider02" } } end,
        GetInfoForEncounter = function(enc) return { encounterName = "The Gale" } end,
    }
    STUB.Fire("LOOT_HISTORY_UPDATE_DROP", 3002, 1)
    check(Loot:Entries()[1].itemID == 19100 and Loot:Entries()[1].boss == "The Gale", "loot: roll winners from loot history")
    C_LootHistory = nil
    -- boss credit only for loot soon after a kill
    STUB.Advance(700)
    STUB.Fire("CHAT_MSG_LOOT", "Raider02 receives loot: " .. STUB.Link(19200, "Late Cloak") .. ".")
    check(Loot:Entries()[1].boss == nil, "loot: no boss credited long after the kill")

    -- options: quality threshold
    G.lootMinQuality = 2
    STUB.Fire("CHAT_MSG_LOOT", "Raider02 receives loot: " .. green .. ".")
    check(Loot:Entries()[1].itemID == 18001, "loot: threshold lowered to Uncommon")
    local menu = Loot:OptionsMenu()
    check(menu[2].text == "> Uncommon quality", "loot: options show the threshold")
    menu[3].func()
    check(G.lootMinQuality == 3, "loot: threshold back to Rare")

    -- tagging, reassigning, deleting
    local helm
    for _, x in ipairs(Loot:Entries()) do if x.itemID == 19100 then helm = x end end
    local m = Loot:EntryMenu(helm)
    m[3].func()
    check(helm.tag == "os", "loot: tag as off spec")
    Loot:Reassign(helm, "Raider03")
    check(helm.player == "Raider03-Realm", "loot: given to someone else, mapped to the guild record")
    local green1 = Loot:Entries()[1]
    Loot:Delete(green1)
    check(G.loot[green1.id].deleted and #Loot:Entries() == 6, "loot: delete leaves a tombstone")

    -- counts over the last 8 nights feed the roster tooltip
    local c = Loot:Counts()
    check(c["Raider01-Realm"].ms == 2 and c["Raider01-Realm"].total == 2, "counts: main spec items")
    check(c["Raider03-Realm"].ms == 0 and c["Raider03-Realm"].total == 1, "counts: off spec not counted as main spec")
    SlashCmdList.POGRAID("roster")
    local slotName
    local r = Roster:Current()
    local _, g1, s1 = Roster:Locate("Raider01-Realm")
    local slot = Roster.slots[g1][s1]
    STUB.Script(slot, "OnEnter")
    local tip = table.concat(GameTooltip.lines, "\n")
    check(GameTooltip.shown and tip:find("Raider01", 1, true) and tip:find("Loot, last 8 nights | 2 main spec, 2 total", 1, true),
        "roster: hovering a raider shows loot")
    check(tip:find("Attendance, weeks (4 / 8 / all)", 1, true) and tip:find("Officer, level 60", 1, true), "roster: tooltip has rank and attendance")
    STUB.Script(slot, "OnLeave")
    check(not GameTooltip.shown, "roster: tooltip hides")

    -- manual entry: shift-click into the prompt, then the name
    SlashCmdList.POGRAID("loot")
    check(Loot.page and Loot.page:IsShown(), "loot: tab opens")
    Loot:PromptAdd()
    local prompt = ns.UI.promptFrame
    ChatEdit_InsertLink(STUB.Link(19300, "Manual Mace"))
    check(prompt.box:GetText():find("Manual Mace", 1, true), "manual: shift-click puts the link in the prompt")
    STUB.Script(prompt.box, "OnEnterPressed")
    STUB.Advance(0)
    prompt.box:SetText("Raider04")
    STUB.Script(prompt.box, "OnEnterPressed")
    local man = Loot:Entries()[1]
    check(man.itemID == 19300 and man.player == "Raider04-Realm" and man.source == "manual" and man.sessionId == s.id,
        "manual: added to the current night")
    Loot:PromptAdd()
    prompt.box:SetText("not a link")
    STUB.printed = {}
    STUB.Script(prompt.box, "OnEnterPressed")
    check(printedContains("shift-click the item"), "manual: plain text refused")

    -- filters and table
    Loot.player = "Raider01-Realm"
    Loot:Refresh()
    check(#Loot:Filtered() == 2 and Loot.rows[1].entry.player == "Raider01-Realm", "filter: by player")
    check(Loot.playerRows[1].label:GetText() == "All players" and Loot.playerRows[1].count == nil and Loot.info == nil,
        "filter: player list keeps all players, no counts")
    Loot.player = nil
    Loot.searchBox:SetText("tier")
    STUB.Script(Loot.searchBox, "OnTextChanged")
    check(#Loot:Filtered() == 1 and Loot:Filtered()[1].itemID == 19100, "filter: search by item name")
    Loot.searchBox:SetText("")
    STUB.Script(Loot.searchBox, "OnTextChanged")
    Att:End()
    STUB.Advance(60)
    Att:Start()
    STUB.Fire("CHAT_MSG_LOOT", "Raider02 receives loot: " .. STUB.Link(19400, "Next Week Wand") .. ".")
    Att:End()
    local nights = Loot:NightMenu()
    check(nights[1].text == "All nights" and #nights >= 3, "filter: night menu")
    for i = 2, #nights do
        nights[i].func()
        if Loot.night == s.id then break end
    end
    check(Loot.night == s.id and #Loot:Filtered() == 7, "filter: one night")
    check(Loot.rows[1].cells.item:GetText() == Loot:Filtered()[1].link and Loot.rows[1].cells.tag:GetText() ~= "", "table: item link and tag")
    STUB.Script(Loot.rows[1], "OnEnter")
    check(GameTooltip.link == Loot.rows[1].entry.link, "table: hovering shows the item tooltip")

    -- export
    local csv = Loot:CSV()
    check(csv:find("^Date,Player,Item,Item ID,Boss,Tag,Night\n") and csv:find(",Raider01,Thunderfury,19019,Stormcaller Vael,MS,", 1, true),
        "export: CSV")
    check(Loot:DiscordText():find("Raider01: Thunderfury (MS), Stormcaller Vael", 1, true), "export: Discord text")
    Loot.night = nil

    -- layout matches the other tabs
    local pl, pt = STUB.rect(Loot.page)
    local tl, tt, tw, th = STUB.rect(Loot.table)
    check(near(tl - pl, 286) and near(tl + tw, pl + 890) and near(pt - tt, 98) and near(th, 464), "layout: loot table on the grid")
    local ol, ot, ow = STUB.rect(Loot.nightBtn)
    check(near(ol, tl), "layout: night filter aligned with the table")
    STUB.roster = nil
    STUB.isLeader = false
    STUB.instance = { "Stormwind", "none" }
    Editor:ShowTab("boards")
end

-- Home dashboard --------------------------------------------------------------------------
do
    local Home, Roster = ns.Home, ns.Roster
    local G = ns.db.guild

    -- /pog always lands on Home; again on Home closes; from another tab it switches back
    SlashCmdList.POGRAID("loot")
    SlashCmdList.POGRAID("")
    check(Editor.frame:IsShown() and Editor.currentTab == "home", "home: /pog switches to Home from another tab")
    SlashCmdList.POGRAID("")
    check(not Editor.frame:IsShown(), "home: /pog on Home closes the window")
    SlashCmdList.POGRAID("")
    check(Editor.frame:IsShown() and Home.page:IsShown(), "home: /pog opens Home")

    -- guild activity from roster scans
    local before = #G.feed
    STUB.guild[4].level = 60
    local lv = STUB.guild[5]
    lv.level = 42
    G.players[lv.name].level = 40
    table.insert(STUB.guild, { name = "Newbie-Realm", rankIndex = 3, level = 5, online = true, class = "MAGE", zone = "Elwynn Forest" })
    local gone = table.remove(STUB.guild, 6)
    Roster:ScanGuild()
    local kinds = {}
    for i = 1, #G.feed - before do kinds[G.feed[i].kind .. ":" .. G.feed[i].name] = G.feed[i].value or true end
    check(kinds["level:" .. lv.name] == 42, "home: level-up noticed")
    check(kinds["join:Newbie-Realm"] == true, "home: new member noticed")
    check(kinds["leave:" .. gone.name] == true and G.players[gone.name].inGuild == false, "home: member who left noticed")
    check(Home:FeedText(G.feed[1]):find("the guild", 1, true) or Home:FeedText(G.feed[1]):find("reached level", 1, true),
        "home: feed lines read as sentences")
    local lvEntry
    for _, e in ipairs(G.feed) do
        if e.kind == "level" and e.name == lv.name then lvEntry = e break end
    end
    check(Home:FeedText(lvEntry):find("reached level 42", 1, true) and Home:FeedText(lvEntry):find("Raider05", 1, true),
        "home: level-up text")

    -- a roster that has not loaded yet, or hides offline members, must not look like everyone left
    local n = #G.feed
    local saved = STUB.guild
    STUB.guild = {}
    Roster:ScanGuild()
    check(#G.feed == n, "home: empty roster during load is ignored")
    STUB.guild = saved
    STUB.showOffline = false
    local offline = {}
    for i = #STUB.guild, 1, -1 do
        if not STUB.guild[i].online then offline[#offline + 1] = table.remove(STUB.guild, i) end
    end
    Roster:ScanGuild()
    check(#G.feed == n and G.players[offline[1].name].inGuild == true, "home: hidden offline members are not 'left'")
    for _, m in ipairs(offline) do table.insert(STUB.guild, m) end
    STUB.showOffline = true
    Roster:ScanGuild()
    check(#G.feed == n, "home: showing offline again changes nothing")
    table.insert(STUB.guild, gone)
    Roster:ScanGuild()
    check(G.feed[1].kind == "join" and G.feed[1].name == gone.name and G.players[gone.name].inGuild, "home: a member who comes back shows as joining")

    -- guild chat
    STUB.Fire("CHAT_MSG_GUILD", "anyone for Skyreach tonight?", "Raider01-Realm")
    STUB.Fire("CHAT_MSG_GUILD", { __secret = true }, "Raider02-Realm")
    check(G.chat[1].text == "anyone for Skyreach tonight?" and G.chat[1].name == "Raider01-Realm", "home: guild chat kept")
    check(G.chat[2] == nil or G.chat[2].text ~= nil, "home: hidden chat skipped")
    for i = 1, 120 do STUB.Fire("CHAT_MSG_GUILD", "spam " .. i, "Raider02-Realm") end
    check(#G.chat == Home.CHAT_MAX and G.chat[1].text == "spam 120", "home: chat capped, newest first")

    -- header: like the game's guild window
    STUB.motd = "Raid Thursday 8pm, bring flasks"
    STUB.guildInfo = "Loot: council. Attendance 75% for priority."
    STUB.canEditMOTD = false
    Home:Refresh()
    local hd = Home.header
    -- a real message starts with a "MOTD: " label in the title colour (0.16)
    local function motd() return ((hd.motd:GetText() or ""):gsub("^|c%x%x%x%x%x%x%x%x" .. Home.MOTD_LABEL .. "|r", "")) end
    check(hd.name:GetText() == "<Pog Squad>" and motd() == STUB.motd, "header: guild name in angle brackets, and the MOTD")
    -- a change arrives with GUILD_MOTD, even while the game still answers with the old one
    STUB.Fire("GUILD_MOTD", "New message, raid moved to Friday")
    check(motd() == "New message, raid moved to Friday", "header: a new message of the day shows at once")
    -- a blank one (the game sends one at login before the message is in) doesn't hide the real one
    STUB.Fire("GUILD_MOTD", "")
    check(motd() == STUB.motd, "header: a blank GUILD_MOTD keeps the game's message")
    local realMotd = STUB.motd
    STUB.motd = ""
    STUB.Fire("GUILD_MOTD", "")
    check(hd.motd:GetText() == "No message of the day.", "header: a cleared message clears")
    STUB.motd = realMotd
    Home.heardMOTD = nil
    Home:Refresh()
    check(hd.name.__fontSize == 22 and hd.motd.__fontSize == 12 and hd.name.__textColor[1] == 1 and hd.name.__textColor[2] == 0.82,
        "header: the guild's name big and gold")
    check(hd.logo == nil and hd.plate == nil, "header: no logo (it's in the window's corner)")
    check(hd.parchment ~= nil and hd.inset == nil and Home.feedCard.inset == nil,
        "header: faint parchment on Home's cards, no inset edges")
    -- the background: a mid grey with the marble over it, a shade lighter than the cards
    local wf = ns.Editor.frame
    check(wf.stone.__texture == ns.UI.SURFACE and ns.UI.SURFACE == ns.UI.Theme("night").surface and wf.stone.__blend == "ADD" and wf.bg.__color[1] == ns.UI.BACKING[1]
        and ns.UI.BACKING[1] > ns.UI.CARD[1], "home: the window is textured grey, a shade lighter than the cards (gentle breaks)")
    -- cards: lighter grey stone, lit from above, no borders
    local fc = Home.feedCard
    check(fc.marble and fc.marble.__texture == ns.UI.SURFACE and fc.marble.__blend == "ADD"
        and fc.bg.__color[1] == ns.UI.CARD[1]
        and fc.shade.__gradient and fc.shade.__gradient[1] == "VERTICAL" and fc.shade.__gradient[2].a == 0.30
        and fc.shade.__gradient[3].a == 0.06 and #fc.edges == 0, "home: cards are textured stone, lit from above")
    check(fc.softEdge and fc.softEdge.__backdrop.edgeFile == ns.UI.FILES.tooltip and fc.softEdge.__backdrop.edgeSize == 12
        and fc.softEdge.__borderColor[1] == ns.UI.CARD_EDGE[1] and fc.softEdge.__borderColor[4] == ns.UI.CARD_EDGE[4],
        "home: cards have the game's soft edge, toned down")
    local board = CreateFrame("Frame")
    ns.UI.Card(board, { 0.03, 0.03, 0.035, 1 })
    check(board.marble == nil and board.shade == nil, "home: a card with its own colour (game boards) stays flat")
    check(Home.StatValues == nil and hd.counts == nil, "header: no member counts (0.16)")
    check(hd.tiles == nil and Home.chart == nil and hd.edit == nil and hd.stats == nil,
        "header: no stat tiles, no level chart, no MOTD edit button")
    -- the guild's own card: name, the message (two lines), counts under it; no countdown
    check(hd.launch == nil and Home.Countdown == nil, "header: no launch countdown")
    -- 0.16: the name and message centred on a short card; no banner, no counts, no level spread
    local hl0, ht0, hw0, hh0 = STUB.rect(hd)
    local nl, nt, nameW = STUB.rect(hd.name)
    local ml, mt0, mw0 = STUB.rect(hd.motd)
    check(hh0 == Home.layout.HEADER_H and hw0 == Home.layout.LEFT_W and mt0 < nt and near(ml + mw0 / 2, nl + nameW / 2),
        "header: a short card as wide as Activity, the name centred over the message")
    check(hd.banner == nil and Home.LevelSpread == nil, "header: no guild banner, no level spread")

    -- achievements in the activity feed
    local ach = "|cffffff00|Hachievement:6:Jake:1:9:25:26:0:0:0:0|h[Level 10]|h|r"
    STUB.Fire("CHAT_MSG_GUILD_ACHIEVEMENT", "%s has earned the achievement " .. ach .. "!", "Raider01-Realm")
    check(G.feed[1].kind == "ach" and G.feed[1].value == ach and G.feed[1].name == "Raider01-Realm", "feed: achievement logged with its link")
    check(Home:FeedText(G.feed[1]):find("earned", 1, true) and Home:FeedText(G.feed[1]):find("[Level 10]", 1, true), "feed: achievement text")
    STUB.Fire("CHAT_MSG_GUILD_ACHIEVEMENT", "no link here", "Raider01-Realm")
    check(G.feed[1].value == ach, "feed: messages without an achievement ignored")
    Home:Refresh()
    STUB.Script(Home.feedCard.rows[1], "OnEnter")
    check(GameTooltip.link == ach, "feed: hovering an achievement shows it")

    -- message board: Jake is guild master here, so an officer
    local Social = ns.Social
    STUB.sent = {}
    check(Social:CanPost(), "board: officers can post")
    local bc = Home.boardCard
    check(bc.newPost:IsShown() and bc.empty:IsShown(), "board: empty board offers New post")
    STUB.Script(bc.newPost, "OnClick")
    local comp = ns.UI.composeFrame
    check(comp:IsShown() and comp.field1:IsShown(), "board: compose opens with a title field")
    comp.field1:SetText("Raid Thursday")
    comp.field2:SetText("Skyreach Spire at 8. Flasks and food.")
    STUB.Script(comp.submit, "OnClick")
    check(#Social:Posts() == 1 and Social:Posts()[1].title == "Raid Thursday" and not comp:IsShown(), "board: post created")
    check(#STUB.sent >= 1 and STUB.sent[1].channel == "GUILD" and STUB.sent[1].text:sub(1, 1) == "Y", "board: post shared with the guild")
    Home:Refresh()
    check(bc.posts[1]:IsShown() and bc.posts[1].title:GetText() == "Raid Thursday"
        and not bc.posts[1].meta:GetText():find("comment", 1, true), "board: post listed, no comment count")
    local realCover, covers = ns.Art.Cover, {}
    ns.Art.Cover = function(f, item, w, h)
        if f == bc then covers[#covers + 1] = h end
        return realCover(f, item, w, h)
    end
    STUB.Script(bc.posts[1], "OnClick")
    check(Home.openPost ~= nil and bc.thread:IsShown() and bc.back:IsShown() and not bc.newPost:IsShown(), "board: clicking a post opens the thread")
    check(bc:GetHeight() == Home.layout.BODY_H and not Home.chatCard:IsShown() and not Home.chatsCard:IsShown()
        and covers[#covers] == Home.layout.BODY_H and bc.thread.visible >= 3,
        "board: an open post takes the whole column, over guild chat, the art refitted")
    check(bc.thread.body:GetText():find("Flasks and food", 1, true), "board: thread shows the full message")
    STUB.Script(bc.thread.add, "OnClick")
    check(comp:IsShown() and not comp.field1:IsShown(), "board: comment compose has no title")
    comp.field2:SetText("Count me in")
    STUB.Script(comp.field2, "OnEnterPressed")
    check(bc.thread.comments[1]:IsShown() and bc.thread.comments[1].text:GetText() == "Count me in"
        and bc.thread.count:GetText() == "Comments", "board: comment shows in the thread")
    STUB.Script(bc.thread.comments[1], "OnClick") -- right-click menu on your own comment opens without errors
    STUB.Script(bc.pinBtn, "OnClick")
    check(Social:Posts()[1].pinned == true and bc.pinBtn.label:GetText() == "Unpin", "board: pin from the thread")
    local cm = Social:Comments(Social:Posts()[1].id)[1]
    Social:Remove("comments", cm)
    Home:Refresh()
    check(#Social:Comments(Social:Posts()[1].id) == 0 and bc.thread.count:GetText() == "No comments yet", "board: comment deleted")
    STUB.Script(bc.back, "OnClick")
    check(Home.openPost == nil and bc.posts[1].pin:GetText() == "Pinned", "board: back to the list, pinned marked")
    check(bc:GetHeight() == Home.layout.BOARD_H and Home.chatCard:IsShown() and Home.chatsCard:IsShown()
        and covers[#covers] == Home.layout.BOARD_H, "board: back, Chats and guild chat return, the art fits again")
    ns.Art.Cover = realCover
    STUB.Script(bc.posts[1], "OnClick")
    STUB.Script(bc.delete, "OnClick")
    check(#Social:Posts() == 1, "board: first Delete click only asks")
    STUB.Script(bc.delete, "OnClick")
    check(#Social:Posts() == 0 and Home.openPost == nil, "board: post deleted")
    -- a regular member sees no New post button
    ns.db.guild.officerRank = -1
    Home:Refresh()
    check(not Social:CanPost() and not bc.newPost:IsShown() and bc.empty:GetText() == "No posts yet.",
        "board: members can't post")
    ns.db.guild.officerRank = nil

    -- group finder
    local gc = Home.groupCard
    STUB.Script(gc.post, "OnClick")
    check(comp.field1:IsShown() and comp.fieldMid:IsShown() and comp.labelMid:GetText() == "Looking for"
        and comp.label2:GetText():find("Description", 1, true), "lfg: compose asks what, who and a description")
    local _, f1t = STUB.rect(comp.field1)
    local _, fmt = STUB.rect(comp.fieldMid)
    local _, at = STUB.rect(comp.area)
    check(near(f1t - fmt, 50) and near(fmt - at, 50), "lfg: compose boxes evenly spaced")
    comp.field1:SetText("Deadmines")
    comp.fieldMid:SetText("tank + healer")
    comp.field2:SetText("Full clear, VanCleef for the chest piece. Bring water.")
    STUB.Script(comp.submit, "OnClick")
    check(Social:MyGroup().desc == "Full clear, VanCleef for the chest piece. Bring water.", "lfg: description saved")
    Home:Refresh()
    STUB.Script(gc.rows[1], "OnEnter")
    local tip = table.concat(GameTooltip.lines, "\n")
    check(GameTooltip.shown and GameTooltip.lines[1] == "Deadmines" and tip:find("Looking for | tank + healer", 1, true)
        and tip:find("Group | 1/5", 1, true) and GameTooltip.lines[#GameTooltip.lines] == Social:MyGroup().desc,
        "lfg: hover shows the details and the description")
    STUB.Script(gc.rows[1], "OnLeave")
    check(#Social:Groups() == 1 and gc.rows[1].text:GetText() == "Deadmines" and gc.rows[1].right:GetText() == "1/5"
        and gc.rows[1].right2:GetText() == "45m left" and gc.rows[1].sub:GetText():find("needs tank + healer", 1, true),
        "lfg: listing shows 1/5 and time left")
    check(gc.post.label:GetText() == "Update", "lfg: button becomes Update once you have a listing")
    STUB.Script(gc.post, "OnClick")
    check(comp.field1:GetText() == "Deadmines" and comp.fieldMid:GetText() == "tank + healer"
        and comp.field2:GetText():find("VanCleef", 1, true), "lfg: update starts from your listing")
    comp.field1:SetText("Stockades")
    STUB.Script(comp.submit, "OnClick")
    check(#Social:Groups() == 1 and Social:Groups()[1].what == "Stockades" and Social:Groups()[1].desc:find("VanCleef", 1, true),
        "lfg: update replaces your listing, description kept")
    STUB.Advance(600)
    Home:Refresh()
    check(gc.rows[1].right2:GetText() == "35m left", "lfg: time left counts down")
    -- group size follows your party
    STUB.party = { { name = "Raider03", class = "MAGE" }, { name = "Raider04", class = "ROGUE" } }
    STUB.Fire("GROUP_ROSTER_UPDATE")
    Home:Refresh()
    check(Social:MyGroup().size == 3 and gc.rows[1].right:GetText() == "3/5", "lfg: 3/5 once two join")
    table.insert(STUB.party, { name = "Raider05", class = "PRIEST" })
    table.insert(STUB.party, { name = "Raider06", class = "WARRIOR" })
    STUB.Fire("GROUP_ROSTER_UPDATE")
    Home:Refresh()
    check(gc.rows[1].right:GetText() == "5/5 full" and Social:IsFull(Social:MyGroup()), "lfg: full at 5/5")
    STUB.party = nil
    STUB.Fire("GROUP_ROSTER_UPDATE")
    check(Social:MyGroup().size == 1, "lfg: back to 1/5 when the party breaks up")
    -- someone asks to join: pop-up, invite, answer whispered back
    local myId = Social:MyGroup().id
    STUB.sent, STUB.invites = {}, {}
    STUB.Fire("CHAT_MSG_ADDON", "PogRaid", "Jwrong-id", "WHISPER", "Raider07-Realm")
    check(Social:RequestCount() == 0, "join: request for another listing ignored")
    STUB.Fire("CHAT_MSG_ADDON", "PogRaid", "J" .. myId, "GUILD", "Raider07-Realm")
    check(Social:RequestCount() == 0, "join: requests only count as whispers")
    STUB.Fire("CHAT_MSG_ADDON", "PogRaid", "J" .. myId, "WHISPER", "Raider07-Realm")
    local pop = ns.JoinPopup.frame
    check(Social:RequestCount() == 1 and pop:IsShown() and pop.text:GetText():find("Raider07", 1, true)
        and pop.text:GetText():find("wants to join your Stockades group", 1, true), "join: pop-up for the poster")
    Home:Refresh()
    check(gc.rows[1].right2:GetText() == "1 request", "join: listing counts requests")
    STUB.Fire("CHAT_MSG_ADDON", "PogRaid", "J" .. myId, "WHISPER", "Raider08-Realm")
    check(pop.more:GetText() == "+1 more", "join: more requests queue")
    STUB.Script(pop.yes, "OnClick")
    check(STUB.invites[1] == "Raider07" and STUB.sent[1].text == "K1" .. myId and STUB.sent[1].target == "Raider07"
        and STUB.sent[1].channel == "WHISPER", "join: Invite invites and tells them")
    check(pop:IsShown() and pop.text:GetText():find("Raider08", 1, true), "join: next request shows")
    STUB.Script(pop.no, "OnClick")
    check(STUB.sent[2].text == "K0" .. myId and #STUB.invites == 1 and not pop:IsShown(), "join: No thanks declines, no invite")
    -- 0.16.2: updating the listing keeps the requests waiting, and asks for the old listing still count
    STUB.sent, STUB.invites = {}, {}
    STUB.Fire("CHAT_MSG_ADDON", "PogRaid", "J" .. myId, "WHISPER", "Raider09-Realm")
    Social:PostGroup("Stockades", "a tank", "")
    local newId = Social:MyGroup().id
    check(newId ~= myId and Social:RequestCount() == 1 and pop:IsShown() and pop.text:GetText():find("Raider09", 1, true),
        "join: updating the listing keeps the request and its pop-up")
    STUB.Fire("CHAT_MSG_ADDON", "PogRaid", "J" .. myId, "WHISPER", "Raider10-Realm")
    check(Social:RequestCount() == 2, "join: someone who saw the listing before the update can still ask")
    STUB.Script(pop.yes, "OnClick")
    check(STUB.invites[1] == "Raider09" and STUB.sent[1].text == "K1" .. myId, "join: and Invite still invites them")
    -- a brand-new group: the last one's requests are gone, pop-up included
    Social:Remove("lfg", Social:MyGroup())
    Social:PostGroup("Deadmines", "", "")
    check(Social:RequestCount() == 0 and not pop:IsShown(), "join: a new group starts without the last one's requests")
    STUB.Fire("CHAT_MSG_ADDON", "PogRaid", "J" .. myId, "WHISPER", "Raider11-Realm")
    check(Social:RequestCount() == 0, "join: or asks for its old listings")
    Social:Remove("lfg", Social:MyGroup())
    Social:PostGroup("Stockades", "", "")
    -- asking to join someone else's listing
    STUB.sent = {}
    -- someone else's listing can be whispered
    local other = { id = "Mira-1-1", rev = ns.Now(), by = "Raider02-Realm", author = "Raider02-Realm", t = ns.Now(),
        what = "Scarlet Monastery", need = "dps", exp = ns.Now() + 1800 }
    ns.Sync:Apply(ns.Sync.collections.lfg, other)
    Home:Refresh()
    local told
    ChatFrame_SendTell = function(name) told = name end
    for _, row in ipairs(gc.rows) do
        if row.item and row.item.id == "Mira-1-1" then STUB.Script(row, "OnClick") end
    end
    Home.Whisper("Raider02-Realm")
    check(told == "Raider02", "lfg: whisper opens a tell to the poster")
    local theirs = ns.Sync:Store("lfg")["Mira-1-1"]
    check(Social:RequestJoin(theirs) and STUB.sent[#STUB.sent].text == "JMira-1-1" and STUB.sent[#STUB.sent].target == "Raider02",
        "join: request whispered to the poster")
    Home:Refresh()
    local theirRow
    for _, row in ipairs(gc.rows) do if row.item and row.item.id == "Mira-1-1" then theirRow = row end end
    check(theirRow and theirRow.right2:GetText() == "requested", "join: listing shows requested")
    STUB.printed = {}
    STUB.Fire("CHAT_MSG_ADDON", "PogRaid", "K0Mira-1-1", "WHISPER", "Raider02-Realm")
    check(printedContains("can't take you") and not Social.requested["Mira-1-1"], "join: decline reported")
    theirs.size, theirs.max = 5, 5
    check(not Social:RequestJoin(theirs), "join: full groups can't be requested")
    theirs.size, theirs.max = 1, 5
    -- online now: whisper and invite
    STUB.invites = {}
    local onlineRow = Home.onlineCard.rows[1]
    if onlineRow.item == ns.Sync:Me() then onlineRow = Home.onlineCard.rows[2] end
    local who = onlineRow.item
    Home.Invite(who)
    check(STUB.invites[1] == Ambiguate(who, "none"), "online: invite from the list")
    Social:Remove("lfg", Social:MyGroup())
    check(#Social:Groups() == 1 and Social:Groups()[1].id == "Mira-1-1", "lfg: close my group")
    STUB.sent = {}

    -- online now
    Home:Refresh()
    local rows = Home.onlineCard.rows
    local onlineNames = Home:OnlineList()
    check(#onlineNames == ns.Count(Roster.online) and rows[1].item == onlineNames[1], "home: online list")
    local newbieRow
    Home.onlineCard.offset = 999 -- lowest level sorts last: scroll to the end
    Home:Refresh()
    for _, r in ipairs(rows) do if r.item == "Newbie-Realm" then newbieRow = r end end
    local newbieText = newbieRow and newbieRow.right:GetText()
    Home.onlineCard.offset = 0
    Home:Refresh()
    check(newbieText == "Elwynn Forest  5", "home: online row shows zone and level")
    check(G.players[onlineNames[1]].level >= G.players[onlineNames[#onlineNames]].level, "home: online sorted by level")
    STUB.Script(rows[1], "OnEnter")
    check(GameTooltip.shown and GameTooltip.lines[1] == Ambiguate(rows[1].item, "short"), "home: hovering someone online shows their tooltip")
    STUB.Script(rows[1], "OnLeave")

    -- Show offline (Jake): the rest of the guild under who's online, with the level they were last seen at
    local tog = Home.onlineCard.toggle
    check(tog:IsShown() and tog.label:GetText() == "Show offline" and #Home:MemberList() == #onlineNames,
        "offline: a Show offline button, off by default")
    STUB.Script(tog, "OnClick")
    local members = Home:MemberList()
    local offlineNames = {}
    for i = #onlineNames + 1, #members do offlineNames[#offlineNames + 1] = members[i] end
    local everyoneOff = true
    for _, n in ipairs(offlineNames) do if Roster.online[n] or not G.players[n].inGuild then everyoneOff = false end end
    check(tog.label:GetText() == "Hide offline" and ns.db.settings.homeOffline == true and #offlineNames > 0 and everyoneOff
        and members[1] == onlineNames[1], "offline: online first, then guild members who are offline")
    local sorted = true
    for i = 2, #offlineNames do
        if (G.players[offlineNames[i - 1]].level or 0) < (G.players[offlineNames[i]].level or 0) then sorted = false end
    end
    check(sorted, "offline: highest level first")
    -- the first offline row on screen
    local offRow
    for _ = 1, 20 do
        for _, r in ipairs(rows) do if r:IsShown() and r.item and not Roster.online[r.item] then offRow = offRow or r end end
        if offRow then break end
        Home.onlineCard.offset = Home.onlineCard.offset + 2
        Home:Refresh()
    end
    local offP = offRow and G.players[offRow.item]
    check(offRow and offRow.right:GetText() == tostring(offP.level) and offRow.text:GetText():find("^|cff7a7a82")
        and offRow.pic.__desaturated, "offline: greyed out, with their level")
    local menu
    local realShow = ns.UI.ShowMenu
    ns.UI.ShowMenu = function(_, e) menu = e end
    STUB.Script(offRow, "OnClick", "LeftButton")
    ns.UI.ShowMenu = realShow
    local canWhisper = false
    for _, e in ipairs(menu or {}) do if e.text == "Whisper" or e.text == "Invite to group" then canWhisper = true end end
    check(not canWhisper, "offline: no whisper or invite for someone offline")
    STUB.Script(tog, "OnClick")
    check(tog.label:GetText() == "Show offline" and not ns.db.settings.homeOffline and #Home:MemberList() == #onlineNames
        and Home.onlineCard.offset == 0, "offline: and back to just who's online")

    -- feed, chat and loot rows
    check(Home.feedCard.rows[1].item == G.feed[1] and Home.feedCard.rows[1].right:GetText() ~= "", "home: activity rows with age")
    -- guild chat: newest on the bottom row, like the chat window; the wheel goes back
    local chat = Home.chatCard
    local lastRow = chat.rows[#chat.rows]
    check(chat.title:GetText() == "Guild chat" and lastRow.item == G.chat[1] and lastRow.text:GetText():find("spam 120", 1, true)
        and chat.rows[1].item == G.chat[#chat.rows], "home: guild chat reads down to the newest")
    STUB.Script(lastRow, "OnEnter")
    check(GameTooltip.lines[2] == "spam 120", "home: chat tooltip shows the full message")
    STUB.Script(chat, "OnMouseWheel", 1)
    check(chat.offset == 2 and lastRow.item == G.chat[3], "home: scrolling up goes back in chat")
    STUB.Script(chat, "OnMouseWheel", -1)
    check(chat.offset == 0 and lastRow.item == G.chat[1], "home: and down to the newest again")
    local savedChat = G.chat
    G.chat = { savedChat[1], savedChat[2] }
    Home:Refresh()
    check(lastRow.item == G.chat[1] and chat.rows[#chat.rows - 1].item == G.chat[2] and not chat.rows[1]:IsShown(),
        "home: a little chat sits at the bottom")
    G.chat = savedChat
    Home:Refresh()
    -- recent loot: blue and up, from anywhere, kept apart from the raid loot log
    check(ns.Attendance:Active() == nil, "home: (no raid night recording for these)")
    local logBefore = #ns.Loot:Entries()
    local seen = G.seenLoot
    local seenBefore = #seen
    STUB.Fire("CHAT_MSG_LOOT", "Newbie receives loot: " .. STUB.Link(20001, "Dungeon Blue", "0070dd") .. ".")
    STUB.Fire("CHAT_MSG_LOOT", "Newbie receives loot: " .. STUB.Link(20002, "Quest Green", "1eff00") .. ".")
    STUB.Fire("CHAT_MSG_LOOT", "You receive loot: " .. STUB.Link(20003, "World Epic") .. ".")
    STUB.Fire("ENCOUNTER_LOOT_RECEIVED", 1, 20003, STUB.Link(20003, "World Epic"), 1, "Jake", "HUNTER")
    check(#seen == seenBefore + 2 and seen[1].itemID == 20003 and seen[2].itemID == 20001, "home: blue and epic kept, green skipped, duplicate merged")
    check(seen[2].player == "Newbie-Realm" and seen[1].player == "Jake-Realm", "home: loot mapped to guild names")
    STUB.Fire("CHAT_MSG_LOOT", "Strangerdanger receives loot: " .. STUB.Link(20004, "Pug Blue", "0070dd") .. ".")
    check(#seen == seenBefore + 2, "home: loot for a pug in the group is skipped")
    table.insert(seen, 1, { t = ns.Now(), player = "Strangerdanger", itemID = 20005, link = STUB.Link(20005, "Old Pug Drop") })
    Home:Refresh()
    check(Home.lootCard.rows[1].item == seen[2], "home: pug drops saved by older versions are hidden")
    table.remove(seen, 1)
    check(#ns.Loot:Entries() == logBefore, "home: raid loot log untouched outside raid nights")
    Home:Refresh()
    check(Home.lootCard.rows[1].item == seen[1] and Home.lootCard.rows[1].text:GetText():find("World Epic", 1, true)
        and Home.lootCard.meta:GetText() == "", "home: recent loot card")
    STUB.Script(Home.lootCard.rows[1], "OnEnter")
    check(GameTooltip.link == seen[1].link, "home: loot row shows the item tooltip")
    for i = 1, 120 do STUB.Fire("CHAT_MSG_LOOT", "Newbie receives loot: " .. STUB.Link(21000 + i, "Blue " .. i, "0070dd") .. ".") end
    check(#seen == Home.LOOT_MAX and seen[1].itemID == 21120, "home: recent loot capped, newest first")

    -- ages
    check(Home.Ago(ns.Now() - 30) == "now" and Home.Ago(ns.Now() - 300) == "5m" and Home.Ago(ns.Now() - 7200) == "2h"
        and Home.Ago(ns.Now() - 3 * 86400) == "3d", "home: ages")

    -- layout: three columns from the top; the guild card heads the left one
    local pl, pt = STUB.rect(Home.page)
    local hl, ht, hw, hh = STUB.rect(Home.header)
    local fl, ft, fw, fh = STUB.rect(Home.feedCard)
    local ol, ot, ow, oh = STUB.rect(Home.onlineCard)
    local bl, bt, bw, bh = STUB.rect(Home.boardCard)
    local gl, gt, gw, gh = STUB.rect(Home.groupCard)
    local ll, lt, lw, lh = STUB.rect(Home.lootCard)
    local chl, cht, chw, chh = STUB.rect(Home.chatCard)
    local xl, xt, xw, xh = STUB.rect(Home.chatsCard)
    -- 0.16: Online now under the guild card; Activity, Guild chat and Recent loot share the bottom half;
    -- LFM and LFG split the right column's top half. 0.16.8: Chats has the bottom third of the message board's half.
    check(near(hl - pl, 12) and near(hw, fw) and near(pt - ht, 30) and near(hh, Home.layout.HEADER_H), "layout: the guild card tops the left column")
    check(near(ot, ht - hh - 8) and near(ot - oh, xt - xh) and near(bt, ht) and near(gt, ht),
        "layout: Online now under it, the other columns start at the top")
    check(near(xt, bt - bh - 8) and near(xl, bl) and near(xw, bw) and near(xh, Home.layout.CHATS_H) and near(bh, Home.layout.BOARD_H)
        and near(bh + 8 + xh, Home.layout.HALF_H) and xh < bh / 2 + 1 and xh > bh / 3, "layout: Chats under the message board, about a third of that half")
    local _, r1t = STUB.rect(Home.chatsCard.rows[1])
    local _, r3t, _, r3h = STUB.rect(Home.chatsCard.rows[#Home.chatsCard.rows])
    check(#Home.chatsCard.rows == 3 and near(xt - r1t, 30) and near((r3t - r3h) - (xt - xh), 4), "layout: three chat rows fill the card")
    check(Home.boardCard.visible == 2, "layout: the board shows two posts above it (it scrolls)")
    check(near(fl - pl, 12) and near(bl, fl + fw + 8) and near(gl, bl + bw + 8) and near(gl + gw, pl + 890), "layout: three columns, even gaps")
    local bottom = ns.PAGE_H - 12
    check(near(pt - (ft - fh), bottom) and near(pt - (cht - chh), bottom) and near(pt - (lt - lh), bottom), "layout: every column ends at the margin")
    local lfg = Home.groupCard.lfg
    local _, lgt, _, lgh = STUB.rect(lfg)
    check(near(ft, ot - oh - 8) and near(cht, xt - xh - 8) and near(ft, cht) and near(ft, lt) and near(fh, chh) and near(fh, lh)
        and near(hh + 8 + oh, bh + 8 + xh) and near(lgt, gt - gh - 8) and near(gh, lgh) and near(gh + 8 + lgh, bh + 8 + xh) and near(lt, lgt - lgh - 8),
        "layout: the halves line up across: Activity, Guild chat and Recent loot start together; LFM over LFG")
    check(near(chl, bl) and near(chw, bw) and Home.feedCard:IsShown() and Home.chatCard:IsShown()
        and Home.feedCard.title:GetText() == "Activity", "layout: Activity and guild chat each have their own card")

    Editor:ShowTab("boards")
end

-- Sapper Sweeper ---------------------------------------------------------------------------
do
    local Games = ns.Games
    local Sweeper = Games.Sweeper

    -- rules, without the UI
    local g = Sweeper.New(9, 9, 10)
    check(#g:Neighbors(1) == 3 and #g:Neighbors(41) == 8 and #g:Neighbors(9) == 3, "sweeper: corner and middle neighbours")
    g:Reveal(41)
    local mines = 0
    for i = 1, g.n do if g.mine[i] then mines = mines + 1 end end
    check(g.state == "playing" and mines == 10 and not g.mine[41], "sweeper: mines placed after the first click, which is safe")
    SlashCmdList.POGRAID("plans")
    check(Editor.currentTab == "boards" and Editor.tabButtons.boards.label:GetText() == "Raid", "tabs: /pog plans opens Raid Plans")
    local clear = true
    for _, j in ipairs(g:Neighbors(41)) do if g.mine[j] then clear = false end end
    check(clear and g.count[41] == 0 and g.opened > 1, "sweeper: first click opens an area (neighbours kept clear)")
    local okCounts = true
    for i = 1, g.n do
        local c = 0
        for _, j in ipairs(g:Neighbors(i)) do if g.mine[j] then c = c + 1 end end
        if c ~= g.count[i] then okCounts = false end
    end
    check(okCounts, "sweeper: every number counts its neighbouring sappers")
    local floodOk = true
    for i = 1, g.n do
        if g.open[i] and g.count[i] == 0 then
            for _, j in ipairs(g:Neighbors(i)) do if not g.open[j] then floodOk = false end end
        end
    end
    check(floodOk, "sweeper: flood fill opens around every empty tile")

    -- the first click is never a sapper, even on a crowded board (8 in 9)
    local safe = true
    for k = 1, 200 do
        local t = Sweeper.New(3, 3, 8)
        local pick = (k % 9) + 1
        if t:Reveal(pick) == "boom" then safe = false end
    end
    check(safe, "sweeper: first click safe on 200 crowded boards")

    -- a fixed board: one mine at cell 1 of a 3x3
    local f = Sweeper.New(3, 3, 1)
    f.mine[1] = true
    f.count = { 0, 1, 0, 1, 1, 0, 0, 0, 0 }
    f.state = "playing"
    f:ToggleFlag(1)
    check(f.flags == 1 and f:Left() == 0, "sweeper: skulls count down the sappers left")
    f:ToggleFlag(1)
    check(f.flags == 0 and not f.flag[1], "sweeper: right-click again removes the skull")
    f:Reveal(5)
    check(f.open[5] and f.opened == 1 and f.state == "playing", "sweeper: a number opens just itself")
    f:Chord(5)
    check(f.opened == 1, "sweeper: clicking a number without enough skulls does nothing")
    f:ToggleFlag(1)
    f:ToggleFlag(5)
    check(not f.flag[5], "sweeper: can't mark an open tile")
    f:Chord(5)
    check(f.state == "won" and f.opened == 8, "sweeper: clicking a satisfied number opens the rest, and wins")
    local l = Sweeper.New(3, 3, 1)
    l.mine[9] = true
    l.count = { 0, 0, 0, 0, 1, 1, 0, 1, 0 }
    l.state = "playing"
    l:Reveal(5)
    l:ToggleFlag(1)
    check(l:Chord(5) == "boom" and l.state == "lost" and l.boom == 9, "sweeper: chording with a wrong skull sets off a sapper")
    local l2 = Sweeper.New(3, 3, 1)
    l2.mine[9] = true
    l2.count = { 0, 0, 0, 0, 1, 1, 0, 1, 0 }
    l2.state = "playing"
    check(l2:Reveal(9) == "boom", "sweeper: clicking a sapper loses")
    l2:Reveal(1)
    l2:ToggleFlag(2)
    check(not l2.open[1] and not l2.flag[2] and l2.opened == 0, "sweeper: nothing opens or marks after a loss")
    local w = Sweeper.New(3, 3, 2)
    w.mine[1], w.mine[3] = true, true
    w.count = { 0, 2, 0, 1, 2, 1, 0, 0, 0 }
    w.state = "playing"
    w:Reveal(8)
    check(w.state == "playing" and w.opened == 6, "sweeper: flood fill stops at numbers")
    w:Reveal(2)
    check(w.state == "won" and w.flag[1] and w.flag[3] and w:Left() == 0, "sweeper: winning marks every sapper")

    -- the tab
    SlashCmdList.POGRAID("games")
    check(Editor.currentTab == "games" and Games.page:IsShown(), "games: /pog games opens the tab")
    Games:SetMode("sweeper") -- 0.16 opens on Wowdle
    Games:NewGame("apprentice")
    check(Games.cells[1].__clicks and Games.cells[1].__clicks[1] == "LeftButtonDown" and Games.cells[1].__clicks[2] == "RightButtonDown",
        "games: tiles act on the press, so fast clicks aren't lost")
    local cell = Games.cellSize
    local pl, pt = STUB.rect(Games.page)
    local bl, bt, bw, bh = STUB.rect(Games.board)
    local sl, st, sw = STUB.rect(Games.bar)
    -- 0.16: the board from the page's left edge, the leaderboard card filling the rest of the width
    local scl, sct, scw = STUB.rect(Games.scores)
    check(cell == 40 and near(bw, 9 * 40 + 4) and near(bl - pl, 12) and near(scl, bl + bw + 8) and near(scl + scw, pl + 902 - 12),
        "games: apprentice board at the left, big tiles, the leaderboard beside it")
    check(near(sl, bl) and near(sw, bw) and near(st - bt, 44 + 4 + 18 + 4), "games: status bar lines up above the board")
    local ml, mt, mw, mh = STUB.rect(Games.bar.message)
    check(Games.bar.message.__parent == Games.page and near(mt, st - 44 - 4) and near(mh, 18) and mt - mh >= bt + 4,
        "games: win/loss line has its own space between the bar and the board")
    check(Games.help == nil and ns.Gems.help == nil, "games: no instructions under the boards (Jake)")
    Games:NewGame("expert")
    bl, bt, bw, bh = STUB.rect(Games.board)
    check(near(bw, 30 * Games.cellSize + 4) and bl - pl >= 12 and bl + bw <= pl + 890 and pt - (bt - bh) <= ns.PAGE_H - 12 - 6,
        "games: expert fits above the help line")
    check(Games.cells[480]:IsShown() and Games.levelButtons.expert.selected, "games: 30x16 tiles")
    Games:NewGame("journeyman")
    check(not Games.cells[300]:IsShown() and Games.cells[256]:IsShown(), "games: extra tiles hidden on a smaller board")

    -- play through the UI
    STUB.Script(Games.cells[1], "OnClick", "RightButton")
    check(Games.game.flag[1] and Games.cells[1].icon:IsShown() and Games.cells[1].icon.__raidIcon == 8
        and Games.bar.left:GetText() == "39", "games: right-click marks a skull")
    STUB.Script(Games.cells[1], "OnClick", "RightButton")
    STUB.Script(Games.cells[137], "OnClick", "LeftButton")
    check(Games.game.state == "playing" and Games.started ~= nil and Games.page.__scripts.OnUpdate ~= nil, "games: first click starts the clock")
    local gg = Games.game
    local shownOk = true
    for i = 1, gg.n do
        local c = Games.cells[i]
        if gg.open[i] and gg.count[i] > 0 and c.num:GetText() ~= tostring(gg.count[i]) then shownOk = false end
        if not gg.open[i] and not c.lightT:IsShown() then shownOk = false end
    end
    check(shownOk, "games: open tiles show numbers, covered tiles stay raised")
    STUB.Advance(12)
    Games:RefreshBar()
    check(Games.bar.time:GetText() == "12s", "games: timer counts")
    -- step on a sapper
    local bomb
    for i = 1, gg.n do if gg.mine[i] then bomb = i break end end
    STUB.Script(Games.cells[bomb], "OnClick", "LeftButton")
    check(gg.state == "lost" and Games.cells[bomb].icon:IsShown() and Games.cells[bomb].bg.__color[1] > 0.5,
        "games: KABOOM, the sapper you hit glows red")
    check(Games.bar.message:GetText():find("KABOOM", 1, true) and Games.page.__scripts.OnUpdate == nil, "games: loss message, clock stops")
    local anyOther
    for i = 1, gg.n do if gg.mine[i] and i ~= bomb and Games.cells[i].icon:IsShown() then anyOther = true end end
    check(anyOther, "games: every sapper revealed after a loss")
    STUB.Script(Games.bar.face, "OnClick")
    check(Games.game ~= gg and Games.game.state == "ready" and Games.bar.time:GetText() == "0s", "games: the gnome starts a new game")

    -- win and best time
    Games:NewGame("apprentice")
    local win = Games.game
    STUB.Script(Games.cells[41], "OnClick", "LeftButton")
    STUB.Advance(30)
    for i = 1, win.n do
        if not win.mine[i] and not win.open[i] then STUB.Script(Games.cells[i], "OnClick", "LeftButton") end
    end
    check(win.state == "won" and ns.db.games.best.apprentice and math.abs(ns.db.games.best.apprentice - 30) < 1,
        "games: winning saves a best time")
    check(Games.bar.message:GetText():find("Cleared in 30s", 1, true) and Games.bar.message:GetText():find("new best", 1, true),
        "games: win message")
    Games:NewGame("apprentice")
    check(Games.bar.message:GetText():find("Best on Apprentice: 30s", 1, true), "games: best time shown under the bar between games")
    Games:NewGame("apprentice")
    STUB.Script(Games.cells[41], "OnClick", "LeftButton")
    STUB.Advance(90)
    for i = 1, Games.game.n do
        if not Games.game.mine[i] and not Games.game.open[i] then STUB.Script(Games.cells[i], "OnClick", "LeftButton") end
    end
    check(math.abs(ns.db.games.best.apprentice - 30) < 1 and not Games.bar.message:GetText():find("new best", 1, true),
        "games: a slower win keeps the best time")
    check(Games.FormatTime(75) == "1:15" and Games.FormatTime(9) == "9s", "games: time format")
    check(ns.db.games.level == "apprentice", "games: difficulty remembered")

    -- guild leaderboard
    local scores = ns.Sync:Store("scores")
    local mine = scores["Jake-Realm:apprentice"]
    check(mine and math.abs(mine.best - 30) < 1 and mine.author == "Jake-Realm", "leaderboard: your best is shared")
    local others = {
        { "Raider02-Realm", "apprentice", 18.4 }, { "Raider03-Realm", "apprentice", 55 }, { "Raider04-Realm", "expert", 301 },
    }
    for _, o in ipairs(others) do
        ns.Sync:Apply(ns.Sync.collections.scores, { id = o[1] .. ":" .. o[2], rev = ns.Now(), by = o[1], author = o[1],
            t = ns.Now() - 3600, level = o[2], best = o[3] })
    end
    check(not ns.Sync:Apply(ns.Sync.collections.scores, { id = "Raider05-Realm:apprentice", rev = ns.Now(), by = "Raider06-Realm",
        author = "Raider05-Realm", t = ns.Now(), level = "apprentice", best = 1 }), "leaderboard: can't post a time for someone else")
    check(not ns.Sync:Apply(ns.Sync.collections.scores, { id = "Raider05-Realm:legendary", rev = ns.Now(), by = "Raider05-Realm",
        author = "Raider05-Realm", t = ns.Now(), level = "legendary", best = 1 }), "leaderboard: unknown difficulty rejected")
    local board = Games:Leaderboard("apprentice")
    check(#board == 3 and board[1].author == "Raider02-Realm" and board[2].author == "Jake-Realm" and Games:Rank("apprentice", "Jake-Realm") == 2,
        "leaderboard: fastest first")
    Games:RefreshScores()
    check(Games.scoresBtn == nil and Games.scores:IsShown() and Games.board:IsShown() and Games.bar:IsShown(),
        "leaderboard: always beside the game, no button to swap")
    local col = Games.scores
    check(col.rows[1].name:GetText() == "Raider02" and col.rows[1].time:GetText() == "18.4s" and col.rows[1].rank:GetText() == "1.",
        "leaderboard: rows show rank and name")
    check(col.rows[2].mine:IsShown() and not col.rows[1].mine:IsShown(), "leaderboard: your row highlighted")
    STUB.Script(Games.levelButtons.expert, "OnClick")
    local expertTime = col.rows[1].time:GetText()
    STUB.Script(Games.levelButtons.journeyman, "OnClick")
    check(expertTime == "5:01" and col.empty:IsShown(), "leaderboard: shows the picked difficulty's times")
    STUB.Script(Games.levelButtons.apprentice, "OnClick")
    -- you outside the top rows: your place shows at the bottom
    for i = 1, 22 do
        local who = ("Speedy%02d-Realm"):format(i)
        ns.Sync:Apply(ns.Sync.collections.scores, { id = who .. ":apprentice", rev = ns.Now(), by = who, author = who,
            t = ns.Now(), level = "apprentice", best = 10 + i / 10 })
    end
    Games:RefreshScores()
    local last = col.rows[#col.rows]
    check(last:IsShown() and last.rank:GetText() == "24." and last.mine:IsShown(), "leaderboard: your rank shown below the top 20")
    -- beating your time: shared and ranked in the win message
    STUB.Script(Games.levelButtons.apprentice, "OnClick")
    check(Games.board:IsShown() and Games.scores:IsShown(), "leaderboard: picking a difficulty keeps the game in view")
    STUB.Script(Games.cells[41], "OnClick", "LeftButton")
    STUB.Advance(5)
    for i = 1, Games.game.n do
        if not Games.game.mine[i] and not Games.game.open[i] then STUB.Script(Games.cells[i], "OnClick", "LeftButton") end
    end
    check(math.abs(scores["Jake-Realm:apprentice"].best - 5) < 0.2 and Games.bar.message:GetText():find("#1 in the guild", 1, true),
        "leaderboard: new best shared and ranked")
    -- best times from before the leaderboard get shared
    ns.db.games.best.journeyman = 123.45
    Games:PublishAll()
    check(scores["Jake-Realm:journeyman"] and scores["Jake-Realm:journeyman"].best == 123.5, "leaderboard: older best times shared")
    local rev, sentBefore = scores["Jake-Realm:journeyman"].rev, #STUB.sent
    STUB.Advance(5)
    Games:PublishAll()
    check(scores["Jake-Realm:journeyman"].rev == rev and #STUB.sent == sentBefore, "leaderboard: nothing resent when unchanged")
    check(Games.FormatBest(18.44) == "18.4s" and Games.FormatBest(301) == "5:01", "leaderboard: time format")
    Editor:ShowTab("boards")
end

-- Demo data ------------------------------------------------------------------------------
do
    local G = ns.db.guild
    local realNights, realLoot, realSeen = #ns.Attendance:Sessions(), #ns.Loot:Entries(), #G.seenLoot
    SlashCmdList.POGRAID("attendance")
    SlashCmdList.POGRAID("demo")
    local nights = ns.Attendance:Sessions()
    check(#nights == realNights + 8 and #ns.Loot:Entries() > realLoot + 8 and #G.seenLoot > realSeen, "demo: nights, loot and recent drops added")
    local sum = ns.Attendance:Summary()
    local spread = {}
    for _, r in ipairs(sum.rows) do spread[math.floor(r.last8 * 4)] = true end
    check(ns.Count(spread) >= 3, "demo: attendance has a spread of percentages")
    local demoNight
    for _, s in ipairs(nights) do if s.demo then demoNight = s break end end
    check(demoNight and #demoNight.bosses == 10 and demoNight.stop - demoNight.start == 3 * 3600, "demo: nights have bosses and a length")
    local tags, withBoss = {}, 0
    for _, e in ipairs(ns.Loot:Entries()) do
        if e.demo then tags[e.tag] = true; if e.boss then withBoss = withBoss + 1 end end
    end
    check(tags.ms and tags.os and tags.de and withBoss > 8, "demo: loot has tags and bosses")
    STUB.printed = {}
    SlashCmdList.POGRAID("demo")
    check(printedContains("already in") and #ns.Attendance:Sessions() == realNights + 8, "demo: not added twice")
    SlashCmdList.POGRAID("loot")
    SlashCmdList.POGRAID("home")
    SlashCmdList.POGRAID("demo clear")
    check(#ns.Attendance:Sessions() == realNights and #ns.Loot:Entries() == realLoot and #G.seenLoot == realSeen,
        "demo: clear removes exactly the demo data")
    local leftover = false
    for _, p in pairs(G.players) do if p.demo then leftover = true end end
    check(not leftover, "demo: made-up raiders removed too")
    Editor:ShowTab("boards")
end

-- Visual polish ---------------------------------------------------------------------------
do
    local UI, Roster, Home, Att = ns.UI, ns.Roster, ns.Home, ns.Attendance
    SlashCmdList.POGRAID("roster")
    -- cards: fill, no outline
    for _, f in ipairs({ Roster.poolPanel, Roster.groupBoxes[1], Roster.benchBox }) do
        check(#f.edges == 0 and f.bg.__color[1] == UI.CARD[1], "polish: roster cards have a fill and no outline")
    end
    -- buttons: outlines, filled only when selected or primary
    local clearBtn
    for _, b in ipairs({ Roster.sizeButtons[10], Roster.sizeButtons[20] }) do
        if not b.selected then clearBtn = b end
    end
    check(clearBtn.bg.__color[4] == 0 and #clearBtn.edges == 4, "polish: ordinary buttons are outlines")
    local sel = Roster.sizeButtons[Roster:Current().size]
    check(sel.bg.__color[4] == 1, "polish: selected buttons fill")
    -- section titles
    check(Roster.groupBoxes[1].title:GetText() == "Group 1" and Roster.benchBox.title:GetText() == "Bench"
        and Roster.groupBoxes[1].title.__fontSize == 12, "polish: section titles as the game writes them, no capitals")
    -- empty groups: no 0/5, no stripes
    local r = Roster:Current()
    local emptyGroup
    for g = 1, Roster:Groups() do
        local any = false
        for s2 = 1, 5 do if r.groups[g][s2] then any = true end end
        if not any then emptyGroup = g end
    end
    if not emptyGroup then
        for s2 = 1, 5 do r.groups[4][s2] = nil end
        emptyGroup = 4
        Roster:Refresh()
    end
    check(Roster.groupBoxes[emptyGroup].count:GetText() == "", "polish: empty groups hide 0/5")
    local wellsOk = true
    for s2 = 1, 5 do
        local w = Roster.slots[emptyGroup][s2].well
        if not w or w.__color[1] ~= 0 or w.__color[4] < 0.2 then wellsOk = false end
    end
    check(wellsOk, "polish: empty groups show five dark spots")
    local fg, fs2
    for g = 1, Roster:Groups() do for s2 = 1, 5 do if r.groups[g][s2] then fg, fs2 = g, s2 end end end
    local fw = Roster.slots[fg][fs2].well
    check(fw.__color[1] == 1 and fw.__color[4] < 0.1, "polish: a filled spot is lighter")
    local wl, wt, ww, wh = STUB.rect(Roster.slots[fg][fs2])
    check(near(wh, 22), "polish: spots keep the 22px row")
    -- online is a dot, not a word
    Roster.search = nil
    Roster:RefreshPool()
    local dotRow, wordOnline
    for _, row in ipairs(Roster.poolRows) do
        if row.player and Roster.online[row.player] then dotRow = row end
        if row.note:GetText() == "online" then wordOnline = true end
    end
    check(dotRow and dotRow.dot:IsShown() and not wordOnline, "polish: a green dot marks who's online")
    -- scroll hints only when the list overflows
    local names = Roster:PoolNames()
    check((#names > Roster.poolVisible) == Roster.poolHint.tex:IsShown(), "polish: pool scroll hint when it overflows")
    Roster.searchBox:SetText("Raider01")
    STUB.Script(Roster.searchBox, "OnTextChanged")
    check(not Roster.poolHint.tex:IsShown(), "polish: no scroll hint for a short list")
    Roster.searchBox:SetText("")
    STUB.Script(Roster.searchBox, "OnTextChanged")
    local h = UI.ScrollHint(Roster.poolPanel, 2, 2)
    h:Set(0, 10, 40)
    local _, t0 = STUB.rect(h.tex)
    h:Set(30, 10, 40)
    local _, t1, _, hh = STUB.rect(h.tex)
    local _, pt2, _, ph = STUB.rect(Roster.poolPanel)
    check(near(hh, (ph - 4) / 4) and t1 < t0 and near((t1 - hh), pt2 - ph + 2), "polish: scroll hint size and position track the list")
    -- window close and home
    -- the classic look: the game's red round X, pressing down, glowing on hover
    local x = Editor.closeBtn
    check(x.bg == nil and x.label == nil and x.tex.__texture == ns.UI.FILES.close .. "Up" and x.tex.__w == 32
        and x.visualW == 20, "polish: close button is the game's red X (round, where the square atlas is missing)")
    STUB.Script(x, "OnMouseDown")
    local pressed = x.tex.__texture
    STUB.Script(x, "OnMouseUp")
    check(pressed == ns.UI.FILES.close .. "Down" and x.tex.__texture == ns.UI.FILES.close .. "Up", "polish: the X presses down")
    check(ns.Gear.window == nil or ns.Gear.window.close.tex ~= nil, "polish: Inspect has the red X too")
    -- where the client has it (Forever does), the square red X its own windows use
    local oldTex = C_Texture
    C_Texture = { GetAtlasInfo = function(name) if name:find("^RedButton") then return { width = 32, height = 32 } end end }
    local sq = ns.UI.CloseButton(CreateFrame("Frame"), 22, 22, function() end)
    STUB.Script(sq, "OnMouseDown")
    local sqDown = sq.tex.__atlas
    STUB.Script(sq, "OnMouseUp")
    C_Texture = oldTex
    check(sq.square and sq.tex.__atlas == "RedButton-Exit" and sq.tex.__w == 22 and sqDown == "RedButton-exit-pressed"
        and sq.visualW == 22, "polish: the square red X where the client has it, pressing down")
    -- the plain look keeps an X like the tabs
    ns.UI.classic = false
    local plain = ns.UI.CloseButton(CreateFrame("Frame"), 28, 30, function() end)
    ns.UI.classic = true
    check(plain.label:GetText() == "X" and plain.visualW == plain.label:GetStringWidth(), "polish: plain look, a plain X")
    SlashCmdList.POGRAID("home")
    check(#Home.header.edges == 0, "polish: home banner has no outline or accent line")
    STUB.motd = ""
    Home:Refresh()
    check(Home.header.motd.__textColor[2] < 0.6, "polish: empty message of the day is dim")
    STUB.motd = "Raid tonight"
    Home:Refresh()
    check(Home.header.motd.__textColor[2] > 0.8, "polish: a real message of the day is green")
    check(Home.feedCard.title:GetText() == "Activity" and Home.chatCard.title:GetText() == "Guild chat", "polish: Activity and Guild chat titles")
    check(Home.boardCard.title:GetText() == "Message board", "polish: home section titles")
    check((Home.onlineCard.meta:GetText() or "") == "", "polish: Online now doesn't repeat the guild card's count")
    STUB.motd = ""
    Editor:ShowTab("boards")
end

-- Ranked duels -----------------------------------------------------------------------------
do
    local Duels, Games = ns.Duels, ns.Games
    -- chess-style math
    check(math.abs(Duels.Expected(1200, 1200) - 0.5) < 1e-9, "elo: even match is 50/50")
    local a, b = Duels.Update(1200, 1200, true)
    check(math.abs(a - 1216) < 1e-9 and math.abs(b - 1184) < 1e-9, "elo: even win is +16 / -16")
    local up = Duels.Update(1200, 1400, true) - 1200
    local down = Duels.Update(1400, 1200, true) - 1400
    check(up > 24 and up < 25 and down > 7 and down < 8, "elo: upsets pay more than expected wins")
    -- reading the game's duel announcements
    local w, l = Duels:ParseResult("Jake has defeated Raider02 in a duel")
    check(w == "Jake" and l == "Raider02", "duel: knockout message read")
    w, l = Duels:ParseResult("Raider02 has fled from Jake in a duel")
    check(w == "Jake" and l == "Raider02", "duel: fleeing counts as a loss")
    check(Duels:ParseResult("Jake has come online.") == nil, "duel: other system messages ignored")

    -- the Games tab switch
    SlashCmdList.POGRAID("duels")
    check(Editor.currentTab == "games" and Games.mode == "duels" and Games.duelsView:IsShown()
        and not Games.board:IsShown() and not Games.levelButtons.expert:IsShown(), "duels: /pog duels opens the Ranked Duels page")
    check(Games.modeTabs.duels.selected and not Games.modeTabs.sweeper.selected, "duels: page tabs")
    local card = Duels.card
    check(card.rating:GetText() == "1200" and card.rank:GetText():find("Unranked", 1, true), "duels: everyone starts at 1200")

    -- challenging your target
    STUB.sent, STUB.duels, STUB.printed = {}, {}, {}
    STUB.target = "Raider02"
    STUB.Script(card.challengeTarget, "OnClick")
    local out = Duels.outgoing
    check(out and STUB.sent[1].channel == "WHISPER" and STUB.sent[1].target == "Raider02"
        and STUB.sent[1].text == ("D1%d:%s"):format(out.t, out.id), "duels: challenge whispered")
    check(card.status:GetText():find("Waiting for", 1, true) and not card.challengeTarget:IsEnabled(), "duels: waiting, no second challenge")
    STUB.Fire("CHAT_MSG_ADDON", "PogRaid", "D21" .. out.id, "WHISPER", "Raider09-Realm")
    check(Duels.outgoing == out, "duels: answers from someone else ignored")
    STUB.Fire("CHAT_MSG_ADDON", "PogRaid", "D21" .. out.id, "WHISPER", "Raider02-Realm")
    check(Duels.agreed and Duels.agreed.challenger == "Jake-Realm" and card.send:IsShown(), "duels: accepted, Send duel appears")
    STUB.Script(card.send, "OnClick")
    check(STUB.duels[1] == "Raider02", "duels: Send duel sends the real duel")
    -- an unrelated duel doesn't count
    STUB.Fire("CHAT_MSG_SYSTEM", "Raider05 has defeated Raider06 in a duel")
    check(Duels.agreed ~= nil, "duels: other people's duels ignored")
    STUB.Fire("CHAT_MSG_SYSTEM", "Jake has defeated Raider02 in a duel")
    local store = ns.Sync:Store("duels")
    local myReport = store[out.id .. ":Jake-Realm"]
    check(myReport and myReport.winner == "Jake-Realm" and myReport.a == "Jake-Realm" and myReport.b == "Raider02-Realm"
        and Duels.agreed == nil, "duels: result reported")
    check(#Duels:Table().list == 0 and printedContains("waiting for Raider02"), "duels: one report isn't enough")
    -- the other player's addon confirms
    STUB.printed = {}
    ns.Sync:Apply(ns.Sync.collections.duels, { id = out.id .. ":Raider02-Realm", rev = ns.Now(), by = "Raider02-Realm",
        author = "Raider02-Realm", t = out.t, match = out.id, a = "Jake-Realm", b = "Raider02-Realm", winner = "Jake-Realm" })
    local tbl = Duels:Table()
    check(math.floor(tbl.players["Jake-Realm"].rating + 0.5) == 1216 and math.floor(tbl.players["Raider02-Realm"].rating + 0.5) == 1184,
        "duels: confirmed, ratings move")
    check(printedContains("ranked duel won: 1200 -> 1216 (+16)"), "duels: you're told your new rating")
    Duels:Refresh()
    check(card.rating:GetText() == "1216" and card.rank:GetText() == "Rank #1 of 2" and card.record:GetText() == "1 W  0 L  (100%)",
        "duels: your card")
    check(card.hist[1].text:GetText():find("Beat", 1, true) and card.hist[1].delta:GetText() == "+16", "duels: recent matches")
    local row1 = Duels.board.rows[1]
    check(row1.cells[2]:GetText() == "Jake" and row1.cells[3]:GetText() == "1216" and row1.cells[4]:GetText() == "1-0"
        and row1.cells[5]:GetText() == "100%" and row1.mine:IsShown(), "duels: leaderboard row")

    -- being challenged
    STUB.sent = {}
    STUB.Fire("CHAT_MSG_ADDON", "PogRaid", "D1" .. ns.Now() .. ":Raider03-1-1", "WHISPER", "Raider03-Realm")
    local pop = ns.DuelPopup.frame
    check(pop:IsShown() and pop.text:GetText():find("Raider03", 1, true) and pop.text:GetText():find("(1200)", 1, true),
        "duels: challenge pop-up with their rating")
    STUB.Fire("CHAT_MSG_ADDON", "PogRaid", "D1" .. ns.Now() .. ":Raider04-1-1", "WHISPER", "Raider04-Realm")
    check(STUB.sent[1].text == "D20Raider04-1-1" and STUB.sent[1].target == "Raider04", "duels: a second challenge is declined while busy")
    STUB.Script(pop.yes, "OnClick")
    check(STUB.sent[2].text == "D21Raider03-1-1" and Duels.agreed.challenger == "Raider03-Realm" and not pop:IsShown(), "duels: Accept agrees")
    STUB.printed = {}
    STUB.Fire("DUEL_REQUESTED", "Raider03")
    check(printedContains("this is your ranked duel"), "duels: the incoming duel is flagged as the ranked one")
    STUB.Fire("CHAT_MSG_SYSTEM", "Raider03 has fled from Jake in a duel")
    local r3 = store["Raider03-1-1:Jake-Realm"]
    check(r3 and r3.a == "Raider03-Realm" and r3.b == "Jake-Realm" and r3.winner == "Jake-Realm", "duels: the challenged side reports too")
    -- the other side says the opposite: doesn't count
    ns.Sync:Apply(ns.Sync.collections.duels, { id = "Raider03-1-1:Raider03-Realm", rev = ns.Now(), by = "Raider03-Realm",
        author = "Raider03-Realm", t = ns.Now(), match = "Raider03-1-1", a = "Raider03-Realm", b = "Jake-Realm", winner = "Raider03-Realm" })
    check(Duels:Table().players["Raider03-Realm"] == nil, "duels: disagreeing reports don't count")
    -- forged reports from someone who wasn't in the match
    check(not ns.Sync:Apply(ns.Sync.collections.duels, { id = "X:Raider09-Realm", rev = ns.Now(), by = "Raider09-Realm",
        author = "Raider09-Realm", t = ns.Now(), match = "X", a = "Raider05-Realm", b = "Raider06-Realm", winner = "Raider05-Realm" }),
        "duels: only the two players can report")
    -- decline + timeouts
    STUB.sent = {}
    STUB.Fire("CHAT_MSG_ADDON", "PogRaid", "D1" .. ns.Now() .. ":Raider05-1-1", "WHISPER", "Raider05-Realm")
    STUB.Script(pop.no, "OnClick")
    check(STUB.sent[1].text == "D20Raider05-1-1" and Duels.agreed == nil, "duels: Decline")
    STUB.printed = {}
    Duels:Challenge("Raider06")
    STUB.Advance(61)
    check(Duels.outgoing == nil and printedContains("didn't answer"), "duels: unanswered challenges time out")
    Duels.agreed = { id = "old", opp = "Raider07-Realm", challenger = "Jake-Realm", t = ns.Now(), expires = ns.Now() + 300 }
    STUB.Advance(301)
    check(not Duels:Busy(), "duels: agreements expire")

    -- Home: challenge from Online now
    local onlineEntries
    local realShow = ns.UI.ShowMenu
    ns.UI.ShowMenu = function(_, e) onlineEntries = e end
    SlashCmdList.POGRAID("home")
    for _, row in ipairs(ns.Home.onlineCard.rows) do
        if row.item and row.item ~= ns.Sync:Me() then STUB.Script(row, "OnClick", "LeftButton") break end
    end
    ns.UI.ShowMenu = realShow
    check(onlineEntries and onlineEntries[#onlineEntries].text == "Challenge to a ranked duel", "duels: challenge from Online now")
    SlashCmdList.POGRAID("games")
    Games:SetMode("sweeper")
    check(Games.board:IsShown() and not Games.duelsView:IsShown() and Games.levelButtons.expert:IsShown(), "duels: back to Sapper Sweeper")
    STUB.target = nil
    STUB.sent = {}
    Editor:ShowTab("boards")
end

-- Settings, minimap button, version check -------------------------------------------------
do
    local Settings, MB, Version = ns.Settings, ns.MinimapButton, ns.Version
    -- minimap button
    local b = MB.button
    check(b and b:IsShown() and b.icon.__texture:find("logo", 1, true), "minimap: gnome button on the minimap")
    local played = {}
    local realPlay = PlaySound
    PlaySound = function(id) table.insert(played, id) end
    STUB.Script(b, "OnClick", "LeftButton")
    check(Editor.frame:IsShown() and Editor.currentTab == "home", "minimap: left-click opens Pog Raid")
    STUB.Script(b, "OnClick", "LeftButton")
    check(not Editor.frame:IsShown(), "minimap: left-click again closes it")
    local menu
    local realShow = ns.UI.ShowMenu
    ns.UI.ShowMenu = function(_, e) menu = e end
    STUB.Script(b, "OnClick", "RightButton")
    ns.UI.ShowMenu = realShow
    check(menu[2].text == "Settings" and menu[3].text == "Hide minimap button", "minimap: right-click menu")
    STUB.printed = {}
    menu[3].func()
    check(not b:IsShown() and ns.db.settings.minimap.hide and printedContains("/pog minimap"), "minimap: hide, and how to bring it back")
    SlashCmdList.POGRAID("minimap")
    check(b:IsShown() and not ns.db.settings.minimap.hide, "minimap: /pog minimap brings it back")
    -- dragging moves it around the ring
    local mx, my = Minimap:GetCenter()
    STUB.cursorX, STUB.cursorY = mx + 50, my
    STUB.Script(b, "OnDragStart")
    STUB.Script(b, "OnUpdate")
    STUB.Script(b, "OnDragStop")
    check(math.abs(ns.db.settings.minimap.angle - 0) < 0.01 and b.__scripts.OnUpdate == nil, "minimap: drag sets the angle")
    local bx, by = b:GetCenter()
    check(math.abs(bx - (mx + 75)) < 0.01 and math.abs(by - my) < 0.01, "minimap: button sits on the ring")
    PogRaid_OnAddonCompartmentClick()
    check(Editor.frame:IsShown(), "minimap: also in Blizzard's AddOns menu")

    -- settings tab
    SlashCmdList.POGRAID("settings")
    check(Editor.currentTab == "settings" and Settings.page:IsShown(), "settings: /pog settings opens the tab")
    local checks = Settings.checks
    check(checks[1].checked and checks[2].checked and checks[3].checked and checks[4].checked, "settings: everything on by default")
    STUB.Script(checks[1], "OnClick")
    check(not b:IsShown() and not checks[1].checked, "settings: minimap checkbox hides the button")
    STUB.Script(checks[1], "OnClick")
    check(b:IsShown(), "settings: and shows it again")
    -- sounds
    played = {}
    ns.Sound("RAID_WARNING")
    STUB.Script(checks[2], "OnClick")
    ns.Sound("RAID_WARNING")
    local warnings = 0
    for _, id in ipairs(played) do if id == SOUNDKIT.RAID_WARNING then warnings = warnings + 1 end end
    check(warnings == 1 and ns.db.settings.sounds == false, "settings: sounds can be turned off")
    STUB.Script(checks[2], "OnClick")
    PlaySound = realPlay
    -- join pop-ups off: a chat note instead
    STUB.Script(checks[3], "OnClick")
    STUB.party = nil
    ns.Social:PostGroup("Wailing Caverns", "healer")
    STUB.printed = {}
    STUB.Fire("CHAT_MSG_ADDON", "PogRaid", "J" .. ns.Social:MyGroup().id, "WHISPER", "Raider07-Realm")
    check(printedContains("wants to join your group") and not (ns.JoinPopup.frame and ns.JoinPopup.frame:IsShown() and #ns.JoinPopup.queue > 0),
        "settings: join requests as a chat note when pop-ups are off")
    STUB.Script(checks[3], "OnClick")
    ns.Social:Remove("lfg", ns.Social:MyGroup())
    wipe(ns.Social.requests)
    -- duel challenges off: declined automatically
    STUB.Script(checks[4], "OnClick")
    STUB.sent = {}
    STUB.Fire("CHAT_MSG_ADDON", "PogRaid", "D1" .. ns.Now() .. ":Raider08-1-1", "WHISPER", "Raider08-Realm")
    check(STUB.sent[1] and STUB.sent[1].text == "D20Raider08-1-1", "settings: duel challenges declined when turned off")
    STUB.Script(checks[4], "OnClick")

    -- officer ranks: default is the top two ranks
    local ranks = Settings.officers.ranks
    check(ranks[1].label:GetText() == "Guild Master" and ranks[1].checked and ranks[2].checked and not ranks[3].checked,
        "officers: guild master and the next rank by default")
    check(not ranks[1].enabled, "officers: the guild master's rank can't be unticked")
    check(not ns.Sync:IsOfficer("Raider03-Realm"), "officers: raiders aren't officers by default")
    STUB.Script(ranks[3], "OnClick")
    check(ns.Sync:IsOfficer("Raider03-Realm") and ns.Sync:Store("config").officers.ranks == "0,1,2", "officers: an officer adds a rank")
    STUB.Script(ranks[3], "OnClick")
    check(not ns.Sync:IsOfficer("Raider03-Realm"), "officers: and removes it")
    check(not ns.Sync:Apply(ns.Sync.collections.config, { id = "officers", rev = ns.Now() + 99, by = "Raider03-Realm",
        author = "Raider03-Realm", t = ns.Now(), ranks = "0,1,2,3" }), "officers: a non-officer can't change them")
    -- forged records (0.16.1): any guildie's addon can relay a record claiming any "by"
    local G = ns.db.guild
    check(G.fullScan and not ns.Sync:IsOfficer("Madeup-Realm"), "officers: once the whole roster is read, a made-up name is no officer")
    check(not ns.Sync:Apply(ns.Sync.collections.config, { id = "officers", rev = ns.Now() + 99, by = "Madeup-Realm",
        author = "Madeup-Realm", t = ns.Now(), ranks = "0,1,2,3,4" }), "officers: so a made-up officer can't hand out officer ranks")
    G.fullScan = nil
    check(ns.Sync:IsOfficer("Madeup-Realm"), "officers: before the roster is read, unknown names get the benefit of the doubt")
    G.fullScan = true
    local r02 = G.players["Raider02-Realm"]
    local r02In, r02Rank = r02.inGuild, r02.rankIndex
    r02.inGuild, r02.rankIndex = false, 1
    check(not ns.Sync:IsOfficer("Raider02-Realm"), "officers: an officer who left the guild is no officer")
    r02.inGuild = true
    check(ns.Sync:IsOfficer("Raider02-Realm"), "officers: (an officer in the guild is one)")
    r02.inGuild, r02.rankIndex = r02In, r02Rank
    local function post(rev, t)
        return { id = "future-post", rev = rev, t = t or ns.Now(), by = "Jake-Realm", author = "Jake-Realm", title = "Hi", body = "" }
    end
    check(not ns.Sync:Apply(ns.Sync.collections.posts, post(ns.Now() + 3600)), "sync: a record stamped in the future is refused (it could never be replaced)")
    check(not ns.Sync:Apply(ns.Sync.collections.posts, post(ns.Now(), ns.Now() + 3600)), "sync: so is one created in the future")
    check(ns.Sync:Apply(ns.Sync.collections.posts, post(ns.Now() + 60)), "sync: a minute of clock difference is fine")
    local gone = post(ns.Now() + 61)
    gone.deleted = true
    check(ns.Sync:Apply(ns.Sync.collections.posts, gone) and ns.Sync:Store("posts")["future-post"].deleted, "sync: (and it can be deleted)")
    -- a member sees the list but can't change it
    local myP = ns.db.guild.players["Jake-Realm"]
    local realRank = myP.rankIndex
    myP.rankIndex = 3
    Settings:Refresh()
    check(not ranks[2].enabled and Settings.officers.note == nil, "officers: read-only for members, no explanation line")
    myP.rankIndex = realRank
    Settings:Refresh()

    -- version check
    STUB.sent, STUB.printed = {}, {}
    Version:Announce()
    check(#STUB.sent == 1 and STUB.sent[1].text == "V" .. ns.VERSION and STUB.sent[1].channel == "GUILD", "version: one tiny guild message")
    STUB.sent = {}
    STUB.Fire("CHAT_MSG_ADDON", "PogRaid", "V0.9.0", "GUILD", "Raider02-Realm")
    check(#STUB.sent == 1 and STUB.sent[1].text == "W" .. ns.VERSION and STUB.sent[1].target == "Raider02", "version: one whispered reply")
    STUB.Fire("CHAT_MSG_ADDON", "PogRaid", "V0.9.0", "GUILD", "Raider02-Realm")
    check(#STUB.sent == 1, "version: doesn't answer the same person twice in a row")
    STUB.Advance(601)
    STUB.sent = {}
    STUB.Fire("CHAT_MSG_ADDON", "PogRaid", "V0.9.0", "GUILD", "Raider02-Realm")
    check(#STUB.sent == 1, "version: answers again after a relog (10 minutes later)")
    STUB.Fire("CHAT_MSG_ADDON", "PogRaid", "W99.0.0", "WHISPER", "Raider03-Realm")
    STUB.Fire("CHAT_MSG_ADDON", "PogRaid", "Wgarbage", "WHISPER", "Raider04-Realm")
    check(printedContains("newer Pog Guild Tools (99.0.0)") and Version.seen["Raider04-Realm"] == nil, "version: newer version noticed, junk ignored")
    STUB.printed = {}
    STUB.Fire("CHAT_MSG_ADDON", "PogRaid", "W99.1.0", "WHISPER", "Raider05-Realm")
    check(not printedContains("newer Pog Raid"), "version: the update note shows once")
    ns.Sync:OnPayload("S0000abcd:3:0.8.0", "Raider06-Realm")
    check(Version.seen["Raider06-Realm"] == "0.8.0", "version: picked up from the sync check-in for free")
    check(Version.Compare("0.10.0", "0.9.0") == 1 and Version.Compare("1.2.3", "1.2.3") == 0 and Version.Compare("x", "1.0.0") == nil,
        "version: compares numbers, not text")
    Settings:Refresh()
    local who = Settings.who
    local found, colour = {}, {}
    for _, row in ipairs(who.rows) do
        if row:IsShown() then found[row.name:GetText()], colour[row.name:GetText()] = row.version:GetText(), row.version.__textColor end
    end
    -- 0.16: an old version is a quieter colour, not "(update)"
    check(found["Raider02"] == "0.9.0" and found["Raider05"] == "99.1.0" and colour["Raider02"][2] < colour["Raider05"][2],
        "version: who has it, old versions in a quieter colour")
    check(who.mine:GetText() == "You: " .. ns.VERSION, "version: your own version shown")
    STUB.sent = {}
    Editor:ShowTab("boards")
end

-- Gem Cutter --------------------------------------------------------------------------------
do
    local Gems, Games = ns.Gems, ns.Games
    local function line(t) return table.concat(t, ",") end
    local out, gained, moved = Gems.SlideLine({ 1, 1, 1, 1 })
    check(line(out) == "2,2,0,0" and gained == 8 and moved, "gems: four in a row make two")
    out, gained = Gems.SlideLine({ 1, 0, 1, 2 })
    check(line(out) == "2,2,0,0" and gained == 4, "gems: a new merge doesn't merge again in the same move")
    out = Gems.SlideLine({ 3, 3, 3, 0 })
    check(line(out) == "4,3,0,0", "gems: three alike merge the first pair")
    out, gained, moved = Gems.SlideLine({ 1, 2, 3, 4 })
    check(not moved and gained == 0, "gems: nothing to slide, no move")
    local b = Gems.Board.New({ 1, 0, 0, 1,  0, 0, 0, 0,  0, 0, 0, 0,  2, 0, 0, 0 })
    check(b:Move("right") and b.cells[4] == 2 and b.cells[16] == 2 and b.score == 4, "gems: slide right")
    check(b:Move("up") and b.cells[4] == 3 and b.cells[16] == 0 and b.score == 12, "gems: slide up merges down the column")
    check(not b:Move("up"), "gems: no change, no move")
    local full = Gems.Board.New({ 1, 2, 1, 2,  2, 1, 2, 1,  1, 2, 1, 2,  2, 1, 2, 1 })
    check(not full:CanMove() and full:Spawn() == nil, "gems: full board with no pairs is game over")
    local e = Gems.Board.New()
    local i = e:Spawn()
    check(i and (e.cells[i] == 1 or e.cells[i] == 2), "gems: new gems are Rough Stone or Malachite")
    check(Gems.Name(11) == "Large Opal" and Gems.Name(15) == "Black Diamond", "gems: gem names")

    -- the page
    SlashCmdList.POGRAID("gems")
    check(Games.mode == "gems" and Games.views.gems:IsShown() and not Games.board:IsShown() and Games.modeTabs.gems.selected,
        "gems: /pog gems opens Gem Cutter")
    local filled = 0
    for _, v in ipairs(Gems.board.cells) do if v > 0 then filled = filled + 1 end end
    check(filled == 2 and Gems.side.score.value:GetText() == "0", "gems: a new game starts with two gems")
    -- keyboard only while hovering the board
    local bf = Gems.boardFrame
    check(not bf.__keyboard, "gems: keys aren't captured until you hover the board")
    STUB.Script(bf, "OnEnter")
    Gems.board = Gems.Board.New({ 1, 1, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0 })
    STUB.Script(bf, "OnKeyDown", "LEFT")
    check(bf.__keyboard and Gems.board.cells[1] == 2 and Gems.board.score == 4 and bf.__propagate == false, "gems: arrow keys play")
    STUB.Script(bf, "OnKeyDown", "ENTER")
    check(bf.__propagate == true, "gems: other keys pass through to the game")
    STUB.Script(bf, "OnLeave")
    check(bf.__keyboard == false, "gems: keys released when the mouse leaves")
    -- a pull with the mouse over the board: combat starting gives the keys back
    STUB.Script(bf, "OnEnter")
    STUB.Script(bf, "OnKeyDown", "LEFT")
    check(bf.__keyboard and bf.__propagate == false, "gems: (hovering, after an arrow key)")
    STUB.blocked = nil
    STUB.Fire("PLAYER_REGEN_DISABLED")
    STUB.combat = true
    local okKey = pcall(STUB.Script, bf, "OnKeyDown", "1")
    local okLeave = pcall(STUB.Script, bf, "OnLeave")
    local okEnter = pcall(STUB.Script, bf, "OnEnter")
    check(bf.__keyboard == false and bf.__propagate == true and okKey and okLeave and okEnter and not STUB.blocked,
        "gems: combat starting gives every key back to the game, and the board stays out of it")
    STUB.combat = false
    STUB.Fire("PLAYER_REGEN_ENABLED")
    -- drag
    local before = Gems.board.score
    Gems.board = Gems.Board.New({ 0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 1, 1 })
    STUB.cursorX, STUB.cursorY = 300, 300
    STUB.Script(bf, "OnMouseDown")
    STUB.cursorX = 380
    STUB.Script(bf, "OnMouseUp")
    check(Gems.board.cells[16] == 2, "gems: dragging right slides right")
    -- tiles show the gem
    Gems:Refresh()
    check(Gems.tiles[16].name:GetText() == "Malachite" and Gems.tiles[16].icon:IsShown(), "gems: tiles show the gem and its name")
    -- the Large Opal moment and game over
    Gems.board = Gems.Board.New({ 10, 10, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0 })
    Gems.over, Gems.announcedWin = nil, nil
    Gems:Move("left")
    check(Gems.board.cells[1] == 11 and Gems.side.message:GetText():find("Large Opal", 1, true), "gems: cutting a Large Opal is celebrated")
    -- after this move no gem that drops in can match a neighbour, so it's truly stuck
    Gems.board = Gems.Board.New({ 3, 4, 3, 4,  4, 3, 4, 3,  3, 4, 3, 4,  5, 6, 7, 7 })
    Gems.over = nil
    Gems:Move("right")
    check(Gems.over and Gems.side.message:GetText():find("No moves left", 1, true), "gems: game over when no moves remain")
    -- best score kept, shared, shown
    local rec = ns.Sync:Store("gems")["Jake-Realm"]
    check(rec and rec.best >= 2048 and rec.tier >= 11 and ns.db.games.gems.best == rec.best, "gems: best score shared with the guild")
    ns.Sync:Apply(ns.Sync.collections.gems, { id = "Raider02-Realm", rev = ns.Now(), by = "Raider02-Realm", author = "Raider02-Realm",
        t = ns.Now(), best = 99999, tier = 13 })
    check(not ns.Sync:Apply(ns.Sync.collections.gems, { id = "Raider03-Realm", rev = ns.Now(), by = "Raider04-Realm",
        author = "Raider03-Realm", t = ns.Now(), best = 5, tier = 1 }), "gems: nobody posts a score for someone else")
    Gems:Refresh()
    local rows = Gems.side.rows
    check(rows[1].name:GetText() == "Raider02" and rows[1].score:GetText() == "99999" and rows[2].mine:IsShown(), "gems: guild leaderboard")
    -- a game in progress survives a reload
    Gems:NewGame()
    Gems.board.cells[5] = 7
    Gems:Save()
    Gems.board = nil
    Gems:Load()
    check(Gems.board.cells[5] == 7, "gems: game restored after a reload")
end

-- Wowdle --------------------------------------------------------------------------------------
do
    local W, Games = ns.Wowdle, ns.Games
    check(W.Score("TOTEM", "TOTEM") == "ggggg", "wowdle: all green")
    check(W.Score("MOTTO", "TOTEM") == "yggyx", "wowdle: repeated letters scored like the original")
    check(W.Score("EEEEE", "TOTEM") == "xxxgx", "wowdle: a letter counts only as often as it appears")
    local bad = {}
    for _, word in ipairs(W.WORDS) do if #word ~= 5 or word:find("[^A-Z]") then bad[#bad + 1] = word end end
    check(#bad == 0 and #W.WORDS >= 100, "wowdle: every word is five letters")
    local day = W:Day()
    check(W:Word(day) == W:Word(day) and W:Word(day) ~= W:Word(day + 1), "wowdle: one word per day, different tomorrow")
    -- daily reset moves the day boundary
    local realReset = C_DateAndTime
    C_DateAndTime = { GetSecondsUntilDailyReset = function() return 3600 end }
    local dayWithReset = W:Day()
    C_DateAndTime = realReset
    check(type(dayWithReset) == "number", "wowdle: day follows the daily reset when the game knows it")

    local wl = STUB.rect(Games.modeTabs.wowdle)
    local gpl = STUB.rect(Games.page)
    local sl = STUB.rect(Games.modeTabs.sweeper)
    local _, _, ww = STUB.rect(Games.modeTabs.wowdle)
    check(Games.MODES[1].key == "wowdle" and near(wl - gpl, 12) and near(sl, wl + ww + ns.UI.SUBTAB_GAP)
        and Games.modeTabs.wowdle.glow ~= nil, "games: Wowdle is the first game tab, talent-window tabs")
    local savedMode = ns.db.games.mode
    ns.db.games.mode = nil
    Games:SetMode(nil)
    check(Games.mode == "wowdle", "games: opens on Wowdle when no game was picked")
    ns.db.games.mode = savedMode
    ns.Editor:ShowTab("home") -- (/pog wowdle toggles: from another tab it opens Wowdle)
    SlashCmdList.POGRAID("wowdle")
    check(Games.mode == "wowdle" and Games.views.wowdle:IsShown() and W.input.__focus, "wowdle: /pog wowdle opens it, ready to type")
    local answer = W:Word(W:Current().day)
    -- typing
    W.input:SetText("to1tx")
    STUB.Script(W.input, "OnTextChanged", true)
    check(W.typed == "TOTX" and W.tiles[1][3].letter:GetText() == "T", "wowdle: typing fills the row, letters only")
    STUB.Script(W.delKey, "OnClick")
    check(W.typed == "TOT", "wowdle: delete key")
    STUB.Script(W.enterKey, "OnClick")
    check(#W:Current().guesses == 0 and W.status:GetText():find(#answer .. " letters, please", 1, true), "wowdle: short guesses refused")
    -- two wrong guesses then the answer
    local wrong = answer == "QQQQQ" and "ZZZZZ" or "QQQQQ"
    for _, g in ipairs({ wrong, wrong }) do
        W.typed = ""
        for k = 1, 5 do STUB.Script(W.keys[g:sub(k, k)], "OnClick") end
        STUB.Script(W.enterKey, "OnClick")
    end
    check(#W:Current().guesses == 2 and W.tiles[1][1].letter:GetText() == "Q", "wowdle: guesses go in row by row")
    local out, open = W.KEY_OUT, W.KEY_OPEN
    local qIn = answer:find("Q", 1, true)
    local q, m = W.keys.Q, W.keys.M
    if not qIn then
        check(q.bg.__color[1] == out.fill[1] and q.label.__alpha == out.alpha and q.edges[1].__color[1] == out.edge[1],
            "wowdle: a letter ruled out sinks away (dark, faint)")
    end
    if not answer:find("M", 1, true) then
        check(m.bg.__color[1] == open.fill[1] and (m.label.__alpha or 1) == 1 and m.edges[1].__color[1] == open.edge[1]
            and open.fill[1] > out.fill[1] + 0.2, "wowdle: a letter not tried yet stands out")
    end
    W.input:SetText(answer:lower())
    STUB.Script(W.input, "OnTextChanged", true)
    STUB.Script(W.input, "OnEnterPressed")
    check(W:State() == "won" and W.status:GetText():find("Solved in 3", 1, true) and not W.input.__focus, "wowdle: solved in three")
    check(ns.db.games.wowdle.history[W:Current().day] == 3, "wowdle: result saved")
    local rec = ns.Sync:Store("wowdle")["Jake-Realm:" .. W:Current().day]
    check(rec and rec.n == 3 and rec.pat == W:Pattern() and not rec.pat:find("[A-Z]"), "wowdle: result shared, colours only")
    check(W:Guess("ABCDE") == "done", "wowdle: no more guesses after solving")
    -- today in the guild
    ns.Sync:Apply(ns.Sync.collections.wowdle, { id = "Raider02-Realm:" .. W:Current().day, rev = ns.Now(), by = "Raider02-Realm",
        author = "Raider02-Realm", t = ns.Now(), day = W:Current().day, n = 2, pat = "xygxx,ggggg" })
    ns.Sync:Apply(ns.Sync.collections.wowdle, { id = "Raider03-Realm:" .. W:Current().day, rev = ns.Now(), by = "Raider03-Realm",
        author = "Raider03-Realm", t = ns.Now(), day = W:Current().day, n = 7, pat = "xxxxx,xxxxx,xxxxx,xxxxx,xxxxx,xxxxx" })
    check(not ns.Sync:Apply(ns.Sync.collections.wowdle, { id = "Raider04-Realm:" .. W:Current().day, rev = ns.Now(),
        by = "Raider04-Realm", author = "Raider04-Realm", t = ns.Now(), day = W:Current().day, n = 3, pat = "TOTEM" }),
        "wowdle: shared results can't carry letters")
    W:Refresh()
    local rows = W.side.rows
    check(rows[1].name:GetText() == "Raider02" and rows[1].score:GetText() == "2/6" and rows[2].mine:IsShown()
        and rows[3].score:GetText() == "X/6", "wowdle: today in the guild, best first")
    STUB.Script(rows[1], "OnEnter")
    check(#GameTooltip.lines == 3 and GameTooltip.lines[2]:find("WHITE8X8", 1, true), "wowdle: hover shows their squares")
    -- stats and share
    local st = W:Stats()
    check(st.played >= 1 and st.wins >= 1 and st.streak == 1 and st.dist[3] >= 1, "wowdle: stats")
    local share = W:ShareText()
    check(share:find("Wowdle #" .. W:Number(W:Current().day) .. "  3/6", 1, true) and select(2, share:gsub("\n", "")) == 3,
        "wowdle: copy result with squares")
    local opened
    local realOpen = ChatFrame_OpenChat
    ChatFrame_OpenChat = function(text) opened = text end
    STUB.Script(W.side.post, "OnClick")
    ChatFrame_OpenChat = realOpen
    check(opened == "/g Wowdle #" .. W:Number(W:Current().day) .. "  3/6", "wowdle: Post to guild puts the score in the chat box, no squares")
    -- a new day, a new word; a streak builds
    STUB.now = STUB.now + 86400
    check(#W:Current().guesses == 0 and W:State() == "playing", "wowdle: fresh board the next day")
    for _ = 1, 6 do W:Guess(W:Word(W:Current().day) == "ZZZZZ" and "QQQQQ" or "ZZZZZ") end
    W:Refresh()
    check(W:State() == "lost" and W.status:GetText():find(W:Word(W:Current().day), 1, true), "wowdle: a miss shows the word")
    check(W:Stats().streak == 0, "wowdle: a miss ends the streak")
    local h = ns.db.games.wowdle.history
    h[W:Day() + 1], h[W:Day() + 2] = 2, 4
    STUB.now = STUB.now + 2 * 86400
    check(W:Stats().streak == 2 and W:Stats().best >= 2, "wowdle: streak and best streak")
    STUB.now = STUB.now - 3 * 86400

    -- the longer word list starts on LIST2_DAY; earlier days keep the words people played
    check(#W:Word(W.LIST2_DAY - 1) == 5 and W:Word(W.LIST2_DAY - 1) == W.WORDS[((W.LIST2_DAY - 1) * 53) % #W.WORDS + 1],
        "wowdle: days before the change keep the old word")
    local lens, plurals = {}, {}
    local names = { IGNIS = true, ARGUS = true, ARTHAS = true, XAVIUS = true, DEFIAS = true, GILNEAS = true, TANARIS = true,
        FERALAS = true, RAGNAROS = true, SYLVANAS = true, SILITHUS = true, SUCCUBUS = true }
    for _, word in ipairs(W.WORDS2) do
        lens[#word] = (lens[#word] or 0) + 1
        if word:sub(-1) == "S" and not names[word] then plurals[#plurals + 1] = word end
        if word:find("[^A-Z]") then plurals[#plurals + 1] = word end
    end
    check(lens[5] and lens[6] and lens[7] and lens[8] and not lens[4] and not lens[9], "wowdle: words are 5 to 8 letters")
    check(#plurals == 0, "wowdle: no plurals in the new list (" .. table.concat(plurals, ",") .. ")")
    check(#W.WORDS2 % 53 ~= 0, "wowdle: every word gets its turn (list size isn't a multiple of 53)")
    local seen, day0 = {}, W.LIST2_DAY
    for d = day0, day0 + #W.WORDS2 - 1 do seen[W:Word(d)] = true end
    check(ns.Count(seen) == #W.WORDS2, "wowdle: the new list cycles through every word before repeating")
    -- play a day with an eight-letter word
    local longDay
    for d = day0, day0 + 400 do if #W:Word(d) == 8 then longDay = d break end end
    local saveNow = STUB.now
    STUB.now = longDay * 86400 - 1790000000 + 3600
    Games:SetMode("wowdle")
    local word8 = W:Word(W:Current().day)
    check(#word8 == 8 and W:Length() == 8, "wowdle: an eight-letter day")
    W:Refresh()
    local gl, _, gw = STUB.rect(W.grid)
    local vl = STUB.rect(W.view)
    check(W.tiles[1][8]:IsShown() and gw <= 400 and near(gl - vl, 12 + (400 - gw) / 2), "wowdle: eight tiles fit, centred")
    check(W.status:GetText():find("8 letters", 1, true), "wowdle: the line under the keyboard says how long the word is")
    local _, st, _, sh = STUB.rect(W.status)
    local _, vt = STUB.rect(W.view)
    check(vt - st > 64, "wowdle: that line sits below the game tabs, not over them")
    W.input:SetText("abcdefghij")
    STUB.Script(W.input, "OnTextChanged", true)
    check(W.typed == "ABCDEFGH", "wowdle: typing stops at the word's length")
    check(W:Guess("ABCDE") == "8 letters, please", "wowdle: guesses must match the word's length")
    W.typed = word8
    W:Submit()
    local rec8 = ns.Sync:Store("wowdle")["Jake-Realm:" .. W:Current().day]
    check(W:State() == "won" and rec8 and rec8.pat == "gggggggg", "wowdle: eight-letter solve shared")
    STUB.now = saveNow
    W.layoutLen = nil
    Games:SetMode("wowdle")
    W.input:SetFocus()
    Games:SetMode("sweeper")
    check(not W.input.__focus, "wowdle: switching away gives the keyboard back")
    Games:SetMode("wowdle")
    W.input:SetFocus()
    STUB.Fire("PLAYER_REGEN_DISABLED")
    check(not W.input.__focus and W.view:IsShown(), "wowdle: combat starting gives the keyboard back (keys cast, not type)")
    STUB.Fire("PLAYER_REGEN_ENABLED")
    Editor:ShowTab("boards")
end

-- Crafting: professions, recipes, search, directory -------------------------------------
do
    local C = ns.Crafting
    local NAMES = { [16665] = "Arcanite Reaper", [20201] = "Arcanite Rod", [30000] = "Reaper Blade",
        [9999] = "Unlearned Thing", [18000] = "Dense Sharpening Stone" }
    local slots = { 1, nil, nil, nil, 2 }
    local info = { { "Blacksmithing", 1, 285, 300, 0, 0, 164 }, { "Cooking", 2, 150, 225, 0, 0, 185 } }
    GetProfessions = function() return slots[1], slots[2], slots[3], slots[4], slots[5] end
    GetProfessionInfo = function(i) return unpack(info[i]) end
    C_Spell = { GetSpellName = function(id) return NAMES[id] end }
    local linked = false
    local known = { 16665, 9999, 20201 }
    C_TradeSkillUI = {
        IsTradeSkillLinked = function() return linked end,
        IsTradeSkillGuild = function() return false end,
        IsNPCCrafting = function() return false end,
        IsTradeSkillReady = function() return true end,
        GetBaseProfessionInfo = function() return { professionName = "Blacksmithing", skillLevel = 285 } end,
        GetAllRecipeIDs = function() return known end,
        GetRecipeInfo = function(id) return NAMES[id] and { name = NAMES[id], learned = id ~= 9999 } end,
    }

    check(C.Unpack(C.Pack({ 1, 64, 16665, 2 ^ 24 - 1 }))[4] == 2 ^ 24 - 1 and #C.Pack({ 1, 2 }) == 8, "crafting: recipe IDs pack four digits each")
    check(C.ReadProfessions and #C:ReadProfessions() == 2 and C:ReadProfessions()[1].name == "Blacksmithing", "crafting: reads the profession slots")

    STUB.Fire("TRADE_SKILL_SHOW")
    STUB.Advance(3)
    local rec = ns.Sync:Store("recipes")["Jake-Realm:Blacksmithing"]
    check(rec and rec.ids == C.Pack({ 16665, 20201 }), "crafting: own learned recipes shared when the window opens")
    local profs = ns.Sync:Store("profs")["Jake-Realm"]
    check(profs and profs.list == "Blacksmithing:285:300|Cooking:150:225", "crafting: professions and skill shared")

    -- someone else's linked list is never taken as ours
    linked = true
    known = { 16665, 20201, 30000 }
    STUB.Fire("TRADE_SKILL_LIST_UPDATE")
    STUB.Advance(3)
    check(ns.Sync:Store("recipes")["Jake-Realm:Blacksmithing"].ids == C.Pack({ 16665, 20201 }), "crafting: a linked profession isn't read")
    linked = false

    -- a guildie's records arrive through sync
    local now = ns.Now()
    ns.Sync:Apply(ns.Sync.collections.profs, { id = "Raider03-Realm", rev = now, by = "Raider03-Realm", author = "Raider03-Realm",
        t = now, list = "Blacksmithing:300:300|Mining:300:300" })
    ns.Sync:Apply(ns.Sync.collections.recipes, { id = "Raider03-Realm:Blacksmithing", rev = now, by = "Raider03-Realm",
        author = "Raider03-Realm", t = now, prof = "Blacksmithing", ids = C.Pack({ 16665, 30000, 18000 }) })
    check(not ns.Sync:Apply(ns.Sync.collections.recipes, { id = "Raider04-Realm:Blacksmithing", rev = now, by = "Raider05-Realm",
        author = "Raider04-Realm", t = now, prof = "Blacksmithing", ids = C.Pack({ 1 }) }), "crafting: nobody shares recipes for someone else")
    check(not ns.Sync:Apply(ns.Sync.collections.recipes, { id = "Raider04-Realm:Blacksmithing", rev = now, by = "Raider04-Realm",
        author = "Raider04-Realm", t = now, prof = "Blacksmithing", ids = "ABC" }), "crafting: malformed recipe lists rejected")

    -- Raider03 is online; count ourselves offline so the ordering is tested
    local meOnline = ns.Roster.online["Jake-Realm"]
    ns.Roster.online["Jake-Realm"] = nil
    local hits = C:Search("arcanite")
    check(#hits == 2 and hits[1].name == "Arcanite Reaper" and #hits[1].crafters == 2, "crafting: search finds a recipe and its crafters")
    check(hits[1].crafters[1].name == "Raider03-Realm", "crafting: online crafters listed first")
    hits = C:Search("reaper")
    check(#hits == 2 and hits[1].name == "Reaper Blade" and hits[2].name == "Arcanite Reaper", "crafting: names starting with the search come first")
    check(#C:Search("  ") == 0 and #C:Search("nothing like this") == 0, "crafting: empty and unmatched searches")
    local dir = C:Directory()
    check(#dir.Blacksmithing == 2 and dir.Blacksmithing[1].name == "Raider03-Realm" and dir.Blacksmithing[1].recipes == 3,
        "crafting: directory lists members, online first, with recipe counts")
    check(dir.Mining and #dir.Mining == 1 and dir.Cooking and #dir.Cooking == 1, "crafting: every profession has its members")

    -- the page
    SlashCmdList.POGRAID("crafting")
    local left, right = C.left, C.right
    check(C.page and C.page:IsShown() and left.rows[1].name:GetText() == "Blacksmithing", "crafting: tab opens with the professions list")
    check(right.status:GetText() == "open your cooking window once to share recipes!",
        "crafting: a nudge to share the other profession")
    STUB.Script(left.rows[1], "OnClick")
    check(C.selected == "Blacksmithing" and right.rows[1]:IsShown() and right.rows[1].name:GetText() == "Raider03"
        and right.rows[1].right:GetText():find("300 / 300", 1, true) ~= nil, "crafting: picking a profession shows its members")
    -- a member's recipe book: click, scroll, filter, back
    local raider = right.rows[1]
    STUB.Script(raider, "OnClick", "RightButton")
    check(C.member == nil, "crafting: right-clicking a member doesn't open their recipes")
    STUB.Script(raider, "OnClick", "LeftButton")
    check(C.member == "Raider03-Realm" and right.back:IsShown() and right.count == nil
        and right.rows[1].name:GetText() == "Arcanite Reaper" and right.rows[2].name:GetText() == "Dense Sharpening Stone"
        and right.rows[3].name:GetText() == "Reaper Blade" and not right.rows[4]:IsShown(), "crafting: clicking a member lists all their recipes")
    check(right.title:GetText():find("Raider03", 1, true) ~= nil and C.searchBox.placeholder:GetText() == "Search Raider03's Blacksmithing recipes",
        "crafting: title and search box say whose recipes these are")
    C.searchBox:SetText("reaper")
    STUB.Script(C.searchBox, "OnTextChanged")
    check(C.member and right.rows[1].name:GetText() == "Arcanite Reaper" and not right.rows[3]:IsShown()
        and right.rows[2].name:GetText() == "Reaper Blade", "crafting: search filters the member's recipes")
    STUB.Script(right.back, "OnClick")
    check(C.member == nil and not right.back:IsShown() and right.rows[1].kind == "member" and C.searchBox:GetText() == "",
        "crafting: Back returns to the members")
    STUB.Script(left.rows[1], "OnClick") -- Blacksmithing off
    for _, row in ipairs(left.rows) do
        if row.item == "Cooking" then
            check(row.icon.__texture == "Interface\\Icons\\INV_Misc_Food_15", "crafting: Cooking has its icon")
            STUB.Script(row, "OnClick")
        end
    end
    STUB.Script(right.rows[1], "OnClick", "LeftButton")
    check(C.member == "Jake-Realm" and right.empty:IsShown() and right.empty:GetText():find("hasn't shared their Cooking recipes", 1, true) ~= nil,
        "crafting: a member who hasn't shared gets a clear note")
    STUB.Script(left.rows[1], "OnClick")
    check(C.member == nil and C.selected == "Blacksmithing", "crafting: picking a profession leaves the recipe book")
    slots = { 1, nil, nil, 3, 2 }
    info[3] = { "Fishing", 3, 75, 150, 0, 0, 356 }
    check(not C:StatusText():lower():find("fishing", 1, true), "crafting: no nudge to open a Fishing window")
    slots = { 1, nil, nil, nil, 2 }

    C.searchBox:SetText("arcanite")
    STUB.Script(C.searchBox, "OnTextChanged")
    check(right.rows[1].kind == "recipe" and right.rows[1].name:GetText() == "Arcanite Reaper" and right.rows[2].name:GetText() == "Arcanite Rod"
        and not right.rows[3]:IsShown(), "crafting: typing shows matching recipes")
    check(right.rows[1].right:GetText() == "Raider03, Jake", "crafting: recipe rows name the crafters, online first, no counts")
    check(left.rows[1].right == nil, "crafting: profession tiles don't count crafters")
    -- tiles: two to a row, the profession's icon on each
    local l1, t1_, w1 = STUB.rect(left.rows[1])
    local l2, t2_ = STUB.rect(left.rows[2])
    local l3, t3_ = STUB.rect(left.rows[3])
    local cl = STUB.rect(left)
    check(left.rows[1].icon.__texture == 136241 and near(l1, cl + 12) and near(l2, l1 + w1 + 8) and near(t2_, t1_)
        and near(l3, l1) and near(t1_ - t3_, 92 + 8), "crafting: professions as icon tiles, two to a row")
    STUB.Script(right.rows[1], "OnEnter")
    local tip = table.concat(GameTooltip.lines, "\n")
    check(tip:find("Raider03", 1, true) and tip:find("Blacksmithing", 1, true), "crafting: hover lists crafters and professions")
    C.searchBox:SetText("")
    STUB.Script(C.searchBox, "OnTextChanged")

    -- dropping a profession withdraws its recipes
    slots = { 2 }
    info[2] = { "Cooking", 2, 150, 225, 0, 0, 185 }
    C:PublishProfessions()
    check(ns.Sync:Store("recipes")["Jake-Realm:Blacksmithing"].deleted and ns.Sync:Store("profs")["Jake-Realm"].list == "Cooking:150:225",
        "crafting: a dropped profession's recipes are withdrawn")
    check(#C:Search("arcanite rod") == 0, "crafting: and no longer found")
    -- no professions at all: shared as an empty list, which everyone accepts
    slots = {}
    C:PublishProfessions()
    local empty = ns.Sync:Store("profs")["Jake-Realm"]
    check(empty.list == nil and ns.Sync.collections.profs.valid(empty), "crafting: no professions shares an empty list others accept")
    -- a client that can't read professions never wipes what was shared
    ns.Roster.online["Jake-Realm"] = meOnline
    GetProfessions, GetProfessionInfo, C_TradeSkillUI, C_Spell = nil, nil, nil, nil
    ns.Sync:Write("profs", { id = "Jake-Realm", author = "Jake-Realm", t = ns.Now(), list = "Cooking:150:225" })
    C:PublishProfessions()
    check(ns.Sync:Store("profs")["Jake-Realm"].list == "Cooking:150:225", "crafting: unreadable professions leave the shared list alone")
    -- the classic skill list: a collapsed Professions header shows no rows under it, which
    -- mustn't wipe what was shared (0.16.2)
    local skills = { { skillName = "Professions", isHeader = true }, { skillName = "Secondary Skills", isHeader = true } }
    local realSkill = C_SkillInfo
    C_SkillInfo = { GetNumSkillLines = function() return #skills end, GetSkillLineInfo = function(i) return skills[i] end }
    local _, readable, from = C:ReadProfessions()
    C:PublishProfessions()
    check(readable and from == "skills" and ns.Sync:Store("profs")["Jake-Realm"].list == "Cooking:150:225",
        "crafting: a collapsed Professions header in the skill list leaves the shared list alone")
    table.insert(skills, 2, { skillName = "Alchemy", skillRank = 120, skillMaxRank = 150 })
    C:PublishProfessions()
    check(ns.Sync:Store("profs")["Jake-Realm"].list == "Alchemy:120:150", "crafting: and the skill list is read when it shows them")
    C_SkillInfo = realSkill
    ns.Editor:ShowTab("home")
end

-- Profiles: accounts, Most played with, kudos, professions, page ---------------------------
do
    local P, Sync, UI = ns.Profiles, ns.Sync, ns.UI
    local Editor = ns.Editor
    STUB.party, STUB.roster, STUB.instance = nil, nil, { "Stormwind", "none" }
    table.insert(STUB.guild, { name = "Jakealt-Realm", rankIndex = 2, level = 23, online = false, class = "MAGE" })
    ns.Roster:ScanGuild()
    local me = Sync:Me()
    local guild = Sync:GuildName()
    local syncKey = ns.GuildKey() -- (sync stores are per guild and realm since 0.16.1)
    local now = ns.Now()
    local function apply(name, rec) return Sync:Apply(Sync.collections[name], rec) end
    local function prof(who, t)
        local r = { id = who, rev = now, by = who, author = who, t = now }
        for k, v in pairs(t or {}) do r[k] = v end
        return r
    end

    -- a test build of 0.13 kept Most played with per character, a profile per
    -- character and a wall: all of it moves to the account
    ns.db.account = nil
    ns.db.profiles = { guid1 = { together = { ["Raider05-Realm"] = 300 }, pins = { "Raider07-Realm" }, hidden = { x = true } },
        guid2 = { together = { ["Raider05-Realm"] = 200 }, pins = {}, hidden = {} } }
    ns.db.selfNames = ns.db.selfNames or {}
    ns.db.selfNames.testguid = me
    ns.db.sync[syncKey].wall = { old = { id = "old" } }
    ns.db.sync[syncKey].profile[me] = prof(me, { status = "From the test build", icon = 134169 })
    local a = P:Mine()
    check(a.together["Raider05-Realm"] == 500 and ns.db.profiles == nil and a.pins == nil,
        "accounts: the test build's Most played with moves to the account")
    check(a.content.status == "From the test build" and a.content.icon == 134169 and ns.db.sync[syncKey].wall == nil,
        "accounts: and its profile, and the old wall is dropped")
    wipe(a.together); wipe(a.content); a.ed = nil
    ns.db.sync[syncKey].profile[me] = nil
    ns.db.selfNames.testguid = nil

    -- our profile
    P:Save({ status = "Farming Devilsaur", about = "Hunter, raider, menace." })
    local mine = P:Get(me)
    check(a.content.status == "Farming Devilsaur" and mine and mine.status == "Farming Devilsaur"
        and mine.about == "Hunter, raider, menace." and mine.ed == a.ed and mine.chars == nil,
        "accounts: saving keeps the profile on the account and shares it")
    P:Save({ status = false, fav1 = "Molten Core" })
    mine = P:Get(me)
    check(mine.status == nil and mine.about == "Hunter, raider, menace." and mine.fav1 == "Molten Core",
        "accounts: fields change one at a time, false clears")
    local _, back = Sync:DecodeRecord(Sync:EncodeRecord(Sync.collections.profile, mine))
    check(back and back.about == mine.about and back.fav1 == "Molten Core" and back.ed == mine.ed, "accounts: a profile survives the wire")

    -- only you write your record; junk is refused
    check(not apply("profile", prof("Raider03-Realm", { by = "Raider05-Realm", status = "hacked" })), "accounts: nobody writes someone else's record")
    check(not apply("profile", prof("Raider03-Realm", { id = "Raider04-Realm" })), "accounts: a record's id is its character")
    check(not apply("profile", prof("Raider03-Realm", { status = ("x"):rep(61) }))
        and not apply("profile", prof("Raider03-Realm", { nick = ("x"):rep(21) })), "accounts: over-long text refused")
    check(not apply("profile", prof("Raider03-Realm", { icon = 0 })) and not apply("profile", prof("Raider03-Realm", { icon = 2.5 }))
        and not apply("profile", prof("Raider03-Realm", { ed = -1 })), "accounts: bad numbers refused")

    -- our characters: every one we play joins the account
    a.chars[guild]["Jakealt-Realm"] = now - 100
    P:Publish()
    check(P:Get(me).chars == "Jake-Realm,Jakealt-Realm" and P:IsMine("Jakealt-Realm") and #P:Linked(me) == 2,
        "accounts: our characters are listed on our record")
    check(P:Content("Jakealt-Realm") == a.content and P:Main("Jakealt-Realm") == me, "accounts: our alt shows our profile")

    -- someone else's account: linked only when both records list each other
    now = now + 10
    apply("profile", prof("Raider03-Realm", { status = "Old news", chars = "Raider03-Realm,Raider09-Realm", ed = 100 }))
    apply("profile", prof("Raider09-Realm", { rev = now + 1, status = "Looking for Scholo", chars = "Raider03-Realm,Raider09-Realm", ed = 200,
        icon = 135349, color = 3, song = 2, role = "H", top = "Raider05-Realm,Raider06-Realm" }))
    apply("profile", prof("Raider05-Realm", { status = "I'm Raider03 now", chars = "Raider03-Realm,Raider05-Realm", ed = 900 }))
    local l3 = P:Linked("Raider03-Realm")
    check(#l3 == 2 and l3[2] == "Raider09-Realm" and #P:Linked("Raider05-Realm") == 1,
        "accounts: two records that list each other are one account; a one-sided claim isn't")
    -- a character last shared before its account knew about the other one
    -- (no list yet): linked when the other lists it and the profile edit matches
    apply("profile", prof("Raider16-Realm", { status = "I tank", chars = "Raider16-Realm,Raider17-Realm", ed = 5000 }))
    apply("profile", prof("Raider17-Realm", { status = "I tank", ed = 5000 }))
    local l16, l17 = P:Linked("Raider16-Realm"), P:Linked("Raider17-Realm")
    check(#l16 == 2 and #l17 == 2 and l17[2] == "Raider16-Realm",
        "accounts: an older record with no list yet joins when the profile edit matches, from either side")
    apply("profile", prof("Raider18-Realm", { status = "Totally Raider19", chars = "Raider18-Realm,Raider19-Realm", ed = 6000 }))
    apply("profile", prof("Raider19-Realm", { status = "Me", ed = 7000 }))
    check(#P:Linked("Raider19-Realm") == 1 and #P:Linked("Raider18-Realm") == 1,
        "accounts: but not when the profiles differ (nobody can claim someone else's character)")
    apply("profile", prof("Raider21-Realm", { status = "I tank", chars = "Raider16-Realm,Raider21-Realm", ed = 5000 }))
    check(#P:Linked("Raider21-Realm") == 1 and #P:Linked("Raider16-Realm") == 2,
        "accounts: copying a profile can't claim a character whose record lists its own characters")
    check(P:Content("Raider03-Realm").status == "Looking for Scholo" and P:Content("Raider09-Realm").status == "Looking for Scholo",
        "accounts: the newest edit shows on every character")
    check(P:Portrait("Raider03-Realm") == 135349 and P:Portrait("Raider04-Realm") == 135428,
        "accounts: their portrait, or their class icon until they pick one")
    local r3, g3, b3 = P:Color("Raider03-Realm")
    check(r3 == P.COLORS[3][1] and g3 == P.COLORS[3][2] and b3 == P.COLORS[3][3] and P:Song("Raider03-Realm")[2] == "Stormwind",
        "accounts: theme color and song")
    check(P:Main("Raider09-Realm") == "Raider03-Realm", "accounts: the account goes by its highest level character")
    local top3 = P:Top("Raider03-Realm")
    check(#top3 == 2 and top3[1] == "Raider05-Realm", "accounts: their Most played with, as their account shared it")

    -- Most played with: time grouped per account, counted every minute
    STUB.party = { { name = "Raider05-Realm", class = "HUNTER" }, { name = "Raider06-Realm", class = "DRUID" },
        { name = "Pugsley", class = "ROGUE" }, { name = "Jakealt-Realm", class = "MAGE" } }
    -- (the stub's clock jumps, so a minute at a time to let every tick run)
    local function minutes(n) for _ = 1, n do STUB.Advance(60) end end
    minutes(20)
    STUB.party = { { name = "Raider05-Realm", class = "HUNTER" } }
    minutes(10)
    STUB.party = nil
    STUB.roster = { { name = "Jake" }, { name = "Raider07-Realm", online = false }, { name = "Raider08-Realm" } }
    minutes(15)
    STUB.roster = nil
    check(a.together["Raider05-Realm"] == 1800 and a.together["Raider06-Realm"] == 1200 and a.together["Raider08-Realm"] == 900,
        "most played: time grouped counted per guild member, party and raid")
    check(a.together.Pugsley == nil and a.together["Raider07-Realm"] == nil and a.together["Jakealt-Realm"] == nil
        and a.together[me] == nil, "most played: pugs, offline raid members and our own characters don't count")
    local function top() return table.concat(P:TopNames(), ",") end
    check(top() == "Raider05-Realm,Raider06-Realm,Raider08-Realm", "most played: most time grouped first")
    a.together["Raider09-Realm"], a.together["Raider03-Realm"] = 500, 500
    check(top() == "Raider05-Realm,Raider06-Realm,Raider03-Realm,Raider08-Realm",
        "most played: someone's characters add up, shown as their account")
    a.together["Raider10-Realm"] = 300
    check(not top():find("Raider10", 1, true), "most played: a few minutes together isn't enough")
    P:Publish()
    check(P:Get(me).top == top(), "most played: shared")
    for i = 11, 15 do a.together[("Raider%02d-Realm"):format(i)] = 700 + i end
    check(#P:TopNames() == 5 and top() == "Raider05-Realm,Raider06-Realm,Raider03-Realm,Raider08-Realm,Raider15-Realm",
        "most played: the top five")
    for i = 11, 15 do a.together[("Raider%02d-Realm"):format(i)] = nil end
    P:Publish()

    -- kudos
    local week = P.Week()
    local T = 2900 * 604800 + 5 * 86400 + 15 * 3600
    check(os.date("!%A %H:%M", T) == "Tuesday 15:00" and P.Week(T) == P.Week(T - 1) + 1 and P.Week(T + 604799) == P.Week(T),
        "kudos: weeks turn over at the Tuesday reset")
    check(P:GiveKudos("Raider03-Realm", 1) == nil and P:GiveKudos("Raider03-Realm", 1, "   ") == nil,
        "kudos: not without a message")
    check(P:GiveKudos("Raider03-Realm", 1, "Thanks for the |cffff0000heals|r") == true, "kudos: giving one")
    local kid = me .. ":1:Raider03-Realm"
    local k1 = Sync:Store("kudos")[kid]
    check(k1 and k1.n == 1 and k1.wk == week and k1.to == "Raider03-Realm" and k1.msg == "Thanks for the /cffff0000heals/r",
        "kudos: shared as a count per giver, kind and person, with the message")
    local kinds, recent, total, givers = P:Kudos("Raider03-Realm")
    check(kinds[1].n == 1 and kinds[1].gave and total == 1 and givers == 1 and recent[1].id == kid, "kudos: counted")
    check(P:GiveKudos("Raider03-Realm", 1) == false and Sync:Store("kudos")[kid].n == 0 and P:Kudos("Raider03-Realm")[1].n == 0,
        "kudos: clicking again the same week takes it back")
    check(P:GiveKudos("Raider03-Realm", 1, "For real") == true and Sync:Store("kudos")[kid].n == 1
        and Sync:Store("kudos")[kid].msg == "For real", "kudos: and gives it again, the newest message kept")
    -- kudos to their alt count on their account; their own alts' don't
    check(apply("kudos", { id = "Raider05-Realm:2:Raider09-Realm", rev = now, by = "Raider05-Realm", author = "Raider05-Realm", t = now,
        to = "Raider09-Realm", kind = 2, n = 3, wk = week - 2, msg = "Never died once" }), "kudos: a guildie's kudos arrive")
    apply("kudos", { id = "Raider09-Realm:3:Raider03-Realm", rev = now, by = "Raider09-Realm", author = "Raider09-Realm", t = now,
        to = "Raider03-Realm", kind = 3, n = 5, wk = week, msg = "me me me" })
    apply("kudos", { id = "Raider06-Realm:8:Raider03-Realm", rev = now, by = "Raider06-Realm", author = "Raider06-Realm", t = now,
        to = "Raider03-Realm", kind = 8, n = 2, wk = week, msg = "lol" })
    kinds, recent, total, givers = P:Kudos("Raider03-Realm")
    check(kinds[2].n == 3 and kinds[3].n == 0 and total == 4 and givers == 2,
        "kudos: an account's characters share their kudos, can't give themselves any, and Funny is retired")
    check(P:GiveKudos("Raider03-Realm", 8, "lol") == nil and P.KUDOS[9][2] == "GGWP", "kudos: Funny can't be given, GGWP can")
    check(P:GiveKudos("Jakealt-Realm", 1, "hi") == nil and P:GiveKudos(me, 1, "hi") == nil, "kudos: none for our own characters")
    local function bad(t)
        local r = { id = "Raider05-Realm:1:Raider06-Realm", rev = now, by = "Raider05-Realm", author = "Raider05-Realm", t = now,
            to = "Raider06-Realm", kind = 1, n = 1, wk = week, msg = "nice" }
        for k, v in pairs(t) do r[k] = v end
        return not apply("kudos", r)
    end
    check(bad({ by = "Raider07-Realm" }) and bad({ id = "Raider05-Realm:2:Raider06-Realm" }) and bad({ kind = 0 })
        and bad({ n = 521 }) and bad({ to = "Raider05-Realm", id = "Raider05-Realm:1:Raider05-Realm" }),
        "kudos: someone else's, mismatched, unknown or self kudos refused")
    check(bad({ msg = false }) and bad({ msg = ("x"):rep(81) }) and not bad({}), "kudos: a message is required, and short")
    -- one a week per kind, from the whole account
    apply("kudos", { id = "Jakealt-Realm:4:Raider05-Realm", rev = now, by = "Jakealt-Realm", author = "Jakealt-Realm", t = now,
        to = "Raider05-Realm", kind = 4, n = 1, wk = week, msg = "from my alt" })
    STUB.printed = {}
    check(P:GiveKudos("Raider05-Realm", 4, "again") == nil and printedContains("you gave that from Jakealt this week"),
        "kudos: one a week per kind, from any of our characters")
    STUB.Advance(7 * 86400)
    check(P:GiveKudos("Raider03-Realm", 1, "Week two") == true and Sync:Store("kudos")[kid].n == 2
        and P:Kudos("Raider03-Realm")[1].n == 2, "kudos: next week it counts up")

    -- professions: the two main ones
    apply("profs", { id = "Raider10-Realm", rev = now, by = "Raider10-Realm", author = "Raider10-Realm", t = now,
        list = "Cooking:300:300|Alchemy:250:300|Herbalism:300:300|Fishing:150:300" })
    local pr = P:Professions("Raider10-Realm")
    check(#pr == 2 and pr[1].name == "Alchemy" and pr[1].icon == 136240 and pr[1].recipes == nil and pr[2].name == "Herbalism"
        and pr[2].gathering, "professions: main professions only, gathering ones marked")
    local p3 = P:Professions("Raider03-Realm")
    check(#p3 == 2 and p3[1].name == "Blacksmithing" and p3[1].recipes == 3 and p3[1].rank == 300 and not p3[2].gathering,
        "professions: skill and shared recipe count")

    -- the page
    STUB.music = nil
    SlashCmdList.POGRAID("profile Raider03")
    check(Editor.currentTab == "profiles" and P.page:IsShown() and P.viewing == "Raider03-Realm", "page: /pog profile <name> opens theirs")
    local b = P.banner
    check(b.name:GetText():find("Raider03", 1, true) and b.status:GetText() == "Looking for Scholo"
        and b.info:GetText():find("Level 60 Mage", 1, true) and b.info:GetText():find("Heals", 1, true), "page: banner")
    check(b.whisper:IsShown() and not b.edit:IsShown() and b.song:GetText() == "Song: Stormwind", "page: someone else's buttons and song")
    check(STUB.music == 53211 and b.play.label:GetText() == "Stop", "page: their song plays")
    STUB.Script(b.play, "OnClick")
    check(STUB.music == nil and b.play.label:GetText() == "Play", "page: and stops")
    P:Refresh()
    check(STUB.music == nil, "page: refreshing doesn't start it again")
    check(P.aboutCard.infoRows[1].value:GetText() == "Raider09" and P.aboutCard.text:GetText() == "Nothing here yet.",
        "page: their other characters")
    -- one page per account: opening an alt shows it, on the alt's professions
    P:Open("Raider09-Realm")
    check(P.viewing == "Raider03-Realm" and P.profChar == "Raider09-Realm" and P.profCard.switch:IsShown()
        and P.profCard.switch.label:GetText() == "Raider09" and not P.profCard.tiles[1]:IsShown(),
        "accounts: opening an alt shows the account's page, on the alt's professions")
    local pmenu
    local realShowP = UI.ShowMenu
    UI.ShowMenu = function(_, e) pmenu = e end
    STUB.Script(P.profCard.switch, "OnClick")
    UI.ShowMenu = realShowP
    check(pmenu[2].text == "   Raider03" and pmenu[3].text == "> Raider09", "accounts: the professions card can switch character")
    pmenu[2].func()
    check(P.profChar == "Raider03-Realm" and P.profCard.tiles[1].name:GetText() == "Blacksmithing", "accounts: switched")
    local tiles = P.topCard.tiles
    check(tiles[1].member == "Raider05-Realm" and tiles[2]:IsShown() and not tiles[3]:IsShown(), "page: their Most played with")
    -- members: one row per account
    local rows, r03, r09 = P.list.rows, nil, nil
    for _, row in ipairs(rows) do
        if row.member == "Raider03-Realm" then r03 = row end
        if row.member == "Raider09-Realm" then r09 = row end
    end
    check(r03 and not r09 and not r03.name:GetText():find("+1", 1, true) and r03.sel:IsShown(), "list: one row per account (no +1 since 0.16)")
    local listed = {}
    for _, m in ipairs(P:Members()) do listed[m] = true end
    check(listed["Raider03-Realm"] and listed[me] and not listed["Raider20-Realm"] and not P:HasAddon("Raider20-Realm"),
        "list: only people confirmed to have Pog Raid")
    ns.db.versions = ns.db.versions or {}
    ns.db.versions["Raider21-Realm"] = { v = "0.13.0", t = ns.Now() }
    check(P:HasAddon("Raider21-Realm"), "list: someone we've heard the version check from counts")
    ns.db.versions["Raider21-Realm"] = nil
    P.searchBox:SetText("raider20")
    STUB.Script(P.searchBox, "OnTextChanged")
    check(not rows[1]:IsShown() and P.list.empty:GetText() == "Nobody with Pog Guild Tools matches.", "list: searching someone without it")
    STUB.printed = {}
    P:Open("Raider20-Realm")
    check(P.viewing == "Raider03-Realm" and printedContains("doesn't have Pog Guild Tools yet"), "page: no profile without Pog Raid")
    P.searchBox:SetText("raider09")
    STUB.Script(P.searchBox, "OnTextChanged")
    check(rows[1].member == "Raider03-Realm" and not rows[2]:IsShown(), "list: searching an alt finds the account")
    P.searchBox:SetText("")
    STUB.Script(P.searchBox, "OnTextChanged")
    -- 0.16: online first, then profiles someone has set up, then the rest, each alphabetical
    local members, online = P:Members()
    local sorted, prev, sawOnline, sawCustom = true, nil, false, false
    for _, m in ipairs(members) do
        local key = { online[m] and 0 or 1, P:Customized(m) and 0 or 1, P:Name(m):lower() }
        if online[m] then sawOnline = true end
        if P:Customized(m) then sawCustom = true end
        if prev and (key[1] < prev[1] or (key[1] == prev[1] and (key[2] < prev[2] or (key[2] == prev[2] and key[3] < prev[3])))) then
            sorted = false
        end
        prev = key
    end
    check(#members > 1 and sawOnline and sawCustom and sorted,
        "list: online first, then set-up profiles, then everyone else, each alphabetical")
    STUB.Script(tiles[1], "OnClick")
    check(P.viewing == "Raider05-Realm", "page: clicking someone in Most played with opens their profile")
    P:Open("Raider03-Realm")

    -- professions and the recipe book
    local pt = P.profCard.tiles
    -- 0.16: no recipe count on the tile; the hint says whether there's a book to browse
    check(pt[1].name:GetText() == "Blacksmithing" and pt[1].skill:GetText() == "300 / 300" and pt[1].recipes == nil
        and pt[1].hint:GetText() == "Browse recipes" and pt[2].hint:GetText() == "Recipes not shared yet", "page: profession tiles")
    STUB.Script(pt[1], "OnClick")
    local book = P.book
    check(book:IsShown() and not P.aboutCard:IsShown() and book.rows[1].recipe and book.rows[1].recipe.name == "Arcanite Reaper"
        and book.rows[3]:IsShown() and not book.rows[4]:IsShown() and book.meta:GetText() == "300 / 300",
        "book: clicking a profession opens their recipes")
    book.search:SetText("reaper")
    STUB.Script(book.search, "OnTextChanged")
    check(book.rows[2]:IsShown() and not book.rows[3]:IsShown(), "book: search")
    STUB.Script(book.back, "OnClick")
    check(not book:IsShown() and P.aboutCard:IsShown(), "book: Back")
    STUB.Script(pt[2], "OnClick")
    check(book:IsShown() and book.empty:IsShown() and book.empty:GetText():find("hasn't shared their Mining", 1, true),
        "book: a profession whose recipes aren't shared says so")
    P:CloseBook()
    P:Open("Raider10-Realm")
    STUB.Script(P.profCard.tiles[2], "OnClick")
    check(not book:IsShown() and P.profCard.tiles[2].hint:GetText() == "", "book: gathering professions have no book")
    P:Open("Raider03-Realm")

    -- kudos: the latest ones, no counts
    local kcard = P.kudosCard
    check(kcard.rows[1]:IsShown() and kcard.rows[2]:IsShown() and not kcard.rows[3]:IsShown() and kcard.meta:GetText() == ""
        and kcard.give:IsShown(), "page: their latest kudos, and no counts")
    local heads = kcard.rows[1].head:GetText() .. "|" .. kcard.rows[2].head:GetText()
    check(heads:find("Clutch heals", 1, true) and heads:find("Great tank", 1, true) and not heads:find("Funny", 1, true)
        and kcard.rows[1].msg:GetText() == "Week two" and kcard.rows[1].icon.__texture == P.KUDOS[1][1],
        "page: each with its kind, giver and message, newest first")
    STUB.Script(kcard.rows[1], "OnEnter")
    local ktip = table.concat(GameTooltip.lines, "|")
    check(ktip:find("Clutch heals", 1, true) and ktip:find("from Jake", 1, true) and ktip:find("Week two", 1, true),
        "page: hovering a kudos shows it in full")
    -- giving: a menu of the kinds, then a few words
    local kmenu
    local realShowK = UI.ShowMenu
    UI.ShowMenu = function(_, e) kmenu = e end
    STUB.Script(kcard.give, "OnClick")
    local ktexts = {}
    for _, e in ipairs(kmenu) do ktexts[#ktexts + 1] = e.text end
    ktexts = table.concat(ktexts, "|")
    check(#kmenu == 9 and kmenu[9].text:find("GGWP", 1, true) and kmenu[2].text:find("take back", 1, true)
        and not ktexts:find("Funny", 1, true), "page: Give kudos lists the kinds, GGWP instead of Funny, ours this week marked")
    kmenu[6].func()
    local kc = UI.composeFrame
    check(kc:IsShown() and kc.heading:GetText() == "Helpful for Raider03", "page: picking one asks for a few words")
    STUB.Script(kc.submit, "OnClick")
    check(kc:IsShown() and kcard.rows[1].msg:GetText() == "Week two", "page: not without them")
    kc.field2:SetText("Showed me the Gnomeregan route")
    STUB.Script(kc.submit, "OnClick")
    check(kcard.rows[1].msg:GetText() == "Showed me the Gnomeregan route" and kcard.rows[3]:IsShown(), "page: given, at the top")
    STUB.Script(kcard.give, "OnClick")
    check(kmenu[6].text:find("take back", 1, true), "page: then it can be taken back")
    kmenu[6].func()
    UI.ShowMenu = realShowK
    check(kcard.rows[1].msg:GetText() == "Week two" and not kcard.rows[3]:IsShown(), "page: taken back")

    -- layout
    local pl, pt0 = STUB.rect(P.page)
    local function edges(f)
        local l, t, w, h = STUB.rect(f)
        return l - pl, pt0 - t, l - pl + w, pt0 - t + h
    end
    local bl, btop, br, bb = edges(b)
    local al, at, ar = edges(P.aboutCard)
    local _, _, _, pb = edges(P.profCard)
    local cl_, ct_, cr_, cb_ = edges(P.charCard)
    local tl, tt, tr = edges(P.topCard)
    local _, _, kr, kb = edges(P.kudosCard)
    local ll, _, lr = edges(P.list)
    local ml, _, _, mb = edges(P.mine)
    local _, st = edges(P.searchBox)
    local _, kt = edges(P.kudosCard)
    local _, _, _, tb = edges(P.topCard)
    local _, pt_ = edges(P.profCard)
    local _, _, _, ab = edges(P.aboutCard)
    check(bl == al and al == lr + 12 and tl == al and tr == ar and br == cr_ and cr_ == kr and br == 902 - 12,
        "layout: columns line up left and right")
    check(btop == st and at == ct_ and pt_ == ab + 8 and tt == pb + 8 and kt == cb_ + 8 and tb == kb and kb == mb
        and mb == ns.PAGE_H - 12, "layout: tops and bottoms line up")
    check(math.abs((cl_ - ar) - 8) < 0.01 and ll == 12 and ml == 12, "layout: gaps on the grid")
    check(P.layout.ABOUT_H <= 170 and cb_ - ct_ >= 240, "layout: a short About me, a big character")
    local _, pTop, _, pBottom = edges(b.pic)
    check(math.abs((pTop - btop) - (bb - pBottom)) < 0.01, "layout: portrait centred in the banner")
    local _, f1 = edges(P.aboutCard.infoRows[1])
    local _, _, _, f3 = edges(P.aboutCard.infoRows[3])
    local AH = P.layout.ABOUT_H
    check(#P.aboutCard.infoRows == 3 and math.abs((f1 - (at + AH - P.layout.INFO_H)) - (at + AH - f3)) < 0.01,
        "layout: info rows centred under their divider")
    local x1 = edges(P.topCard.tiles[1])
    local _, _, x5 = edges(P.topCard.tiles[5])
    check(math.abs((x1 - tl) - (tr - x5)) < 0.01, "layout: Most played with centred in its card")
    -- (rows stretch between two anchors, which the stub doesn't follow: check where they start)
    local k1l, k1t = edges(P.kudosCard.rows[1])
    local _, _, _, kLast = edges(P.kudosCard.rows[#P.kudosCard.rows])
    check(k1l == cl_ + 2 and k1t == kt + 26 + 4 and kLast <= kb and kLast > kb - 38,
        "layout: kudos rows under the header, filling the card")
    local p1l = edges(pt[1])
    local _, _, p2r = edges(pt[2])
    check(math.abs((p1l - al) - 8) < 0.01 and math.abs((ar - p2r) - 8) < 0.01, "layout: profession tiles fill their card")
    local bkl, bkt, bkr, bkb = edges(book)
    check(bkl == al and bkt == at and bkr == kr and bkb == kb, "layout: the recipe book covers the profile's body")
    -- someone with nothing shared: their portrait, Inspect at the bottom
    local c = P.charCard
    local il, it_, ir, ib = edges(c.inspect)
    check(c.inspect:IsShown() and c.pic:IsShown() and not c.mini[1]:IsShown() and math.abs((il - cl_) - (cr_ - ir)) < 0.01
        and ib == cb_ - 16, "layout: nothing shared, Inspect centred at the bottom")
    local gl = edges(c.inspect.glass)
    check(c.inspect.label:GetText() == "Inspect" and math.abs((gl - il) - (ir - (gl + 14 + 5 + c.inspect.label:GetStringWidth()))) <= 1,
        "layout: the glass and the word are centred together")
    -- the character card (0.16): our numbers between our gear by default, a button above the weapons
    -- switches to the model
    local viewed = P.viewing
    P:Open(me)
    local vl, _, vr, vb = edges(c.viewBtn)
    local _, wt = edges(c.mini[#c.mini])
    check(c.title == nil and c.name == nil and c.miniInspect == nil and not c.inspect:IsShown() and c.mini[1]:IsShown()
        and not c.classIcon:IsShown() and c.stats:IsShown() and not c.model:IsShown() and c.viewBtn:IsShown()
        and c.viewBtn.label:GetText() == "Show model" and math.abs((vl - cl_) - (cr_ - vr)) < 0.01 and vb < wt,
        "layout: the character card shows our stats between our gear, a button above the weapons")
    STUB.Script(c.viewBtn, "OnClick")
    local ml_, mt_, mr_ = edges(c.model)
    local _, _, lcr = edges(c.mini[1])
    local rcl = edges(c.mini[#P.MINI.left + 1])
    check(c.model:IsShown() and not c.stats:IsShown() and c.viewBtn.label:GetText() == "Show stats"
        and mt_ == ct_ + 8 and math.abs((ml_ - cl_) - (cr_ - mr_)) < 0.01 and ml_ > lcr and mr_ < rcl,
        "layout: Show model puts our model between our gear")
    STUB.Script(c.viewBtn, "OnClick")
    check(c.stats:IsShown() and not c.model:IsShown(), "layout: and back to the stats")
    -- our own icons: what we're wearing now
    local wornBefore = STUB.worn
    STUB.worn = { [1] = 5001 }
    P:RefreshCharacter()
    check(c.mini[1].link and c.mini[1].link:find("Hitem:5001", 1, true) and c.mini[2].link == nil
        and c.mini[2]:IsShown(), "layout: our gear icons show what we wear")
    STUB.worn = { [1] = 5001, [2] = 5002 }
    STUB.Fire("PLAYER_EQUIPMENT_CHANGED", 2)
    check(c.mini[2].link and c.mini[2].link:find("Hitem:5002", 1, true), "layout: changing gear updates them straight away")
    STUB.worn = wornBefore
    P:Open(viewed)

    -- our own profile: edit it
    P.playing = { 1, "x" }
    STUB.music = 1
    STUB.Script(P.mine, "OnClick")
    check(P.viewing == me and STUB.music == nil and b.edit:IsShown() and b.portraitBtn == nil and not b.whisper:IsShown(),
        "page: My profile shows ours with edit buttons, and stops the music")
    check(not P.kudosCard.give:IsShown(), "page: no kudos for ourselves")
    local cf
    local function edit(label)
        for _, e in ipairs(P:EditMenu()) do if e.text == label then return e.func() end end
        error("no " .. label)
    end
    edit("Status and About Me...")
    cf = UI.composeFrame
    cf.field1:SetText("Back from the Barrens")
    cf.field2:SetText("")
    STUB.Script(cf.submit, "OnClick")
    check(a.content.status == "Back from the Barrens" and a.content.about == nil and P:Get(me).status == "Back from the Barrens"
        and b.status:GetText() == "Back from the Barrens", "edit: status and About Me saved, an empty box clears")
    edit("Status and About Me...")
    cf.field1:SetText("")
    cf.field2:SetText("Hunter main.")
    STUB.Script(cf.submit, "OnClick")
    check(a.content.status == nil and a.content.about == "Hunter main." and not cf:IsShown(), "edit: the status can be cleared too")
    edit("Favorites...")
    check(cf.fieldMid:IsShown() and not cf.area:IsShown(), "edit: favorites are two one-line boxes")
    cf.field1:SetText("Molten Core")
    cf.fieldMid:SetText("Deadmines")
    STUB.Script(cf.fieldMid, "OnEnterPressed")
    check(a.content.fav1 == "Molten Core" and a.content.fav2 == "Deadmines" and not cf:IsShown()
        and P.aboutCard.infoRows[3].value:GetText() == "Deadmines", "edit: favorites, Enter in the last box saves")
    local roles = {}
    for _, e in ipairs(P:EditMenu()) do roles[#roles + 1] = e.text end
    check(table.concat(roles, "|"):find("Main role|   DPS|   Tank|   Heals|> No main role", 1, true), "edit: roles DPS, Tank, Heals")
    for _, e in ipairs(P:EditMenu()) do if e.text == "   Tank" then e.func() end end
    check(a.content.role == "T" and b.info:GetText():find("Tank", 1, true), "edit: main role")
    -- a nickname: big on the banner, our character's name beside it, everywhere
    edit("Nickname...")
    check(cf.field1:IsShown() and not cf.area:IsShown(), "nickname: one line")
    cf.field1:SetText("Jakey")
    STUB.Script(cf.submit, "OnClick")
    check(a.content.nick == "Jakey" and P:Get(me).nick == "Jakey" and b.name:GetText():find("Jakey", 1, true)
        and b.info:GetText():find("Jake|r", 1, true), "nickname: big on the banner, our character's name under it")
    check(P:Name("Jakealt-Realm") == "Jakey" and P:Name(me, true) == "Jakey (Jake)" and P:Name("Raider03-Realm") == "Raider03",
        "nickname: the whole account goes by it, others by their main")
    local mineRow
    for _, row in ipairs(P.list.rows) do if row.member == me then mineRow = row end end
    check(mineRow and mineRow.name:GetText():find("Jakey", 1, true) and mineRow.name:GetText():find("Jake|r", 1, true),
        "nickname: the members list shows it with the character's name")
    P.searchBox:SetText("jakey")
    STUB.Script(P.searchBox, "OnTextChanged")
    check(P.list.rows[1].member == me, "nickname: the search finds it")
    P.searchBox:SetText("")
    STUB.Script(P.searchBox, "OnTextChanged")
    edit("Portrait...") -- 0.16: in the Edit profile menu
    local pk = UI.pickerFrame
    check(pk:IsShown() and pk.pageText:GetText() == "Page 1 of 4" and pk.cells[96]:IsShown() and pk.cells[97] == nil
        and pk.nav:IsShown(), "edit: portrait picker: ours, then the client's classic icons, in pages")
    check(#P:IconChoices() == 48 + 300 and P:IconChoices()[49] == 139001,
        "edit: the client's classic-art icons as file IDs, no repeats, nothing newer")
    STUB.Script(pk.next, "OnClick")
    check(pk.cells[1].index == 97 and pk.cells[1].icon.__texture == 139049, "edit: next page")
    STUB.Script(pk, "OnMouseWheel", 1)
    check(pk.page == 1 and not pk.prev:IsEnabled(), "edit: the mouse wheel turns pages")
    STUB.Script(pk.cells[25], "OnClick")
    check(a.content.icon == 134169 and P:Portrait(me) == 134169 and P:Portrait("Jakealt-Realm") == 134169 and not pk:IsShown()
        and b.pic.icon.__texture == 134169, "edit: picking a portrait, for the whole account")
    edit("Portrait...") -- 0.16: in the Edit profile menu
    STUB.Script(pk.next, "OnClick")
    STUB.Script(pk.cells[1], "OnClick")
    edit("Portrait...") -- 0.16: in the Edit profile menu
    check(a.content.icon == 139049 and pk.page == 2 and pk.cells[1].selected, "edit: the picker opens on the page with ours")
    edit("Portrait...") -- 0.16: in the Edit profile menu
    edit("Color...")
    check(pk:IsShown() and pk.cells[1].tip == "Class color" and pk.cells[10]:IsShown() and not pk.cells[11]:IsShown()
        and not pk.nav:IsShown(), "edit: color picker reuses the grid")
    STUB.Script(pk.cells[8], "OnClick")
    check(a.content.color == 7 and b.washColor[1] == P.COLORS[7][1], "edit: picking a color (the banner's wash, 0.16)")
    edit("Color...")
    STUB.Script(pk.cells[1], "OnClick")
    check(a.content.color == nil, "edit: back to class color")
    local songs = P:SongMenu()
    check(#songs == #P.SONGS + 1, "edit: song menu lists every song")
    songs[3].func()
    check(a.content.song == 2 and STUB.music == 53211 and b.song:GetText() == "Song: Stormwind", "edit: picking a song plays it")
    P:Open("Raider03-Realm")
    P:Open(me)
    check(STUB.music == nil and b.play:IsShown(), "song: our own doesn't play by itself")
    P:SongMenu()[1].func()
    check(a.content.song == nil and STUB.music == nil and not b.play:IsShown(), "edit: No song")

    -- our Most played with: automatic, nothing to pick
    local ours = P.topCard.tiles
    check(ours[4].member == "Raider08-Realm" and not ours[5]:IsShown() and P.topCard.meta:GetText() == "",
        "most played: ours, automatic, no empty slots")
    STUB.Script(ours[4], "OnEnter")
    check(table.concat(GameTooltip.lines, "|"):find("Doesn't have Pog Guild Tools yet", 1, true), "most played: says who doesn't have it")
    STUB.Script(ours[4], "OnClick")
    check(P.viewing == me, "most played: no profile to open without Pog Raid")
    local shown
    local realShow = UI.ShowMenu
    UI.ShowMenu = function(_, e) shown = e end
    -- our characters: forget one
    STUB.Script(P.aboutCard.infoRows[1], "OnClick")
    UI.ShowMenu = realShow
    check(P.aboutCard.infoRows[1].value:GetText() == "Jakealt" and shown[#shown].text == "Jakealt isn't mine any more",
        "accounts: our characters, and a way to let one go")
    shown[#shown].func()
    check(not P:IsMine("Jakealt-Realm") and P:Get(me).chars == nil and P.aboutCard.infoRows[1].value:GetText() == "just this one",
        "accounts: a character let go leaves the account")

    -- songs: off in Settings, and leaving the page stops them
    ns.db.settings.profileSongs = false
    P:Open("Raider03-Realm")
    check(STUB.music == nil, "song: off in Settings, nothing plays")
    ns.db.settings.profileSongs = true
    P:Open(me)
    P:Open("Raider03-Realm")
    check(STUB.music == 53211, "song: (playing)")
    Editor:ShowTab("home")
    check(STUB.music == nil, "song: leaving the page stops it")

    -- View profile from names elsewhere
    local entries = ns.Roster:PlayerEntries("Raider03-Realm")
    check(entries[2].text == "View profile" and ns.Roster:PlayerEntries("Raider20-Realm")[2].text ~= "View profile",
        "names: roster menu has View profile, only for people with Pog Raid")
    entries[2].func()
    check(Editor.currentTab == "profiles" and P.viewing == "Raider03-Realm", "names: and it opens their profile")

    STUB.music = nil
    Editor:ShowTab("home")
end

-- Poisons, group pop-ups, guild-wide recent loot ---------------------------------------
do
    local Sync, Home, C = ns.Sync, ns.Home, ns.Crafting
    local now = ns.Now()

    -- Poisons (and Lockpicking) aren't professions here
    local parsed = C.ParseList("Poisons:100:300|Alchemy:50:75|Lockpicking:20:300")
    check(#parsed == 1 and parsed[1].name == "Alchemy", "crafting: Poisons and Lockpicking left out of shared lists")
    GetProfessions = function() return 1, nil, nil, 2 end
    GetProfessionInfo = function(i) return unpack(({ { "Poisons", 1, 100, 300 }, { "Alchemy", 2, 50, 75 } })[i]) end
    local mine = C:ReadProfessions()
    check(#mine == 1 and mine[1].name == "Alchemy", "crafting: and not read as ours")
    GetProfessions, GetProfessionInfo = nil, nil
    Sync:Apply(Sync.collections.recipes, { id = "Raider07-Realm:Poisons", rev = now, by = "Raider07-Realm",
        author = "Raider07-Realm", t = now, prof = "Poisons", ids = C.Pack({ 16665 }) })
    C.index = nil
    local found = false
    for _, hit in ipairs(C:Search("arcanite")) do
        for _, cr in ipairs(hit.crafters) do if cr.name == "Raider07-Realm" then found = true end end
    end
    check(not found and C:Directory().Poisons == nil, "crafting: nobody's Poisons in search or the directory")

    -- a guildie posts a group: a pop-up fades in above the chat box
    local T = ns.GroupToast
    local function listing(id, who, t, extra)
        local r = { id = id, rev = t, by = who, author = who, t = t, what = "Deadmines", need = "healer",
            exp = t + 2700, size = 2, max = 5 }
        for k, v in pairs(extra or {}) do r[k] = v end
        return Sync:Apply(Sync.collections.lfg, r)
    end
    listing("lfg-t1", "Raider03-Realm", now)
    local f = T.frame
    check(f and f:IsShown() and f.text:GetText():find("Raider03", 1, true) and f.text:GetText():find("is forming a group for Deadmines", 1, true)
        and f.sub:GetText() == "needs healer  2/5", "toast: a guildie's new group pops up")
    check(not f.two and f:GetHeight() == 50 and f:GetWidth() >= T.MIN_W and f:GetWidth() <= T.MAX_W
        and f.text:GetWidth() == f:GetWidth() - 62 and f.text:GetStringWidth() <= f.text:GetWidth(), "toast: wide enough for its line")
    check(f:GetAlpha() == 0, "toast: starts see-through")
    T:Step(0.15)
    local half = f:GetAlpha()
    T:Step(0.3)
    check(half > 0.3 and half < 0.7 and f:GetAlpha() == 1 and f:IsShown(), "toast: fades in and stays")
    T:Step(7.8)
    check(f:GetAlpha() < 1 and f:GetAlpha() > 0 and f:IsShown(), "toast: fades out after a few seconds")
    f.age = 1
    f.hover = true
    T:Step(30)
    check(f:IsShown(), "toast: stays while hovered")
    f.hover = false
    T:Step(10)
    check(not f:IsShown(), "toast: then fades away")
    listing("lfg-t1", "Raider03-Realm", now, { rev = now + 1, size = 3 })
    check(not f:IsShown(), "toast: once per group, not for every update")
    listing("lfg-old", "Raider04-Realm", now - 600)
    check(not f:IsShown(), "toast: not for groups caught up on at login")
    listing("lfg-mine", "Jake-Realm", now)
    check(not f:IsShown(), "toast: not for our own group")
    ns.db.settings.groupToasts = false
    listing("lfg-off", "Raider05-Realm", now)
    check(not f:IsShown(), "toast: can be turned off in Settings")
    ns.db.settings.groupToasts = true
    -- clicking asks to join; right-click dismisses
    listing("lfg-t2", "Raider06-Realm", now)
    STUB.sent = {}
    STUB.Script(f, "OnClick", "LeftButton")
    check(ns.Social.requested["lfg-t2"] and STUB.sent[1] and STUB.sent[1].text == "Jlfg-t2" and STUB.sent[1].target == "Raider06"
        and f.sub:GetText() == "Asked to join", "toast: click to ask to join")
    T:Step(3)
    check(not f:IsShown(), "toast: leaves soon after")
    listing("lfg-long", "Raider07-Realm", now, { what = ("Farming Devilsaur leather in Un'Goro, all welcome!"):sub(1, 50) })
    local _, st, _, sh = STUB.rect(f.sub)
    local _, ft, _, fh = STUB.rect(f)
    check(f.two and f:GetWidth() == T.MAX_W and f:GetHeight() == 64 and (st - sh) > (ft - fh),
        "toast: a long title wraps to a second line, the rest still inside")
    listing("lfg-t3", "Raider08-Realm", now)
    check(not f.two and f:GetHeight() == 50, "toast: back to one line for a short one")
    STUB.Script(f, "OnClick", "RightButton")
    check(not f:IsShown(), "toast: right-click dismisses")
    STUB.sent = {}

    -- recent loot from the whole guild: everyone shares their own drops
    local blue = STUB.Link(22001, "Shared Blue", "0070dd")
    Home:OnLoot("Jake", blue)
    local ours
    for _, rec in pairs(Sync:Store("drops")) do if rec.item == blue and rec.author == "Jake-Realm" then ours = rec end end
    check(ours and ours.q == 3, "drops: our own blue drop is shared")
    local function drop(id, who, link, t, q)
        return Sync:Apply(Sync.collections.drops, { id = id, rev = t, by = who, author = who, t = t, item = link, q = q or 3 })
    end
    check(drop("d1", "Raider09-Realm", STUB.Link(22002, "Far Away Epic"), now + 5, 4), "drops: a guildie's drop arrives")
    local recent = Home:RecentLoot()
    check(recent[1].player == "Raider09-Realm" and recent[1].itemID == 22002, "drops: a guildie's drop shows, though we weren't with them")
    local partyBlue = STUB.Link(22003, "Party Blue", "0070dd")
    Home:OnLoot("Raider10", partyBlue)
    drop("d2", "Raider10-Realm", partyBlue, ns.Now() + 30)
    local n = 0
    for _, e in ipairs(Home:RecentLoot()) do if e.itemID == 22003 then n = n + 1 end end
    check(n == 1, "drops: seen in our group and shared, it shows once")
    check(not drop("d3", "Raider11-Realm", STUB.Link(22004, "Green", "1eff00"), now, 2)
        and not Sync:Apply(Sync.collections.drops, { id = "d4", rev = now, by = "Raider12-Realm", author = "Raider11-Realm",
            t = now, item = blue, q = 3 }) and not drop("d5", "Raider11-Realm", "not an item", now),
        "drops: greens, someone else's and junk refused")
    check(not drop("d6", "Raider11-Realm", STUB.Link(22005, "Yesterday"), now - 90000, 4), "drops: older than a day refused")
    SlashCmdList.POGRAID("home")
    Home:Refresh()
    local shown = false
    for _, row in ipairs(Home.lootCard.rows) do
        if row.item and row.item.itemID == 22002 then shown = true end
    end
    check(shown, "drops: on the Home page")
    Editor:ShowTab("boards")
end

-- Bug reports ----------------------------------------------------------------------------
do
    local Bug = ns.Bug
    Bug:Clear()
    ns.On("POG_TEST_BREAK", function() error("PogRaid/Home.lua:42: attempt to index a nil value", 0) end)
    STUB.stack = "Interface/AddOns/PogRaid/Home.lua:42: in function <Interface/AddOns/PogRaid/Home.lua:40>\n[C]: in function 'pcall'"
    check(not pcall(STUB.Fire, "POG_TEST_BREAK") and not pcall(STUB.Fire, "POG_TEST_BREAK"), "bug: handler errors still reach the game's handler")
    local list = ns.db.errors
    check(#list == 1 and list[1].count == 2 and list[1].msg == "PogRaid/Home.lua:42: attempt to index a nil value",
        "bug: an event handler's error is kept once, with a count")
    STUB.Advance(1)
    check(not pcall(geterrorhandler(), "Interface/AddOns/PogRaid/Crafting.lua:7: bad argument"), "bug: timer/click errors pass through")
    check(#list == 2 and list[1].msg == "PogRaid/Crafting.lua:7: bad argument" and list[1].stack:find("Home.lua:42", 1, true) ~= nil,
        "bug: errors outside handlers are kept too, with our stack lines")
    STUB.stack = "Interface/AddOns/OtherAddon/x.lua:1: in main chunk"
    pcall(geterrorhandler(), "Interface/AddOns/OtherAddon/x.lua:1: not ours")
    check(#list == 2, "bug: other addons' errors are left alone")
    local report = Bug:Report()
    check(report:find("Pog Guild Tools " .. ns.VERSION, 1, true) and report:find("This session:", 1, true) and report:find("[x2]", 1, true)
        and report:find("    PogRaid/Home.lua:42: in function", 1, true), "bug: report has version, counts and stack lines")
    Bug.session = {}
    check(Bug:Report():find("Earlier:", 1, true) and not Bug:Report():find("This session:", 1, true), "bug: older errors listed as earlier")
    for i = 1, 30 do Bug.Record("PogRaid/X.lua:" .. i .. ": e" .. i) end
    check(#list == Bug.KEEP, "bug: keeps the last 25 different errors")
    SlashCmdList.POGRAID("bug")
    check(PogRaidCopy and PogRaidCopy:IsShown() and PogRaidCopy.edit:GetText():find("X.lua:30", 1, true) ~= nil, "bug: /pog bug opens the copy box")
    PogRaidCopy:Hide()
    SlashCmdList.POGRAID("bug clear")
    check(#ns.db.errors == 0 and Bug:Report():find("No Pog Guild Tools errors recorded.", 1, true) ~= nil, "bug: /pog bug clear empties it")
    STUB.stack = nil

    -- performance lines for /pog probe
    C_AddOnProfiler = {
        IsEnabled = function() return true end,
        GetAddOnMetric = function(_, m) return ({ [0] = 0.012, [1] = 0.009, [4] = 3.24, [6] = 0 })[m] end,
        GetOverallMetric = function() return 0.6 end,
    }
    UpdateAddOnMemoryUsage = function() end
    GetAddOnMemoryUsage = function(name) return name == "PogRaid" and 1843.2 or 0 end
    local perf = table.concat(Bug:Performance(), "\n")
    check(perf:find("0.012 ms a frame on average (2% of all addons)", 1, true) and perf:find("slowest 3.2 ms", 1, true)
        and perf:find("memory: 1.8 MB, shared records:", 1, true), "probe: CPU time and memory")
    C_AddOnProfiler, UpdateAddOnMemoryUsage, GetAddOnMemoryUsage = nil, nil, nil
    check(Bug:Performance()[1]:find("isn't available", 1, true) ~= nil, "probe: says so when the profiler is missing")
end

-- Names and catching up after missed messages ----------------------------------------------
do
    check(ns.SameName("Flyne", "Flyne Lee") and ns.SameName("Flyne Lee", "Flyne") and ns.SameName("Jake", "Jake-Realm"),
        "names: a first name matches its full name")
    check(not ns.SameName("Keeb Pog", "Keeb Sixseven") and not ns.SameName("Flyne", "Flynn Lee") and not ns.SameName("Flyne", nil),
        "names: different characters stay different")
    local n = #STUB.guild
    table.insert(STUB.guild, { name = "Flyne Lee", rankIndex = 2, level = 20, online = true, class = "WARRIOR" })
    table.insert(STUB.guild, { name = "Keeb Pog", rankIndex = 0, level = 18, online = false, class = "MAGE" })
    table.insert(STUB.guild, { name = "Keeb Sixseven", rankIndex = 0, level = 18, online = true, class = "PRIEST" })
    table.insert(STUB.guild, { name = "Tam One", rankIndex = 3, level = 5, online = false, class = "MAGE" })
    table.insert(STUB.guild, { name = "Tam Two", rankIndex = 3, level = 5, online = false, class = "MAGE" })
    ns.Roster:ScanGuild()
    local A = ns.Attendance
    check(A:Key("Flyne") == "Flyne Lee" and A:Key("Flyne Lee") == "Flyne Lee", "names: a bare first name finds its guild member")
    check(A:Key("Keeb") == "Keeb Sixseven", "names: of two with the same first name, the online one")
    check(A:Key("Tam") == "Tam" and A:Key("Stranger") == "Stranger", "names: ambiguous or unknown names are left alone")
    check(ns.Loot:ParseChat("Flyne receives loot: " .. STUB.Link(19019, "Thunderfury") .. ".") == "Flyne"
        and A:Key(ns.Loot:ParseChat("Flyne receives loot: " .. STUB.Link(19019, "Thunderfury") .. ".")) == "Flyne Lee",
        "names: a loot line's first name is logged under the full name")
    for _ = 1, 5 do table.remove(STUB.guild, n + 1) end
    ns.Roster:ScanGuild()

    -- a loading screen: show our fingerprint again soon, at most once a minute
    local function fingerprints()
        local k = 0
        for _, m in ipairs(STUB.sent) do
            if m.text:sub(1, 1) == "Y" and m.text:sub(4, 4) == "A" and m.text:sub(6, 6) == "F" then k = k + 1 end
        end
        return k
    end
    ns.Sync.missedAt = nil
    STUB.sent = {}
    STUB.Fire("PLAYER_ENTERING_WORLD", true, false)
    STUB.Advance(20)
    check(fingerprints() == 0, "catch-up: logging in doesn't count as a missed moment")
    STUB.Fire("PLAYER_ENTERING_WORLD", false, false)
    STUB.Advance(20)
    check(fingerprints() == 1, "catch-up: after a loading screen we show our fingerprint")
    STUB.Fire("PLAYER_ENTERING_WORLD", false, false)
    STUB.Advance(20)
    check(fingerprints() == 1, "catch-up: at most once a minute")

    -- a multi-part message that never finishes means we missed something
    STUB.Advance(61)
    STUB.sent = {}
    STUB.Fire("CHAT_MSG_ADDON", "PogRaid", "YQzAB" .. ("x"):rep(240), "GUILD", "Raider03-Realm")
    STUB.Advance(32)
    STUB.Advance(16)
    check(fingerprints() == 1 and (ns.Comm.stats.lost or 0) >= 1, "catch-up: an incomplete message brings a fingerprint")
    STUB.sent = {}
end

-- Wishlist ---------------------------------------------------------------------------------
do
    local D = ns.Wishlist
    local Sync = ns.Sync
    STUB.bags, STUB.worn = {}, {}
    STUB.equip = { [9001] = "INVTYPE_CLOAK", [9002] = "INVTYPE_FINGER", [9010] = "INVTYPE_FINGER", [9011] = "INVTYPE_FINGER",
        [9012] = "INVTYPE_FINGER", [9004] = "INVTYPE_WEAPON", [9005] = "INVTYPE_FEET", [9006] = "INVTYPE_WAIST",
        [9100] = "INVTYPE_HEAD", [9050] = "", [9007] = "INVTYPE_CLOAK", [9008] = "INVTYPE_CLOAK" }
    local ILVL = { [9001] = 20, [9007] = 25, [9003] = 22, [9005] = 24 }
    local requested = {}
    C_Item = C_Item or {}
    C_Item.GetItemCount = function(id) return STUB.bags[id] or 0 end
    C_Item.GetItemIconByID = function(id) return 1000 + id end
    C_Item.GetItemInfoInstant = function(id)
        if STUB.equip[id] then return id, "Armor", "Cloth", STUB.equip[id], 1000 + id end
    end
    C_Item.GetItemInfo = function(id)
        if ILVL[id] then return "Item " .. id, STUB.Link(id, "Item " .. id, "1eff00"), 2, ILVL[id] end
    end
    C_Item.RequestLoadItemDataByID = function(id) requested[id] = true end
    GetInventoryItemID = function(unit, slot) return STUB.worn[slot] end
    ForeverDungeonJournal_NS = nil

    ns.Editor:ShowTab("wishlist")
    local doll, side, browse = D.doll, D.side, D.browse
    local function slotB(id)
        for _, b in ipairs(doll.slots) do if b.slot.id == id then return b end end
    end
    local function sideRow(name)
        for _, r in ipairs(side.rows) do if r.name:GetText() == name then return r end end
    end
    check(doll:IsShown() and not browse:IsShown() and #doll.slots == 17 and D.title:GetText() == "Wishlist 1"
        and D.meta == nil and side.rows[2].count == nil and side.note:IsShown(),
        "wishlist: its own tab, a sheet of 17 empty slots, no counts")
    local names = {}
    for i, r in ipairs(side.rows) do names[i] = r.name:GetText() end
    check(D.addBox.placeholder:GetText() == "Search...", "wishlist: the box says Search...")
    check(table.concat(names, ",") == "Wishlist 1,Where to get them,Head,Neck,Shoulder,Back,Chest,Wrist,Hands,Waist,Legs,Feet,Finger,Trinket,Main Hand,Off Hand,Ranged"
        and side.rows[3].icon.__texture == "slot-HeadSlot",
        "wishlist: the side lists the wishlist we're on, where to get them (0.16), then each kind of slot")
    check(slotB(1).name:GetText() == "Head" and slotB(1).icon.__texture == "slot-HeadSlot" and not slotB(1).check:IsShown(),
        "wishlist: empty slots show the game's empty slot art and their name")

    -- layout: two mirrored columns, evenly spaced, the model between them
    local cl, ct, cw, ch = STUB.rect(D.card)
    local L = D.layout
    local okCols = true
    local n = { 0, 0, 0 }
    for _, b in ipairs(doll.slots) do
        local side_ = b.slot.side
        n[side_] = n[side_] + 1
        if side_ ~= 3 then
            local _, t = STUB.rect(b)
            local il = STUB.rect(b.icon)
            local want = side_ == 1 and cl + L.EDGE or cl + cw - L.EDGE - L.SLOT
            if not near(il, want) or not near(ct - t, L.SLOT_TOP + (n[side_] - 1) * L.PITCH) then okCols = false end
        end
    end
    check(okCols and n[1] == 7 and n[2] == 7 and n[3] == 3 and slotB(10).slot.side == 1,
        "wishlist: 7 armour slots a side (Hands on the left), 16px from the card's edges")
    -- the weapons: a row along the bottom, like the character pane (0.16.5; Ranged used to hang alone under the left column)
    local mhI, mhT = STUB.rect(slotB(16).icon)
    local _, ohT = STUB.rect(slotB(17))
    local ohL, _, ohW = STUB.rect(slotB(17))
    local ohI = STUB.rect(slotB(17).icon)
    local rI, rT = STUB.rect(slotB(18).icon)
    local rowY = L.SLOT_TOP + 8 * L.PITCH
    local _, mhBT = STUB.rect(slotB(16))
    local _, rBT = STUB.rect(slotB(18))
    check(near(ct - mhBT, rowY) and near(ct - ohT, rowY) and near(ct - rBT, rowY), "wishlist: the three weapons share the bottom row")
    check(near(mhI, cl + L.EDGE) and near(rI, cl + cw - L.EDGE - L.SLOT) and near(ohL + ohW / 2, cl + cw / 2, 0.5) and near(ohI, ohL),
        "wishlist: Main Hand under the left column, Ranged under the right, Off Hand centred")
    check(slotB(16).name.__justifyH == "LEFT" and slotB(17).name.__justifyH == "LEFT" and slotB(18).name.__justifyH == "RIGHT"
        and mhI + L.SLOT + 10 + 140 <= ohL and ohL + ohW <= rI - 10 - 140 + 0.5,
        "wishlist: their names don't run into each other (Ranged mirrored like the right column)")
    check(near(L.SLOT_TOP, ch - (L.SLOT_TOP + 8 * L.PITCH + L.SLOT), 1), "wishlist: the columns are centred top to bottom")
    local model = doll.model
    local ml, mt, mw = STUB.rect(model)
    check(model and ml >= cl + L.EDGE + L.SLOT and ml + mw <= cl + cw - L.EDGE - L.SLOT and near((ml - cl) + mw / 2, cw / 2)
        and mw >= 400, "wishlist: the model spans the space between the icons, centred (wide shoulders don't clip)")
    check(model:GetFrameLevel() < slotB(1):GetFrameLevel() and model:GetFrameLevel() < slotB(10):GetFrameLevel(),
        "wishlist: the model sits behind the slots, so their names and clicks stay on top")
    check(model.__unit == "player", "wishlist: the model is your character")
    -- the art fills the whole card, behind the slots too
    C_Texture = { GetAtlasInfo = function(name)
        if name:find("^dressingroom%-background%-") then return { file = 55, width = 400, height = 600,
            leftTexCoord = 0, rightTexCoord = 1, topTexCoord = 0, bottomTexCoord = 1 } end
    end }
    D:Refresh()
    local art = D.backdrop.art
    local al, at, aw, ah = STUB.rect(art)
    check(art:IsShown() and art.__texture == 55 and near(al, cl) and near(at, ct) and near(aw, cw) and near(ah, ch)
        and doll.backdrop == nil, "wishlist: the art fills the whole card, item slots included")
    C_Texture = nil
    D:Refresh()

    -- shift-click while the box has focus: the item goes to its slot
    D.addBox:SetFocus()
    ChatEdit_InsertLink(STUB.Link(9001, "Cape of the Wanderer", "0070dd"))
    local mine = D:Mine()
    local back = slotB(15)
    check(#mine == 1 and mine[1].id == 9001 and mine[1].slot == 15 and not mine[1].got, "wishlist: a shift-clicked cape goes in the Back slot")
    check(back.name:GetText():find("Cape of the Wanderer", 1, true) and back.name:GetText():find("0070dd", 1, true)
        and back.icon.__texture == 10001 and near(back.border.__color[3], 0xdd / 255, 0.01) and near(back.border.__color[1], 0, 0.01),
        "wishlist: the slot shows the icon, the quality-coloured name and border")
    check(model.__tried[#model.__tried]:find("Hitem:9001", 1, true),
        "wishlist: the model tries the item on")
    local dressings = model.__dressed
    D:Refresh()
    check(model.__dressed == dressings, "wishlist: the model is only dressed again when the list changes")
    STUB.printed = {}
    D.addBox:SetText(STUB.Link(9001, "Cape of the Wanderer", "0070dd"))
    check(#mine == 1 and D.addBox:GetText() == "" and #STUB.printed == 0, "wishlist: the same click reaching the box adds nothing more")
    STUB.Advance(2)
    D.addBox:SetText(STUB.Link(9001, "Cape of the Wanderer", "0070dd"))
    check(#mine == 1 and printedContains("already on your wishlist"), "wishlist: adding it again later says it's there")
    D.addBox:SetText(STUB.Link(9050, "Linen Cloth", "ffffff"))
    check(#mine == 1 and printedContains("only gear goes on your wishlist"), "wishlist: only gear")
    D.addBox:ClearFocus()
    ChatEdit_InsertLink(STUB.Link(9002, "Ring", "1eff00"))
    check(#mine == 1, "wishlist: shift-clicks into chat don't add")

    -- rings fill both finger slots, then replace the first
    D:AddLink(STUB.Link(9010, "Ring A"))
    D:AddLink(STUB.Link(9011, "Ring B"))
    check(D:Find(9010).slot == 11 and D:Find(9011).slot == 12, "wishlist: two rings take both finger slots")
    STUB.printed = {}
    D:AddLink(STUB.Link(9012, "Ring C"))
    check(not D:Find(9010) and D:Find(9012).slot == 11 and printedContains("replaces"), "wishlist: a third ring replaces the first")
    D:Remove(9011)
    D:Remove(9012)

    -- shared: what we still want, by item ID
    local function shared() return D:WantedBy(Sync:Me()) end
    check(#shared() == 1 and shared()[1] == 9001, "wishlist: shared with the guild")
    local rec = Sync:Store("wish")[Sync:Me()]
    check(rec and rec.id == Sync:Me() and #rec.ids == 4, "wishlist: one record per player, 4 characters an item")

    -- the journal: where things drop, and every item for a slot
    ForeverDungeonJournal_NS = { DB = {
        ["The Stockade"] = { level = "22-30", bosses = {
            { name = "Bazil Thredd", loot = { { 9001, "Cape of the Wanderer", "Back", 3 }, { 9003, "Bracers", "Wrist, Cloth", 2 },
                { 9060, "Prison Key", "Quest Item", 1 } } },
            { name = "Trash Drops", trash = true, loot = { { 9004, "Dagger", "One-Hand, Dagger", 2 }, { 9008, "Old Cloak", "Back", 2 } } },
        }, quests = { { id = 1, name = "The Fury Runs Deep", rewardItems = { { 9005, "Boots", 2 } } } } },
        ["Ragefire Chasm"] = { level = "13-18", bosses = { { name = "Taragaman", loot = { { 9006, "Belt", "Waist", 3 },
            { 9007, "Fiery Cloak", "Back", 3 } } } } },
    } }
    D:Refresh()
    check(back.sub:GetText() == "Bazil Thredd, The Stockade", "wishlist: each item says where it drops")
    check(not side.note:IsShown() and D.Counts == nil, "wishlist: with the journal, the note goes (and nothing counts the journal)")
    STUB.Script(sideRow("Back"), "OnClick")
    check(D.list.name == "Back" and D.title:GetText() == "Back" and browse.rows[3]:IsShown() and not browse.rows[4]:IsShown() and browse:IsShown()
        and not doll:IsShown() and not D.backdrop.glow:IsShown(), "wishlist: picking a slot lists its items")
    local order = {}
    for i = 1, 3 do order[i] = browse.rows[i].data.id end
    check(table.concat(order, ",") == "9007,9001,9008" and browse.rows[1].right:GetText() == "ilvl 25"
        and browse.rows[3].right:GetText() == "" and requested[9008], "wishlist: best item level first, unknown last (and asked for)")
    check(browse.rows[1].sub:GetText() == "Taragaman, Ragefire Chasm" and browse.rows[3].sub:GetText() == "Trash, The Stockade"
        and browse.rows[2].right2:GetText() == "on your wishlist" and browse.rows[1].right2:GetText() == "Cloth",
        "wishlist: where each drops, ours marked, the kind of item")
    STUB.Script(browse.rows[1], "OnEnter")
    check(GameTooltip.lines[#GameTooltip.lines] == "Taragaman, Ragefire Chasm", "wishlist: the tooltip says where it drops")
    STUB.printed = {}
    STUB.Script(browse.rows[1], "OnClick", "LeftButton")
    check(D:Find(9007) and D:Find(9007).slot == 15 and not D:Find(9001) and printedContains("replaces")
        and browse.rows[1].right2:GetText() == "on your wishlist", "wishlist: clicking an item puts it in its slot")
    STUB.Script(browse.rows[1], "OnClick", "LeftButton")
    check(not D:Find(9007), "wishlist: clicking it again takes it off")
    STUB.Script(browse.rows[2], "OnClick", "LeftButton")
    check(D:Find(9001) and D:Find(9001).slot == 15, "wishlist: (the cape back on)")

    -- searching: gear by name, best item level first
    D.addBox:SetText("cloak")
    check(D.search == "cloak" and browse:IsShown() and D.title:GetText() == 'Search: "cloak"'
        and browse.rows[1].data.id == 9007 and browse.rows[2].data.id == 9008 and not browse.rows[3]:IsShown()
        and not sideRow("Back").sel:IsShown(), "wishlist: Search finds gear by name")
    D.addBox:SetText("c")
    check(D.search == nil, "wishlist: (two letters at least)")
    D.addBox:SetText("zzz")
    check(browse.empty:IsShown() and browse.empty:GetText() == "No gear by that name.", "wishlist: nothing found says so")
    D.addBox:SetText("prison")
    check(not browse.rows[1]:IsShown(), "wishlist: search finds gear only")
    STUB.Script(sideRow("Head"), "OnClick")
    check(D.addBox:GetText() == "" and D.search == nil and D.list.name == "Head", "wishlist: picking a slot clears the search")
    D.addBox:SetText("cape")
    D.addBox:SetText("")
    check(D.search == nil and D.list.name == "Head", "wishlist: clearing the search goes back")

    -- the sheet: an empty slot opens its list, an item's menu can too
    STUB.Script(sideRow("Wishlist 1"), "OnClick")
    check(D.list == nil and doll:IsShown() and D.backdrop.glow:IsShown(), "wishlist: back to the sheet")
    STUB.Script(slotB(8), "OnClick", "LeftButton")
    check(D.list and D.list.name == "Feet" and browse.rows[1].data.id == 9005
        and browse.rows[1].sub:GetText() == "Quest: The Fury Runs Deep, The Stockade", "wishlist: an empty slot opens its list")
    STUB.Script(browse.rows[1], "OnClick", "LeftButton")
    check(D:Find(9005) and D:Find(9005).slot == 8, "wishlist: (boots on)")
    STUB.Script(slotB(12), "OnClick", "LeftButton")
    check(D.list.name == "Finger", "wishlist: the second ring slot opens the rings")
    STUB.Script(sideRow("Wishlist 1"), "OnClick")
    local entries
    local show = ns.UI.ShowMenu
    ns.UI.ShowMenu = function(_, e) entries = e end
    STUB.Script(back, "OnClick", "LeftButton")
    ns.UI.ShowMenu = show
    local browseEntry
    for _, e in ipairs(entries or {}) do if e.text == "Browse Back" then browseEntry = e end end
    check(browseEntry ~= nil, "wishlist: an item's menu offers its slot's list")
    browseEntry.func()
    check(D.list.name == "Back", "wishlist: and opens it")
    STUB.Script(sideRow("Wishlist 1"), "OnClick")

    -- getting it checks it off; the guild sees only what's still wanted
    STUB.bags[9001] = 1
    STUB.Fire("BAG_UPDATE_DELAYED")
    STUB.Advance(2)
    check(D:Find(9001).got and printedContains("wishlist: got"), "wishlist: an item in your bags checks itself off")
    check(#shared() == 1 and shared()[1] == 9005, "wishlist: got items aren't shared")
    check(back.check:IsShown() and back.sub:GetText() == "Got it",
        "wishlist: got items are ticked")
    STUB.worn[8] = 9005
    STUB.Fire("PLAYER_EQUIPMENT_CHANGED", 8)
    STUB.Advance(2)
    check(D:Find(9005).got, "wishlist: equipping it counts too")
    check(Sync:Store("wish")[Sync:Me()].ids == nil and #shared() == 0, "wishlist: nothing left to share")
    D:SetGot(9001, false)
    check(not D:Find(9001).got and shared()[1] == 9001, "wishlist: marked not got again")
    STUB.bags[9001] = nil

    -- adding something you already have arrives checked off
    STUB.bags[9100] = 1
    D:AddLink(STUB.Link(9100, "Already Mine"))
    check(D:Find(9100).got and D:Find(9100).slot == 1, "wishlist: something you have already is checked off")
    D:Remove(9100)
    check(not D:Find(9100) and slotB(1).name:GetText() == "Head", "wishlist: removed")
    STUB.Script(back, "OnEnter")
    check(GameTooltip.link and GameTooltip.link:find("Hitem:9001", 1, true), "wishlist: hovering an item shows its tooltip")

    -- other people's lists arrive and are checked
    local def = Sync.collections.wish
    local function try(r) return Sync:Apply(def, r, true) end
    check(try({ id = "Raider03-Realm", author = "Raider03-Realm", by = "Raider03-Realm", rev = 10, t = 1, ids = ns.Crafting.Pack({ 9003, 9006 }) }),
        "wishlist: a guildie's list is accepted")
    check(#D:WantedBy("Raider03-Realm") == 2 and D:WantedBy("Raider03-Realm")[2] == 9006, "wishlist: and read back")
    check(not try({ id = "Raider03-Realm", author = "Raider03-Realm", by = "Someone-Realm", rev = 11, t = 1, ids = "AAAA" }),
        "wishlist: nobody writes another player's list")
    check(not try({ id = "Raider04-Realm", author = "Raider04-Realm", by = "Raider04-Realm", rev = 11, t = 1, ids = "AAA" }),
        "wishlist: malformed lists are refused")
    check(not try({ id = "Raider04-Realm", author = "Raider04-Realm", by = "Raider04-Realm", rev = 11, t = 1, ids = ("AAAA"):rep(D.MAX + 1) }),
        "wishlist: over-long lists are refused")

    -- lists from before the sheet get slots (or lose what has none)
    local list = D:Mine()
    table.insert(list, { id = 9006, link = STUB.Link(9006, "Belt"), t = 1 })
    table.insert(list, { id = 9050, link = STUB.Link(9050, "Linen Cloth"), t = 1 })
    D:Mine()
    check(D:Find(9006) and D:Find(9006).slot == 6 and not D:Find(9050), "wishlist: older lists move into slots")

    -- up to three wishlists, made from the Wishlists menu: each its own sheet;
    -- the guild sees what we want on any of them
    local first = #D:Mine()
    local showMenu, menu = ns.UI.ShowMenu, nil
    ns.UI.ShowMenu = function(_, entries) menu = entries end
    local function menuText()
        local t = {}
        for _, e in ipairs(menu) do t[#t + 1] = e.text end
        return table.concat(t, ",")
    end
    local function pick(text)
        for _, e in ipairs(menu) do
            if e.text == text then
                menu = nil
                if e.func then e.func() end
                return true
            end
        end
    end
    local function openMenu() menu = nil; STUB.Script(D.setsBtn, "OnClick") end
    openMenu()
    check(#D:Data().sets == 1 and menuText() == "Wishlists,> Wishlist 1,New wishlist,Rename this one...",
        "wishlist: one list until we make another (no delete for the last)")
    STUB.Script(sideRow("Head"), "OnClick")
    openMenu()
    pick("New wishlist")
    check(#D:Data().sets == 2 and D:Data().cur == 2 and #D:Mine() == 0 and D.title:GetText() == "Wishlist 2"
        and sideRow("Wishlist 2") and sideRow("Wishlist 2").sel:IsShown() and not sideRow("Wishlist 1")
        and D.doll:IsShown() and slotB(15).name:GetText() == "Back", "wishlist: New makes a second, empty, on the sheet")
    D:AddLink(STUB.Link(9007, "Fiery Cloak"))
    check(D:Find(9007) and D:Find(9007).slot == 15 and slotB(15).name:GetText():find("Fiery Cloak", 1, true)
        and sideRow("Wishlist 2") ~= nil, "wishlist: its own items")
    -- item tooltips: the game's "Currently equipped" comparison only with Shift
    local cloak = slotB(15)
    STUB.hover = cloak
    STUB.Script(cloak, "OnEnter")
    check(GameTooltip.shown and GameTooltip.link:find("Fiery Cloak", 1, true) and not ShoppingTooltip1:IsShown(),
        "item tooltips: no comparison without Shift")
    STUB.shift = true
    STUB.Fire("MODIFIER_STATE_CHANGED", "LSHIFT", 1)
    check(GameTooltip.shown and ShoppingTooltip1:IsShown(), "item tooltips: Shift shows what's equipped")
    STUB.shift = false
    STUB.Fire("MODIFIER_STATE_CHANGED", "LSHIFT", 0)
    check(GameTooltip.shown and not ShoppingTooltip1:IsShown(), "item tooltips: letting go hides it again")
    GameTooltip:AddLine("still here")
    STUB.Fire("MODIFIER_STATE_CHANGED", "LCTRL", 1)
    check(not ShoppingTooltip1:IsShown() and GameTooltip.lines[#GameTooltip.lines] == "still here", "item tooltips: other keys leave it")
    GameTooltip:SetOwner(CreateFrame("Frame"), "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(STUB.Link(9007, "Fiery Cloak"))
    check(ShoppingTooltip1:IsShown(), "item tooltips: the game's own tooltips are left alone")
    GameTooltip:Hide()
    STUB.hover = nil
    local wanted = {}
    for _, id in ipairs(D:WantedBy(Sync:Me())) do wanted[id] = true end
    check(wanted[9007] and wanted[9001], "wishlist: the guild sees what we want on all of them")
    -- rename
    local compose, saveName = ns.UI.Compose, nil
    ns.UI.Compose = function(opts, fn) saveName = fn end
    openMenu()
    pick("Rename this one...")
    ns.UI.Compose = compose
    saveName("Healing set")
    openMenu()
    check(sideRow("Healing set") and D.title:GetText() == "Healing set" and D:Data().cur == 2
        and menuText() == "Wishlists,   Wishlist 1,> Healing set,New wishlist,Rename this one...,Delete this one", "wishlist: the menu renames one")
    saveName("")
    check(sideRow("Wishlist 2") ~= nil, "wishlist: an empty name goes back to the default")
    -- switch
    pick("   Wishlist 1")
    check(D:Data().cur == 1 and #D:Mine() == first and sideRow("Wishlist 1"), "wishlist: the menu switches lists")
    -- a third, and no more
    openMenu()
    pick("New wishlist")
    openMenu()
    check(#D:Data().sets == 3 and D:Data().cur == 3 and not menuText():find("New wishlist", 1, true), "wishlist: three at most")
    check(not D:NewSet() and #D:Data().sets == 3, "wishlist: no fourth")
    -- got on one list counts everywhere it's on
    D:AddLink(STUB.Link(9001, "Cape of the Wanderer", "0070dd"))
    local times = 0
    for _, id in ipairs(D:WantedBy(Sync:Me())) do if id == 9001 then times = times + 1 end end
    check(times == 1, "wishlist: an item on two lists is shared once")
    STUB.bags[9001] = 1
    STUB.printed = {}
    D:CheckOwned()
    local saidOnce = 0
    for _, m in ipairs(STUB.printed) do if m:find("wishlist: got", 1, true) then saidOnce = saidOnce + 1 end end
    check(D:Find(9001).got and D:Data().sets[1].items[1].got and saidOnce == 1, "wishlist: getting it ticks every list, said once")
    STUB.bags[9001] = nil
    -- delete (asks first), never the last
    openMenu()
    pick("Delete this one")
    check(#D:Data().sets == 3 and menuText() == "Delete Wishlist 3?,Sure? Delete it,Keep it", "wishlist: delete asks first")
    pick("Keep it")
    check(#D:Data().sets == 3, "wishlist: Keep it keeps it")
    openMenu()
    pick("Delete this one")
    pick("Sure? Delete it")
    check(#D:Data().sets == 2 and D:Data().cur == 2 and D:Find(9007), "wishlist: deleted, on to the one before")
    wanted = {}
    for _, id in ipairs(D:WantedBy(Sync:Me())) do wanted[id] = true end
    check(wanted[9007], "wishlist: what we still want on the others stays shared")
    openMenu()
    pick("Delete this one")
    pick("Sure? Delete it")
    check(#D:Data().sets == 1 and D:Data().cur == 1 and #D:Mine() == first, "wishlist: back to the first, as it was")
    wanted = {}
    for _, id in ipairs(D:WantedBy(Sync:Me())) do wanted[id] = true end
    check(not wanted[9007], "wishlist: a deleted list's items stop being shared")
    D:DeleteSet(1)
    check(#D:Data().sets == 1 and #D:Mine() == first, "wishlist: never the last one")
    -- deleting one before the one we're on keeps us on it
    local orig = D:Data().sets[1]
    D:NewSet()
    D:AddLink(STUB.Link(9007, "Fiery Cloak"))
    D:NewSet()
    D:UseSet(2)
    D:DeleteSet(1)
    check(#D:Data().sets == 2 and D:Data().cur == 1 and D:Find(9007), "wishlist: deleting an earlier one keeps ours")
    D:Data().sets = { orig }
    D:Data().cur = 1
    D:Publish()
    check(#D:Mine() == first, "wishlist: the first is untouched")
    ns.UI.ShowMenu = showMenu
    -- an old single list becomes the first
    local key = UnitGUID("player") or ns.PlayerName()
    local saved = ns.db.wishlist[key]
    ns.db.wishlist[key] = { { id = 9006, link = STUB.Link(9006, "Belt"), t = 1, slot = 6 } }
    check(#D:Data().sets == 1 and D:Data().cur == 1 and D:Mine()[1].id == 9006, "wishlist: an older list becomes Wishlist 1")
    ns.db.wishlist[key] = saved

    -- per character
    local oldGuid = STUB.guid
    STUB.guid = "Player-1-ALT"
    check(#D:Mine() == 0, "wishlist: each character has its own list")
    STUB.guid = oldGuid
end

-- LFG: groups and who's looking --------------------------------------------------------------
do
    local DG, Sync = ns.Dungeons, ns.Sync
    local me = Sync:Me()
    local level = 24
    UnitLevel = function(u) if u == "player" then return level end end
    C_Texture = { GetAtlasInfo = function(name)
        if name:find("^groupfinder%-icon%-role%-large%-") then return { file = 1, width = 64, height = 64 } end
    end }
    ForeverDungeonJournal_NS = nil -- the built-in list of dungeons

    ns.Editor:ShowTab("lfg")
    local you, dungeons, groups, lookingC = DG.you, DG.dungeons, DG.groups, DG.looking
    local function drow(name)
        for _, r in ipairs(dungeons.rows) do if r:IsShown() and r.name:GetText() == name then return r end end
    end
    check(DG.title == nil and DG.meta == nil and dungeons.rows[1].name:GetText() == "Hall of Thanes"
        and dungeons.rows[1].level:GetText() == "13-20" and dungeons.rows[1].box:IsShown(), "lfg: the dungeons by level, each with a tick box")
    -- in our level range or not
    local fits, far = drow("The Stockade"), drow("Scarlet Monastery: Library")
    local bfd = drow("Blackfathom Deeps")
    check(bfd and bfd.level:GetText() == "22-32", "lfg: Blackfathom Deeps shows 22-32, not the journal's open-ended 22+")
    ForeverDungeonJournal_NS = { DB = { ["Blackfathom Deeps"] = { level = "22+" }, ["The Stockade"] = { level = "24-32" },
        ["Cozy Sleeping Bag"] = { level = "14+", questChainPage = true } } }
    local fixed, bag
    for _, d in ipairs(DG:List()) do
        if d.name == "Blackfathom Deeps" then fixed = d end
        if d.name == "Cozy Sleeping Bag" then bag = d end
    end
    ForeverDungeonJournal_NS = nil
    check(#DG:List() > 0 and not bag, "lfg: the journal's quest-chain pages (Cozy Sleeping Bag) aren't dungeons")
    check(fixed and fixed.level == "22-32" and fixed.min == 22 and fixed.max == 32, "lfg: the journal's 22+ is shown as 22-32 too")
    check(fits.name.__textColor[1] == ns.UI.TEXT[1] and fits.name.__textColor[1] > far.name.__textColor[1] + 0.25
        and far.name.__textColor[1] < 0.6, "lfg: dungeons in our level range stand out")
    -- the level ranges line up on the right; Survival Hunter art behind the list
    local r1 = STUB.rect(dungeons.rows[1].level)
    local r2 = STUB.rect(dungeons.rows[7].level)
    local _, _, lw = STUB.rect(dungeons.rows[1].level)
    check(near(r1, r2) and dungeons.rows[1].level.__justifyH == "RIGHT" and lw == 40, "lfg: level ranges in one right-aligned column")
    check(dungeons.tex and dungeons.tex[1]:IsShown() and dungeons.tex[1].__texture == "Interface\\TalentFrame\\HunterBeastMastery-TopLeft"
        and near(dungeons.tex[1]:GetAlpha(), ns.Art.CARD_ALPHA), "lfg: Beast Mastery Hunter art behind the dungeon list")
    -- you: role buttons with the game's role icons
    local roles = {}
    for i, b in ipairs(you.roles) do roles[i] = b.label:GetText() end
    check(table.concat(roles, ",") == "Tank,Heals,DPS" and you.roles[1].icon.__atlas == "groupfinder-icon-role-large-tank"
        and you.roles[2].icon.__atlas == "groupfinder-icon-role-large-heal" and you.roles[3].icon.__atlas == "groupfinder-icon-role-large-dps"
        and you.meta:GetText() == "Not looking" and not you.stop:IsShown(), "lfg: you, with Tank, Heals and DPS")
    -- roles: from our profile (main role and off spec) until we pick; any of the three, at least one
    ns.db.lookRole = nil
    local content = ns.Profiles:Mine().content
    local savedRole, savedOff = content.role, content.off
    content.role, content.off = "H", "D"
    check(DG:Role() == "HD", "lfg: our roles start as our main role and off spec")
    ns.db.lookRole = "D"
    DG:Refresh()
    STUB.Script(you.roles[1], "OnClick") -- Tank on
    check(DG:Role() == "TD" and you.roles[1].selected and you.roles[3].selected and not you.roles[2].selected,
        "lfg: more than one role")
    STUB.Script(you.roles[3], "OnClick") -- DPS off
    check(DG:Role() == "T", "lfg: a role clicked again comes off")
    STUB.Script(you.roles[1], "OnClick") -- 0.16: the last one comes off too
    check(DG:Role() == "", "lfg: the last role can come off too")
    STUB.Script(you.roles[1], "OnClick") -- Tank back on
    STUB.Script(you.roles[2], "OnClick") -- Heals on: TH
    content.role, content.off = savedRole, savedOff
    local pickB = { key = "TH" }

    -- tick a dungeon: looking
    STUB.Script(fits.box, "OnClick")
    local rec = Sync:Store("lfd")[me]
    check(rec and rec.list == "The Stockade" and rec.role == pickB.key and fits.box.mark:IsShown()
        and you.stop:IsShown() and not you.meta:IsShown() and dungeons.meta:GetText() == "Looking",
        "lfg: ticking a dungeon puts us down for it")
    STUB.Script(drow("The Deadmines"), "OnClick")
    check(Sync:Store("lfd")[me].list == "The Stockade,The Deadmines" and drow("The Deadmines").box.mark:IsShown(),
        "lfg: clicking a dungeon's name ticks it too (more than one at once)")
    STUB.Script(drow("Gnomeregan"), "OnClick")
    STUB.Script(drow("Gnomeregan"), "OnClick")
    check(Sync:Store("lfd")[me].list == "The Stockade,The Deadmines" and not drow("Gnomeregan").box.mark:IsShown(),
        "lfg: clicking it again unticks it")
    -- a note
    you.note:SetText("LF tank, have quests")
    STUB.Script(you.note, "OnEnterPressed")
    check(Sync:Store("lfd")[me].note == "LF tank, have quests" or Sync:Store("lfd")[me].note == "LF tank have quests",
        "lfg: our note is shared")
    local l1 = lookingC.rows[1]
    check(l1:IsShown() and l1.item.name == me and l1.roles[1].__atlas == DG.ROLE_ATLAS.TANK[1]
        and l1.roles[2].__atlas == DG.ROLE_ATLAS.HEALER[1] and l1.roles[2]:IsShown() and l1.roles[1]:GetAlpha() == 1
        and l1.roles[3]:IsShown() and l1.roles[3]:GetAlpha() == DG.ROLE_OFF_ALPHA -- 0.16: all three in place, DPS greyed
        and l1.sub:GetText():find("The Stockade, The Deadmines", 1, true) and l1.sub:GetText():find("have quests", 1, true)
        and l1.right:GetText() == "online" and l1.right2 == nil, "lfg: we're listed with both roles, dungeons and note (no time left)")

    -- others: those after the same dungeons as us first
    local def = Sync.collections.lfd
    local now = ns.Now()
    local function lrec(name, list, over)
        local r = { id = name, author = name, by = name, rev = now, t = now, exp = now + 3600, list = list, role = "H" }
        for k, v in pairs(over or {}) do r[k] = v end
        return r
    end
    Sync:Apply(def, lrec("Raider05-Realm", "Ragefire Chasm"), true)
    Sync:Apply(def, lrec("Raider06-Realm", "Wailing Caverns,The Deadmines", { role = "T" }), true)
    DG:Refresh()
    check(lookingC.rows[2].item.name == "Raider06-Realm" and lookingC.rows[3].item.name == "Raider05-Realm"
        and lookingC.rows[2].sub:GetText():find(ns.UI.AccentCode() .. "The Deadmines|r", 1, true) and ns.UI.AccentCode() == "|cffffd100", "lfg: the ones after our dungeons come first, those marked")
    check(drow("The Deadmines").count == nil, "lfg: no counts beside the dungeons")
    check(not Sync:Apply(def, lrec("Raider07-Realm", "X", { note = ("n"):rep(41) }), true)
        and not Sync:Apply(def, lrec("Raider07-Realm", "X", { note = "a|cffff0000b" }), true)
        and not Sync:Apply(def, lrec("Raider07-Realm", "X", { by = "Someone-Realm" }), true)
        and not Sync:Apply(def, lrec("Raider07-Realm", "X", { exp = now + 9 * 3600 }), true)
        and not Sync:Apply(def, lrec("Raider07-Realm", "A|B"), true) and not Sync:Apply(def, lrec("Raider07-Realm", "X", { role = "Q" }), true),
        "lfg: odd records are refused")

    -- groups as tiles
    ns.Social:PostGroup("SFK run", "a healer", "")
    DG:Refresh()
    local t1 = groups.tiles[1]
    check(t1:IsShown() and t1.what:GetText() == "SFK run" and t1.who:GetText():find("needs a healer", 1, true)
        and t1.slots[1]:IsShown() and t1.slots[1].__w == DG.SLOT and t1.slots[2]:IsShown() and t1.slots[2].__w == 10 -- 0.16: role icon, then empty-slot dots
        and t1.join.label:GetText() == "Manage" and t1.edge:IsShown(), "lfg: a group as a tile (ours: Manage)")
    local entries
    local show = ns.UI.ShowMenu
    ns.UI.ShowMenu = function(_, e) entries = e end
    STUB.Script(t1.join, "OnClick")
    ns.UI.ShowMenu = show
    check(entries and entries[#entries].text == "Close my group", "lfg: Manage has the group finder's menu")
    -- someone else's: Join
    local lfg = Sync.collections.lfg
    Sync:Apply(lfg, { id = "g-1", author = "Raider05-Realm", by = "Raider05-Realm", rev = now, t = now, what = "Deadmines",
        exp = now + 1800, size = 2, max = 5 }, true)
    DG:Refresh()
    local other
    for _, t in ipairs(groups.tiles) do if t:IsShown() and t.item.id == "g-1" then other = t end end
    check(other and other.join.label:GetText() == "Join" and not other.edge:IsShown() and other.left:GetText() == "30m left",
        "lfg: someone else's group has Join")
    STUB.Script(other.join, "OnClick")
    check(ns.Social.requested["g-1"] and other.join.label:GetText() == "Requested" and not other.join:IsEnabled(),
        "lfg: Join asks to join")

    ns.Social:Remove("lfg", ns.Social:MyGroup())
    local prefill
    local compose = ns.UI.Compose
    ns.UI.Compose = function(opts) prefill = opts.text1 end
    STUB.Script(DG.groups.quiet.post, "OnClick") -- 0.16: on the empty Groups card
    ns.UI.Compose = compose
    check(prefill == "", "lfg: Post a group opens the group finder's dialog")
    local _, pgT = STUB.rect(DG.page)
    local _, gT = STUB.rect(DG.groups)
    local _, yT = STUB.rect(DG.you)
    check(DG.postBtn == nil and DG.groups.quiet.post.label:GetText() == "Post a group" and near(pgT - gT, 30)
        and near(pgT - yT, 30), "lfg: no title bar: both columns start at the top, Post a group on the empty Groups card")

    -- stop, and running out
    STUB.Script(you.stop, "OnClick")
    check(DG:MyLooking() == nil and Sync:Store("lfd")[me].deleted and not you.stop:IsShown(), "lfg: Stop looking")
    STUB.Advance(3601)
    check(#DG:LookingFor("Ragefire Chasm") == 0, "lfg: others drop off when their time runs out")
    -- without the large role icons: the classic round ones
    C_Texture = nil
    local tex = CreateFrame("Frame"):CreateTexture()
    DG.RoleIcon(tex, "T")
    check(tex.__texture == "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES", "lfg: the classic role icons when there are no large ones")
    UnitLevel = nil
end

-- Gear: what everyone wears, profiles' Character card, Inspect --------------------------
do
    local Gear, P, D, UI = ns.Gear, ns.Profiles, ns.Wishlist, ns.UI
    local Sync = ns.Sync
    local me = Sync:Me()
    STUB.worn = {}
    local NAMES = { [5001] = "Helm of Testing", [5016] = "Sword of Testing", [5005] = "Robe of Testing" }
    C_Item.GetItemInfo = function(id)
        if NAMES[id] then return NAMES[id], STUB.Link(id, NAMES[id], "1eff00") end
    end
    STUB.equip[5001], STUB.equip[5016], STUB.equip[5005] = "INVTYPE_HEAD", "INVTYPE_WEAPON", "INVTYPE_ROBE"

    -- packing
    local packed = Gear.Pack({ [1] = 5001, [16] = 5016, [19] = 16777215 })
    local back = Gear.Unpack(packed)
    check(#packed == 76 and back[1] == 5001 and back[16] == 5016 and back[19] == 16777215 and back[2] == nil,
        "gear: 19 slots, 4 characters each, empty slots stay empty")

    -- shared a little after a gear change, once it settles
    STUB.worn = { [1] = 5001, [16] = 5016 }
    STUB.Fire("PLAYER_EQUIPMENT_CHANGED", 1)
    STUB.Advance(10)
    STUB.worn[5] = 5005
    STUB.Fire("PLAYER_EQUIPMENT_CHANGED", 5)
    STUB.Advance(25)
    local mine = Gear:Record(me)
    check(mine and Gear.Unpack(mine.items)[5] ~= 5005, "gear: not shared while gear is still changing")
    STUB.Advance(10)
    mine = Gear:Record(me)
    local ids = Gear.Unpack(mine.items)
    check(ids[1] == 5001 and ids[16] == 5016 and ids[5] == 5005 and mine.race == 7 and mine.sex == 2 and mine.id == me,
        "gear: our gear, race and sex are shared")
    local rev = mine.rev
    Gear:Publish()
    check(Gear:Record(me).rev == rev, "gear: nothing new, nothing sent")

    -- records from others are checked
    local def = Sync.collections.gear
    local function try(r) return Sync:Apply(def, r, true) end
    local function rec(over)
        local r = { id = "Raider03-Realm", author = "Raider03-Realm", by = "Raider03-Realm", rev = 50, t = ns.Now() - 7200,
            items = Gear.Pack({ [1] = 5001, [5] = 5005 }), race = 1, sex = 3 }
        for k, v in pairs(over or {}) do r[k] = v end
        return r
    end
    check(not try(rec({ by = "Someone-Realm" })), "gear: nobody shares another player's gear")
    check(not try(rec({ items = "AAAA" })), "gear: malformed gear is refused")
    check(not try(rec({ race = 1.5 })) and not try(rec({ sex = 1 })), "gear: odd race or sex is refused")
    check(try(rec()), "gear: a guildie's gear is accepted")
    check(not P:HasAddon("Newbie-Realm"), "gear: (someone we know nothing about)")
    try(rec({ id = "Newbie-Realm", author = "Newbie-Realm", by = "Newbie-Realm", rev = ns.Now() + 300 }))
    check(P:HasAddon("Newbie-Realm"), "gear: sharing gear shows they run the addon")

    -- which character, live or not
    check(Gear:Current({ "Raider03-Realm" }) == "Raider03-Realm" and Gear:Current({ "Newbie-Realm", me }) == me
        and Gear:Current({ "Raider03-Realm", "Newbie-Realm" }) == "Newbie-Realm",
        "gear: the character we're playing, or the one that shared last")
    check(Gear:UnitOf(me) == "player" and Gear:UnitOf("Raider03-Realm") == nil, "gear: only nearby players are drawn live")
    STUB.target = "Raider03"
    check(Gear:UnitOf("Raider03-Realm") == "target", "gear: a targeted guildie is drawn live")
    STUB.target = nil

    -- the profile's Character card
    ns.Editor:ShowTab("profiles")
    P:Open("Raider03-Realm")
    local c = P.charCard
    check(c:IsShown() and P.charFor == "Raider03-Realm", "gear: the card shows their current character")
    local warrior = RAID_CLASS_COLORS[ns.db.guild.players["Raider03-Realm"].class]
    check(c.backdrop.glow:IsShown() and c.backdrop.glow.__vertex[1] == warrior.r and c.backdrop.glow.__vertex[3] == warrior.b
        and not c.backdrop.shadow:IsShown(), "gear: a glow in their class colour; no shadow without a model (0.16)")
    local cl, ct, cw, ch = STUB.rect(c)
    local al, at, aw, ah = STUB.rect(c.backdrop.art)
    local il, it, iw, ih = STUB.rect(c.inspect)
    check(near(al, cl + 8) and near(at, ct - 8) and near(aw, cw - 16) and near(ah, ch - 16)
        and it - ih >= at - ah, "gear: the art fills the card 8px in all round, the Inspect button on it")
    -- out of range: no model (the game can't draw them), their portrait and gear icons instead
    local function mini(slot)
        for _, b in ipairs(c.mini) do if b.slot == slot then return b end end
    end
    check(not c.model:IsShown() and not c.pic:IsShown() and #c.mini == 19 and mini(1):IsShown()
        and mini(1).icon.__texture == 6001 and mini(5).icon.__texture == 6005 and mini(1).border.__color[2] > 0.9
        and mini(2).icon.__texture == "slot-NeckSlot" and mini(2).icon:GetAlpha() < 1,
        "gear: out of range, their gear icons (no portrait)")
    -- laid out like the character pane: two columns either side, the weapons below
    -- like the character pane: left column head to wrists (shirt and tabard too), right hands to trinkets,
    -- the weapons along the bottom between them
    local ml, mt1, mw1 = STUB.rect(mini(1))
    local mr, mtHands, mwid = STUB.rect(mini(10))
    local _, mt2 = STUB.rect(mini(2))
    local _, mtWrist = STUB.rect(mini(9))
    local _, mtTrinket2 = STUB.rect(mini(14))
    local trl = STUB.rect(mini(13))
    local wl_, wt_ = STUB.rect(mini(16))
    local rl_, _, rw_ = STUB.rect(mini(18))
    check(near(ml, cl + 20) and near(mr + mwid, cl + cw - 20) and mw1 == 24 and near(mt1 - mt2, 27) and near(mtHands, mt1)
        and near(trl, mr) and near(mtTrinket2, mtWrist) and near(wt_, mtWrist) and wl_ > ml + 24 + 8 and rl_ + rw_ < mr - 8
        and near((wl_ + rl_ + rw_) / 2, cl + cw / 2), "gear: laid out like the character pane, trinkets on the right")
    check(mini(4).icon.__texture == "slot-ShirtSlot" and mini(19).icon.__texture == "slot-TabardSlot",
        "gear: shirt and tabard slots too")
    -- the middle: their class icon above the weapons (0.16: no small Inspect button; the art or a gear icon opens it)
    local order = { WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5, SHAMAN = 6, MAGE = 7, WARLOCK = 8, DRUID = 9 }
    local classIcon = P.ICONS[order[ns.db.guild.players["Raider03-Realm"].class]][1]
    local cil, cit, ciw, cih = STUB.rect(c.classIcon)
    check(c.classIcon:IsShown() and c.classIcon.icon.__texture == classIcon and c.miniInspect == nil and not c.inspect:IsShown()
        and near(cil + ciw / 2, cl + cw / 2) and cit - cih > wt_,
        "gear: their class icon in the middle, above the weapons")
    STUB.Script(mini(1), "OnEnter")
    check(GameTooltip.link and GameTooltip.link:find("Hitem:5001", 1, true), "gear: hovering a gear icon shows the item")
    -- targeted (in range): the live model in the middle, their gear still around it
    STUB.target = "Raider03"
    P:Refresh()
    check(c.model:IsShown() and c.model.__unit == "target" and not c.pic:IsShown() and mini(1):IsShown()
        and not c.inspect:IsShown() and not c.classIcon:IsShown() and c.backdrop.shadow:IsShown(),
        "gear: in range, their live model in the middle instead of the class icon")
    STUB.target = nil
    P:Refresh()
    check(not c.model:IsShown() and mini(1):IsShown(), "gear: and back to the gear icons out of range")
    check(c.inspect:IsEnabled(), "gear: Inspect is offered")

    -- someone who hasn't shared: their portrait, no Inspect
    P:Open("Raider10-Realm")
    check(P.viewing ~= "Raider03-Realm" and not c.model:IsShown() and c.pic:IsShown() and not c.mini[1]:IsShown()
        and not c.inspect:IsEnabled(),
        "gear: nothing shared, the portrait shows instead")

    -- Inspect
    P:Open("Raider03-Realm")
    STUB.Script(c.open, "OnClick")
    local w = Gear.window
    local function slotB(id)
        for _, b in ipairs(w.sheet.slots) do if b.slot.id == id then return b end end
    end
    C_Item.GetItemInfo = function(id)
        if NAMES[id] then return NAMES[id], ("|cnIQ3:|Hitem:%d::::::::60:::::|h[%s]|h|r"):format(id, NAMES[id]) end
    end
    Gear:RefreshWindow()
    check(slotB(1).name:GetText():find("|cff0070dd", 1, true) and near(slotB(1).border.__color[3], 0xdd / 255, 0.01),
        "gear: names and borders take the item's rarity colour")
    check(ns.Loot.Quality("|cnIQ4:|Hitem:1::::|h[x]|h|r") == 4, "loot: newer links' quality is read")
    check(w and w:IsShown() and w.title:GetText() == "Raider03" and w.when:GetText() == "Updated 2h ago"
        and slotB(1).name:GetText():find("Helm of Testing", 1, true) and slotB(5).name:GetText():find("Robe of Testing", 1, true)
        and slotB(16).name:GetText() == "Main Hand", "gear: Inspect shows their gear on the character sheet")
    local found = false
    for _, n in ipairs(UISpecialFrames) do if n == "PogRaidInspect" then found = true end end
    check(found and w:GetFrameStrata() ~= "HIGH", "gear: Escape closes it, and it sits above the main window")
    local cls = ns.db.guild.players["Raider03-Realm"].class
    local il = STUB.rect(w.info)
    local wl = STUB.rect(w)
    check(w.metal and w.title == w.metal.title and w.close == w.metal.close and w.metal.portrait.icon.__texture == Gear.CLASS_CIRCLES
        and w.metal.portrait.icon.__coord[1] == CLASS_ICON_TCOORDS[cls][1] and w.metal.portrait.icon.__coord[3] == CLASS_ICON_TCOORDS[cls][3]
        and near(il, wl + ns.UI.PORTRAIT_CLEAR), "gear: Inspect wears the metal frame: their name in the strip, their class in the ring")
    local entries
    local show = UI.ShowMenu
    UI.ShowMenu = function(_, e) entries = e end
    STUB.Script(slotB(1), "OnClick", "LeftButton")
    UI.ShowMenu = show
    check(entries and entries[2].text == "Add to my wishlist", "gear: an item offers the wishlist")
    entries[2].func()
    check(D:Find(5001) and D:Find(5001).slot == 1, "gear: and adds it")
    UI.ShowMenu = function(_, e) entries = e end
    STUB.Script(slotB(1), "OnClick", "LeftButton")
    UI.ShowMenu = show
    check(entries[2].disabled and entries[2].text == "On your wishlist", "gear: already on it")
    D:Remove(5001)

    -- the game's dressing room art for their class, when the client has it
    C_Texture = { GetAtlasInfo = function(name)
        if name == "dressingroom-background-" .. ns.db.guild.players["Raider03-Realm"].class:lower() then
            return { file = 4242, width = 400, height = 600, leftTexCoord = 0, rightTexCoord = 1, topTexCoord = 0, bottomTexCoord = 1 }
        end
    end }
    Gear:RefreshWindow()
    local bd = w.backdrop
    local mw_, mh_ = w.artArea:GetWidth(), w.artArea:GetHeight()
    local wl, wt, ww, wh = STUB.rect(w)
    local al_, at_, aw_, ah_ = STUB.rect(bd.art)
    check(w.sheet.backdrop == nil and al_ == wl + 1 and at_ == wt - 36 and aw_ == ww - 2 and at_ - ah_ == wt - wh + 1,
        "gear: the backdrop fills the window under the title band")
    check(bd.art:IsShown() and bd.art.__texture == 4242 and not bd.glow:IsShown(), "gear: the class's dressing room art when there is some")
    local cut = (1 - (400 / 600) / (mw_ / mh_)) / 2
    local tc = bd.art.__coord
    check(near(tc[1], 0) and near(tc[2], 1) and near(tc[3], cut, 1e-4) and near(tc[4], 1 - cut, 1e-4),
        "gear: the art is cropped to the model's shape, not stretched")
    C_Texture = nil
    Gear:RefreshWindow()
    check(not bd.art:IsShown() and bd.glow:IsShown(), "gear: else the glow")

    -- their new gear arrives while the window is open
    Sync:Apply(def, rec({ rev = 60, items = Gear.Pack({ [16] = 5016 }) }))
    check(slotB(16).name:GetText():find("Sword of Testing", 1, true) and slotB(1).name:GetText() == "Head",
        "gear: the window follows their latest gear")

    -- our own: live
    Gear:Inspect(me)
    check(w.when:GetText() == "" and slotB(5).name:GetText():find("Robe of Testing", 1, true)
        and w.sheet.model.__unit == "player", "gear: our own window shows what we wear now")
    STUB.worn[5] = nil
    STUB.Fire("PLAYER_EQUIPMENT_CHANGED", 5)
    check(slotB(5).name:GetText() == "Chest", "gear: and follows our gear changes")
    w:Hide()
    STUB.worn = {}

end

-- Art gallery (/pog art) -----------------------------------------------------------------
do
    local Art = ns.Art
    local L = Art.layout
    local files = { ["Interface\\TalentFrame\\WarriorArms-TopLeft"] = 1, ["Interface\\TalentFrame\\MageFire-TopLeft.blp"] = 2,
        ["Interface\\Glues\\LoadingScreens\\LoadScreenDeadmines"] = 3 }
    GetFileIDFromPath = function(p) return files[p] end
    C_Texture = { GetAtlasInfo = function(name)
        if name == "dressingroom-background-mage" then return { file = 9, width = 400, height = 600 } end
    end }

    SlashCmdList.POGRAID("art")
    local f = Art.frame
    local grid = f.grid
    check(f and f:IsShown() and f.title:GetText() == "Art gallery" and f.list.rows[1].name:GetText() == "Talent trees",
        "art: /pog art opens the gallery on the talent trees")
    check(f.list.rows[1].count:GetText() == "2" and f.meta:GetText() == "2 of 27 in this client"
        and grid.tiles[1]:IsShown() and grid.tiles[2]:IsShown() and not grid.tiles[3]:IsShown(),
        "art: only what this client has is shown")
    local t1 = grid.tiles[1]
    check(t1.label:GetText() == "Warrior: Arms" and grid.tiles[2].label:GetText() == "Mage: Fire"
        and t1.img.tex[1].__texture == "Interface\\TalentFrame\\WarriorArms-TopLeft"
        and t1.img.tex[4].__texture == "Interface\\TalentFrame\\WarriorArms-BottomRight", "art: the classic talent art, four pieces")
    -- the four pieces fit the tile, centred, in their 256+64 by 256+128 shape
    local il, it, iw, ih = STUB.rect(t1.img)
    local l1, t_1, w1, h1 = STUB.rect(t1.img.tex[1])
    local l4, t4, w4, h4 = STUB.rect(t1.img.tex[4])
    local s = math.min(L.TILE_W / 296, L.IMG_H / 332)
    check(near(h1, 256 * s) and near(w1, 256 * s) and near(t_1, it) and near((l1 - il) * 2 + 296 * s, L.TILE_W)
        and near(l4 + w4, l1 + 296 * s) and near(t4 - h4, it - 332 * s) and near(t1.img.tex[4].__coord[2], 40 / 64)
        and near(t1.img.tex[4].__coord[4], 76 / 128), "art: talent pictures fit the tile, centred, without their dark padding")
    -- tiles on an even grid filling the space
    local fl, ft, fw = STUB.rect(f)
    local a1 = STUB.rect(grid.tiles[1])
    local a3, _, w3 = STUB.rect(grid.tiles[3])
    local _, b4 = STUB.rect(grid.tiles[4])
    check(near(a1, fl + L.GRID_X) and near(a3 + w3, fl + L.GRID_X + 2 * (L.TILE_W + 10) + L.TILE_W) and a3 + w3 <= fl + fw - 12
        and near(ft - b4, 36 + 12 + L.PITCH), "art: tiles on an even grid")

    -- other kinds
    STUB.Script(f.list.rows[3], "OnClick")
    check(f.list.rows[3].name:GetText() == "Dressing rooms" and grid.tiles[1].label:GetText() == "Mage (class)"
        and grid.tiles[1].img.tex[1].__atlas == "dressingroom-background-mage" and not grid.tiles[2]:IsShown(),
        "art: dressing room art (atlases)")
    STUB.Script(f.list.rows[2], "OnClick")
    check(grid.empty:IsShown() and not grid.tiles[1]:IsShown() and f.list.rows[2].count:GetText() == "0",
        "art: a category with nothing in this client says so")
    STUB.Script(f.list.rows[4], "OnClick")
    check(grid.tiles[1].label:GetText() == "The Deadmines"
        and grid.tiles[1].img.tex[1].__texture == "Interface\\Glues\\LoadingScreens\\LoadScreenDeadmines", "art: loading screens")

    -- one big
    STUB.Script(grid.tiles[1], "OnClick")
    check(f.big:IsShown() and f.big.name:GetText() == "The Deadmines"
        and f.big.img.tex[1].__texture == "Interface\\Glues\\LoadingScreens\\LoadScreenDeadmines", "art: click a picture to see it big")
    STUB.Script(f.big.back, "OnClick")
    check(not f.big:IsShown(), "art: Back returns to the grid")
    local found = false
    for _, n in ipairs(UISpecialFrames) do if n == "PogRaidArt" then found = true end end
    check(found, "art: Escape closes it")
    SlashCmdList.POGRAID("art")
    check(not f:IsShown(), "art: /pog art again closes it")

    -- pages; and a client that can't say what it has shows everything
    Art.cats = nil
    GetFileIDFromPath, C_Texture = nil, nil
    SlashCmdList.POGRAID("art")
    STUB.Script(f.list.rows[1], "OnClick")
    check(f.meta:GetText() == "27 of 27 in this client" and grid.pageText:GetText() == "1 / 3" and not grid.prev:IsEnabled(),
        "art: nine to a page")
    STUB.Script(grid.next, "OnClick")
    check(grid.pageText:GetText() == "2 / 3" and grid.tiles[1].label:GetText() == "Rogue: Assassination", "art: next page")
    STUB.Script(grid, "OnMouseWheel", -1)
    check(grid.pageText:GetText() == "3 / 3" and not grid.next:IsEnabled(), "art: the mouse wheel turns pages too")
    STUB.Script(grid, "OnMouseWheel", -1)
    check(grid.pageText:GetText() == "3 / 3" and grid.tiles[1]:IsShown(), "art: and stops at the last page")
    f:Hide()

    -- the dungeon journal's own pictures, as the client lists them
    Art.cats = nil
    EJ_GetNumTiers = function() return 2 end
    local tier = 1
    EJ_GetCurrentTier = function() return tier end
    EJ_SelectTier = function(t) tier = t end
    local inst = { [1] = { [false] = { 101, 102 }, [true] = { 201 } }, [2] = { [false] = { 101 } } }
    EJ_GetInstanceByIndex = function(i, raid) return (inst[tier][raid] or {})[i] end
    local info = { [101] = { "The Deadmines", 5001, 5002 }, [102] = { "Wailing Caverns", 5003, nil }, [201] = { "Molten Core", 5004, 5005 } }
    EJ_GetInstanceInfo = function(id) local x = info[id] return x[1], "desc", x[2], 0, x[3] end
    SlashCmdList.POGRAID("art")
    local names = {}
    local jrow
    for i, r in ipairs(f.list.rows) do names[i] = r.name:GetText() if r.name:GetText() == "Dungeon journal" then jrow = r end end
    check(table.concat(names, ",") == "Talent trees,Talents (modern),Dressing rooms,Dungeons,Raids,World and PvP,Dungeon journal,Faction crests,Stationery and parchment",
        "art: new categories: dungeon journal, faction crests, stationery and parchment")
    STUB.Script(jrow, "OnClick")
    local jt = {}
    for _, t in ipairs(grid.tiles) do if t:IsShown() then jt[#jt + 1] = t.label:GetText() end end
    check(table.concat(jt, ",") == "The Deadmines,The Deadmines (lore),Wailing Caverns,Molten Core,Molten Core (lore)"
        and grid.tiles[1].img.tex[1].__texture == 5001 and tier == 1, "art: the journal's pictures, each once (and its tier put back)")

    -- try your own: a file ID, shown big and usable on a page
    STUB.Script(grid.tiles[1], "OnClick")
    STUB.Script(f.big.back, "OnClick")
    f.list.own:SetText("12345")
    STUB.Script(f.list.own, "OnEnterPressed")
    check(f.big:IsShown() and f.big.name:GetText() == "12345" and f.big.img.tex[1].__texture == 12345 and f.list.ownNote:GetText() == "",
        "art: Try your own shows a file ID big")
    local useRoster
    for _, b in ipairs(f.big.uses) do if b.key == "roster" then useRoster = b end end
    STUB.Script(useRoster, "OnClick")
    check(ns.db.art.roster[1] == "Custom" and ns.db.art.roster[2] == "12345" and ns.Roster.poolArt.card.tex[1].__texture == 12345
        and useRoster.selected, "art: and Use on puts it on the page (kept for next time)")
    check(Art.PickFor("roster").path == 12345, "art: a custom pick is found again")
    -- a path the client doesn't have
    GetFileIDFromPath = function() return nil end
    STUB.Script(f.big.back, "OnClick")
    f.list.own:SetText("Interface/Nothing/Here")
    STUB.Script(f.list.own, "OnEnterPressed")
    check(f.list.ownNote:GetText() == "Not in this client." and not f.big:IsShown(), "art: a missing file says so")
    f.list.own:SetText("777")
    STUB.Script(f.list.own, "OnEnterPressed")
    check(f.big:IsShown() and f.big.img.tex[1].__texture == 777, "art: a file ID works even when paths can't be looked up")
    STUB.Script(f.big.back, "OnClick")
    check(Art.Custom("Interface/Glues/Foo").path == "Interface\\Glues\\Foo", "art: slashes either way")
    GetFileIDFromPath = nil
    ns.db.art = nil
    ns.Roster.poolArt:Show(Art.PickFor("roster"))
    EJ_GetNumTiers, EJ_GetCurrentTier, EJ_SelectTier, EJ_GetInstanceByIndex, EJ_GetInstanceInfo = nil, nil, nil, nil, nil
    Art.cats = nil
    f:Hide()
end

-- Talent tree art helpers (Art.lua) -------------------------------------------------------
do
    local Art = ns.Art
    local function wipeCache() for k in pairs(Art.treeCache) do Art.treeCache[k] = nil end end
    local trees = Art.Trees("MAGE")
    check(#trees == 3 and trees[2][1] == "MageFire" and trees[2][2] == "Fire" and Art.Trees("NOPE") == nil,
        "talents: each class's three trees")
    wipeCache()
    GetFileIDFromPath = function(p) return p:find("TalentFrame", 1, true) and 1 or nil end
    local art = Art.TreeArt("MAGE", 2)
    check(art and art.kind == "quad" and art.base == "Interface\\TalentFrame\\MageFire-", "talents: the classic art when the client has it")
    -- covering an area keeps the shape: the pieces add up to it, cropped top and bottom
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetPoint("TOPLEFT", 0, 0)
    f:SetSize(604, 600)
    Art.Cover(f, art, 604, 600)
    local _, _, w1, h1 = STUB.rect(f.tex[1])
    local _, _, w2 = STUB.rect(f.tex[2])
    local _, _, _, h3 = STUB.rect(f.tex[3])
    local s = math.max(604 / 296, 600 / 332)
    local cut = (332 - 600 / s) / 2
    check(near(w1 + w2, 604, 1e-6) and near(h1 + h3, 600, 1e-6) and near(f.tex[1].__coord[3], cut / 256, 1e-6)
        and near(f.tex[2].__coord[2], 40 / 64, 1e-6) and near(f.tex[3].__coord[4], (332 - cut - 256) / 128, 1e-6)
        and near(w1 / (256 * f.tex[1].__coord[2]), s, 1e-6),
        "talents: covering an area fills it with the picture (no dark padding), cropped to keep its shape")
    wipeCache()
    GetFileIDFromPath = function() return nil end
    C_Texture = { GetAtlasInfo = function(name)
        if name == "talents-background-mage-fire" then return { file = 777, width = 1600, height = 800 } end
    end }
    art = Art.TreeArt("MAGE", 2)
    check(art and art.kind == "atlas", "talents: the modern art when the classic is missing")
    Art.Cover(f, art, 604, 600)
    check(f.tex[1].__texture == 777 and not f.tex[2]:IsShown(), "talents: modern art is one picture")
    wipeCache()
    C_Texture = nil
    check(Art.TreeArt("MAGE", 2) == nil, "talents: neither, nothing")
    wipeCache()
    GetFileIDFromPath = nil
end

-- Game art in page cards ------------------------------------------------------------------
do
    local Art = ns.Art
    for k in pairs(Art.treeCache) do Art.treeCache[k] = nil end
    local function shows(ctl, file)
        local t = ctl and ctl.card.tex and ctl.card.tex[1]
        return t and t:IsShown() and t.__texture == "Interface\\TalentFrame\\" .. file .. "-TopLeft"
            and near(t:GetAlpha(), Art.CARD_ALPHA) and ctl.card.bg:GetAlpha() == 1
    end
    ns.Crafting.selected, ns.Crafting.member = nil, nil
    ns.Crafting:Refresh()
    check(shows(ns.Settings.whoArt, "MageFire"), "art: Settings shows Mage: Fire, whatever our class")
    check(shows(ns.Roster.poolArt, "PriestHoly") and shows(ns.Attendance.tableArt, "PaladinHoly")
        and shows(ns.Loot.tableArt, "DruidRestoration") and shows(ns.Crafting.rightArt, "ShamanElementalCombat"),
        "art: each page has its own picture, faint, in a solid card")
    -- the picture reaches every edge of the card
    local who = ns.Settings.whoArt.card
    local cl, ct, cw, ch = STUB.rect(who)
    local l, r, t, b = math.huge, -math.huge, -math.huge, math.huge
    for _, tx in ipairs(who.tex) do
        if tx:IsShown() then
            local xl, xt, xw, xh = STUB.rect(tx)
            l, r, t, b = math.min(l, xl), math.max(r, xl + xw), math.max(t, xt), math.min(b, xt - xh)
        end
    end
    check(near(l, cl, 1e-6) and near(r, cl + cw, 1e-6) and near(t, ct, 1e-6) and near(b, ct - ch, 1e-6),
        "talents: the art fills the whole card, edge to edge")
    -- Crafting: each profession its own picture; gathering ones aren't listed
    local Cr = ns.Crafting
    ns.Sync:Apply(ns.Sync.collections.profs, { id = "Raider09-Realm", author = "Raider09-Realm", by = "Raider09-Realm",
        rev = ns.Now(), t = ns.Now(), list = "Blacksmithing:100:150|Mining:50:75|Engineering:5:75|Tailoring:10:75" }, true)
    Cr.selected, Cr.member = nil, nil
    ns.Editor:ShowTab("crafting")
    local listed = {}
    for _, r in ipairs(Cr.left.rows) do if r:IsShown() then listed[r.name:GetText()] = true end end
    check(listed.Blacksmithing and listed.Engineering and not listed.Mining and not listed.Fishing and not listed.Herbalism
        and not listed.Skinning and not listed["First Aid"], "crafting: gathering professions, First Aid and Fishing aren't listed")
    check(shows(Cr.rightArt, "ShamanElementalCombat"), "art: Crafting's own picture until a profession is picked")
    Cr.selected = "Blacksmithing"
    Cr:Refresh()
    check(shows(Cr.rightArt, "WarriorArms"), "art: Blacksmithing shows Arms Warrior")
    Cr.selected = "Tailoring"
    Cr:Refresh()
    check(shows(Cr.rightArt, "MageFrost"), "art: Tailoring shows Frost Mage")
    Cr.selected = "Engineering"
    Cr:Refresh()
    check(shows(Cr.rightArt, "MageArcane"), "art: Engineering shows Arcane Mage")
    Cr.ART.Engineering = nil
    Cr:Refresh()
    check(shows(Cr.rightArt, "ShamanElementalCombat"), "art: a profession without its own keeps the page's picture")
    Cr.ART.Engineering = "Mage: Arcane"
    Cr.selected = "Mining"
    Cr:Refresh()
    check(Cr.selected == nil, "crafting: a hidden profession can't stay picked")
    check(Cr.ART.Alchemy == "Shaman: Elemental" and Cr.ART.Cooking == "Druid: Restoration" and Cr.ART.Enchanting == "Priest: Discipline"
        and Cr.ART.Leatherworking == "Druid: Feral" and ns.Art.Find("Talent trees", Cr.ART.Leatherworking)
        and ns.Art.Find("Talent trees", Cr.ART.Enchanting), "art: every profession's picture is in the gallery")

    ns.Editor:ShowTab("games")
    check(shows(ns.Wowdle.sideArt, "MageArcane"), "art: Wowdle's guild card too")
    SlashCmdList.POGRAID("duels")
    check(shows(ns.Duels.boardArt, "RogueSubtlety"), "art: Subtlety Rogue behind the ranked duels leaderboard")

    -- try another picture on a page from the gallery
    SlashCmdList.POGRAID("art")
    local g = Art.frame
    STUB.Script(g.list.rows[1], "OnClick")
    local tile = g.grid.tiles[9]
    check(tile.label:GetText() == "Hunter: Survival", "art: (the ninth talent picture)")
    STUB.Script(tile, "OnClick")
    local big = g.big
    local labels, rosterBtn = {}, nil
    for i, btn in ipairs(big.uses) do
        labels[i] = btn.label:GetText()
        if btn.key == "roster" then rosterBtn = btn end
    end
    check(big:IsShown() and big.useLabel:GetText() == "Use on"
        and table.concat(labels, ",") == "Roster,Attendance,Loot,Crafting,Wowdle,Duels,Settings" and not rosterBtn.selected,
        "art: the big view offers Use on each page")
    local _, _, bw = STUB.rect(big)
    local ll = STUB.rect(big.uses[1])
    local lastL, _, lastW = STUB.rect(big.uses[#big.uses])
    local backL = STUB.rect(big.back)
    check(ll > STUB.rect(big.useLabel) and lastL + lastW <= backL - 4, "art: the Use on buttons fit beside Back")
    STUB.Script(rosterBtn, "OnClick")
    check(ns.db.art.roster[1] == "Talent trees" and ns.db.art.roster[2] == "Hunter: Survival"
        and shows(ns.Roster.poolArt, "HunterSurvival") and rosterBtn.selected, "art: Use on puts it on that page at once")
    STUB.Script(big.back, "OnClick")
    STUB.Script(g.grid.tiles[1], "OnClick")
    check(not rosterBtn.selected, "art: another picture isn't marked for that page")
    g:Hide()
    ns.db.art = nil
    ns.Roster.poolArt:Show(Art.PickFor("roster"))
    check(shows(ns.Roster.poolArt, "PriestHoly"), "art: without a pick, the page's own picture")

    -- a card drops the art when the client has none
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetPoint("TOPLEFT", 0, 0)
    f:SetSize(200, 300)
    f.bg = f:CreateTexture()
    local ctl = Art.CardArt(f)
    ctl:Set("MAGE", 1)
    check(f.tex[1]:IsShown(), "talents: (a card with art)")
    GetFileIDFromPath = function() return nil end
    for k in pairs(Art.treeCache) do Art.treeCache[k] = nil end
    ctl:Set("MAGE", 1)
    check(not f.tex[1]:IsShown(), "talents: no art in this client, a plain card")
    GetFileIDFromPath = nil
    for k in pairs(Art.treeCache) do Art.treeCache[k] = nil end
end

-- Home: our spec's remastered talent art on the message board -----------------------------
do
    local Art, Home = ns.Art, ns.Home
    local spec, specName = nil, nil
    GetSpecialization = function() return spec end
    GetSpecializationInfo = function(i) return 250 + i, specName end
    local board = Home.boardCard
    local function art() return board.tex and board.tex[1] end
    -- no spec yet: our first tree (the classic picture, no remastered one here)
    ns.Editor:ShowTab("home")
    check(art() and art():IsShown() and art().__texture == "Interface\\TalentFrame\\HunterBeastMastery-TopLeft"
        and near(art():GetAlpha(), Art.CARD_ALPHA) and board.bg:GetAlpha() == 1,
        "home: the message board shows our class's art, faint, before we pick a spec")
    -- our spec's remastered picture
    spec, specName = 2, "Marksmanship"
    C_Texture = { GetAtlasInfo = function(name)
        if name:find("^talents%-background%-hunter%-") then return { file = name, width = 1600, height = 800 } end
    end }
    ns.Editor:ShowTab("settings")
    ns.Editor:ShowTab("home")
    check(art().__texture == "talents-background-hunter-marksmanship" and (board.tex[2] == nil or not board.tex[2]:IsShown()),
        "home: our current spec's remastered picture")
    -- the client's order may differ: matched by name
    spec, specName = 3, "Beast Mastery"
    STUB.Fire("PLAYER_SPECIALIZATION_CHANGED", "player")
    check(art().__texture == "talents-background-hunter-beastmastery", "home: switching spec changes it, matched by name")
    check(Art.MySpec() == 1, "home: (Beast Mastery is the first tree)")
    -- no remastered picture for it: the classic one
    C_Texture = nil
    spec, specName = 3, "Survival"
    Home:RefreshArt()
    check(art().__texture == "Interface\\TalentFrame\\HunterSurvival-TopLeft", "home: the classic picture when there's no remastered one")
    GetSpecialization, GetSpecializationInfo = nil, nil

    check(Home.header.tex == nil, "home: no art behind the banner")

    -- plain card titles (Jake: no icons on Home)
    check(Home.boardCard.icon == nil and Home.onlineCard.icon == nil and Home.lootCard.icon == nil and Home.groupCard.icon == nil
        and near(STUB.rect(Home.onlineCard.title), STUB.rect(Home.onlineCard) + 10), "home: plain card titles, no icons")
end

-- Friend feedback: off spec, kudos total, everyone you've grouped with, Group finder to LFG --
do
    local P, Sync = ns.Profiles, ns.Sync
    local me = Sync:Me()
    ns.Editor:ShowTab("profiles")
    P:Open(me)
    -- off spec: picked in Edit, shown in the banner, shared with the profile
    local saved = P:Mine().content
    local savedRole, savedOff = saved.role, saved.off
    local entries = P:EditMenu()
    local offHeader, offDps
    for _, e in ipairs(entries) do
        if e.text == "Off spec" then offHeader = true end
        if offHeader and e.text:find("DPS", 1, true) then offDps = offDps or e end
    end
    P:Save({ role = "H" })
    offDps.func()
    local info = P.banner.info:GetText()
    check(offHeader and P:Mine().content.off == "D" and info:find("Heals", 1, true) and info:find("off spec", 1, true)
        and info:find("DPS", 1, true), "profiles: an off spec, shown beside the main role")
    check(Sync:Store("profile")[me].off == "D", "profiles: the off spec is shared")
    local def = Sync.collections.profile
    local bad = {}
    for k, v in pairs(Sync:Store("profile")[me]) do bad[k] = v end
    bad.off, bad.rev = "DPS", bad.rev + 1
    check(not Sync:Apply(def, bad, true), "profiles: an odd off spec is refused")
    -- kudos: your own total, on your own profile only
    local _, _, total = P:Kudos(me)
    check(P.kudosCard.meta:GetText() == (total > 0 and (total .. " received") or ""), "profiles: your own kudos total, on your page")
    -- everyone you've grouped with
    P:Mine().together["Raider05-Realm"] = 3 * 3600 + 20 * 60
    P:Mine().together["Raider06-Realm"] = 30
    P:Refresh()
    check(P.topCard.all:IsShown(), "profiles: See all on your own Most played with")
    local menu
    local show = ns.UI.ShowMenu
    ns.UI.ShowMenu = function(_, e) menu = e end
    STUB.Script(P.topCard.all, "OnClick")
    ns.UI.ShowMenu = show
    local found
    for _, e in ipairs(menu or {}) do if e.text:find("3h 20m", 1, true) then found = e end end
    local brief = false
    for _, e in ipairs(P:Together()) do if e[1] == P:Main("Raider06-Realm") and e[2] < 60 then brief = true end end
    check(menu and menu[1].text == "Grouped with" and found and #menu == #P:Together() + 1 and not brief,
        "profiles: See all lists everyone you've grouped with and for how long (not a moment's group)")
    check(P.Duration(45 * 60) == "45m" and P.Duration(2 * 3600) == "2h" and P.Duration(3 * 3600 + 5 * 60) == "3h 5m",
        "profiles: times read 45m, 2h, 3h 5m")
    P:Open("Raider03-Realm")
    check(not P.topCard.all:IsShown() and P.kudosCard.meta:GetText() == "", "profiles: neither on someone else's page")
    P:Mine().together["Raider05-Realm"] = nil
    P:Mine().together["Raider06-Realm"] = nil
    P:Save({ role = savedRole or false, off = savedOff or false })

    -- Home's Group finder card opens the LFG tab
    ns.Editor:ShowTab("home")
    STUB.Script(ns.Home.groupCard, "OnMouseUp", "LeftButton")
    check(ns.Editor.currentTab == "lfg", "home: clicking the Group finder card opens LFG")
end

-- Classic look: the game's gold, borders, red buttons, check boxes, highlights, sounds -----
do
    local UI = ns.UI
    check(UI.DEFAULT_THEME == "night" and ns.db.settings.theme == "night" and UI.theme == "night" and UI.classic
        and UI.ACCENT[1] == 1 and UI.ACCENT[2] == 0.82, "classic: the Night theme by default (Jake's pick), gold instead of blue")
    -- body text: the theme's pale yellow, never pure white
    local stoneT = UI.Theme("night")
    local probe = UI.Text(CreateFrame("Frame"), 11)
    check(UI.TEXT[1] == stoneT.text[1] and UI.TEXT[3] == stoneT.text[3] and UI.TEXT[1] < 0.92
        and probe.__textColor[1] == UI.TEXT[1] and probe.__textColor[3] == UI.TEXT[3], "classic: body text is the theme's colour, not white")
    check(ns.Home.boardCard.thread.body.__textColor[3] == UI.TEXT[3], "classic: text that used to be set white follows the theme")
    -- the navigation band: the theme's solid colour, the marble over it, lit from above
    local bandTex = CreateFrame("Frame"):CreateTexture()
    UI.Band(bandTex, CreateFrame("Frame"):CreateTexture())
    check(UI.BAND[1] == stoneT.band[1] and UI.BAND[4] == 1 and bandTex.__color[1] == UI.BAND[1] and bandTex.marble
        and bandTex.marble.__texture == UI.SURFACE and bandTex.marble.__blend == "ADD" and bandTex.shade.__gradient
        and bandTex.shade.__gradient[3].a == 0.08, "classic: the navigation band is textured and lit, not flat")
    -- the main window: the game's metal frame (as on Professions), the strip above the window
    local f = ns.Editor.frame
    local m = ns.Editor.metal
    local fl, ft, fw, fh = STUB.rect(f)
    local el, et = STUB.rect(m.edge)
    local sl, st, sw, sh = STUB.rect(m.strip)
    local pl, pt = STUB.rect(m.portrait)
    check(m and m.edge.__layout == "PortraitFrameTemplate" and f.frameBorder == nil and el == fl and et == ft + 21
        and m.edge:GetFrameLevel() > f:GetFrameLevel() + 20 and f.stone and f.stone.__texture == UI.SURFACE
        and not f.edges[1]:IsShown(), "classic: the window wears the game's metal frame, its strip above the window, on the theme's surface")
    check(sl == fl and st == ft + 21 and sh == 21 and m.title:GetText() == "Pog Guild Tools" and m.title.__textColor[2] == 0.82
        and not ns.Editor.bandTitle:IsShown(), "classic: the title sits centred in the strip, not in the band")
    check(pl == fl - 5 and pt == ft + 28 and m.portrait:GetFrameLevel() < m.edge:GetFrameLevel()
        and m.portrait.icon.__texture == ns.MEDIA .. "logo", "classic: our logo in the corner's portrait ring")
    check(ns.Editor.closeBtn == m.close and m.close.inStrip and m.close:GetParent() == m.strip, "classic: the X in the strip")
    STUB.Script(m.close, "OnClick")
    check(not f:IsShown(), "classic: the strip's X closes the window")
    f:Show()
    -- the other windows wear it too, their names in the strip
    UI.CopyBox("Loot for Discord", "y")
    check(PogRaidCopy.metal and PogRaidCopy.metal.edge.__layout == "PortraitFrameTemplate"
        and PogRaidCopy.metal.title:GetText() == "Loot for Discord", "classic: the copy box wears the metal frame, its title in the strip")
    PogRaidCopy:Hide()
    ns.Art:Toggle()
    check(PogRaidArt.metal and PogRaidArt.metal.title:GetText() == "Art gallery" and PogRaidArt.close == PogRaidArt.metal.close,
        "classic: the art gallery wears the metal frame")
    PogRaidArt:Hide()
    ns.Viewer:Build()
    local vf = ns.Viewer.frame
    check(ns.Viewer.title:GetParent() ~= nil and vf.frameBorder == nil, "classic: the raid plan viewer wears the metal frame")
    -- small prompts keep the dialog border
    UI.Compose({ heading = "x" }, function() end)
    local cb = UI.composeFrame.frameBorder
    local cl, ct = STUB.rect(UI.composeFrame)
    local bl, bt = STUB.rect(cb)
    check(cb and cb.__backdrop.edgeFile == UI.FILES.dialog and bl == cl - 10 and bt == ct + 10, "classic: prompts wear the dialog border")
    UI.composeFrame:Hide()
    -- without the game's layouts: the dialog border
    local nsu = NineSliceUtil
    NineSliceUtil = nil
    local bare = CreateFrame("Frame")
    bare.edges = {}
    check(UI.PortraitFrame(bare, "x", "y") == nil, "classic: no layouts, no metal frame (the dialog border instead)")
    NineSliceUtil = nsu
    -- menus: the tooltip border
    UI.ShowMenu(ns.Editor.closeBtn, { { text = "x" } })
    check(UI.menuFrame.frameBorder and UI.menuFrame.frameBorder.__backdrop.edgeFile == UI.FILES.tooltip, "classic: menus wear the tooltip border")
    UI.HideMenu()
    -- the main action is the red panel button; it presses and greys out like the game's
    UI.Compose({ heading = "x", button = "Post" }, function() end)
    local sub = UI.composeFrame.submit
    check(sub.red and #sub.red == 3 and sub.red[2].__texture == UI.FILES.red .. "Up" and not sub.bg:IsShown()
        and sub.label.__textColor[1] == 1 and sub.label.__textColor[2] == 0.82, "classic: the main button is the game's red button")
    STUB.Script(sub, "OnMouseDown")
    local down = sub.red[1].__texture
    STUB.Script(sub, "OnMouseUp")
    check(down == UI.FILES.red .. "Down" and sub.red[1].__texture == UI.FILES.red .. "Up", "classic: it presses down")
    sub:SetEnabledState(false)
    check(sub.red[3].__texture == UI.FILES.red .. "Disabled" and sub.label.__textColor[1] == 0.5, "classic: and greys out")
    sub:SetEnabledState(true)
    UI.composeFrame:Hide()
    -- check boxes: the game's box and tick, with its sounds; and the switch itself
    ns.Editor:ShowTab("settings")
    local minimap = ns.Settings.checks[1]
    check(minimap.frameTex and minimap.frameTex.__texture == UI.FILES.check .. "Up" and minimap.mark.__texture == UI.FILES.check .. "Check"
        and not minimap.box.bg:IsShown(), "classic: check boxes are the game's")
    STUB.sounds = {}
    STUB.Script(minimap, "OnClick")
    STUB.Script(minimap, "OnClick")
    check(STUB.sounds[1] == SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF and STUB.sounds[2] == SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON,
        "classic: ticking makes the game's click")
    -- the Theme picker: the current one on the button, a menu of all, picking one saves and reloads
    local tb = ns.Settings.themeBtn
    local showMenu, themeMenu = UI.ShowMenu, nil
    UI.ShowMenu = function(_, entries) themeMenu = entries end
    STUB.Script(tb, "OnClick")
    UI.ShowMenu = showMenu
    local names = {}
    for i = 2, #themeMenu do names[#names + 1] = themeMenu[i].text end
    check(tb.label:GetText() == "Night" and themeMenu[1].text == "Theme"
        and table.concat(names, ",") == "   Stone,   Ember,   Sandstone,   Leather,> Night,   Plain (modern)", "classic: Settings has a Theme picker")
    local rb = ns.Settings.reloadBtn
    check(rb and not rb:IsShown() and rb.__attr.type == "macro" and rb.__attr.macrotext == "/reload" and rb.__secure
        and rb:GetParent() == UIParent, "classic: the Reload button is the game's secure /reload, on UIParent, hidden until needed")
    STUB.printed = {}
    themeMenu[3].func()
    check(ns.db.settings.theme == "ember" and tb.label:GetText() == "Ember" and rb:IsShown() and printedContains("Click Reload"),
        "classic: picking a theme saves it and offers Reload (the addon can't reload itself)")
    check(rb.__anchor and rb.__anchor.rel == ns.Settings.general, "classic: Reload sits on the Settings card while offered")
    -- combat: a secure button inside the window used to lock all of it (closing, Esc, tabs, dragging)
    STUB.blocked = nil
    STUB.Fire("PLAYER_REGEN_DISABLED")
    check(not rb:IsShown() and rb.__anchor == nil, "reload: combat starting lets go of the button")
    STUB.combat = true
    local okClose = pcall(ns.Editor.Toggle, ns.Editor, "settings")
    local okOpen = pcall(ns.Editor.Toggle, ns.Editor, "settings")
    local okTab = pcall(ns.Editor.ShowTab, ns.Editor, "home")
    local okBack = pcall(ns.Editor.ShowTab, ns.Editor, "settings")
    check(okClose and okOpen and okTab and okBack and not STUB.blocked,
        "reload: in combat the window still closes, opens and changes tabs after Reload was offered")
    STUB.combat = false
    STUB.Fire("PLAYER_REGEN_ENABLED")
    check(rb:IsShown() and rb.__anchor and rb.__anchor.rel == ns.Settings.general, "reload: offered again once combat ends")
    ns.Editor:ShowTab("home")
    check(not rb:IsShown(), "reload: leaving Settings hides it")
    ns.Editor:ShowTab("settings")
    check(rb:IsShown(), "reload: coming back to Settings shows it while still wanted")
    ns.db.settings.theme = "night"
    ns.Settings:ThemePicked()
    check(not rb:IsShown() and tb.label:GetText() == "Night", "classic: back to the theme in use, no reload needed")
    -- each theme sets its colours (and Plain is the modern look); Stone put back after
    UI.SetTheme("leather")
    local timber = UI.Theme("leather")
    check(UI.classic and UI.CARD[1] == timber.card[1] and UI.BACKING[1] == timber.backing[1] and UI.TEXT[2] == timber.text[2]
        and UI.CARD_EDGE == timber.edge and UI.BACKING[1] > UI.CARD[1] and UI.SURFACE == timber.surface
        and UI.Surface() == timber.surface and UI.SURFACE_TINT == 0.55, "classic: Leather sets its leather, turned down, and warm browns")
    local tcard = CreateFrame("Frame")
    UI.Card(tcard)
    local tbandTex = CreateFrame("Frame"):CreateTexture()
    UI.Band(tbandTex, CreateFrame("Frame"):CreateTexture())
    check(tcard.marble.__texture == timber.surface and tbandTex.marble.__texture == timber.surface
        and tcard.marble.__vertex[1] == 0.55 and tbandTex.marble.__vertex[1] == 0.55,
        "classic: cards and the band wear the theme's surface at its strength")
    local surfaces = {}
    for _, t in ipairs(UI.THEMES) do if t.surface then surfaces[t.surface] = true end end
    local distinct = 0
    for _ in pairs(surfaces) do distinct = distinct + 1 end
    check(distinct == 4 and UI.Theme("ember").surface == UI.Theme("stone").surface, "classic: four surfaces (Stone and Ember share marble)")
    local hasFile = GetFileIDFromPath
    GetFileIDFromPath = function(p) if p:find("Marble") then return 374154 end end
    check(UI.Surface() == UI.FILES.marble, "classic: a surface this client lacks falls back to marble")
    GetFileIDFromPath = hasFile
    UI.SetTheme("plain")
    check(not UI.classic and UI.theme == "plain", "classic: Plain is the modern look")
    UI.SetTheme("night")
    -- tabs and the window make the character window's sounds
    STUB.sounds = {}
    STUB.Script(ns.Editor.tabButtons.home, "OnClick")
    check(STUB.sounds[1] == SOUNDKIT.IG_CHARACTER_INFO_TAB and ns.Editor.currentTab == "home", "classic: tabs make the tab sound")
    STUB.sounds = {}
    f:Hide()
    f:Show()
    check(STUB.sounds[1] == SOUNDKIT.IG_CHARACTER_INFO_CLOSE and STUB.sounds[2] == SOUNDKIT.IG_CHARACTER_INFO_OPEN,
        "classic: the window opens and closes with the game's sounds")
    -- lists: the quest log's bar for the selected row, a gold glow on hover, gold dividers
    ns.Editor:ShowTab("wishlist")
    local row = ns.Wishlist.side.rows[1]
    local gr = row.sel.__gradient
    check(gr and gr[1] == "HORIZONTAL" and gr[2].a == UI.SEL_WASH[1] and gr[3].a == UI.SEL_WASH[2] and gr[2].g == 0.80,
        "classic: the selected row is a gold wash, fading left to right (0.16)")
    local t = f:CreateTexture()
    UI.Hover(t, 0.05)
    local line = f:CreateTexture()
    UI.Line(line, 0.06)
    check(t.__color[1] == 1 and t.__color[2] == 0.82 and t.__blend == "ADD" and line.__color[3] < line.__color[1],
        "classic: hovers glow gold, dividers are gold")
    -- parchment where you read
    ns.Editor:ShowTab("profiles")
    local P = ns.Profiles
    check(P.aboutCard.parchment and P.kudosCard.parchment and P.aboutCard.parchment.__texture == UI.FILES.parchment
        and P.aboutCard.parchment.__alpha == 0.2, "classic: About me and Kudos sit on faint parchment")
    -- the plain look keeps the old helpers
    UI.classic = false
    local p1, p2, p3 = f:CreateTexture(), f:CreateTexture(), CreateFrame("Frame")
    UI.Hover(p1, 0.05)
    UI.SelBar(p2, 0.12)
    p3.edges = {}
    UI.Window(p3)
    check(p1.__color[2] == 1 and p1.__blend == nil and p2.__color and p2.__texture == nil and p3.frameBorder == nil
        and UI.Parchment(CreateFrame("Frame")) == nil, "classic: off, the plain tints and no borders")
    STUB.sounds = {}
    UI.Sound("IG_CHARACTER_INFO_TAB")
    check(#STUB.sounds == 0, "classic: off, no interface sounds")
    UI.classic = true
end

-- Probe and slash commands run clean ------------------------------------------------------
do
    STUB.printed = {}
    SlashCmdList.POGRAID("probe")
    check(printedContains("probe: client 1.60.1") and printedContains("map art: 1 layer(s), 1002x668"), "probe: reports client and map art")
    STUB.Deliver("Jake-Realm")
    check(printedContains("self whisper test"), "probe: self whisper round trip")
    STUB.Fire("ENCOUNTER_START", 3001, "Stormcaller Vael", 14, 20)
    check(ns.db.encounters["3001"] == "Stormcaller Vael", "encounters: engaged bosses are remembered")
    SlashCmdList.POGRAID("reset")
    SlashCmdList.POGRAID("nonsense")
    check(printedContains("/pog opens"), "slash: help for unknown command")
end

-- Alts in other guilds (0.16.1) ---------------------------------------------------------
do
    local G0, keyA = ns.db.guild, ns.GuildKey()
    local savedGuild, savedName, savedPlayer = STUB.guild, STUB.guildName, STUB.player
    local function inGuild(g)
        local n = 0
        for _, p in pairs(g.players) do if p.inGuild then n = n + 1 end end
        return n
    end
    local membersA, inA, feedA = ns.Count(G0.players), inGuild(G0), #G0.feed
    check(keyA == "Pog Squad" and ns.db.guilds[keyA] == G0, "guilds: our guild's data lives under its name")

    -- an alt in another guild
    STUB.player, STUB.guildName = "Bankalt", "Other Guild"
    STUB.guild = { { name = "Bankalt-Realm", rankIndex = 0, level = 10, online = true, class = "MAGE" },
        { name = "Stranger-Realm", rankIndex = 1, level = 60, online = false, class = "PRIEST" } }
    STUB.Fire("PLAYER_GUILD_UPDATE")
    local GB = ns.db.guild
    check(GB ~= G0 and ns.GuildKey() == "Other Guild" and ns.db.guilds[keyA] == G0, "guilds: another guild gets its own data")
    ns.Roster:ScanGuild()
    ns.Roster:ScanGuild()
    check(inGuild(G0) == inA and #G0.feed == feedA and ns.Count(GB.players) == 2 and inGuild(GB) == 2 and #GB.feed == 0,
        "guilds: the alt's guild leaves ours alone: nobody 'left', no 'joined' flood")
    check(ns.Sync:Store("posts") ~= ns.db.sync[keyA].posts and ns.Attendance:Key("Stranger") == "Stranger-Realm"
        and ns.Attendance:Key("Raider01") ~= "Raider01-Realm", "guilds: shared data and name lookups are per guild too")

    -- back on the main; the roster can arrive before the client says the guild changed
    STUB.player, STUB.guild, STUB.guildName = savedPlayer, savedGuild, savedName
    STUB.Fire("GUILD_ROSTER_UPDATE")
    check(ns.db.guild == G0 and #G0.feed == feedA and ns.Count(G0.players) == membersA and inGuild(G0) == inA
        and ns.Attendance:Key("Raider01") == "Raider01-Realm", "guilds: back on the main, everything as it was")

    -- logging out: the pointer isn't saved (it would be a second copy); loading picks it again
    STUB.Fire("PLAYER_LOGOUT")
    check(PogRaidDB.guild == nil and PogRaidDB.guilds[keyA] == G0, "guilds: saved once, under its guild")
    STUB.Fire("ADDON_LOADED", "PogRaid")
    check(ns.db.guild == G0, "guilds: loading picks this guild's data again")

    -- a save from 0.16.0 or older: one table for every guild, given to the guild it belongs to,
    -- even when an alt in another guild logs in first
    local old = { players = { ["Jake-Realm"] = { inGuild = true, rankIndex = 0 } }, feed = { { kind = "old" } } }
    PogRaidDB.version, PogRaidDB.guild, PogRaidDB.guilds, PogRaidDB.charGuild = 2, old, {}, {}
    STUB.player, STUB.guildName = "Bankalt", "Other Guild"
    STUB.guild = { { name = "Bankalt-Realm", rankIndex = 0, level = 10, online = true, class = "MAGE" } }
    STUB.Fire("ADDON_LOADED", "PogRaid")
    check(ns.db.guild ~= old and ns.db.legacyGuild == old and #ns.db.guild.feed == 0, "guilds: an old save waits while an alt in another guild plays")
    STUB.Fire("PLAYER_LOGOUT")
    STUB.player, STUB.guild, STUB.guildName = savedPlayer, savedGuild, savedName
    STUB.Fire("ADDON_LOADED", "PogRaid")
    check(ns.db.guild == old and ns.db.guilds[keyA] == old and ns.db.legacyGuild == nil and old.feed[1].kind == "old",
        "guilds: and goes to its own guild when one of its members logs in")

    -- put the test's guild back
    STUB.Fire("PLAYER_LOGOUT")
    PogRaidDB.guilds[keyA] = G0
    STUB.Fire("ADDON_LOADED", "PogRaid")
    check(ns.db.guild == G0, "guilds: (test guild restored)")

    -- 0.16.3: on connected realms the game names the guild's realm only some of the time; 0.16.2
    -- keyed guilds by realm too and split one guild into two tables that took turns
    local posts = ns.Sync:Store("posts")
    for _, realm in ipairs({ "OtherRealm", false, "OtherRealm" }) do
        STUB.guildRealm = realm or nil
        STUB.Fire("PLAYER_GUILD_UPDATE")
        STUB.Fire("GUILD_ROSTER_UPDATE")
    end
    STUB.guildRealm = nil
    check(ns.db.guild == G0 and ns.GuildKey() == "Pog Squad" and ns.Sync:Store("posts") == posts and ns.Count(ns.db.guilds) == 2,
        "guilds: one guild stays one table, whatever realm the game names for it")

    -- just after login the game can say "not in a guild": no roster is filed under "no guild"
    STUB.Fire("PLAYER_LOGOUT")
    PogRaidDB.charGuild = {}
    ns.guildKnown = nil
    STUB.guildLoading = true
    STUB.Fire("ADDON_LOADED", "PogRaid")
    STUB.Fire("PLAYER_LOGIN")
    check(ns.GuildKey() == nil and ns.guildKey == nil and ns.db.guild ~= G0, "guilds: 'not in a guild' just after login isn't believed yet")
    local none = PogRaidDB.guilds[ns.NO_GUILD]
    local noneBefore = none and ns.Count(none.players) or 0
    STUB.guildLoading, STUB.guildNameLoading = nil, true
    STUB.Fire("GUILD_ROSTER_UPDATE")
    check((PogRaidDB.guilds[ns.NO_GUILD] and ns.Count(PogRaidDB.guilds[ns.NO_GUILD].players) or 0) == noneBefore and ns.db.guild ~= G0
        and ns.Count(ns.db.guild.players) == 0 and #ns.db.guild.feed == 0,
        "guilds: a roster before the game names the guild isn't filed anywhere")
    STUB.guildNameLoading = nil
    STUB.Fire("GUILD_ROSTER_UPDATE")
    check(ns.db.guild == G0, "guilds: once it does, it's our guild's table")
    STUB.Advance(ns.GUILD_LOAD_WAIT + 1)
    check(ns.db.guild == G0, "guilds: (and stays it once the guild is known)")

    -- someone really not in a guild: "no guild" once the guild had time to load
    local savedG = STUB.guild
    STUB.guild = nil
    STUB.Fire("PLAYER_GUILD_UPDATE")
    check(ns.GuildKey() == ns.NO_GUILD and ns.guildKey == ns.NO_GUILD, "guilds: out of a guild once the game is sure")
    STUB.guild = savedG
    STUB.Fire("PLAYER_GUILD_UPDATE")
    check(ns.db.guild == G0, "guilds: (back in it)")

    -- version 4 merges a guild split by 0.16.1 / 0.16.2 back into one, and empties "no guild"
    STUB.Fire("PLAYER_LOGOUT")
    local splitA = { players = { ["Jake-Realm"] = { inGuild = true, rankIndex = 0 }, ["Raider01-Realm"] = { inGuild = true } },
        sessions = { n1 = { id = "n1", rev = 10, name = "Night A" } }, loot = {}, rosters = { r1 = { id = "r1", rev = 5, name = "Old" } },
        feed = { { t = 200, kind = "level", name = "Raider01-Realm", value = 60 } }, chat = {}, seenLoot = {}, fullScan = true }
    local splitB = { players = { ["Jake-Realm"] = { inGuild = true, rankIndex = 0 }, ["Raider02-Realm"] = { inGuild = true } },
        sessions = { n2 = { id = "n2", rev = 20, name = "Night B" } }, loot = { l1 = { id = "l1", rev = 3 } },
        rosters = { r1 = { id = "r1", rev = 9, name = "Newer" } },
        feed = { { t = 300, kind = "join", name = "Raider02-Realm" } }, chat = {}, seenLoot = {} }
    local bogus = { players = { ["Raider03-Realm"] = { inGuild = true }, ["Pugsley"] = { manual = true } },
        sessions = { n3 = { id = "n3", rev = 1, name = "Pug night" } }, loot = {}, rosters = {},
        feed = { { t = 100, kind = "join", name = "Raider03-Realm" } }, chat = { { t = 100, name = "x", text = "y" } }, seenLoot = {}, fullScan = true }
    local realGuilds, realSync = PogRaidDB.guilds, PogRaidDB.sync
    PogRaidDB.version = 3
    PogRaidDB.guilds = { ["Pog Squad-Realm9"] = splitA, ["Pog Squad-Realm10"] = splitB, [ns.NO_GUILD] = bogus }
    PogRaidDB.sync = {
        ["Pog Squad-Realm9"] = { posts = { p1 = { id = "p1", rev = 50, title = "newer" } }, profile = { u1 = { id = "u1", rev = 1 } } },
        ["Pog Squad-Realm10"] = { posts = { p1 = { id = "p1", rev = 40, title = "older" }, p2 = { id = "p2", rev = 7 } } } }
    PogRaidDB.charGuild = { ["Jake-Realm"] = "Pog Squad-Realm10" }
    STUB.Fire("ADDON_LOADED", "PogRaid")
    local merged = PogRaidDB.guilds["Pog Squad"]
    check(PogRaidDB.version == 5 and merged and PogRaidDB.guilds["Pog Squad-Realm9"] == nil and PogRaidDB.guilds["Pog Squad-Realm10"] == nil
        and ns.db.guild == merged, "merge: one table for the guild, in use")
    check(merged.players["Raider01-Realm"] and merged.players["Raider02-Realm"] and merged.sessions.n1 and merged.sessions.n2
        and merged.loot.l1 and merged.rosters.r1.name == "Newer" and merged.fullScan,
        "merge: everyone, every night and loot entry from both halves; the newer copy of a roster")
    check(#merged.feed == 2 and merged.feed[1].t == 300, "merge: both halves' activity, newest first")
    local store = PogRaidDB.sync["Pog Squad"]
    check(store and PogRaidDB.sync["Pog Squad-Realm9"] == nil and store.posts.p1.title == "newer" and store.posts.p2 and store.profile.u1,
        "merge: one shared store, the newer copy of each record")
    check(PogRaidDB.charGuild["Jake-Realm"] == "Pog Squad", "merge: characters remember the guild by name")
    -- the store names a real save had (found in Jake's data: one of them was skipped once)
    PogRaidDB.version = 3
    PogRaidDB.sync = {
        ["pog-CAMWOWUS1Realm9RPPvP"] = { profs = { a = { id = "a", rev = 9 } }, drops = { d = { id = "d", rev = 1 } } },
        ["pog-CAMWOWUS2Realm10RPPvP"] = { profs = { a = { id = "a", rev = 5 }, b = { id = "b", rev = 2 } } } }
    STUB.Fire("ADDON_LOADED", "PogRaid")
    local leftover = {}
    for k in pairs(PogRaidDB.sync) do if k ~= "pog" and k ~= "Pog Squad" then leftover[#leftover + 1] = k end end
    local pogStore = PogRaidDB.sync.pog
    check(#leftover == 0 and pogStore and pogStore.profs.a.rev == 9 and pogStore.profs.b and pogStore.drops.d,
        "merge: every split store is merged, none left behind (" .. table.concat(leftover, ", ") .. ")")
    local nb = PogRaidDB.guilds[ns.NO_GUILD]
    check(nb.players["Raider03-Realm"] == nil and nb.players["Pugsley"] and nb.sessions.n3 and #nb.feed == 0 and #nb.chat == 0
        and not nb.fullScan, "merge: 'no guild' loses the guild roster filed there, keeps its own nights and pugs")
    -- and the test's own data back
    STUB.Fire("PLAYER_LOGOUT")
    PogRaidDB.guilds, PogRaidDB.sync, PogRaidDB.charGuild = realGuilds, realSync, {}
    STUB.Fire("ADDON_LOADED", "PogRaid")
    check(ns.db.guild == G0, "merge: (test guild restored)")
end

-- Group listings: a malformed "2/5" is refused, and an old one can't break Home (0.16.2) -
do
    local Sync, Home = ns.Sync, ns.Home
    local def = Sync.collections.lfg
    local now = ns.Now()
    local function listing(over)
        local r = { id = "odd-1", rev = now, t = now, by = "Raider05-Realm", author = "Raider05-Realm", what = "Deadmines",
            exp = now + 1800, size = 2, max = 5 }
        for k, v in pairs(over or {}) do r[k] = v end
        return r
    end
    check(not Sync:Apply(def, listing({ max = false })) and not Sync:Apply(def, listing({ size = 0 }))
        and not Sync:Apply(def, listing({ size = 2.5 })) and not Sync:Apply(def, listing({ max = 99 })),
        "lfg: a listing with a size and no max, or odd numbers, is refused")
    local bad = listing()
    bad.max = nil
    check(not Sync:Apply(def, bad), "lfg: (a size with no max)")
    -- one saved by an older version before this check
    Sync:Store("lfg")["odd-1"] = bad
    ns.Editor:ShowTab("home")
    local ok = pcall(Home.Refresh, Home)
    local row
    for _, r in ipairs(Home.groupCard.rows or {}) do if r.item == bad or (r.item and r.item.id == "odd-1") then row = r end end
    check(ok and (row == nil or row.right:GetText() == "2/5"), "lfg: Home still draws, showing it as 2/5")
    Sync:Store("lfg")["odd-1"] = nil
    Home:Refresh()
end

-- Duels: a stray third report on a match can't split the guild's standings (0.16.2) -------
do
    local D, Sync = ns.Duels, ns.Sync
    local def = Sync.collections.duels
    local now = ns.Now()
    local function report(author, a, b, winner)
        return { id = "m-stray:" .. author, rev = now, t = now, by = author, author = author, match = "m-stray",
            a = a, b = b, winner = winner }
    end
    check(Sync:Apply(def, report("Raider01-Realm", "Raider01-Realm", "Raider02-Realm", "Raider01-Realm"))
        and Sync:Apply(def, report("Raider02-Realm", "Raider01-Realm", "Raider02-Realm", "Raider01-Realm")),
        "duels: (both players report the same result)")
    -- a third report on the same match, claiming a different pairing
    check(Sync:Apply(def, report("Raider03-Realm", "Raider03-Realm", "Raider01-Realm", "Raider03-Realm")),
        "duels: (a stray third report arrives)")
    -- every client walks the reports in its own order: try both ways round
    local realPairs = pairs
    local function ordered(desc)
        return function(t)
            local keys = {}
            for k in realPairs(t) do keys[#keys + 1] = k end
            table.sort(keys, function(x, y)
                x, y = tostring(x), tostring(y)
                if desc then return x > y end
                return x < y
            end)
            local i = 0
            return function()
                i = i + 1
                local k = keys[i]
                if k ~= nil then return k, t[k] end
            end, t, nil
        end
    end
    local outcomes = {}
    for _, desc in ipairs({ false, true }) do
        pairs = ordered(desc)
        local ok, list = pcall(D.Confirmed, D)
        pairs = realPairs
        local hit
        for _, c in ipairs(ok and list or {}) do if c.id == "m-stray" then hit = c end end
        outcomes[#outcomes + 1] = hit and (hit.a .. ">" .. hit.winner) or "none"
    end
    check(outcomes[1] == "Raider01-Realm>Raider01-Realm" and outcomes[2] == outcomes[1],
        "duels: the agreed match counts for everyone, whatever order a stray third report comes in ("
        .. table.concat(outcomes, " / ") .. ")")
    for _, who in ipairs({ "Raider01-Realm", "Raider02-Realm", "Raider03-Realm" }) do Sync:Store("duels")["m-stray:" .. who] = nil end
    D.cache = nil
end

-- 0.16.5 ------------------------------------------------------------------------------------
do
    local Home, Sync, Att, Roster, W, Games = ns.Home, ns.Sync, ns.Attendance, ns.Roster, ns.Wowdle, ns.Games
    local G = ns.db.guild
    local me = Sync:Me()
    local function mine(itemID)
        local n, rec = 0, nil
        for _, r in pairs(Sync:Store("drops")) do
            if r.author == me and not r.deleted and ns.Loot.ItemID(r.item) == itemID then n, rec = n + 1, r end
        end
        return n, rec
    end

    -- drops: the same item again is still one shared record (a dungeon farmed all night)
    local farm = STUB.Link(31001, "Farmed Blue", "0070dd")
    STUB.Fire("CHAT_MSG_LOOT", "You receive loot: " .. farm .. ".")
    local n1, r1 = mine(31001)
    local t1 = r1 and r1.t
    STUB.Advance(600)
    STUB.Fire("CHAT_MSG_LOOT", "You receive loot: " .. farm .. ".")
    local n2, r2 = mine(31001)
    check(n1 == 1 and n2 == 1 and r2.t == t1 and r2.id == me .. ":31001", "drops: the same item again is one record, not renewed within the hour")
    STUB.Advance(Home.DROP_RENEW)
    STUB.Fire("CHAT_MSG_LOOT", "You receive loot: " .. farm .. ".")
    local n3, r3 = mine(31001)
    check(n3 == 1 and r3.t > t1, "drops: an hour on, the record is renewed")
    local rows = 0
    for _, e in ipairs(Home:RecentLoot()) do if e.player == me and e.itemID == 31001 then rows = rows + 1 end end
    check(rows == 1, "drops: Recent loot shows a player's item once, however often they got it")
    -- an older version still shares one record per drop: shown once each, and a few per player
    local now = ns.Now()
    local before09 = 0
    for _, e in ipairs(Home:RecentLoot()) do if e.player == "Raider09-Realm" then before09 = before09 + 1 end end
    for i = 1, 6 do
        Sync:Apply(Sync.collections.drops, { id = "old-" .. i, rev = now, by = "Raider09-Realm", author = "Raider09-Realm", t = now - i,
            item = STUB.Link(32000 + (i % 2 == 0 and 99 or i), "Run " .. i, "0070dd"), q = 3 })
    end
    for i = 1, 12 do
        Sync:Apply(Sync.collections.drops, { id = "many-" .. i, rev = now, by = "Raider08-Realm", author = "Raider08-Realm", t = now - i,
            item = STUB.Link(33000 + i, "Other " .. i, "0070dd"), q = 3 })
    end
    local per = {}
    for _, e in ipairs(Home:RecentLoot()) do per[e.player] = (per[e.player] or 0) + 1 end
    check(per["Raider09-Realm"] == before09 + 4 and per["Raider08-Realm"] == Home.LOOT_PER_PLAYER,
        "drops: repeats collapse (4 different items in 6 drops), and one player fills at most 8 lines")
    for id, r in pairs(Sync:Store("drops")) do if id:find("^old%-") or id:find("^many%-") then Sync:Store("drops")[id] = nil end end
    Sync.index = nil

    -- late: there by the end of the first boss attempt is on time, however long the raid took to form
    local start = ns.Now() - 3 * 3600
    local night = { id = "pull-night", rev = ns.Now(), by = "Raider01-Realm", author = "Raider01-Realm", t = start, name = "Forming",
        start = start, stop = start + 7200, snaps = 24,
        seen = "Raider11-Realm:24:0:7200/Raider12-Realm:24:0:7200/Raider13-Realm:16:2400:7200/Raider14-Realm:12:3600:7200",
        bench = "", over = "", bosses = "Slow Trash Boss:1:3000" }
    check(Sync:Apply(Sync.collections.nights, night), "pull: (a shared night arrives)")
    local pn = G.sessions["pull-night"]
    check(Att:Status(pn, "Raider13-Realm") == "present" and Att:Credit(pn, "Raider13-Realm") == 1,
        "pull: 40 minutes after the raid gathered but before the first boss ended is on time")
    check(Att:Status(pn, "Raider14-Realm") == "late" and Att:Credit(pn, "Raider14-Realm") == 0.5, "pull: after the first boss is late")
    pn.bosses = {}
    check(Att:Status(pn, "Raider13-Realm") == "late", "pull: (with no boss yet, 15 minutes after the raid gathered)")
    Att:DeleteSession(pn)

    -- surnames: a first name from the game (your target, a raid frame) reaches the roster's full name
    G.players["Zed Alpha"] = { inGuild = true, class = "MAGE", level = 60, rankIndex = 3 }
    Att.keyCache = nil
    Roster.online["Zed Alpha"] = true
    STUB.sent = {}
    ns.Duels.outgoing, ns.Duels.agreed = nil, nil
    check(ns.Duels:Challenge("Zed") ~= false and STUB.sent[#STUB.sent].target == "Zed Alpha" and STUB.sent[#STUB.sent].text:find("^D1"),
        "surnames: challenging your target whispers their full name")
    ns.Duels.outgoing = nil
    local r = Roster:Current()
    local savedGroups, savedBench = r.groups, r.bench
    r.groups = { { "Zed Alpha" }, {}, {}, {}, {}, {}, {}, {} }
    local savedRoster, savedParty, wasLeader = STUB.roster, STUB.party, STUB.isLeader
    STUB.party, STUB.isLeader = nil, true
    STUB.roster = { { name = "Jake", rank = 2, class = "HUNTER", sub = 1 }, { name = "Zed", class = "MAGE", sub = 2 } }
    STUB.printed, STUB.invites = {}, {}
    Roster:Invite()
    check(#STUB.invites == 0 and printedContains("already in your group"), "surnames: someone in the raid under their first name isn't invited again")
    r.groups, r.bench = savedGroups, savedBench
    STUB.roster, STUB.party, STUB.isLeader = savedRoster, savedParty, wasLeader
    G.players["Zed Alpha"], Roster.online["Zed Alpha"] = nil, nil
    Att.keyCache = nil
    local canvas = ns.Viewer.canvas or (ns.Editor and ns.Editor.canvas)
    check(ns.SameName("Flyne", "Flyne Lee") and not ns.SameName("Flyne", "Flynn Lee"), "surnames: (a raid plan's dot is ours by first name too)")

    -- a new player is found by name straight away (the quick path never answers from an old list)
    Roster:Player("Brandnew Member").inGuild = true
    check(Att:Key("Brandnew") == "Brandnew Member" and Att:Key("Brandnew Member") == "Brandnew Member", "names: someone added a moment ago is found")
    G.players["Brandnew Member"] = nil
    Att.keyCache = nil

    -- pugs: met in a raid, remembered for the night, not put in the roster pool
    local savedInst, savedLead = STUB.instance, STUB.isLeader
    STUB.roster = { { name = "Jake", rank = 2, class = "HUNTER" }, { name = "Pugwash", class = "ROGUE" } }
    STUB.instance, STUB.isLeader = { "Skyreach Spire", "raid" }, true
    Att:Check()
    local sp = Att:Active()
    local pool = {}
    for _, n in ipairs(Roster:PoolNames()) do pool[n] = true end
    check(sp and sp.present["Pugwash"] == 1 and G.players["Pugwash"] and G.players["Pugwash"].pug and not G.players["Pugwash"].manual
        and not pool["Pugwash"], "pugs: on the night, with their class, but not in the roster pool")
    Att:End()
    Att:DeleteSession(sp)
    STUB.roster, STUB.instance, STUB.isLeader = savedRoster, savedInst, savedLead
    -- saves from before: the snapshot's pugs leave the pool, players added by hand stay
    G.players["Oldpug"] = { manual = true, class = "ROGUE" }
    Roster:AddManual("Handadded", "PRIEST")
    STUB.Fire("PLAYER_LOGOUT")
    PogRaidDB.version = 4
    STUB.Fire("ADDON_LOADED", "PogRaid")
    G = ns.db.guild
    check(PogRaidDB.version == 5 and G.players["Oldpug"].pug and not G.players["Oldpug"].manual and G.players["Handadded"].manual,
        "pugs: an old save's snapshot pugs leave the pool, players added by hand stay")
    G.players["Oldpug"], G.players["Handadded"], G.players["Pugwash"] = nil, nil, nil
    Att.keyCache = nil

    -- Wowdle: opening Games doesn't take the keyboard; clicking the board or /pog wowdle does
    local cur = W:Current()
    local savedGuesses = cur.guesses
    cur.guesses = {}
    ns.Editor:ShowTab("home")
    ns.Editor:ShowTab("games")
    Games:SetMode("wowdle")
    check(W:State() == "playing" and not W.input.__focus and W.status:GetText():find("click the board to type", 1, true),
        "wowdle: opening the page leaves the keyboard alone, and says how to type")
    STUB.Script(W.grid, "OnClick")
    check(W.input.__focus and not W.status:GetText():find("click the board", 1, true), "wowdle: clicking the board starts typing")
    W.input:ClearFocus()
    ns.Editor:ShowTab("home")
    SlashCmdList.POGRAID("wowdle")
    check(W.input.__focus, "wowdle: /pog wowdle is ready to type")
    W.input:ClearFocus()
    cur.guesses = savedGuesses
    W:Refresh()
    ns.Editor:ShowTab("home")

    -- a dev build (run from the project folder) doesn't tell the guild a newer version is out
    check(ns.DEV == nil and ns.WireVersion() == ns.VERSION, "dev: (the tests run a release build)")
    ns.DEV = true
    STUB.sent = {}
    ns.Version:Announce()
    check(ns.WireVersion() == ns.VERSION .. "-dev" and STUB.sent[#STUB.sent].text == "V" .. ns.VERSION .. "-dev", "dev: a dev build announces <version>-dev")
    ns.DEV = nil
    ns.Version.warned = nil
    STUB.printed = {}
    STUB.Fire("CHAT_MSG_ADDON", "PogRaid", "V99.0.0-dev", "GUILD", "Raider02-Realm")
    ns.Sync:OnPayload("F" .. ("A"):rep(ns.Sync.BUCKETS * 5) .. "0:99.0.0-dev", "Raider02-Realm")
    check(not printedContains("newer Pog Guild Tools") and not ns.Version.warned and ns.Version.seen["Raider02-Realm"] ~= "99.0.0-dev",
        "dev: which nobody takes for a newer version")
    STUB.Fire("CHAT_MSG_ADDON", "PogRaid", "V99.0.0", "GUILD", "Raider02-Realm")
    check(printedContains("newer Pog Guild Tools"), "dev: (a released one still is)")
    ns.Version.seen["Raider02-Realm"], ns.db.versions["Raider02-Realm"] = nil, nil

    -- sync: an expired record leaves every addon's fingerprint at the turn of the minute
    local lfd = Sync.collections.lfd
    local t0 = ns.Now()
    Sync:Apply(lfd, { id = "Raider06-Realm", author = "Raider06-Realm", by = "Raider06-Realm", rev = t0, t = t0, exp = t0 + 30,
        list = "The Deadmines", role = "T" })
    local idx1 = Sync:Index()
    local has1 = idx1.tags[Sync.Tag("fRaider06-Realm", t0)] ~= nil
    check(has1 and Sync:Index() == idx1, "sync: (a listing is in the fingerprint, which is kept for the minute)")
    STUB.Advance(120)
    local idx2 = Sync:Index()
    check(idx2 ~= idx1 and idx2.tags[Sync.Tag("fRaider06-Realm", t0)] == nil and Sync:Store("lfd")["Raider06-Realm"] ~= nil,
        "sync: expired, it leaves the fingerprint at the turn of the minute, before the next prune")
    Sync:Store("lfd")["Raider06-Realm"] = nil
    Sync.index = nil

    -- the loot log keeps a year
    local L = ns.Loot
    G.loot["ancient"] = { id = "ancient", t = ns.Now() - 400 * 86400, player = "Jake-Realm", itemID = 1, link = STUB.Link(1, "Old") }
    G.loot["recent"] = { id = "recent", t = ns.Now() - 30 * 86400, player = "Jake-Realm", itemID = 2, link = STUB.Link(2, "New") }
    L:Prune()
    check(G.loot["ancient"] == nil and G.loot["recent"] ~= nil, "loot: entries over a year old are dropped")
    G.loot["recent"] = nil
    L:Changed()
end

-- 0.16.5 design: Activity times, tile names, Wowdle's bars -----------------------------------
do
    local Home, Roster, P, W, UI = ns.Home, ns.Roster, ns.Profiles, ns.Wowdle, ns.UI
    local G = ns.db.guild
    -- a level-up seen live has its time; an offline member's (it happened earlier) has none
    Roster:ScanGuild()
    local on, off
    for _, m in ipairs(STUB.guild) do
        if m.online and m.level < 60 and not on then on = m end
        if not m.online and not off then off = m end
    end
    on = on or STUB.guild[3]
    local onLevel, offLevel = on.level, off.level
    G.players[on.name].level, G.players[off.name].level = on.level - 1, off.level - 1
    Roster:ScanGuild()
    local eOn, eOff
    for _, e in ipairs(G.feed) do
        if e.kind == "level" and e.name == on.name and not eOn then eOn = e end
        if e.kind == "level" and e.name == off.name and not eOff then eOff = e end
    end
    check(eOn and not eOn.away and eOff and eOff.away == true, "activity: a live level-up has its time, an offline member's doesn't")
    ns.Editor:ShowTab("home")
    Home.feedCard.offset = 0
    Home:Refresh()
    local shownOn, shownOff
    for _, row in ipairs(Home.feedCard.rows) do
        if row.item == eOn then shownOn = row.right:GetText() end
        if row.item == eOff then shownOff = row.right:GetText() end
    end
    check(shownOn == "now" and shownOff == "", "activity: shown as 'now' and as no time at all")
    -- the first read after logging in is all catch-up
    Roster.sessionScan = nil
    G.players[on.name].level = on.level - 1
    Roster:ScanGuild()
    check(G.feed[1].name == on.name and G.feed[1].away == true, "activity: what's found at login happened while we were away")

    -- Most played with: first names fit the tiles; a nickname stays as it is
    G.players["Zed Alpha"] = { inGuild = true, class = "MAGE", level = 60 }
    G.players["Wamuel Whacks"] = { inGuild = true, class = "ROGUE", level = 60 }
    local realTop, realContent = P.Top, P.Content
    P.Top = function() return { "Zed Alpha", "Wamuel Whacks" } end
    P.Content = function(self, who) if who == "Wamuel Whacks" then return { nick = "Wam the Great" } end return realContent(self, who) end
    ns.Editor:ShowTab("profiles")
    P:RefreshTop()
    local t1, t2 = P.topCard.tiles[1].name:GetText(), P.topCard.tiles[2].name:GetText()
    check(t1:find("Zed|r", 1, true) and not t1:find("Alpha", 1, true) and t2:find("Wam the Great", 1, true),
        "most played: a first name on the tile, a nickname whole")
    P.Top, P.Content = realTop, realContent
    G.players["Zed Alpha"], G.players["Wamuel Whacks"] = nil, nil
    ns.Attendance.keyCache = nil
    P:RefreshTop()

    -- Wowdle's stats bars wear the theme's accent, not a blue of their own
    ns.Editor:ShowTab("games")
    ns.Games:SetMode("wowdle")
    W:Refresh()
    local today = ns.db.games.wowdle.history[W:Current().day]
    local plain
    for i, b in ipairs(W.side.bars) do if i ~= today then plain = plain or b end end
    local c = plain.bar.__color
    check(c[1] == UI.ACCENT[1] and c[2] == UI.ACCENT[2] and c[3] == UI.ACCENT[3] and c[4] == W.BAR_ALPHA and W.BAR_BLUE == nil,
        "wowdle: the stats bars are the theme's accent")
    ns.Editor:ShowTab("home")
end

-- 0.16.5: group chat (Chat.lua) and the kudos pop-up --------------------------------------------
do
    local Chat, Sync, Roster, T, P, Home, UI = ns.Chat, ns.Sync, ns.Roster, ns.GroupToast, ns.Profiles, ns.Home, ns.UI
    local G = ns.db.guild
    local me = Sync:Me()
    local A, B, C, D = "Raider03-Realm", "Raider04-Realm", "Raider05-Realm", "Raider06-Realm"
    -- four guildies: A and B online with chat, C online on an old version, D offline with chat
    local savedGuild = {}
    for i, m in ipairs(STUB.guild) do savedGuild[i] = { m, m.online } end
    local function member(name, online)
        for _, m in ipairs(STUB.guild) do
            if m.name == name then m.online = online return end
        end
        table.insert(STUB.guild, { name = name, rankIndex = 2, level = 60, online = online, class = "MAGE" })
    end
    member(A, true) member(B, true) member(C, true) member(D, false)
    Roster:ScanGuild()
    local V = ns.Version
    local savedSeen, savedVersions = V.seen, ns.db.versions
    V.seen, V.dev, ns.db.versions = { [A] = "0.16.5", [B] = "0.17.0", [C] = "0.16.4" }, {}, { [D] = { v = "0.16.5", t = ns.Now() } }
    G.chats = nil
    wipe(Chat.off) wipe(Chat.picked)
    Chat.saidOff = nil
    T.notes = {}
    if T.frame then T.frame:Hide() end
    local function wire(others, text)
        local list = table.concat(others, ",")
        return "M" .. Sync.Enc(#list, 2) .. list .. text
    end
    local function incoming(from, others, text, channel)
        STUB.Fire("CHAT_MSG_ADDON", "PogRaid", "CAAAA" .. wire(others, text), channel or "WHISPER", from)
    end
    local function count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
    local function logText(c, i) local l = c.log[i or #c.log] return l and l.text end

    -- who can be chatted with
    check(Chat:Enabled() and ns.db.settings.chat == true, "chat: on by default")
    check(ns.db.settings.chatWhispers == true and Chat:Whispers(), "whispers: kept in chats by default")
    ns.db.settings.chatWhispers = false -- (this block is the addon's own lines; whispers have the next one)
    check(Chat:CanChat(A) and Chat:CanChat(B) and not Chat:CanChat(C) and not Chat:CanChat(D) and not Chat:CanChat(me)
        and not Chat:CanChat("Stranger-Realm"), "chat: with guildies online on 0.16.5 or newer, nobody else")
    local buddies = Chat:Buddies()
    check(#buddies == 2 and buddies[1] == A and buddies[2] == B, "chat: the buddy list, in name order")
    V:Note(C, "0.16.5-dev")
    check(V.dev[C] == "0.16.5" and V.seen[C] == "0.16.4" and Chat:CanChat(C), "chat: a dev build counts as the version it's built on")
    V.dev = {}

    -- a chat is its people
    local key = Chat.Key({ B, me, A })
    check(key == Chat.Key({ me, A, B }) and Chat:Get({ A, B, me }) == nil, "chat: the same people in any order are one chat, none until made")
    STUB.sent, STUB.sounds, STUB.allowance = {}, {}, 10
    Chat:OpenWith({ A, D, A })
    local c = Chat.current
    check(Chat.frame:IsShown() and c and #c.members == 3 and c == Chat:Get({ D, A, me }) and count(G.chats) == 1
        and #Chat:Others(c) == 2, "chat: starting one opens the window on it (nobody twice)")
    check(Chat.input.__focus == true, "chat: opening a chat yourself is ready to type")

    -- sending: a whisper to everyone else who's online, carrying the others' names
    check(Chat:Send(c, "  hi |cffff0000all|r\n ") == true, "chat: sending a line")
    local m1 = STUB.sent[1]
    check(#STUB.sent == 1 and m1.channel == "WHISPER" and m1.target == "Raider03" and m1.text:sub(1, 1) == "C"
        and m1.text:sub(6) == wire({ A, D }, "hi |cffff0000all|r"), "chat: whispered addon to addon to who's online, tidied")
    check(#c.log == 1 and c.log[1].from == me and logText(c) == "hi |cffff0000all|r", "chat: our line in the log")
    local shown = Chat.log.__messages[#Chat.log.__messages]
    check(shown:find("Jake", 1, true) and shown:find("hi ||cffff0000all||r", 1, true), "chat: shown with its | escaped (no colours or links from a line)")
    check(Chat:Send(c, "   ") == false and Chat:Send(c, "") == false and #c.log == 1, "chat: nothing to send, nothing sent")
    local long = ("x"):rep(300)
    Chat:Send(c, long)
    check(#logText(c) == Chat.MAX_TEXT, "chat: a line is cut at the limit")
    local dchat = Chat:Get({ me, D }, true)
    STUB.sent = {}
    Chat:Send(dchat, "you there?")
    check(#STUB.sent == 0 and #dchat.log == 2 and dchat.log[2].sys and logText(dchat):find("Nobody in this chat is online", 1, true),
        "chat: nobody online to hear it says so, and nothing is whispered")
    Chat:Delete(dchat)
    check(Chat:Get({ me, D }) == nil, "chat: a chat can be deleted")

    -- receiving, with the window closed: unread, a sound and a pop-up
    Chat.frame:Hide()
    STUB.sounds = {}
    incoming(A, { me, D }, "on my way")
    local f = T.frame
    check(#c.log == 3 and c.log[3].from == A and logText(c) == "on my way" and c.unread == 1 and Chat:Unread() == 1,
        "chat: a line from someone in the chat lands in it, unread")
    check(f and f:IsShown() and f.note and f.text:GetText():find("Raider03", 1, true) and f.text:GetText():find("on my way", 1, true)
        and f.sub:GetText() == "Chat with Raider03, Raider06" and STUB.sounds[1] == SOUNDKIT.TELL_MESSAGE,
        "chat: a pop-up and a sound for a line we aren't looking at")
    STUB.Script(f, "OnClick", "LeftButton")
    check(not f:IsShown() and Chat.frame:IsShown() and Chat.current == c and c.unread == 0, "chat: clicking the pop-up opens that chat, read")
    -- with the chat open in front of us: just the line
    STUB.sounds = {}
    local before = #Chat.log.__messages
    incoming(A, { D, me }, "almost there")
    check(c.unread == 0 and not f:IsShown() and #STUB.sounds == 0 and #Chat.log.__messages == before + 1
        and Chat.log.__messages[before + 1]:find("almost there", 1, true), "chat: a line in the open chat just appears")
    -- a new set of people is a new chat; one to one says "Click to reply"
    incoming(B, { me }, "psst ||x")
    local bc = Chat:Get({ me, B })
    check(bc and bc ~= c and bc.unread == 1 and f:IsShown() and f.sub:GetText() == "Click to reply"
        and f.text:GetText():find("psst ||||x", 1, true), "chat: a line from someone else starts their chat, the pop-up escaped too")
    STUB.Script(f, "OnClick", "RightButton")
    check(not f:IsShown() and bc.unread == 1 and Chat.current == c, "chat: right-click dismisses the pop-up, the chat stays unread")

    -- a long line arrives in chunks
    local names = {}
    for i = 1, 6 do names[i] = ("Somebody Withaverylongsurname%d-Realm"):format(i) end
    names[7] = me
    local big = wire(names, ("y"):rep(200))
    STUB.sent, STUB.allowance = {}, 10
    ns.Comm.SendChunked("C", big, "WHISPER", "Jake")
    check(#STUB.sent > 1, "chat: (a full chat with a long line takes more than one message)")
    STUB.Deliver(B)
    local members = { B }
    for _, n in ipairs(names) do members[#members + 1] = n end
    local bigChat = Chat:Get(members)
    check(bigChat and #bigChat.members == 8 and logText(bigChat) == ("y"):rep(200), "chat: put back together from its chunks")
    Chat:Delete(bigChat)

    -- what is turned away
    local n0 = count(G.chats)
    local function ignored(from, others, text, channel)
        local lines = #c.log + #bc.log
        incoming(from, others, text, channel)
        return count(G.chats) == n0 and #c.log + #bc.log == lines
    end
    check(ignored("Stranger-Realm", { me }, "hi"), "chat: not from someone outside the guild")
    check(ignored(A, { D }, "hi") and ignored(A, { "Jakey-Realm" }, "hi"), "chat: not a chat we aren't in")
    check(ignored(A, { me, D }, "hi", "GUILD") and ignored(A, { me, D }, "hi", "RAID"), "chat: only by whisper")
    check(ignored(A, { me, D, D }, "hi") and ignored(A, { me, A }, "hi"), "chat: nobody in it twice")
    check(ignored(A, { me, D }, "   ") and ignored(A, { me, D }, ""), "chat: not an empty line")
    local nine = { me }
    for i = 1, 8 do nine[#nine + 1] = "X" .. i .. "-Realm" end
    check(ignored(A, nine, "hi"), "chat: not more people than a chat holds")
    STUB.Fire("CHAT_MSG_ADDON", "PogRaid", "CAAAAM!!junk", "WHISPER", A)
    STUB.Fire("CHAT_MSG_ADDON", "PogRaid", "CAAAAMzz" .. me, "WHISPER", A)
    STUB.Fire("CHAT_MSG_ADDON", "PogRaid", "CAAAAQ", "WHISPER", A)
    STUB.Fire("CHAT_MSG_ADDON", "PogRaid", "CAAAA", "WHISPER", A)
    check(count(G.chats) == n0, "chat: junk is ignored")
    incoming(A, { me, D }, "line1\nline2\tend")
    check(logText(c) == "line1 line2 end", "chat: control characters become spaces")
    STUB.Fire("CHAT_MSG_ADDON", "PogRaid", "CAAAA" .. wire({ me, D }, "echo"), "WHISPER", "Jake-Realm")
    check(logText(c) == "line1 line2 end", "chat: our own echo is ignored")

    -- the list on the left: just our chats (newest first, unread counted), New chat under them (Jake:
    -- everyone online used to be listed there too, which read as a muddle)
    Chat.current = c
    Chat:Refresh()
    local rows = Chat.left.rows
    check(rows[1].item.chat == c and rows[1].sel:IsShown() and rows[2].item.chat == bc and rows[2].right:GetText() == "1"
        and not rows[2].sel:IsShown() and not rows[3]:IsShown(), "chat: the list is our chats and nothing else, the open one marked, unread counted")
    -- New chat: the right card becomes a picker of who's online
    local pk = Chat.picker
    check(not pk:IsShown() and Chat.newBtn.label:GetText() == "New chat" and Chat.log:IsShown() and not Chat.picking, "chat: New chat under the list")
    STUB.Script(Chat.newBtn, "OnClick")
    check(Chat.picking and pk:IsShown() and not Chat.log:IsShown() and not Chat.input:IsShown() and Chat.pane.with:GetText() == "New chat"
        and pk.search.__focus and not rows[1].sel:IsShown() and Chat.newBtn.selected == true,
        "chat: New chat puts the picker where the open chat was, ready to type a name")
    check(pk.rows[1].item == A and pk.rows[2].item == B and not pk.rows[3]:IsShown() and pk.rows[1].right:GetText() == ""
        and not pk.start:IsEnabled() and pk.start.label:GetText() == "Start chat" and pk.hint:GetText() == "Pick one person, or several for a group."
        and pk.search.ghost:IsShown(), "chat: it lists who's online with chat, and Start chat waits for a pick")
    STUB.Script(pk.rows[1], "OnClick")
    STUB.Script(pk.rows[2], "OnClick")
    check(Chat.picked[A] and Chat.picked[B] and pk.rows[1].sel:IsShown() and pk.start:IsEnabled()
        and pk.start.label:GetText() == "Start chat (2)" and pk.hint:GetText() == "", "chat: clicking people picks them")
    STUB.Script(pk.rows[2], "OnClick")
    check(not Chat.picked[B] and not pk.rows[2].sel:IsShown() and pk.start.label:GetText() == "Start chat", "chat: clicking again unpicks")
    -- a line for the chat under the picker is unread until we're back in it
    incoming(A, { D, me }, "under the picker")
    check(c.unread == 1 and T.frame:IsShown(), "chat: a line for the chat behind the picker counts as unread")
    T.notes = {}
    T.frame:Hide()
    STUB.Script(pk.cancel, "OnClick")
    check(not Chat.picking and not pk:IsShown() and Chat.log:IsShown() and Chat.input:IsShown() and count(Chat.picked) == 0
        and Chat.pane.with:GetText():find("Raider03", 1, true) and c.unread == 0 and rows[1].sel:IsShown() and not Chat.newBtn.selected
        and not pk.search.__focus, "chat: Cancel goes back to the open chat (now read)")
    check(Chat.log.__messages[#Chat.log.__messages]:find("under the picker", 1, true) and #Chat.log.__messages == #c.log,
        "chat: with everything that arrived meanwhile, once")
    -- typing a name narrows the list; Enter with one name left opens that chat
    STUB.Script(Chat.newBtn, "OnClick")
    pk.search:SetText("RAIDER04")
    check(pk.rows[1].item == B and not pk.rows[2]:IsShown() and not pk.search.ghost:IsShown() and not pk.empty:IsShown(), "chat: typing narrows the list")
    pk.search:SetText("zzz")
    check(not pk.rows[1]:IsShown() and pk.empty:IsShown() and pk.empty:GetText() == "Nobody online matches that." and pk.hint:GetText() == "",
        "chat: and says so when nobody matches")
    STUB.Script(pk.search, "OnEnterPressed")
    check(Chat.picking and Chat.current == c, "chat: Enter with nobody to pick does nothing")
    pk.search:SetText("raider0")
    STUB.Script(pk.search, "OnEnterPressed")
    check(Chat.picking, "chat: nor with more than one name left")
    pk.search:SetText("raider04")
    STUB.Script(pk.start, "OnClick")
    check(Chat.picking and Chat.current == c, "chat: the Start chat button wants a pick (a lone match is Enter's shortcut)")
    pk.search:SetText("  raider04 ")
    STUB.Script(pk.search, "OnEnterPressed")
    check(not Chat.picking and Chat.current == bc and bc.unread == 0 and not pk.search.__focus and Chat.input.__focus,
        "chat: Enter with one name left opens the chat with them")
    bc.unread = 1
    -- New chat again starts clean; clicking it a second time is Cancel
    Chat.picked[A] = true -- (a pick left over from somewhere)
    STUB.Script(Chat.newBtn, "OnClick")
    check(pk.search:GetText() == "" and pk.rows[1].item == A and pk.rows[2].item == B and count(Chat.picked) == 0, "chat: the picker starts clean each time")
    STUB.Script(Chat.newBtn, "OnClick")
    check(not Chat.picking and Chat.log:IsShown(), "chat: clicking New chat again closes the picker")
    -- clicking a chat on the left takes over from the picker
    STUB.Script(Chat.newBtn, "OnClick")
    STUB.Script(pk.rows[1], "OnClick")
    STUB.Script(rows[1], "OnClick", "LeftButton")
    check(not Chat.picking and Chat.current == rows[1].item.chat and count(Chat.picked) == 0 and Chat.log:IsShown(), "chat: opening a chat closes the picker")
    Chat.current = c
    bc.unread = 1
    -- several people: a group chat
    STUB.Script(Chat.newBtn, "OnClick")
    STUB.Script(pk.rows[1], "OnClick")
    STUB.Script(pk.rows[2], "OnClick")
    STUB.Script(pk.start, "OnClick")
    local group = Chat:Get({ me, A, B })
    check(group and Chat.current == group and count(Chat.picked) == 0 and not Chat.picking and not pk:IsShown() and Chat.log:IsShown()
        and Chat.pane.with:GetText():find("Raider03", 1, true)
        and Chat.pane.with:GetText():find("Raider04", 1, true), "chat: Start chat opens the chat with the people picked")
    STUB.sent, STUB.allowance = {}, 10
    STUB.Script(Chat.input, "OnEnterPressed")
    check(#STUB.sent == 0, "chat: Enter on an empty box sends nothing")
    STUB.now = STUB.now + 1
    Chat.input:SetText("pull in 5")
    STUB.Script(Chat.input, "OnEnterPressed")
    check(#STUB.sent == 2 and STUB.sent[1].target == "Raider03" and STUB.sent[2].target == "Raider04"
        and STUB.sent[2].text:sub(6) == wire({ A, B }, "pull in 5") and Chat.input:GetText() == "", "chat: Enter sends to everyone and clears the box")
    Chat:Refresh()
    check(rows[1].item.chat == group, "chat: the chat with the newest line is on top")
    -- clicking a chat opens it; right-click offers to delete it
    STUB.Script(rows[3], "OnClick", "LeftButton")
    check(Chat.current == rows[3].item.chat and Chat.current.unread == 0, "chat: clicking a chat opens it")
    local menu
    local realMenu = UI.ShowMenu
    UI.ShowMenu = function(_, e) menu = e end
    Chat:Refresh()
    STUB.Script(rows[1], "OnClick", "RightButton")
    local function entry(text)
        for _, e in ipairs(menu or {}) do if e.text == text then return e end end
    end
    check(menu and menu[1].header and menu[#menu].text == "Delete chat", "chat: right-click a chat to delete it")
    local doomed = rows[1].item.chat
    entry("Delete chat").func()
    check(G.chats[doomed.key] == nil and Chat.current ~= doomed, "chat: and it's gone")
    UI.ShowMenu = realMenu

    -- the window: two cards side by side inside it, the input inside the right one
    local L = Chat.layout
    local fl, ft, fw, fh = STUB.rect(Chat.frame)
    local ll, lt, lw, lh = STUB.rect(Chat.left)
    local pl, pt, pw, ph = STUB.rect(Chat.pane)
    check(fw == L.W and fh == L.H and near(ll - fl, 10) and near(pl - (ll + lw), 8) and near((fl + fw) - (pl + pw), 10)
        and near(lt, pt) and near(lh, ph) and near((lt - lh) - (ft - fh), 10), "chat window: two cards, 10px in from the edges, 8px apart")
    local il, it, iw, ih = STUB.rect(Chat.input)
    local gl, gt, gw, gh = STUB.rect(Chat.log)
    check(near(il - pl, 8) and near((pl + pw) - (il + iw), 8) and near((it - ih) - (pt - ph), 8) and gt - gh >= it + 6
        and near(gl - pl, 10) and near((pl + pw) - (gl + gw), 10), "chat window: the line box along the bottom, the log above it")
    local rl, rt, rw, rh = STUB.rect(rows[#rows])
    local bl, bt, bw, bh = STUB.rect(Chat.newBtn)
    check(rt - rh >= bt + 4 and near((bt - bh) - (lt - lh), 8) and near((bl + bw / 2), ll + lw / 2), "chat window: the list ends above New chat")
    -- the picker, in the right card: search under the heading, the names, then the hint, Cancel and Start chat along the bottom
    local sl, st, sw, sh = STUB.rect(pk.search)
    local _, p1t = STUB.rect(pk.rows[1])
    local _, pnt, _, pnh = STUB.rect(pk.rows[#pk.rows])
    local xl, xt, xw, xh = STUB.rect(pk.start)
    local cl2, ct2, cw2, ch2 = STUB.rect(pk.cancel)
    local hl2, ht2, hw2, hh2 = STUB.rect(pk.hint)
    check(near(sl - pl, 8) and near((pl + pw) - (sl + sw), 8) and near(pt - st, 32) and near((st - sh) - p1t, 6) and near(pt - p1t, L.PICK_TOP)
        and #pk.rows == L.PICK_ROWS, "picker: the search box under the heading, the names 6px under it")
    check(near((pl + pw) - (xl + xw), 8) and near((xt - xh) - (pt - ph), 8) and near(xl - (cl2 + cw2), 6) and near(ct2 - ch2 / 2, xt - xh / 2)
        and ch2 == xh and pnt - pnh >= xt + 6, "picker: Start chat in the corner, Cancel 6px left of it, the names ending above them")
    check(near(hl2 - pl, 10) and near((ht2 - hh2) - (pt - ph), 8) and hl2 + hw2 <= cl2 - 8 + 0.5 and hw2 == L.PICK_HINT_W and hw2 >= 120,
        "picker: the hint in the bottom corner, clear of Cancel")
    local found
    for _, n in ipairs(UISpecialFrames) do if n == "PogRaidChat" then found = true end end
    check(found, "chat window: Esc closes it")

    -- a fight takes the keyboard back
    Chat.input:SetFocus()
    STUB.Fire("PLAYER_REGEN_DISABLED")
    check(not Chat.input.__focus, "chat: starting a fight takes the keyboard off the line box")
    STUB.Fire("PLAYER_REGEN_ENABLED")

    -- history is kept short
    local hc = Chat:Get({ me, A }, true)
    for i = 1, Chat.KEEP_LINES + 20 do incoming(A, { me }, "n" .. i) end
    check(#hc.log == Chat.KEEP_LINES and logText(hc) == "n" .. (Chat.KEEP_LINES + 20) and logText(hc, 1) == "n21", "chat: a chat keeps its newest lines")
    T.notes = {}
    T.frame:Hide()
    Chat.current = nil
    Chat:Refresh()
    local savedNow = STUB.now
    for i = 1, Chat.KEEP_CHATS + 5 do
        STUB.now = STUB.now + 1
        Chat:Get({ me, "Old" .. i .. "-Realm" }, true)
    end
    check(count(G.chats) == Chat.KEEP_CHATS and Chat:Get({ me, "Old1-Realm" }) == nil
        and Chat:Get({ me, "Old" .. (Chat.KEEP_CHATS + 5) .. "-Realm" }), "chat: only the most recent chats are kept")
    STUB.now = savedNow
    for i = 1, Chat.KEEP_CHATS + 5 do G.chats[Chat.Key({ me, "Old" .. i .. "-Realm" })] = nil end

    -- they have chat turned off: we're told once, and stop whispering them
    local ac = Chat:Get({ me, A }, true)
    local lines = #ac.log
    STUB.Fire("CHAT_MSG_ADDON", "PogRaid", "CAAAAN", "WHISPER", A)
    check(Chat.off[A] and #ac.log == lines + 1 and ac.log[#ac.log].sys and logText(ac) == "Raider03 has chat turned off."
        and not Chat:CanChat(A), "chat: someone with chat off says so, once, and leaves the buddy list")
    STUB.Fire("CHAT_MSG_ADDON", "PogRaid", "CAAAAN", "WHISPER", A)
    check(#ac.log == lines + 1, "chat: (said once)")
    STUB.sent = {}
    Chat:Send(ac, "hello?")
    check(#STUB.sent == 0 and logText(ac) == "Not sent: Raider03 has chat turned off.", "chat: and isn't whispered again (the line says why)")
    incoming(A, { me }, "turned it back on")
    check(not Chat.off[A] and Chat:CanChat(A), "chat: until they write, which means it's back on")

    -- turned off here (Settings): the window goes, lines are turned away with a note back
    ns.Editor:ShowTab("settings")
    local checks = ns.Settings.checks
    check(#checks == 8 and checks[7].label:GetText() == "Kudos pop-ups" and checks[8].label:GetText() == "Group chat"
        and checks[7].checked and checks[8].checked, "settings: Kudos pop-ups and Group chat, on by default")
    local _, gtop, _, gh2 = STUB.rect(ns.Settings.general)
    local _, c8t, _, c8h = STUB.rect(checks[8])
    local _, tbt, _, tbh = STUB.rect(ns.Settings.themeBtn)
    local _, ot, _, oh = STUB.rect(ns.Settings.officers)
    local _, r10t, _, r10h = STUB.rect(ns.Settings.officers.ranks[10])
    check(gh2 == 300 and tbt <= c8t - c8h and near((tbt - tbh - 26) - (gtop - gh2), 12) and near(gtop - gh2 - ot, 8)
        and r10t - r10h >= ot - oh, "settings: eight checks, the theme and Reload fit the card, ten officer ranks under it")
    Chat:Open()
    STUB.Script(checks[8], "OnClick")
    check(ns.db.settings.chat == false and not Chat:Enabled() and not Chat.frame:IsShown() and #Chat:Buddies() == 0,
        "settings: Group chat off closes the window")
    STUB.sent, STUB.printed, STUB.allowance = {}, {}, 10
    lines = #ac.log
    incoming(A, { me }, "anyone home")
    check(#ac.log == lines and #STUB.sent == 1 and STUB.sent[1].text:sub(6) == "N" and STUB.sent[1].target == "Raider03"
        and STUB.sent[1].channel == "WHISPER", "chat off: a line is turned away, and its sender told")
    incoming(A, { me }, "hello??")
    check(#STUB.sent == 1, "chat off: told once a minute at most")
    STUB.now = STUB.now + 61
    incoming(A, { me }, "still there?")
    check(#STUB.sent == 2, "chat off: (and again after a minute)")
    check(Chat:Send(ac, "x") == false, "chat off: nothing can be sent")
    SlashCmdList.POGRAID("chat")
    check(not Chat.frame:IsShown() and printedContains("group chat is turned off in Settings"), "chat off: /pog chat says where to turn it on")
    ns.Editor:ShowTab("home")
    Home:Refresh()
    local cc = Home.chatsCard
    check(Home.onlineCard.chat == nil and cc.empty:IsShown() and cc.empty:GetText() == "chat is turned off in Settings" and not cc.cta:IsShown()
        and not cc.new:IsShown() and not cc.rows[1]:IsShown(), "chat off: Home's Chats card says so, with nothing to click")
    ns.Editor:ShowTab("settings")
    STUB.Script(checks[8], "OnClick")
    check(Chat:Enabled() and ns.db.settings.chat == true, "settings: and on again")

    -- Home: a Chats card under the message board (0.16.8, Jake): our newest chats, what's unread, a way to start one;
    -- and Chat in a guildie's menu
    ns.Editor:ShowTab("home")
    for _, ch in pairs(G.chats) do ch.unread = 0 end
    Chat.frame:Hide()
    STUB.now = STUB.now + 180
    incoming(B, { me }, "you up?")
    T.notes = {}
    T.frame:Hide()
    local bchat = Chat:Get({ me, B })
    check(cc:IsShown() and cc.title:GetText() == "Chats" and cc.rows[1].item == bchat and cc.rows[1].right:GetText() == "1"
        and cc.rows[1].right.__textColor[1] == UI.ACCENT[1] and cc.rows[1].text:GetText():find("Raider04", 1, true)
        and cc.rows[1].text:GetText():find("you up?", 1, true) and cc.rows[1].pic:GetTexture() == Chat:Picture(bchat)
        and Chat:Picture(bchat) == ns.Profiles:Portrait(B), "home: the Chats card has the newest chat on top: who, their last line, what's unread")
    check(cc.rows[2]:IsShown() and cc.rows[2].item ~= bchat and cc.rows[2].right:GetText():match("^%d+[mh]$") and cc.rows[2].right.__textColor[1] == 0.5
        and cc.new:IsShown() and cc.new.label:GetText() == "New chat" and not cc.cta:IsShown() and not cc.empty:IsShown(),
        "home: a read chat shows when it last spoke; New chat in the heading")
    local raised = Chat.frame.__raised or 0
    STUB.Script(cc.rows[1], "OnClick", "LeftButton")
    check(Chat.frame:IsShown() and Chat.current == bchat and bchat.unread == 0 and cc.rows[1].right:GetText() == "now"
        and Chat.input.__focus, "home: clicking a chat opens it, read")
    -- in front of the main window, which is open (it's where the button is) and comes forward on every click:
    -- on its layer the chat opened behind it and the button seemed to do nothing (Jake, 0.16.5)
    local STRATA = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
    local main = ns.Editor.frame
    check(main:IsShown() and main.__toplevel and STRATA[Chat.frame.__strata] > STRATA[main.__strata]
        and STRATA[Chat.frame.__strata] < STRATA.FULLSCREEN_DIALOG,
        "chat window: a layer above the main window (and under our menus)")
    check(Chat.frame.__toplevel == true and Chat.frame.__raised == raised + 1, "chat window: opening it brings it to the front")
    STUB.sent, STUB.allowance = {}, 10
    Chat:Send(bchat, "on || my way")
    check(cc.rows[1].text:GetText():find("You: on |||| my way", 1, true), "home: our own last line says You (and stays escaped)")
    Chat.frame:Hide()
    STUB.Script(cc.new, "OnClick")
    check(Chat.frame:IsShown() and Chat.picking and Chat.picker:IsShown() and Chat.picker.search.__focus, "home: New chat opens the window on its picker")
    STUB.Script(cc.new, "OnClick")
    check(Chat.picking, "home: (again leaves the picker up)")
    STUB.Script(Chat.picker.cancel, "OnClick")
    Chat.frame:Hide()
    local function menuFor(name)
        menu = nil
        UI.ShowMenu = function(_, e) menu = e end
        for off = 0, #Home:MemberList() do
            Home.onlineCard.offset = off
            Home:Refresh()
            for _, row in ipairs(Home.onlineCard.rows) do
                if row.item == name and row:IsShown() and not menu then STUB.Script(row, "OnClick", "RightButton") end
            end
            if menu then break end
        end
        Home.onlineCard.offset = 0
        UI.ShowMenu = realMenu
        local texts = {}
        for i, e in ipairs(menu or {}) do texts[i] = e.text end
        return table.concat(texts, "|")
    end
    local withChat, without = menuFor(A), menuFor(C)
    check(withChat:find("|Chat|", 1, true) and withChat:find("Whisper|Chat|Invite to group", 1, true) and not without:find("Chat", 1, true),
        "home: Chat in the menu of a guildie who has it, under Whisper")
    menuFor(A)
    for _, e in ipairs(menu) do if e.text == "Chat" then e.func() end end
    check(Chat.frame:IsShown() and Chat.current == Chat:Get({ me, A }), "home: which opens the chat with them")

    -- /pog chat, and the practice chat
    SlashCmdList.POGRAID("chat")
    check(not Chat.frame:IsShown(), "chat: /pog chat closes the window")
    SlashCmdList.POGRAID("chat")
    check(Chat.frame:IsShown(), "chat: and opens it")
    G.chats = nil
    Chat.current = nil
    STUB.sent, STUB.timers = {}, {}
    SlashCmdList.POGRAID("chat test")
    local tc = Chat.current
    check(tc and tc.test and #tc.members == 2 and tc.log[1].sys and tc.log[2].from == Chat:Others(tc)[1]
        and logText(tc) == Chat.TEST_LINES[1], "practice chat: /pog chat test opens one that says hello")
    member(Chat:Others(tc)[1], true) -- (online, so a real chat would whisper them)
    Roster:ScanGuild()
    STUB.sent, STUB.timers, STUB.allowance = {}, {}, 10
    Chat:Send(tc, "testing")
    Chat.frame:Hide()
    STUB.sounds = {}
    T.frame:Hide()
    STUB.Advance(Chat.TEST_DELAY)
    check(#STUB.sent == 0 and #tc.log == 4 and logText(tc) == Chat.TEST_LINES[2] and tc.unread == 1 and T.frame:IsShown()
        and STUB.sounds[1] == SOUNDKIT.TELL_MESSAGE, "practice chat: it answers after a moment (pop-up and all), and nothing is sent to anyone")
    T.frame:Hide()
    local other = Chat:Others(tc)[1]
    V.seen[other] = "0.16.5"
    incoming(other, { me }, "a real line")
    check(tc.test == nil and logText(tc) == "a real line", "practice chat: a real line from them makes it a real chat")
    STUB.sent, STUB.allowance = {}, 10
    member(other, true)
    Roster:ScanGuild()
    Chat:Send(tc, "real reply")
    check(#STUB.sent == 1, "practice chat: (which is whispered)")
    SlashCmdList.POGRAID("chat test")
    check(Chat.current ~= tc and Chat.current.test, "practice chat: a new one is with someone we have no chat with")
    local again, notes = Chat.current, 0
    SlashCmdList.POGRAID("chat test")
    for _, l in ipairs(again.log) do if l.sys then notes = notes + 1 end end
    check(Chat.current == again and notes == 1 and logText(again) == Chat.TEST_LINES[2], "practice chat: asking again carries the same one on, its note said once")
    wipe(Chat.off)
    V.seen = {}
    Chat:Refresh()
    STUB.Script(Chat.newBtn, "OnClick")
    check(not pk.rows[1]:IsShown() and pk.empty:IsShown() and pk.empty:GetText() == "Nobody online has Pog Guild Tools 0.16.5 or newer."
        and pk.hint:GetText() == "" and not pk.start:IsEnabled(), "chat: with nobody to chat with the picker says so")
    STUB.Script(pk.cancel, "OnClick")
    G.chats = nil
    Chat.current = nil
    Chat:Refresh()
    ns.Editor:ShowTab("home")
    Home:RefreshChats()
    local cl, ct, cw, ch = STUB.rect(cc)
    local el, et, ew, eh = STUB.rect(cc.empty)
    local tl, tt, tw, th = STUB.rect(cc.cta)
    check(cc.empty:IsShown() and cc.empty:GetText() == "no chats atm" and cc.cta:IsShown() and cc.cta.label:GetText() == "Start a chat"
        and not cc.new:IsShown() and not cc.rows[1]:IsShown(), "home: with no chats the card offers to start one")
    check(near(ct - et, 38) and near(tl + tw / 2, cl + cw / 2) and tt < et and (tt - th) - (ct - ch) >= 8 and th == 24,
        "home: the line and its button sit inside the card")
    Chat.frame:Hide()
    STUB.Script(cc.cta, "OnClick")
    check(Chat.frame:IsShown() and Chat.picking, "home: Start a chat opens the picker")
    STUB.Script(Chat.picker.cancel, "OnClick")
    check(Chat.left.rows[1].item.head == "No chats yet" and not Chat.left.rows[1]:IsEnabled() and not Chat.left.rows[2]:IsShown()
        and Chat.pane.empty:IsShown() and Chat.pane.empty:GetText() == "Click New chat to message someone." and not Chat.log:IsShown(),
        "chat: with no chats the list says so, and the card says where to start")
    G.chats = nil
    Chat.current = nil
    Chat.frame:Hide()

    -- the pop-up takes notes one at a time, and waits out a fight
    T.notes = {}
    T.frame:Hide()
    local clicked
    T:Note({ icon = 1, text = "first", sub = "one", onClick = function() clicked = "first" end })
    T:Note({ icon = 2, text = "second", sub = "two" })
    f = T.frame
    check(f:IsShown() and f.text:GetText() == "first" and f.sub:GetText() == "one" and f.icon:GetTexture() == 1 and #T.notes == 1
        and f:GetAlpha() == 0, "notes: one at a time, fading in")
    T:Step(0.5)
    T:Step(T.SHOW + 5)
    check(f:IsShown() and f.text:GetText() == "second" and #T.notes == 0 and clicked == nil, "notes: the next one follows when the first fades")
    STUB.Script(f, "OnClick", "LeftButton")
    check(not f:IsShown(), "notes: a note with nothing to open just closes")
    T:Note({ text = "third", onClick = function() clicked = "third" end })
    STUB.Script(f, "OnClick", "LeftButton")
    check(clicked == "third" and not f:IsShown(), "notes: clicking one runs what it's for")
    STUB.combat = true
    T:Note({ text = "in a fight" })
    check(not f:IsShown() and #T.notes == 1, "notes: nothing pops up in a fight")
    STUB.combat = false
    STUB.Fire("PLAYER_REGEN_ENABLED")
    check(f:IsShown() and f.text:GetText() == "in a fight", "notes: it shows when the fight ends")
    for i = 1, T.MAX_NOTES + 3 do T:Note({ text = "n" .. i }) end
    check(#T.notes == T.MAX_NOTES and T.notes[1].text == "n4", "notes: only the newest few wait")
    T.notes = {}
    -- a new group takes the pop-up over; the note's click no longer applies
    f:Hide()
    T:Note({ text = "note", onClick = function() clicked = "note" end })
    check(f:IsShown() and f.note ~= nil, "notes: (a note is up)")
    local now = ns.Now()
    Sync:Apply(Sync.collections.lfg, { id = "lfg-chat-test", rev = now, by = B, author = B, t = now, what = "Stratholme", need = "tank", exp = now + 2700, size = 1, max = 5 })
    check(f:IsShown() and f.note == nil and f.id == "lfg-chat-test" and f.text:GetText():find("Stratholme", 1, true), "notes: a new group shows over a note")
    STUB.Script(f, "OnClick", "RightButton")
    ns.Social.requested["lfg-chat-test"] = nil
    Sync:Store("lfg")["lfg-chat-test"] = nil
    Sync.index = nil

    -- kudos for us: a pop-up, once per kudos
    local week = P.Week()
    local guild = Sync:GuildName()
    local rev = now
    local function kudos(from, to, kind, n, wk, msg, quiet)
        rev = rev + 1
        return Sync:Apply(Sync.collections.kudos, { id = from .. ":" .. kind .. ":" .. to, rev = rev, by = from, author = from, t = now,
            to = to, kind = kind, n = n, wk = wk or week, msg = msg or "Thanks for the run" }, quiet)
    end
    G.kudosSeen = nil
    T.notes = {}
    f:Hide()
    STUB.sounds = {}
    check(ns.db.settings.kudosToasts == true, "kudos pop-up: on by default")
    check(kudos(C, me, 2, 1, week, "Never ||died once") and f:IsShown() and f.note
        and f.text:GetText():find("Raider05", 1, true) and f.text:GetText():find("gave you kudos: Great tank", 1, true)
        and f.sub:GetText() == '"Never ||||died once"' and f.icon:GetTexture() == P.KUDOS[2][1] and STUB.sounds[1] == SOUNDKIT.IG_QUEST_LIST_COMPLETE
        and G.kudosSeen[C .. ":2:" .. me] == 1, "kudos pop-up: a guildie's kudos for us pops up with its message")
    ns.Editor:ShowTab("home")
    STUB.Script(f, "OnClick", "LeftButton")
    check(not f:IsShown() and ns.Editor.currentTab == "profiles" and P.viewing == P:Main(me), "kudos pop-up: clicking it opens our profile")
    ns.Editor:ShowTab("home")
    kudos(C, me, 2, 1)
    check(not f:IsShown(), "kudos pop-up: the same kudos coming round again doesn't")
    kudos(C, me, 2, 2)
    check(f:IsShown() and G.kudosSeen[C .. ":2:" .. me] == 2, "kudos pop-up: another one from them does")
    f:Hide()
    kudos(C, me, 2, 1, week - 1)
    check(not f:IsShown() and G.kudosSeen[C .. ":2:" .. me] == 1, "kudos pop-up: one taken back is quiet")
    kudos(C, me, 2, 2)
    check(f:IsShown(), "kudos pop-up: and given again shows again")
    f:Hide()
    kudos(A, me, 1, 3, week - 2)
    check(not f:IsShown() and G.kudosSeen[A .. ":1:" .. me] == 3, "kudos pop-up: not for kudos from weeks ago (a new install catching up)")
    kudos(A, B, 3, 1)
    check(not f:IsShown() and G.kudosSeen[A .. ":3:" .. B] == nil, "kudos pop-up: not for someone else's kudos")
    kudos(A, me, 8, 1)
    check(not f:IsShown(), "kudos pop-up: not for a retired kind")
    -- one that arrives in a page of records (the catch-up after logging in) counts too
    kudos(B, me, 5, 1, week, "Helped me with my key", true)
    check(f:IsShown() and f.text:GetText():find("Helpful", 1, true), "kudos pop-up: also when it arrives with a batch of records")
    f:Hide()
    -- for our alt; never from our own characters
    local a = P:Mine()
    a.chars[guild] = a.chars[guild] or {}
    local hadAlt = a.chars[guild]["Jakealt-Realm"]
    a.chars[guild]["Jakealt-Realm"] = now
    kudos(A, "Jakealt-Realm", 4, 1)
    check(f:IsShown() and f.text:GetText():find("Carried me", 1, true), "kudos pop-up: for our alt as well")
    f:Hide()
    kudos("Jakealt-Realm", me, 4, 1)
    check(not f:IsShown(), "kudos pop-up: not from our own alt")
    a.chars[guild]["Jakealt-Realm"] = hadAlt
    -- turned off in Settings: quiet, and not saved up for later
    ns.Editor:ShowTab("settings")
    STUB.Script(checks[7], "OnClick")
    check(ns.db.settings.kudosToasts == false, "settings: Kudos pop-ups off")
    kudos(B, me, 9, 1)
    check(not f:IsShown() and #T.notes == 0 and G.kudosSeen[B .. ":9:" .. me] == 1, "kudos pop-up: off means none")
    STUB.Script(checks[7], "OnClick")
    kudos(B, me, 9, 1)
    check(ns.db.settings.kudosToasts == true and not f:IsShown(), "kudos pop-up: and the ones missed don't pop up when it's back on")
    -- in a fight it waits
    STUB.combat = true
    kudos(B, me, 7, 1)
    check(not f:IsShown() and #T.notes == 1, "kudos pop-up: waits out a fight")
    STUB.combat = false
    STUB.Fire("PLAYER_REGEN_ENABLED")
    check(f:IsShown() and f.text:GetText():find("Great leader", 1, true), "kudos pop-up: then shows")
    f:Hide()

    -- tidy up
    local store = Sync:Store("kudos")
    for id in pairs(G.kudosSeen) do store[id] = nil end
    store[A .. ":3:" .. B], store[A .. ":8:" .. me], store["Jakealt-Realm:4:" .. me] = nil, nil, nil
    Sync.index = nil
    G.kudosSeen, G.chats = nil, nil
    T.notes = {}
    ns.db.settings.chatWhispers = true
    V.seen, V.dev, ns.db.versions = savedSeen, {}, savedVersions
    for _, e in ipairs(savedGuild) do e[1].online = e[2] end
    for i = #STUB.guild, #savedGuild + 1, -1 do table.remove(STUB.guild, i) end
    Roster:ScanGuild()
    ns.Attendance.keyCache = nil
    ns.Editor:ShowTab("home")
end

-- 0.16.7: guildmates' whispers in the chat window ------------------------------------------------
do
    local Chat, Sync, Roster, T, Home, UI = ns.Chat, ns.Sync, ns.Roster, ns.GroupToast, ns.Home, ns.UI
    local G = ns.db.guild
    local me = Sync:Me()
    -- A has chat, B has it too, C is on an old version, D is offline, E has never had the addon
    local A, B, C, D, E = "Raider03-Realm", "Raider04-Realm", "Raider05-Realm", "Raider06-Realm", "Noaddon-Realm"
    local savedGuild = {}
    for i, m in ipairs(STUB.guild) do savedGuild[i] = { m, m.online } end
    local function member(name, online)
        for _, m in ipairs(STUB.guild) do
            if m.name == name then m.online = online return end
        end
        table.insert(STUB.guild, { name = name, rankIndex = 2, level = 60, online = online, class = "MAGE" })
    end
    member(A, true) member(B, true) member(C, true) member(D, false) member(E, true)
    Roster:ScanGuild()
    local V = ns.Version
    local savedSeen, savedVersions = V.seen, ns.db.versions
    V.seen, V.dev, ns.db.versions = { [A] = "0.16.7", [B] = "0.16.5", [C] = "0.16.4" }, {}, {}
    G.chats = nil
    wipe(Chat.off) wipe(Chat.picked) wipe(Chat.pending)
    Chat.current = nil
    T.notes = {}
    if T.frame then T.frame:Hide() end
    if Chat.frame then Chat.frame:Hide() end
    ns.Editor:ShowTab("home")
    local function count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
    local function last(c) return c.log[#c.log] end
    local function whisperIn(text, from) STUB.Fire("CHAT_MSG_WHISPER", text, from) end
    local function whisperOut(text, to) STUB.Fire("CHAT_MSG_WHISPER_INFORM", text, to) end

    -- who can be chatted with now: the whole guild that's online
    check(Chat:HasChat(A) and Chat:HasChat(B) and not Chat:HasChat(C) and not Chat:HasChat(E) and not Chat:HasChat(me),
        "whispers: the addon's own lines still only reach who has chat")
    check(Chat:CanChat(A) and Chat:CanChat(C) and Chat:CanChat(E) and not Chat:CanChat(D) and not Chat:CanChat(me)
        and not Chat:CanChat("Stranger-Realm"), "whispers: but any guildmate who's online can be chatted with")
    local buddies = Chat:Buddies()
    local pos, ordered, seenPlain = {}, true, false
    for i, n in ipairs(buddies) do
        pos[n] = i
        if Chat:HasChat(n) then ordered = ordered and not seenPlain else seenPlain = true end
    end
    check(pos[A] == 1 and pos[B] == 2 and pos[C] and pos[E] and not pos[D] and not pos[me] and ordered,
        "whispers: the list has everyone online, those with chat first")

    -- a guildmate's whisper lands in the chat with them: unread, no pop-up or sound of ours (the game has shown it)
    STUB.sounds, STUB.sent, STUB.said = {}, {}, {}
    local link = "want this? |cff0070dd|Hitem:2100::::::::60|h[Precisely Calibrated Boomstick]|h|r"
    whisperIn(link, E)
    local ec = Chat:Get({ me, E })
    check(ec and #ec.log == 1 and last(ec).from == E and last(ec).w == true and last(ec).text == link and ec.unread == 1 and count(G.chats) == 1,
        "whispers: one from a guildmate is kept in the chat with them, unread")
    check(not (T.frame and T.frame:IsShown()) and #T.notes == 0 and #STUB.sounds == 0 and #STUB.sent == 0,
        "whispers: no pop-up or sound of ours for it, and nothing sent")
    Home:Refresh()
    check(Home.chatsCard.rows[1].item == ec and Home.chatsCard.rows[1].right:GetText() == "1"
        and Home.chatsCard.rows[1].text:GetText():find("|Hitem:2100", 1, true), "whispers: Home's Chats card counts it (the link as the game sent it)")
    -- one we sent from the game's own chat box is kept too, and answering means we've read theirs
    whisperOut("yes please", "Noaddon-Realm")
    check(#ec.log == 2 and last(ec).from == me and last(ec).w == true and last(ec).text == "yes please" and ec.unread == 0
        and Home.chatsCard.rows[1].right:GetText() == "now" and Home.chatsCard.rows[1].text:GetText():find("You: yes please", 1, true),
        "whispers: our own whisper to them too, which marks theirs read")
    whisperIn("short name works", "Noaddon")
    check(#ec.log == 3 and last(ec).from == E, "whispers: (however the game spells their name)")
    -- what isn't kept
    local function ignored(fn)
        local chats, lines = count(G.chats), #ec.log
        fn()
        return count(G.chats) == chats and #ec.log == lines
    end
    check(ignored(function() whisperIn("psst", "Stranger-Realm") end) and ignored(function() whisperOut("hi", "Stranger-Realm") end),
        "whispers: not with people outside the guild")
    check(ignored(function() whisperIn({ __secret = true }, E) end) and ignored(function() whisperIn("hi", { __secret = true }) end)
        and ignored(function() whisperIn(nil, E) end) and ignored(function() whisperIn("", E) end),
        "whispers: not ones the game hides from addons, or empty ones")
    check(ignored(function() whisperIn("me?", "Jake-Realm") end), "whispers: not our own name")
    ns.db.settings.chatWhispers = false
    check(ignored(function() whisperIn("off", E) end) and not Chat:CanChat(E) and Chat:CanChat(A), "whispers: none when Guild whispers is off")
    ns.db.settings.chatWhispers = true
    ns.db.settings.chat = false
    check(ignored(function() whisperIn("chat off", E) end), "whispers: none when group chat is off")
    ns.db.settings.chat = true

    -- shown as the game sent it (its links work); an addon line is still escaped
    Chat:Open(ec)
    local msgs = Chat.log.__messages
    check(msgs[1]:find("|Hitem:2100", 1, true) and not msgs[1]:find("||Hitem", 1, true) and msgs[1]:find("Noaddon", 1, true),
        "whispers: shown as the game sent it, item link and all")
    local got
    SetItemRef = function(l, t, b) got = l .. "/" .. b end
    STUB.Script(Chat.log, "OnHyperlinkClick", "item:2100::::::::60", "[Precisely Calibrated Boomstick]", "LeftButton")
    check(got == "item:2100::::::::60/LeftButton", "whispers: clicking a link opens it like the game's chat does")
    SetItemRef = nil
    -- reading the open chat: a new whisper just appears
    whisperIn("you there", E)
    check(ec.unread == 0 and Chat.log.__messages[#Chat.log.__messages]:find("you there", 1, true), "whispers: in the open chat it just appears")

    -- the heading says how a line gets there
    check(Chat.pane.how:GetText() == "Sent as whispers", "whispers: the chat with someone without the addon says lines go as whispers")
    -- typing to them sends an ordinary whisper; the line is the game's echo of it, once
    STUB.said, STUB.sent, STUB.timers = {}, {}, {}
    local lines = #ec.log
    check(Chat:Send(ec, "be there | soon") == true and #STUB.said == 1 and STUB.said[1].type == "WHISPER" and STUB.said[1].target == "Noaddon"
        and STUB.said[1].text == "be there || soon" and #STUB.sent == 0, "whispers: a line to them goes as a whisper (a | made safe), not an addon message")
    check(#ec.log == lines + 1 and last(ec).from == me and last(ec).w and Chat.pending[E] == nil, "whispers: and shows once, when the game says it went")
    STUB.Advance(Chat.WHISPER_WAIT + 1)
    check(#ec.log == lines + 1, "whispers: (no complaint afterwards)")
    -- one the game swallows is noticed
    STUB.whisperLost = true
    lines = #ec.log
    check(Chat:Send(ec, "hello?") == true and #ec.log == lines and Chat.pending[E] ~= nil, "whispers: one that doesn't come back isn't shown as sent")
    STUB.Advance(Chat.WHISPER_WAIT)
    check(#ec.log == lines + 1 and last(ec).sys and last(ec).text == "That didn't reach Noaddon. Whisper them from the game's chat box."
        and Chat.pending[E] == nil, "whispers: and after a moment the chat says it didn't go")
    STUB.whisperLost = nil
    -- the game refusing chat, or no way to send: said at once, the text stays in the box
    STUB.restricted = true
    STUB.said = {}
    lines = #ec.log
    Chat.input:SetText("in a boss fight")
    STUB.Script(Chat.input, "OnEnterPressed")
    check(#STUB.said == 0 and #ec.log == lines + 1 and last(ec).sys and last(ec).text:find("Whispers can't be sent from here right now", 1, true)
        and Chat.input:GetText() == "in a boss fight", "whispers: when the game is refusing chat it says so and keeps what was typed")
    STUB.restricted = false
    local realSend = SendChatMessage
    SendChatMessage = function() error("blocked") end
    lines = #ec.log
    check(Chat:Send(ec, "blocked?") == false and #ec.log == lines + 1 and last(ec).text:find("That didn't reach Noaddon", 1, true)
        and Chat.pending[E] == nil, "whispers: a whisper the game throws out is reported at once")
    -- the newer call is used where the client has it
    local viaNew
    C_ChatInfo.SendChatMessage = function(text, chatType, _, target) viaNew = text .. ">" .. chatType .. ">" .. target end
    Chat:Send(ec, "new api")
    check(viaNew == "new api>WHISPER>Noaddon", "whispers: sent with C_ChatInfo.SendChatMessage where there is one")
    C_ChatInfo.SendChatMessage = nil
    SendChatMessage = realSend
    wipe(Chat.pending)
    STUB.timers = {}

    -- someone with chat still gets the addon's own lines, and nothing is whispered
    STUB.said, STUB.sent, STUB.allowance = {}, {}, 10
    Chat:OpenWith({ A })
    local ac = Chat.current
    Chat:Send(ac, "addon way")
    check(#STUB.said == 0 and #STUB.sent == 1 and STUB.sent[1].channel == "WHISPER" and STUB.sent[1].text:sub(1, 1) == "C"
        and Chat.pane.how:GetText() == "" and last(ac).w == nil, "whispers: someone with chat gets it the addon's way")
    -- unless they've turned chat off: then a whisper it is
    STUB.Fire("CHAT_MSG_ADDON", "PogRaid", "CAAAAN", "WHISPER", A)
    STUB.said, STUB.sent = {}, {}
    Chat:Send(ac, "whisper then")
    check(#STUB.said == 1 and STUB.said[1].target == "Raider03" and #STUB.sent == 0 and Chat:CanChat(A) and not Chat:HasChat(A)
        and last(ac).w, "whispers: someone who turned chat off can still be whispered")
    wipe(Chat.off)
    -- offline: nothing goes anywhere
    STUB.said, STUB.sent = {}, {}
    local dc = Chat:Get({ me, D }, true)
    Chat:Send(dc, "you on?")
    check(#STUB.said == 0 and #STUB.sent == 0 and last(dc).sys and last(dc).text:find("Nobody in this chat is online", 1, true),
        "whispers: nobody offline is whispered")
    Chat:Delete(dc)
    -- an old version of the addon: a whisper too (it has no chat)
    STUB.said, STUB.sent = {}, {}
    Chat:OpenWith({ C })
    Chat:Send(Chat.current, "update your addon")
    check(#STUB.said == 1 and STUB.said[1].target == "Raider05" and #STUB.sent == 0 and Chat.pane.how:GetText() == "Sent as whispers",
        "whispers: someone on an old version is whispered")
    -- the practice chat still sends nothing
    STUB.said, STUB.sent, STUB.timers = {}, {}, {}
    SlashCmdList.POGRAID("chat test")
    local partner = Chat:Others(Chat.current)[1]
    member(partner, true) -- (online and without chat: a real chat with them would go as whispers)
    Roster:ScanGuild()
    V.seen[partner] = nil
    Chat:Refresh()
    Chat:Send(Chat.current, "testing")
    check(Chat.current.test and #STUB.said == 0 and #STUB.sent == 0 and Chat.pane.how:GetText() == "", "whispers: the practice chat whispers nobody")
    Chat:Delete(Chat.current)
    STUB.timers = {}

    -- the picker: everyone online, the whisper-only marked; they can't be put in a group
    Chat:Open(ec)
    local pk = Chat.picker
    STUB.Script(Chat.newBtn, "OnClick")
    local function rowFor(name)
        for off = 0, 80 do
            pk.offset = off
            Chat:RefreshPicker()
            for _, row in ipairs(pk.rows) do
                if row:IsShown() and row.item == name then return row end
            end
            if pk.offset ~= off then break end
        end
    end
    check(rowFor(A).right:GetText() == "" and rowFor(E).right:GetText() == "whisper" and rowFor(C).right:GetText() == "whisper"
        and not rowFor(D) and not rowFor(me), "whispers: someone without chat is marked in the picker")
    check(#Chat:PickList() > Chat.layout.PICK_ROWS and pk.scroll.tex:IsShown(), "whispers: (a guild's worth of names scrolls)")
    local addonHint = "A group chat needs the addon on everyone."
    STUB.printed = {}
    STUB.Script(rowFor(A), "OnClick")
    local eRow = rowFor(E)
    check(eRow.dim and not eRow:IsEnabled() and eRow:GetAlpha() < 0.5 and pk.hint:GetText() == addonHint,
        "whispers: with someone picked, people without chat are greyed out and the picker says why")
    check(not rowFor(B).dim and rowFor(B):IsEnabled() and rowFor(B):GetAlpha() == 1 and not rowFor(A).dim, "whispers: (people with chat aren't)")
    STUB.Script(rowFor(E), "OnClick")
    check(Chat.picked[A] and not Chat.picked[E] and count(Chat.picked) == 1 and #STUB.printed == 0,
        "whispers: a greyed-out name can't be picked, and nothing is printed to chat about it")
    STUB.Script(rowFor(B), "OnClick")
    check(Chat.picked[A] and Chat.picked[B] and pk.start.label:GetText() == "Start chat (2)", "whispers: (people with chat still group up)")
    STUB.Script(rowFor(A), "OnClick")
    STUB.Script(rowFor(B), "OnClick")
    check(count(Chat.picked) == 0 and not rowFor(E).dim and not rowFor(C).dim and pk.hint:GetText() == "Pick one person, or several for a group.",
        "whispers: with nobody picked, anyone can be")
    STUB.Script(rowFor(E), "OnClick")
    check(Chat.picked[E] and rowFor(E).sel:IsShown() and not rowFor(E).dim and rowFor(A).dim and rowFor(C).dim and pk.hint:GetText() == addonHint
        and pk.start:IsEnabled() and pk.start.label:GetText() == "Start chat", "whispers: someone without chat is picked alone")
    STUB.Script(rowFor(A), "OnClick")
    check(not Chat.picked[A] and count(Chat.picked) == 1, "whispers: nobody can be added to them")
    STUB.Script(pk.start, "OnClick")
    check(Chat.current == ec and count(Chat.picked) == 0 and not Chat.picking, "whispers: Start chat opens the chat with them")
    -- the search finds people by any part of their name
    STUB.Script(Chat.newBtn, "OnClick")
    pk.search:SetText("noadd")
    check(pk.rows[1].item == E and not pk.rows[2]:IsShown(), "whispers: the search finds someone without the addon")
    STUB.Script(pk.search, "OnEnterPressed")
    check(Chat.current == ec and not Chat.picking, "whispers: and Enter opens the chat with them")
    -- a chat holds eight: with seven picked nobody else can be
    local extra = {}
    for i = 1, 8 do
        extra[i] = ("Extra%02d-Realm"):format(i)
        member(extra[i], true)
        V.seen[extra[i]] = "0.16.7"
    end
    Roster:ScanGuild()
    STUB.Script(Chat.newBtn, "OnClick")
    for i = 1, 7 do STUB.Script(rowFor(extra[i]), "OnClick") end
    check(count(Chat.picked) == 7 and rowFor(extra[8]).dim and rowFor(A).dim and not rowFor(extra[1]).dim
        and pk.hint:GetText() == "A chat holds 8 people at most." and pk.start.label:GetText() == "Start chat (7)", "picker: a chat holds eight, us included")
    STUB.Script(rowFor(extra[8]), "OnClick")
    check(count(Chat.picked) == 7, "picker: (the eighth can't be picked)")
    -- someone picked who logs off drops out
    member(extra[1], false)
    Roster:ScanGuild()
    STUB.Fire("GUILD_ROSTER_UPDATE")
    check(count(Chat.picked) == 6 and not Chat.picked[extra[1]] and not rowFor(extra[1]) and not rowFor(extra[8]).dim
        and pk.start.label:GetText() == "Start chat (6)", "picker: someone picked who logs off drops out")
    pk.offset = 0
    STUB.Script(pk.cancel, "OnClick")
    check(Chat.current == ec and not Chat.picking, "picker: (and Cancel)")

    -- someone coming or going redraws the list and the heading, not the log (it would lose its place)
    local kept = Chat.log.__messages
    V.seen[E] = "0.16.7"
    STUB.Fire("GUILD_ROSTER_UPDATE")
    check(Chat.log.__messages == kept and Chat.pane.how:GetText() == "", "whispers: a roster change updates the heading and leaves the log alone")
    V.seen[E] = nil
    STUB.Fire("GUILD_ROSTER_UPDATE")
    check(Chat.pane.how:GetText() == "Sent as whispers", "whispers: (and back)")

    -- the Guild whispers check in the title bar
    local chk = Chat.whisperCheck
    local fl, ft, fw, fh = STUB.rect(Chat.frame)
    local kl, kt, kw, kh = STUB.rect(chk)
    check(chk.checked and chk.label:GetText() == "Guild whispers" and near(kt - kh / 2, ft - 15) and kl + kw <= fl + fw - 10 - 21 - 6 + 0.5
        and kl > fl + 60, "chat window: a Guild whispers check in the title bar, clear of the title and the X")
    STUB.Script(chk, "OnClick")
    check(ns.db.settings.chatWhispers == false and not chk.checked and not Chat:CanChat(E) and Chat.pane.how:GetText() == "",
        "chat window: unticking it turns whispers off")
    STUB.Script(Chat.newBtn, "OnClick")
    check(rowFor(A) and not rowFor(E) and not rowFor(C), "chat window: and the picker goes back to who has chat")
    STUB.Script(chk, "OnClick")
    check(ns.db.settings.chatWhispers == true and chk.checked and Chat:CanChat(E) and rowFor(E), "chat window: and on again, with everyone back")
    pk.offset = 0
    STUB.Script(pk.cancel, "OnClick")

    -- Sound and Pop-ups (0.16.8, Jake: "mute sounds ... a disable popups button"): the window's own switches for a new line
    local snd, pop = Chat.soundCheck, Chat.toastCheck
    local sl, st, sw, sh = STUB.rect(snd)
    local ol, ot, ow, oh = STUB.rect(pop)
    kl, kt, kw, kh = STUB.rect(chk)
    check(snd.checked and pop.checked and snd.label:GetText() == "Sound" and pop.label:GetText() == "Pop-ups"
        and ns.db.settings.chatSound == true and ns.db.settings.chatToasts == true, "chat window: Sound and Pop-ups switches, on by default")
    check(near(ol - (sl + sw), 16) and near(kl - (ol + ow), 16) and near(st, ot) and near(ot, kt) and sh == kh and sl > fl + 60
        and sw == 22 + snd.label:GetStringWidth() and ow == 22 + pop.label:GetStringWidth() and kw == 22 + chk.label:GetStringWidth()
        and near(kl + kw, fl + fw - 37), "chat window: the three switches in a row before the X, each as wide as its words, 16px apart")
    STUB.Script(snd, "OnEnter")
    check(GameTooltip.shown and GameTooltip.lines[1] == "Sound", "chat window: each switch says what it does when hovered")
    STUB.Script(snd, "OnLeave")
    check(not GameTooltip.shown, "chat window: (and the tooltip goes)")
    Chat.frame:Hide()
    T.notes = {}
    T.frame:Hide()
    local function lineFrom(text)
        STUB.sounds = {}
        STUB.Fire("CHAT_MSG_ADDON", "PogRaid", "CAAAAM" .. Sync.Enc(#me, 2) .. me .. text, "WHISPER", A)
    end
    local wa = Chat:Get({ me, A }, true)
    lineFrom("both on")
    check(T.frame:IsShown() and STUB.sounds[1] == SOUNDKIT.TELL_MESSAGE and wa.log[#wa.log].text == "both on", "chat window: (a new line pops up and sounds)")
    T.frame:Hide()
    STUB.Script(snd, "OnClick")
    lineFrom("muted")
    check(ns.db.settings.chatSound == false and not snd.checked and T.frame:IsShown() and T.frame.text:GetText():find("muted", 1, true)
        and #STUB.sounds == 0, "chat window: Sound off: the pop-up without the sound")
    T.frame:Hide()
    STUB.Script(snd, "OnClick")
    STUB.Script(pop, "OnClick")
    local unread = wa.unread
    lineFrom("no pop-up")
    check(ns.db.settings.chatToasts == false and not pop.checked and snd.checked and not T.frame:IsShown() and #T.notes == 0
        and STUB.sounds[1] == SOUNDKIT.TELL_MESSAGE and wa.unread == unread + 1, "chat window: Pop-ups off: the sound and the unread count, no pop-up")
    STUB.Script(snd, "OnClick")
    lineFrom("silent")
    check(not T.frame:IsShown() and #T.notes == 0 and #STUB.sounds == 0 and wa.unread == unread + 2 and wa.log[#wa.log].text == "silent",
        "chat window: both off: the line just waits, unread")
    -- other pop-ups are their own business
    T:Note({ text = "something else" })
    check(T.frame:IsShown() and T.frame.text:GetText() == "something else", "chat window: (other pop-ups aren't touched)")
    T.frame:Hide()
    STUB.Script(snd, "OnClick")
    STUB.Script(pop, "OnClick")
    check(ns.db.settings.chatSound == true and ns.db.settings.chatToasts == true and snd.checked and pop.checked, "chat window: and both on again")

    -- In game chat (0.16.8, Jake): off unless ticked; a new line is then also written to the game's chat box
    do
        local echo = Chat.echoCheck
        local el, et, ew = STUB.rect(echo)
        local sl2 = STUB.rect(snd)
        check(ns.db.settings.chatEcho == false and not echo.checked and echo.label:GetText() == "In game chat"
            and near(sl2 - (el + ew), 16) and near(et, st) and el > fl + 60, "chat window: an In game chat switch, off, 16px before Sound")
        STUB.printed = {}
        lineFrom("quiet")
        check(#STUB.printed == 0, "in game chat: nothing is written there by default")
        STUB.Script(echo, "OnClick")
        lineFrom("loud | one")
        check(ns.db.settings.chatEcho == true and echo.checked and #STUB.printed == 1 and STUB.printed[1] == "[Pog chat] Raider03: loud || one",
            "in game chat: ticked, a new line is written to the chat box too (escaped)")
        whisperIn("a real whisper", E)
        Chat:Send(wa, "my own line")
        check(#STUB.printed == 1, "in game chat: not whispers (the game prints those), nor our own lines")
        Chat:Open(wa)
        lineFrom("while open")
        check(#STUB.printed == 2, "in game chat: also while that chat is open")
        Chat.frame:Hide()
        T.notes = {}
        T.frame:Hide()
    end

    -- a group chat's own name and picture, shared with the group (0.16.8, Jake: "like imessage")
    do
        local function wireTo(op, from, others, rest)
            local list = table.concat(others, ",")
            STUB.Fire("CHAT_MSG_ADDON", "PogRaid", "CAAAA" .. op .. Sync.Enc(#list, 2) .. list .. rest, "WHISPER", from)
        end
        local function meta(from, others, at, icon, name) wireTo("R", from, others, at .. "~" .. icon .. "~" .. name) end
        local function sys(c) local l = c.log[#c.log] return l.sys and l.text end
        wipe(Chat.told)
        STUB.printed = {}
        STUB.now = STUB.now + 2 -- (so this chat is the newest, whatever else was said this second)
        wireTo("M", A, { me, B }, "hi all")
        local gc = Chat:Get({ me, A, B })
        check(gc and Chat:IsGroup(gc) and not Chat:IsGroup(wa) and Chat:Picture(gc) == Chat.GROUP_ICON and Chat:Picture(wa) == ns.Profiles:Portrait(A)
            and Chat:Title(gc, true) == "Raider03, Raider04" and gc.name == nil, "group: a chat of three or more is a group, with a picture of its own")
        check(STUB.printed[1] == "[Raider03, Raider04] Raider03: hi all", "in game chat: a group's line says which group")
        T.notes = {}
        T.frame:Hide()
        -- its heading: the picture, who's in it, and Edit; a one-to-one chat has the person's portrait and no Edit
        Chat:Open(gc)
        local pane = Chat.pane
        local pl, pt, pw = STUB.rect(pane)
        local il, it, iw, ih = STUB.rect(pane.pic)
        local wl = STUB.rect(pane.with)
        local dl, dt, dw, dh = STUB.rect(pane.edit)
        check(pane.pic:IsShown() and pane.pic:GetTexture() == Chat.GROUP_ICON and pane.edit:IsShown() and pane.edit.label:GetText() == "Edit"
            and near(il - pl, 10) and iw == 16 and ih == 16 and near(wl - (il + iw), 6) and near(it - ih / 2, dt - dh / 2)
            and (pl + pw) - (dl + dw) <= 12 and wl + pane.with:GetWidth() <= dl, "group: its heading has the picture, the people and Edit")
        local row = Chat.left.rows[1]
        local rl = STUB.rect(row)
        local ril, _, riw = STUB.rect(row.pic)
        local rtl = STUB.rect(row.text)
        check(row.item.chat == gc and row.pic:IsShown() and row.pic:GetTexture() == Chat.GROUP_ICON and near(ril - rl, 6) and riw == 16
            and near(rtl - (ril + riw), 6), "group: its row in the list has the picture before the name")
        Chat:Open(wa)
        check(pane.pic:GetTexture() == ns.Profiles:Portrait(A) and not pane.edit:IsShown(), "group: a one-to-one chat shows the person, and has no Edit")
        local menu
        local realMenu, realPrompt, realPicker = UI.ShowMenu, UI.Prompt, UI.Picker
        UI.ShowMenu = function(_, e) menu = e end
        local function entry(text)
            for _, e in ipairs(menu or {}) do if e.text == text then return e end end
        end
        Chat:Menu(row, wa)
        check(#menu == 2 and menu[1].header and menu[2].text == "Delete chat", "group: a one-to-one chat's menu is just Delete")
        check(Chat:SetMeta(wa, "nope", 1) == false and wa.name == nil and wa.icon == nil, "group: a one-to-one chat can't be named")
        Chat:Open(gc)
        STUB.Script(pane.edit, "OnClick")
        check(menu[1].text == "Raider03, Raider04" and entry("Name this chat") and entry("Choose a picture") and menu[#menu].text == "Delete chat",
            "group: Edit offers a name and a picture")
        -- naming it
        local asked
        UI.Prompt = function(_, _, _, label, initial, onAccept) asked = { label = label, initial = initial, accept = onAccept } end
        entry("Name this chat").func()
        STUB.sent, STUB.allowance = {}, 10
        STUB.printed = {}
        asked.accept("  Raid | planning crew for tonight ")
        local list = A .. "," .. B
        check(asked.initial == "" and gc.name == "Raid / planning crew for" and #gc.name == Chat.MAX_NAME and gc.metaAt ~= nil
            and sys(gc) == 'You named the chat "Raid / planning crew for".', "group: naming it (tidied and cut to length)")
        check(#STUB.sent == 2 and STUB.sent[1].target == "Raider03" and STUB.sent[2].target == "Raider04" and STUB.sent[1].channel == "WHISPER"
            and STUB.sent[1].text:sub(6) == "R" .. Sync.Enc(#list, 2) .. list .. gc.metaAt .. "~~Raid / planning crew for",
            "group: the name is whispered to everyone in the chat")
        check(Chat:Title(gc) == gc.name and pane.with:GetText() == gc.name and Chat.left.rows[1].text:GetText() == gc.name
            and Chat:Members(gc, true) == "Raider03, Raider04", "group: it goes by its name in the heading and the list")
        ns.Editor:ShowTab("home")
        Home:RefreshChats()
        check(Home.chatsCard.rows[1].item == gc and Home.chatsCard.rows[1].text:GetText():find("Raid / planning crew for", 1, true)
            and Home.chatsCard.rows[1].text:GetText():find("Raider03: hi all", 1, true) and Home.chatsCard.rows[1].pic:GetTexture() == Chat.GROUP_ICON,
            "group: and on Home's Chats card, with who said the last line")
        local stamp = gc.metaAt
        STUB.sent = {}
        asked.accept("Raid / planning crew for")
        check(#STUB.sent == 0 and gc.metaAt == stamp, "group: the same name again changes nothing")
        STUB.Script(pane.edit, "OnClick")
        check(entry("Rename this chat") ~= nil and entry("Name this chat") == nil, "group: (then it's Rename)")
        entry("Rename this chat").func()
        check(asked.initial == "Raid / planning crew for", "group: renaming starts from its name")
        -- a picture, from the same icons as a profile's portrait
        local offered
        UI.Picker = function(anchor, items, cols, size, onPick, rows, selected) offered = { anchor = anchor, items = items, onPick = onPick, selected = selected } end
        entry("Choose a picture").func()
        STUB.sent = {}
        offered.onPick(3)
        local icon = offered.items[3]
        check(offered.anchor == pane.pic and #offered.items >= 9 and type(icon) == "number" and gc.icon == icon and gc.metaAt > stamp
            and Chat:Picture(gc) == icon and pane.pic:GetTexture() == icon and Chat.left.rows[1].pic:GetTexture() == icon
            and sys(gc) == "You changed the chat's picture.", "group: choosing a picture")
        check(#STUB.sent == 2 and STUB.sent[2].text:sub(6) == "R" .. Sync.Enc(#list, 2) .. list .. gc.metaAt .. "~" .. icon .. "~Raid / planning crew for",
            "group: the picture is shared too")
        entry("Choose a picture").func()
        check(offered.selected == 3, "group: the picker opens on the picture it has")
        -- someone else's change: the newest wins
        STUB.sent = {}
        local at = gc.metaAt + 5
        meta(A, { me, B }, at, "135846", "Frost | squad")
        check(gc.name == "Frost / squad" and gc.icon == 135846 and gc.metaAt == at and sys(gc) == 'Raider03 named the chat "Frost / squad".'
            and #STUB.sent == 0 and pane.with:GetText() == "Frost / squad", "group: someone else's newer name and picture are taken")
        meta(B, { me, A }, at - 3, "", "Old name")
        check(gc.name == "Frost / squad" and gc.metaAt == at and #STUB.sent == 1 and STUB.sent[1].target == "Raider04"
            and STUB.sent[1].text:sub(6) == "R" .. Sync.Enc(#list, 2) .. list .. at .. "~135846~Frost / squad",
            "group: an older one is turned down, and its sender told the newer")
        meta(B, { me, A }, at - 3, "", "Old name")
        check(#STUB.sent == 1, "group: (told once)")
        meta(A, { me, B }, at, "1", "Same stamp")
        check(gc.name == "Frost / squad" and #STUB.sent == 1, "group: one with the stamp we have changes nothing")
        local lines = #gc.log
        meta(A, { me, B }, at + 1, "135846", "")
        check(gc.name == nil and gc.icon == 135846 and sys(gc) == "Raider03 removed the chat's name." and Chat:Title(gc, true) == "Raider03, Raider04",
            "group: a name can be removed")
        meta(A, { me, B }, at + 2, "135812", "")
        check(gc.icon == 135812 and sys(gc) == "Raider03 changed the chat's picture.", "group: a picture alone can change")
        -- what's turned away
        lines = #gc.log
        local chats = count(G.chats)
        meta(A, { me, B }, ns.Now() + 99999, "1", "From the future")
        meta(A, { me, B }, at + 3, "123456789", "Icon too long")
        wireTo("R", A, { me, B }, "junk")
        wireTo("R", A, { me, B }, "")
        meta(A, { B, D }, at + 3, "1", "Not our chat")
        meta("Stranger-Realm", { me, B }, at + 3, "1", "Not a guildie")
        meta(A, { me }, at + 3, "1", "Just us two")
        check(#gc.log == lines and gc.name == nil and gc.icon == 135812 and wa.name == nil and count(G.chats) == chats,
            "group: junk, a far-off date, a chat we aren't in, an outsider's or a one-to-one's are ignored")
        ns.db.settings.chat = false
        STUB.sent = {}
        meta(A, { me, B }, at + 4, "1", "While off")
        check(gc.name == nil and #STUB.sent == 0, "group: nothing is taken (or answered) with chat off")
        ns.db.settings.chat = true
        -- someone who writes without having heard it is told, once
        Chat:SetMeta(gc, "Crew", gc.icon)
        wipe(Chat.told)
        STUB.sent = {}
        wireTo("M", B, { me, A }, "what did I miss")
        check(#STUB.sent == 1 and STUB.sent[1].target == "Raider04" and STUB.sent[1].text:sub(6):find("~135812~Crew", 1, true), "group: someone who writes without having heard the name is told it")
        wireTo("M", B, { me, A }, "thanks")
        check(#STUB.sent == 1, "group: once")
        -- its pop-up and its line in the game's chat box say the name
        Chat.frame:Hide()
        T.notes = {}
        T.frame:Hide()
        STUB.printed = {}
        wireTo("M", A, { me, B }, "pull")
        check(T.frame:IsShown() and T.frame.sub:GetText() == "Crew" and STUB.printed[1] == "[Crew] Raider03: pull", "group: its pop-up and its game chat line go by the name")
        T.notes = {}
        T.frame:Hide()
        -- only people with chat are sent it
        STUB.sent = {}
        V.seen[B] = "0.16.4"
        Chat:SetMeta(gc, "Crew two", gc.icon)
        check(#STUB.sent == 1 and STUB.sent[1].target == "Raider03", "group: only people the addon reaches are sent it")
        V.seen[B] = "0.16.5"
        UI.ShowMenu, UI.Prompt, UI.Picker = realMenu, realPrompt, realPicker
        STUB.Script(Chat.echoCheck, "OnClick")
        check(ns.db.settings.chatEcho == false, "in game chat: (and off again)")
        wipe(Chat.told)
    end

    -- tidy up
    G.chats = nil
    Chat.current = nil
    Chat.frame:Hide()
    wipe(Chat.off) wipe(Chat.picked) wipe(Chat.pending)
    STUB.said, STUB.sent, STUB.timers = {}, {}, {}
    V.seen, V.dev, ns.db.versions = savedSeen, {}, savedVersions
    for _, e in ipairs(savedGuild) do e[1].online = e[2] end
    for i = #STUB.guild, #savedGuild + 1, -1 do table.remove(STUB.guild, i) end
    Roster:ScanGuild()
    ns.Attendance.keyCache = nil
    ns.Editor:ShowTab("home")
end

return results

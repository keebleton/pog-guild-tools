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
STUB.Fire("ADDON_LOADED", "PogRaid")
STUB.Fire("PLAYER_LOGIN")

check(ns.db ~= nil and #ns.db.order == 1, "load: first board created")
check(STUB.prefix == "PogRaid", "load: addon prefix registered")
check(SlashCmdList.POGRAID ~= nil, "load: slash command registered")
check(ns.On("NOT_A_REAL_EVENT", function() end) == false, "events: unknown event fails quietly")

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
    check(table.concat(order, ",") == "home,roster,attendance,loot,crafting,games,boards,settings", "tabs: Home ... Crafting, Games, Raid Plans, then Settings")
    do
        -- every gap between tab labels (and before the X) is the same: text
        -- edges from each tab's centre and its label width
        local fl, _, fw = STUB.rect(Editor.frame)
        local edges = {}
        for _, key in ipairs(order) do
            local b = Editor.tabButtons[key]
            local l, _, w = STUB.rect(b)
            local tw = b.label:GetStringWidth()
            edges[#edges + 1] = { l + w / 2 - tw / 2, l + w / 2 + tw / 2 }
        end
        local close = Editor.closeBtn
        -- the band stretches across the window (two anchors, which the stub
        -- doesn't follow), so place the X from the window's edge
        local xc = fl + fw - (12 - 7) - close:GetWidth() / 2
        edges[#edges + 1] = { xc - close.label:GetStringWidth() / 2, xc + close.label:GetStringWidth() / 2 }
        local lo, hi = math.huge, -math.huge
        for i = 2, #edges do
            local g = edges[i][1] - edges[i - 1][2]
            lo, hi = math.min(lo, g), math.max(hi, g)
        end
        check(hi - lo <= 1 and lo >= 20, ("tabs: evenly spaced, X included (gaps %.1f to %.1f)"):format(lo, hi))
        local sel = Editor.tabButtons.roster
        check(near(sel.underline:GetWidth(), sel.label:GetStringWidth() + 16), "tabs: underline is the label plus 8px each side")
    end
    local bl = STUB.rect(Editor.tabButtons.boards)
    local rl = STUB.rect(Editor.tabButtons.roster)
    check(rl < bl, "tabs: Boards button is last in the row")
    local rt = Editor.tabButtons.roster
    check(rt.bg == nil and rt.edges == nil, "tabs: plain text, no button box")
    check(rt.underline:IsShown() and not Editor.tabButtons.loot.underline:IsShown(), "tabs: selected tab underlined")
    local lootTab = Editor.tabButtons.loot
    STUB.Script(lootTab, "OnEnter")
    local hoverText = lootTab.label.__textColor
    STUB.Script(lootTab, "OnLeave")
    check(hoverText and hoverText[1] > 0.8 and lootTab.label.__textColor[1] < 0.7, "tabs: hover brightens a tab")
    local fl0, ft0, fw0, fh0 = STUB.rect(Editor.frame)
    local bl0, bt0, bw0, bh0 = STUB.rect(Editor.band)
    local ul, ut, uw, uh = STUB.rect(rt)
    check(near(bh0, 36) and near(ut - uh, bt0 - bh0), "tabs: sit on the band's bottom edge")
    local pgl, pgt = STUB.rect(rosterTab.page)
    check(near(ft0 - pgt, 16) and near(fh0, 624), "band: pages start below the band, window 16px taller")
    local _, nameTop = STUB.rect(Roster.nameBox)
    check(near((bt0 - bh0) - nameTop, 10), "band: 10px between the band and a page's first row")
    check(rosterTab.page and rosterTab.page:IsShown() and not boardsTab.page:IsShown(), "tabs: roster tab replaces the boards page")
    check(Editor.tabButtons.roster.selected and not Editor.tabButtons.boards.selected, "tabs: roster tab button selected")
    local r = Roster:Current()
    check(r and r.size == 20 and r.id and r.rev and r.by == "Jake", "roster: first roster made, with sync fields")

    local pool = Roster:PoolNames()
    check(#pool == 31, "pool: every guild member by default, whatever their level")
    local lvlRow
    Roster.search = "Levelling"
    Roster:RefreshPool()
    Roster.search = nil
    for _, row in ipairs(Roster.poolRows) do if row.player == "Levelling-Realm" then lvlRow = row end end
    check(lvlRow and lvlRow.name:GetText():find("59", 1, true), "pool: level shown for players below the cap")
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
    check(ns.db.guild.maxLevelOnly == false and ns.db.version == 2, "migration: old default filter turned off")
    ns.db.guild.maxLevelOnly = true
    STUB.Fire("ADDON_LOADED", "PogRaid")
    check(ns.db.guild.maxLevelOnly == true, "migration: a filter you turn on stays on")
    Roster:ToggleRank(4, 5)
    pool = Roster:PoolNames()
    inPool = {}
    for _, n in ipairs(pool) do inPool[n] = true end
    check(#pool == 29 and not inPool["Socialite-Realm"], "pool: rank filter drops socials")
    check(Roster:RoleOf(pool[1]) == nil, "pool: nobody has a role until one is set (no class guessing)")
    check(Roster.poolInfo:GetText():find("29 raiders", 1, true) and Roster.poolInfo:GetText():find("online", 1, true),
        "pool: summary line")

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
    check(menu[3].text:find("> ", 1, true) == 1, "marks: menu shows the current mark")

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
    check(Att:Credit(s, "Raider01-Realm") == 1 and Att:Credit(s, "Raider09-Realm") == 0.5, "attendance: credit is the share of snapshots")
    check(Att:Status(s, "Raider01-Realm") == "present" and Att:Status(s, "Raider09-Realm") == "partial", "attendance: status labels")

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
    check(math.abs(r1.last8 - 2 / 3) < 1e-9 and r1.attended == 2, "summary: missed one of three nights")
    check(r2.last8 == 1 and r2.all == 1, "summary: perfect attendance")
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
    check(table.concat(GameTooltip.lines, "|"):find("67%% / 67%%") ~= nil, "roster: attendance still in the hover tooltip")
    STUB.Script(row, "OnLeave")

    -- tab UI
    SlashCmdList.POGRAID("attendance")
    check(Att.page and Att.page:IsShown(), "attendance: tab opens")
    check(Att.listRows[1].label:GetText() == "Summary" and Att.listRows[2].sessionId == s3.id, "attendance: summary first, newest night next")
    check(Att:Viewing() == s3, "attendance: opens on the night last recorded")
    STUB.Script(Att.listRows[1], "OnClick")
    check(Att.headCells[3].text:GetText():find("LAST 8", 1, true) and Att.tableRows[1].player ~= nil, "attendance: summary table")
    STUB.Script(Att.headCells[1], "OnClick")
    check(Att.sortCol == "name" and Att.tableRows[1].player < Att.tableRows[2].player, "attendance: header click sorts")
    Att.sortCol = nil
    STUB.Script(Att.listRows[4], "OnClick")
    check(Att:Viewing() == s and Att.headCells[2].text:GetText() == "STATUS", "attendance: clicking a night shows its players")
    check(Att.info:GetText():find("1 kill, 1 wipe", 1, true), "attendance: night info line")
    check(Att.startBtn:IsEnabled() ~= false, "attendance: start enabled when not recording")

    -- export
    local csv = Att:CSV()
    check(csv:find("^Player,Last 4,Last 8,All,Nights attended\n") and csv:find("\nRaider01,67,67,67,2", 1, true), "export: CSV")
    check(Att:DiscordText():find("Raider02 100%", 1, true), "export: Discord text")

    -- delete a night (two clicks), tombstone kept
    STUB.Script(Att.deleteBtn, "OnClick")
    STUB.Script(Att.deleteBtn, "OnClick")
    check(G.sessions[s.id].deleted and #Att:Sessions() == 2 and Att:Viewing() == nil, "attendance: delete night leaves a tombstone")

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
    raid({ 1, 5 })
    Att:Snapshot(sb)
    check(sb.benchSnaps["Raider05-Realm"] == 1 and sb.present["Raider05-Realm"] == 1, "attendance: bench time only while not in the raid")
    Att:End()
    table.remove(r2.bench)
    Att:DeleteSession(sb)

    -- windows: ten nights, Raider03 only came to the two oldest
    local saved = {}
    for id, x in pairs(G.sessions) do saved[id] = x end
    wipe(G.sessions)
    for i = 1, 10 do
        local present = { ["Raider02-Realm"] = 1 }
        if i <= 2 then present["Raider03-Realm"] = 1 end
        G.sessions["n" .. i] = { id = "n" .. i, name = "Night " .. i, start = 1000 * i, stop = 1000 * i + 10, snaps = 1,
            present = present, benchSnaps = {}, bosses = {}, overrides = {} }
    end
    Att.cache = nil
    local w = Att:Summary().byName["Raider03-Realm"]
    check(w.last4 == 0 and w.last8 == 0 and math.abs(w.all - 0.2) < 1e-9 and w.attended == 2, "summary: last 4 / last 8 / all windows")
    G.sessions["n9"].present["Raider03-Realm"] = 1
    Att.cache = nil
    w = Att:Summary().byName["Raider03-Realm"]
    check(w.last4 == 0.25 and w.last8 == 0.125, "summary: a recent night counts in both windows")
    wipe(G.sessions)
    for id, x in pairs(saved) do G.sessions[id] = x end
    Att.cache = nil

    -- layout: same grid as the roster tab
    local page = Att.page
    local pl, pt = STUB.rect(page)
    local tl, tt, tw, th = STUB.rect(Att.table)
    local ll, lt, lw, lh = STUB.rect(Att.listRows[1]:GetParent() or Att.table)
    check(near(tl - pl, 12 + 262 + 12) and near(tl + tw, pl + 902 - 12), "layout: table fills the right column")
    check(near(pt - tt, 98) and near(th, 464), "layout: table on the list rows of the grid")
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
    check(tip:find("Attendance (4 / 8 / all)", 1, true) and tip:find("Officer, level 60", 1, true), "roster: tooltip has rank and attendance")
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
    check(Loot.playerRows[1].label:GetText() == "All players" and Loot.playerRows[1].count:GetText() == "7",
        "filter: player list keeps all players with counts")
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

    -- header: MOTD, stats, logo, level spread
    STUB.motd = "Raid Thursday 8pm, bring flasks"
    STUB.guildInfo = "Loot: council. Attendance 75% for priority."
    STUB.canEditMOTD = false
    Home:Refresh()
    local hd = Home.header
    check(hd.name:GetText() == "Pog Squad" and hd.motd:GetText() == STUB.motd, "header: guild name and MOTD")
    check(hd.logo.__texture:find("Media\\logo", 1, true) and hd.plate and hd.ring == nil, "header: guild logo on a plate, no ring")
    local m, o, d = Home:StatValues()
    check(hd.tiles[1].label:GetText() == "MEMBERS" and hd.tiles[1].value:GetText() == tostring(m)
        and hd.tiles[2].label:GetText() == "ONLINE" and hd.tiles[2].value:GetText() == tostring(o)
        and hd.tiles[3].label:GetText() == "DINGS TODAY" and hd.tiles[3].value:GetText() == tostring(d), "header: stat tiles")
    check(hd.edit == nil and hd.stats == nil, "header: no MOTD edit button, no stats line")
    -- launch countdown tile
    local left = Home:LaunchTime() - ns.Now()
    check(hd.tiles[4]:IsShown() and hd.tiles[4].label:GetText() == "LAUNCH IN"
        and hd.tiles[4].value:GetText() == math.ceil(left / 86400) .. "d", "header: days until Forever launches")
    STUB.Script(hd.tiles[4], "OnEnter")
    check(GameTooltip.lines[2] == "Launches November 4, 2026", "header: countdown tooltip names the date")
    local _, _, nameW = STUB.rect(hd.name)
    local t1l, _, t1w = STUB.rect(hd.tiles[1])
    local t4l, _, t4w = STUB.rect(hd.tiles[4])
    local chl = STUB.rect(Home.chart)
    local hl0 = STUB.rect(hd)
    check(near(t1w, 92) and near(hl0 + 88 + nameW + 16, t1l) and near(t4l + t4w + 20, chl), "header: name, four tiles and chart side by side")
    local _, _, mw0, mh0 = STUB.rect(hd.motd)
    check(near(mw0, nameW) and near(mh0, 28), "header: message of the day gets two lines")
    -- countdown: hours on the last day, Live! on the day, gone a week later
    local realNow = STUB.now
    STUB.now = realNow + left - 5 * 3600
    check(Home:Countdown() == "5h", "header: hours on the last day")
    STUB.now = realNow + left + 3600
    check(Home:Countdown() == "Live!", "header: Live! on launch day")
    STUB.now = realNow + left + 8 * 86400
    Home:Refresh()
    local _, _, wideName = STUB.rect(hd.name)
    check(not hd.tiles[4]:IsShown() and near(wideName, nameW + 92), "header: countdown retires, the text gets the space back")
    STUB.now = realNow
    Home:Refresh()
    STUB.canEditMOTD = false
    local counts, members = Home:LevelSpread()
    local sum, sixty = 0, 0
    for _, n in ipairs(counts) do sum = sum + n end
    for _, pl in pairs(G.players) do if pl.inGuild and pl.level and pl.level >= 56 then sixty = sixty + 1 end end
    check(sum == members and counts[12] == sixty and counts[1] >= 1, "chart: members bucketed by level")
    check(Home.chart.bars[12].count == counts[12] and Home.chart.bars[12].fill.__h > 0, "chart: bars sized by count")
    STUB.Script(Home.chart.bars[1], "OnEnter")
    check(GameTooltip.lines[1] == "Levels 1-5", "chart: hover names the level range")

    -- achievements in the activity feed
    local ach = "|cffffff00|Hachievement:6:Jake:1:9:25:26:0:0:0:0|h[Level 10]|h|r"
    STUB.Fire("CHAT_MSG_GUILD_ACHIEVEMENT", "%s has earned the achievement " .. ach .. "!", "Raider01-Realm")
    check(G.feed[1].kind == "ach" and G.feed[1].value == ach and G.feed[1].name == "Raider01-Realm", "feed: achievement logged with its link")
    check(Home:FeedText(G.feed[1]):find("earned", 1, true) and Home:FeedText(G.feed[1]):find("[Level 10]", 1, true), "feed: achievement text")
    STUB.Fire("CHAT_MSG_GUILD_ACHIEVEMENT", "no link here", "Raider01-Realm")
    check(G.feed[1].value == ach, "feed: messages without an achievement ignored")
    Home.leftMode = "feed"
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
        and bc.posts[1].meta:GetText():find("0 comments", 1, true), "board: post listed")
    STUB.Script(bc.posts[1], "OnClick")
    check(Home.openPost ~= nil and bc.thread:IsShown() and bc.back:IsShown() and not bc.newPost:IsShown(), "board: clicking a post opens the thread")
    check(bc.thread.body:GetText():find("Flasks and food", 1, true), "board: thread shows the full message")
    STUB.Script(bc.thread.add, "OnClick")
    check(comp:IsShown() and not comp.field1:IsShown(), "board: comment compose has no title")
    comp.field2:SetText("Count me in")
    STUB.Script(comp.field2, "OnEnterPressed")
    check(bc.thread.comments[1]:IsShown() and bc.thread.comments[1].text:GetText() == "Count me in"
        and bc.thread.count:GetText() == "1 comment", "board: comment shows in the thread")
    STUB.Script(bc.thread.comments[1], "OnClick") -- right-click menu on your own comment opens without errors
    STUB.Script(bc.pinBtn, "OnClick")
    check(Social:Posts()[1].pinned == true and bc.pinBtn.label:GetText() == "Unpin", "board: pin from the thread")
    local cm = Social:Comments(Social:Posts()[1].id)[1]
    Social:Remove("comments", cm)
    Home:Refresh()
    check(#Social:Comments(Social:Posts()[1].id) == 0 and bc.thread.count:GetText() == "0 comments", "board: comment deleted")
    STUB.Script(bc.back, "OnClick")
    check(Home.openPost == nil and bc.posts[1].pin:GetText() == "PINNED", "board: back to the list, pinned marked")
    STUB.Script(bc.posts[1], "OnClick")
    STUB.Script(bc.delete, "OnClick")
    check(#Social:Posts() == 1, "board: first Delete click only asks")
    STUB.Script(bc.delete, "OnClick")
    check(#Social:Posts() == 0 and Home.openPost == nil, "board: post deleted")
    -- a regular member sees no New post button
    ns.db.guild.officerRank = -1
    Home:Refresh()
    check(not Social:CanPost() and not bc.newPost:IsShown() and bc.empty:GetText():find("Officers can post", 1, true),
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

    -- feed, chat and loot rows
    check(Home.feedCard.rows[1].item == G.feed[1] and Home.feedCard.rows[1].right:GetText() ~= "", "home: activity rows with age")
    check(Home.chatCard.rows[1].text:GetText():find("spam 120", 1, true), "home: chat rows")
    STUB.Script(Home.chatCard.rows[1], "OnEnter")
    check(GameTooltip.lines[2] == "spam 120", "home: chat tooltip shows the full message")
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
    check(#ns.Loot:Entries() == logBefore, "home: raid loot log untouched outside raid nights")
    Home:Refresh()
    check(Home.lootCard.rows[1].item == seen[1] and Home.lootCard.rows[1].text:GetText():find("World Epic", 1, true)
        and Home.lootCard.meta:GetText() == "blue and up", "home: recent loot card")
    STUB.Script(Home.lootCard.rows[1], "OnEnter")
    check(GameTooltip.link == seen[1].link, "home: loot row shows the item tooltip")
    for i = 1, 120 do STUB.Fire("CHAT_MSG_LOOT", "Newbie receives loot: " .. STUB.Link(21000 + i, "Blue " .. i, "0070dd") .. ".") end
    check(#seen == Home.LOOT_MAX and seen[1].itemID == 21120, "home: recent loot capped, newest first")

    -- ages
    check(Home.Ago(ns.Now() - 30) == "now" and Home.Ago(ns.Now() - 300) == "5m" and Home.Ago(ns.Now() - 7200) == "2h"
        and Home.Ago(ns.Now() - 3 * 86400) == "3d", "home: ages")

    -- layout: header across the top, three columns under it
    local pl, pt = STUB.rect(Home.page)
    local hl, ht, hw, hh = STUB.rect(Home.header)
    local fl, ft, fw, fh = STUB.rect(Home.feedCard)
    local ol, ot, ow, oh = STUB.rect(Home.onlineCard)
    local bl, bt, bw, bh = STUB.rect(Home.boardCard)
    local gl, gt, gw, gh = STUB.rect(Home.groupCard)
    local ll, lt, lw, lh = STUB.rect(Home.lootCard)
    local chl, cht, chw, chh = STUB.rect(Home.chatCard)
    check(near(hl - pl, 12) and near(hl + hw, pl + 890) and near(pt - ht, 30) and near(hh, 80), "layout: header spans the window")
    check(near(ft, ht - hh - 8) and near(bt, ft) and near(gt, ft), "layout: columns start one gap under the header")
    check(near(fl - pl, 12) and near(bl, fl + fw + 8) and near(gl, bl + bw + 8) and near(gl + gw, pl + 890), "layout: three columns, even gaps")
    check(near(pt - (ot - oh), 596) and near(pt - (bt - bh), 596) and near(pt - (lt - lh), 596), "layout: every column ends at the margin")
    check(near(ot, ft - fh - 8) and near(lt, gt - gh - 8) and near(fh, oh) and near(gh, lh), "layout: stacked cards split evenly")
    check(near(chl, fl) and near(cht, ft) and near(chw, fw), "layout: chat shares the activity slot")
    STUB.Script(Home.feedCard.modeChat, "OnClick")
    check(Home.chatCard:IsShown() and not Home.feedCard:IsShown() and Home.chatCard.modeChat.selected, "layout: Chat toggle swaps the card")
    STUB.Script(Home.chatCard.modeFeed, "OnClick")
    check(Home.feedCard:IsShown() and not Home.chatCard:IsShown(), "layout: Activity toggle swaps back")
    local cl2 = STUB.rect(Home.chart)
    check(near(cl2 + 240, hl + hw - 10), "layout: level spread sits at the header's right edge")
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
    check(Editor.tabButtons.boards.label:GetText() == "Raid Plans", "tabs: Boards is now Raid Plans")
    SlashCmdList.POGRAID("plans")
    check(Editor.currentTab == "boards", "tabs: /pog plans opens Raid Plans")
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
    Games:NewGame("apprentice")
    local cell = Games.cellSize
    local pl, pt = STUB.rect(Games.page)
    local bl, bt, bw, bh = STUB.rect(Games.board)
    local sl, st, sw = STUB.rect(Games.bar)
    check(cell == 40 and near(bw, 9 * 40 + 4) and near((bl - pl) + bw / 2, 451), "games: apprentice board centred, big tiles")
    check(near(sl, bl) and near(sw, bw) and near(st - bt, 44 + 4 + 18 + 4), "games: status bar lines up above the board")
    local ml, mt, mw, mh = STUB.rect(Games.bar.message)
    check(Games.bar.message.__parent == Games.page and near(mt, st - 44 - 4) and near(mh, 18) and mt - mh >= bt + 4,
        "games: win/loss line has its own space between the bar and the board")
    local hl, ht, hw, hh = STUB.rect(Games.help)
    check(near(ht - hh, pt - 608 + 12) and near(hh, 14), "games: help line sits inside the bottom margin")
    check(bt - bh >= ht + 6, "games: board ends above the help line")
    Games:NewGame("expert")
    bl, bt, bw, bh = STUB.rect(Games.board)
    check(near(bw, 30 * Games.cellSize + 4) and bl - pl >= 12 and bl + bw <= pl + 890 and pt - (bt - bh) <= 596 - 14 - 6,
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
    STUB.Script(Games.scoresBtn, "OnClick")
    check(Games.showingScores and Games.scores:IsShown() and not Games.board:IsShown() and not Games.bar:IsShown()
        and Games.scoresBtn.label:GetText() == "Back to game", "leaderboard: button swaps the board for the scores")
    local col = Games.scores.cols.apprentice
    check(col.rows[1].name:GetText() == "Raider02" and col.rows[1].time:GetText() == "18.4s" and col.rows[1].rank:GetText() == "1.",
        "leaderboard: rows show rank and name")
    check(col.rows[2].mine:IsShown() and not col.rows[1].mine:IsShown(), "leaderboard: your row highlighted")
    check(Games.scores.cols.expert.rows[1].time:GetText() == "5:01" and Games.scores.cols.journeyman.empty:IsShown(),
        "leaderboard: each difficulty has its own column")
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
    check(not Games.showingScores and Games.board:IsShown(), "leaderboard: picking a difficulty goes back to the game")
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
    check(Roster.groupBoxes[1].title:GetText() == "GROUP 1" and Roster.benchBox.title:GetText() == "BENCH"
        and Roster.groupBoxes[1].title.__fontSize == 10, "polish: small capital section titles")
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
    check(Editor.closeBtn.bg == nil and Editor.closeBtn.label:GetText() == "X", "polish: close button matches the tabs")
    SlashCmdList.POGRAID("home")
    check(#Home.header.edges == 0, "polish: home banner has no outline or accent line")
    STUB.motd = ""
    Home:Refresh()
    check(Home.header.motd.__textColor[2] < 0.6, "polish: empty message of the day is dim")
    STUB.motd = "Raid tonight"
    Home:Refresh()
    check(Home.header.motd.__textColor[2] > 0.8, "polish: a real message of the day is green")
    check(Home.feedCard.modeFeed.bg == nil and Home.feedCard.modeFeed.label:GetText() == "ACTIVITY", "polish: Activity/Chat are small tabs")
    check(Home.boardCard.title:GetText() == "MESSAGE BOARD" and Home.chart.label:GetText() == "LEVEL SPREAD", "polish: home section titles")
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
    check(#played == 1 and ns.db.settings.sounds == false, "settings: sounds can be turned off")
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
    -- a member sees the list but can't change it
    local myP = ns.db.guild.players["Jake-Realm"]
    local realRank = myP.rankIndex
    myP.rankIndex = 3
    Settings:Refresh()
    check(not ranks[2].enabled and Settings.officers.note:GetText():find("Only officers", 1, true), "officers: read-only for members")
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
    check(printedContains("newer Pog Raid (99.0.0)") and Version.seen["Raider04-Realm"] == nil, "version: newer version noticed, junk ignored")
    STUB.printed = {}
    STUB.Fire("CHAT_MSG_ADDON", "PogRaid", "W99.1.0", "WHISPER", "Raider05-Realm")
    check(not printedContains("newer Pog Raid"), "version: the update note shows once")
    ns.Sync:OnPayload("S0000abcd:3:0.8.0", "Raider06-Realm")
    check(Version.seen["Raider06-Realm"] == "0.8.0", "version: picked up from the sync check-in for free")
    check(Version.Compare("0.10.0", "0.9.0") == 1 and Version.Compare("1.2.3", "1.2.3") == 0 and Version.Compare("x", "1.0.0") == nil,
        "version: compares numbers, not text")
    Settings:Refresh()
    local who = Settings.who
    local found = {}
    for _, row in ipairs(who.rows) do
        if row:IsShown() then found[row.name:GetText()] = row.version:GetText() end
    end
    check(found["Raider02"] == "0.9.0  (update)" and found["Raider05"] == "99.1.0", "version: who has it, old versions flagged")
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
    check(Games.MODES[1].key == "wowdle" and near(wl - gpl, 12) and sl > wl, "games: Wowdle is the first game tab")
    local savedMode = ns.db.games.mode
    ns.db.games.mode = nil
    Games:SetMode(nil)
    check(Games.mode == "wowdle", "games: opens on Wowdle when no game was picked")
    ns.db.games.mode = savedMode
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
    check(W.keys.Q.bg.__color[1] == 0.2, "wowdle: keyboard greys out letters that aren't in it")
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
    check(W.status:GetText():find("Today's word has 8 letters", 1, true), "wowdle: the line under the keyboard says how long the word is")
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
    check(right.empty:IsShown() and right.status:GetText():find("Open your Cooking window", 1, true) ~= nil,
        "crafting: hint, and a nudge to share the other profession")
    STUB.Script(left.rows[1], "OnClick")
    check(C.selected == "Blacksmithing" and right.rows[1]:IsShown() and right.rows[1].name:GetText() == "Raider03"
        and right.rows[1].right:GetText():find("300 / 300", 1, true) ~= nil, "crafting: picking a profession shows its members")
    -- a member's recipe book: click, scroll, filter, back
    local raider = right.rows[1]
    STUB.Script(raider, "OnClick", "RightButton")
    check(C.member == nil, "crafting: right-clicking a member doesn't open their recipes")
    STUB.Script(raider, "OnClick", "LeftButton")
    check(C.member == "Raider03-Realm" and right.back:IsShown() and right.count:GetText() == "3 recipes"
        and right.rows[1].name:GetText() == "Arcanite Reaper" and right.rows[2].name:GetText() == "Dense Sharpening Stone"
        and right.rows[3].name:GetText() == "Reaper Blade" and not right.rows[4]:IsShown(), "crafting: clicking a member lists all their recipes")
    check(right.title:GetText():find("RAIDER03", 1, true) ~= nil and C.searchBox.placeholder:GetText() == "Search Raider03's Blacksmithing recipes",
        "crafting: title and search box say whose recipes these are")
    C.searchBox:SetText("reaper")
    STUB.Script(C.searchBox, "OnTextChanged")
    check(C.member and right.count:GetText() == "2 recipes" and right.rows[1].name:GetText() == "Arcanite Reaper"
        and right.rows[2].name:GetText() == "Reaper Blade", "crafting: search filters the member's recipes")
    STUB.Script(right.back, "OnClick")
    check(C.member == nil and not right.back:IsShown() and right.rows[1].kind == "member" and C.searchBox:GetText() == "",
        "crafting: Back returns to the members")
    STUB.Script(left.rows[1], "OnClick") -- Blacksmithing off
    for _, row in ipairs(left.rows) do if row.item == "Cooking" then STUB.Script(row, "OnClick") end end
    STUB.Script(right.rows[1], "OnClick", "LeftButton")
    check(C.member == "Jake-Realm" and right.empty:IsShown() and right.empty:GetText():find("hasn't shared their Cooking recipes", 1, true) ~= nil,
        "crafting: a member who hasn't shared gets a clear note")
    STUB.Script(left.rows[1], "OnClick")
    check(C.member == nil and C.selected == "Blacksmithing", "crafting: picking a profession leaves the recipe book")
    slots = { 1, nil, nil, 3, 2 }
    info[3] = { "Fishing", 3, 75, 150, 0, 0, 356 }
    check(not C:StatusText():find("Fishing", 1, true), "crafting: no nudge to open a Fishing window")
    slots = { 1, nil, nil, nil, 2 }

    C.searchBox:SetText("arcanite")
    STUB.Script(C.searchBox, "OnTextChanged")
    check(right.rows[1].kind == "recipe" and right.rows[1].name:GetText() == "Arcanite Reaper" and right.rows[2].name:GetText() == "Arcanite Rod"
        and not right.rows[3]:IsShown(), "crafting: typing shows matching recipes")
    check(right.rows[1].right:GetText() == "Raider03, Jake", "crafting: recipe rows name the crafters, online first, no counts")
    check(left.rows[1].right:GetText() == "2", "crafting: professions list shows just the member count")
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
    ns.Editor:ShowTab("home")
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
    check(report:find("Pog Raid " .. ns.VERSION, 1, true) and report:find("This session:", 1, true) and report:find("[x2]", 1, true)
        and report:find("    PogRaid/Home.lua:42: in function", 1, true), "bug: report has version, counts and stack lines")
    Bug.session = {}
    check(Bug:Report():find("Earlier:", 1, true) and not Bug:Report():find("This session:", 1, true), "bug: older errors listed as earlier")
    for i = 1, 30 do Bug.Record("PogRaid/X.lua:" .. i .. ": e" .. i) end
    check(#list == Bug.KEEP, "bug: keeps the last 25 different errors")
    SlashCmdList.POGRAID("bug")
    check(PogRaidCopy and PogRaidCopy:IsShown() and PogRaidCopy.edit:GetText():find("X.lua:30", 1, true) ~= nil, "bug: /pog bug opens the copy box")
    PogRaidCopy:Hide()
    SlashCmdList.POGRAID("bug clear")
    check(#ns.db.errors == 0 and Bug:Report():find("No Pog Raid errors recorded.", 1, true) ~= nil, "bug: /pog bug clear empties it")
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

return results

Ext.Require("Shared.lua")

-- DOS2 DE keyboard/mouse inventory and context menu UI types.
local sources = {[9] = true, [40] = true, [116] = true, [119] = true}
local menus = {[10] = true, [11] = true}
local context, sequence, refreshing = nil, 0, false
local pendingCapture = {}

local function capture(ui)
    local id = ui:GetTypeId()
    if sources[id] or menus[id] then
        ui:CaptureExternalInterfaceCalls()
        if menus[id] then
            -- UIObjectCreated can fire before the Flash player exists.
            if ui:GetRoot() then
                ui:CaptureInvokes()
                pendingCapture[id] = nil
            else
                pendingCapture[id] = true
            end
        end
    end
end

local function selectedCharacter(ui, ownerDouble)
    if ownerDouble then
        local owner = Ext.Entity.GetCharacter(Ext.UI.DoubleToHandle(ownerDouble))
        if owner then return owner.NetID end
    end
    -- A container window can refer to an item, rather than a character.
    -- Let the server resolve the scroll's outermost inventory owner.
    if ui:GetTypeId() == 9 then return 0 end
    local handle = ui:GetPlayerHandle()
    local character = handle and Ext.Entity.GetCharacter(handle)
    if character then return character.NetID end
    local bar = Ext.UI.GetByType(40)
    if bar then
        handle = bar:GetPlayerHandle()
        character = handle and Ext.Entity.GetCharacter(handle)
        if character then return character.NetID end
    end
    -- The server can use the scroll's inventory owner if no UI player is set.
    return 0
end

local function addButton(array, id, label, disabled)
    local n = #array
    -- Native contextMenu.swf uses seven slots for each button.
    array[n] = id
    array[n + 1] = id
    array[n + 2] = true
    array[n + 3] = ""
    array[n + 4] = label
    array[n + 5] = disabled
    array[n + 6] = true
end

local function appendOptions(array, ctx)
    ctx.actions = {}
    if not ctx.reply then
        addButton(array, RR.ActionBase, "Checking dead teammates...", true)
    elseif ctx.reply.error then
        addButton(array, RR.ActionBase, RR.Label(ctx.reply.error), true)
    elseif #ctx.reply.targets == 0 then
        addButton(array, RR.ActionBase, "No dead teammates on this map", true)
    else
        for i, target in ipairs(ctx.reply.targets) do
            if i >= RR.ActionLimit - RR.ActionBase then break end
            local id = RR.ActionBase + i
            ctx.actions[id] = target.guid
            addButton(array, id, "Revive " .. RR.Label(target.name), false)
        end
    end
end

local function refresh()
    local ctx = context
    if not ctx or not ctx.menu or not ctx.original then return end
    local root = ctx.menu:GetRoot()
    if not root or not root.buttonArr then return end
    refreshing = true
    local ok, err = pcall(function()
        root.buttonArr.length = 0
        for i, value in ipairs(ctx.original) do root.buttonArr[i - 1] = value end
        appendOptions(root.buttonArr, ctx)
        root.updateButtons()
    end)
    refreshing = false
    if not ok then Ext.Utils.PrintError("[Remote Resurrection] Menu refresh: " .. tostring(err)) end
end

Ext.Events.UICall:Subscribe(function(e)
    -- v60 dispatches both phases through UICall. The after phase would replace
    -- the context saved while the game opened the menu in the before phase.
    if e.When ~= "Before" then return end
    local ui, name = e.UI, e.Function
    local uiType = ui:GetTypeId()
    if sources[uiType] and name == "openContextMenu" then
        context = nil
        -- Native inventoryClass supplies (character, item, x, y), while
        -- containerInventory supplies (item, x, y). These are Flash doubles.
        local argc = #e.Args
        if argc ~= 3 and argc ~= 4 then return end
        local itemIndex = argc == 4 and 2 or 1
        local handle = Ext.UI.DoubleToHandle(e.Args[itemIndex])
        local item = handle and Ext.Entity.GetItem(handle)
        if not RR.IsScroll(item) then return end
        for id in pairs(menus) do
            local menu = Ext.UI.GetByType(id)
            if menu then capture(menu) end
        end
        sequence = sequence + 1
        context = {request = sequence, actions = {}, started = Ext.Utils.MonotonicTime()}
        RR.Log("Scroll menu request " .. sequence .. " from UI " .. uiType)
        Ext.Net.PostMessageToServer(RR.RequestChannel, Ext.Json.Stringify({
            request = sequence, item = item.NetID,
            caster = selectedCharacter(ui, argc == 4 and e.Args[1] or nil)
        }))
    elseif menus[uiType] and name == "buttonPressed" and RR.IsAction(e.Args[1]) then
        -- Custom IDs must never reach the game's built-in item action handler.
        e:PreventAction()
        local ctx = context
        local target = ctx and ctx.actions[e.Args[1]]
        if target and ctx.reply and ctx.reply.token then
            context = nil -- one click, one request
            Ext.Net.PostMessageToServer(RR.CastChannel, Ext.Json.Stringify({
                token = ctx.reply.token, target = target
            }))
        end
        ui:Hide()
    elseif menus[uiType] and name == "menuClosed" then
        context = nil
    end
end)

Ext.Events.UIInvoke:Subscribe(function(e)
    if e.When ~= "Before" then return end
    if not menus[e.UI:GetTypeId()] then return end
    if e.Function == "close" then context = nil; return end
    if e.Function ~= "updateButtons" or refreshing or not context then return end
    local root = e.UI:GetRoot()
    if not root or not root.buttonArr then return end
    context.menu = e.UI
    context.original = {}
    -- Strip our previous entries if the game refreshes this same menu.
    for i = 0, #root.buttonArr - 1, 7 do
        if not RR.IsAction(root.buttonArr[i]) then
            for j = 0, 6 do
                context.original[#context.original + 1] = root.buttonArr[i + j]
            end
        end
    end
    root.buttonArr.length = 0
    for i, value in ipairs(context.original) do root.buttonArr[i - 1] = value end
    appendOptions(root.buttonArr, context)
end)

Ext.RegisterNetListener(RR.MenuChannel, function(_, payload)
    local reply = RR.Decode(payload)
    if reply and context and reply.request == context.request then
        reply.targets = reply.targets or {}
        context.reply = reply
        RR.Log("Menu reply: " .. (reply.error or (#reply.targets .. " eligible teammate(s)")))
        refresh()
    end
end)

Ext.Events.UIObjectCreated:Subscribe(function(e) capture(e.UI) end)
Ext.Events.Tick:Subscribe(function()
    for id in pairs(pendingCapture) do
        local ui = Ext.UI.GetByType(id)
        if ui then capture(ui) end
    end
    if context and not context.reply and Ext.Utils.MonotonicTime() - context.started > 5000 then
        context.reply = {error = "No reply from host; check the host's mod"}
        RR.Log("Scroll menu request timed out")
        refresh()
    end
end)
Ext.Events.SessionLoaded:Subscribe(function()
    context = nil
    for id in pairs(sources) do local ui = Ext.UI.GetByType(id); if ui then capture(ui) end end
    for id in pairs(menus) do local ui = Ext.UI.GetByType(id); if ui then capture(ui) end end
end)
RR.Log("Client loaded, build 1.0.0.4")

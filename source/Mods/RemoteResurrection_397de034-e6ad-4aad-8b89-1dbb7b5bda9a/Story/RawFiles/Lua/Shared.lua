-- Remote Resurrection 1.0.0.4 - original source, MIT licensed.
RR = {}
RR.RequestChannel = "RR_397de034_MenuRequest"
RR.MenuChannel = "RR_397de034_MenuReply"
RR.CastChannel = "RR_397de034_Cast"
RR.ActionBase = 739100
RR.ActionLimit = 739500
RR.APCost = 3
RR.HealthPercent = 20.0

function RR.Log(message)
    Ext.Utils.Print("[Remote Resurrection] " .. message)
end

function RR.Decode(payload)
    if type(payload) ~= "string" or #payload > 8192 then return nil end
    local ok, result = pcall(Ext.Json.Parse, payload)
    if ok and type(result) == "table" then return result end
end

function RR.IsScroll(item)
    if not item then return false end
    -- Internal identifiers, never localized display names. Includes the stock
    -- Resurrection Scroll and modded variants retaining its naming convention.
    local names = {item.StatsId or "", item.RootTemplate and item.RootTemplate.Name or ""}
    if item.StatsFromName then names[#names + 1] = item.StatsFromName.Name or "" end
    for _, name in ipairs(names) do
        name = string.lower(name)
        if name:find("scroll", 1, true) and name:find("resurrect", 1, true) then
            return true
        end
    end
    return false
end

function RR.Label(name)
    name = tostring(name or "Teammate"):gsub("[%c]", " ")
    -- The native menu renders HTML. A player name must remain plain text.
    return name:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")
end

function RR.IsAction(id)
    return type(id) == "number" and id >= RR.ActionBase and id < RR.ActionLimit
end

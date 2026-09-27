Ext.Require("Shared.lua")

local offers, jobs, locks, serial = {}, {}, {}, 0
PersistentVars = {jobs = jobs, locks = locks, serial = serial}
local function nextSerial()
    serial = serial + 1
    PersistentVars.serial = serial
    return serial
end
local function now() return Ext.Utils.MonotonicTime() end
local function notify(character, message)
    Osi.CharacterStatusText(character, message)
end

local function ownedBy(character, user)
    -- Extender messages use a connection ID (e.g. 65536); controlled characters
    -- use a player ID on that connection (e.g. 65537). UserId::GetPeerId in
    -- Norbyte's API extracts the upper 16 bits. Exclude unassigned IDs.
    local function peer(id)
        if type(id) ~= "number" or id < 0 or id >= 0xFFFF0000 or id % 1 ~= 0 then return nil end
        return id // 65536
    end
    local sender = peer(user)
    return character and sender ~= nil
        and (peer(character.UserID) == sender or peer(character.ReservedUserID) == sender)
end

local function canAct(caster)
    if not caster or Osi.CharacterIsPlayer(caster.MyGuid) ~= 1 then
        return "Select a player character"
    end
    if caster.Dead or caster.OffStage or caster.InDialog or caster.IsTrading
        or (caster.Stats.IsIncapacitatedRefCount or 0) > 0 then
        return "This character cannot use a scroll right now"
    end
    for _, status in ipairs({"DYING", "CHARMED", "MADNESS"}) do
        if Osi.HasActiveStatus(caster.MyGuid, status) == 1 then
            return "This character cannot use a scroll right now"
        end
    end
    if Osi.CharacterIsInCombat(caster.MyGuid) == 1 then
        local combat = Ext.Entity.GetCombat(Osi.CombatGetIDForCharacter(caster.MyGuid))
        local order = combat and combat:GetCurrentTurnOrder()
        if not order or not order[1] or not order[1].Character
            or order[1].Character.MyGuid ~= caster.MyGuid then
            return "Wait for this character's turn"
        end
        if caster.Stats.CurrentAP < RR.APCost then return "Requires 3 action points" end
    end
end

local function validTarget(caster, target)
    return target and target.MyGuid ~= caster.MyGuid
        and Osi.CharacterIsPlayer(target.MyGuid) == 1
        and Osi.CharacterIsInPartyWith(caster.MyGuid, target.MyGuid) == 1
        and Osi.CharacterIsDead(target.MyGuid) == 1
        and not target.OffStage and not target.Summon
        and Osi.GetRegion(target.MyGuid) == Osi.GetRegion(caster.MyGuid)
        and Osi.IsTagged(target.MyGuid, "BLOCKED_RESURRECTION") ~= 1
        and Osi.IsTagged(target.MyGuid, "BLOCK_RESURRECTION") ~= 1
end

local function displayName(character)
    if character.CustomDisplayName and character.CustomDisplayName ~= "" then
        return character.CustomDisplayName
    end
    local handle, fallback = Osi.CharacterGetDisplayName(character.MyGuid)
    return Ext.L10N.GetTranslatedString(handle, fallback or character.DisplayName or "Teammate")
end

local function scrollInfo(caster, item)
    if not RR.IsScroll(item) or item.Amount < 1 or item.Destroyed then return nil end
    -- Only a scroll already carried by the caster is eligible. Bags are allowed.
    if Osi.ItemIsInCharacterInventory(item.MyGuid, caster.MyGuid) ~= 1 then return nil end
    return Osi.GetTemplate(item.MyGuid), Osi.GetInventoryOwner(item.MyGuid)
end

Ext.RegisterNetListener(RR.RequestChannel, function(_, payload, user)
    local request = RR.Decode(payload)
    if not request or type(request.item) ~= "number" or type(request.request) ~= "number" then return end
    local item = Ext.Entity.GetItem(request.item)
    local caster
    if type(request.caster) == "number" and request.caster ~= 0 then
        caster = Ext.Entity.GetCharacter(request.caster)
    elseif item then
        local owner = Osi.GetInventoryOwner(item.MyGuid)
        for _ = 1, 8 do
            caster = owner and Ext.Entity.GetCharacter(owner)
            if caster then break end
            local container = owner and Ext.Entity.GetItem(owner)
            if not container then break end
            owner = Osi.GetInventoryOwner(container.MyGuid)
        end
    end
    if not ownedBy(caster, user) then
        RR.Log("Menu request rejected: sender=" .. tostring(user)
            .. ", character user=" .. tostring(caster and caster.UserID)
            .. ", reserved user=" .. tostring(caster and caster.ReservedUserID))
        Ext.Net.PostMessageToUser(user, RR.MenuChannel, Ext.Json.Stringify({
            request = request.request, targets = {}, error = "Select a character you control"
        }))
        return
    end
    offers[user] = nil
    local reply = {request = request.request, targets = {}}
    reply.error = canAct(caster)
    if not reply.error and not scrollInfo(caster, item) then
        reply.error = "Put the scroll in this character's inventory"
    end
    if not reply.error then
        local allowed = {}
        for _, row in pairs(Osi.DB_IsPlayer:Get(nil)) do
            local target = Ext.Entity.GetCharacter(row[1])
            if validTarget(caster, target) and not allowed[target.MyGuid] then
                allowed[target.MyGuid] = true
                reply.targets[#reply.targets + 1] = {guid = target.MyGuid, name = displayName(target)}
            end
        end
        table.sort(reply.targets, function(a, b)
            if a.name == b.name then return a.guid < b.guid end
            return a.name < b.name
        end)
        reply.token = tostring(user) .. ":" .. nextSerial()
        offers[user] = {token = reply.token, caster = caster.MyGuid, item = item.MyGuid,
            allowed = allowed, expires = now() + 60000}
    end
    Ext.Net.PostMessageToUser(user, RR.MenuChannel, Ext.Json.Stringify(reply))
    RR.Log("Menu answered: " .. (reply.error or (#reply.targets .. " eligible teammate(s)")))
end)
RR.Log("Server loaded, build 1.0.0.4")

local function release(job)
    jobs[job.id] = nil
    locks[job.caster], locks[job.target], locks[job.item] = nil, nil, nil
    Osi.TimerCancel(job.id)
end

local function complete(job)
    if not jobs[job.id] then return end
    release(job)
    Osi.CharacterSetHitpointsPercentage(job.target, RR.HealthPercent)
    notify(job.caster, "Teammate resurrected beside you")
end

local function fail(job, reason)
    if not jobs[job.id] then return end
    -- If resurrection completed but its event was suppressed by another mod,
    -- settle it as a success, without duplicating a scroll or reviving twice.
    if Osi.CharacterIsDead(job.target) == 0 then complete(job); return end
    release(job)
    if job.paid then
        Osi.ItemTemplateAddTo(job.template, job.caster, 1, 0)
        if job.apPaid > 0 then Osi.CharacterAddActionPoints(job.caster, job.apPaid) end
    end
    Osi.TeleportToPosition(job.target, job.origin[1], job.origin[2], job.origin[3], "", 0, 1)
    notify(job.caster, reason .. (job.paid and ". Scroll refunded." or "."))
end

Ext.RegisterNetListener(RR.CastChannel, function(_, payload, user)
    local request = RR.Decode(payload)
    local offer = offers[user]
    if not request or not offer or request.token ~= offer.token then return end
    offers[user] = nil -- single use, even if revalidation fails
    local caster = Ext.Entity.GetCharacter(offer.caster)
    local target = type(request.target) == "string" and Ext.Entity.GetCharacter(request.target)
    local item = Ext.Entity.GetItem(offer.item)
    if not ownedBy(caster, user) then return end
    local error = canAct(caster)
    if error then notify(caster.MyGuid, error); return end
    if now() > offer.expires then notify(caster.MyGuid, "Reopen the scroll menu"); return end
    if not target or not offer.allowed[target.MyGuid] or not validTarget(caster, target) then
        notify(caster.MyGuid, "That teammate can no longer be resurrected"); return
    end
    local template, owner = scrollInfo(caster, item)
    if not template or not owner then notify(caster.MyGuid, "Resurrection scroll unavailable"); return end
    if locks[caster.MyGuid] or locks[target.MyGuid] or locks[item.MyGuid] then
        notify(caster.MyGuid, "A resurrection is already in progress"); return
    end
    local x, y, z = Osi.GetPosition(caster.MyGuid)
    local px, py, pz = Osi.FindValidPosition(x + 1.5, y, z, 3.0, target.MyGuid)
    if not px or (px-x)^2 + (pz-z)^2 > 25 or math.abs(py-y) > 3 then
        notify(caster.MyGuid, "No room beside you. Move and try again"); return
    end
    local ox, oy, oz = Osi.GetPosition(target.MyGuid)
    local job = {id = "RR_397de034_" .. nextSerial(), caster = caster.MyGuid, target = target.MyGuid,
        item = item.MyGuid, template = template, origin = {ox, oy, oz},
        destination = {px, py, pz}, paid = false, apPaid = 0, moved = false}
    jobs[job.id] = job
    locks[job.caster], locks[job.target], locks[job.item] = job.id, job.id, job.id
    local ok, err = pcall(function()
        Osi.ItemTemplateRemoveFrom(template, owner, 1)
        job.paid = true
        if Osi.CharacterIsInCombat(caster.MyGuid) == 1 then
            Osi.CharacterAddActionPoints(caster.MyGuid, -RR.APCost)
            job.apPaid = RR.APCost
        end
        Osi.TimerLaunch(job.id, 5000)
        -- Teleport the corpse first. Only the teleport completion event starts
        -- resurrection, so no living teammate briefly appears at the old body.
        Osi.TeleportToPosition(target.MyGuid, px, py, pz, job.id, 0, 1)
    end)
    if not ok then
        Ext.Utils.PrintError("[Remote Resurrection] " .. tostring(err))
        fail(job, "Resurrection failed")
    end
end)

Ext.Osiris.RegisterListener("StoryEvent", 2, "after", function(object, event)
    local job = jobs[event]
    local target = job and Ext.Entity.GetCharacter(object)
    if not target or target.MyGuid ~= job.target then return end
    local x, y, z = Osi.GetPosition(job.target)
    local dest = job.destination
    if (x-dest[1])^2 + (y-dest[2])^2 + (z-dest[3])^2 > 9 then
        fail(job, "Could not move the teammate"); return
    end
    job.moved = true
    local caster = Ext.Entity.GetCharacter(job.caster)
    if not caster or not validTarget(caster, target) then fail(job, "Target changed"); return end
    if job.resurrecting then return end
    job.resurrecting = true
    Osi.CharacterResurrect(job.target)
end)

Ext.Osiris.RegisterListener("CharacterResurrected", 1, "after", function(character)
    local target = Ext.Entity.GetCharacter(character)
    local job = target and jobs[locks[target.MyGuid]]
    if job and job.target == target.MyGuid then complete(job) end
end)

Ext.Osiris.RegisterListener("TimerFinished", 1, "after", function(timer)
    if jobs[timer] then fail(jobs[timer], "Resurrection timed out") end
end)

Ext.Events.SessionLoaded:Subscribe(function()
    offers = {}
    PersistentVars = PersistentVars or {}
    jobs, locks, serial = PersistentVars.jobs or {}, PersistentVars.locks or {}, PersistentVars.serial or 0
    PersistentVars.jobs, PersistentVars.locks = jobs, locks
    -- Recover a save made in the brief interval between paying and teleporting.
    local interrupted = {}
    for _, job in pairs(jobs) do interrupted[#interrupted + 1] = job end
    for _, job in ipairs(interrupted) do fail(job, "Interrupted resurrection") end
end)

"""Behavioral tests using Lua 5.3 and simulated DOS2 engine APIs.

These exercise the shipped scripts, not a reimplementation. They cannot establish
compatibility with the real game's Flash UI, networking or Osiris scheduler.
Run with Python and the `lupa` package installed.
"""
from pathlib import Path
import json
import re
import sys
import unittest

local_deps = Path(__file__).resolve().parents[2] / "tools" / "python"
if local_deps.exists():
    sys.path.insert(0, str(local_deps))
from lupa.lua53 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
LUA = next((ROOT / "source" / "Mods").iterdir()) / "Story" / "RawFiles" / "Lua"


def native(value):
    if hasattr(value, "items"):
        items = dict(value.items())
        if items and set(items) == set(range(1, len(items) + 1)):
            return [native(items[i]) for i in range(1, len(items) + 1)]
        return {k: native(v) for k, v in items.items()}
    return value


MOCK = r'''
net, events, osiEvents, sent, trace = {}, {}, {}, {}, {}
clock, failPosition, suppressResurrection = 1000, false, false
local function event(name)
    local e = {listeners={}}
    function e:Subscribe(fn) self.listeners[#self.listeners+1]=fn end
    function e:Emit(...) for _,fn in ipairs(self.listeners) do fn(...) end end
    events[name]=e
    return e
end
local function char(id, guid, dead, name)
    return {NetID=id, MyGuid=guid, Dead=dead, DisplayName=name,
        UserID=65537, ReservedUserID=65537, IsPlayer=true, Party="party", Region="FortJoy",
        Stats={CurrentAP=4,IsIncapacitatedRefCount=0}, Position={0,0,0}, Tags={}, Statuses={}}
end
caster=char(1,"caster",false,"Caster")
dead=char(2,"dead",true,"Sebille")
dead.Position={2000,0,-1800}
dead.UserID,dead.ReservedUserID=131073,131073
alive=char(3,"alive",false,"Fane")
chars={caster=caster,dead=dead,alive=alive}
scroll={MyGuid="scroll",NetID=11,StatsId="LOOT_Scroll_Resurrect",Amount=3,
    RootTemplate={Name="LOOT_Scroll_Resurrect",Id="scroll-template"},Owner="caster"}
items={scroll=scroll}
local function character(id)
    if type(id)=="string" then return chars[id] end
    for _,c in pairs(chars) do if c.NetID==id then return c end end
end
local function item(id)
    if type(id)=="string" then return items[id] end
    for _,v in pairs(items) do if v.NetID==id then return v end end
end
Ext={
    Events={UICall=event("UICall"),UIInvoke=event("UIInvoke"),
        UIObjectCreated=event("UIObjectCreated"),SessionLoaded=event("SessionLoaded"),Tick=event("Tick")},
    Entity={GetCharacter=character,GetItem=item},
    Json={Parse=pyparse,Stringify=pystringify},
    Utils={MonotonicTime=function() return clock end,
        Print=function(message) trace[#trace+1]={"log",message} end,
        PrintError=function(message) trace[#trace+1]={"error",message} end},
    L10N={GetTranslatedString=function(h,f) return f end},
    Net={}, Osiris={}, UI={}
}
setmetatable(Ext.Events,{__index=function(_,k) error("Unknown event: "..k) end})
function Ext.RegisterNetListener(channel,fn) net[channel]=fn end
function Ext.Net.PostMessageToUser(user,channel,payload)
    sent[#sent+1]={user=user,channel=channel,payload=payload}
end
function Ext.Net.PostMessageToServer(channel,payload)
    sent[#sent+1]={channel=channel,payload=payload}
end
function Ext.Osiris.RegisterListener(name,arity,when,fn) osiEvents[name]=fn end
function Ext.Entity.GetCombat(id)
    if id==1 then return {GetCurrentTurnOrder=function() return {{Character=turn or caster}} end} end
end
function Ext.Require(path) pyrequire(path) end
Osi={}
function Osi.CharacterIsPlayer(g) return chars[g] and chars[g].IsPlayer and 1 or 0 end
function Osi.CharacterIsInPartyWith(a,b) return chars[a].Party==chars[b].Party and 1 or 0 end
function Osi.CharacterIsDead(g) return chars[g].Dead and 1 or 0 end
function Osi.GetRegion(g) return chars[g].Region end
function Osi.IsTagged(g,t) return chars[g].Tags[t] and 1 or 0 end
function Osi.HasActiveStatus(g,t) return chars[g].Statuses[t] and 1 or 0 end
function Osi.CharacterIsInCombat(g) return chars[g].InCombat and 1 or 0 end
function Osi.CombatGetIDForCharacter(g) return 1 end
function Osi.CharacterGetDisplayName(g) return "name-handle",chars[g].DisplayName end
function Osi.ItemIsInCharacterInventory(g,c) return items[g].Owner==c and 1 or 0 end
function Osi.GetTemplate(g) return items[g].RootTemplate.Id end
function Osi.GetInventoryOwner(g) return items[g].Owner end
Osi.DB_IsPlayer={Get=function() local t={} for g in pairs(chars) do t[#t+1]={g} end return t end}
function Osi.GetPosition(g) return table.unpack(chars[g].Position) end
function Osi.FindValidPosition(x,y,z,r,g) if not failPosition then return x,y,z end end
function Osi.CharacterStatusText(g,t) trace[#trace+1]={"message",g,t} end
function Osi.ItemTemplateRemoveFrom(t,o,n)
    assert(t=="scroll-template" and o==scroll.Owner and n==1)
    scroll.Amount=scroll.Amount-n
    trace[#trace+1]={"charge",n}
end
function Osi.ItemTemplateAddTo(t,o,n,show)
    assert(t=="scroll-template" and o=="caster" and n==1)
    scroll.Amount=scroll.Amount+n
    trace[#trace+1]={"refund",n}
end
function Osi.CharacterAddActionPoints(g,n) chars[g].Stats.CurrentAP=chars[g].Stats.CurrentAP+n end
function Osi.TimerLaunch(id,t) timer=id end
function Osi.TimerCancel(id) end
function Osi.TeleportToPosition(g,x,y,z,e,linked,exclude)
    assert(linked==0 and exclude==1)
    chars[g].Position={x,y,z}
    trace[#trace+1]={"teleport",g,x,y,z}
    lastStory={g,e}
end
function Osi.CharacterResurrect(g)
    if suppressResurrection then return end
    chars[g].Dead=false
    trace[#trace+1]={"resurrect",g}
    osiEvents.CharacterResurrected(g)
end
function Osi.CharacterSetHitpointsPercentage(g,p) chars[g].Health=p end
setmetatable(Osi,{__index=function(_,k) error("Unknown Osiris API: "..k) end})

-- An Iggy-style zero-based Flash array, including a writable length.
function flashArray(values)
    local data,n={},0
    for i,v in ipairs(values or {}) do data[i-1]=v;n=n+1 end
    return setmetatable({}, {
        __len=function() return n end,
        __index=function(_,k) if k=="length" then return n end;return data[k] end,
        __newindex=function(_,k,v)
            if k=="length" then for i=v,n-1 do data[i]=nil end;n=v
            else data[k]=v;if k>=n then n=k+1 end end
        end
    })
end
uis={}
function ui(id, ready)
    local u={root={buttonArr=flashArray({1,1,true,"","Use",false,true})},id=id,ready=ready~=false}
    function u:GetTypeId() return self.id end
    function u:GetPlayerHandle() return 1 end
    function u:GetRoot() if self.ready then return self.root end end
    function u:CaptureExternalInterfaceCalls() self.captured=true end
    function u:CaptureInvokes() assert(self.ready,"Flash player not ready");self.invokes=true end
    -- Native contextMenu.swf consumes buttonArr and replaces it with an empty
    -- array after rendering. A network reply must rebuild the saved buttons.
    function u.root.updateButtons()
        u.rendered=flashArray()
        for i=0,#u.root.buttonArr-1 do u.rendered[i]=u.root.buttonArr[i] end
        u.root.buttonArr=flashArray()
    end
    function u:Invoke(f)
        if f=="updateButtons" then self.root.buttonArr=flashArray({1,1,true,"","Use",false,true}) end
        if self.invokes then events.UIInvoke:Emit({UI=self,Function=f,Args={},When="Before"}) end
        if f=="updateButtons" then self.root.updateButtons() end
        if self.invokes then events.UIInvoke:Emit({UI=self,Function=f,Args={},When="After"}) end
    end
    function u:Hide() self.hidden=true end
    uis[id]=u;return u
end
function Ext.UI.DoubleToHandle(n) return n end
function Ext.UI.GetByType(id) return uis[id] end
function call(u,f,args,nativeAction)
    local e={UI=u,Function=f,Args=args,When="Before"}
    function e:PreventAction() self.prevented=true end
    if u.captured then events.UICall:Emit(e) end
    if not e.prevented then
        if nativeAction then nativeAction() end
        e.When="After"
        if u.captured then events.UICall:Emit(e) end
    end
    return e
end
function requestMenu()
    net[RR.RequestChannel](RR.RequestChannel,pystringify({request=1,item=11,caster=1}),65536)
    return pyparse(sent[#sent].payload)
end
function cast(reply,target)
    net[RR.CastChannel](RR.CastChannel,pystringify({token=reply.token,target=target or "dead"}),65536)
end
'''


def runtime(script):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().pyparse = lambda s: lua.table_from(json.loads(s), recursive=True)
    lua.globals().pystringify = lambda x: json.dumps(native(x))
    lua.globals().pyrequire = lambda path: lua.execute((LUA / path).read_text())
    lua.execute(MOCK)
    lua.execute((LUA / script).read_text())
    return lua


class ServerTests(unittest.TestCase):
    def setUp(self):
        self.lua = runtime("BootstrapServer.lua")

    def run_lua(self, text):
        self.lua.execute(text)

    def test_remote_menu_and_revival(self):
        self.run_lua('''
            local r=requestMenu();assert(#r.targets==1 and r.targets[1].name=="Sebille")
            cast(r);assert(scroll.Amount==2 and dead.Dead)
            osiEvents.StoryEvent(table.unpack(lastStory))
            assert(not dead.Dead and dead.Health==20)
            assert(dead.Position[1]==1.5 and alive.Position[1]==0)
            assert(caster.Stats.CurrentAP==4)
            cast(r);assert(scroll.Amount==2)
        ''')

    def test_ineligible_targets(self):
        for condition in ['dead.Dead=false', 'dead.IsPlayer=false', 'dead.Summon=true',
                          'dead.OffStage=true', 'dead.Region="Arx"', 'dead.Party="enemy"',
                          'dead.Tags.BLOCKED_RESURRECTION=true', 'dead.Tags.BLOCK_RESURRECTION=true']:
            lua = runtime("BootstrapServer.lua")
            lua.execute(condition + ';local r=requestMenu();assert(#r.targets==0)')

    def test_no_scroll_lost_on_invalid_cast(self):
        for condition in ['dead.Dead=false', 'dead.Party="enemy"', 'failPosition=true',
                          'caster.Dead=true', 'clock=100000', 'dead.Tags.BLOCKED_RESURRECTION=true',
                          'scroll.Owner="alive"', 'caster.UserID=3;caster.ReservedUserID=3']:
            lua = runtime("BootstrapServer.lua")
            lua.execute('local r=requestMenu();' + condition + ';cast(r);assert(scroll.Amount==3)')

    def test_empty_or_wrong_item(self):
        self.run_lua('''
            scroll.Amount=0;local r=requestMenu();assert(r.error)
            scroll.Amount=3;scroll.StatsId="Scroll_Fireball";scroll.RootTemplate.Name="Scroll_Fireball"
            r=requestMenu();assert(r.error and scroll.Amount==3)
        ''')

    def test_combat_turn_and_cost(self):
        self.run_lua('''
            caster.InCombat=true;turn=alive;assert(requestMenu().error)
            turn=caster;caster.Stats.CurrentAP=2;assert(requestMenu().error)
            caster.Stats.CurrentAP=4;local r=requestMenu();cast(r)
            assert(caster.Stats.CurrentAP==1 and scroll.Amount==2)
            osiEvents.StoryEvent(table.unpack(lastStory));assert(not dead.Dead)
        ''')

    def test_wrong_user_and_tampered_target(self):
        self.run_lua('''
            net[RR.RequestChannel](RR.RequestChannel,pystringify({request=1,item=11,caster=1}),999)
            assert(#sent==1 and pyparse(sent[1].payload).error and scroll.Amount==3)
            local r=requestMenu();cast(r,"alive");assert(scroll.Amount==3)
            net[RR.CastChannel](RR.CastChannel,pystringify({token=r.token,target="dead"}),999)
            assert(scroll.Amount==3)
        ''')

    def test_timeout_refunds_and_restores_body(self):
        self.run_lua('''
            caster.InCombat=true;local r=requestMenu();cast(r)
            assert(scroll.Amount==2 and caster.Stats.CurrentAP==1)
            osiEvents.TimerFinished(timer)
            assert(scroll.Amount==3 and caster.Stats.CurrentAP==4 and dead.Dead)
            assert(dead.Position[1]==2000)
            osiEvents.TimerFinished(timer);assert(scroll.Amount==3)
        ''')

    def test_resurrection_failure_and_duplicate_teleport_callback(self):
        self.run_lua('''
            suppressResurrection=true;local r=requestMenu();cast(r)
            local event=lastStory;osiEvents.StoryEvent(table.unpack(event))
            osiEvents.StoryEvent(table.unpack(event))
            osiEvents.TimerFinished(timer);assert(scroll.Amount==3 and dead.Dead)
        ''')

    def test_pending_job_lock_and_session_recovery(self):
        self.run_lua('''
            local r=requestMenu();cast(r)
            local second=requestMenu();cast(second);assert(scroll.Amount==2)
            events.SessionLoaded:Emit()
            assert(scroll.Amount==3 and dead.Dead and dead.Position[1]==2000)
            assert(next(PersistentVars.jobs)==nil)
        ''')

    def test_restore_saved_transaction_into_new_lua_state(self):
        self.run_lua('local r=requestMenu();cast(r)')
        saved = native(self.lua.globals().PersistentVars)
        other = runtime("BootstrapServer.lua")
        other.globals().PersistentVars = other.table_from(saved, recursive=True)
        other.execute('scroll.Amount=2;dead.Position={1.5,0,0};events.SessionLoaded:Emit();assert(scroll.Amount==3)')

    def test_bad_json(self):
        self.run_lua('net[RR.RequestChannel](RR.RequestChannel,"{broken",65537);assert(#sent==0)')

    def test_network_peer_owns_player_id_but_other_peers_do_not(self):
        self.run_lua('''
            local r=requestMenu();assert(not r.error and #r.targets==1)
            net[RR.RequestChannel](RR.RequestChannel,pystringify({request=2,item=11,caster=1}),131072)
            assert(pyparse(sent[#sent].payload).error and scroll.Amount==3)
            net[RR.CastChannel](RR.CastChannel,pystringify({token=r.token,target="dead"}),131072)
            assert(scroll.Amount==3)
            cast(r);assert(scroll.Amount==2)
        ''')

    def test_unassigned_ownership_ids_cannot_authorize_a_cast(self):
        self.run_lua('''
            caster.UserID=-65536;caster.ReservedUserID=0xFFFF0000
            assert(requestMenu().error and scroll.Amount==3)
        ''')


class ClientTests(unittest.TestCase):
    def setUp(self):
        self.lua = runtime("BootstrapClient.lua")
        self.lua.execute('inventory=ui(116);menu=ui(10);events.SessionLoaded:Emit()')

    def test_async_named_dropdown_and_single_use(self):
        self.lua.execute('''
            call(inventory,"openContextMenu",{11,10,20});menu:Invoke("updateButtons")
            assert(menu.rendered[4]=="Use")
            assert(menu.rendered[11]=="Checking dead teammates...")
            assert(#menu.root.buttonArr==0)
            net[RR.MenuChannel](RR.MenuChannel,pystringify({request=1,token="one",
                targets={{guid="dead",name="Sebille"},{guid="dead2",name="Lohse <Mage>"}}}))
            assert(#menu.rendered==21)
            assert(menu.rendered[4]=="Use")
            assert(menu.rendered[11]=="Revive Sebille")
            assert(menu.rendered[18]=="Revive Lohse &lt;Mage&gt;")
            menu:Invoke("updateButtons");assert(#menu.rendered==21)
            local e=call(menu,"buttonPressed",{739101,739101,0});assert(e.prevented)
            assert(pyparse(sent[#sent].payload).target=="dead")
            local n=#sent;call(menu,"buttonPressed",{739101,739101,0});assert(#sent==n)
        ''')

    def test_late_response_does_not_reopen_closed_menu(self):
        self.lua.execute('''
            call(inventory,"openContextMenu",{11,10,20});menu:Invoke("updateButtons")
            call(menu,"menuClosed",{})
            net[RR.MenuChannel](RR.MenuChannel,pystringify({request=1,targets={{guid="dead",name="Sebille"}}}))
            assert(menu.rendered[11]=="Checking dead teammates...")
        ''')

    def test_vanilla_and_other_items_unaffected(self):
        self.lua.execute('''
            scroll.StatsId="Gold";scroll.RootTemplate.Name="Gold"
            call(inventory,"openContextMenu",{11,10,20});menu:Invoke("updateButtons")
            assert(#sent==0 and #menu.rendered==7)
            assert(not call(menu,"buttonPressed",{1,1,0}).prevented)
        ''')

    def test_no_dead_players_and_stale_responses(self):
        self.lua.execute('''
            call(inventory,"openContextMenu",{11,10,20});menu:Invoke("updateButtons")
            net[RR.MenuChannel](RR.MenuChannel,pystringify({request=999,targets={}}))
            assert(menu.rendered[11]=="Checking dead teammates...")
            net[RR.MenuChannel](RR.MenuChannel,pystringify({request=1,targets={}}))
            assert(menu.rendered[11]=="No dead teammates on this map")
            assert(menu.rendered[12]==true)
        ''')

    def test_native_party_inventory_owner_then_item_arguments(self):
        self.lua.execute('''
            call(inventory,"openContextMenu",{1,11,10,20});menu:Invoke("updateButtons")
            assert(#sent==1)
            local request=pyparse(sent[1].payload)
            assert(request.item==11 and request.caster==1)
            assert(menu.rendered[4]=="Use" and menu.rendered[11]=="Checking dead teammates...")
        ''')

    def test_container_inventory_uses_item_first_and_server_owner(self):
        self.lua.execute('''
            local bag=ui(9);events.UIObjectCreated:Emit({UI=bag})
            call(bag,"openContextMenu",{11,10,20});menu:Invoke("updateButtons")
            local request=pyparse(sent[1].payload)
            assert(request.item==11 and request.caster==0)
            assert(menu.rendered[11]=="Checking dead teammates...")
        ''')

    def test_flash_capture_retries_after_ui_object_creation(self):
        self.lua.execute('''
            menu=ui(10,false);events.UIObjectCreated:Emit({UI=menu})
            assert(menu.captured and not menu.invokes)
            menu.ready=true;events.Tick:Emit();assert(menu.invokes)
            call(inventory,"openContextMenu",{1,11,10,20});menu:Invoke("updateButtons")
            assert(menu.rendered[11]=="Checking dead teammates...")
        ''')

    def test_host_timeout_is_visible_and_does_not_spend_a_scroll(self):
        self.lua.execute('''
            call(inventory,"openContextMenu",{1,11,10,20});menu:Invoke("updateButtons")
            clock=7000;events.Tick:Emit()
            assert(menu.rendered[11]:find("No reply from host",1,true))
            assert(menu.rendered[12] and scroll.Amount==3 and #sent==1)
        ''')

    def test_after_callback_does_not_replace_open_menu_context(self):
        self.lua.execute('''
            call(inventory,"openContextMenu",{1,11,10,20},function() menu:Invoke("updateButtons") end)
            assert(#sent==1 and #menu.root.buttonArr==0)
            net[RR.MenuChannel](RR.MenuChannel,pystringify({request=1,token="one",
                targets={{guid="dead",name="Ifan ben-Mezd"}}}))
            assert(menu.rendered[4]=="Use" and menu.rendered[11]=="Revive Ifan ben-Mezd")
            call(menu,"buttonPressed",{739101,739101,0})
            assert(#sent==2 and pyparse(sent[2].payload).target=="dead")
        ''')


if __name__ == "__main__":
    unittest.main(verbosity=2)

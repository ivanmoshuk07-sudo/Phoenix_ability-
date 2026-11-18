local A=PhoenixPanel
local T=A.Abilities
local function truth(v) return v==true or v==1 end
local nextSwing={78,845,6807,2973,56815} -- Heroic Strike, Cleave, Maul, Raptor Strike, Rune Strike; names cover ranks.
local function speed()
    local main=UnitAttackSpeed and UnitAttackSpeed('player')
    local value=tonumber(main) or 0
    return value and value>0 and value<60 and value or 0
end
T.autoResources={current='Текущий ресурс',mana='Мана',rage='Ярость',focus='Фокус',energy='Энергия',runic='Сила рун'}

local nextSwingRanks={
    78,284,285,1608,11564,11565,11566,11567,25286,29707,30324,47449,47450,
    845,7369,11608,11609,20569,25231,47519,47520,
    6807,6808,6809,8972,9745,9880,9881,26996,48479,48480,
    2973,14260,14261,14262,14263,14264,14265,14266,27014,48995,48996,56815
}
local rankSet={}; for _,id in ipairs(nextSwingRanks) do rankSet[id]=true end
function T:IsNextSwingBuiltin(id,name)
    if rankSet[tonumber(id)] then return true end
    name=name or (id and GetSpellInfo(id))
    for _,base in ipairs(nextSwing) do
        if name and name==GetSpellInfo(base) then return true end
    end
    return false
end
function T:NextSwingEntry(p)
    if p.kind=='resource' then return false end
    if type(p.nextSwingOverride)=='boolean' then return p.nextSwingOverride end
    return p.nextSwing or self:IsNextSwingBuiltin(p.spellId)
end
function T:IsNextSwing(id,name)
    if self:IsNextSwingBuiltin(id,name) then return true end
    for _,p in ipairs(self:Config().entries) do
        if p.enabled and self:NextSwingEntry(p) and ((id and p.spellId==id) or (name and name==GetSpellInfo(p.spellId))) then return true end
    end
    return false
end

function T:SwingStart()
    local duration=speed()
    if duration>0 then self.swing={duration=duration,finish=GetTime()+duration} else self.swing=nil end
end

-- Sirus 3.3.5a combat log layout, as used by the supplied WA swing tracker.
function T:SwingLog(ts,event,sourceGUID,sourceName,sourceFlags,destGUID,destName,destFlags,...)
    local me=UnitGUID('player')
    if not me then return end
    if sourceGUID==me then
        if event=='SPELL_EXTRA_ATTACKS' then
            self.extraSwingTime=tonumber(ts); self.extraSwingCount=tonumber(select(4,...)) or 0
        elseif event=='SWING_DAMAGE' or event=='SWING_MISSED' then
            if self.extraSwingTime and tonumber(ts) and ts-self.extraSwingTime>=0 and ts-self.extraSwingTime<0.04 and self.extraSwingCount>0 then
                self.extraSwingCount=self.extraSwingCount-1; return
            end
            local _,offSpeed=0,0
            if UnitAttackSpeed then _,offSpeed=UnitAttackSpeed('player') end
            local off
            if event=='SWING_DAMAGE' then off=select(10,...) else off=select(2,...) end
            -- Old clients omit isOffHand. Use WA's timing heuristic only in that case.
            if off~=nil then off=truth(off)
            else off=offSpeed and offSpeed>0 and self.lastMainSwing and GetTime()-self.lastMainSwing<speed()*0.6 end
            if not off then self.lastMainSwing=GetTime(); self:SwingStart() end
        elseif event=='SPELL_DAMAGE' or event=='SPELL_MISSED' then
            local id,name=...
            if self:IsNextSwing(tonumber(id),name) then
                -- Cleave hits several units; all hits belong to one weapon swing.
                if not self.lastReplacementSwing or GetTime()-self.lastReplacementSwing>0.1 then
                    self.lastReplacementSwing=GetTime(); self.lastMainSwing=GetTime(); self:SwingStart()
                end
            end
        end
    elseif destGUID==me and ((event=='SWING_MISSED' and (...)=='PARRY') or (event=='SPELL_MISSED' and select(4,...)=='PARRY')) then
        local s=self.swing
        if s then
            local left=s.finish-GetTime()
            if left>s.duration*0.2 then s.finish=GetTime()+math.max(s.duration*0.2,left-s.duration*0.4) end
        end
    end
end

function T:AutoEvent(event,...)
    if event=='COMBAT_LOG_EVENT_UNFILTERED' then
        if select('#',...)==0 and CombatLogGetCurrentEventInfo then
            local function modern(ts,sub,hide,sg,sn,sf,sr,dg,dn,df,dr,...)
                T:SwingLog(ts,sub,sg,sn,sf,dg,dn,df,...)
            end
            modern(CombatLogGetCurrentEventInfo()); return
        end
        self:SwingLog(...)
    elseif event=='UNIT_ATTACK_SPEED' then
        if (...)~='player' then return end
        local s=self.swing; local new=speed()
        if s and new>0 then
            local remaining=math.max(0,s.finish-GetTime())
            s.finish=GetTime()+remaining*new/s.duration; s.duration=new
        end
    elseif event=='PLAYER_ENTER_COMBAT' then self.autoAttacking=true
    elseif event=='PLAYER_LEAVE_COMBAT' or event=='PLAYER_ENTERING_WORLD' or event=='PLAYER_LOGOUT' then
        self.autoAttacking=false; self.swing=nil; self.lastMainSwing=nil; self.lastReplacementSwing=nil
        self.extraSwingTime=nil; self.extraSwingCount=0; self.swingCasting=nil
    elseif event=='PLAYER_EQUIPMENT_CHANGED' then
        local slot=...
        if slot==16 or slot==17 then self.swing=nil; self.lastMainSwing=nil end
    elseif event=='UNIT_SPELLCAST_START' then
        if (...)=='player' then self.swingCasting=true; self.swing=nil end
    elseif event=='UNIT_SPELLCAST_SUCCEEDED' then
        if (...)=='player' and self.swingCasting then
            self.swingCasting=nil
            if self.autoAttacking then self:SwingStart() end
        end
    elseif event=='UNIT_SPELLCAST_INTERRUPTED' or event=='UNIT_SPELLCAST_FAILED' then
        if (...)=='player' then self.swingCasting=nil end
    end
end

function T:AutoItem()
    local cfg=self:Config().autoAttack
    local name,_,icon=GetSpellInfo(6603)
    local item={id='autoattack',spellId=6603,text=name or 'Автоатака',icon=icon or 'Interface\\Icons\\INV_Sword_04',remaining=0,total=0,multiplicity=1,available=true,autoAttack=true}
    local s=self.swing
    if cfg.showTimer and s then
        item.remaining=math.max(0,s.finish-GetTime()); item.total=s.duration
    end
    if cfg.showResource then
        local r=self:Resource(cfg.resource,'player')
        item.resourceText=r.valid and (tostring(r.value)..'/'..tostring(r.max)) or '—'
    end
    return item
end

function T:Transition(p,item)
    self.transitions=self.transitions or {}
    local now=GetTime()
    local identity=p.kind..':'..tostring(p.spellId or p.resource)..':'..tostring(p.kind=='debuff' and UnitGUID(p.unit) or '')
    local previous=self.transitions[p.uid]
    if not previous or previous.identity~=identity then previous={identity=identity}; self.transitions[p.uid]=previous end
    local cfg=self:Config().flashes
    if p.kind=='spell' and cfg.cooldown and previous.cooling and not item.ownPaused and not item.ownEnd and item.available and item.conditionPassed and not item.queued then
        previous.flashUntil=now+1.2
    elseif p.kind=='debuff' and cfg.debuff and previous.auraEnd and previous.auraEnd>0 and previous.auraEnd<=now and not item.available and item.canApply and item.conditionPassed then
        previous.flashUntil=now+1.2
    end
    previous.cooling=item.ownEnd~=nil
    previous.auraEnd=item.available and item.auraEnd or nil
    if (p.kind=='spell' and (not item.available or item.queued)) or (p.kind=='debuff' and (not item.canApply or item.available)) or not item.conditionPassed then previous.flashUntil=nil end
    item.flash=previous.flashUntil and previous.flashUntil>now or false
    if item.flash and item.conditionPassed then item.visible=true end
end

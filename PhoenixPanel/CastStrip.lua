local A=PhoenixPanel
local T=A.Abilities

function T:CastPriority(entry)
    local value=tonumber(entry.castPriority) or 5
    if value~=value then return 5 end
    return math.max(1,math.min(10,math.floor(value)))
end

function T:StripSpellReadyAt(item)
    if item.queued then return math.huge end
    if item.available then return 0 end
    if not item.priorityCanCast then return math.huge end

    -- Forecast timing without spell costs. The renderer still uses noResource
    -- to tint the ability and conditions are evaluated before scheduling.
    if item.noResource then
        if item.charges~=nil then
            if item.charges>0 then return 0 end
        elseif not item.ownCooldownActive and not item.ownPaused then
            return 0
        end
    end
    if item.ownPaused then return math.huge end
    return item.ownRemaining and item.ownRemaining>0 and item.ownRemaining or math.huge
end

local function entryReadyAt(self,entry,item)
    if entry.kind=='spell' then return self:StripSpellReadyAt(item) end
    if entry.kind=='resource' or item.auraEnd==0 then return math.huge end

    -- "Available" for an aura means it is already present. To forecast
    -- refreshing it, wait for both expiry and the application spell.
    local probe=self.Copy(entry)
    probe.kind='spell'
    probe.mode='always'
    return math.max(self:StripSpellReadyAt(self:Evaluate(probe,true,true)),item.remaining)
end

local function higherPriority(a,b)
    if a.priority~=b.priority then return a.priority<b.priority end
    return a.index<b.index
end

local function spendAura(source,mode,amount,at)
    for _,aura in ipairs(source.auras) do
        if mode=='once' then
            aura.count=0
        elseif aura.expires>at and amount>0 then
            local spent=math.min(aura.count,amount)
            aura.count=aura.count-spent
            amount=amount-spent
        end
    end
end

local function auraSource(self,group,sources,now)
    local unit,id=group.auraConditionUnit,group.auraConditionId
    local filter=group.auraConditionKind=='debuff' and 'HARMFUL' or 'HELPFUL'
    local key=unit..':'..filter..':'..id
    if sources[key] then return sources[key] end
    local auras={}
    for _,aura in ipairs(self:Auras(unit,filter)[id] or {}) do
        local expires=aura.expiration==0 and math.huge or aura.expiration
        if expires>now then auras[#auras+1]={expires=expires,count=math.max(1,aura.count)} end
    end
    table.sort(auras,function(a,b)
        if a.expires~=b.expires then return a.expires<b.expires end
        return a.count<b.count
    end)
    local parts={UnitGUID and UnitGUID(unit) or unit}
    for _,aura in ipairs(auras) do
        parts[#parts+1]=aura.expires..':'..aura.count
    end
    local source={key=key,auras=auras,signature=table.concat(parts,';')}
    sources[key]=source

    -- The success event can precede the aura update. Apply the actual cast
    -- once to its old snapshot until the client reports the changed aura.
    local pending=self.stripPendingAuras and self.stripPendingAuras[key]
    if pending then
        if pending.signature==source.signature then
            spendAura(source,pending.mode,pending.count,now)
        else
            self.stripPendingAuras[key]=nil
        end
    end
    return source
end

local function auraBranches(self,entry,sources,now)
    local triggers=entry.triggers
    if not triggers or entry.invertTriggers then return end
    local any=entry.triggerMode~='one' and entry.triggerMode~='all'
    local first,last=1,#triggers
    if entry.triggerMode=='one' then first=entry.selectedTrigger; last=first end
    local hasCost=false
    for i=first,last do
        if self:AuraConsumptionMode(triggers[i]) then hasCost=true; break end
    end
    if not hasCost then return end

    local branches={}
    local required={}
    for i=first,last do
        local group=triggers[i]
        if group.enabled then
            if self:TriggerState(group) then
                local mode=self:AuraConsumptionMode(group)
                if mode then
                    local source=auraSource(self,group,sources,now)
                    if any then
                        branches[#branches+1]={[source]=mode}
                    elseif required[source]~='once' then
                        required[source]=mode
                    end
                elseif any then
                    return -- An independent trigger already enables the spell.
                end
            elseif not any then
                return {}
            end
        end
    end
    return any and branches or {required}
end

local function payableAuraBranch(branches,at)
    if not branches then return true end
    for _,branch in ipairs(branches) do
        local payable=true
        for source in pairs(branch) do
            local available=false
            for _,aura in ipairs(source.auras) do
                if aura.count>0 and aura.expires>at then available=true; break end
            end
            if not available then payable=false; break end
        end
        if payable then return branch end
    end
end

local function usesAuraStacks(branches)
    for _,branch in ipairs(branches or {}) do
        for _,mode in pairs(branch) do
            if mode=='stack' then return true end
        end
    end
    return false
end

local function refreshSpentAuras(self,now)
    local pending=self.stripPendingAuras
    if not pending then return end
    self.auraCacheTime=nil
    for key,spent in pairs(pending) do
        if spent.expires<=now then pending[key]=nil end
    end
    if not next(pending) then self.stripPendingAuras=nil end
end

local function rememberAuraSpending(self,item,now)
    if not item or not item.stripAuraCost then return end
    self.stripPendingAuras=self.stripPendingAuras or {}
    for _,cost in ipairs(item.stripAuraCost) do
        local previous=self.stripPendingAuras[cost.key]
        local same=previous and previous.signature==cost.signature and previous.expires>now
        local mode=same and previous.mode=='once' and 'once' or cost.mode
        self.stripPendingAuras[cost.key]={
            signature=cost.signature,mode=mode,count=(same and previous.count or 0)+1,
            expires=now+0.5
        }
    end
end

local function knownCooldown(self,spellId)
    if not spellId then return end
    if GetSpellCharges then
        local charges,maximum=GetSpellCharges(spellId)
        if maximum and maximum>0 then
            -- Use the known charges plus at most one projected use if all
            -- charges are currently spent and the next recharge is visible.
            return nil,math.max(1,charges or 0)
        end
    end
    if GetSpellBaseCooldown then
        local milliseconds=GetSpellBaseCooldown(spellId)
        if type(milliseconds)=='number' and milliseconds>=0 and milliseconds<=604800000 then
            return milliseconds/1000
        end
    end
    return self.stripMeasuredCooldowns and self.stripMeasuredCooldowns[spellId]
end

local function sampleCooldowns(self,now,gcdStart,gcdDuration)
    for id,cast in pairs(self.stripObservedCasts or {}) do
        local age=now-cast.time
        if age>0.8 then
            self.stripObservedCasts[id]=nil
        elseif age>=0.1 then
            local start,duration,paused=self:Cooldown(cast.lookup)
            if not paused and duration>0 and math.abs(start-cast.time)<0.35 then
                local shared=gcdDuration>0 and math.abs(start-gcdStart)<0.05
                    and math.abs(duration-gcdDuration)<0.05
                self.stripMeasuredCooldowns=self.stripMeasuredCooldowns or {}
                self.stripMeasuredCooldowns[id]=shared and 0 or duration
                self.stripObservedCasts[id]=nil
            end
        end
    end
end

local function stripBaseKey(item)
    return tostring(item.id)..':'..tostring(item.spellId or item.itemId)
end

local function stripItem(self,item,counts,at)
    local key=stripBaseKey(item)
    counts[key]=(counts[key] or 0)+1
    local slot=self.Copy(item)
    slot.stripAt=at
    slot.stripOccurrence=(self.stripConfirmed and self.stripConfirmed[key] or 0)+counts[key]
    return slot
end

local function project(self,ordered,candidates,limit,cursor,gcdDuration,counts,now)
    local spellReady={}
    local spentCharges={}
    while #ordered<limit do
        local choice,cost
        local nextTime=math.huge
        for _,candidate in ipairs(candidates) do
            local ready=math.max(candidate.ready,spellReady[candidate.spellId] or 0)
            if ready<math.huge then
                local branch=payableAuraBranch(candidate.auraBranches,now+math.max(ready,cursor))
                if branch then
                    if ready<=cursor+0.000001 then
                        if not choice or higherPriority(candidate,choice) then choice,cost=candidate,branch end
                    elseif ready<nextTime then
                        nextTime=ready
                    end
                end
            end
        end
        if choice then
            local slot=stripItem(self,choice.item,counts,cursor)
            ordered[#ordered+1]=slot
            if type(cost)=='table' then
                slot.stripAuraCost={}
                for source,mode in pairs(cost) do
                    spendAura(source,mode,1,now+cursor)
                    slot.stripAuraCost[#slot.stripAuraCost+1]={key=source.key,signature=source.signature,mode=mode}
                end
            end
            local spellId=choice.spellId
            if choice.charges then
                local used=(spentCharges[spellId] or 0)+1
                spentCharges[spellId]=used
                spellReady[spellId]=used<choice.charges and cursor or math.huge
            else
                spellReady[spellId]=choice.cooldown and cursor+choice.cooldown or math.huge
            end
            if choice.aura then
                choice.ready=choice.refresh and cursor+choice.refresh or math.huge
            end
            cursor=cursor+gcdDuration
        elseif nextTime<math.huge then
            cursor=nextTime
        else
            break
        end
    end
end

function T:BuildCastStrip(states)
    local cfg=self:Config()
    local replace=cfg.autoAttack.enabled and cfg.autoAttack.replace
    local now=GetTime()
    local gcdStart,gcdDuration=self:Cooldown(61304)
    local gcdLeft=math.max(0,gcdStart+gcdDuration-now)
    if gcdDuration>0 then self.stripLastGCD=gcdDuration end
    sampleCooldowns(self,now,gcdStart,gcdDuration)
    refreshSpentAuras(self,now)

    local first,candidates,blocked,monitors=nil,{},{},{}
    local sources={}
    for index,state in ipairs(states) do
        local entry,item=state.entry,state.item
        if state.nextSwing then
            if not first and item.conditionPassed and item.visible
                and (not replace or item.available or item.queued) then
                first=item
            end
        elseif item.conditionPassed and (item.visible or entry.kind=='spell') then
            local ready=entryReadyAt(self,entry,item)
            if item.visible or (entry.kind=='spell' and ready<math.huge) then
                local candidate={item=item,index=index,priority=self:CastPriority(entry)}
                if entry.kind=='resource' then
                    monitors[#monitors+1]=candidate
                elseif ready==math.huge or not item.spellId then
                    blocked[#blocked+1]=candidate
                else
                    candidate.ready=ready
                    candidate.spellId=item.spellId
                    candidate.cooldown,candidate.charges=knownCooldown(self,item.spellId)
                    if not item.replacement then
                        candidate.auraBranches=auraBranches(self,entry,sources,now)
                    end
                    if entry.kind=='spell' and candidate.cooldown==nil and not candidate.charges
                        and item.ownRemaining==0 and usesAuraStacks(candidate.auraBranches) then
                        candidate.cooldown=0
                    end
                    candidate.aura=entry.kind~='spell'
                    if candidate.aura and item.available and item.total>0 then
                        candidate.refresh=item.total
                    end
                    candidates[#candidates+1]=candidate
                end
            end
        end
    end

    local ordered={first or self:AutoItem()}
    local limit=cfg.appearance.perRow
    local counts={}
    project(self,ordered,candidates,limit,gcdLeft,self.stripLastGCD or 1.5,counts,now)
    table.sort(blocked,higherPriority)
    table.sort(monitors,higherPriority)
    for _,list in ipairs({blocked,monitors}) do
        for _,entry in ipairs(list) do
            if #ordered>=limit then return ordered end
            ordered[#ordered+1]=stripItem(self,entry.item,counts)
        end
    end
    return ordered
end

function T:CastStripEvent(event,unit,name,rank,lineId,spellId)
    if event~='UNIT_SPELLCAST_SUCCEEDED' or unit~='player'
        or not A.db or not A.db.abilities then return end
    local cfg=self:Config()
    if cfg.panelMode~='strip' or not cfg.appearance.enabled or self:IsProfileOff() then return end

    local id=tonumber(spellId)
    if not id and lineId==nil and type(rank)=='number' then
        -- Some clients send unit, cast GUID and spell ID.
        id=rank
        if type(name)=='string' and name:match('^Cast%-') then name=nil end
    end
    if type(name)=='number' then id=id or name; name=nil end
    if not id and type(name)~='string' then return end

    local used=self:OnStripCast(id,name)
    local now=GetTime()
    rememberAuraSpending(self,used,now)
    if used and used.stripOccurrence then
        self.stripConfirmed=self.stripConfirmed or {}
        local key=stripBaseKey(used)
        self.stripConfirmed[key]=math.max(self.stripConfirmed[key] or 0,used.stripOccurrence)
    end
    local tracked=used and used.spellId or id
    if not tracked then
        for _,entry in ipairs(cfg.entries) do
            if entry.enabled and entry.spellId and GetSpellInfo(entry.spellId)==name then
                tracked=entry.spellId
                break
            end
        end
    end
    if tracked then
        self.stripObservedCasts=self.stripObservedCasts or {}
        self.stripObservedCasts[tracked]={time=now,lookup=id or tracked}
    end
end

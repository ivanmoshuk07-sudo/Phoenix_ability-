local A=PhoenixPanel
local T=A.Abilities

function T:CastPriority(entry)
    local value=tonumber(entry.castPriority) or 5
    if value~=value then return 5 end
    return math.max(1,math.min(10,math.floor(value)))
end

local function spellTiming(item)
    if item.available and not item.queued
        or (item.prioritySoon and item.priorityReady and not item.noResource) then
        return true,0
    end
    if item.priorityCanCast and not item.noResource and not item.ownPaused
        and not item.queued and item.ownRemaining and item.ownRemaining>0 then
        return false,item.ownRemaining
    end
    return false,math.huge
end

local function timing(self,entry,item)
    if entry.kind=='spell' then return spellTiming(item) end
    if entry.kind=='resource' then return false,math.huge end
    if item.auraEnd==0 then return false,math.huge end

    -- In an aura entry, available describes the aura rather than the spell.
    local probe=self.Copy(entry)
    probe.kind='spell'
    probe.mode='always'
    local ready,left=spellTiming(self:Evaluate(probe,true,true))
    return ready and (not item.available or item.auraPrioritySoon),math.max(left,item.remaining)
end

local function compare(a,b)
    if a.band~=b.band then return a.band<b.band end
    if a.band==2 and a.left~=b.left then return a.left<b.left end
    if a.priority~=b.priority then return a.priority<b.priority end
    return a.index<b.index
end

function T:BuildCastStrip(states)
    local cfg=self:Config()
    local replace=cfg.autoAttack.enabled and cfg.autoAttack.replace
    local first,candidates=nil,{}
    for index,state in ipairs(states) do
        local entry,item=state.entry,state.item
        if state.nextSwing then
            if not first and item.conditionPassed and item.visible
                and (not replace or item.available or item.queued) then
                first=item
            end
        elseif item.conditionPassed and (item.visible or entry.kind=='spell') then
            local ready,left=timing(self,entry,item)
            -- A spell that will recover during the current GCD is actionable
            -- for the strip even without the classic "move to front" flag.
            if item.visible or (entry.kind=='spell' and ready) then
                candidates[#candidates+1]={
                    item=item,index=index,priority=self:CastPriority(entry),left=left,
                    band=ready and 1 or (entry.kind=='resource' and 3 or 2)
                }
            end
        end
    end
    table.sort(candidates,compare)
    local ordered={first or self:AutoItem()}
    for _,candidate in ipairs(candidates) do
        ordered[#ordered+1]=candidate.item
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
    self:OnStripCast(id,name)
end

local A=PhoenixPanel
local E=ElvUI[1]
local T={holders={},revision=0,auraCache={}}
A.Abilities=T
-- Reuse stateless drawing helpers only; lifecycle and timers are independent.
T.TextStyle=A.DBM.TextStyle
T.SpellTooltip=A.DBM.SpellTooltip
T.HideAll=A.DBM.HideAll
T.HideUnused=A.DBM.HideUnused
local inverse={TOP='BOTTOM',BOTTOM='TOP',TOPLEFT='BOTTOMLEFT',TOPRIGHT='BOTTOMRIGHT',LEFT='RIGHT',RIGHT='LEFT',BOTTOMLEFT='TOPLEFT',BOTTOMRIGHT='TOPRIGHT',CENTER='CENTER'}
local function copy(t)
    local out={}; for k,v in pairs(t) do out[k]=type(v)=='table' and copy(v) or v end; return out
end
T.Copy=copy
local appearance=copy(A.defaults.dbm)
appearance.selected=nil; appearance.sort=nil; appearance.descending=nil
appearance.frame='target'; appearance.y=40; appearance.desaturate=true
appearance.scale=1
A.defaults.abilities={appearance=appearance,entries={},nextId=1,panelMode='classic',stripHighestOnly=false,autoAttack={enabled=false,showTimer=true,showResource=false,resource='current',resourcePosition='BOTTOM',replace=true},flashes={cooldown=true,debuff=true}}
T.kinds={spell='Способность',buff='Баф',debuff='Дебаф',resource='Ресурс'}
T.units={player='Игрок',target='Цель',focus='Фокус',pet='Питомец'}
T.resources={current='Текущий ресурс',mana='Мана',rage='Ярость',focus='Фокус',energy='Энергия',runic='Сила рун',combo='Комбо-очки',health='Здоровье',targethealth='ХП цели',happiness='Счастье питомца',runes='Все руны',blood='Руны крови',frost='Руны льда',unholy='Руны нечестивости',death='Руны смерти'}
local powers={mana=0,rage=1,focus=2,energy=3,runic=6}
local runeTypes={blood=1,unholy=2,frost=3,death=4}
local textures={mana='Interface\\Icons\\INV_Potion_76',rage='Interface\\Icons\\Ability_Racial_BloodRage',energy='Interface\\Icons\\Spell_Shadow_ShadowWordDominate',runic='Interface\\Icons\\Spell_Deathknight_RuneTap',combo='Interface\\Icons\\Ability_Rogue_Eviscerate',health='Interface\\Icons\\INV_Stone_04',runes='Interface\\Icons\\Spell_Deathknight_BloodTap',blood='Interface\\Icons\\Spell_Deathknight_BloodPresence',frost='Interface\\Icons\\Spell_Deathknight_FrostPresence',unholy='Interface\\Icons\\Spell_Deathknight_UnholyPresence',death='Interface\\Icons\\Spell_Deathknight_EmpowerRuneBlade',focus='Interface\\Icons\\Ability_Hunter_FocusFire'}
textures.happiness='Interface\\Icons\\Ability_Hunter_BeastCall'
textures.targethealth=textures.health
local function apiTrue(value) return value==true or value==1 end

local function spellOutOfRange(id,name)
    if not name or (UnitExists and not apiTrue(UnitExists('target'))) then return false end
    local spellRange=E.Libs and E.Libs.SpellRange
    local range
    if spellRange and spellRange.IsSpellInRange then range=spellRange.IsSpellInRange(id,'target') end
    if range==nil and IsSpellInRange then range=IsSpellInRange(name,'target') end
    return range==0 or range==false
end

function T:Config() return A.db.abilities end

function T:Validate()
    local cfg=self:Config()
    if not self.stationary and cfg.panelMode~='strip' then cfg.panelMode='classic' end
    local function number(t,k,d,lo,hi)
        local n=tonumber(t[k]); if not n or n~=n then n=d end
        t[k]=math.floor(math.max(lo,math.min(hi,n)))
    end
    for _,k in ipairs({'enabled','stack','desaturate','keepAspect'}) do if type(cfg.appearance[k])~='boolean' then cfg.appearance[k]=appearance[k] end end
    for k,b in pairs({size={6,60},height={6,60},perRow={1,20},rows={1,5},spacing={0,60},x={-100,100},y={-100,100}}) do number(cfg.appearance,k,appearance[k],b[1],b[2]) end
    local scale=tonumber(cfg.appearance.scale) or 1
    if scale~=scale then scale=1 end
    cfg.appearance.scale=math.max(0.25,math.min(3,scale))
    if not inverse[cfg.appearance.anchor] then cfg.appearance.anchor='TOPLEFT' end
    if cfg.appearance.growX~='LEFT' then cfg.appearance.growX='RIGHT' end
    if cfg.appearance.growY~='DOWN' then cfg.appearance.growY='UP' end
    local frames={target=true,player=true,unitTarget=true,unitPlayer=true}
    if not frames[cfg.appearance.frame] then cfg.appearance.frame='target' end
    for _,k in ipairs({'count','duration'}) do
        local s=cfg.appearance[k]
        if type(s.font)~='string' or s.font=='' then s.font='DEFAULT' end
        if type(s.show)~='boolean' then s.show=true end
        if k=='duration' and type(s.swipe)~='boolean' then s.swipe=true end
        if not inverse[s.point] then s.point=appearance[k].point end
        local outlines={['']=true,OUTLINE=true,THICKOUTLINE=true,['MONOCHROME,OUTLINE']=true}
        if not outlines[s.outline] then s.outline='OUTLINE' end
        number(s,'size',12,4,60); number(s,'x',0,-100,100); number(s,'y',0,-100,100)
    end
    local auto=cfg.autoAttack
    for _,k in ipairs({'enabled','showTimer','showResource','replace'}) do if type(auto[k])~='boolean' then auto[k]=A.defaults.abilities.autoAttack[k] end end
    if not self.autoResources[auto.resource] then auto.resource='current' end
    if auto.resourcePosition~='TOP' then auto.resourcePosition='BOTTOM' end
    for _,k in ipairs({'cooldown','debuff'}) do if type(cfg.flashes[k])~='boolean' then cfg.flashes[k]=true end end
    local entries={}; local used={}; local nextId=math.max(1,tonumber(cfg.nextId) or 1)
    for i=1,#cfg.entries do
        local p=cfg.entries[i]
        local id=type(p)=='table' and tonumber(p.kind=='item' and p.itemId or p.spellId)
        if type(p)=='table' and self.kinds[p.kind] and (p.kind=='resource' or (id and id>0)) then
            p.uid=tonumber(p.uid)
            if not p.uid or p.uid~=math.floor(p.uid) or p.uid<1 or used[p.uid] then p.uid=nextId; nextId=nextId+1 end
            used[p.uid]=true; nextId=math.max(nextId,p.uid+1)
            if p.kind=='item' then p.itemId=id elseif p.spellId then p.spellId=id end
            p.unit=T.units[p.unit] and p.unit or 'player'
            p.mode=p.mode=='available' and 'available' or 'always'
            if p.enabled==nil then p.enabled=true end
            if p.showGCD==nil then p.showGCD=true end
            if not T.resources[p.resource] then p.resource='current' end
            if not T.resources[p.conditionResource] then p.conditionResource='current' end
            p.conditionValue=tonumber(p.conditionValue) or 0
            if p.conditionOp~='le' and p.conditionOp~='eq' then p.conditionOp='ge' end
            if p.auraConditionUnit~='target' then p.auraConditionUnit='player' end
            if p.auraConditionKind~='debuff' then p.auraConditionKind='buff' end
            if not self.stationary and p.kind~='resource' then p.nextSwing=self:NextSwingEntry(p) end
            if not self.stationary and p.castPriority~=nil then p.castPriority=self:CastPriority(p) end
            p.auraConditionId=tonumber(p.auraConditionId)
            if p.auraConditionMode~='absent' then p.auraConditionMode='present' end
            entries[#entries+1]=p
        end
    end
    cfg.entries=entries; cfg.nextId=nextId
end

function T:Find(id,kind,resource)
    if not self.kinds[kind] then return nil,'Выберите тип отслеживания.' end
    if kind=='resource' then
        if not self.resources[resource] then return nil,'Выберите ресурс.' end
        return {kind=kind,resource=resource,name=self.resources[resource],icon=textures[resource] or textures.mana,unit=resource=='targethealth' and 'target' or 'player',mode='always',enabled=true,showGCD=true,conditionResource='current',conditionOp='ge',conditionValue=0,auraConditionKind='buff',auraConditionUnit='player'}
    end
    id=tonumber(id)
    if not id or id<1 or id>2147483647 or id~=math.floor(id) then return nil,'Введите целый положительный ID способности.' end
    local name,_,icon=GetSpellInfo(id)
    if not name then return nil,'Способность не найдена в клиенте. Проверьте ID и повторите поиск.' end
    return {nextSwing=kind=='spell' and self:IsNextSwing(id) or false,kind=kind,spellId=id,name=name,icon=icon,unit=kind=='debuff' and 'target' or 'player',mode='always',enabled=true,showGCD=true,onlyMine=false,conditionResource='current',conditionOp='ge',conditionValue=0,auraConditionKind='buff',auraConditionUnit='player'}
end

function T:Save(p,index)
    local cfg=self:Config(); local entry=copy(p)
    if index and cfg.entries[index] then entry.uid=cfg.entries[index].uid; cfg.entries[index]=entry
    else entry.uid=cfg.nextId; cfg.nextId=cfg.nextId+1; cfg.entries[#cfg.entries+1]=entry end
    self:Apply()
end
function T:Move(index,delta)
    local list=self:Config().entries; local other=index+delta
    if list[index] and other>=1 and other<=#list then list[index],list[other]=list[other],list[index]; self:Apply() end
end
function T:Delete(index)
    local list=self:Config().entries
    if list[index] then table.remove(list,index); self:Apply() end
end

function T:Cooldown(id)
    if type(GetSpellCooldown)~='function' then return 0,0,false end
    local start,duration,enabled=GetSpellCooldown(id)
    start=tonumber(start) or 0; duration=tonumber(duration) or 0
    if duration<0 or duration>604800 or duration~=duration or start~=start then return 0,0,false end
    if start>GetTime()+2147483.648 then start=start-4294967.296 end
    if duration==0 or start+duration<=GetTime() then return 0,0,false end
    local paused=enabled==0 or enabled==false
    if paused and (duration<=0.5 or duration==10) then return 0,0,false end
    return start,duration,paused
end

function T:Resource(key,unit)
    if key=='targethealth' then key='health'; unit='target' end
    local r={value=0,max=0,remaining=0,total=0,valid=false}
    if not UnitExists(unit) then return r end
    if key=='health' then
        if UnitHealth and UnitHealthMax then r.value=UnitHealth(unit) or 0; r.max=UnitHealthMax(unit) or 0; r.valid=r.max>0 end
    elseif key=='combo' then
        if unit=='player' and GetComboPoints then r.value=GetComboPoints('player','target') or 0; r.max=MAX_COMBO_POINTS or 5; r.valid=true end
    elseif key=='happiness' then
        if (unit=='player' or unit=='pet') and GetPetHappiness then r.value=GetPetHappiness() or 0; r.max=3; r.valid=r.value>0 end
    elseif key=='runes' or runeTypes[key] then
        local _,class=UnitClass('player')
        if unit=='player' and class=='DEATHKNIGHT' and GetRuneCooldown then
            for i=1,6 do
                if key=='runes' or (GetRuneType and GetRuneType(i)==runeTypes[key]) then
                    local start,duration,ready=GetRuneCooldown(i)
                    if start and duration then
                        r.valid=true; r.max=r.max+1
                        local left=math.max(0,start+duration-GetTime())
                        if ready or left<=0 then r.value=r.value+1
                        elseif r.remaining==0 or left<r.remaining then r.remaining=left; r.total=duration end
                    end
                end
            end
        end
    elseif UnitPower and UnitPowerMax then
        local power=powers[key]
        if key=='current' and UnitPowerType then power=UnitPowerType(unit) end
        if power then r.value=UnitPower(unit,power) or 0; r.max=UnitPowerMax(unit,power) or 0; r.valid=r.max>0; r.power=power end
    end
    return r
end

function T:Auras(unit,filter)
    if not self.auraCacheTime or GetTime()-self.auraCacheTime>=1 then self.auraCache={}; self.auraCacheTime=GetTime() end
    local cache=self.auraCache[unit..':'..filter]
    if cache then return cache end
    cache={}; self.auraCache[unit..':'..filter]=cache
    if not UnitExists(unit) then return cache end
    for i=1,80 do
        local name,rank,icon,count,dispel,duration,expiration,caster,steal,consolidate,id
        if UnitAura then name,rank,icon,count,dispel,duration,expiration,caster,steal,consolidate,id=UnitAura(unit,i,filter)
        elseif filter=='HELPFUL' and UnitBuff then name,rank,icon,count,dispel,duration,expiration,caster,steal,consolidate,id=UnitBuff(unit,i)
        elseif filter=='HARMFUL' and UnitDebuff then name,rank,icon,count,dispel,duration,expiration,caster,steal,consolidate,id=UnitDebuff(unit,i) end
        if not name then break end
        if id then
            cache[id]=cache[id] or {}
            cache[id][#cache[id]+1]={icon=icon,count=count or 0,duration=duration or 0,expiration=expiration or 0,caster=caster,index=i}
        end
    end
    return cache
end

function T:Condition(p)
    if p.auraCondition then
        if not p.auraConditionId or not UnitExists(p.auraConditionUnit) then return false,'Не найдена цель или не задан ID условия ауры.' end
        local filter=p.auraConditionKind=='debuff' and 'HARMFUL' or 'HELPFUL'
        local found=false
        for _,aura in ipairs(self:Auras(p.auraConditionUnit,filter)[p.auraConditionId] or {}) do
            if aura.expiration==0 or aura.expiration>GetTime() then found=true; break end
        end
        if p.auraConditionMode=='absent' then
            if found then return false,'Выбранный баф/дебаф присутствует.' end
        elseif not found then return false,'Нет выбранного бафа/дебафа.' end
    end
    if not p.condition then return true end
    local r=self:Resource(p.conditionResource,'player')
    if not r.valid then return false,'Выбранный ресурс недоступен.' end
    local value=r.value
    if p.conditionPercent then if r.max<=0 then return false,'Ресурс недоступен.' end; value=value/r.max*100 end
    local passed
    if p.conditionOp=='le' then passed=value<=p.conditionValue
    elseif p.conditionOp=='eq' then passed=math.abs(value-p.conditionValue)<0.0001
    else passed=value>=p.conditionValue end
    local reason=string.format('%s: %.1f%s, условие %s %.1f.',self.resources[p.conditionResource],value,p.conditionPercent and '%' or '',({le='<=',eq='=',ge='>='})[p.conditionOp],p.conditionValue)
    return passed,reason
end

local overpowerRanks={[7384]=true,[7887]=true,[11584]=true,[11585]=true}
function T:IsOverpower(id)
    if overpowerRanks[id] then return true end
    local name=id and GetSpellInfo(id)
    return name and name==GetSpellInfo(7384) or false
end
function T:HasOverpowerProc()
    for _,id in ipairs({304676,60503}) do
        for _,aura in ipairs(self:Auras('player','HELPFUL')[id] or {}) do
            if aura.expiration==0 or aura.expiration>GetTime() then return true end
        end
    end
    return false
end

function T:Evaluate(p,inspect)
    local item={id=p.uid,spellId=p.spellId,text=p.name or '',icon=p.icon,remaining=0,total=0,multiplicity=1,available=false}
    local known=true
    if p.kind=='resource' then
        local r=self:Resource(p.resource,p.unit)
        if p.resource=='current' then item.icon=textures[({[0]='mana',[1]='rage',[2]='focus',[3]='energy',[6]='runic'})[r.power]] or item.icon end
        item.remaining=r.remaining; item.total=r.total; item.available=r.valid and r.value>0
        item.countText=r.valid and (p.resourcePercent and string.format('%.0f%%',r.value/math.max(1,r.max)*100) or tostring(r.value)..'/'..r.max) or '—'
        item.details=(T.resources[p.resource] or 'Ресурс')..': '..item.countText; item.resource=true
    elseif p.kind=='spell' then
        local start,duration,paused=self:Cooldown(p.spellId)
        local gs,gd=self:Cooldown(61304)
        local gcdLeft=gd>0 and math.max(0,gs+gd-GetTime()) or 0
        item.gcdActive=gcdLeft>0
        local gcd=duration>0 and gd>0 and math.abs(start-gs)<0.05 and math.abs(duration-gd)<0.05
        local ownCD=duration>0 and not gcd
        item.ownCooldownActive=ownCD
        local name=GetSpellInfo(p.spellId)
        local usable,lacksResource=true,false
        if IsUsableSpell then
            -- Like the supplied WA: legacy Sirus usability uses the learned spell name.
            local u,n=IsUsableSpell(name or p.spellId)
            if not apiTrue(u) and not apiTrue(n) and name then
                local byId,byIdResource=IsUsableSpell(p.spellId)
                if apiTrue(byId) or apiTrue(byIdResource) then u,n=byId,byIdResource end
            end
            lacksResource=apiTrue(n); usable=apiTrue(u) and not lacksResource
        end
        if IsSpellKnown then
            known=apiTrue(IsSpellKnown(p.spellId))
        end
        item.applicationBlocked=not known or (not usable and not lacksResource and (not ownCD or item.gcdActive))
        item.noResource=known and lacksResource
        if not known then item.reason='Способность не изучена.'
        elseif lacksResource then item.reason='Недостаточно ресурса.'
        elseif ownCD then item.reason='Собственная перезарядка.'
        elseif not usable then item.reason='Сейчас нельзя применить.' end
        item.available=known and usable and not ownCD and not paused
        if GetSpellCharges then
            local charges,maxCharges,cs,cd=GetSpellCharges(p.spellId)
            if charges and maxCharges and maxCharges>0 then
                item.charges=charges
                item.countText=charges..'/'..maxCharges
                item.available=known and usable and charges>0
                if charges<maxCharges and cs and cd and cd>0 then start=cs; duration=cd; ownCD=true; paused=false end
            end
        end
        if p.checkRange and known and spellOutOfRange(p.spellId,name) then
            item.outOfRange=true
            -- Range is a visual warning in the dynamic queue. Keep its
            -- ordering and visibility based on the spell's other checks.
            if self.stationary then
                item.available=false
                item.reason='Цель вне дальности.'
                item.applicationBlocked=true
            end
        end
        if ownCD then item.total=duration; item.remaining=paused and duration or math.max(0,start+duration-GetTime()); item.paused=paused end
        item.ownRemaining=ownCD and not paused and math.max(0,start+duration-GetTime()) or 0
        item.ownEnd=item.ownRemaining>0 and start+duration or nil
        item.ownPaused=paused
        -- A spell can enter the priority queue early only if its own cooldown
        -- ends by the END of the CURRENT GCD, not within a whole new GCD.
        -- If the GCD has already ended, wait for the spell itself to be ready.
        local gcdWindow=gd>0 and gd or 1.5
        item.prioritySoon=ownCD and not paused and gcdLeft>0
            and item.ownRemaining>0 and item.ownRemaining<=gcdLeft
        -- Resource shortage does not cancel the "move to front" checkbox.
        -- Learned-spell, proc and cooldown checks still control forecast eligibility.
        item.priorityCanCast=known and (usable or lacksResource)
            and not item.applicationBlocked
        -- This marker is only used for display ordering: an old-style
        -- priority candidate still waiting past the current GCD must not
        -- remain in front of another already usable spell.
        item.priorityWaiting=ownCD and not paused and item.priorityCanCast
            and item.ownRemaining>gcdLeft and item.ownRemaining<=gcdWindow
        if p.showGCD and gd>0 and not item.paused and gcdLeft>item.remaining then
            item.total=gd; item.remaining=gcdLeft; item.gcd=true
        end
    else
        local filter=p.kind=='buff' and 'HELPFUL' or 'HARMFUL'
        local matches=UnitExists(p.unit) and (self:Auras(p.unit,filter)[p.spellId] or {}) or {}
        local best,stacks
        for _,aura in ipairs(matches) do
            if (aura.expiration==0 or aura.expiration>GetTime()) and (not p.onlyMine or (aura.caster and UnitIsUnit(aura.caster,'player'))) then
                stacks=(stacks or 0)+math.max(1,aura.count)
                if not best or (aura.expiration>0 and (best.expiration==0 or aura.expiration<best.expiration)) then best=aura end
                if not self:Config().appearance.stack then break end
            end
        end
        if best then
            item.available=true; item.icon=best.icon or item.icon; item.total=best.duration
            item.remaining=best.expiration>0 and math.max(0,best.expiration-GetTime()) or 0
            item.count=self:Config().appearance.stack and stacks or best.count
            item.auraEnd=best.expiration
            item.auraUnit=p.unit; item.auraIndex=best.index; item.auraFilter=filter
            -- An expiring buff/debuff may be refreshed by the end of the
            -- CURRENT GCD. A permanent aura (expiration=0) is not expiring.
            local gs,gd=self:Cooldown(61304)
            local gcdLeft=gd>0 and math.max(0,gs+gd-GetTime()) or 0
            item.auraPrioritySoon=best.expiration>0 and item.remaining>0
                and gcdLeft>0 and item.remaining<=gcdLeft
        end
    end
    if p.kind=='spell' and self:IsOverpower(p.spellId) and not self:HasOverpowerProc() then
        item.procBlocked=true; item.applicationBlocked=true; item.noResource=false
        item.available=false; item.remaining=0; item.total=0; item.ownRemaining=0; item.ownEnd=nil; item.gcd=nil
        item.reason='Нет прока Превосходства: требуется баф 304676 или 60503.'
    end
    if p.kind~='resource' and IsCurrentSpell then
        local name=GetSpellInfo(p.spellId)
        item.queued=apiTrue(IsCurrentSpell(name or p.spellId)) or apiTrue(IsCurrentSpell(p.spellId))
        if not known or item.procBlocked then item.queued=false end
        item.queueGray=p.kind=='debuff'
    end
    item.unavailable=not item.available
    item.fade=p.kind=='spell' and (item.applicationBlocked and not item.queued or false) or (p.kind~='spell' and item.unavailable and not item.noResource)
    local condition,conditionText=self:Condition(p)
    item.conditionPassed=condition
    item.visible=(p.mode~='available' or item.available or (p.kind=='spell' and item.queued)) and condition
    item.conditionText=conditionText
    item.hiddenReason=not condition and conditionText or ((p.mode=='available' and not item.available) and item.reason)
    if p.kind=='debuff' or (p.kind=='buff' and p.readyFirst) then
        local probe=copy(p); probe.kind='spell'; probe.mode='always'
        local cast=self:Evaluate(probe,true)
        item.canApply=(cast.available or
            (cast.noResource and cast.priorityCanCast and not cast.ownCooldownActive))
            and cast.conditionPassed and not cast.queued
        local canApplyByGCDEnd=item.canApply or (cast.prioritySoon and cast.priorityReady and cast.conditionPassed)
        item.priorityReady=(not item.available or item.auraPrioritySoon) and canApplyByGCDEnd
        if p.readyFirst and item.priorityReady and condition then item.visible=true end
    elseif p.kind=='spell' then
        item.priorityReady=item.priorityCanCast
            and (item.available or item.prioritySoon or (item.noResource and not item.ownCooldownActive))
            and not item.queued and not item.procBlocked
        -- In "when available" mode, a flagged spell may be shown early only
        -- for this short, usable cooldown window; unrelated entries are unchanged.
        if p.readyFirst and item.prioritySoon and item.priorityReady and condition then
            item.visible=true; item.hiddenReason=nil
        end
    else item.priorityReady=item.available and not item.queued end
    if not item.visible and not inspect then return end
    return item
end

function T:NewHolder(plate)
    -- Keep icon size in UI units instead of inheriting the engine/nameplate zoom.
    local frame=CreateFrame('Frame',nil,UIParent)
    -- Same low layer as normal gameplay/action panels. System menus stay above icons.
    frame:EnableMouse(false); frame:SetFrameStrata('LOW'); frame:SetFrameLevel(5)
    local h={frame=frame,icons={}}
    self.holders[plate]=h
    return h
end

function T:Icon(h,index)
    local icon=A.DBM.Icon(self,h,index)
    if not icon.abilityTooltip then
        icon.abilityTooltip=true
        icon.autoResource=icon.textLayer:CreateFontString(nil,'OVERLAY','GameFontNormal')
        icon.autoResource:SetJustifyH('CENTER'); icon.autoResource:Hide()
        icon.queueGlow={}
        for i=1,4 do
            local edge=icon.textLayer:CreateTexture(nil,'OVERLAY')
            edge:SetTexture(1,1,1,1)
            if i<=2 then
                edge:SetPoint(i==1 and 'TOPLEFT' or 'BOTTOMLEFT',icon,i==1 and 'TOPLEFT' or 'BOTTOMLEFT',-2,i==1 and 2 or -2)
                edge:SetPoint(i==1 and 'TOPRIGHT' or 'BOTTOMRIGHT',icon,i==1 and 'TOPRIGHT' or 'BOTTOMRIGHT',2,i==1 and 2 or -2)
                edge:SetHeight(3)
            else
                edge:SetPoint(i==3 and 'TOPLEFT' or 'TOPRIGHT',icon,i==3 and 'TOPLEFT' or 'TOPRIGHT',i==3 and -2 or 2,2)
                edge:SetPoint(i==3 and 'BOTTOMLEFT' or 'BOTTOMRIGHT',icon,i==3 and 'BOTTOMLEFT' or 'BOTTOMRIGHT',i==3 and -2 or 2,-2)
                edge:SetWidth(3)
            end
            edge:Hide(); icon.queueGlow[i]=edge
        end
        icon.textLayer:SetScript('OnUpdate',function(_,dt)
            if icon.buttonGlowLib or (not icon.queueActive and not icon.flashActive) then return end
            icon.queuePhase=(icon.queuePhase or 0)+dt
            local alpha=0.25+0.75*(0.5+0.5*math.sin(icon.queuePhase*math.pi*4))
            for _,edge in ipairs(icon.queueGlow) do edge:SetAlpha(alpha) end
        end)
        icon:HookScript('OnHide',function(f)
            if f.buttonGlowLib then f.buttonGlowLib.ButtonGlow_Stop(f); f.buttonGlowLib=nil; f.glowKey=nil end
        end)
        icon:SetScript('OnEnter',function(f) self:TrackingTooltip(f) end)
    end
    return icon
end

function T:TrackingTooltip(frame)
    local item=frame.abilityState
    if not item then return end
    if item.itemId then
        GameTooltip:SetOwner(frame,'ANCHOR_RIGHT')
        local _,link
        if GetItemInfo then _,link=GetItemInfo(item.itemId) end
        if link then GameTooltip:SetHyperlink(link) else GameTooltip:SetText(item.text) end
        GameTooltip:Show()
    elseif item.resource then
        GameTooltip:SetOwner(frame,'ANCHOR_RIGHT'); GameTooltip:SetText(item.text); GameTooltip:AddLine(item.details or '',1,1,1,true); GameTooltip:Show()
    elseif item.auraIndex and GameTooltip.SetUnitAura then
        GameTooltip:SetOwner(frame,'ANCHOR_RIGHT'); GameTooltip:SetUnitAura(item.auraUnit,item.auraIndex,item.auraFilter); GameTooltip:Show()
    else
        self:SpellTooltip(frame,item.spellId,item.text)
    end
end

function T:Render(plate,items)
    local panel=self:Config()
    local cfg=panel.appearance
    if #items==0 then if self.holders[plate] then self.holders[plate].frame:Hide() end; return end
    local h=self.holders[plate] or self:NewHolder(plate)
    if h.scale~=cfg.scale then h.frame:SetScale(cfg.scale); h.scale=cfg.scale end
    h.touched=true
    local rowsLimit=h.castStrip and 1 or cfg.rows
    local n=math.min(#items,cfg.perRow*rowsLimit)
    local w,height=cfg.size,cfg.keepAspect and cfg.size or cfg.height
    local columns=h.castStrip and cfg.perRow or math.min(n,cfg.perRow)
    local rows=math.ceil(n/cfg.perRow)
    local width=columns*w+(columns-1)*cfg.spacing
    -- Position resource numbers independently per icon; existing entries keep
    -- their original default (below for spells/autoattack, overlaid for resources).
    local entriesById={}
    for _,entry in ipairs(panel.entries) do entriesById[entry.uid]=entry end
    local resourceValues={}
    local abovePadding,belowPadding=0,0
    if h.castStrip then
        -- Keep the mover dimensions stable when icons disappear so a centered
        -- or right-anchored mover does not pull the fixed first slot sideways.
        local pad=cfg.count.size+4
        local auto=panel.autoAttack
        if auto.showResource then
            if auto.resourcePosition=='TOP' then abovePadding=pad else belowPadding=pad end
        end
        for _,entry in ipairs(panel.entries) do
            if entry.enabled and (entry.showResource or (entry.kind=='resource' and cfg.count.show)) then
                if entry.resourcePosition=='TOP' then abovePadding=pad
                elseif entry.resourcePosition=='BOTTOM' or entry.kind~='resource' then belowPadding=pad end
            end
        end
    end
    for i=1,n do
        local item=items[i]
        local entry=entriesById[item.id]
        local position=item.autoAttack and panel.autoAttack.resourcePosition
            or (entry and entry.resourcePosition)
        local value=item.resourceText or ''
        if item.resource then
            if position~='TOP' and position~='BOTTOM' then position='ICON' end
            if position~='ICON' then value=cfg.count.show and (item.countText or '') or '' end
        elseif position~='TOP' then position='BOTTOM' end
        resourceValues[i]={position=position,text=value}
        if value~='' and position=='TOP' then abovePadding=cfg.count.size+4
        elseif value~='' and position=='BOTTOM' then belowPadding=cfg.count.size+4 end
    end
    local rowHeight=height+abovePadding+belowPadding
    local totalHeight=rows*rowHeight+(rows-1)*cfg.spacing
    local anchor=plate.Health or plate
    local layoutSize=h.castStrip and columns or n
    local layout=tostring(self.revision)..':'..layoutSize..':'..abovePadding..':'..belowPadding
    if h.layout~=layout or h.anchor~=anchor or h.scaleLayout~=cfg.scale then
        -- ElvUI's mover follows the size of its registered parent. Keep its
        -- visible box aligned with the full icon group in config mode.
        -- Avoid the old nameplate anchor offsets: they made the orange
        -- draggable box appear far below/aside from the actual abilities.
        anchor:SetSize(width*cfg.scale,totalHeight*cfg.scale)
        h.frame:ClearAllPoints(); h.frame:SetSize(width,totalHeight)
        h.frame:SetPoint('TOPLEFT',anchor,'TOPLEFT',0,0)
        h.layout=layout; h.anchor=anchor; h.scaleLayout=cfg.scale
    end
    local now=GetTime()
    for i,item in ipairs(items) do
        if i>n then break end
        local icon=self:Icon(h,i)
        local previous=icon.abilityState
        icon.spellId=item.spellId; icon.timerText=item.text; icon.abilityState=item
        if GameTooltip:IsOwned(icon) and (not previous or previous.spellId~=item.spellId
            or previous.itemId~=item.itemId or previous.text~=item.text) then
            self:TrackingTooltip(icon)
        end
        local col=(i-1)%cfg.perRow; local row=math.floor((i-1)/cfg.perRow)
        if h.castStrip then
            self:PositionCastStripIcon(h,icon,col*(w+cfg.spacing),-abovePadding,w,height)
        elseif icon.layout~=layout then
            if cfg.growX=='LEFT' then col=columns-1-col end
            if cfg.growY=='UP' then row=rows-1-row end
            icon:SetSize(w,height); icon:ClearAllPoints()
            icon:SetPoint('TOPLEFT',h.frame,'TOPLEFT',col*(w+cfg.spacing),-abovePadding-row*(rowHeight+cfg.spacing))
            icon.layout=layout
        end
        local texture=item.icon or 'Interface\\Icons\\INV_Misc_QuestionMark'
        if icon.texturePath~=texture then icon.texture:SetTexture(texture); icon.texturePath=texture end
        if icon.keepAspect~=cfg.keepAspect then
            if cfg.keepAspect then icon.texture:SetTexCoord(0.08,0.92,0.08,0.92)
            else icon.texture:SetTexCoord(0,1,0,1) end
            icon.keepAspect=cfg.keepAspect
        end
        local dark=item.applicationBlocked and not item.noResource and not item.queued
        local desaturated=not item.outOfRange and ((not dark and item.procBlocked)
            or (cfg.desaturate and item.fade and (not dark or item.gcdActive))) or false
        if icon.desaturated~=desaturated then icon.texture:SetDesaturated(desaturated); icon.desaturated=desaturated end
        local tint=item.outOfRange and 'range' or (dark and 'unusable' or (item.noResource and 'resource' or 'normal'))
        if icon.tint~=tint then
            if item.outOfRange then icon.texture:SetVertexColor(1,0.25,0.25,1)
            elseif dark then icon.texture:SetVertexColor(0.4,0.4,0.4,1)
            elseif item.noResource then icon.texture:SetVertexColor(0.3,0.55,1,1)
            else icon.texture:SetVertexColor(1,1,1,1) end
            icon.tint=tint
        end
        if icon.glowId~=item.id or icon.queueActive~=item.queued or icon.queueGray~=item.queueGray or icon.flashActive~=item.flash then
            icon.glowId=item.id; icon.flashActive=item.flash
            icon.queueActive=item.queued; icon.queueGray=item.queueGray; icon.queuePhase=0
            for _,edge in ipairs(icon.queueGlow) do
                if item.queued or item.flash then
                    if item.queueGray and not item.flash then edge:SetVertexColor(0.65,0.65,0.65,1) else edge:SetVertexColor(1,0.8,0.1,1) end
                    edge:SetAlpha(1); edge:Show()
                else edge:Hide() end
            end
        end
        local lib=E.Libs.CustomGlow
        if lib and lib.ButtonGlow_Start and lib.ButtonGlow_Stop then
            for _,edge in ipairs(icon.queueGlow) do edge:Hide() end
            local active=item.queued or item.flash
            local gray=item.queueGray and not item.flash
            local key=active and (tostring(item.id)..(gray and ':gray' or ':gold')..':'..w..':'..height) or nil
            if icon.buttonGlowLib and (icon.buttonGlowLib~=lib or icon.glowKey~=key) then
                icon.buttonGlowLib.ButtonGlow_Stop(icon); icon.buttonGlowLib=nil
            end
            if key and (icon.glowKey~=key or not icon.buttonGlowLib) then
                -- Same animated action-button effect used by WA; never restart on each tick.
                lib.ButtonGlow_Start(icon,gray and {0.65,0.65,0.65,1} or nil,nil,8)
                icon.buttonGlowLib=lib
            end
            icon.glowKey=key
        end
        local alpha=1
        if icon.alphaValue~=alpha then icon:SetAlpha(alpha); icon.alphaValue=alpha end
        if h.revision~=self.revision or icon.revision~=self.revision then
            self:TextStyle(icon.count,cfg.count); self:TextStyle(icon.duration,cfg.duration)
            self:TextStyle(icon.autoResource,cfg.count)
            -- TextStyle resets the point to the general count-text anchor.
            -- Force the selected TOP/BOTTOM/ICON resource point to be restored.
            -- Otherwise a profile switch or Apply() puts TOP text back below.
            icon.resourcePosition=nil
            icon.revision=self.revision
        end
        local value=resourceValues[i]
        if icon.resourcePosition~=value.position then
            icon.autoResource:ClearAllPoints()
            if value.position=='TOP' then
                icon.autoResource:SetPoint('BOTTOM',icon,'TOP',0,2)
            else
                icon.autoResource:SetPoint('TOP',icon,'BOTTOM',0,-2)
            end
            icon.resourcePosition=value.position
        end
        local count=tonumber(item.count) or item.multiplicity
        local countText=cfg.count.show and (item.countText or (count and count>1 and tostring(count))) or ''
        countText=countText or ''
        if item.resource and value.position~='ICON' then countText='' end
        if icon.countText~=countText then icon.count:SetText(countText); icon.countText=countText end
        local resourceText=value.text
        if icon.autoResourceValue~=resourceText then icon.autoResource:SetText(resourceText); icon.autoResourceValue=resourceText end
        if resourceText~='' and value.position~='ICON' then icon.autoResource:Show() else icon.autoResource:Hide() end
        local left=item.remaining
        local durationText=cfg.duration.show and left>0 and (left>=60 and string.format('%d:%02d',math.floor(left/60),math.floor(left%60)) or (left<3 and string.format('%.1f',left) or tostring(math.ceil(left)))) or ''
        if item.paused then durationText=cfg.duration.show and '—' or '' end
        if icon.durationText~=durationText then icon.duration:SetText(durationText); icon.durationText=durationText end
        if cfg.duration.swipe and left>0 and not item.paused then
            local total=math.max(item.total,left,0.01)
            local start=now-(total-left)
            -- Let the client animate the swipe. Repeated SetCooldown restarts it.
            -- Small DBT/frame-clock jitter is not an actual timer adjustment.
            if icon.cooldownId~=item.id or not icon.cooldownTotal or math.abs(icon.cooldownTotal-total)>0.01 or math.abs(icon.cooldownStart-start)>0.2 then
                icon.cooldown:SetCooldown(start,total)
                icon.cooldownId=item.id; icon.cooldownTotal=total; icon.cooldownStart=start
            end
            if not icon.cooldown:IsShown() then icon.cooldown:Show() end
        else
            if icon.cooldown:IsShown() then icon.cooldown:Hide() end
            icon.cooldownId=nil; icon.cooldownTotal=nil; icon.cooldownStart=nil
        end
        if not icon:IsShown() then icon:Show() end
    end
    for i=n+1,#h.icons do h.icons[i]:Hide() end
    h.revision=self.revision
    if not h.frame:IsShown() then h.frame:Show() end
end


-- Only the placement anchor changes. Spell, debuff, trigger and stacking
-- evaluation remain the original v0.8.5 implementation.
-- Do not gate the independent ability panel on target or nameplate visibility.
function T:EnsureMover()
    local name=self.stationary and 'PhoenixPanelStationary' or 'PhoenixPanelAbilities'
    if not self.moverAnchor then
        local parent=E.UIParent or UIParent
        local anchor=CreateFrame('Frame',name..'Anchor',parent)
        anchor:SetSize(160,36)
        anchor:SetPoint('CENTER',parent,'CENTER',0,self.stationary and -180 or -120)
        anchor:EnableMouse(false)
        self.moverAnchor=anchor
    end
    -- Keep this anchor registered in ElvUI's mover system independently of target.
    -- Recheck registration if the addon initialized before CreateMover became ready.
    if not self.moverRegistered and type(E.CreateMover)=='function' then
        local title=self.stationary and 'Стационарная панель' or 'Динамическая панель'
        local options=self.stationary and 'stationary' or 'abilities'
        E:CreateMover(self.moverAnchor,name..'Mover','PhoenixPanel — '..title,nil,nil,nil,
            'ALL,GENERAL,SOLO,PARTY,RAID,ARENA',nil,'phoenixPanel,'..options)
        self.moverRegistered=true
        -- Registering after the unlock screen opens must not leave the new mover hidden.
        if E.configMode and _G[name..'Mover'] then
            _G[name..'Mover']:Show()
        end
    end
    return self.moverAnchor
end

function T:Anchor()
    return self:EnsureMover()
end

function T:Tick()
    if self.shuttingDown or not A.db or not A.db.abilities then return end
    if self:IsProfileOff() then self:ResetCastStrip(); self:HideAll(); return end
    local cfg=self:Config()
    for _,h in pairs(self.holders) do h.touched=false end
    if not cfg.appearance.enabled then self:ResetCastStrip(); self.transitions={}; self:HideUnused(); return end
    if not self.auraCacheTime or GetTime()-self.auraCacheTime>=1 then self.auraCache={}; self.auraCacheTime=GetTime() end
    local items={}; local autoAdded=false; local hasReplacers=false
    local states={}; local hasMatchingVariant=false
    for _,p in ipairs(cfg.entries) do
        if p.enabled then
            local item=self:Evaluate(p,true)
            self:Transition(p,item)
            local nextSwing=self:NextSwingEntry(p)
            if nextSwing then
                hasReplacers=true
                if item.conditionPassed then hasMatchingVariant=true end
            end
            states[#states+1]={entry=p,item=item,nextSwing=nextSwing}
        end
    end
    if cfg.panelMode=='strip' then
        local anchor=self:Anchor()
        if not anchor or not anchor:IsShown() then self:ResetCastStrip(); self:HideUnused(); return end
        self:RenderCastStrip(anchor,self:BuildCastStrip(states))
        self:HideUnused()
        return
    end
    self:ResetCastStrip()
    for _,state in ipairs(states) do
        local p,item,nextSwing=state.entry,state.item,state.nextSwing
        -- Mutually exclusive aura conditions choose a variant, not a second attack slot.
        -- If no variant matches, conditions must still fall back instead of hiding everything.
        local unavailable=(not item.conditionPassed and not hasMatchingVariant)
            or (item.conditionPassed and (not item.visible or (not item.available and not item.queued)))
        local replace=cfg.autoAttack.enabled and cfg.autoAttack.replace and nextSwing and unavailable
        if replace then
            if not autoAdded then items[#items+1]=self:AutoItem(); autoAdded=true end
        elseif item.visible then
            item.readyFirst=p.readyFirst and item.priorityReady and item.conditionPassed
            item.priorityWaiting=p.kind=='spell' and p.readyFirst and item.priorityWaiting
                and item.conditionPassed and not item.queued and not nextSwing or false
            item.prioritySortTime=p.kind=='spell' and item.priorityCanCast
                and item.conditionPassed and not item.queued and not item.procBlocked
                and not item.ownPaused and item.ownRemaining or nil
            item.swingEnhancer=nextSwing and true or false
            items[#items+1]=item
        end
    end
    if cfg.autoAttack.enabled and not autoAdded and (not cfg.autoAttack.replace or not hasReplacers) then items[#items+1]=self:AutoItem() end
    local ordered={}; local added={}; local hasWaitingPriority=false
    local function add(item) ordered[#ordered+1]=item; added[item]=true end
    -- Autoattack and its enhancers retain absolute priority.
    for _,item in ipairs(items) do if item.autoAttack then add(item) end end
    for _,item in ipairs(items) do if item.swingEnhancer and not added[item] then add(item) end end
    for _,item in ipairs(items) do
        if not added[item] and item.readyFirst then add(item) end
        if item.priorityWaiting then hasWaitingPriority=true end
    end
    -- Normally preserve the saved relative order for non-priority entries.
    -- If a flagged spell cannot be ready by the CURRENT GCD's end, compare
    -- remaining OWN cooldowns of usable spells so an earlier-ready spell
    -- (even one without the flag) is not left behind that waiting spell.
    -- Non-spell items keep their original slots; ties retain saved order.
    local rest={}
    for _,item in ipairs(items) do if not added[item] then rest[#rest+1]=item end end
    if hasWaitingPriority then
        local slots,comparable={},{}
        for i,item in ipairs(rest) do
            if item.prioritySortTime then
                slots[#slots+1]=i
                comparable[#comparable+1]={item=item,remaining=item.prioritySortTime,index=#comparable+1}
            end
        end
        table.sort(comparable,function(a,b)
            if a.remaining~=b.remaining then return a.remaining<b.remaining end
            return a.index<b.index
        end)
        for i,slot in ipairs(slots) do rest[slot]=comparable[i].item end
    end
    for _,item in ipairs(rest) do add(item) end
    items=ordered
    local anchor=self:Anchor()
    if not anchor or not anchor:IsShown() then self:HideUnused(); return end
    self:Render(anchor,items); self:HideUnused()
end

function T:Apply()
    if not self.stationary then
        self:ResetCastStrip()
        self.stripConfirmed=nil
        self.stripRecentCasts=nil
    end
    self.transitions={}
    self:Validate(); self.revision=self.revision+1
    self.auraCache={}; self.auraCacheTime=nil
    if not self.stationary then self:RefreshVisualKeys() end
    if self.initialized then self:Tick() end
end

function T:Initialize()
    if self.initialized then return end
    self.initialized=true
    self:EnsureMover()
    local driver=CreateFrame('Frame'); self.driver=driver
    for _,event in ipairs({'PLAYER_TARGET_CHANGED','PLAYER_FOCUS_CHANGED','UNIT_AURA','PLAYER_ENTERING_WORLD','PLAYER_LOGOUT'}) do
        driver:RegisterEvent(event)
    end
    if not self.stationary then
        for _,event in ipairs({'COMBAT_LOG_EVENT_UNFILTERED','UNIT_ATTACK_SPEED','PLAYER_ENTER_COMBAT','PLAYER_LEAVE_COMBAT','PLAYER_EQUIPMENT_CHANGED','UNIT_SPELLCAST_START','UNIT_SPELLCAST_SUCCEEDED','UNIT_SPELLCAST_FAILED','UNIT_SPELLCAST_INTERRUPTED'}) do
            driver:RegisterEvent(event)
        end
    end
    driver:SetScript('OnEvent',function(_,event,...)
        if not self.stationary then
            self:AutoEvent(event,...)
            if event=='UNIT_SPELLCAST_SUCCEEDED' or event=='COMBAT_LOG_EVENT_UNFILTERED' then
                self:CastStripEvent(event,...)
            elseif event=='PLAYER_LOGOUT' or event=='PLAYER_ENTERING_WORLD' then
                self:ResetCastStrip()
                self.stripRecentCasts=nil
            end
        end
        if event=='PLAYER_LOGOUT' then self.shuttingDown=true; self:HideAll()
        elseif event=='UNIT_AURA' or event=='PLAYER_TARGET_CHANGED' or event=='PLAYER_FOCUS_CHANGED' or event=='PLAYER_ENTERING_WORLD' then self.auraCacheTime=nil end
    end)
    local elapsed=0
    driver:SetScript('OnUpdate',function(_,dt)
        elapsed=elapsed+dt
        if elapsed<0.1 then return end
        elapsed=0; self:Tick()
    end)
end

-- Independent ability presets inside the *current* ElvUI profile.
-- Existing v0.10.3 abilities become "Основной" without resetting any entry.
local A=PhoenixPanel
local T=A.Abilities
local OFF='__OFF__'
local PRIMARY='Основной'

local function trim(s)
    if type(s)~='string' then return '' end
    return (s:gsub('^%s+',''):gsub('%s+$',''))
end

local function validName(name)
    name=trim(name)
    if name=='' then return nil,'Введите название профиля.' end
    if #name>96 then return nil,'Название профиля слишком длинное.' end
    if name==OFF or name=='Выключить' then return nil,'Это название зарезервировано.' end
    return name
end

-- Must run after A.Fill but before the active ability configuration is used.
function T:PrepareProfiles()
    if not A.db then return end
    local db=A.db
    local state=db.abilityProfiles
    if type(state)~='table' or type(state.presets)~='table' then
        state={selected=PRIMARY,last=PRIMARY,presets={[PRIMARY]=db.abilities}}
        db.abilityProfiles=state
    end
    local fallback
    for name,preset in pairs(state.presets) do
        if type(preset)=='table' then fallback=name; break end
    end
    if not fallback then
        -- Incomplete saved state: migrate the still-present active configuration.
        state.presets[PRIMARY]=db.abilities
        fallback=PRIMARY
    end
    if type(state.selected)~='string' then state.selected=fallback end
    if state.selected~=OFF and type(state.presets[state.selected])~='table' then state.selected=fallback end
    if type(state.last)~='string' or type(state.presets[state.last])~='table' then state.last=fallback end
    -- A.Fill() only normalizes db.abilities at ElvUI profile binding.
    -- Ability presets are separate saved tables; they may be missing nested
    -- text/appearance fields (e.g. appearance.count or .duration) after an
    -- older build or an interrupted migration. Fill only missing defaults
    -- in EACH preset, preserving all saved spells, triggers and preferences.
    for _,preset in pairs(state.presets) do
        if type(preset)=='table' then A.Fill(preset,A.defaults.abilities) end
    end
    local active=state.selected~=OFF and state.selected or state.last
    db.abilities=state.presets[active]
    return state
end

function T:Profiles()
    return self:PrepareProfiles()
end

function T:IsProfileOff()
    local state=A.db and A.db.abilityProfiles
    return type(state)=='table' and state.selected==OFF
end

function T:ProfileOptions()
    local state=self:Profiles()
    local result={[OFF]='Выключить'}
    for name,preset in pairs(state.presets) do
        if type(preset)=='table' then result[name]=name end
    end
    return result
end

local function refresh()
    T:Apply()  -- instantly refresh shown icons and all active calculations
    if A.RefreshAbilityOptions then A.RefreshAbilityOptions() end
    -- Do not call AceConfigRegistry:NotifyChange here.  When an AceConfig
    -- button is being processed, ElvUI's AceConfigDialog reopens the panel
    -- itself AFTER the callback returns.  A second, nested refresh can
    -- invalidate the current widget while its action is still executing.
end

function T:SelectProfile(name)
    local state=self:Profiles()
    if name~=OFF and type(state.presets[name])~='table' then return false end
    -- The selected profile is a live table: edits are saved immediately.
    if state.selected~=OFF then state.presets[state.selected]=A.db.abilities end
    state.selected=name
    if name~=OFF then
        state.last=name
        A.db.abilities=state.presets[name]
    end
    refresh()
    return true
end

function T:CreateProfile(rawName,duplicate)
    local state=self:Profiles()
    -- A copy button should work without entering a name first. Keep manual
    -- naming fully supported; choose a unique name only for an empty field.
    if duplicate and trim(rawName)=='' then
        local sourceName=state.selected~=OFF and state.selected or state.last or PRIMARY
        local stem=sourceName..' (копия)'
        if #stem>90 then stem='Копия профиля' end
        rawName=stem
        local i=2
        while state.presets[rawName] do
            rawName=stem..' '..i
            i=i+1
        end
    end
    local name,err=validName(rawName)
    if not name then return false,err end
    if state.presets[name]~=nil then return false,'Профиль с таким названием уже существует.' end
    -- Include appearance/autoattack/flashes as well as entries in each preset.
    local source=duplicate and A.db.abilities or A.defaults.abilities
    local preset=self.Copy(source)
    A.Fill(preset,A.defaults.abilities)
    state.presets[name]=preset
    -- Make the new profile active directly. Calling SelectProfile() here
    -- re-enters PrepareProfiles() before the UI handler has finished and
    -- can cause a second AceConfig refresh from inside its first callback.
    state.selected=name
    state.last=name
    A.db.abilities=preset
    -- Verify that creation is visible through the same profile storage
    -- used by the live panel; do not report success for an absent preset.
    if state.presets[name]~=A.db.abilities then
        return false,'Не удалось активировать новый профиль.'
    end
    refresh()
    return true,'Создан профиль «'..name..'».'
end

function T:DeleteProfile(name)
    local state=self:Profiles()
    if type(state.presets[name])~='table' then return false,'Профиль не найден.' end
    local count=0
    for _,p in pairs(state.presets) do if type(p)=='table' then count=count+1 end end
    if count<=1 then return false,'Нельзя удалить последний профиль.' end
    -- Keep an existing preset active before removing the selected one.
    if state.selected==name or state.last==name then
        local nextName
        if name~=PRIMARY and type(state.presets[PRIMARY])=='table' then nextName=PRIMARY end
        if not nextName then
            for key,p in pairs(state.presets) do if key~=name and type(p)=='table' then nextName=key; break end end
        end
        state.selected=nextName
        state.last=nextName
        A.db.abilities=state.presets[nextName]
    end
    state.presets[name]=nil
    refresh()
    return true,'Профиль «'..name..'» удалён.'
end

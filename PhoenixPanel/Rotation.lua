local A=PhoenixPanel
local T=A.Abilities
local baseCondition=T.Condition
local baseEvaluate=T.Evaluate

-- The two 8-yard hostile item checks are also used by the supplied WA's
-- LibRangeCheck. Unknown answers must never be treated as outside range.
function T:Enemies8()
    local now=GetTime()
    if self.enemySample and now-self.enemySample.time<0.2 then return self.enemySample end
    local sample={time=now,count=0,unknown=0}; local seen={}
    local function add(unit)
        if not unit or not UnitExists(unit) then return end
        local guid=UnitGUID(unit)
        if not guid or seen[guid] then return end
        seen[guid]=true
        if not UnitCanAttack or not (UnitCanAttack('player',unit)==true or UnitCanAttack('player',unit)==1) then return end
        if UnitIsDeadOrGhost and (UnitIsDeadOrGhost(unit)==true or UnitIsDeadOrGhost(unit)==1) then return end
        local answer
        if IsItemInRange then
            answer=IsItemInRange(34368,unit)
            if answer==nil then answer=IsItemInRange(33278,unit) end
        end
        if answer==true or answer==1 then sample.count=sample.count+1
        elseif answer~=false and answer~=0 then sample.unknown=sample.unknown+1 end
    end
    add('target')
    local np=ElvUI[1]:GetModule('NamePlates',true)
    for plate in pairs(np and np.Plates or {}) do if plate:IsShown() then add(plate.unit) end end
    if C_NamePlate and C_NamePlate.GetNamePlates then
        for _,plate in pairs(C_NamePlate.GetNamePlates() or {}) do
            if plate:IsShown() then add(plate.namePlateUnitToken or plate.unit) end
        end
    end
    self.enemySample=sample
    return sample
end

function T:TargetCountCondition(group)
    if not group.targetCondition then return true end
    local s=self:Enemies8(); local limit=tonumber(group.targetValue) or 2
    local op=group.targetOp or 'ge'
    if op=='ge' then
        if s.count>=limit then return true end
        if s.unknown>0 then return false,'Дальность части целей неизвестна.',true end
        return false,'Недостаточно целей в пределах 8 ярдов.'
    elseif op=='le' then
        if s.count>limit then return false,'Слишком много целей в пределах 8 ярдов.' end
        return s.unknown==0,s.unknown>0 and 'Дальность части целей неизвестна.' or nil,s.unknown>0
    end
    return s.count==limit and s.unknown==0,'Количество целей не совпадает или неизвестно.',s.unknown>0 and s.count<=limit
end

local triggerFields={'condition','conditionResource','conditionOp','conditionValue','conditionPercent',
    'auraCondition','auraConditionKind','auraConditionUnit','auraConditionMode','auraConditionId','auraConsumption',
    'targetCondition','targetOp','targetValue'}
local function active(g) return g.condition or g.auraCondition or g.targetCondition end
function T:NewTrigger()
    return {enabled=true,conditionResource='current',conditionOp='ge',conditionValue=0,
        auraConditionKind='buff',auraConditionUnit='player',auraConditionMode='present',
        targetOp='ge',targetValue=2}
end
function T:PrepareTriggers(p)
    if type(p.triggers)~='table' then
        local primary=self:NewTrigger()
        for _,key in ipairs(triggerFields) do if p[key]~=nil then primary[key]=p[key] end end
        local others={}
        for _,g in ipairs(type(p.alternatives)=='table' and p.alternatives or {}) do
            if type(g)=='table' and active(g) then others[#others+1]=self.Copy(g) end
        end
        p.triggers={}
        if active(primary) or #others==0 then p.triggers[1]=primary end
        for _,g in ipairs(others) do g.enabled=true; p.triggers[#p.triggers+1]=g end
        p.triggerMode='any'; p.selectedTrigger=1
        p.invertTriggers=p.invertConditions or false
    end
    -- 0.8.0's spell-specific presets are intentionally discarded, not converted.
    p.meleeMode=nil; p.aoeIgnoreAura=nil; p.alternatives=nil; p.invertConditions=nil
    if #p.triggers==0 then p.triggers[1]=self:NewTrigger() end
    if p.triggerMode~='all' and p.triggerMode~='one' then p.triggerMode='any' end
    local selected=tonumber(p.selectedTrigger) or 1
    if selected~=selected then selected=1 end
    p.selectedTrigger=math.max(1,math.min(#p.triggers,math.floor(selected)))
    return p.triggers
end
function T:TriggerState(g)
    if not g.enabled then return false,'Триггер выключен.' end
    local ok,reason=baseCondition(self,g)
    local unknown
    if ok then ok,reason,unknown=self:TargetCountCondition(g) end
    if g.invert then
        if unknown then return false,'Дальность части целей неизвестна.',true end
        ok=not ok
    end
    return ok,reason,unknown
end
local function hasConsumableAura(g)
    return g and not g.invert and g.auraCondition and g.auraConditionMode~='absent' and g.auraConditionId
end

function T:AuraConsumptionMode(g)
    if not g.enabled or not hasConsumableAura(g) then return end
    if g.auraConsumption=='once' or g.auraConsumption=='stack' then return g.auraConsumption end
end

local function triggerDiagnostics(self,g)
    if not g.enabled then return 'Триггер выключен.' end
    local lines={}
    local function add(label,ok,reason,unknown)
        local status=unknown and 'неизвестно' or (ok and 'выполнено' or 'не выполнено')
        lines[#lines+1]=label..' — '..status..(reason and (' ('..reason..')') or '')
    end
    if g.auraCondition then
        add('Баф / дебаф',baseCondition(self,setmetatable({condition=false},{__index=g})))
    end
    if g.condition then
        add('Ресурс',baseCondition(self,setmetatable({auraCondition=false},{__index=g})))
    end
    if g.targetCondition then
        local ok,reason,unknown=self:TargetCountCondition(g)
        add('Количество целей',ok,not ok and reason or nil,unknown)
    end
    if #lines==0 then lines[1]='Нет условий.' end
    local ok,_,unknown=self:TriggerState(g)
    add(g.invert and 'Итог с инверсией' or 'Итог',ok,nil,unknown)
    return table.concat(lines,'\n')
end
function T:Condition(p)
    local triggers=self:PrepareTriggers(p)
    local mode=p.triggerMode
    local ok=mode=='all'; local uncertain=false; local used=0;local reason
    if mode=='one' then
        ok,reason,uncertain=self:TriggerState(triggers[p.selectedTrigger])
        used=1
    else
        for _,g in ipairs(triggers) do
            if g.enabled then
                used=used+1
                local passed,why,unknown=self:TriggerState(g)
                reason=why or reason
                if mode=='all' then
                    if not passed and not unknown then ok=false;uncertain=false;break end
                    if unknown then uncertain=true end
                else
                    if passed then ok=true;uncertain=false;break end
                    if unknown then uncertain=true end
                end
            end
        end
    end
    if used==0 then ok=false end
    if uncertain then return false,'Дальность части целей неизвестна.' end
    if p.invertTriggers then ok=not ok end
    return ok,ok and nil or (reason or 'Условия активации триггеров не выполнены.')
end

function T:Evaluate(p,inspect,noReplacement)
    local item=baseEvaluate(self,p,true)
    if p.kind=='spell' and self:NextSwingEntry(p) and not item.procBlocked then
        local swing=self.swing
        item.gcd=nil; item.total=0; item.remaining=0
        if swing then item.total=swing.duration; item.remaining=math.max(0,swing.finish-GetTime()) end
    end
    if p.kind=='spell' and p.replacementEnabled and not noReplacement and item.noResource and item.conditionPassed then
        item.visible=true
        local id=tonumber(p.replacementId)
        if id and id~=p.spellId then
            local replacement=self:Find(id,'spell')
            if replacement then
                replacement.uid=p.uid; replacement.checkRange=p.checkRange
                local r=self:Evaluate(replacement,true,true)
                if r.available and not r.applicationBlocked and not r.queued then
                    r.id=item.id; r.replacement=true; r.originalSpellId=p.spellId
                    r.priorityReady=false; r.visible=true
                    item=r
                end
            end
        end
    end
    if p.showResource and p.kind~='resource' then
        local r=self:Resource(p.displayResource or 'current','player')
        item.resourceText=r.valid and (tostring(r.value)..'/'..tostring(r.max)) or '—'
    end
    if not inspect and not item.visible then return end
    return item
end
local transition=T.Transition
function T:Transition(p,item)
    if item.replacement then
        self.transitions=self.transitions or {}; self.transitions[p.uid]=nil
        return
    end
    return transition(self,p,item)
end

local function foreground(h)
    if not h.foreground then
        h.frame:SetFrameStrata('TOOLTIP'); h.frame:SetFrameLevel(100); h.frame:SetAlpha(1)
        if h.frame.SetIgnoreParentAlpha then h.frame:SetIgnoreParentAlpha(true) end
        h.foreground=true
    end
    for _,icon in ipairs(h.icons) do
        if not icon.foreground then
            icon:SetAlpha(1); icon.alphaValue=1
            if icon.SetIgnoreParentAlpha then icon:SetIgnoreParentAlpha(true) end
            if icon.texture then icon.texture:SetAlpha(1) end
            icon.foreground=true
        end
    end
end
for _,module in ipairs({T,A.DBM}) do
    local original=module.Render
    module.Render=function(self,plate,items)
        original(self,plate,items)
        if self.holders[plate] then foreground(self.holders[plate]) end
    end
end

local validate=T.Validate
local function numeric(v,default,lo,hi)
    local n=tonumber(v)
    if not n or n~=n then n=default end
    return math.max(lo,math.min(hi,n))
end
function T:Validate()
    validate(self); self.enemySample=nil
    for _,p in ipairs(self:Config().entries) do
        if not self.autoResources[p.displayResource] then p.displayResource='current' end
        p.replacementId=tonumber(p.replacementId)
        local source=self:PrepareTriggers(p);local groups={}
        for i=1,math.min(20,#source) do
            local g=source[i]
            if type(g)=='table' then
                if g.enabled==nil then g.enabled=true end
                g.conditionResource=self.resources[g.conditionResource] and g.conditionResource or 'current'
                g.conditionValue=numeric(g.conditionValue,0,-1000000000,1000000000)
                if g.conditionOp~='le' and g.conditionOp~='eq' then g.conditionOp='ge' end
                g.auraConditionUnit=g.auraConditionUnit=='target' and 'target' or 'player'
                g.auraConditionKind=g.auraConditionKind=='debuff' and 'debuff' or 'buff'
                g.auraConditionMode=g.auraConditionMode=='absent' and 'absent' or 'present'
                g.auraConditionId=tonumber(g.auraConditionId)
                if g.auraConsumption~='once' and g.auraConsumption~='stack' then g.auraConsumption=nil end
                g.targetValue=math.floor(numeric(g.targetValue,2,0,50))
                if g.targetOp~='le' and g.targetOp~='eq' then g.targetOp='ge' end
                groups[#groups+1]=g
            end
        end
        p.triggers=groups;self:PrepareTriggers(p)
    end
end

local initialize=T.Initialize
function T:Initialize()
    if GetItemInfo then GetItemInfo(34368); GetItemInfo(33278) end
    return initialize(self)
end

function T:AddRotationOptions(args,getDraft,triggerArgs)
    triggerArgs=triggerArgs or args
    local function p() return getDraft() end
    local function hidden() return not p() or p().kind~='spell' end
    args.showResource={type='toggle',name='Показывать ресурс под иконкой',order=7.3,hidden=hidden}
    args.displayResource={type='select',name='Ресурс под иконкой',order=7.4,values=self.autoResources,hidden=function() return hidden() or not p().showResource end,
        get=function() return p() and p().displayResource or 'current' end}
    args.replacementEnabled={type='toggle',name='Замена при нехватке ресурса',order=7.5,hidden=hidden}
    args.replacementId={type='input',name='ID способности замены',order=7.6,hidden=function() return hidden() or not p().replacementEnabled end,
        get=function() return p() and p().replacementId and tostring(p().replacementId) or '' end,
        validate=function(_,v) local id=tonumber(v); return id and id>0 and id==math.floor(id) and id~=p().spellId and GetSpellInfo(id) and true or 'Введите ID другой существующей способности.' end,
        set=function(_,v) p().replacementId=tonumber(v) end}

    for _,key in ipairs({'condition','conditionResource','conditionOp','conditionValue','conditionPercent',
        'auraCondition','auraConditionMode','auraConditionKind','auraConditionUnit','auraConditionId','auraName'}) do args[key]=nil end
    local currentDraft,editorIndex
    local function list()
        local draft=p()
        if draft~=currentDraft then
            currentDraft=draft
            editorIndex=1
        end
        if not draft then return end
        local triggers=T:PrepareTriggers(draft)
        editorIndex=math.max(1,math.min(#triggers,editorIndex or 1))
        return triggers
    end
    local function triggerNames()
        local values={}
        for i,trigger in ipairs(list() or {}) do
            values[i]='Триггер '..i..(trigger.enabled and '' or ' (выкл.)')
        end
        return values
    end

    triggerArgs.triggerMode={type='select',name='Правило активации',order=8,width='normal',
        values={any='Любой включённый (ИЛИ)',all='Все включённые (И)',one='Один выбранный'},
        get=function() list(); return p() and p().triggerMode or 'any' end,
        set=function(_,value) if p() then p().triggerMode=value end end}
    triggerArgs.selectedTrigger={type='select',name='Активный триггер',order=8.1,width='normal',
        hidden=function() list(); return not p() or p().triggerMode~='one' end,values=triggerNames,
        get=function() list(); return p() and p().selectedTrigger or 1 end,
        set=function(_,value) if p() then p().selectedTrigger=value end end}
    triggerArgs.legacyInversion={type='description',order=8.2,width='full',
        name='Сохранённая инверсия правила применяется к общему результату.',
        hidden=function() list(); return not p() or not p().invertTriggers end}
    triggerArgs.triggerInfo={type='description',order=8.3,width='full',
        name='Внутри триггера все включённые условия должны выполняться. Триггер без условий срабатывает всегда, если он включён.'}
    triggerArgs.targetsNow={type='description',order=8.4,width='full',
        hidden=function()
            local triggers=list()
            return not triggers or not triggers[editorIndex].targetCondition
        end,
        name=function()
            local s=T:Enemies8()
            return 'Врагов в 8 ярдах: '..s.count..'. Неизвестная дальность: '..s.unknown..'.'
        end}

    triggerArgs.triggers={type='group',name='Редактор триггеров',order=9,guiInline=true,args={}}
    local editors=triggerArgs.triggers.args
    editors.current={type='select',name='Редактируемый триггер',order=1,width='normal',values=triggerNames,
        get=function() list(); return editorIndex or 1 end,
        set=function(_,value) list(); editorIndex=value end}
    editors.add={type='execute',name='Добавить',order=2,width='half',
        disabled=function() return not list() or #list()>=20 end,func=function()
            local triggers=list()
            if triggers and #triggers<20 then
                local trigger=T:NewTrigger()
                trigger.enabled=false
                triggers[#triggers+1]=trigger
                editorIndex=#triggers
            end
        end}
    editors.recheck={type='execute',name='Проверить',order=3,width='half',func=function()
        T.auraCacheTime=nil
        T.enemySample=nil
    end}

    for i=1,20 do
        local index=i
        local function g() local v=list(); return v and v[index] end
        local function off(key) return function() return not g() or not g()[key] end end
        local function toggle(name,order,desc)
            return {type='toggle',name=name,desc=desc,order=order,width='full'}
        end
        local function consumptionToggle(mode,name,order,desc)
            return {
                type='toggle',name=name,order=order,desc=desc,
                hidden=function() return not hasConsumableAura(g()) end,
                get=function() local trigger=g(); return trigger and trigger.auraConsumption==mode end,
                set=function(_,enabled)
                    local trigger=g()
                    if not hasConsumableAura(trigger) then return end
                    if enabled then
                        trigger.auraConsumption=mode
                    elseif trigger.auraConsumption==mode then
                        trigger.auraConsumption=nil
                    end
                end}
        end
        editors['trigger'..i]={type='group',name='Триггер '..i,order=i+3,guiInline=true,
            hidden=function() local trigger=g(); return not trigger or editorIndex~=index end,
            get=function(info) return g() and g()[info[#info]] end,
            set=function(info,v) if g() then g()[info[#info]]=v; T.auraCacheTime=nil end end,args={
                enabled=toggle('Включить триггер',1),
                copy={type='execute',name='Копировать',order=2,width='normal',
                    disabled=function() return not list() or #list()>=20 end,func=function()
                        local triggers=list()
                        if triggers and #triggers<20 then
                            triggers[#triggers+1]=T.Copy(triggers[index])
                            editorIndex=#triggers
                        end
                    end},
                remove={type='execute',name='Удалить',order=3,width='normal',
                    disabled=function() return not list() or #list()<=1 end,func=function()
                        local triggers=list()
                        if not triggers or #triggers<=1 then return end
                        local selected=p().selectedTrigger or 1
                        table.remove(triggers,index)
                        if selected>index then selected=selected-1 end
                        p().selectedTrigger=math.max(1,math.min(#triggers,selected))
                        editorIndex=math.min(index,#triggers)
                    end},
                legacyInversion={type='description',order=4,width='full',
                    name='Сохранённая инверсия этого триггера применяется к его результату.',hidden=off('invert')},

                auraCondition=toggle('Баф / дебаф',10,'Проверить наличие или отсутствие эффекта по ID.'),
                auraConditionKind={type='select',name='Тип эффекта',order=11,values={buff='Баф',debuff='Дебаф'},hidden=off('auraCondition')},
                auraConditionUnit={type='select',name='На ком',order=12,values={player='Игрок',target='Цель'},hidden=off('auraCondition')},
                auraConditionMode={type='select',name='Наличие',order=13,values={present='Есть',absent='Нет'},hidden=off('auraCondition')},
                auraConditionId={type='input',name='ID эффекта',order=14,hidden=off('auraCondition'),get=function() return g() and g().auraConditionId and tostring(g().auraConditionId) or '' end,
                    validate=function(_,v) local id=tonumber(v); return id and id>0 and id==math.floor(id) and GetSpellInfo(id) and true or 'Введите ID эффекта.' end,
                    set=function(_,v) g().auraConditionId=tonumber(v); T.auraCacheTime=nil end},
                auraName={type='description',order=15,width='full',hidden=off('auraCondition'),name=function() return g() and g().auraConditionId and (GetSpellInfo(g().auraConditionId) or 'Эффект не найден.') or 'Укажите ID эффекта.' end},

                auraOnce=consumptionToggle('once','Одно применение',16,
                    'В прогнозе полосы одно применение расходует эффект целиком.'),
                auraByStacks=consumptionToggle('stack','По стакам',17,
                    'В прогнозе полосы одно применение расходует один стак. Эффект без стаков даёт одно применение.'),

                condition=toggle('Ресурс',20,'Сравнить текущее количество ресурса с заданным значением.'),
                conditionResource={type='select',name='Тип ресурса',order=21,values=T.resources,hidden=off('condition')},
                conditionOp={type='select',name='Сравнение',order=22,values={ge='Не меньше',le='Не больше',eq='Равно'},hidden=off('condition')},
                conditionValue={type='input',name='Значение',order=23,hidden=off('condition'),get=function() return tostring(g() and g().conditionValue or 0) end,
                    validate=function(_,v) local n=tonumber(v); return n and n==n and math.abs(n)<=1000000000 and true or 'Введите число.' end,
                    set=function(_,v) g().conditionValue=tonumber(v) end},
                conditionPercent={type='toggle',name='В процентах',order=24,hidden=off('condition')},

                targetCondition=toggle('Враги в 8 ярдах',30,'Проверить количество ближайших врагов.'),
                targetOp={type='select',name='Сравнение',order=31,values={ge='Не меньше',le='Не больше',eq='Равно'},hidden=off('targetCondition')},
                targetValue={type='range',name='Количество врагов',order=32,min=0,max=50,step=1,hidden=off('targetCondition')},

                diagnosticsTitle={type='header',name='Результат проверки',order=40},
                diagnostics={type='description',order=41,width='full',
                    name=function() local trigger=g(); return trigger and triggerDiagnostics(T,trigger) or '' end}
            }}
    end
end

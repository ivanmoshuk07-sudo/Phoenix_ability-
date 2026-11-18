local A=PhoenixPanel
local E=ElvUI[1]
local T=A.Abilities

-- Only this profile-name input needs live typing. AceConfig's regular input
-- commits on Enter; custom textChanged inside an option is INVALID in AceConfig.
-- Use the supported dialogControl API to listen to its *own* edit box, without
-- patching ElvUI's widgets or guessing their global names.
local profileNameTyping
local PROFILE_NAME_CONTROL='PhoenixPanelProfileNameInput'
local function RegisterProfileNameControl()
    local gui=E.Libs and E.Libs.AceGUI
    if not gui or gui:GetWidgetVersion(PROFILE_NAME_CONTROL) then return end
    gui:RegisterWidgetType(PROFILE_NAME_CONTROL,function()
        -- Reuse the original ElvUI input behavior (Enter, focus, OK button).
        local widget=gui:Create('EditBox-ElvUI')
        widget.type=PROFILE_NAME_CONTROL
        widget.editbox:HookScript('OnTextChanged',function(editbox,isUserInput)
            -- Do not treat AceConfig's SetText during a redraw as user typing.
            if isUserInput and editbox:HasFocus() and profileNameTyping then
                profileNameTyping(editbox:GetText())
            end
        end)
        return widget
    end,1)
end

-- Rotation.lua (retained unmodified) makes all its renders TOOLTIP/100.
-- Override only the abilities presentation layer after its original renderer.
-- The DBM frame and every original ability/trigger calculation remain intact.
local previousRender=T.Render
function T:Render(plate,items)
    previousRender(self,plate,items)
    local h=self.holders[plate]
    if h and not h.lowLayer then
        h.frame:SetFrameStrata('LOW')
        h.frame:SetFrameLevel(5)
        h.lowLayer=true
    end
end

local kind,spellText,resource='spell','','current'
local draft,editing,status
local function cfg() return A.db.abilities end
local function selectOption(name,order,values) return {type='select',name=name,order=order,values=values} end
local function toggle(name,order) return {type='toggle',name=name,order=order} end
local function locate(uid)
    for index,p in ipairs(cfg().entries) do if p.uid==uid then return index,p end end
end

function A:InsertAbilityOptions(parent)
    -- Editing a draft cannot leak into a different ElvUI profile.
    local profile=A.db
    local root,list
    local newProfileName=''
    local profileMessage=''
    -- Only the focused profile-name widget updates this variable while typing.
    -- The normal AceConfig 'set' callback still handles Enter/OK.
    profileNameTyping=function(value) newProfileName=value end
    RegisterProfileNameControl()
    local function isOff() return T:IsProfileOff() end
    local function stripMode() return cfg().panelMode=='strip' end
    local function reset() draft=nil; editing=nil; status=nil end
    local function rebuild()
        if profile~=A.db then profile=A.db; reset() end
        local args={}
        for number,p in ipairs(cfg().entries) do
            local uid=p.uid
            local name=p.name or (p.spellId and GetSpellInfo(p.spellId)) or 'Без названия'
            local label=number..'. '..name..' — '..T.kinds[p.kind]
            args['entry'..uid]={type='group',name=label,order=number,guiInline=true,args={
                enabled={type='toggle',name='Отслеживать',order=1,
                    image=function() return (p.spellId and select(3,GetSpellInfo(p.spellId))) or p.icon or 'Interface\\Icons\\INV_Misc_QuestionMark' end,
                    arg={spellId=p.spellId,text=name},dialogControl=p.kind~='resource' and A.DBM.spellWidgetRegistered and 'PhoenixPanelSpellCheck' or nil,
                    desc=p.kind=='resource' and 'Индикатор выбранного ресурса.' or ('Игровое описание: '..tostring(p.spellId)),
                    get=function() local _,entry=locate(uid); return entry and entry.enabled end,
                    set=function(info,value) local _,entry=locate(uid); if entry then entry.enabled=value; T:Apply() end end},
                edit={type='execute',name='Изменить',order=2,func=function()
                    local _,entry=locate(uid)
                    if entry then draft=T.Copy(entry); editing=uid; kind=entry.kind; spellText=tostring(entry.spellId or ''); resource=entry.resource or 'current'; status='Редактирование: '..name end
                end},
                up={type='execute',name='Выше',order=3,disabled=function() return locate(uid)==1 end,func=function() local index=locate(uid); if index then T:Move(index,-1); rebuild() end end},
                down={type='execute',name='Ниже',order=4,disabled=function() return locate(uid)==#cfg().entries end,func=function() local index=locate(uid); if index then T:Move(index,1); rebuild() end end},
                delete={type='execute',name='Удалить',order=5,confirm=true,func=function()
                    local index=locate(uid); if index then T:Delete(index); if editing==uid then reset() end; rebuild() end
                end}
            }}
        end
        if not next(args) then args.empty={type='description',name='Список пока пуст. Найдите способность или выберите ресурс выше и добавьте его.',order=1} end
        list.args=args
    end
    root={type='group',name='Динамическая панель',order=6,childGroups='tab',args={
        appearance=self:AbilityAppearanceOptions(T,
            'Иконки следуют настройкам приоритета. У скрытых записей место освобождается. Панель перемещается через ElvUI → Перенос рамок.',isOff),
        tracking={type='group',name='Выбор способностей',order=2,disabled=isOff,args={
            kind={type='select',name='Тип отслеживания',order=1,values=T.kinds,get=function() return kind end,set=function(info,value) kind=value; reset() end},
            spellId={type='input',name='ID способности',order=2,hidden=function() return kind=='resource' end,get=function() return spellText end,set=function(info,value) spellText=value; reset() end},
            resource={type='select',name='Ресурс',order=2,values=T.resources,hidden=function() return kind~='resource' end,get=function() return resource end,set=function(info,value) resource=value; reset() end},
            find={type='execute',name='Найти',order=3,func=function()
                local found,err=T:Find(spellText,kind,resource)
                draft=found; editing=nil; status=found and ('Найдено: '..found.name) or err
            end},
            status={type='description',order=4,name=function() return status or 'Выберите тип, введите ID и нажмите «Найти». Для ресурса ID не требуется.' end},
            settings={type='group',name='Настройки найденной записи',order=5,guiInline=true,hidden=function() return not draft end,
                get=function(info) return draft and draft[info[#info]] end,set=function(info,value) if draft then
                    local key=info[#info]; draft[key]=value
                    if key=='nextSwing' then draft.nextSwingOverride=value end
                end end,args={
                    found={type='description',order=1,name=function() return draft and draft.name or '' end,image=function() return draft and draft.icon or 'Interface\\Icons\\INV_Misc_QuestionMark' end,imageWidth=32,imageHeight=32},
                    mode=selectOption('Показывать',2,{always='Всегда',available='Когда доступно / эффект активен'}),
                    unit={type='select',name='На ком отслеживать',order=3,values=T.units,hidden=function() return not draft or draft.kind=='spell' or (draft.kind=='resource' and draft.resource=='targethealth') end},
                    showGCD={type='toggle',name='Показывать ГКД',order=4,hidden=function() return not draft or draft.kind~='spell' end},
                    nextSwing={type='toggle',name='Заменяет / усиливает следующую автоатаку',order=5.1,hidden=function() return not draft or draft.kind=='resource' end},
                    readyFirst={type='toggle',name='Переносить в начало при готовности',order=5.2,desc='Переносит способность в очередь после автоатаки и её усилителей. Для заклинания перенос возможен уже во время ГКД или когда до конца собственного КД осталось не больше одного ГКД (обычно 1,5 сек), но только при достаточном ресурсе и доступности применения. Для бафа/дебафа перенос выполняется при отсутствии эффекта или когда он закончится к завершению текущего ГКД (при доступности заклинания). Сам список не переставляется. В полосе применений порядок определяет числовой приоритет.',hidden=function() return not draft or draft.kind=='resource' end},
                    castPriority={type='range',name='Приоритет в полосе применений',order=5.3,min=1,max=10,step=1,
                        desc='1 — самый высокий приоритет. При одинаковом приоритете раньше идёт запись выше в списке.',
                        hidden=function() return not draft or not stripMode() or draft.kind=='resource' or T:NextSwingEntry(draft) end,
                        get=function() return draft and T:CastPriority(draft) or 5 end},
                    checkRange={type='toggle',name='Учитывать дальность до цели',order=5,hidden=function() return not draft or draft.kind~='spell' end},
                    onlyMine={type='toggle',name='Только мои ауры',order=6,hidden=function() return not draft or (draft.kind~='buff' and draft.kind~='debuff') end},
                    resourcePercent={type='toggle',name='Ресурс в процентах',order=7,hidden=function() return not draft or draft.kind~='resource' end},
                    condition=toggle('Условие показа по ресурсу игрока',8),
                    conditionResource={type='select',name='Тип ресурса условия',values=T.resources,order=9,hidden=function() return not draft or not draft.condition end},
                    conditionOp={type='select',name='Сравнение',values={ge='Не меньше',le='Не больше',eq='Равно'},order=10,hidden=function() return not draft or not draft.condition end},
                    conditionValue={type='input',name='Значение ресурса',order=11,hidden=function() return not draft or not draft.condition end,
                        get=function() return tostring(draft and draft.conditionValue or 0) end,
                        validate=function(info,value) local n=tonumber(value); return (n and n==n and math.abs(n)<=1000000000) and true or 'Введите число.' end,
                        set=function(info,value) if draft then draft.conditionValue=tonumber(value) or 0 end end},
                    conditionPercent={type='toggle',name='Сравнивать в процентах',order=12,hidden=function() return not draft or not draft.condition end},
                    auraCondition=toggle('Условие бафа / дебафа',12.1),
                    auraConditionMode={type='select',name='Условие',order=12.15,values={present='Присутствует',absent='Отсутствует'},hidden=function() return not draft or not draft.auraCondition end,get=function() return draft and draft.auraConditionMode or 'present' end},
                    auraConditionKind={type='select',name='Тип эффекта условия',order=12.2,values={buff='Баф',debuff='Дебаф'},hidden=function() return not draft or not draft.auraCondition end},
                    auraConditionUnit={type='select',name='На ком должен быть эффект',order=12.3,values={player='Игрок',target='Цель'},hidden=function() return not draft or not draft.auraCondition end},
                    auraConditionId={type='input',name='ID бафа / дебафа условия',order=12.4,hidden=function() return not draft or not draft.auraCondition end,
                        get=function() return draft and draft.auraConditionId and tostring(draft.auraConditionId) or '' end,
                        validate=function(info,value) local id=tonumber(value); return (id and id>0 and id<2147483648 and id==math.floor(id) and GetSpellInfo(id)) and true or 'Введите ID существующего заклинания.' end,
                        set=function(info,value) if draft then draft.auraConditionId=tonumber(value); T.auraCacheTime=nil end end},
                    auraName={type='description',order=12.5,hidden=function() return not draft or not draft.auraCondition end,name=function() return draft and draft.auraConditionId and (GetSpellInfo(draft.auraConditionId) or 'Не найдено') or 'Укажите ID эффекта.' end},
                    liveStatus={type='description',order=12.6,name=function()
                        if not draft then return '' end
                        local state=T:Evaluate(draft,true)
                        local replacement=''
                        if T:NextSwingEntry(draft) then
                            replacement=cfg().autoAttack.enabled and cfg().autoAttack.replace and 'Замена автоатакой включена. ' or 'Для замены включите автоатаку и замену в её вкладке. '
                        end
                        local why=replacement..(state.hiddenReason or state.conditionText or state.reason or 'Доступно.')
                        local anchor=T:Anchor()
                        if not anchor or not anchor:IsShown() then return 'Нет видимого фрейма для иконок. '..why end
                        return (state.visible and 'Условия показа выполнены. ' or 'Сейчас скрыто. ')..why
                    end},
                    help={type='description',order=13,name='Доступная способность — обычного цвета. Нехватка ресурса — синий цвет без обесцвечивания. КД/ГКД не делают иконку серой; серый означает недоступность применения, например отсутствие прока. В режиме «Когда доступно» недоступные иконки скрываются. ГКД показывается только если закончится позже собственного КД, без надписи. Для усилителей автоатаки вместо КД/ГКД показан таймер оружия после первого удара. Очередь применения подсвечивается миганием; у дебафа — серым. Условия задаются в независимых триггерах ниже. Правило активации выбирается отдельно.'},
                    save={type='execute',order=14,name=function() return editing and 'Сохранить изменения' or 'Добавить в список' end,func=function()
                        if not draft then return end
                        for i,g in ipairs(T:PrepareTriggers(draft)) do if g.enabled and g.auraCondition and (not g.auraConditionId or not GetSpellInfo(g.auraConditionId)) then status='Триггер '..i..': укажите ID существующего эффекта.'; return end end
                        local index=editing and locate(editing)
                        if editing and not index then reset(); status='Запись уже удалена.'; return end
                        T:Save(draft,index); reset(); status='Настройки сохранены.'; rebuild()
                    end},
                    cancel={type='execute',name='Отменить',order=15,func=reset}
                }},
            list={type='group',name='Нумерованный список — порядок иконок',order=10,guiInline=true,args={}}
        }}
    }}
    local appearanceArgs=root.args.appearance.args
    appearanceArgs.panelMode={type='select',name='Режим динамической панели',order=0,
        values={classic='Классический',strip='Полоса применений'},
        get=function() return stripMode() and 'strip' or 'classic' end,
        set=function(_,value) cfg().panelMode=value; T:Apply() end}
    appearanceArgs.stripInfo={type='description',order=0.1,width='full',hidden=function() return not stripMode() end,
        name='Первый слот занимает автоатака или её усилитель. Готовые к концу ГКД способности идут дальше по приоритету. Иконки движутся в одном ряду; «Кол-во в ряду» включает первый слот.'}
    for _,key in ipairs({'rows','growX','growY'}) do appearanceArgs[key].hidden=stripMode end
    T:AddRotationOptions(root.args.tracking.args.settings.args,function() return draft end)
    local abilityFields=root.args.tracking.args.settings.args
    abilityFields.showResource.name='Показывать ресурс у иконки'
    abilityFields.displayResource.name='Какой ресурс показывать'
    abilityFields.resourcePosition={type='select',name='Положение значения ресурса',order=7.45,
        values={BOTTOM='Под иконкой',TOP='Над иконкой'},
        hidden=function() return not draft or draft.kind~='spell' or not draft.showResource end,
        get=function() return draft and draft.resourcePosition=='TOP' and 'TOP' or 'BOTTOM' end,
        set=function(info,value) if draft then draft.resourcePosition=value end end}
    abilityFields.resourceValuePosition={type='select',name='Положение числа ресурса',order=7.1,
        values={ICON='На иконке (как раньше)',BOTTOM='Под иконкой',TOP='Над иконкой'},
        hidden=function() return not draft or draft.kind~='resource' end,
        get=function() return draft and (draft.resourcePosition=='TOP' or draft.resourcePosition=='BOTTOM') and draft.resourcePosition or 'ICON' end,
        set=function(info,value) if draft then draft.resourcePosition=value end end}
    root.args.autoAttack={type='group',name='Автоатака',order=3,disabled=isOff,
        get=function(info) return cfg().autoAttack[info[#info]] end,
        set=function(info,value) cfg().autoAttack[info[#info]]=value; T:Apply() end,args={
            enabled=toggle('Отслеживать автоатаку',1),
            showTimer=toggle('Показывать таймер до следующего удара',2),
            showResource=toggle('Показывать ресурс персонажа',3),
            resource=selectOption('Ресурс',4,T.autoResources),
            resourcePosition={type='select',name='Положение значения ресурса',order=4.1,
                values={BOTTOM='Под иконкой',TOP='Над иконкой'},
                hidden=function() return not cfg().autoAttack.showResource end},
            replace=toggle('Заменять недоступные усиленные автоатаки',5),
            help={type='description',order=6,name='Таймер основной руки начинается после зарегистрированного удара или промаха. При включённой замене и наличии отмеченных усилителей иконка автоатаки появляется вместо скрытых или недоступных ударов — только одна, на месте первого из них. Удар в очереди сохраняет свою иконку только при выполненных условиях. Условия ресурса и ауры имеют приоритет над очередью. Варианты с невыполненными условиями не добавляют автоатаку, если другой усиленный удар подходит по условиям. Если ни один не подходит, остаётся одна автоатака. Если усилителей нет или замена выключена, автоатака добавляется в конце списка. Для особых способностей отметьте «Заменяет / усиливает следующую автоатаку» в настройках записи. Положение значения ресурса выбирается выше; шрифт берётся из «Стаки / заряды / ресурс». До первого удара таймер не выдумывается.'}
        }}
    -- Profile settings are isolated from the DBM and from other ElvUI profiles.
    root.args.profiles={type='group',name='Профили',order=0,args={
        info={type='description',order=1,name='Каждый профиль хранит собственный список способностей, триггеры, оформление и автоатаку. Изменения выбранного профиля сохраняются автоматически. При выборе «Выключить» панель скрывается, а профили остаются.'},
        current={type='select',name='Активный профиль',order=2,width='full',
            values=function() return T:ProfileOptions() end,
            get=function() return T:Profiles().selected end,
            set=function(info,value) T:SelectProfile(value); profileMessage=''; end},
        createName={type='input',name='Название нового профиля (для копии необязательно)',order=3,width='full',
            dialogControl=PROFILE_NAME_CONTROL,
            get=function() return newProfileName end,
            set=function(info,value) newProfileName=value end},
        copyCurrent={type='execute',name='Создать копию текущего',order=4,desc='Если название не указано, копия получит имя автоматически.',
            func=function()
                local ok,message=T:CreateProfile(newProfileName,true)
                profileMessage=message or 'Ошибка создания профиля.'
                A:Say(profileMessage)
                if ok then newProfileName='' end
            end},
        createEmpty={type='execute',name='Создать пустой профиль',order=5,
            func=function()
                local ok,message=T:CreateProfile(newProfileName,false)
                profileMessage=message or 'Ошибка создания профиля.'
                A:Say(profileMessage)
                if ok then newProfileName='' end
            end},
        deleteCurrent={type='execute',name='Удалить выбранный профиль',order=6,
            disabled=function() return T:Profiles().selected=='__OFF__' end,
            confirm=function() return 'Удалить выбранный профиль способностей? Его записи и настройки будут потеряны.' end,
            func=function()
                local selected=T:Profiles().selected
                local _,message=T:DeleteProfile(selected)
                profileMessage=message or ''
            end},
        message={type='description',name=function() return profileMessage end,order=7}
    }}
    list=root.args.tracking.args.list
    parent.abilities=root
    rebuild()
    self.RefreshAbilityOptions=function() reset(); profile=A.db; rebuild() end
end

local A=PhoenixPanel
local E=ElvUI[1]
local T=A.Abilities

-- Only this profile-name input needs live typing. AceConfig's regular input
-- commits on Enter; custom textChanged inside an option is INVALID in AceConfig.
-- Use the supported dialogControl API to listen to its *own* edit box, without
-- patching ElvUI's widgets or guessing their global names.
local profileNameTyping
local PROFILE_NAME_CONTROL='PhoenixPanelProfileNameInput'
local VISUAL_KEY_CONTROL='PhoenixPanelVisualKey'
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

local function RegisterVisualKeyControl()
    local gui=E.Libs and E.Libs.AceGUI
    if not gui or not gui:GetWidgetVersion('Keybinding') then return end
    if not gui:GetWidgetVersion(VISUAL_KEY_CONTROL) then
        gui:RegisterWidgetType(VISUAL_KEY_CONTROL,function()
            local widget=gui:Create('Keybinding')
            widget.type=VISUAL_KEY_CONTROL
            local setKey=widget.SetKey
            function widget:SetKey(key)
                self.visualKey=key
                setKey(self,key)
                if not key or key=='' then self.button:SetText('Назначить клавишу') end
            end
            function widget:GetKey() return self.visualKey end
            widget.msgframe.msg:SetText('Нажмите игровую клавишу. Esc — снять назначение, повторный щелчок — отменить.')
            widget.frame:HookScript('OnHide',function()
                if widget.waitingForKey then
                    widget.waitingForKey=nil
                    widget.button:EnableKeyboard(false)
                    widget.button:EnableMouseWheel(false)
                    widget.button:UnlockHighlight()
                    widget.msgframe:Hide()
                end
            end)
            return widget
        end,1)
    end
    return VISUAL_KEY_CONTROL
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
    local visualKeyControl=RegisterVisualKeyControl()
    local function isOff() return T:IsProfileOff() end
    local function stripMode() return cfg().panelMode=='strip' end
    local function reset() draft=nil; editing=nil; status=nil end
    local function selectEditor()
        if E.Libs.AceConfigDialog then
            E.Libs.AceConfigDialog:SelectGroup('ElvUI','phoenixPanel','abilities','tracking','editor')
        end
    end
    local function rebuild()
        if profile~=A.db then profile=A.db; reset() end
        local args={}
        args.add={type='execute',name='Добавить запись',order=0,width=1.2,func=function()
            reset()
            spellText=''
            selectEditor()
        end}
        args.help={type='description',name='Назначьте записи клавишу с игровой панели для визуального эффекта нажатия. Esc снимает назначение.',order=0.1,width='full'}
        for number,p in ipairs(cfg().entries) do
            local uid=p.uid
            local name=p.name or (p.spellId and GetSpellInfo(p.spellId)) or 'Без названия'
            local label=number..'. '..name..' — '..T.kinds[p.kind]
            args['entry'..uid]={type='group',name=label,order=number,guiInline=true,args={
                enabled={type='toggle',name='Включено',order=1,width=0.83,
                    image=function() return (p.spellId and select(3,GetSpellInfo(p.spellId))) or p.icon or 'Interface\\Icons\\INV_Misc_QuestionMark' end,
                    arg={spellId=p.spellId,text=name},dialogControl=p.kind~='resource' and A.DBM.spellWidgetRegistered and 'PhoenixPanelSpellCheck' or nil,
                    desc=p.kind=='resource' and 'Индикатор выбранного ресурса.' or ('Игровое описание: '..tostring(p.spellId)),
                    get=function() local _,entry=locate(uid); return entry and entry.enabled end,
                    set=function(info,value) local _,entry=locate(uid); if entry then entry.enabled=value; T:Apply() end end},
                edit={type='execute',name='Изменить',order=2,width=0.73,func=function()
                    local _,entry=locate(uid)
                    if entry then
                        draft=T.Copy(entry); editing=uid; kind=entry.kind
                        spellText=tostring(entry.spellId or ''); resource=entry.resource or 'current'
                        status='Редактирование — '..name
                        selectEditor()
                    end
                end},
                pressKey={type='keybinding',name=visualKeyControl and '' or 'Назначить клавишу',order=2.1,width=1.2,
                    dialogControl=visualKeyControl,hidden=p.kind~='spell',disabled=InCombatLockdown,
                    desc='Эффект нажатия для этой записи при использовании выбранной клавиши. Esc снимает назначение в PhoenixPanel.',
                    get=function() local _,entry=locate(uid); return entry and entry.pressKey or '' end,
                    validate=function(_,value)
                        return value=='' or T:CanObserveVisualKey(value) or 'Выберите клавишу, назначенную на кнопку панели WoW или ElvUI.'
                    end,
                    set=function(_,value)
                        local _,entry=locate(uid)
                        if not entry then return end
                        entry.pressKey=value~='' and value or nil
                        if draft and editing==uid then draft.pressKey=entry.pressKey end
                        T:RefreshVisualKeys()
                    end},
                up={type='execute',name='Выше',order=3,width=0.53,disabled=function() return locate(uid)==1 end,func=function() local index=locate(uid); if index then T:Move(index,-1); rebuild() end end},
                down={type='execute',name='Ниже',order=4,width=0.53,disabled=function() return locate(uid)==#cfg().entries end,func=function() local index=locate(uid); if index then T:Move(index,1); rebuild() end end},
                delete={type='execute',name='Удалить',order=5,width=0.69,confirm=true,func=function()
                    local index=locate(uid); if index then T:Delete(index); if editing==uid then reset() end; rebuild() end
                end}
            }}
        end
        if #cfg().entries==0 then args.empty={type='description',name='Список пока пуст.',order=1,width='full'} end
        list.args=args
    end
    local function draftValue(info) return draft and draft[info[#info]] end
    local function setDraftValue(info,value)
        if not draft then return end
        local key=info[#info]
        draft[key]=value
        if key=='nextSwing' then draft.nextSwingOverride=value end
    end
    local function draftSection(name,order,args)
        return {type='group',name=name,order=order,args=args,
            hidden=function() return not draft end,get=draftValue,set=setDraftValue}
    end
    local function spellOnly() return not draft or draft.kind~='spell' end
    local function auraOnly() return not draft or (draft.kind~='buff' and draft.kind~='debuff') end
    local function resourceOnly() return not draft or draft.kind~='resource' end
    local function entryStatus()
        if not draft then return '' end
        local state=T:Evaluate(draft,true)
        if stripMode() and draft.kind=='spell' and state.noResource and state.conditionPassed
            and not T:NextSwingEntry(draft) and T:StripSpellReadyAt(state)<math.huge then
            return 'Участвует в прогнозе. Недостаточно ресурса.'
        end
        if not state.visible then return 'Сейчас скрыто. '..(state.hiddenReason or state.reason or 'Запись скрыта настройками показа.') end
        return 'Условия показа выполнены. '..(state.reason or state.conditionText or '')
    end
    local function saveEntry()
        if not draft then return end
        for i,g in ipairs(T:PrepareTriggers(draft)) do
            if g.enabled and g.auraCondition and (not g.auraConditionId or not GetSpellInfo(g.auraConditionId)) then
                status='Триггер '..i..' — укажите ID существующего эффекта.'
                return
            end
        end
        local index=editing and locate(editing)
        if editing and not index then reset(); status='Запись уже удалена.'; return end
        T:Save(draft,index)
        reset()
        status='Настройки сохранены.'
        rebuild()
        if E.Libs.AceConfigDialog then
            E.Libs.AceConfigDialog:SelectGroup('ElvUI','phoenixPanel','abilities','tracking','list')
        end
    end
    local abilityFields={
        found={type='description',order=1,width='full',name=function() return draft and draft.name or '' end,
            image=function() return draft and draft.icon or '' end,imageWidth=26,imageHeight=26},
        mode={type='select',name='Показывать',order=2,width=1.3,values={always='Всегда',available='При готовности / эффекте'}},
        unit={type='select',name='Отслеживать на',order=3,width=1.1,values=T.units,
            hidden=function() return not draft or draft.kind=='spell' or draft.resource=='targethealth' end},
        showGCD={type='toggle',name='Показывать ГКД',order=4,width=1.1,hidden=spellOnly},
        checkRange={type='toggle',name='Дальность до цели',order=5,width=1.2,
            desc='Учитывать дальность при показе доступности способности.',hidden=spellOnly},
        onlyMine={type='toggle',name='Только мои ауры',order=5.1,width=1.15,hidden=auraOnly},
        resourcePercent={type='toggle',name='В процентах',order=5.2,width=1.1,hidden=resourceOnly},
        priorityTitle={type='header',name='Приоритет',order=6,hidden=function() return not draft or draft.kind=='resource' end},
        nextSwing={type='toggle',name='Усилитель автоатаки',order=6.1,width=1.3,
            desc='Отметить запись как замену или усиление следующего удара.',hidden=function() return not draft or draft.kind=='resource' end},
        readyFirst={type='toggle',name='В начало при готовности',order=6.2,width=1.5,
            desc='В классическом режиме запись поднимается в начало, если эффект отсутствует либо закончится к концу ГКД, или способность готова к этому моменту.',
            hidden=function() return not draft or draft.kind=='resource' or stripMode() end},
        castPriority={type='range',name='Приоритет',order=6.3,min=1,max=10,step=1,width=1.2,
            desc='1 — самый высокий. При равном приоритете действует порядок списка.',
            hidden=function() return not draft or not stripMode() or draft.kind=='resource' or T:NextSwingEntry(draft) end,
            get=function() return draft and T:CastPriority(draft) or 5 end},
        resourceTitle={type='header',name='Ресурс и замена',order=7.2,hidden=spellOnly},
        liveStatus={type='description',name=entryStatus,order=13,width='full'},
    }
    local triggerFields,stackFields={},{}
    T:AddRotationOptions(abilityFields,function() return draft end,triggerFields,stackFields)

    abilityFields.showResource.name='Ресурс на иконке'
    abilityFields.showResource.width=1.15
    abilityFields.displayResource.name='Тип ресурса'
    abilityFields.displayResource.width=1.15
    abilityFields.replacementEnabled.name='Замена без ресурса'
    abilityFields.replacementEnabled.width=1.3
    abilityFields.replacementEnabled.desc='Показать выбранную способность при нехватке ресурса для этой записи.'
    abilityFields.replacementId.name='ID замены'
    abilityFields.resourcePosition={type='select',name='Положение числа',order=7.45,width=1.1,
        values={BOTTOM='Под иконкой',TOP='Над иконкой'},
        hidden=function() return spellOnly() or not draft.showResource end,
        get=function() return draft and draft.resourcePosition=='TOP' and 'TOP' or 'BOTTOM' end,
        set=function(_,value) if draft then draft.resourcePosition=value end end}
    abilityFields.resourceValuePosition={type='select',name='Положение числа',order=5.3,width=1.1,
        values={ICON='На иконке',BOTTOM='Под иконкой',TOP='Над иконкой'},
        hidden=resourceOnly,
        get=function() return draft and (draft.resourcePosition=='TOP' or draft.resourcePosition=='BOTTOM') and draft.resourcePosition or 'ICON' end,
        set=function(_,value) if draft then draft.resourcePosition=value end end}

    local editor={type='group',name='Редактор',order=2,childGroups='tab',args={
        kind={type='select',name='Что отслеживать',order=1,width=1.2,values=T.kinds,
            get=function() return kind end,set=function(_,value) kind=value; reset() end},
        spellId={type='input',name='ID заклинания',order=2,width=1.05,hidden=function() return kind=='resource' end,
            get=function() return spellText end,set=function(_,value) spellText=value; reset() end},
        resource={type='select',name='Ресурс',order=2,width=1.05,values=T.resources,hidden=function() return kind~='resource' end,
            get=function() return resource end,set=function(_,value) resource=value; reset() end},
        find={type='execute',name='Найти',order=3,width=0.7,func=function()
            local found,err=T:Find(spellText,kind,resource)
            draft=found; editing=nil; status=found and nil or err
        end},
        status={type='description',order=4,width='full',name=function() return status or 'Выберите тип записи, укажите ID или ресурс и нажмите «Найти».' end,
            hidden=function() return draft~=nil and not status end},
        save={type='execute',order=5,width=1.15,name=function() return editing and 'Сохранить' or 'Добавить' end,
            hidden=function() return not draft end,func=saveEntry},
        cancel={type='execute',name='Отмена',order=5.1,width=0.8,hidden=function() return not draft end,func=reset},
        settings=draftSection('Основное',10,abilityFields),
        triggerSettings=draftSection('Триггеры',11,triggerFields),
        stackSettings=draftSection('Стаки',12,stackFields)
    }}
    editor.args.stackSettings.hidden=resourceOnly

    list={type='group',name='Список',order=1,args={}}
    root={type='group',name='Динамическая панель',order=6,childGroups='tab',args={
        appearance=self:AbilityAppearanceOptions(T,
            'Порядок зависит от режима и приоритета. Расположение настраивается через «Перенос рамок» ElvUI.',isOff),
        tracking={type='group',name='Способности',order=2,childGroups='tab',disabled=isOff,args={
            stripHighestOnly={type='toggle',name='Только лучший вариант способности',order=0,width='full',
                desc='В «Полосе применений» из записей одной способности с разными триггерами выбирается подходящая запись с самым высоким приоритетом. Повторы по ГКД и стакам учитываются отдельно.',
                get=function() return cfg().stripHighestOnly==true end,
                set=function(_,value) cfg().stripHighestOnly=value; T:Apply() end},
            list=list,editor=editor
        }}
    }}
    local appearanceArgs=root.args.appearance.args.icons.args
    appearanceArgs.panelMode={type='select',name='Режим панели',order=0,width=1.35,
        values={classic='Классический',strip='Полоса применений'},
        get=function() return stripMode() and 'strip' or 'classic' end,
        set=function(_,value) cfg().panelMode=value; T:Apply() end}
    appearanceArgs.stripInfo={type='description',order=0.1,width='full',hidden=function() return not stripMode() end,
        name='Прогноз по ГКД идёт после автоатаки. Синий цвет означает нехватку ресурса. Первый слот входит в лимит иконок.'}
    for _,key in ipairs({'rows','growX','growY'}) do appearanceArgs[key].hidden=stripMode end
    root.args.autoAttack={type='group',name='Автоатака',order=3,disabled=isOff,
        get=function(info) return cfg().autoAttack[info[#info]] end,
        set=function(info,value) cfg().autoAttack[info[#info]]=value; T:Apply() end,args={
            enabled=toggle('Отслеживать',1),
            showTimer=toggle('Таймер удара',2),
            showResource=toggle('Ресурс на иконке',3),
            resource={type='select',name='Ресурс',order=4,values=T.autoResources},
            resourcePosition={type='select',name='Положение числа',order=4.1,
                values={BOTTOM='Под иконкой',TOP='Над иконкой'},
                hidden=function() return not cfg().autoAttack.showResource end},
            replace=toggle('Заменять усилители',5),
            help={type='description',order=6,width='full',name='Таймер оружия начинается с первого удара или промаха. Если подходящий усилитель недоступен, настройка замены показывает автоатаку. Отметить усилитель можно в редакторе записи.'}
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
        copyCurrent={type='execute',name='Копировать профиль',order=4,desc='Если название не указано, копия получит имя автоматически.',
            func=function()
                local ok,message=T:CreateProfile(newProfileName,true)
                profileMessage=message or 'Ошибка создания профиля.'
                A:Say(profileMessage)
                if ok then newProfileName='' end
            end},
        createEmpty={type='execute',name='Новый профиль',order=5,
            func=function()
                local ok,message=T:CreateProfile(newProfileName,false)
                profileMessage=message or 'Ошибка создания профиля.'
                A:Say(profileMessage)
                if ok then newProfileName='' end
            end},
        deleteCurrent={type='execute',name='Удалить профиль',order=6,
            disabled=function() return T:Profiles().selected=='__OFF__' end,
            confirm=function() return 'Удалить профиль способностей? Его записи и настройки будут потеряны.' end,
            func=function()
                local selected=T:Profiles().selected
                local _,message=T:DeleteProfile(selected)
                profileMessage=message or ''
            end},
        message={type='description',name=function() return profileMessage end,order=7}
    }}
    parent.abilities=root
    rebuild()
    self.RefreshAbilityOptions=function() reset(); profile=A.db; rebuild() end
end

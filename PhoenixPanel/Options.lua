local E=ElvUI[1]
local A=PhoenixPanel

local PROFILE_NAME_CONTROL='PhoenixPanelProfileNameInput'
local profileNameTyping

local function registerProfileNameControl()
    local gui=E.Libs and E.Libs.AceGUI
    if not gui or gui:GetWidgetVersion(PROFILE_NAME_CONTROL) then return end
    gui:RegisterWidgetType(PROFILE_NAME_CONTROL,function()
        local widget=gui:Create('EditBox-ElvUI')
        widget.type=PROFILE_NAME_CONTROL
        -- AceConfig's input setter commits on Enter, but the buttons also
        -- need the name entered before a user clicks away from the field.
        widget.editbox:HookScript('OnTextChanged',function(editbox,isUserInput)
            if isUserInput and editbox:HasFocus() and profileNameTyping then
                profileNameTyping(editbox:GetText())
            end
        end)
        return widget
    end,1)
end

local function insertProfiles(parent)
    local T=A.Abilities
    local newProfileName,profileMessage='',''
    local deleteDB,deleteName
    profileNameTyping=function(value) newProfileName=value end
    registerProfileNameControl()

    local function create(duplicate)
        local ok,message=T:CreateProfile(newProfileName,duplicate)
        profileMessage=message or 'Ошибка создания профиля.'
        A:Say(profileMessage)
        if ok then newProfileName='' end
    end

    parent.profiles={type='group',name='Профили',order=4,args={
        info={type='description',order=1,width='full',
            name='Профиль хранит записи и настройки обеих панелей. Изменения сохраняются автоматически. Настройки DBM и положение рамок хранятся отдельно.'},
        current={type='select',name='Активный профиль',order=2,width='full',
            desc='«Выключить» скрывает динамическую панель. Стационарная продолжает использовать настройки последнего активного профиля.',
            values=function() return T:ProfileOptions() end,
            get=function() return T:Profiles().selected end,
            set=function(_,value) T:SelectProfile(value); profileMessage='' end},
        createName={type='input',name='Название профиля',order=3,width='full',
            dialogControl=PROFILE_NAME_CONTROL,
            get=function() return newProfileName end,
            set=function(_,value) newProfileName=value end},
        copyCurrent={type='execute',name='Копировать профиль',order=4,
            desc='Копировать обе панели активного профиля. Если динамическая панель выключена, используется последний активный профиль. Если имя пустое, оно будет создано автоматически.',
            func=function() create(true) end},
        createEmpty={type='execute',name='Новый профиль',order=5,
            desc='Создать профиль с настройками по умолчанию для обеих панелей.',
            func=function() create(false) end},
        deleteCurrent={type='execute',name='Удалить профиль',order=6,
            disabled=function() return T:Profiles().selected=='__OFF__' end,
            confirm=function()
                deleteDB,deleteName=A.db,T:Profiles().selected
                return 'Удалить профиль «'..deleteName..'»? Его записи и настройки обеих панелей будут удалены.'
            end,
            func=function()
                local db,name=deleteDB,deleteName
                deleteDB,deleteName=nil,nil
                if db~=A.db or not name or name~=T:Profiles().selected then return end
                local _,message=T:DeleteProfile(name)
                profileMessage=message or ''
            end},
        message={type='description',name=function() return profileMessage end,order=7,width='full',
            hidden=function() return profileMessage=='' end}
    }}
end

function A:InsertOptions()
    local args={
        description={type='description',order=1,
            name='Стационарная панель держит записи на заданных местах. Динамическая меняет порядок по готовности и триггерам. Перемещение каждой панели доступно через ElvUI → Перенос рамок.'}
    }
    E.Options.args.phoenixPanel={type='group',name='PhoenixPanel',order=80,childGroups='tab',args=args}
    self:InsertDBMOptions(args)
    self:InsertAbilityOptions(args)
    self:InsertStationaryOptions(args)
    insertProfiles(args)
end

function A:OpenOptions()
    if InCombatLockdown() then self:Say('Откройте настройки после боя.'); return end
    local toggleOptions=E.ToggleOptions or E.ToggleOptionsUI
    toggleOptions(E,'phoenixPanel')
end

SLASH_PHOENIXPANEL1='/phoenixpanel'
SlashCmdList.PHOENIXPANEL=function() A:OpenOptions() end

local E=ElvUI[1]
local A=PhoenixPanel

function A:InsertOptions()
    local args={
        description={type='description',order=1,
            name='Стационарная панель держит записи на заданных местах. Динамическая меняет порядок по готовности и триггерам. Перемещение каждой панели доступно через ElvUI → Перенос рамок.'}
    }
    E.Options.args.phoenixPanel={type='group',name='PhoenixPanel',order=80,childGroups='tab',args=args}
    self:InsertDBMOptions(args)
    self:InsertAbilityOptions(args)
    self:InsertStationaryOptions(args)
end

function A:OpenOptions()
    if InCombatLockdown() then self:Say('Откройте настройки после боя.'); return end
    local toggleOptions=E.ToggleOptions or E.ToggleOptionsUI
    toggleOptions(E,'phoenixPanel')
end

SLASH_PHOENIXPANEL1='/phoenixpanel'
SlashCmdList.PHOENIXPANEL=function() A:OpenOptions() end

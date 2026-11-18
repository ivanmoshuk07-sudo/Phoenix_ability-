local A=PhoenixPanel
local E=ElvUI[1]
local S=A.Stationary

local points={TOPLEFT='TOPLEFT',TOP='TOP',TOPRIGHT='TOPRIGHT',LEFT='LEFT',CENTER='CENTER',RIGHT='RIGHT',BOTTOMLEFT='BOTTOMLEFT',BOTTOM='BOTTOM',BOTTOMRIGHT='BOTTOMRIGHT'}
local outlines={['']='Без обводки',OUTLINE='Outline',THICKOUTLINE='Thick outline',['MONOCHROME,OUTLINE']='Monochrome outline'}
local function toggle(name,order) return {type='toggle',name=name,order=order} end
local function range(name,order,lo,hi) return {type='range',name=name,order=order,min=lo,max=hi,step=1} end
local function selectOption(name,order,values) return {type='select',name=name,order=order,values=values} end

function A:AbilityAppearanceOptions(panel,orderDescription,isDisabled)
    local function appearance() return panel:Config().appearance end
    local function fonts()
        local values={DEFAULT='Шрифт клиента'}
        if E.Libs.LSM then
            for name in pairs(E.Libs.LSM:HashTable('font')) do values[name]=name end
        end
        values[appearance().count.font]=appearance().count.font
        values[appearance().duration.font]=appearance().duration.font
        return values
    end
    local function textGroup(key,title,order)
        local args={
            show=toggle('Показывать',1),font=selectOption('Шрифт',2,fonts),size=range('Размер шрифта',3,4,60),
            outline=selectOption('Граница шрифта',4,outlines),point=selectOption('Позиция',5,points),
            x=range('Отступ по X',6,-100,100),y=range('Отступ по Y',7,-100,100)
        }
        if key=='duration' then args.swipe=toggle('Восстановление (затемнение)',8) end
        return {
            type='group',name=title,order=order,guiInline=true,args=args,
            get=function(info) return appearance()[key][info[#info]] end,
            set=function(info,value) appearance()[key][info[#info]]=value; panel:Apply() end
        }
    end
    local group={
        type='group',name='Оформление',order=1,disabled=isDisabled,
        get=function(info) return appearance()[info[#info]] end,
        set=function(info,value) appearance()[info[#info]]=value; panel:Apply() end,
        args={
            enabled=toggle('Включить',1),stack=toggle('Стакать одинаковые ауры',2),
            desaturate=toggle('Обесцвечивать недоступные',3),keepAspect=toggle('Сохранить пропорции',4),
            size=range('Размер',6,6,60),height=range('Высота без сохранения пропорций',7,6,60),
            perRow=range('Кол-во в ряду',8,1,20),rows=range('Рядов',9,1,5),spacing=range('Отступ',10,0,60),
            scale={type='range',name='Масштаб иконок',order=6.1,min=0.25,max=3,step=0.05,isPercent=true},
            growX=selectOption('Рост по X',14,{LEFT='Влево',RIGHT='Вправо'}),
            growY=selectOption('Рост по Y',15,{UP='Вверх',DOWN='Вниз'}),
            orderInfo={type='description',name=orderDescription,order=16},
            count=textGroup('count',panel.stationary and 'Стаки / заряды' or 'Стаки / заряды / ресурс',20),
            duration=textGroup('duration','Длительность / КД / ГКД',21)
        }
    }
    if not panel.stationary then
        group.args.x=range('Отступ по X',11,-100,100)
        group.args.y=range('Отступ по Y',12,-100,100)
        group.args.anchor=selectOption('Точка фиксации',13,points)
        group.args.flashes={
            type='group',name='Подсветка событий',order=22,guiInline=true,
            get=function(info) return panel:Config().flashes[info[#info]] end,
            set=function(info,value) panel:Config().flashes[info[#info]]=value; panel:Apply() end,
            args={cooldown=toggle('Способность готова после КД',1),debuff=toggle('Дебаф закончился',2)}
        }
        panel:AddStackAppearance(group)
    end
    return group
end

function A:InsertStationaryOptions(parent)
    local profile
    local kind,idText='spell',''
    local draft,editing,status
    local list={type='group',name='Порядок иконок',order=10,guiInline=true,args={}}
    local function reset()
        draft,editing,status=nil,nil,nil
    end
    local function locate(uid)
        for index,entry in ipairs(S:Config().entries) do
            if entry.uid==uid then return index,entry end
        end
    end
    local function entryName(entry)
        if entry.itemId then
            return (GetItemInfo and GetItemInfo(entry.itemId)) or entry.name or ('Предмет #'..entry.itemId)
        end
        return entry.name or ('Заклинание #'..entry.spellId)
    end
    local function rebuild()
        if profile~=A.db then
            profile=A.db
            reset()
        end
        local args={}
        for index,entry in ipairs(S:Config().entries) do
            local uid=entry.uid
            args['entry'..uid]={
                type='group',order=index,guiInline=true,
                name=function() return index..'. '..entryName(entry)..' — '..S.kinds[entry.kind] end,
                args={
                    enabled={type='toggle',name='Отслеживать',order=1,
                        get=function() local _,current=locate(uid); return current and current.enabled end,
                        set=function(_,value)
                            local _,current=locate(uid)
                            if current then current.enabled=value; S:Apply() end
                        end},
                    edit={type='execute',name='Изменить',order=2,func=function()
                        local _,current=locate(uid)
                        if not current then return end
                        draft=S.Copy(current)
                        editing=uid
                        kind=current.kind
                        idText=tostring(current.itemId or current.spellId)
                        status=nil
                    end},
                    up={type='execute',name='Выше',order=3,
                        disabled=function() return locate(uid)==1 end,
                        func=function()
                            local position=locate(uid)
                            if position then S:Move(position,-1); rebuild() end
                        end},
                    down={type='execute',name='Ниже',order=4,
                        disabled=function() return locate(uid)==#S:Config().entries end,
                        func=function()
                            local position=locate(uid)
                            if position then S:Move(position,1); rebuild() end
                        end},
                    delete={type='execute',name='Удалить',order=5,confirm=true,func=function()
                        local position=locate(uid)
                        if position then S:Delete(position); rebuild() end
                        if editing==uid then reset() end
                    end}
                }
            }
        end
        if not next(args) then
            args.empty={type='description',name='Список пока пуст. Найдите запись по ID и добавьте её на панель.',order=1}
        end
        list.args=args
    end

    local function hideAuraFields() return not draft or (draft.kind~='buff' and draft.kind~='debuff') end
    local function hideSpellFields() return not draft or draft.kind~='spell' end
    parent.stationary={type='group',name='Стационарная панель',order=5,childGroups='tab',args={
        appearance=self:AbilityAppearanceOptions(S,'Иконки следуют порядку списка. Готовность, КД и отсутствие эффекта не меняют их позиции. Рамка перемещается через ElvUI → Перенос рамок.'),
        tracking={type='group',name='Отслеживание',order=2,args={
            kind={type='select',name='Тип отслеживания',order=1,values=S.kinds,
                get=function() return kind end,set=function(_,value) kind=value; reset() end},
            id={type='input',name=function() return kind=='item' and 'ID предмета' or 'ID заклинания / эффекта' end,order=2,
                get=function() return idText end,set=function(_,value) idText=value; reset() end},
            find={type='execute',name='Найти',order=3,func=function()
                local found,err=S:Find(idText,kind)
                draft,editing,status=found,nil,err
            end},
            status={type='description',order=4,name=function() return status or '' end,hidden=function() return not status end},
            entry={type='group',name='Настройки записи',order=5,guiInline=true,hidden=function() return not draft end,
                get=function(info) return draft and draft[info[#info]] end,
                set=function(info,value) if draft then draft[info[#info]]=value end end,
                args={
                    preview={type='description',order=1,
                        name=function() return draft and entryName(draft) or '' end,
                        image=function() return draft and draft.icon or 'Interface\\Icons\\INV_Misc_QuestionMark' end,imageWidth=32,imageHeight=32},
                    unit={type='select',name='На ком отслеживать',order=2,values=S.units,hidden=hideAuraFields},
                    onlyMine={type='toggle',name='Только мои ауры',order=3,hidden=hideAuraFields},
                    showGCD={type='toggle',name='Показывать ГКД',order=4,hidden=hideSpellFields},
                    checkRange={type='toggle',name='Учитывать дальность до цели',order=5,hidden=hideSpellFields},
                    save={type='execute',order=6,name=function() return editing and 'Сохранить изменения' or 'Добавить в список' end,
                        func=function()
                            if not draft then return end
                            local index=editing and locate(editing)
                            if editing and not index then reset(); status='Запись уже удалена.'; return end
                            S:Save(draft,index)
                            reset()
                            rebuild()
                        end},
                    cancel={type='execute',name='Отменить',order=7,func=reset}
                }},
            list=list
        }}
    }}
    A.RefreshStationaryOptions=rebuild
    rebuild()
end

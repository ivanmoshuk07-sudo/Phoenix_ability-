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
            show=toggle('Показывать',1),font=selectOption('Шрифт',2,fonts),size=range('Размер',3,4,60),
            outline=selectOption('Обводка',4,outlines),point=selectOption('Позиция',5,points),
            x=range('Отступ по X',6,-100,100),y=range('Отступ по Y',7,-100,100)
        }
        if key=='duration' then
            args.swipe={type='toggle',name='Затемнение',order=8,desc='Показывать ход таймера затемнением иконки.'}
        end
        return {
            type='group',name=title,order=order,args=args,
            get=function(info) return appearance()[key][info[#info]] end,
            set=function(info,value) appearance()[key][info[#info]]=value; panel:Apply() end
        }
    end
    local layout={
        type='group',name='Иконки',order=1,args={
            enabled=toggle('Включить панель',1),
            stack={type='toggle',name='Объединять ауры',order=2,desc='Суммировать стаки отслеживаемых аур с одинаковым ID.'},
            desaturate={type='toggle',name='Обесцвечивать',order=3,desc='Обесцвечивать недоступные записи.'},
            keepAspect=toggle('Сохранять пропорции',4),
            size=range('Размер',6,6,60),height=range('Высота',7,6,60),
            perRow=range('Иконок в ряду',8,1,20),rows=range('Рядов',9,1,5),spacing=range('Промежуток',10,0,60),
            scale={type='range',name='Масштаб',order=6.1,min=0.25,max=3,step=0.05,isPercent=true},
            growX=selectOption('Рост по X',14,{LEFT='Влево',RIGHT='Вправо'}),
            growY=selectOption('Рост по Y',15,{UP='Вверх',DOWN='Вниз'}),
            orderInfo={type='description',name=orderDescription,order=16}
        }
    }
    layout.args.height.disabled=function() return appearance().keepAspect end
    local group={
        type='group',name='Оформление',order=1,childGroups='tab',disabled=isDisabled,
        get=function(info) return appearance()[info[#info]] end,
        set=function(info,value) appearance()[info[#info]]=value; panel:Apply() end,
        args={
            icons=layout,
            count=textGroup('count','Числа',20),
            duration=textGroup('duration','Таймер',21)
        }
    }
    group.args.count.desc=panel.stationary and 'Текст стаков и зарядов.' or 'Текст стаков, зарядов и ресурсов.'
    group.args.duration.desc='Текст длительности, КД и ГКД.'
    if not panel.stationary then
        layout.args.x=range('Отступ по X',11,-100,100)
        layout.args.y=range('Отступ по Y',12,-100,100)
        layout.args.anchor=selectOption('Точка фиксации',13,points)
        group.args.flashes={
            type='group',name='Подсветка',order=22,
            get=function(info) return panel:Config().flashes[info[#info]] end,
            set=function(info,value) panel:Config().flashes[info[#info]]=value; panel:Apply() end,
            args={
                cooldown={type='toggle',name='Конец КД',order=1,desc='Подсвечивать способность, когда она готова после КД.'},
                debuff={type='toggle',name='Конец дебафа',order=2,desc='Подсвечивать запись, когда её дебаф истёк.'}
            }
        }
        panel:AddStackAppearance(group)
        group.args.stacks.name='Стаки'
        group.args.stacks.desc='Оформление отдельного счётчика отслеживаемых стаков.'
        group.args.stacks.guiInline=nil
    end
    return group
end

function A:InsertStationaryOptions(parent)
    local profile
    local kind,idText='spell',''
    local selected,draft,editing,status
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
    local function refresh()
        if profile~=A.db then
            profile=A.db
            selected=nil
            reset()
        end
        if not locate(selected) then
            local first=S:Config().entries[1]
            selected=first and first.uid
        end
    end
    local function move(delta)
        local position=locate(selected)
        if position then S:Move(position,delta) end
    end
    local list={type='group',name='Список',order=5,guiInline=true,args={
        empty={type='description',name='Список пуст. Найдите запись по ID, чтобы добавить её.',order=1,
            hidden=function() return #S:Config().entries>0 end},
        items={type='select',name='Запись',order=2,width='full',
            hidden=function() return #S:Config().entries==0 end,
            values=function()
                local values={}
                for index,entry in ipairs(S:Config().entries) do
                    values[entry.uid]=index..'. '..entryName(entry)..' — '..S.kinds[entry.kind]
                end
                return values
            end,
            sorting=function()
                local keys={}
                for index,entry in ipairs(S:Config().entries) do keys[index]=entry.uid end
                return keys
            end,
            get=function() refresh(); return selected end,
            set=function(_,uid)
                if editing and editing~=uid then reset() end
                selected=uid
            end},
        enabled={type='toggle',name='Отслеживать',order=3,width='half',
            hidden=function() return not locate(selected) end,
            get=function() local _,entry=locate(selected); return entry and entry.enabled end,
            set=function(_,value)
                local _,entry=locate(selected)
                if entry then
                    entry.enabled=value
                    if editing==selected then draft.enabled=value end
                    S:Apply()
                end
            end},
        edit={type='execute',name='Изменить',order=4,width='half',
            hidden=function() return not locate(selected) end,func=function()
                local _,entry=locate(selected)
                if not entry then return end
                draft=S.Copy(entry)
                editing=selected
                kind=entry.kind
                idText=tostring(entry.itemId or entry.spellId)
                status=nil
            end},
        up={type='execute',name='Выше',order=5,width='half',
            hidden=function() return not locate(selected) end,
            disabled=function() return locate(selected)==1 end,func=function() move(-1) end},
        down={type='execute',name='Ниже',order=6,width='half',
            hidden=function() return not locate(selected) end,
            disabled=function() return locate(selected)==#S:Config().entries end,func=function() move(1) end},
        delete={type='execute',name='Удалить',order=7,width='half',confirm=true,
            hidden=function() return not locate(selected) end,func=function()
                local position=locate(selected)
                if not position then return end
                if editing==selected then reset() end
                S:Delete(position)
                local entries=S:Config().entries
                local nextEntry=entries[position] or entries[#entries]
                selected=nextEntry and nextEntry.uid
            end}
    }}

    local function hideAuraFields() return not draft or (draft.kind~='buff' and draft.kind~='debuff') end
    local function hideSpellFields() return not draft or draft.kind~='spell' end
    parent.stationary={type='group',name='Стационарная панель',order=5,childGroups='tab',args={
        appearance=self:AbilityAppearanceOptions(S,'Порядок иконок задаётся в списке. Чтобы переместить панель, откройте ElvUI → Перенос рамок.'),
        tracking={type='group',name='Отслеживание',order=2,args={
            kind={type='select',name='Тип',order=1,values=S.kinds,
                get=function() return kind end,set=function(_,value) kind=value; reset() end},
            id={type='input',name=function() return kind=='item' and 'ID предмета' or 'ID заклинания' end,order=2,
                get=function() return idText end,set=function(_,value) idText=value; reset() end},
            find={type='execute',name='Найти',order=3,width='half',func=function()
                local found,err=S:Find(idText,kind)
                draft,editing,status=found,nil,err
            end},
            status={type='description',order=4,name=function() return status or '' end,hidden=function() return not status end},
            entry={type='group',name='Редактор',order=6,guiInline=true,hidden=function() return not draft end,
                get=function(info) return draft and draft[info[#info]] end,
                set=function(info,value) if draft then draft[info[#info]]=value end end,
                args={
                    preview={type='description',order=1,
                        name=function() return draft and entryName(draft) or '' end,
                        image=function() return draft and draft.icon or 'Interface\\Icons\\INV_Misc_QuestionMark' end,imageWidth=32,imageHeight=32},
                    unit={type='select',name='На ком',order=2,values=S.units,hidden=hideAuraFields},
                    onlyMine={type='toggle',name='Только мои ауры',order=3,hidden=hideAuraFields},
                    showGCD={type='toggle',name='Показывать ГКД',order=4,hidden=hideSpellFields},
                    checkRange={type='toggle',name='Проверять дальность',order=5,hidden=hideSpellFields},
                    save={type='execute',order=6,name=function() return editing and 'Сохранить' or 'Добавить' end,
                        func=function()
                            if not draft then return end
                            local index=editing and locate(editing)
                            if editing and not index then reset(); status='Запись уже удалена.'; return end
                            S:Save(draft,index)
                            local entries=S:Config().entries
                            local entry=entries[index or #entries]
                            selected=entry and entry.uid
                            reset()
                        end},
                    cancel={type='execute',name='Отменить',order=7,func=reset}
                }},
            list=list
        }}
    }}
    A.RefreshStationaryOptions=refresh
    refresh()
end

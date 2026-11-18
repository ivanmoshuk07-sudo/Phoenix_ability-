local A=PhoenixPanel
local E=ElvUI[1]
local D=A.DBM
local points={TOPLEFT='TOPLEFT',TOP='TOP',TOPRIGHT='TOPRIGHT',LEFT='LEFT',CENTER='CENTER',RIGHT='RIGHT',BOTTOMLEFT='BOTTOMLEFT',BOTTOM='BOTTOM',BOTTOMRIGHT='BOTTOMRIGHT'}
local function cfg() return A.db.dbm end
local function apply() D:Apply() end
local function fontValues()
    local values={DEFAULT='Шрифт клиента'}
    if E.Libs.LSM then for name,path in pairs(E.Libs.LSM:HashTable('font')) do values[name]=name end end
    values[cfg().count.font]=cfg().count.font; values[cfg().duration.font]=cfg().duration.font
    return values
end
local function range(name,order,min,max)
    return {type='range',name=name,order=order,min=min,max=max,step=1}
end
local function selectOption(name,order,values)
    return {type='select',name=name,order=order,values=values}
end
local function toggle(name,order) return {type='toggle',name=name,order=order} end
local function textGroup(key,title,order)
    local args={show=toggle('Показывать',1),font=selectOption('Шрифт',2,fontValues),size=range('Размер шрифта',3,4,60),
        outline=selectOption('Граница шрифта',4,{['']='Без обводки',OUTLINE='Outline',THICKOUTLINE='Thick outline',['MONOCHROME,OUTLINE']='Monochrome outline'}),
        point=selectOption('Позиция',5,points),x=range('Отступ по X',6,-100,100),y=range('Отступ по Y',7,-100,100)}
    if key=='duration' then args.swipe=toggle('Восстановление (затемнение)',8) end
    return {type='group',name=title,order=order,guiInline=true,
        get=function(info) return cfg()[key][info[#info]] end,
        set=function(info,value) cfg()[key][info[#info]]=value; apply() end,args=args}
end


local function registerSpellWidget()
    local gui=E.Libs.AceGUI
    if not gui or D.spellWidgetRegistered then return end
    D.spellWidgetRegistered=true
    gui:RegisterWidgetType('PhoenixPanelSpellCheck',function()
        local widget=gui:Create('CheckBox')
        widget.type='PhoenixPanelSpellCheck'
        local fire=widget.Fire
        function widget:Fire(event,...)
            fire(self,event,...)
            if event=='OnEnter' then
                local option=self:GetUserData('option')
                local data=option and option.arg
                if data then
                    local dialog=E.Libs.AceConfigDialog
                    if dialog and dialog.tooltip then dialog.tooltip:Hide() end
                    D:SpellTooltip(self.frame,data.spellId,data.text)
                end
            elseif event=='OnLeave' then GameTooltip:Hide() end
        end
        return widget
    end,1)
end

local function ordered(values,orders)
    local keys={}; for key in pairs(values) do keys[#keys+1]=key end
    table.sort(keys,function(a,b)
        local x,y=orders[a] or 99999,orders[b] or 99999
        if x==y then return a<b end
        return x<y
    end)
    return keys
end

local function groupData(entry)
    local meta=(A.DBMPackMeta or {})[entry.pack] or {kind='RAID',order=999}
    local key=entry.pack
    local name=(A.DBMPackNames or {})[key] or key:gsub('^DBM%-','')
    local rank=meta.order*1000
    if (meta.kind=='PARTY' or entry.pack=='DBM-ChamberOfAspects') and entry.instance and entry.instance~='' then
        key=key..'/'..entry.instance
        name=entry.instanceName~='' and entry.instanceName or entry.instance
        rank=rank+(entry.instanceOrder or 99)
        if entry.pack=='DBM-ChamberOfAspects' then
            if entry.instance=='Ruby' then rank=24500 elseif entry.instance=='Bronze' then rank=25500 end
        end
    end
    return key,name,rank,meta.kind
end

local function browser(kind,title,order)
    local state={search=''}
    local group={type='group',name=title,order=order,args={}}
    local function groups()
        local values,orders={},{}
        for _,entry in pairs(D.catalog) do
            local key,name,rank,entryKind=groupData(entry)
            if entryKind==kind then values[key]=name; orders[key]=rank end
        end
        return values,ordered(values,orders)
    end
    local function chooseGroup()
        local values,sort=groups()
        if not state.pack or not values[state.pack] then state.pack=sort[1]; state.boss=nil end
        return state.pack
    end
    local function bosses()
        local values,orders={},{}
        local selected=chooseGroup()
        for id,entry in pairs(D.catalog) do
            if groupData(entry)==selected then values[id]=entry.name; orders[id]=entry.order or 99999 end
        end
        return values,ordered(values,orders)
    end
    local function chooseBoss()
        local values,sort=bosses()
        if not state.boss or not values[state.boss] then state.boss=sort[1] end
        return state.boss
    end
    local function abilities()
        local id=chooseBoss(); local result={}
        local entry=id and D.catalog[id]
        if not entry then return result end
        for _,spell in ipairs(entry.spells or {}) do result[D:Key(id,spell,'')]={spellId=spell} end
        for key,data in pairs(entry.extra or {}) do result[key]={spellId=data.spellId,text=data.text,icon=data.icon} end
        local lower=string.utf8lower or string.lower
        local query=lower(state.search)
        for key,data in pairs(result) do
            local name=data.spellId and GetSpellInfo(data.spellId)
            data.text=name or data.text or 'Заклинание'
            if data.spellId then data.text=data.text..' ['..data.spellId..']' end
            data.icon=(data.spellId and select(3,GetSpellInfo(data.spellId))) or data.icon or 'Interface\\Icons\\INV_Misc_QuestionMark'
            if query~='' and not lower(data.text):find(query,1,true) then result[key]=nil end
        end
        return result
    end
    local function rebuild()
        local args={}
        local data=abilities(); local values,orders={},{}
        for key,ability in pairs(data) do values[key]=ability.text; orders[key]=ability.spellId or 99999999 end
        for index,key in ipairs(ordered(values,orders)) do
            local ability=data[key]
            ability.key=key
            args['ability'..index]={type='toggle',name=ability.text,order=index,width='full',
                dialogControl=D.spellWidgetRegistered and 'PhoenixPanelSpellCheck' or nil,
                image=function() return ability.icon end,imageCoords={0.08,0.92,0.08,0.92},arg=ability,
                desc=ability.spellId and ('Игровое описание: заклинание '..ability.spellId) or 'Именованный таймер DBM; отдельного игрового заклинания нет.',
                get=function() return cfg().selected[key]~=false end,
                set=function(info,value) if value then cfg().selected[key]=nil else cfg().selected[key]=false end; apply() end}
        end
        if not next(args) then args.empty={type='description',name='Нет подходящих таймеров. Для дополнительных способностей загрузите модуль этого босса в DBM и обновите список.',order=1} end
        group.args.spells.args=args
    end
    group.args={
        pack={type='select',name=kind=='RAID' and 'Рейд' or 'Подземелье',order=1,
            values=function() return (groups()) end,sorting=function() local _,sort=groups(); return sort end,
            get=chooseGroup,set=function(info,value) state.pack=value; state.boss=nil; state.search=''; rebuild() end},
        boss={type='select',name='Босс',order=2,values=function() return (bosses()) end,
            sorting=function() local _,sort=bosses(); return sort end,get=chooseBoss,
            set=function(info,value) state.boss=value; state.search=''; rebuild() end},
        search={type='input',name='Поиск способностей',order=3,get=function() return state.search end,
            set=function(info,value) state.search=value; rebuild() end},
        refresh={type='execute',name='Обновить из DBM',order=4,func=function() D:RefreshCatalog(); rebuild(); apply() end},
        all={type='execute',name='Выбрать показанные',order=5,func=function() for key in pairs(abilities()) do cfg().selected[key]=nil end; apply() end},
        none={type='execute',name='Снять показанные',order=6,func=function() for key in pairs(abilities()) do cfg().selected[key]=false end; apply() end},
        spells={type='group',name='Отслеживать способности',guiInline=true,order=7,args={}}
    }
    rebuild()
    return group
end

function A:InsertDBMOptions(parent)
    registerSpellWidget()
    parent.dbm={type='group',name='DBM',order=7,childGroups='tree',args={
        appearance={type='group',name='Оформление',order=1,
            get=function(info) return cfg()[info[#info]] end,
            set=function(info,value) cfg()[info[#info]]=value; apply() end,args={
                enabled=toggle('Включить панель DBM',1),stack=toggle('Стакать одинаковые способности',2),desaturate=toggle('Обесцвечивание',3),keepAspect=toggle('Сохранить соотношение размеров',4),
                size=range('Размер',5,6,60),height=range('Высота (без сохранения пропорций)',6,6,60),
                perRow=range('Кол-во в ряду',7,1,20),rows=range('Рядов',8,1,5),spacing=range('Отступ',9,0,60),
                x=range('Отступ по X',10,-100,100),y=range('Отступ по Y',11,-100,100),anchor=selectOption('Точка фиксации',12,points),
                growX=selectOption('Рост по X',13,{LEFT='Влево',RIGHT='Вправо'}),growY=selectOption('Рост по Y',14,{UP='Вверх',DOWN='Вниз'}),
                sort=selectOption('Сортировать по',15,{remaining='Оставшееся время',name='Название',spell='ID способности'}),
                descending=toggle('Нисходящая сортировка',16),
                test={type='execute',name=function() return D.testUntil and 'Остановить тест' or 'Тест' end,order=17,func=function() D:Test() end,disabled=function() return not cfg().enabled end},
                nativeTest={type='execute',name='Тест через DBM',order=17.1,func=function() D:NativeTest() end,disabled=function() return not cfg().enabled end},
                diagnostics={type='execute',name='Проверка подключения',order=17.2,func=function() D:Report() end},
                status={type='description',order=18,width='full',name=function()
                    return D.attached and 'DBM подключён. Большие таймеры отображаются на отдельной панели, независимо от выбранной цели. Перемещение: ElvUI → Перенос рамок.' or 'DBM не загружен. Тест оформления доступен без DBM.'
                end},
                count=textGroup('count','Количество стаков / номер применения DBM',20),duration=textGroup('duration','Длительность',21)
            }},

        abilities={type='group',name='Выбор способностей',order=2,childGroups='tab',args={
            raids=browser('RAID','Рейды',1),
            dungeons=browser('PARTY','Подземелья',2)
        }}
    }}
end

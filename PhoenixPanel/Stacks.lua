local A=PhoenixPanel
local T=A.Abilities
local E=ElvUI[1]
local points={TOPLEFT='TOPLEFT',TOP='TOP',TOPRIGHT='TOPRIGHT',LEFT='LEFT',CENTER='CENTER',RIGHT='RIGHT',BOTTOMLEFT='BOTTOMLEFT',BOTTOM='BOTTOM',BOTTOMRIGHT='BOTTOMRIGHT'}
A.defaults.abilities.appearance.stacks={show=true,font='DEFAULT',size=14,outline='OUTLINE',point='BOTTOMRIGHT'}

function T:StackConfig(p)
    if type(p.stacks)~='table' then p.stacks={} end
    local c=p.stacks
    if c.mode~='other' then c.mode='own' end
    if c.unit~='player' and c.unit~='target' then c.unit=p.kind=='debuff' and 'target' or 'player' end
    if c.kind~='buff' and c.kind~='debuff' then c.kind=p.kind=='debuff' and 'debuff' or 'buff' end
    if type(c.sources)~='table' then c.sources={} end
    return c
end

function T:StackTotal(p)
    local c=self:StackConfig(p)
    local sources=c.mode=='own' and {{id=p.spellId,unit=c.unit,kind=c.kind}} or c.sources
    local onlyMine=c.mode=='own' and p.onlyMine and (p.kind=='buff' or p.kind=='debuff')
    local total=0;local seen={}
    for _,source in ipairs(sources) do
        local id=tonumber(source.id)
        if id and (source.unit=='player' or source.unit=='target') and (source.kind=='buff' or source.kind=='debuff') then
            local key=source.unit..':'..source.kind..':'..id
            if not seen[key] then
                seen[key]=true
                local filter=source.kind=='buff' and 'HELPFUL' or 'HARMFUL'
                for _,aura in ipairs(self:Auras(source.unit,filter)[id] or {}) do
                    if (aura.expiration==0 or aura.expiration>GetTime())
                        and (not onlyMine or (aura.caster and UnitIsUnit(aura.caster,'player'))) then
                        total=total+math.max(1,tonumber(aura.count) or 0)
                    end
                end
            end
        end
    end
    return total
end

local evaluate=T.Evaluate
function T:Evaluate(p,inspect,noReplacement)
    local item=evaluate(self,p,inspect,noReplacement)
    if item and p.kind~='resource' and p.stacks and p.stacks.enabled then item.trackedStacks=self:StackTotal(p) end
    return item
end

local validate=T.Validate
function T:Validate()
    validate(self)
    local style=self:Config().appearance.stacks
    if type(style)~='table' then style=self.Copy(A.defaults.abilities.appearance.stacks); self:Config().appearance.stacks=style end
    if type(style.show)~='boolean' then style.show=true end
    if type(style.font)~='string' or style.font=='' then style.font='DEFAULT' end
    local n=tonumber(style.size) or 14;if n~=n then n=14 end;style.size=math.max(4,math.min(60,n))
    if not points[style.point] then style.point='BOTTOMRIGHT' end
    local outlines={['']=true,OUTLINE=true,THICKOUTLINE=true,['MONOCHROME,OUTLINE']=true}
    if not outlines[style.outline] then style.outline='OUTLINE' end
    for _,p in ipairs(self:Config().entries) do
        local c=self:StackConfig(p);c.enabled=c.enabled==true
        local sources={}
        for i=1,math.min(30,#c.sources) do
            local source=c.sources[i]
            if type(source)=='table' then
                local id=tonumber(source.id)
                if id and id>0 and id<2147483648 and id==math.floor(id) then
                    sources[#sources+1]={id=id,unit=source.unit=='target' and 'target' or 'player',kind=source.kind=='debuff' and 'debuff' or 'buff'}
                end
            end
        end
        c.sources=sources
    end
end

local render=T.Render
function T:Render(plate,items)
    render(self,plate,items)
    local h=self.holders[plate];if not h then return end
    local style=self:Config().appearance.stacks
    for i,icon in ipairs(h.icons) do
        local item=items[i]
        if icon:IsShown() and item and item.trackedStacks~=nil then
            if not icon.stackSum then icon.stackSum=icon.textLayer:CreateFontString(nil,'OVERLAY','GameFontNormal') end
            icon.count:Hide()
            if style.show then
                local text=icon.stackSum
                text:SetText(tostring(item.trackedStacks))
                local cfg=self.Copy(style);cfg.size=math.max(1,math.min(style.size,icon:GetHeight()-4));cfg.x=0;cfg.y=0
                self:TextStyle(text,cfg)
                local width=math.max(1,icon:GetWidth()-4)
                if text.GetStringWidth then
                    local actual=text:GetStringWidth()
                    if actual and actual>width then cfg.size=math.max(1,cfg.size*width/actual);self:TextStyle(text,cfg) end
                end
                -- ApplyFont intentionally clamps ordinary UI text to >=4.
                -- A very small icon may require smaller text to stay inside it.
                if cfg.size<4 then
                    local font,_,flags=text:GetFont()
                    if font then pcall(text.SetFont,text,font,cfg.size,flags) end
                end
                text:ClearAllPoints();text:SetPoint('TOPLEFT',icon,'TOPLEFT',2,-2);text:SetPoint('BOTTOMRIGHT',icon,'BOTTOMRIGHT',-2,2)
                text:SetJustifyH(style.point:find('LEFT',1,true) and 'LEFT' or (style.point:find('RIGHT',1,true) and 'RIGHT' or 'CENTER'))
                text:SetJustifyV(style.point:find('TOP',1,true) and 'TOP' or (style.point:find('BOTTOM',1,true) and 'BOTTOM' or 'MIDDLE'))
                if text.SetWordWrap then text:SetWordWrap(false) end
                text:Show()
            elseif icon.stackSum then icon.stackSum:Hide() end
        else
            icon.count:Show()
            if icon.stackSum then icon.stackSum:Hide() end
        end
    end
end

local addOptions=T.AddRotationOptions
function T:AddRotationOptions(args,getDraft,triggerFields,stackFields)
    addOptions(self,args,getDraft,triggerFields)
    args=stackFields or args
    local function p() return getDraft() end
    local function cfg() return p() and T:StackConfig(p()) end
    local form,owner={unit='player',kind='buff',id=''},nil
    local function input()
        if owner~=p() then owner=p();form={unit='player',kind='buff',id=''} end
        return form
    end
    local function valid(_,value)
        local id=tonumber(value)
        return id and id>0 and id<2147483648 and id==math.floor(id) and GetSpellInfo(id) and true or 'Введите ID существующего эффекта.'
    end
    args.stackEnabled={type='toggle',name='Отслеживать стаки',order=7.7,hidden=function() return not p() or p().kind=='resource' end,
        get=function() return cfg() and cfg().enabled or false end,set=function(_,v) cfg().enabled=v end}
    local group={type='group',name='Источники стаков',order=7.8,guiInline=true,hidden=function() return not cfg() or not cfg().enabled end,
        get=function(info) return cfg() and cfg()[info[#info]] end,set=function(info,v) cfg()[info[#info]]=v;T.auraCacheTime=nil end,args={
            mode={type='select',name='Источник',order=1,values={own='Свой эффект',other='Другие эффекты'}},
            unit={type='select',name='На ком свой эффект',order=2,values={player='Игрок',target='Цель'},hidden=function() return not cfg() or cfg().mode~='own' end},
            kind={type='select',name='Свой эффект',order=3,values={buff='Баф',debuff='Дебаф'},hidden=function() return not cfg() or cfg().mode~='own' end},
            info={type='description',order=4,name='«Свой» использует ID отслеживаемой способности. Если ID накладываемого эффекта другой, выберите «Другие». Активный эффект без стаков = 1, отсутствующий = 0. Повтор одного ID на том же юните и с тем же типом не удваивает сумму.'}
        }}
    args.stackSources=group
    local other={type='group',name='Другие эффекты',order=5,guiInline=true,hidden=function() return not cfg() or cfg().mode~='other' end,args={}}
    group.args.other=other
    other.args.id={type='input',name='ID добавляемого эффекта',order=1,get=function() return input().id end,set=function(_,v) input().id=v end,validate=valid}
    other.args.unit={type='select',name='На ком',order=2,values={player='Игрок',target='Цель'},get=function() return input().unit end,set=function(_,v) input().unit=v end}
    other.args.kind={type='select',name='Тип эффекта',order=3,values={buff='Баф',debuff='Дебаф'},get=function() return input().kind end,set=function(_,v) input().kind=v end}
    other.args.add={type='execute',name='Добавить эффект',order=4,disabled=function() return not cfg() or #cfg().sources>=30 or valid(nil,input().id)~=true end,func=function()
        local f=input();if valid(nil,f.id)~=true or #cfg().sources>=30 then return end
        cfg().sources[#cfg().sources+1]={id=tonumber(f.id),unit=f.unit,kind=f.kind};f.id='';T.auraCacheTime=nil
    end}
    for i=1,30 do
        local index=i
        local function source() return cfg() and cfg().sources[index] end
        other.args['source'..i]={type='group',name=function() local s=source();return index..'. '..(s and (GetSpellInfo(s.id) or tostring(s.id)) or '') end,
            order=i+4,guiInline=true,hidden=function() return not source() end,
            get=function(info) return source() and source()[info[#info]] end,set=function(info,v) if source() then source()[info[#info]]=v;T.auraCacheTime=nil end end,args={
                id={type='input',name='ID эффекта',order=1,validate=valid,get=function() return source() and tostring(source().id) or '' end,set=function(_,v) source().id=tonumber(v);T.auraCacheTime=nil end},
                unit={type='select',name='На ком',order=2,values={player='Игрок',target='Цель'}},
                kind={type='select',name='Тип эффекта',order=3,values={buff='Баф',debuff='Дебаф'}},
                remove={type='execute',name='Удалить',order=4,func=function() table.remove(cfg().sources,index);T.auraCacheTime=nil end}
            }}
    end
end

function T:AddStackAppearance(appearance)
    local function style() return T:Config().appearance.stacks end
    local function fonts()
        local v={DEFAULT='Шрифт клиента'}
        if E.Libs.LSM then for name in pairs(E.Libs.LSM:HashTable('font')) do v[name]=name end end
        v[style().font]=style().font;return v
    end
    appearance.args.stacks={type='group',name='Стаки — сумма внутри иконки',order=23,guiInline=true,
        get=function(info) return style()[info[#info]] end,set=function(info,v) style()[info[#info]]=v;T:Apply() end,args={
            show={type='toggle',name='Показывать',order=1},font={type='select',name='Шрифт',order=2,values=fonts},
            size={type='range',name='Размер шрифта',order=3,min=4,max=60,step=1},
            outline={type='select',name='Обводка',order=4,values={['']='Без обводки',OUTLINE='Outline',THICKOUTLINE='Thick outline',['MONOCHROME,OUTLINE']='Monochrome outline'}},
            point={type='select',name='Положение внутри иконки',order=5,values=points},
            info={type='description',order=6,name='Отдельное оформление суммы стаков. Размер ограничивается границами иконки; число размещается внутри с небольшим отступом.'}
        }}
end

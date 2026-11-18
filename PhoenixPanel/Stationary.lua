local A=PhoenixPanel
local T=A.Abilities
local S=setmetatable({
    holders={},revision=0,auraCache={},stationary=true,
    units=T.units,resources=T.resources,autoResources=T.autoResources
},{__index=function(_,key)
    if type(T[key])=='function' then return T[key] end
end})
A.Stationary=S
A.defaults.stationary=T.Copy(A.defaults.abilities)
S.kinds={spell=T.kinds.spell,buff=T.kinds.buff,debuff=T.kinds.debuff,item='Предмет'}

function S:Config()
    return A.db.stationary
end

local function itemInfo(id)
    if GetItemInfo then
        local name,_,_,_,_,_,_,_,equipSlot,icon=GetItemInfo(id)
        if name then return name,icon,equipSlot end
    end
    return 'Предмет №'..id,GetItemIcon and GetItemIcon(id)
end

function S:Find(id,kind)
    if kind~='item' then return T.Find(self,id,kind) end
    id=tonumber(id)
    if not id or id<1 or id>2147483647 or id~=math.floor(id) then
        return nil,'Введите целый положительный ID предмета.'
    end
    local name,icon=itemInfo(id)
    return {kind=kind,itemId=id,name=name,icon=icon,enabled=true}
end

local function evaluateItem(p)
    local name,icon,equipSlot=itemInfo(p.itemId)
    local item={id=p.uid,itemId=p.itemId,text=name,icon=icon or p.icon,remaining=0,total=0,multiplicity=1,available=false}
    local count=GetItemCount and GetItemCount(p.itemId) or 0
    local equipped=IsEquippedItem and IsEquippedItem(p.itemId)
    equipped=equipped==true or equipped==1
    local requiresEquipment=equipSlot and equipSlot~='' and equipSlot~='INVTYPE_NON_EQUIP'
    item.count=count
    if count<=0 and not equipped then
        item.reason='Предмета нет в сумках или экипировке.'
    elseif requiresEquipment and IsEquippedItem and not equipped then
        item.reason='Предмет не экипирован.'
    elseif GetItemCooldown then
        local start,duration,enabled=GetItemCooldown(p.itemId)
        start=tonumber(start)
        duration=tonumber(duration)
        if start and duration and start==start and duration>0 and duration<=604800 then
            local now=GetTime()
            if start>now+2147483.648 then start=start-4294967.296 end
            item.remaining=math.max(0,start+duration-now)
            item.total=duration
        end
        item.paused=enabled==0 or enabled==false
        if item.paused then
            item.reason='Использован, перезарядка ещё не началась.'
        elseif item.remaining>0 then
            item.reason='Предмет перезаряжается.'
        elseif IsUsableItem then
            local usable=IsUsableItem(p.itemId)
            item.available=usable==true or usable==1
            if not item.available then item.reason='Сейчас нельзя использовать предмет.' end
        else
            item.available=true
        end
    else
        item.reason='Клиент не сообщает перезарядку предмета.'
    end
    item.fade=not item.available
    return item
end

function S:Evaluate(p)
    if p.kind=='item' then return evaluateItem(p) end
    return T.Evaluate(self,p,true,true)
end

function S:Tick()
    if self.shuttingDown or not A.db or not A.db.stationary then return end
    local cfg=self:Config()
    if not cfg.appearance.enabled then self:HideAll(); return end

    local anchor=self:Anchor()
    if not anchor or not anchor:IsShown() then self:HideAll(); return end

    local items={}
    local limit=cfg.appearance.perRow*cfg.appearance.rows
    for _,entry in ipairs(cfg.entries) do
        if entry.enabled then
            -- Cooldown and aura state affect the artwork, while list order sets the slot.
            items[#items+1]=self:Evaluate(entry)
            if #items==limit then break end
        end
    end
    self:Render(anchor,items)
end

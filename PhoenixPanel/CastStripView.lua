local A=PhoenixPanel
local T=A.Abilities

local moveTime=0.24
local castTime=0.5
local castLevelOffset=16

local function itemKey(item)
    return tostring(item.id)..':'..tostring(item.spellId or item.itemId)
end

local function place(h,icon,x,y)
    icon.stripX,icon.stripY=x,y
    icon:ClearAllPoints()
    icon:SetPoint('TOPLEFT',h.frame,'TOPLEFT',x,y)
end

local function recycle(state,icon)
    icon:Hide()
    if icon.stripLayers then
        for _,layer in ipairs(icon.stripLayers) do layer.frame:SetFrameLevel(layer.level) end
        icon.stripLayers=nil
    end
    icon:EnableMouse(true)
    icon:SetAlpha(1)
    icon.alphaValue=1
    icon.layout=nil
    icon.stripX,icon.stripY,icon.stripMove=nil,nil,nil
    icon.stripWidth,icon.stripHeight=nil,nil
    state.pool[#state.pool+1]=icon
end

local function liftCastIcon(h,icon)
    local highest=h.frame:GetFrameLevel()
    for _,other in ipairs(h.icons) do
        highest=math.max(highest,other:GetFrameLevel(),(other.textLayer or other):GetFrameLevel())
    end
    local offset=highest-icon:GetFrameLevel()+castLevelOffset
    local layers={}
    for _,frame in ipairs({icon,icon.cooldown,icon.textLayer}) do
        layers[#layers+1]={frame=frame,level=frame:GetFrameLevel()}
    end
    for _,layer in ipairs(layers) do layer.frame:SetFrameLevel(layer.level+offset) end
    icon.stripLayers=layers
end

local function animate(h,state)
    local now=GetTime()
    local busy=false
    for _,icon in ipairs(h.icons) do
        local move=icon.stripMove
        if move then
            local progress=math.min(1,(now-move.start)/moveTime)
            local eased=progress*progress*(3-2*progress)
            place(h,icon,move.fromX+(move.x-move.fromX)*eased,move.fromY+(move.y-move.fromY)*eased)
            if progress==1 then icon.stripMove=nil else busy=true end
        end
    end
    for icon,cast in pairs(state.departures) do
        local progress=math.min(1,(now-cast.start)/castTime)
        if progress==1 then
            state.departures[icon]=nil
            recycle(state,icon)
        else
            local width=cast.width*(1+0.5*progress)
            local height=cast.height*(1+0.5*progress)
            icon:SetSize(width,height)
            place(h,icon,cast.x-(width-cast.width)/2,cast.y+(height-cast.height)/2)
            icon:SetAlpha(1-progress)
            busy=true
        end
    end
    if not busy then h.frame:SetScript('OnUpdate',nil) end
end

local function startStrip(h)
    local state={pool=h.icons,active={},departures={},suppressed={}}
    for _,icon in ipairs(state.pool) do icon:Hide(); icon.layout=nil end
    h.icons={}
    h.castStrip=true
    h.castStripState=state
    state.update=function() animate(h,state) end
    return state
end

function T:PositionCastStripIcon(h,icon,x,y,width,height)
    if icon.stripWidth~=width or icon.stripHeight~=height then
        icon:SetSize(width,height)
        icon.stripWidth,icon.stripHeight=width,height
    end
    if not icon.stripX then
        place(h,icon,x,y)
        return
    end
    local move=icon.stripMove
    if move and move.x==x and move.y==y then return end
    if icon.stripX==x and icon.stripY==y then
        icon.stripMove=nil
        return
    end
    icon.stripMove={start=GetTime(),fromX=icon.stripX,fromY=icon.stripY,x=x,y=y}
    h.frame:SetScript('OnUpdate',h.castStripState.update)
end

function T:RenderCastStrip(plate,items)
    local h=self.holders[plate] or self:NewHolder(plate)
    local state=h.castStripState or startStrip(h)
    state.items=items
    local now=GetTime()
    for key,expires in pairs(state.suppressed) do
        if expires<=now then state.suppressed[key]=nil end
    end

    local visible,keys={},{}
    local capacity=self:Config().appearance.perRow
    for i,item in ipairs(items) do
        if state.suppressed[itemKey(item)] then
            item=i==1 and self:AutoItem() or nil
        end
        if item then
            visible[#visible+1]=item
            keys[itemKey(item)]=true
            if #visible==capacity then break end
        end
    end
    for key,icon in pairs(state.active) do
        if not keys[key] and not state.departures[icon] then recycle(state,icon) end
    end

    local active={}
    h.icons={}
    for i,item in ipairs(visible) do
        local key=itemKey(item)
        local icon=state.active[key] or table.remove(state.pool)
        h.icons[i]=icon or self:Icon(h,i)
        active[key]=h.icons[i]
    end
    state.active=active
    self:Render(plate,visible)
end

local function castIcon(h,spellId,spellName)
    local nameMatch
    for _,icon in ipairs(h.icons) do
        local item=icon.abilityState
        if item and item.spellId and not item.autoAttack and icon:IsShown() then
            if spellId and item.spellId==spellId then return icon end
            if not nameMatch and spellName and GetSpellInfo(item.spellId)==spellName then nameMatch=icon end
        end
    end
    return nameMatch
end

function T:OnStripCast(spellId,spellName)
    for plate,h in pairs(self.holders) do
        local state=h.castStripState
        if state and h.frame:IsVisible() then
            local icon=castIcon(h,spellId,spellName)
            if icon then
                local started=GetTime()
                state.suppressed[itemKey(icon.abilityState)]=started+castTime
                state.departures[icon]={start=started,x=icon.stripX,y=icon.stripY,width=icon.stripWidth,height=icon.stripHeight}
                icon.stripMove=nil
                liftCastIcon(h,icon)
                icon:EnableMouse(false)
                if GameTooltip:IsOwned(icon) then GameTooltip:Hide() end
                h.frame:SetScript('OnUpdate',state.update)
                self:RenderCastStrip(plate,state.items)
                return
            end
        end
    end
end

local function resetHolder(h)
    local state=h.castStripState
    if not state then return end
    h.frame:SetScript('OnUpdate',nil)
    for _,icon in ipairs(h.icons) do recycle(state,icon) end
    for icon in pairs(state.departures) do recycle(state,icon) end
    h.icons=state.pool
    h.castStripState=nil
    h.castStrip=nil
    h.layout=nil
end

function T:ResetCastStrip(h)
    if h then
        resetHolder(h)
    else
        for _,holder in pairs(self.holders) do resetHolder(holder) end
    end
end

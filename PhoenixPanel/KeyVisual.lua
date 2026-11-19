local A=PhoenixPanel
local E=ElvUI[1]
local T=A.Abilities

local pulseTime=0.2
local multiBars={'MultiBarBottomLeft','MultiBarBottomRight','MultiBarRight','MultiBarLeft'}
local multiCommands={}
for i,bar in ipairs(multiBars) do multiCommands[bar]='MULTIACTIONBAR'..i..'BUTTON' end

local function mouseKey(key)
    return key:match('BUTTON%d+$') or key:match('MOUSEWHEELUP$') or key:match('MOUSEWHEELDOWN$')
end

local function clickFrame(command)
    if type(command)~='string' then return end
    local name,mouse=command:match('^CLICK ([^:%s]+):([^%s]*)$')
    if mouse=='' or mouse=='LeftButton' then return name end
    return command:match('^CLICK ([^:%s]+)$')
end

local function nativeBinding(command)
    return (command:match('^ACTIONBUTTON%d+$') and type(ActionButtonDown)=='function')
        or (command:match('^MULTIACTIONBAR[1-4]BUTTON%d+$') and type(MultiActionButtonDown)=='function')
end

local function elvButton(command)
    local bars=E.GetModule and E:GetModule('ActionBars',true)
    local name=clickFrame(command)
    for _,bar in pairs(bars and bars.handledBars or {}) do
        for i,button in ipairs(bar.buttons or {}) do
            local binding=bar.bindButtons and (bar.bindButtons..i)
            if not binding and button.GetBindingAction then binding=button:GetBindingAction() end
            local frame=button:GetName()
            if frame and (name==frame or binding==command) then
                return button,binding,frame
            end
        end
    end
end

local function reachesRoute(command,route)
    if not command or command=='' then return false end
    return command==route.action or command==route.binding
        or (route.frame and clickFrame(command)==route.frame)
end

local function observeKey(key)
    if type(key)~='string' or key=='' or mouseKey(key)
        or not GetBindingAction or not GetBindingKey then return end
    local action=GetBindingAction(key,true)
    if not action or action=='' then return end
    local button,binding,frame=elvButton(action)
    if button and not button.HookScript then button=nil end
    local stock=nativeBinding(action)
    if not button and not stock then return end
    local route={key=key,action=action,button=button,binding=binding,frame=frame,stock=stock and action}

    -- A secure button's callbacks identify the button, not which of several
    -- bindings activated it. Do not attribute an ambiguous route to a key.
    local function hasAlias(bound)
        for _,other in ipairs({GetBindingKey(bound)}) do
            if other~=key and reachesRoute(GetBindingAction(other,true),route) then return true end
        end
    end
    if hasAlias(action) or (binding and binding~=action and hasAlias(binding)) then return end
    if frame then
        local command='CLICK '..frame
        for _,suffix in ipairs({'',':',':LeftButton'}) do
            if command..suffix~=action and hasAlias(command..suffix) then return end
        end
    end
    return route
end

function T:CanObserveVisualKey(key)
    return observeKey(key)~=nil
end

local function paint(icon,strength)
    icon.pressTint:SetAlpha((icon.pressTexture and 0.8 or 0.15)*strength)
    for _,edge in ipairs(icon.pressEdges) do edge:SetAlpha(strength) end
end

local function makePulse(icon)
    local tint=icon.textLayer:CreateTexture(nil,'ARTWORK')
    tint:SetAllPoints(icon)
    icon.pressTint=tint
    icon.pressEdges={}
    for i=1,4 do
        local edge=icon.textLayer:CreateTexture(nil,'OVERLAY')
        edge:SetTexture(0.58,0.85,1,1)
        if i<=2 then
            local left,right=i==1 and 'TOPLEFT' or 'BOTTOMLEFT',i==1 and 'TOPRIGHT' or 'BOTTOMRIGHT'
            edge:SetPoint(left,icon,left,0,0)
            edge:SetPoint(right,icon,right,0,0)
            edge:SetHeight(2)
        else
            local top,bottom=i==3 and 'TOPLEFT' or 'TOPRIGHT',i==3 and 'BOTTOMLEFT' or 'BOTTOMRIGHT'
            edge:SetPoint(top,icon,top,0,0)
            edge:SetPoint(bottom,icon,bottom,0,0)
            edge:SetWidth(2)
        end
        icon.pressEdges[i]=edge
    end
    icon:HookScript('OnHide',function() paint(icon,0) end)
end

local function updatePulses(_,state)
    local now=GetTime()
    for icon,pulse in pairs(state.pulses) do
        local item=icon.abilityState
        local remaining=(pulse.expires-now)/pulseTime
        if not icon:IsVisible() or not item or item.id~=pulse.id or item.spellId~=pulse.spellId
            or item.stripOccurrence~=pulse.occurrence or remaining<=0 then
            paint(icon,0)
            state.pulses[icon]=nil
        else
            paint(icon,remaining)
        end
    end
    if not next(state.pulses) then state.driver:SetScript('OnUpdate',nil) end
end

local function flash(T,state,route,button)
    if not route or not reachesRoute(GetBindingAction(route.key,true),route) then return end
    -- The action bar only reports the bound key. The PhoenixPanel assignment
    -- selects the visual target, even if the button is empty or runs a macro.
    for _,h in pairs(T.holders) do
        if h.frame:IsVisible() then
            for _,icon in ipairs(h.icons) do
                local item=icon.abilityState
                local assigned=item and state.entries[item.id]
                local shared=item and state.sharedKeys[item.spellId]
                if icon:IsVisible() and item and item.spellId
                    and (assigned==route.key or (not assigned and shared and shared[route.key])) then
                    if not icon.pressTint then makePulse(icon) end
                    local pushed=button and button.GetPushedTexture and button:GetPushedTexture()
                    local texture=pushed and pushed.GetTexture and pushed:GetTexture()
                    icon.pressTexture=type(texture)=='string' or type(texture)=='number'
                    if icon.pressTexture then
                        icon.pressTint:SetTexture(texture)
                        icon.pressTint:SetTexCoord(pushed:GetTexCoord())
                    else
                        icon.pressTint:SetTexture(0.58,0.85,1,1)
                        icon.pressTint:SetTexCoord(0,1,0,1)
                    end
                    state.pulses[icon]={id=item.id,spellId=item.spellId,occurrence=item.stripOccurrence,expires=GetTime()+pulseTime}
                    paint(icon,1)
                    state.driver:SetScript('OnUpdate',state.update)
                    return
                end
            end
        end
    end
end

local function watchButton(T,state,button)
    if state.hooked[button] then return end
    state.hooked[button]=true
    local mouseChanged
    local function physicalMouse()
        mouseChanged=GetTime()
    end
    button:HookScript('OnMouseDown',physicalMouse)
    button:HookScript('OnMouseUp',physicalMouse)
    button:HookScript('PreClick',function(frame,mouse)
        if (mouse and mouse~='' and mouse~='LeftButton')
            or (mouseChanged and GetTime()-mouseChanged<0.05) then return end
        local pressed=IsMouseButtonDown and IsMouseButtonDown('LeftButton')
        if (pressed==true or pressed==1) and (not frame.IsMouseOver or frame:IsMouseOver()) then return end
        flash(T,state,state.buttons[frame],frame)
    end)
end

function T:InitializeKeyVisual()
    if self.keyVisual then return end
    local driver=CreateFrame('Frame')
    local state={driver=driver,pulses={},hooked={},buttons={},commands={},entries={},sharedKeys={}}
    self.keyVisual=state
    self.keyVisualDriver=driver
    state.update=function(frame) updatePulses(frame,state) end
    driver:RegisterEvent('UPDATE_BINDINGS')
    driver:RegisterEvent('PLAYER_REGEN_ENABLED')
    driver:SetScript('OnEvent',function() self:RefreshVisualKeys() end)
    if type(ActionButtonDown)=='function' then
        hooksecurefunc('ActionButtonDown',function(id)
            local route=state.commands['ACTIONBUTTON'..id]
            if not route then return end
            local prefix='ActionButton'
            if VehicleMenuBar and VehicleMenuBar:IsShown() and id<=(VEHICLE_MAX_ACTIONBUTTONS or 0) then
                prefix='VehicleMenuBarActionButton'
            elseif BonusActionBarFrame and BonusActionBarFrame:IsShown() then
                prefix='BonusActionButton'
            end
            flash(self,state,route,_G[prefix..id])
        end)
    end
    if type(MultiActionButtonDown)=='function' then
        hooksecurefunc('MultiActionButtonDown',function(bar,id)
            local prefix=multiCommands[bar]
            local route=prefix and state.commands[prefix..id]
            if route then flash(self,state,route,_G[bar..'Button'..id]) end
        end)
    end
    local bars=E.GetModule and E:GetModule('ActionBars',true)
    if bars and type(bars.ReassignBindings)=='function' then
        hooksecurefunc(bars,'ReassignBindings',function() self:RefreshVisualKeys() end)
    end
    self:RefreshVisualKeys()
end

function T:RefreshVisualKeys()
    local state=self.keyVisual
    if not state then return end
    local inCombat=InCombatLockdown and InCombatLockdown()
    for icon in pairs(state.pulses) do paint(icon,0) end
    state.pulses={}
    state.driver:SetScript('OnUpdate',nil)
    state.buttons,state.commands,state.entries,state.sharedKeys={},{},{},{}
    if not A.db or not A.db.abilities or self:IsProfileOff() then return end
    local cfg=self:Config()
    local share=cfg.panelMode=='strip' and cfg.stripHighestOnly
    local keys={}
    for _,entry in ipairs(cfg.entries) do
        local key=entry.enabled and entry.kind=='spell' and entry.pressKey
        if type(key)=='string' and key~='' then
            if keys[key]==nil then keys[key]=observeKey(key) or false end
            local route=keys[key]
            state.entries[entry.uid]=key
            if route then
                if route.button then
                    if not inCombat or state.hooked[route.button] then
                        state.buttons[route.button]=route
                        watchButton(self,state,route.button)
                    end
                end
                if route.stock then state.commands[route.stock]=route end
                if share and entry.spellId then
                    local shared=state.sharedKeys[entry.spellId] or {}
                    shared[key]=true
                    state.sharedKeys[entry.spellId]=shared
                end
            end
        end
    end
end

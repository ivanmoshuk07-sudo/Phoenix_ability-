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

local function elvButton(command)
    local bars=E.GetModule and E:GetModule('ActionBars',true)
    local name=command:match('^CLICK ([^:]+):LeftButton$')
    for _,bar in pairs(bars and bars.handledBars or {}) do
        for i,button in ipairs(bar.buttons or {}) do
            local binding=bar.bindButtons and (bar.bindButtons..i)
            local frame=button:GetName()
            if name==frame or binding==command then
                return button,binding,'CLICK '..frame..':LeftButton'
            end
        end
    end
end

local function observeKey(key)
    if type(key)~='string' or key=='' or mouseKey(key)
        or not GetBindingAction or not GetBindingKey then return end
    local action=GetBindingAction(key,true)
    if not action or action=='' then return end
    local button,binding,click=elvButton(action)
    if button then
        if not button.HookScript then return end
    elseif not (action:match('^ACTIONBUTTON%d+$') and type(ActionButtonDown)=='function')
        and not (action:match('^MULTIACTIONBAR[1-4]BUTTON%d+$') and type(MultiActionButtonDown)=='function') then
        return
    end

    -- A secure button's callbacks identify the button, not which of several
    -- bindings activated it. Do not attribute an ambiguous route to a key.
    local function sameRoute(bound)
        for _,other in ipairs({GetBindingKey(bound)}) do
            if other~=key then
                local effective=GetBindingAction(other,true)
                if effective and effective~='' and (effective==action or effective==binding or effective==click) then
                    return true
                end
            end
        end
    end
    if sameRoute(binding or action) or (click and click~=binding and sameRoute(click)) then return end
    return {key=key,action=action,button=button}
end

function T:CanObserveVisualKey(key)
    return observeKey(key)~=nil
end

local function spellIdentity(spell,book)
    if type(spell)=='number' and not book then return spell end
    if GetSpellLink and spell then
        local link=GetSpellLink(spell,book)
        local id=link and tonumber(link:match('spell:(%d+)'))
        if id then return id end
    end
    if type(spell)=='string' and spell~='' then return nil,spell end
end

local function macroSpell(macro)
    if macro and GetMacroSpell then
        local spell=GetMacroSpell(macro)
        return spellIdentity(spell)
    end
end

local function buttonSpell(button,mouse)
    if not button then return end
    local function attribute(key)
        if SecureButton_GetModifiedAttribute and button.GetAttribute then
            return SecureButton_GetModifiedAttribute(button,key,mouse)
        elseif button.GetAttribute then
            return button:GetAttribute(key)
        end
    end
    local kind=attribute('type') or button._state_type
    if kind=='spell' then return spellIdentity(attribute('spell') or button._state_action) end
    if kind=='macro' then return macroSpell(attribute('macro')) end
    if kind and kind~='action' then return end
    local slot=attribute('action') or button._state_action or button.action
    if not slot or not GetActionInfo then return end
    local action,id,book,spellId=GetActionInfo(slot)
    if action=='spell' then
        if tonumber(spellId) then return tonumber(spellId) end
        if book=='spell' or book=='pet' then return spellIdentity(id,book) end
        return spellIdentity(id)
    elseif action=='macro' then
        return macroSpell(id)
    end
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

local function flash(T,state,route,button,mouse)
    if not route or GetBindingAction(route.key,true)~=route.action then return end
    local id,name=buttonSpell(button,mouse)
    if not id and not name then return end
    for _,h in pairs(T.holders) do
        if h.frame:IsVisible() then
            for _,icon in ipairs(h.icons) do
                local item=icon.abilityState
                if icon:IsVisible() and item and item.spellId and state.entries[item.id]==route.key
                    and (id==item.spellId or (not id and GetSpellInfo(item.spellId)==name)) then
                    if not icon.pressTint then makePulse(icon) end
                    local pushed=button.GetPushedTexture and button:GetPushedTexture()
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
        if mouse~='LeftButton' or (mouseChanged and GetTime()-mouseChanged<0.05)
            or (IsMouseButtonDown and IsMouseButtonDown(mouse) and frame:IsMouseOver()) then return end
        flash(T,state,state.buttons[frame],frame,mouse)
    end)
end

function T:InitializeKeyVisual()
    if self.keyVisual then return end
    local driver=CreateFrame('Frame')
    local state={driver=driver,pulses={},hooked={},buttons={},commands={},entries={}}
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
            flash(self,state,route,_G[prefix..id],'LeftButton')
        end)
    end
    if type(MultiActionButtonDown)=='function' then
        hooksecurefunc('MultiActionButtonDown',function(bar,id)
            local prefix=multiCommands[bar]
            local route=prefix and state.commands[prefix..id]
            if route then flash(self,state,route,_G[bar..'Button'..id],'LeftButton') end
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
    state.buttons,state.commands,state.entries={},{},{}
    if not A.db or not A.db.abilities or self:IsProfileOff() then return end
    local keys={}
    for _,entry in ipairs(self:Config().entries) do
        local key=entry.enabled and entry.kind=='spell' and entry.pressKey
        if type(key)=='string' and key~='' then
            if keys[key]==nil then keys[key]=observeKey(key) or false end
            local route=keys[key]
            if route then
                if route.button then
                    if not inCombat or state.hooked[route.button] then
                        state.buttons[route.button]=route
                        watchButton(self,state,route.button)
                    end
                else
                    state.commands[route.action]=route
                end
                state.entries[entry.uid]=key
            end
        end
    end
end

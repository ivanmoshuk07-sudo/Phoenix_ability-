local addonName=...
local E=ElvUI[1]
local A=PhoenixPanel
local M=E:NewModule('PhoenixPanelPlugin')
local copy=A.Abilities.Copy

local function importProfile(profile)
    local db={}
    local legacy=profile.standaloneNames
    if type(legacy)=='table' then
        for _,key in ipairs({'abilities','abilityProfiles','dbm'}) do
            if type(legacy[key])=='table' then db[key]=copy(legacy[key]) end
        end
    end
    profile.phoenixPanel=db

    local imported={}
    local movers=profile.movers
    if type(movers)=='table' then
        for _,suffix in ipairs({'AbilitiesMover','DBMMover'}) do
            local name='PhoenixPanel'..suffix
            local original=movers['StandaloneNames'..suffix]
            if movers[name]==nil and type(original)=='string' then
                movers[name]=original
                imported[name]=original
            end
        end
    end
    return imported
end

function M:BindProfile()
    local imported
    if type(E.db.phoenixPanel)~='table' then imported=importProfile(E.db) end
    A.db=E.db.phoenixPanel
    A.Fill(A.db,A.defaults)
    A.Abilities:PrepareProfiles()

    -- ElvUI restores movers before its post-UpdateAll hook. Apply positions
    -- imported on this profile switch to the two movers already created.
    for name,point in pairs(imported or {}) do
        local frame=_G[name]
        local delimiter=point:find('\031',1,true) and '\031' or ','
        if frame and frame.Point and strsplit then
            local anchor,relative,relativeAnchor,x,y=strsplit(delimiter,point)
            if anchor and relative and relativeAnchor and tonumber(x) and tonumber(y) then
                frame:ClearAllPoints()
                frame:Point(anchor,relative,relativeAnchor,tonumber(x),tonumber(y))
            end
        end
    end

    A.DBM:Apply()
    A.Abilities:Apply()
    A.Stationary:Apply()
    if A.RefreshAbilityOptions then A.RefreshAbilityOptions() end
    if A.RefreshStationaryOptions then A.RefreshStationaryOptions() end
end

function M:Initialize()
    if self.initialized then return end
    self.initialized=true
    if type(PhoenixPanelDB)~='table' then PhoenixPanelDB={} end
    A.state=PhoenixPanelDB
    self:BindProfile()
    A.DBM:Initialize()
    A.Abilities:Initialize()
    A.Abilities:InitializeKeyVisual()
    A.Stationary:Initialize()
    E.Libs.EP:RegisterPlugin(addonName,function() A:InsertOptions() end)
    hooksecurefunc(E,'UpdateAll',function() M:BindProfile() end)
end

E:RegisterModule(M:GetName(),function() M:Initialize() end)

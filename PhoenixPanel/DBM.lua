local A=PhoenixPanel
local E=ElvUI[1]
local D={records={},holders={},catalog=A.DBMCatalog or {}}
A.DBM=D
local inverse={TOP='BOTTOM',BOTTOM='TOP',TOPLEFT='BOTTOMLEFT',TOPRIGHT='BOTTOMRIGHT',LEFT='RIGHT',RIGHT='LEFT',BOTTOMLEFT='TOPLEFT',BOTTOMRIGHT='TOPRIGHT',CENTER='CENTER'}
local textDefaults={show=true,font='DEFAULT',size=12,outline='OUTLINE',point='BOTTOMRIGHT',x=0,y=2}
A.defaults.dbm={enabled=true,stack=true,desaturate=false,keepAspect=true,size=28,height=28,perRow=5,rows=1,spacing=2,x=0,y=5,anchor='TOPLEFT',growX='RIGHT',growY='UP',sort='remaining',descending=false,selected={},count=textDefaults,
    duration={show=true,swipe=true,font='DEFAULT',size=12,outline='OUTLINE',point='CENTER',x=0,y=0}}

function D:Key(modId,spellId,timerId)
    local n=tonumber(spellId)
    return tostring(modId)..'|'..(n and n>0 and ('s:'..n) or ('t:'..tostring(timerId):match('^[^\t]+')))
end

function D:Mod(id)
    if not DBM or type(DBM.GetModByName)~='function' then return end
    return DBM:GetModByName(tostring(id))
end

function D:Remember(id,text,duration,icon,kind,spellId,color,modId,keep,fade,name,guid,count)
    if not id or not modId then return end
    local key=self:Key(modId,spellId,id)
    self.records[id]={id=id,key=key,modId=tostring(modId),spellId=tonumber(spellId),text=text or name or tostring(id),icon=icon,guid=guid,count=count,demo=tostring(modId)=='TestMod'}
    -- DBM's own DemoMode has no encounter/NPC identity; keep it out of boss lists.
    if tostring(modId)=='TestMod' then return end
    local entry=self.catalog[tostring(modId)]
    if not entry then entry={pack='Загруженные модули',name=tostring(modId),spells={}}; self.catalog[tostring(modId)]=entry end
    entry.extra=entry.extra or {}
    entry.extra[key]={spellId=tonumber(spellId),text=name or text or tostring(id),icon=icon}
end

function D:RefreshCatalog()
    if not DBM then return end
    for _,mod in pairs(DBM.Mods or {}) do
        local id=tostring(mod.id)
        if id~='TestMod' then
        local entry=self.catalog[id]
        if not entry then entry={pack=mod.modId or 'Загруженные модули',name=id,spells={},order=9999}; self.catalog[id]=entry end
        entry.name=mod.localization and mod.localization.general and mod.localization.general.name or entry.name
        entry.extra=entry.extra or {}
        for _,timer in ipairs(mod.timers or {}) do
            local key=self:Key(id,timer.spellId,timer.id)
            entry.extra[key]={spellId=tonumber(timer.spellId),text=timer.name or timer.text or tostring(timer.id),icon=timer.icon}
            -- Covers a plugin loaded after a fight/timer has already started.
            for _,started in ipairs(timer.startedTimers or {}) do
                if not self.records[started] then
                    self:Remember(started,timer.name or timer.text,timer.timer,timer.icon,timer.type,timer.spellId,nil,id,nil,nil,timer.name)
                end
            end
        end
        end
    end
end

function D:Attach()
    if self.attached or not DBM or type(DBM.RegisterCallback)~='function' then return end
    self.attached=DBM
    DBM:RegisterCallback('DBM_TimerStart',function(event,...) D:Remember(...) end)
    DBM:RegisterCallback('DBM_TimerStop',function(event,id) D.records[id]=nil end)
    local function ended(event,mod)
        for id,rec in pairs(D.records) do
            if not mod or rec.modId==tostring(mod.id) then D.records[id]=nil end
        end
        D:Tick()
    end
    DBM:RegisterCallback('DBM_Wipe',ended)
    DBM:RegisterCallback('DBM_Kill',ended)
    self:RefreshCatalog()
end

function D:IsLarge(bar)
    return DBT and DBT.Options and DBT.Options.HugeBarsEnabled and not bar.dead and not bar.paused and not bar.isDummy and not bar.dummy and
        (bar.enlarged or bar.moving=='enlarge' or bar.moving=='nextEnlarge') and (not bar.frame or bar.frame:IsShown())
end

function D:CID(guid)
    if not guid then return end
    if guid:find('-',1,true) then
        local fields={}; for part in guid:gmatch('[^-]+') do fields[#fields+1]=part end
        return tonumber(fields[6])
    end
    return tonumber(guid:sub(8,12),16)
end

function D:Matches(rec,unit)
    local guid=UnitGUID(unit)
    if not guid then return false,'no-unit-guid' end
    if rec.demo then return UnitExists('target') and UnitGUID('target')==guid,'demo-target' end
    if rec.guid then return rec.guid==guid,'source-guid' end
    local mod=self:Mod(rec.modId)
    if not mod then return false,'module-not-found' end
    if mod.isDummyMod or mod.isTrashMod then return false,'dummy-or-trash-module' end
    local cid=self:CID(guid)
    local mobs=mod.multiMobPullDetection or (mod.combatInfo and mod.combatInfo.multiMobPullDetection)
    if type(mobs)=='table' and #mobs>1 then
        -- Shared encounter timers have no individual caster identity. Show only
        -- on the selected encounter member, never an unrelated target or add.
        if not UnitExists('target') or UnitGUID('target')~=guid then return false,'shared-timer-not-selected' end
        for _,id in ipairs(mobs) do
            if tonumber(id)==cid then return true,'selected-encounter-member' end
        end
        return false,'selected-unit-not-in-encounter'
    end
    local expected=tonumber(mod.creatureId or (mod.combatInfo and mod.combatInfo.mob))
    return expected~=nil and cid==expected,'creature-id:'..tostring(cid)..'/'..tostring(expected)
end

function D:CaptureFailure()
    if not InCombatLockdown() or not A.state then return end
    local now=GetTime()
    if self.lastFailureCapture and now-self.lastFailureCapture<10 then return end
    local large=0
    for bar in pairs(DBT and DBT.bars or {}) do if self:IsLarge(bar) then large=large+1 end end
    if large==0 then return end
    for _,h in pairs(self.holders) do
        if h.frame:IsShown() then
            for _,icon in ipairs(h.icons) do if icon:IsShown() then return end end
        end
    end
    self.lastFailureCapture=now
    local lines={'PhoenixPanel DBM: large bars without visible icons',
        'time='..tostring(now)..' attached='..tostring(self.attached~=nil)..' large='..large,
        'target='..tostring(UnitName('target'))..' guid='..tostring(UnitGUID('target'))}
    local np=E:GetModule('NamePlates',true)
    local visible={}
    for plate in pairs(np and np.Plates or {}) do
        if plate.unit and plate:IsShown() and #visible<20 then
            visible[#visible+1]=plate.unit
            lines[#lines+1]='plate '..plate.unit..' name='..tostring(UnitName(plate.unit))..' guid='..tostring(UnitGUID(plate.unit))..' healthShown='..tostring(plate.Health and plate.Health:IsShown())
        end
    end
    local n=0
    for bar in pairs(DBT and DBT.bars or {}) do
        if self:IsLarge(bar) and n<16 then
            n=n+1
            local rec=self.records[bar.id]
            lines[#lines+1]='bar='..tostring(bar.id)..' seconds='..tostring(bar.timer)..' record='..tostring(rec~=nil)
            if rec then
                lines[#lines+1]='mod='..tostring(rec.modId)..' source='..tostring(rec.guid)..' spell='..tostring(rec.spellId)..' selected='..tostring(A.db.dbm.selected[rec.key]~=false)
                for _,unit in ipairs(visible) do
                    local ok,why=self:Matches(rec,unit)
                    lines[#lines+1]='  '..unit..' match='..tostring(ok)..' reason='..tostring(why)
                end
            end
        end
    end
    A.state.dbmFailureReports=A.state.dbmFailureReports or {}
    local reports=A.state.dbmFailureReports
    reports[#reports+1]=table.concat(lines,'\n')
    if #reports>6 then table.remove(reports,1) end
end

function D:Collect(unit)
    local cfg=A.db.dbm
    local result,grouped={},{}
    for bar in pairs(DBT and DBT.bars or {}) do
        local rec=self.records[bar.id]
        if rec and cfg.selected[rec.key]~=false and self:IsLarge(bar) then
            local remaining=math.max(0,tonumber(bar.timer) or 0)
            if remaining>0 or bar.keep then
                local item={id=rec.id,key=rec.key,spellId=rec.spellId,text=rec.text,icon=rec.icon,remaining=remaining,total=tonumber(bar.totalTime) or remaining,count=rec.count,multiplicity=1,fade=bar.fade}
                local old=cfg.stack and grouped[rec.key]
                if old then
                    old.multiplicity=old.multiplicity+1
                    if remaining<old.remaining then
                        item.multiplicity=old.multiplicity
                        for k,v in pairs(item) do old[k]=v end
                        old.count=item.count
                    end
                else result[#result+1]=item; grouped[rec.key]=item end
            end
        end
    end
    return result
end

function D:Validate()
    local cfg=A.db.dbm
    local defaults=A.defaults.dbm
    for _,key in ipairs({'enabled','stack','desaturate','keepAspect','descending'}) do
        if type(cfg[key])~='boolean' then cfg[key]=defaults[key] end
    end
    local function number(t,key,default,min,max)
        local value=tonumber(t[key])
        if not value or value~=value then value=default end
        t[key]=math.floor(math.max(min,math.min(max,value)))
    end
    for key,limits in pairs({size={6,60},height={6,60},perRow={1,20},rows={1,5},spacing={0,60},x={-100,100},y={-100,100}}) do number(cfg,key,defaults[key],limits[1],limits[2]) end
    if not inverse[cfg.anchor] then cfg.anchor=defaults.anchor end
    if cfg.growX~='LEFT' and cfg.growX~='RIGHT' then cfg.growX='RIGHT' end
    if cfg.growY~='UP' and cfg.growY~='DOWN' then cfg.growY='UP' end
    if cfg.sort~='name' and cfg.sort~='remaining' and cfg.sort~='spell' then cfg.sort='remaining' end
    for _,key in ipairs({'count','duration'}) do
        local t=cfg[key]
        if type(t.show)~='boolean' then t.show=true end
        if key=='duration' and type(t.swipe)~='boolean' then t.swipe=true end
        if type(t.font)~='string' or t.font=='' then t.font='DEFAULT' end
        if not inverse[t.point] then t.point=defaults[key].point end
        if t.outline~='' and t.outline~='OUTLINE' and t.outline~='THICKOUTLINE' and t.outline~='MONOCHROME,OUTLINE' then t.outline='OUTLINE' end
        number(t,'size',12,4,60); number(t,'x',0,-100,100); number(t,'y',0,-100,100)
    end
end

function D:NewHolder(plate)
    local frame=CreateFrame('Frame',nil,UIParent)
    -- Same layer as the independent abilities panel; system menus stay above.
    frame:EnableMouse(false); frame:SetFrameStrata('LOW'); frame:SetFrameLevel(5)
    local h={frame=frame,icons={}}
    self.holders[plate]=h
    return h
end

function D:Icon(h,index)
    if h.icons[index] then return h.icons[index] end
    local f=CreateFrame('Frame',nil,h.frame)
    f:EnableMouse(true)
    f:SetScript('OnEnter',function(self) D:SpellTooltip(self,self.spellId,self.timerText) end)
    f:SetScript('OnLeave',function() GameTooltip:Hide() end)
    f:SetScript('OnHide',function(self) if GameTooltip:IsOwned(self) then GameTooltip:Hide() end end)
    f.texture=f:CreateTexture(nil,'ARTWORK'); f.texture:SetAllPoints(f)
    f.cooldown=CreateFrame('Cooldown',nil,f,'CooldownFrameTemplate')
    f.cooldown.noOCC=true; f.cooldown.noCooldownCount=true
    f.cooldown:SetAllPoints(f); f.cooldown:EnableMouse(false)
    if f.cooldown.SetHideCountdownNumbers then f.cooldown:SetHideCountdownNumbers(true) end
    f.textLayer=CreateFrame('Frame',nil,f)
    f.textLayer:SetAllPoints(f); f.textLayer:SetFrameLevel(f.cooldown:GetFrameLevel()+2)
    f.textLayer:EnableMouse(false)
    f.count=f.textLayer:CreateFontString(nil,'OVERLAY','GameFontNormal')
    f.duration=f.textLayer:CreateFontString(nil,'OVERLAY','GameFontNormal')
    h.icons[index]=f
    return f
end

function D:TextStyle(text,cfg)
    local font=cfg.font
    if font~='DEFAULT' and E.Libs.LSM and not font:find('\\',1,true) and not font:find('/',1,true) then
        font=E.Libs.LSM:Fetch('font',font,true) or font
    end
    A:ApplyFont(text,font,cfg.size,cfg.outline)
    text:ClearAllPoints(); text:SetPoint(cfg.point,text:GetParent(),cfg.point,cfg.x,cfg.y)
    text:SetTextColor(1,1,1)
end

function D:Render(plate,items)
    local cfg=A.db.dbm
    if #items==0 then if self.holders[plate] then self.holders[plate].frame:Hide() end; return end
    table.sort(items,function(a,b)
        local av,bv
        if cfg.sort=='name' then av,bv=a.text,b.text
        elseif cfg.sort=='spell' then av,bv=a.spellId or 0,b.spellId or 0
        else av,bv=a.remaining,b.remaining end
        if av==bv then return tostring(a.id)<tostring(b.id) end
        if cfg.descending then return av>bv else return av<bv end
    end)
    local h=self.holders[plate] or self:NewHolder(plate)
    h.touched=true
    local n=math.min(#items,cfg.perRow*cfg.rows)
    local w,height=cfg.size,cfg.keepAspect and cfg.size or cfg.height
    local columns=math.min(n,cfg.perRow); local rows=math.ceil(n/cfg.perRow)
    local width=columns*w+(columns-1)*cfg.spacing
    local totalHeight=rows*height+(rows-1)*cfg.spacing
    local anchor=plate
    local layout=tostring(self.revision)..':'..n
    if h.layout~=layout or h.anchor~=anchor then
        h.frame:ClearAllPoints(); h.frame:SetSize(width,totalHeight)
        h.frame:SetPoint(inverse[cfg.anchor],anchor,cfg.anchor,cfg.x,cfg.y)
        h.layout=layout; h.anchor=anchor
    end
    local now=GetTime()
    for i,item in ipairs(items) do
        if i>n then break end
        local icon=self:Icon(h,i)
        if GameTooltip:IsOwned(icon) and (icon.spellId~=item.spellId or icon.timerText~=item.text) then self:SpellTooltip(icon,item.spellId,item.text) end
        icon.spellId=item.spellId; icon.timerText=item.text
        local col=(i-1)%cfg.perRow; local row=math.floor((i-1)/cfg.perRow)
        if cfg.growX=='LEFT' then col=columns-1-col end
        if cfg.growY=='UP' then row=rows-1-row end
        if icon.layout~=layout then
            icon:SetSize(w,height); icon:ClearAllPoints()
            icon:SetPoint('TOPLEFT',h.frame,'TOPLEFT',col*(w+cfg.spacing),-row*(height+cfg.spacing))
            icon.layout=layout
        end
        local texture=item.icon or 'Interface\\Icons\\INV_Misc_QuestionMark'
        if icon.texturePath~=texture then icon.texture:SetTexture(texture); icon.texturePath=texture end
        if icon.keepAspect~=cfg.keepAspect then
            if cfg.keepAspect then icon.texture:SetTexCoord(0.08,0.92,0.08,0.92)
            else icon.texture:SetTexCoord(0,1,0,1) end
            icon.keepAspect=cfg.keepAspect
        end
        if icon.desaturated~=cfg.desaturate then icon.texture:SetDesaturated(cfg.desaturate); icon.desaturated=cfg.desaturate end
        local alpha=1
        if icon.alphaValue~=alpha then icon:SetAlpha(alpha); icon.alphaValue=alpha end
        if h.revision~=self.revision or icon.revision~=self.revision then
            self:TextStyle(icon.count,cfg.count); self:TextStyle(icon.duration,cfg.duration)
            icon.revision=self.revision
        end
        local count=tonumber(item.count) or item.multiplicity
        local countText=cfg.count.show and count and count>1 and tostring(count) or ''
        if icon.countText~=countText then icon.count:SetText(countText); icon.countText=countText end
        local left=item.remaining
        local durationText=cfg.duration.show and (left>=60 and string.format('%d:%02d',math.floor(left/60),math.floor(left%60)) or (left<3 and string.format('%.1f',left) or tostring(math.ceil(left)))) or ''
        if icon.durationText~=durationText then icon.duration:SetText(durationText); icon.durationText=durationText end
        if cfg.duration.swipe and left>0 then
            local total=math.max(item.total,left,0.01)
            local start=now-(total-left)
            -- Let the client animate the swipe. Repeated SetCooldown restarts it.
            -- Small DBT/frame-clock jitter is not an actual timer adjustment.
            if icon.cooldownId~=item.id or not icon.cooldownTotal or math.abs(icon.cooldownTotal-total)>0.01 or math.abs(icon.cooldownStart-start)>0.2 then
                icon.cooldown:SetCooldown(start,total)
                icon.cooldownId=item.id; icon.cooldownTotal=total; icon.cooldownStart=start
            end
            if not icon.cooldown:IsShown() then icon.cooldown:Show() end
        else
            if icon.cooldown:IsShown() then icon.cooldown:Hide() end
            icon.cooldownId=nil; icon.cooldownTotal=nil; icon.cooldownStart=nil
        end
        if not icon:IsShown() then icon:Show() end
    end
    for i=n+1,#h.icons do h.icons[i]:Hide() end
    h.revision=self.revision
    if not h.frame:IsShown() then h.frame:Show() end
end

function D:HideAll()
    for _,h in pairs(self.holders) do h.frame:Hide() end
end

function D:HideUnused()
    for _,h in pairs(self.holders) do if not h.touched then h.frame:Hide() end end
end

function D:SpellTooltip(frame,spellId,label)
    GameTooltip:SetOwner(frame,'ANCHOR_RIGHT')
    if tonumber(spellId) and tonumber(spellId)>0 then
        GameTooltip:SetHyperlink('spell:'..tonumber(spellId))
    else
        GameTooltip:SetText(label or 'Таймер DBM')
        GameTooltip:AddLine('Именованный таймер DBM: отдельного игрового заклинания нет.',1,1,1,true)
    end
    GameTooltip:Show()
end

-- Independent panel: its ElvUI mover persists without a selected target.
function D:PanelAnchor()
    if not self.moverAnchor then
        local parent=E.UIParent or UIParent
        local anchor=CreateFrame('Frame','PhoenixPanelDBMAnchor',parent)
        anchor:SetSize(160,36)
        anchor:SetPoint('CENTER',parent,'CENTER',0,100)
        anchor:EnableMouse(false)
        self.moverAnchor=anchor
    end
    if not self.moverRegistered and type(E.CreateMover)=='function' then
        E:CreateMover(self.moverAnchor,'PhoenixPanelDBMMover',
            'PhoenixPanel — ДБМ',nil,nil,nil,
            'ALL,GENERAL,SOLO,PARTY,RAID,ARENA',nil,'phoenixPanel,dbm')
        self.moverRegistered=true
        if E.configMode and _G.PhoenixPanelDBMMover then
            _G.PhoenixPanelDBMMover:Show()
        end
    end
    return self.moverAnchor
end

function D:Report()
    local bars,large,known,shown=0,0,0,0
    for bar in pairs(DBT and DBT.bars or {}) do
        bars=bars+1
        if self:IsLarge(bar) then large=large+1 end
        if self.records[bar.id] then known=known+1 end
    end
    for _,h in pairs(self.holders) do
        if h.frame:IsShown() then for _,icon in ipairs(h.icons) do if icon:IsShown() then shown=shown+1 end end end
    end
    local plate=self:PanelAnchor()
    A:Say(string.format('DBM: %s; полос: %d; больших: %d; получено таймеров: %d; иконок: %d; панель: %s.',
        self.attached and 'подключён' or 'не подключён',bars,large,known,shown,plate and 'найдена' or 'не найдена'))
end

function D:NativeTest()
    if InCombatLockdown() then A:Say('Запустите тест DBM после боя.'); return end
    self:Attach()
    if not DBM or type(DBM.DemoMode)~='function' then A:Say('Встроенный тест DBM недоступен: DBM не загружен.'); return end
    if not A.db.dbm.enabled then A:Say('Сначала включите отображение DBM в настройках плагина.'); return end
    self:StopTest()
    DBM:DemoMode()
    self:Tick()
end

function D:Tick()
    if self.shuttingDown or not A.db or not A.db.dbm then return end
    local cfg=A.db.dbm
    self:PanelAnchor()  -- retry registration if ElvUI's mover system initialized later
    for _,h in pairs(self.holders) do h.touched=false end
    if not cfg.enabled then self:StopTest(); self:HideUnused(); return end
    if self.testUntil then
        if GetTime()>=self.testUntil or not self.testPlate or not self.testPlate:IsShown() then self:StopTest() else
            local items={}
            for i,id in ipairs({313034,313036,317571,317579,317596,317594}) do
                local left=math.max(0,self.testUntil-GetTime()-i*0.3)
                items[#items+1]={id='test'..i,key='test'..i,spellId=id,text=GetSpellInfo(id) or ('Тест '..i),icon=select(3,GetSpellInfo(id)),remaining=left,total=20,count=i,multiplicity=1}
            end
            self:Render(self.testPlate,items)
        end
    end
    if not self.attached then self:HideUnused(); self:CaptureFailure(); return end
    local plate=self:PanelAnchor()
    if plate and not self.testUntil then
        -- Only the displayed destination changes; selection and large-bar filters stay intact.
        self:Render(plate,self:Collect())
    end
    -- Stop callbacks and the authoritative bar table cover cancellation/expiry.
    for id in pairs(self.records) do
        local present=false
        for bar in pairs(DBT and DBT.bars or {}) do if bar.id==id and not bar.dead then present=true; break end end
        if not present then self.records[id]=nil end
    end
    self:HideUnused()
    self:CaptureFailure()
end

function D:Apply()
    if A.db and A.db.dbm then self:Validate() end
    self.revision=(self.revision or 0)+1
    self:HideAll()
    if self.initialized then self:Tick() end
end

function D:StopTest()
    self.testUntil=nil
    if self.testPlate then
        if self.holders[self.testPlate] then self.holders[self.testPlate].frame:Hide() end
    end
    self.testPlate=nil
end

function D:Test()
    if not A.db.dbm.enabled then return end
    if InCombatLockdown() then A:Say('Запустите тест DBM после боя.'); return end
    if self.testUntil then self:StopTest(); return end
    local plate=self:PanelAnchor()
    self.testPlate=plate
    self.testUntil=GetTime()+20; self:Tick()
end

function D:Initialize()
    if self.initialized then return end
    self.initialized=true; self.revision=1
    self:PanelAnchor()
    local driver=CreateFrame('Frame')
    self.driver=driver
    driver:RegisterEvent('ADDON_LOADED'); driver:RegisterEvent('PLAYER_LOGOUT')
    driver:SetScript('OnEvent',function(_,event,addon)
        if event=='PLAYER_LOGOUT' then D.shuttingDown=true; D:StopTest(); D:HideAll(); D.records={}; return end
        if addon and addon:match('^DBM%-') then D:Attach(); D:RefreshCatalog() end
    end)
    local elapsed=0
    driver:SetScript('OnUpdate',function(_,dt)
        elapsed=elapsed+dt; if elapsed<0.1 then return end; elapsed=0
        D:Tick()
    end)
    self:Attach()
end

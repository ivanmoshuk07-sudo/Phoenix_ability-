local A=PhoenixPanel
-- Start with an existing client font object; never SetText on an uninitialised FontString.
function A:ApplyFont(fs,path,size,flags)
    size=math.max(4,math.min(60,tonumber(size) or 18))
    flags=flags or 'OUTLINE'
    fs:SetFontObject(GameFontNormal)
    local base=GameFontNormal:GetFont()
    local candidate=(type(path)=='string' and path~='' and path~='DEFAULT') and path or base
    local function try(font)
        if not font then return false end
        local ok,result=pcall(fs.SetFont,fs,font,size,flags)
        if not ok or result==false then return false end
        local actual=fs:GetFont()
        -- Some clients return nil on success: inspect the applied path as well.
        local function norm(s) return tostring(s or ''):lower():gsub('/','\\') end
        return actual and norm(actual)==norm(font)
    end
    if try(candidate) then return true end
    fs:SetFontObject(GameFontNormal)
    if not try(base) then fs:SetFontObject(GameFontNormal) end
    return false
end

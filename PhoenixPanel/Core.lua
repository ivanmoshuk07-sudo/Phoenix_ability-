local A = {defaults={}}
PhoenixPanel = A
local function fill(dst,defaults)
    for key,value in pairs(defaults) do
        if type(value)=='table' then
            if type(dst[key])~='table' then dst[key]={} end
            fill(dst[key],value)
        elseif dst[key]==nil then dst[key]=value end
    end
end
A.Fill=fill
function A:Say(message)
    DEFAULT_CHAT_FRAME:AddMessage('|cff66ccffPhoenixPanel|r: '..tostring(message))
end

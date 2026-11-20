-- Use dark controls only on white and near-white widget fills.
local function linear(channel)
    channel = channel / 255
    if channel <= 0.04045 then return channel / 12.92 end
    return ((channel + 0.055) / 1.055) ^ 2.4
end

local function rgb(value)
    value = tostring(value or ''):match('^%s*(.-)%s*$')
    local r, g, b = value:match('^(%d+)%s*,%s*(%d+)%s*,%s*(%d+)')
    if r then return tonumber(r), tonumber(g), tonumber(b) end
    value = value:gsub('^#', ''):gsub('^0[xX]', '')
    if (#value == 6 or #value == 8) and value:match('^%x+$') then
        return tonumber(value:sub(1,2),16), tonumber(value:sub(3,4),16), tonumber(value:sub(5,6),16)
    end
end

function Update()
    local r, g, b = rgb(SKIN:GetVariable('BackgroundColor'))
    if not r then return 0 end
    local luminance = 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    local foreground = luminance >= 0.72 and math.min(r, g, b) >= 210 and '000000' or 'FFFFFF'
    if SKIN:GetVariable('ForegroundColor', ''):upper() ~= foreground then
        SKIN:Bang('!SetVariable', 'ForegroundColor', foreground)
    end
    return luminance
end

function PreviousTrack()
    if string.lower(SKIN:GetVariable('Plugin') or '') == 'mediaplayer' then
        SKIN:Bang('!CommandMeasure', 'WindowsPrevious', 'Run')
    else
        SKIN:Bang('!CommandMeasure', 'TitleMeasure', 'Previous')
    end
end

local entries = {}
local running = false
local cellCount = {Small=1, Medium=4, Wide=4, Large=6}

function Initialize()
    entries = {}
    running = false
    for _, name in ipairs({'CPU', 'RAM', 'Disk', 'Net'}) do
        entries[#entries+1] = {name=name, source=SKIN:GetMeasure(name..'Rounded'), value=0}
    end
end

function Start()
    if running then return end
    for _, entry in ipairs(entries) do
        local target = entry.source and entry.source:GetValue()
        if target and target == target and target >= 0 and target <= 100 and math.abs(target-entry.value) > 0.01 then
            running = true
            SKIN:Bang('!CommandMeasure','MonitorAnimationTimer','Execute 1')
            return
        end
    end
end

function AnimationFrame()
    local saver = tonumber(SKIN:GetVariable('BatterySaverMode', '0')) == 1
    local changed, unsettled = false, false
    for _, entry in ipairs(entries) do
        local target = entry.source and entry.source:GetValue()
        if target and target == target and target >= 0 and target <= 100 then
            local delta = target - entry.value
            if math.abs(delta) > 0.01 then
                entry.value = (saver or math.abs(delta) <= 0.5) and target or entry.value + delta * 0.5
                SKIN:Bang('!SetVariable', entry.name..'Value', string.format('%.6f', entry.value))
                SKIN:Bang('!UpdateMeasure', entry.name..'Measure')
                changed = true
                if math.abs(target-entry.value) > 0.01 then unsettled = true end
            end
        end
    end
    if changed then
        local count = cellCount[SKIN:GetVariable('WidgetSize','Medium')] or 4
        for i=1,count do
            SKIN:Bang('!UpdateMeter','MeterMeter'..i)
            if count==6 then SKIN:Bang('!UpdateMeter','MeterValue'..i) end
        end
        SKIN:Bang('!Redraw')
    end
    if not unsettled and running then
        running = false
        SKIN:Bang('!CommandMeasure','MonitorAnimationTimer','Stop 1')
    end
end

function Finished()
    running = false
    Start()
end

local entries = {}

function Initialize()
    entries = {}
    for _, name in ipairs({'CPU', 'RAM', 'Disk', 'Net'}) do
        entries[#entries+1] = {name=name, source=SKIN:GetMeasure(name..'Rounded'), value=0}
    end
end

function Update()
    local saver = tonumber(SKIN:GetVariable('BatterySaverMode', '0')) == 1
    for _, entry in ipairs(entries) do
        local target = entry.source and entry.source:GetValue()
        if target and target == target and target >= 0 and target <= 100 then
            local delta = target - entry.value
            if delta ~= 0 then
                if saver or math.abs(delta) <= 0.5 then
                    entry.value = target
                else
                    entry.value = entry.value + delta * 0.5
                end
                SKIN:Bang('!SetVariable', entry.name..'Value', string.format('%.6f', entry.value))
            end
        end
    end
    return 0
end

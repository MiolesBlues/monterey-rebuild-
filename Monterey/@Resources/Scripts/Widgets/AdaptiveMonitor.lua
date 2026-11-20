local countBySize={Small=1,Medium=4,Wide=4,Large=6}
local supported={CPU=true,RAM=true,Disk=true,Net=true,Battery=true,None=true}
local devices,assignment,display,lastGeneration={}, {}, {}, -1
local cellCount=0
local legacy={}
local pending=false

local function decode(s)
    return (s:gsub('..',function(b) return string.char(tonumber(b,16) or 32) end))
end
local function parse(raw)
    if not raw or raw:sub(1,3)~='OK:' then return nil end
    local found={}
    for row in raw:sub(4):gmatch('([^;]+)') do
        local id,name,category,connected,battery=row:match('^([0-9A-F]*),([0-9A-F]*),([0-9A-F]*),([01]),(-?%d+)$')
        if id and name then
            local d={id=decode(id),name=decode(name),category=decode(category),connected=connected=='1',battery=tonumber(battery)}
            if d.id~='' and d.name~='' then found[d.id]=d end
        end
    end
    return found
end
local function iconKey(id)
    if #id==38 and id:match('^%{[%x%-]+%}$') then id=id:lower() end
    return 'DeviceIcon_'..id:gsub('.',function(c) return string.format('%02X',string.byte(c)) end)
end
local function chosenIcon(id)
    local icon=SKIN:GetVariable(iconKey(id),'')
    if icon=='Phone' or icon=='Mouse' or icon=='Headphones' or icon=='Tablet' or icon=='Watch' or icon=='Bluetooth' then return icon end
end
local function config(i)
    local old=legacy[i] or 'None'
    local mode=SKIN:GetVariable('DeviceMode'..i,'Legacy')
    local fallback=SKIN:GetVariable('Fallback'..i,'Legacy')
    if mode=='Legacy' then mode=old=='None' and 'Auto' or 'None' end
    if fallback=='Legacy' then fallback=supported[old] and old or 'None' end
    if not supported[fallback] then fallback='None' end
    if mode~='Auto' and mode~='Pinned' then mode='None' end
    return mode,SKIN:GetVariable('PinnedId'..i,''),fallback
end
local function set(name,value) SKIN:Bang('!SetVariable',name,tostring(value)) end
local function option(meter,key,value) SKIN:Bang('!SetOption',meter,key,tostring(value)) end
local function updateCell(i,kind,device)
    local customIcon=device and chosenIcon(device.id)
    local signature=kind..'|'..(device and (device.id..'|'..device.name..'|'..device.battery..'|'..(customIcon or '')) or '')
    if display[i]==signature then return end
    display[i]=signature
    local measure,label,icon,tooltip,color,unknown
    if device then
        local level=device.battery
        unknown=level<0 or level>100
        measure='Phone'..i
        set(measure..'Level',unknown and 0 or level)
        color=SKIN:GetVariable(unknown and 'GrayColor' or (level<=10 and 'RedColor' or level<=30 and 'YellowColor' or 'GreenColor'))
        set(measure..'Color',color)
        SKIN:Bang('!UpdateMeasure',measure..'Measure')
        SKIN:Bang('!UpdateMeasure',measure..'Rounded')
        label=device.name
        icon=device.category=='Phone' and 'Phone1' or device.category=='Mouse' and 'Mouse1' or 'Bluetooth1'
        tooltip=device.name..(unknown and ', battery unavailable' or (', '..level..'%'))
    else
        measure=kind
        label=kind=='Net' and 'Network' or kind
        icon=kind
        tooltip=({CPU='Processor usage',RAM='Memory usage',Disk='Disk activity',Net='Network activity',Battery='Laptop battery level',None=' '})[kind]
        unknown=kind=='None'
    end
    set('Meter'..i,measure)
    local image=customIcon and ('#@#Images\\Monitor\\DeviceIcons\\'..customIcon..'.png') or ('#@#Images\\Monitor\\'..icon..'.png')
    option('MeterImage'..i,'ImageName',SKIN:ReplaceVariables(image))
    for _,meter in ipairs({'MeterImage','MeterMeter','MeterText','MeterValue'}) do
        option(meter..i,'ToolTipText',tooltip)
    end
    if device then SKIN:Bang('!CommandMeasure','BluetoothWatcher','CELL|'..i..'|'..device.id) end
    if SKIN:GetVariable('WidgetSize')=='Large' then
        option('MeterText'..i,'Text',label)
        option('MeterValue'..i,'Hidden',unknown and '1' or '0')
        option('MeterMeter'..i,'Hidden',unknown and '1' or '0')
        option('MeterText'..i,'Hidden',kind=='None' and '1' or '0')
    elseif SKIN:GetVariable('WidgetSize')=='Wide' then
        option('MeterText'..i,'Text',device and label or '%1 %')
        option('MeterText'..i,'FontSize',device and '(#WidgetHeight#*0.06)' or '(#WidgetHeight#*0.1)')
        option('MeterText'..i,'Hidden',unknown and '1' or '0')
        option('MeterMeter'..i,'Hidden',unknown and '1' or '0')
    else
        option('MeterMeter'..i,'Hidden',unknown and '1' or '0')
    end
    SKIN:Bang('!UpdateMeter','MeterImage'..i)
    SKIN:Bang('!UpdateMeter','MeterMeter'..i)
    if SKIN:GetVariable('WidgetSize')=='Large' or SKIN:GetVariable('WidgetSize')=='Wide' then
        SKIN:Bang('!UpdateMeter','MeterText'..i)
        if SKIN:GetVariable('WidgetSize')=='Large' then SKIN:Bang('!UpdateMeter','MeterValue'..i) end
    end
    SKIN:Bang('!Redraw')
end
local function resolve()
    local reserved,used={},{}
    local modes,ids,fallbacks={},{},{}
    for i=1,cellCount do
        modes[i],ids[i],fallbacks[i]=config(i)
        if modes[i]=='Pinned' and ids[i]~='' and not reserved[ids[i]] then reserved[ids[i]]=i end
    end
    for i=1,cellCount do
        local id=ids[i]
        local d=modes[i]=='Pinned' and reserved[id]==i and devices[id] or nil
        if d and d.connected then used[id]=true; assignment[i]=id
        elseif modes[i]~='Auto' then assignment[i]=nil end
    end
    for i=1,cellCount do
        if modes[i]=='Auto' then
            local id=assignment[i]
            if not id or not devices[id] or not devices[id].connected or reserved[id] or used[id] then assignment[i]=nil
            else used[id]=true end
        end
    end
    local available={}
    for id,d in pairs(devices) do
        if d.connected and not used[id] and not reserved[id] then available[#available+1]=id end
    end
    local priority={Phone=1,Mouse=2,Headphones=3,Bluetooth=4}
    table.sort(available,function(a,b)
        local pa=priority[devices[a].category] or 4
        local pb=priority[devices[b].category] or 4
        return pa==pb and a<b or pa<pb
    end)
    local nextId=1
    for i=1,cellCount do
        if modes[i]=='Auto' and not assignment[i] then
            assignment[i]=available[nextId]; if assignment[i] then nextId=nextId+1 end
        end
        local d=assignment[i] and devices[assignment[i]]
        if d and d.connected then updateCell(i,'Device',d) else updateCell(i,fallbacks[i]) end
    end
end
function Initialize()
    cellCount=countBySize[SKIN:GetVariable('WidgetSize')] or 0
    for i=1,cellCount do legacy[i]=SKIN:GetVariable('Meter'..i,'None') end
    devices,assignment,display,lastGeneration={}, {}, {}, -1
    pending=true
end
function Update()
    if pending then resolve(); pending=false end
    local measure=SKIN:GetMeasure('BluetoothWatcher')
    if not measure then return 0 end
    local generation=measure:GetValue()
    if generation~=lastGeneration then
        local found=parse(measure:GetStringValue())
        if found then devices=found; resolve() end
        lastGeneration=generation
    end
    return 0
end

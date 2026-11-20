local slots, nextPoll, busy, now, lastGood
local countBySize = {Small=1, Medium=4, Wide=4, Large=6}
local function set(k,v) SKIN:Bang('!SetVariable',k,tostring(v)) end

function Initialize()
    slots={}
    for i=1,countBySize[SKIN:GetVariable('WidgetSize')] or 0 do
        if SKIN:GetVariable('Meter'..i)=='None' then slots[#slots+1]=i end
    end
    nextPoll=0; busy=false; lastGood=nil
end

local function publish(values)
    for n,i in ipairs(slots) do
        local device=values[n]
        local v=device and device.level
        local kind=device and device.kind
        local label=({P='Phone',M='Mouse',B='Bluetooth'})[kind] or 'None'
        local icon=({P='Phone',M='Mouse',B='Bluetooth'})[kind]
        local key='Phone'..i
        set(key..'Level',v or -1)
        if v then
            local color=v<=10 and 'RedColor' or (v<=30 and 'YellowColor' or 'GreenColor')
            set(key..'Color',SKIN:GetVariable(color))
        end
        set('Meter'..i,v and key or 'None')
        SKIN:Bang('!UpdateMeasure',key..'Measure')
        SKIN:Bang('!UpdateMeasure',key..'Rounded')
        SKIN:Bang('!SetOption','MeterImage'..i,'ImageName',SKIN:ReplaceVariables('#@#Images\\Monitor\\'..(icon and (icon..'1') or 'None')..'.png'))
        SKIN:Bang('!SetOption','MeterImage'..i,'ToolTipText',v and (label..': '..v..'%') or '')
        if SKIN:GetVariable('WidgetSize')=='Large' then
            SKIN:Bang('!SetOption','MeterText'..i,'Text',label)
        end
    end
    SKIN:Bang('!UpdateMeter','*'); SKIN:Bang('!Redraw')
end

function Finished()
    busy=false
    local raw=SKIN:GetMeasure('PhoneBatteryQuery'):GetStringValue()
    local payload=raw:match('^%s*OK:([PMB%d,]*)%s*$')
    if payload then
        local values={}
        for kind,s in payload:gmatch('([PMB])(%d+)') do
            local v=tonumber(s)
            if v>=0 and v<=100 then values[#values+1]={kind=kind,level=v} end
        end
        lastGood=os.time(); publish(values)
    elseif not lastGood or os.time()-lastGood>=60 then
        publish({})
    end
end

function Update()
    now=os.time()
    if #slots>0 and not busy and now>=nextPoll then
        busy=true; nextPoll=now+15
        SKIN:Bang('!CommandMeasure','PhoneBatteryQuery','Run')
    end
    return 0
end

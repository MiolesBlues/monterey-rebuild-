local modes={'None','Auto'}
local fallbacks={'CPU','RAM','Disk','Net','Battery','None'}
local iconChoices={'Phone','Mouse','Headphones','Tablet','Watch','Bluetooth'}
local validIcon={Phone=true,Mouse=true,Headphones=true,Tablet=true,Watch=true,Bluetooth=true}
local devices,ordered,selection={}, {}, {}
local page,cell,index,origin='main',1,1,'main'
local dirty=true
local lastGeneration=-1
local dropdownCell,fallbackCell,iconRow=nil,nil,nil
local function canonicalId(id)
    if #id==38 and id:match('^%{[%x%-]+%}$') then return id:lower() end
    return id
end
local function decode(s) return (s:gsub('..',function(b) return string.char(tonumber(b,16) or 32) end)) end
local function iconKey(id)
    return 'DeviceIcon_'..canonicalId(id):gsub('.',function(c) return string.format('%02X',string.byte(c)) end)
end
local function chosenIcon(id,category)
    local icon=SKIN:GetVariable(iconKey(id),'')
    if validIcon[icon] then return icon end
    return validIcon[category] and category or 'Bluetooth'
end
local function parse(raw)
    if not raw or raw:sub(1,3)~='OK:' then return end
    local found={}
    for row in raw:sub(4):gmatch('([^;]+)') do
        local id,name,category,connected,battery=row:match('^([0-9A-F]*),([0-9A-F]*),([0-9A-F]*),([01]),(-?%d+)$')
        if id and name then
            local d={id=canonicalId(decode(id)),name=decode(name),category=decode(category),connected=connected=='1',battery=tonumber(battery)}
            if d.id~='' and d.name~='' then found[d.id]=d end
        end
    end
    devices=found; ordered={}
    for _,d in pairs(devices) do if d.connected then ordered[#ordered+1]=d end end
    table.sort(ordered,function(a,b) return a.name:lower()<b.name:lower() end)
    if index>#ordered then index=math.max(1,4*math.floor((#ordered-1)/4)+1) end
    dirty=true
end
local function cfg(i)
    local old=SKIN:GetVariable('Meter'..i,'None')
    local mode=SKIN:GetVariable('DeviceMode'..i,'Legacy')
    local fallback=SKIN:GetVariable('Fallback'..i,'Legacy')
    if mode=='Legacy' then mode=old=='None' and 'Auto' or 'None' end
    if fallback=='Legacy' then fallback=old end
    if fallback=='Network' then fallback='Net' end
    if fallback~='CPU' and fallback~='RAM' and fallback~='Disk' and fallback~='Net' and fallback~='Battery' then fallback='None' end
    return mode,canonicalId(SKIN:GetVariable('PinnedId'..i,'')),fallback
end
local function write(key,value)
    SKIN:Bang('!WriteKeyValue','Variables',key,value,SKIN:ReplaceVariables('#@#Variables\\Monitor.inc'))
    SKIN:Bang('!SetVariable',key,value)
    dirty=true
end
local function action(name)
    return '[!CommandMeasure AdaptiveSettings "'..name..'"]'
end
local function row(i,title,value,command,tooltip)
    local t='Option'..i..'Title'; local v='Option'..i..'Value'
    SKIN:Bang('!SetOption',t,'Text',title or '')
    SKIN:Bang('!SetOption',v,'Text',value or '')
    SKIN:Bang('!SetOption',t,'LeftMouseUpAction',command and command~='' and action(command) or '[]')
    SKIN:Bang('!SetOption',v,'LeftMouseUpAction',command and command~='' and action(command) or '[]')
    local tip=tooltip and tooltip~='' and tooltip or ' '
    SKIN:Bang('!SetOption',t,'ToolTipText',tip)
    SKIN:Bang('!SetOption',v,'ToolTipText',tip)
    SKIN:Bang('!SetOption',t,'Hidden',title and title~='' and '0' or '1')
    SKIN:Bang('!SetOption',v,'Hidden',value and value~='' and '0' or '1')
end
local function tooltip(meters,text)
    for _,meter in ipairs(meters) do SKIN:Bang('!SetOption',meter,'ToolTipText',text) end
end
local function assignment(id)
    for i=1,6 do local mode,pinned=cfg(i); if mode=='Pinned' and pinned==id then return i end end
end
local function show(meter,visible)
    SKIN:Bang('!SetOption',meter,'Hidden',visible and '0' or '1')
    SKIN:Bang('!UpdateMeter',meter)
end
local function rowPosition(i,y)
    for _,suffix in ipairs({'Title','Value'}) do
        SKIN:Bang('!SetOption','Option'..i..suffix,'Y','(#WidgetPadding# + #WidgetHeight# * '..y..')')
    end
end
local function deviceTitleLayout(enabled)
    for i=1,4 do
        local meter='Option'..i..'Title'
        SKIN:Bang('!SetOption',meter,'X','(#WidgetPadding# + #WidgetWidth# * '..(enabled and '0.19' or '0.05')..')')
        SKIN:Bang('!SetOption',meter,'W','(#WidgetWidth# * '..(enabled and '0.62' or (i==3 and '0.62' or '0.65'))..')')
        SKIN:Bang('!SetOption',meter,'H',enabled and '18' or '22')
        SKIN:Bang('!SetOption',meter,'ClipString','2')
        SKIN:Bang('!SetOption',meter,'FontSize','(#WidgetWidth# * '..(enabled and '0.032' or (i==1 and '0.035' or '0.03'))..')')
        SKIN:Bang('!SetOption',meter,'FontWeight',enabled and '600' or '500')
    end
end
local function modeAppearance(control,surface,mode)
    local pinColor=tonumber(SKIN:GetVariable('DarkMode','0'))==1 and 'B5C7FF' or '3157B7'
    local fill=mode=='Pinned' and 'A9BEF080' or '#BackgroundColor#'
    local shape='Rectangle 0,0,(#WidgetWidth# * 0.21),24,6,6 | Fill Color '..fill..' | StrokeWidth 1 | Stroke Color #GrayColor#'
    SKIN:Bang('!SetOption',control,'FontColor',mode=='Pinned' and pinColor or '#ForegroundColor#')
    local arrow=control:gsub('Control','Arrow')
    SKIN:Bang('!SetOption',arrow,'FontColor',mode=='Pinned' and pinColor or '#ForegroundColor#')
    SKIN:Bang('!SetOption',surface,'Shape',shape)
    SKIN:Bang('!SetOption',control,'MouseLeaveAction','[!SetOption '..surface..' Shape "'..shape..'"][!UpdateMeter '..surface..'][!Redraw]')
    SKIN:Bang('!SetOption',arrow,'MouseLeaveAction','[!SetOption '..surface..' Shape "'..shape..'"][!UpdateMeter '..surface..'][!Redraw]')
end
local function menu()
    local visible=dropdownCell~=nil
    show('DropdownDismiss',visible or fallbackCell~=nil or iconRow~=nil)
    local y=0.39+0.085*((dropdownCell or 1)-1)
    if page=='cell' then y=0.43 end
    if y>0.70 then y=y-0.215 else y=y+0.075 end
    local x=page=='cell' and 0.70 or 0.31
    for n,meter in ipairs({'ModeMenuSurface','ModeChoiceNone','ModeChoiceAuto','ModeChoicePinned'}) do
        SKIN:Bang('!SetOption',meter,'X','(#WidgetPadding# + #WidgetWidth# * '..x..')')
        SKIN:Bang('!SetOption',meter,'Y','(#WidgetPadding# + #WidgetHeight# * '..(y+math.max(0,n-2)*0.065)..')')
        show(meter,visible)
    end
    if visible then
        local selected=cfg(dropdownCell)
        for _,mode in ipairs({'None','Auto','Pinned'}) do
            SKIN:Bang('!SetOption','ModeChoice'..mode,'Text',(selected==mode and '> ' or '  ')..mode)
            SKIN:Bang('!UpdateMeter','ModeChoice'..mode)
        end
    end
    local fallbackVisible=fallbackCell~=nil
    local fy=0.39+0.085*((fallbackCell or 1)-1)
    if page=='cell' then fy=0.53 end
    if fy>0.51 then fy=math.max(0.30,fy-0.25) else fy=fy+0.075 end
    local fx=page=='cell' and 0.70 or 0.57
    local _,_,selectedFallback=cfg(fallbackCell or 1)
    SKIN:Bang('!SetOption','FallbackMenuSurface','X','(#WidgetPadding# + #WidgetWidth# * '..fx..')')
    SKIN:Bang('!SetOption','FallbackMenuSurface','Y','(#WidgetPadding# + #WidgetHeight# * '..fy..')')
    show('FallbackMenuSurface',fallbackVisible)
    for n,value in ipairs(fallbacks) do
        local meter='FallbackChoice'..value
        SKIN:Bang('!SetOption',meter,'X','(#WidgetPadding# + #WidgetWidth# * '..fx..')')
        SKIN:Bang('!SetOption',meter,'Y','(#WidgetPadding# + #WidgetHeight# * '..(fy+(n-1)*0.065)..')')
        SKIN:Bang('!SetOption',meter,'Text',(selectedFallback==value and '> ' or '  ')..(value=='Net' and 'Network' or value))
        show(meter,fallbackVisible)
    end
    local iconVisible=page=='devices' and origin=='main' and iconRow~=nil and selection[iconRow]~=nil
    show('IconMenuSurface',iconVisible)
    show('IconMenuHeading',iconVisible)
    show('IconChoiceAuto',iconVisible)
    for n,name in ipairs(iconChoices) do
        local selected=iconVisible and SKIN:GetVariable(iconKey(selection[iconRow]),'')==name
        SKIN:Bang('!SetOption','IconChoiceTile'..n,'Shape','Rectangle 0,0,38,34,6,6 | Fill Color '..(selected and 'A9BEF080' or '#GrayColor#')..' | StrokeWidth 1 | Stroke Color #GrayColor#')
        show('IconChoiceTile'..n,iconVisible)
        show('IconChoice'..n,iconVisible)
    end
end
local function controls()
    local main=page=='main'
    local listing=page=='devices'
    for i=1,6 do
        local mode,_,fb=cfg(i)
        SKIN:Bang('!SetOption','ModeControl'..i,'Text',mode)
        modeAppearance('ModeControl'..i,'ModeSurface'..i,mode)
        SKIN:Bang('!SetOption','FallbackControl'..i,'Text',fb=='Net' and 'Network' or fb)
        for _,prefix in ipairs({'ResourceLabel','ModeSurface','ModeControl','ModeArrow','FallbackSurface','FallbackControl','FallbackArrow','GearSurface','GearControl'}) do
            show(prefix..i,main)
        end
    end
    if page=='cell' then
        local mode,id,fb=cfg(cell)
        SKIN:Bang('!SetOption','CellModeControl','Text',mode)
        modeAppearance('CellModeControl','CellModeSurface',mode)
        SKIN:Bang('!SetOption','CellModeControl','LeftMouseUpAction',action('OpenMode('..cell..')'))
        SKIN:Bang('!SetOption','CellModeArrow','LeftMouseUpAction',action('OpenMode('..cell..')'))
        SKIN:Bang('!SetOption','CellFallbackControl','Text',fb=='Net' and 'Network' or fb)
        SKIN:Bang('!SetOption','CellFallbackControl','LeftMouseUpAction',action('OpenFallback('..cell..')'))
        SKIN:Bang('!SetOption','CellFallbackArrow','LeftMouseUpAction',action('OpenFallback('..cell..')'))
        SKIN:Bang('!SetOption','Option3Prompt','Text',id~='' and 'Change' or 'Choose')
    end
    show('CellModeSurface',page=='cell')
    show('CellModeControl',page=='cell')
    show('CellModeArrow',page=='cell')
    show('CellFallbackSurface',page=='cell')
    show('CellFallbackControl',page=='cell')
    show('CellFallbackArrow',page=='cell')
    show('CellDivider1',page=='cell')
    show('CellDivider2',page=='cell')
    show('CellBackSurface',page=='cell')
    show('CellBackControl',page=='cell')
    show('Option3Surface',page=='cell' and cfg(cell)=='Pinned')
    show('Option3Prompt',page=='cell' and cfg(cell)=='Pinned')
    show('AdaptiveHint',page=='cell' and cfg(cell)=='Pinned')
    show('ColumnResource',main)
    show('ColumnDevice',main)
    show('ColumnFallback',main)
    show('DevicesHeading',listing)
    show('DeviceRefreshSurface',listing)
    show('DeviceRefreshIcon',listing)
    show('DeviceEmpty',listing and #ordered==0)
    local paged=listing and #ordered>4
    show('DevicePrevSurface',paged)
    show('DevicePrev',paged)
    show('DeviceNextSurface',paged)
    show('DeviceNext',paged)
    show('DevicePage',paged)
    for i=1,4 do
        local present=listing and ordered[index+i-1]~=nil
        for _,prefix in ipairs({'DeviceCard','DeviceTile','DeviceIcon','DeviceDetail'}) do show(prefix..i,present) end
        show('DeviceChevron'..i,present and origin=='cell')
    end
    menu()
end
local function render()
    dropdownCell,fallbackCell,iconRow=nil,nil,nil
    deviceTitleLayout(page=='devices')
    if page=='main' then
        SKIN:Bang('!SetOption','AdaptiveNav','Y','(#WidgetPadding# + #WidgetHeight# * 0.275)')
        SKIN:Bang('!SetOption','Description','Hidden','0')
        SKIN:Bang('!SetOption','AdaptiveNav','Text','Available Devices  >')
        SKIN:Bang('!SetOption','AdaptiveNav','LeftMouseUpAction',action('OpenDevices()'))
        SKIN:Bang('!SetOption','AdaptiveNav','Hidden','0')
        SKIN:Bang('!SetOption','AdaptiveRefresh','Hidden','1')
        for i=1,6 do
            row(i,'','')
        end
    elseif page=='cell' then
        SKIN:Bang('!SetOption','AdaptiveNav','Y','(#WidgetPadding# + #WidgetHeight# * 0.275)')
        SKIN:Bang('!SetOption','Description','Hidden','1')
        SKIN:Bang('!SetOption','AdaptiveNav','Text',' ')
        SKIN:Bang('!SetOption','AdaptiveNav','LeftMouseUpAction','[]')
        SKIN:Bang('!SetOption','AdaptiveNav','Hidden','0')
        SKIN:Bang('!SetOption','AdaptiveRefresh','Hidden','1')
        local mode,id,fb=cfg(cell)
        local d=devices[id]
        SKIN:Bang('!SetOption','Option1Title','FontSize','(#WidgetWidth# * 0.035)')
        SKIN:Bang('!SetOption','Option1Title','FontWeight','600')
        rowPosition(1,0.30)
        rowPosition(2,0.43)
        rowPosition(3,0.63); rowPosition(4,0.53)
        row(1,'Resource '..cell,'','', 'Configure what Resource '..cell..' displays.')
        local modeTip='Auto selects a device automatically. None disables device monitoring. Pinned uses the device chosen below.'
        local fallbackTip='Local resource data to show when device data is unavailable.'
        local pinnedTip='Choose a connected device to keep on this resource. Available in Pinned mode.'
        row(2,'Device mode','','',modeTip)
        tooltip({'CellModeSurface','CellModeControl','CellModeArrow'},modeTip)
        if mode=='Pinned' then
            row(3,'Pinned device','','OpenDevices()',pinnedTip)
            if d then SKIN:Bang('!CommandMeasure','BluetoothWatcher','PICK|3|'..id) end
        else row(3,'','') end
        tooltip({'Option3Surface','Option3Prompt','AdaptiveHint'},pinnedTip)
        row(4,'Fallback function','','',fallbackTip)
        tooltip({'CellFallbackSurface','CellFallbackControl','CellFallbackArrow'},fallbackTip)
        row(5,'','')
        row(6,'','')
    elseif page=='devices' then
        SKIN:Bang('!SetOption','Description','Hidden','1')
        for i=1,4 do rowPosition(i,0.405+0.115*(i-1)+0.014) end
        SKIN:Bang('!SetOption','AdaptiveNav','Text','< Back')
        SKIN:Bang('!SetOption','AdaptiveNav','LeftMouseUpAction',action('Back()'))
        SKIN:Bang('!SetOption','AdaptiveNav','Hidden','0')
        SKIN:Bang('!SetOption','AdaptiveNav','Y','(#WidgetPadding# + #WidgetHeight# * 0.23)')
        SKIN:Bang('!SetOption','AdaptiveRefresh','Hidden','1')
        for i=1,4 do
            local d=ordered[index+i-1]
            if d then
                selection[i]=d.id
                local owner=assignment(d.id)
                local info=d.category..'  |  Connected'..(d.battery>=0 and ('  |  '..d.battery..'%') or '')
                local command=origin=='cell' and ('Pick('..i..')') or nil
                row(i,'Device','',command,info)
                local icon=chosenIcon(d.id,d.category)
                SKIN:Bang('!SetOption','DeviceIcon'..i,'ImageName','#@#Images\\Monitor\\DeviceIcons\\'..icon..'.png')
                SKIN:Bang('!SetOption','DeviceDetail'..i,'Text',info)
                for _,prefix in ipairs({'DeviceCard','DeviceDetail','DeviceChevron'}) do
                    SKIN:Bang('!SetOption',prefix..i,'LeftMouseUpAction',command and action(command) or '[]')
                end
                local iconAction=origin=='main' and action('OpenIcon('..i..')') or (command and action(command) or '[]')
                SKIN:Bang('!SetOption','DeviceTile'..i,'LeftMouseUpAction',iconAction)
                SKIN:Bang('!SetOption','DeviceIcon'..i,'LeftMouseUpAction',iconAction)
                SKIN:Bang('!SetOption','DeviceTile'..i,'ToolTipText',origin=='main' and 'Choose icon' or info)
                SKIN:Bang('!SetOption','DeviceIcon'..i,'ToolTipText',origin=='main' and 'Choose icon' or info)
                SKIN:Bang('!CommandMeasure','BluetoothWatcher','NAME|'..i..'|'..d.id..'|'..(owner or ''))
            else selection[i]=nil; row(i,'','') end
        end
        row(5,'',''); row(6,'','')
        SKIN:Bang('!SetOption','DevicePage','Text',tostring(math.floor((index-1)/4)+1)..' / '..math.ceil(#ordered/4))
    end
    controls()
    SKIN:Bang('!UpdateMeter','Description')
    for i=1,6 do SKIN:Bang('!UpdateMeter','Option'..i..'Title'); SKIN:Bang('!UpdateMeter','Option'..i..'Value') end
    SKIN:Bang('!UpdateMeter','AdaptiveNav'); SKIN:Bang('!UpdateMeter','AdaptiveRefresh')
    SKIN:Bang('!Redraw'); dirty=false
end
function OpenMode(i)
    fallbackCell=nil
    dropdownCell=dropdownCell==i and nil or i
    menu(); SKIN:Bang('!Redraw')
end
function DismissMenus()
    dropdownCell,fallbackCell,iconRow=nil,nil,nil
    menu(); SKIN:Bang('!Redraw')
end
function SelectMode(value)
    if not dropdownCell or (value~='Auto' and value~='None' and value~='Pinned') then return end
    cell=dropdownCell
    dropdownCell=nil
    if value=='Pinned' then
        write('DeviceMode'..cell,'Pinned')
        render()
        return
    end
    local current=cfg(cell)
    if current~=value then
        CycleMode()
        if cfg(cell)~=value then CycleMode() end
    else render() end
end
function OpenIcon(i)
    if page~='devices' or origin~='main' or not selection[i] then return end
    dropdownCell,fallbackCell=nil,nil
    iconRow=iconRow==i and nil or i
    menu(); SKIN:Bang('!Redraw')
end
function SelectIcon(name)
    if page~='devices' or origin~='main' or not iconRow or not selection[iconRow] then return end
    if name~='Auto' and not validIcon[name] then return end
    local key=iconKey(selection[iconRow])
    local value=name=='Auto' and '' or name
    if SKIN:GetVariable(key,'')~=value then write(key,value) end
    iconRow=nil
    render()
end
function OpenFallback(i)
    dropdownCell=nil
    fallbackCell=fallbackCell==i and nil or i
    menu(); SKIN:Bang('!Redraw')
end
function SelectFallback(value)
    if not fallbackCell then return end
    local valid=false
    for _,option in ipairs(fallbacks) do if option==value then valid=true; break end end
    if not valid then return end
    cell=fallbackCell
    fallbackCell=nil
    local _,_,current=cfg(cell)
    if current~=value then write('Fallback'..cell,value) end
    render()
end
function Initialize() dirty=true end
function Update()
    local measure=SKIN:GetMeasure('BluetoothWatcher')
    if measure then
        local generation=measure:GetValue()
        if generation~=lastGeneration then parse(measure:GetStringValue()); lastGeneration=generation end
    end
    if dirty then render() end
    return 0
end
function OpenCell(i) if i>=1 and i<=6 then cell=i; page='cell'; dirty=true; render() end end
function OpenDevices() origin=page; page='devices'; index=1; dirty=true; render() end
function Back() if page=='devices' then page=origin else page='main' end; dirty=true; render() end
function Previous() index=math.max(1,index-4); dirty=true; render() end
function Next() if index+4<=#ordered then index=index+4; dirty=true; render() end end
function CycleMode()
    local mode=cfg(cell)
    write('DeviceMode'..cell,mode=='None' and 'Auto' or 'None')
    render()
end
function CycleFallback()
    local _,_,fb=cfg(cell)
    local nextValue=fallbacks[1]
    for i,value in ipairs(fallbacks) do if value==fb then nextValue=fallbacks[i%#fallbacks+1]; break end end
    write('Fallback'..cell,nextValue); render()
end
function Pick(i)
    local id=selection[i]; if not id or origin~='cell' then return end
    local owner=assignment(id)
    if owner and owner~=cell then
        SKIN:Bang('!SetOption','AdaptiveNav','Text','Already assigned to Resource '..owner)
        SKIN:Bang('!UpdateMeter','AdaptiveNav'); SKIN:Bang('!Redraw'); return
    end
    write('PinnedId'..cell,id); write('DeviceMode'..cell,'Pinned')
    page='cell'; dirty=true; render()
end
function RefreshDevices()
    SKIN:Bang('!UpdateMeasure','BluetoothWatcher')
    local measure=SKIN:GetMeasure('BluetoothWatcher')
    if measure then
        parse(measure:GetStringValue())
        lastGeneration=measure:GetValue()
    end
    render()
end

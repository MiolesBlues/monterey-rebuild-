local kind, height, step, mouse, audio, request, status, nativeBrightness
local target, displayed, tick, dragging, serial, pending, ready = 0,0,0,false,0,nil,false
local lastWritten, lastVisual, muted, waitTicks = nil,nil,false,0
local moving, pressY, dragged, clickY, clickUntil = false,nil,false,nil,0
local pollDivider = 6
local timerList, frameSeconds, timerRunning = 2,0.017,false
local anchorPending=true
local debugPath, lastSnapshot, lastFrame, lastDirection
local function trace(event,detail)
    if not debugPath then return end
    local f=io.open(debugPath,'a'); if not f then return end
    f:write(string.format('%s tick=%d %s id=%d target=%.2f displayed=%.2f drag=%s timer=%s %s\n',os.date('%H:%M:%S'),tick,event,serial,target,displayed,tostring(dragging),tostring(timerRunning),detail or '')); f:close()
end

local function clamp(n, lo, hi) return math.max(lo,math.min(hi,n)) end
local function round(n) return math.floor(n+0.5) end
local function var(k,v) SKIN:Bang('!SetVariable',k,tostring(v)) end
local function screenVar(k) return tonumber(SKIN:ReplaceVariables('#'..k..'#')) end

local function anchorRight()
    local x,y=screenVar('CURRENTCONFIGX'),screenVar('CURRENTCONFIGY')
    local w,h=screenVar('CURRENTCONFIGWIDTH'),screenVar('CURRENTCONFIGHEIGHT')
    if not x or not y or not w or not h or w<=0 or h<=0 then return false end
    local best,area,sx,sy,sw=nil,0,nil,nil,nil
    for n=1,32 do
        local a,b=screenVar('SCREENAREAX@'..n),screenVar('SCREENAREAY@'..n)
        local c,d=screenVar('SCREENAREAWIDTH@'..n),screenVar('SCREENAREAHEIGHT@'..n)
        if a and b and c and d and c>0 and d>0 then
            local overlap=math.max(0,math.min(x+w,a+c)-math.max(x,a))*math.max(0,math.min(y+h,b+d)-math.max(y,b))
            if overlap>area then best,area,sx,sy,sw=n,overlap,a,b,c end
        end
    end
    if not best then return false end
    local margin=math.max(0,round(sx+sw-x-w))
    SKIN:Bang('!SetWindowPosition',margin..'R@'..best,round(y-sy)..'@'..best,'100%','0')
    return true
end
local function read(p)
    local f=io.open(p,'r'); if not f then return nil end
    local s=f:read('*a'); f:close(); return s
end
local function write(p,s)
    local f=io.open(p,'w'); if not f then return false end
    local ok=f:write(s); f:close(); return ok~=nil
end

function Initialize()
    local fps=tonumber(SKIN:GetVariable('SliderFPS','60'))
    if fps==30 then timerList,frameSeconds=1,0.033
    elseif fps==120 then timerList,frameSeconds=3,0.008
    elseif fps==144 then timerList,frameSeconds=4,0.007 end
    kind=SKIN:GetVariable('SliderType','Volume')
    if kind=='Brightness' and SKIN:GetVariable('BrightnessDiagnostics','0')=='1' then
        debugPath=SKIN:ReplaceVariables('#CURRENTPATH#brightness-debug.log')
        local f=io.open(debugPath,'w'); if f then f:write('Monterey brightness diagnostic v1; op 1=write, 2=read\n'); f:close() end
        trace('INIT','fps='..tostring(fps))
    end
    local base=tonumber(SKIN:GetVariable('WidgetBase','75')) or 75
    local padding=tonumber(SKIN:GetVariable('PaddingBase','8')) or 8
    height=tonumber(SKIN:GetVariable('SliderHeight','')) or (2*base+2*padding)
    step=tonumber(SKIN:GetVariable('SliderStep','2')) or 2
    mouse=SKIN:GetMeasure('SliderMouse')
    if kind=='Volume' then audio=SKIN:GetMeasure('SystemVolume') elseif SKIN:GetVariable('NativeBrightness','0')=='1' then
        nativeBrightness=SKIN:GetMeasure('SystemBrightness')
    else
        request=SKIN:ReplaceVariables('#CURRENTPATH#slider-request.txt')
        status=SKIN:ReplaceVariables('#CURRENTPATH#slider-status.txt')
        os.remove(request); os.remove(status)
    end
end

local function draw()
    local level=round(displayed*10)/10
    local value=ready and (tostring(round(target))..'%') or '--'
    local icon=muted and -1 or (target==0 and 0 or math.min(3,math.ceil(target/34)))
    local function color(s,fallback)
        local r,g,b=tostring(s):match('^(%d+),%s*(%d+),%s*(%d+)')
        if r then return {clamp(tonumber(r),0,255),clamp(tonumber(g),0,255),clamp(tonumber(b),0,255)} end
        local hex=tostring(s):match('^#?(%x%x%x%x%x%x)')
        if hex then return {tonumber(hex:sub(1,2),16),tonumber(hex:sub(3,4),16),tonumber(hex:sub(5,6),16)} end
        return fallback
    end
    local function rgba(c,a) return table.concat({c[1],c[2],c[3],a},',') end
    local function contrast(c) return (c[1]*0.2126+c[2]*0.7152+c[3]*0.0722)>145 and '32,32,35,255' or '255,255,255,235' end
    local theme=SKIN:GetVariable('Theme','Dark')
    local dark=theme=='Dark' or ((theme=='Auto' or theme=='Blur' or theme=='Color') and SKIN:GetVariable('DarkMode','1')=='1')
    local bgKey=theme=='Auto' and (dark and 'DarkThemeBackground' or 'LightThemeBackground') or 'BackgroundColor'
    local fgKey=theme=='Auto' and (dark and 'DarkThemeForeground' or 'LightThemeForeground') or 'ForegroundColor'
    local bg=color(SKIN:GetVariable(bgKey,''),dark and {32,32,36} or {245,245,248})
    local fg=color(SKIN:GetVariable(fgKey,''),dark and {248,248,250} or {32,32,36})
    local track={}; for i=1,3 do track[i]=round(bg[i]*0.82+fg[i]*0.18) end
    local trackColor=rgba(track,theme=='Blur' and 155 or 235)
    -- Preserve the original white iOS fill; use the actual rendered color for contrast.
    local fill={255,255,255}
    local fillColor=rgba(fill,255)
    local boundary=8+height*(1-level/100)
    local tint=contrast(boundary<=8+height-29 and fill or track)
    local top=contrast(boundary<=30 and fill or track)
    local key=table.concat({level,value,icon,tint,top,trackColor,fillColor},'|')
    if key==lastVisual then return end
    lastVisual=key
    var('SliderLevel',level); var('SliderText',value); var('SliderVolumeIcon',icon)
    var('SliderTint',tint); var('SliderTopTint',top)
    var('SliderTrackColor',trackColor); var('SliderFillColor',fillColor)
    SKIN:Bang('!UpdateMeter','Track')
    SKIN:Bang('!UpdateMeter','Fill'); SKIN:Bang('!UpdateMeter','Percent')
    SKIN:Bang('!UpdateMeter','VolumeIcon'); SKIN:Bang('!UpdateMeter','SunIcon'); SKIN:Bang('!Redraw')
end

function AnimationFinished() timerRunning=false; trace('ANIMATION_END') end
function AnimationFrame()
    local alpha=1-math.exp(-frameSeconds/(dragging and 0.035 or 0.09))
    displayed=displayed+(target-displayed)*alpha
    if math.abs(displayed-target)<0.15 then displayed=target end
    if debugPath then
        local direction=displayed> (lastFrame or displayed) and 1 or (displayed<(lastFrame or displayed) and -1 or 0)
        if not lastFrame or math.abs(displayed-lastFrame)>=5 or direction~=lastDirection then trace('FRAME'); lastFrame=displayed; lastDirection=direction end
    end
    draw()
end

local function startAnimation()
    if not timerRunning and math.abs(displayed-target)>=0.15 then
        timerRunning=true
        SKIN:Bang('!CommandMeasure','SliderAnimationTimer','Execute '..timerList)
    end
end

local function change(value)
    if not ready or moving then return end
    value=round(clamp(value,kind=='Brightness' and 5 or 0,100))
    if value==lastWritten and value==target and not muted then return end
    if kind=='Volume' then
        SKIN:Bang('!CommandMeasure','SystemVolume','SetVolume '..value)
        waitTicks=2
    elseif nativeBrightness then
        serial=serial+1
        SKIN:Bang('!CommandMeasure','SystemBrightness','Set '..serial..' '..value)
    else
        serial=serial+1
        if not write(request,serial..' '..value..'\n') then return end
        pending=serial
    end
    target, muted, lastWritten=value,false,value
    trace('INPUT','value='..value)
end

local function fromY(y) change((1-clamp(y/height,0,1))*100) end
local function setPolling(divider)
    if pollDivider == divider then return end
    pollDivider = divider
    for _,name in ipairs({'SliderLogic','SliderMouse',kind=='Volume' and 'SystemVolume' or 'SystemBrightness'}) do
        if SKIN:GetMeasure(name) then SKIN:Bang('!SetOption',name,'UpdateDivider',tostring(divider)) end
    end
end

function Begin(y)
    if moving then return end
    setPolling(1)
    dragging,dragged,pressY=true,false,tonumber(y) or 0
end
function Finish(y)
    if moving or not dragging then return end
    y=tonumber(y) or pressY
    if dragged or math.abs(y-pressY)>=3 then fromY(y) else clickY,clickUntil=y,tick+5 end
    dragging=false
    setPolling(6)
end
function CancelDrag() dragging=false; setPolling(6) end
function ToggleMove()
    moving=not moving
    dragging,dragged,clickY=false,false,nil
    local actions='LeftMouseDownAction|LeftMouseUpAction|MouseLeaveAction|MouseScrollUpAction|MouseScrollDownAction'
    if moving then
        SKIN:Bang('!AutoSelectScreen','1')
        SKIN:Bang('!ClearMouseAction','Hit',actions)
        SKIN:Bang('!Draggable','1')
        SKIN:Bang('!SetOption','Hit','MouseActionCursor','0')
    else
        SKIN:Bang('!Draggable','0')
        anchorPending=true
        SKIN:Bang('!EnableMouseAction','Hit',actions)
        SKIN:Bang('!SetOption','Hit','MouseActionCursor','1')
    end
    var('SliderMoving',moving and 1 or 0)
    SKIN:Bang('!UpdateMeter','Hit'); SKIN:Bang('!UpdateMeter','MoveBorder'); SKIN:Bang('!UpdateMeter','MoveHint'); SKIN:Bang('!Redraw')
end
function Step(direction) change(target+step*(tonumber(direction) or 0)) end

function Update()
    tick=tick+1
    if debugPath and nativeBrightness and tick%7==1 then
        local raw=nativeBrightness:GetStringValue() or ''
        if raw~=lastSnapshot then trace('PLUGIN',raw); lastSnapshot=raw end
    end
    if anchorPending and not moving then
        SKIN:Bang('!AutoSelectScreen','1')
        anchorRight()
        anchorPending=false
    end
    if dragging then
        local sy=tonumber(SKIN:ReplaceVariables('#CURRENTCONFIGY#'))
        if sy and mouse then
            local y=mouse:GetValue()-sy-8
            if dragged or math.abs(y-pressY)>=3 then dragged=true; clickY=nil; fromY(y) end
        end
    end
    if clickY and not dragging and tick>=clickUntil then local y=clickY; clickY=nil; fromY(y) end
    if waitTicks>0 then waitTicks=waitTicks-1 end
    do
        if kind=='Volume' and audio and waitTicks==0 and not dragging then
            local v=audio:GetValue(); ready=true; muted=v<0; target=clamp(v,0,100)
        elseif nativeBrightness then
            if not dragging then
                local raw=nativeBrightness:GetStringValue() or ''
                local id,v=raw:match('^(%d+)%s+(-?%d+)%s')
                if not id then id,v=raw:match('^(%d+)%s+(-?%d+)$') end
                id,v=tonumber(id),tonumber(v)
                if id and v and id>=serial then
                    if v~=target then trace('SYNC','incoming='..v..' responseId='..id) end
                    ready=v>=0; if ready then target=clamp(v,0,100) end
                end
            end
        elseif kind=='Brightness' then
            local s=read(status)
            local a,b=(s or ''):match('^(%d+)%s+(-?%d+)\n?$')
            a,b=tonumber(a),tonumber(b)
            if a and b and (not pending or a>=pending) then
                pending=nil; ready=b>=0; if ready and not dragging then target=clamp(b,0,100) end
            end
        end
    end
    startAnimation()
    draw(); return target
end

local data, cache, key, retryAt, nextTry, failures, lastHour
local retryDelays={15,30,60,120,300}
local icons={[0]='sunny',[1]='sunny',[2]='cloudy',[3]='overcast',[45]='fog',[48]='fog',[51]='drizzle',[53]='drizzle',[55]='drizzle',[56]='drizzle',[57]='drizzle',[61]='rain',[63]='rain',[65]='rain',[66]='rain',[67]='rain',[71]='snow',[73]='snow',[75]='snow',[77]='snow',[80]='rain',[81]='rain',[82]='rain',[85]='snow',[86]='snow',[95]='thunder',[96]='thunder',[99]='thunder'}
local function set(k,v)
    v=tostring(v)
    if SKIN:GetVariable(k,'')==v then return false end
    SKIN:Bang('!SetVariable',k,v)
    return true
end
local function object(s,k) return s:match('"'..k..'"%s*:%s*(%b{})') end
local function scalar(s,k) return tonumber(s:match('"'..k..'"%s*:%s*([%-%d%.eE+]+)')) end
local function array(s,k)
    local a=s:match('"'..k..'"%s*:%s*%[(.-)%]'); if not a then return {} end
    local out={}; for token in (a..','):gmatch('(.-),') do
        token=token:match('^%s*(.-)%s*$'); out[#out+1]=tonumber(token) or token:match('^"(.-)"$') or false
    end; return out
end
local function finite(n) return type(n)=='number' and n==n and math.abs(n)<1000 end
local function parse(raw)
    if type(raw)~='string' or raw:match('"error"%s*:%s*true') then return end
    local c,h,d=object(raw,'current'),object(raw,'hourly'),object(raw,'daily')
    if not c or not h or not d then return end
    local r={temp=scalar(c,'temperature_2m'),code=scalar(c,'weather_code'),offset=scalar(raw,'utc_offset_seconds'),hour=array(h,'time'),ht=array(h,'temperature_2m'),hc=array(h,'weather_code'),day=array(d,'time'),lo=array(d,'temperature_2m_min'),hi=array(d,'temperature_2m_max'),dc=array(d,'weather_code')}
    if not finite(r.temp) or not icons[r.code] or not r.offset or #r.hour<24 or #r.day<6 then return end
    return r
end
local function redraw() SKIN:Bang('!UpdateMeasureGroup','WeatherValues'); SKIN:Bang('!UpdateMeterGroup','Meters'); SKIN:Bang('!Redraw') end
local function publish(r,now)
    local localHour=os.date('!%Y-%m-%dT%H:00',now+r.offset)
    local day=localHour:sub(1,10); local h,d
    for i,v in ipairs(r.hour) do if v==localHour then h=i; break end end
    for i,v in ipairs(r.day) do if v==day then d=i; break end end
    if not h or not d then return false end
    for i=0,5 do
        if type(r.hour[h+i])~='string' or not finite(r.ht[h+i]) or not icons[r.hc[h+i]] or type(r.day[d+i])~='string' or not finite(r.lo[d+i]) or not finite(r.hi[d+i]) or not icons[r.dc[d+i]] then return false end
    end
    local changed=false
    local function publishValue(k,v) changed=set(k,v) or changed end
    local function rounded(n) return math.floor(n+0.5) end
    publishValue('WeatherCurrentTemp',rounded(r.temp)); publishValue('WeatherCurrentIcon',icons[r.code]); publishValue('WeatherCurrentDescription',SKIN:GetVariable('tWeatherCode'..r.code,''))
    for i=1,6 do
        local j,k=h+i-1,d+i-1
        publishValue('WeatherHourlyTime'..i,r.hour[j]:sub(12,13)); publishValue('WeatherHourlyTemp'..i,rounded(r.ht[j])); publishValue('WeatherHourlyIcon'..i,icons[r.hc[j]])
        publishValue('WeatherDailyLow'..i,rounded(r.lo[k])); publishValue('WeatherDailyHigh'..i,rounded(r.hi[k])); publishValue('WeatherDailyLowValue'..i,r.lo[k]); publishValue('WeatherDailyHighValue'..i,r.hi[k]); publishValue('WeatherDailyIcon'..i,icons[r.dc[k]])
    end
    lastHour=localHour; return true,changed
end
function Initialize()
    key=table.concat({SKIN:GetVariable('Latitude'),SKIN:GetVariable('Longitude'),SKIN:GetVariable('Units')},'|')
    cache=SKIN:ReplaceVariables('#CURRENTPATH#weather-cache.txt')
    failures=0; retryAt=nil; nextTry=os.time()+45
    local f=io.open(cache,'r')
    if f then
        local stored=f:read('*l'); local stamp=tonumber(f:read('*l')); local raw=f:read('*a'); f:close()
        if stored==key and stamp and os.time()-stamp>=0 and os.time()-stamp<=21600 then
            local r=parse(raw); if r and publish(r,os.time()) then data=r end
        end
    end
end
function Failure()
    failures=failures+1; retryAt=os.time()+retryDelays[math.min(failures,#retryDelays)]; nextTry=nil
    local changed=set('IsError',1)
    changed=set('ErrorCode',1) or changed
    if changed then redraw() end
end
function Receive()
    local now=os.time(); local raw=SKIN:GetMeasure('WeatherRaw'):GetStringValue(); local r=parse(raw)
    if not r then Failure(); return end
    local valid,changed=publish(r,now)
    if not valid then Failure(); return end
    data=r; failures=0; retryAt=nil; nextTry=nil
    changed=set('IsError',0) or changed
    changed=set('ErrorCode',-1) or changed
    local f=io.open(cache,'w'); if f then f:write(key,'\n',now,'\n',raw); f:close() end
    if changed then redraw() end
end
function Update()
    local now=os.time()
    if nextTry and now>=nextTry then Failure() end
    if retryAt and now>=retryAt then retryAt=nil; nextTry=now+45; SKIN:Bang('!CommandMeasure','OpenMeteoParser','Update') end
    if data and os.date('!%Y-%m-%dT%H:00',now+data.offset)~=lastHour then
        local valid,changed=publish(data,now)
        if valid and changed then redraw() end
    end
    return 0
end

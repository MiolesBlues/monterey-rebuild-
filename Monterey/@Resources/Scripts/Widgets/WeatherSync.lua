local data, cache, key, retryAt, nextTry, failures, lastHour
local lastRaw, dirty, cacheNeedsRepair
local maxRaw, maxCache = 1048576, 1049088
local retryDelays={15,30,60,120,300}
local icons={[0]='sunny',[1]='sunny',[2]='cloudy',[3]='overcast',[45]='fog',[48]='fog',[51]='drizzle',[53]='drizzle',[55]='drizzle',[56]='drizzle',[57]='drizzle',[61]='rain',[63]='rain',[65]='rain',[66]='rain',[67]='rain',[71]='snow',[73]='snow',[75]='snow',[77]='snow',[80]='rain',[81]='rain',[82]='rain',[85]='snow',[86]='snow',[95]='thunder',[96]='thunder',[99]='thunder'}
local function set(k,v)
    v=tostring(v)
    if SKIN:GetVariable(k,'')==v then return end
    dirty=true; SKIN:Bang('!SetVariable',k,v)
end
local decode
local function finite(n) return type(n)=='number' and n==n and math.abs(n)<1000 end
local function parse(raw)
    local json=decode(raw)
    if type(json)~='table' or json.error then return end
    local c,h,d=json.current,json.hourly,json.daily
    if type(c)~='table' or type(h)~='table' or type(d)~='table' then return end
    for _,v in ipairs({h.time,h.temperature_2m,h.weather_code,d.time,d.temperature_2m_min,d.temperature_2m_max,d.weather_code}) do
        if type(v)~='table' then return end
    end
    if not h.time or not h.temperature_2m or not h.weather_code or not d.time or not d.temperature_2m_min or not d.temperature_2m_max or not d.weather_code then return end
    local r={temp=c.temperature_2m,code=c.weather_code,offset=json.utc_offset_seconds,hour=h.time,ht=h.temperature_2m,hc=h.weather_code,day=d.time,lo=d.temperature_2m_min,hi=d.temperature_2m_max,dc=d.weather_code}
    if not finite(r.temp) or not icons[r.code] or type(r.offset)~='number' or r.offset%1~=0 or math.abs(r.offset)>50400 or #r.hour<24 or #r.day<6 then return end
    return r
end
local function redraw()
    if not dirty then return end
    SKIN:Bang('!UpdateMeasureGroup','WeatherValues'); SKIN:Bang('!UpdateMeterGroup','Meters'); SKIN:Bang('!Redraw')
    dirty=false
end
local function publish(r,now)
    local localHour=os.date('!%Y-%m-%dT%H:00',now+r.offset)
    local day=localHour:sub(1,10); local h,d
    for i,v in ipairs(r.hour) do if v==localHour then h=i; break end end
    for i,v in ipairs(r.day) do if v==day then d=i; break end end
    if not h or not d then return false end
    for i=0,5 do
        if type(r.hour[h+i])~='string' or not finite(r.ht[h+i]) or not icons[r.hc[h+i]] or type(r.day[d+i])~='string' or not finite(r.lo[d+i]) or not finite(r.hi[d+i]) or not icons[r.dc[d+i]] then return false end
    end
    local function rounded(n) return math.floor(n+0.5) end
    set('WeatherCurrentTemp',rounded(r.temp)); set('WeatherCurrentIcon',icons[r.code]); set('WeatherCurrentDescription',SKIN:GetVariable('tWeatherCode'..r.code,''))
    for i=1,6 do
        local j,k=h+i-1,d+i-1
        set('WeatherHourlyTime'..i,r.hour[j]:sub(12,13)); set('WeatherHourlyTemp'..i,rounded(r.ht[j])); set('WeatherHourlyIcon'..i,icons[r.hc[j]])
        set('WeatherDailyLow'..i,rounded(r.lo[k])); set('WeatherDailyHigh'..i,rounded(r.hi[k])); set('WeatherDailyLowValue'..i,r.lo[k]); set('WeatherDailyHighValue'..i,r.hi[k]); set('WeatherDailyIcon'..i,icons[r.dc[k]])
    end
    lastHour=localHour; return true
end
local function readCache(path, now)
    local f=io.open(path,'rb')
    if not f then return end
    local size=f:seek('end')
    if not size or size>maxCache then f:close(); return end
    f:seek('set')
    local contents=f:read(size)
    f:close()
    if not contents then return end
    local stored,stamp,raw=contents:match('^([^\r\n]*)\r?\n([^\r\n]*)\r?\n(.*)$')
    stamp=tonumber(stamp)
    if stored~=key or not stamp or stamp%1~=0 or now-stamp<0 or now-stamp>21600 or not raw or #raw>maxRaw then return end
    local parsed=parse(raw)
    if not parsed then return end
    return parsed,raw
end
local function saveCache(raw, now)
    local temp=cache..'.tmp'
    local f=io.open(temp,'wb')
    if not f then return false end
    local ok=f:write(key,'\n',now,'\n',raw)
    if ok then ok=f:flush() end
    local closed=f:close()
    if not ok or not closed then os.remove(temp); return false end
    local previous=cache..'.previous'
    local primaryValid=readCache(cache,now)~=nil
    if primaryValid then
        local older=previous..'.old'
        local oldFile=io.open(previous,'rb')
        if oldFile then
            oldFile:close()
            os.remove(older)
            if not os.rename(previous,older) then os.remove(temp); return false end
        end
        if not os.rename(cache,previous) then
            os.rename(older,previous); os.remove(temp); return false
        end
        if not os.rename(temp,cache) then
            os.rename(previous,cache)
            os.rename(older,previous)
            os.remove(temp)
            return false
        end
        os.remove(older)
    else
        -- Never overwrite a valid backup with a corrupt primary.
        os.remove(cache)
        if not os.rename(temp,cache) then os.remove(temp); return false end
    end
    return true
end
function Initialize()
    decode=dofile(SKIN:ReplaceVariables('#@#Scripts\\Widgets\\WeatherJSON.lua'))
    key=table.concat({SKIN:GetVariable('Latitude'),SKIN:GetVariable('Longitude'),SKIN:GetVariable('Units')},'|')
    cache=SKIN:ReplaceVariables('#CURRENTPATH#weather-cache.txt')
    local now=os.time()
    failures=0; retryAt=nil; nextTry=now+45; cacheNeedsRepair=false
    for _,path in ipairs({cache,cache..'.previous'}) do
        local r,raw=readCache(path,now)
        if r and publish(r,now) then
            data=r; lastRaw=raw; cacheNeedsRepair=path~=cache; break
        end
    end
end
function Failure()
    failures=failures+1; retryAt=os.time()+retryDelays[math.min(failures,#retryDelays)]; nextTry=nil
    set('IsError',1); set('ErrorCode',1); redraw()
end
function Receive()
    local now=os.time(); local raw=SKIN:GetMeasure('WeatherRaw'):GetStringValue()
    if raw==lastRaw and data then
        if cacheNeedsRepair then cacheNeedsRepair=not saveCache(raw,now) end
        failures=0; retryAt=nil; nextTry=nil
        set('IsError',0); set('ErrorCode',-1); redraw(); return
    end
    local r=parse(raw)
    if not r or not publish(r,now) then Failure(); return end
    data=r; failures=0; retryAt=nil; nextTry=nil
    set('IsError',0); set('ErrorCode',-1)
    if raw~=lastRaw or cacheNeedsRepair then
        cacheNeedsRepair=not saveCache(raw,now)
        lastRaw=raw
    end
    redraw()
end
function Update()
    local now=os.time()
    if nextTry and now>=nextTry then Failure() end
    if retryAt and now>=retryAt then retryAt=nil; nextTry=now+45; SKIN:Bang('!CommandMeasure','OpenMeteoParser','Update') end
    if data and os.date('!%Y-%m-%dT%H:00',now+data.offset)~=lastHour then
        if publish(data,now) then redraw() end
    end
    return 0
end

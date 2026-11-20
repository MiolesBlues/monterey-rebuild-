-- Bounded JSON decoder for the Open-Meteo response. null remains a non-number
-- so missing temperatures can never silently become zero or shift array slots.
local function decode(source)
    if type(source)~='string' or #source>1048576 then return nil end
    local at,depth=1,0
    local function fail() error('Invalid weather JSON',0) end
    local function space() at=source:find('[^ \t\r\n]',at) or (#source+1) end
    local function utf8(n)
        if n<128 then return string.char(n) end
        if n<2048 then return string.char(192+math.floor(n/64),128+n%64) end
        if n<65536 then return string.char(224+math.floor(n/4096),128+math.floor(n/64)%64,128+n%64) end
        return string.char(240+math.floor(n/262144),128+math.floor(n/4096)%64,128+math.floor(n/64)%64,128+n%64)
    end
    local escapes={['"']='"',['\\']='\\',['/']='/',b='\b',f='\f',n='\n',r='\r',t='\t'}
    local function hex4()
        local value=source:sub(at,at+3)
        if #value~=4 or not value:match('^%x%x%x%x$') then fail() end
        at=at+4; return tonumber(value,16)
    end
    local function str()
        at=at+1
        local parts={}
        while at<=#source do
            local c=source:sub(at,at); at=at+1
            if c=='"' then return table.concat(parts) end
            if c=='\\' then
                c=source:sub(at,at); at=at+1
                if c=='u' then
                    local n=hex4()
                    if n>=55296 and n<=56319 then
                        if source:sub(at,at+1)~='\\u' then fail() end
                        at=at+2; local low=hex4()
                        if low<56320 or low>57343 then fail() end
                        n=65536+(n-55296)*1024+low-56320
                    elseif n>=56320 and n<=57343 then fail() end
                    parts[#parts+1]=utf8(n)
                elseif escapes[c] then parts[#parts+1]=escapes[c] else fail() end
            else
                if c:byte()<32 then fail() end
                parts[#parts+1]=c
            end
        end
        fail()
    end
    local value
    value=function()
        space(); depth=depth+1; if depth>32 then fail() end
        local c=source:sub(at,at); local result
        if c=='"' then result=str()
        elseif c=='{' or c=='[' then
            local object=c=='{'; local close=object and '}' or ']'
            at=at+1; space(); result={}; local count=0
            if source:sub(at,at)~=close then
                while true do
                    local key
                    if object then
                        if source:sub(at,at)~='"' then fail() end
                        key=str(); space()
                        if source:sub(at,at)~=':' or result[key]~=nil then fail() end
                        at=at+1
                    else key=count+1 end
                    result[key]=value(); count=count+1; if count>10000 then fail() end
                    space(); local separator=source:sub(at,at)
                    if separator==close then break end
                    if separator~=',' then fail() end
                    at=at+1; space()
                end
            end
            at=at+1
        elseif source:sub(at,at+3)=='null' then result=false; at=at+4
        elseif source:sub(at,at+3)=='true' then result=true; at=at+4
        elseif source:sub(at,at+4)=='false' then result=false; at=at+5
        else
            local start=at
            if c=='-' then at=at+1 end
            if source:sub(at,at)=='0' then at=at+1
            else
                local digits=source:match('^[1-9]%d*',at); if not digits then fail() end
                at=at+#digits
            end
            if source:sub(at,at)=='.' then
                at=at+1; local digits=source:match('^%d+',at); if not digits then fail() end; at=at+#digits
            end
            if source:sub(at,at):match('[eE]') then
                at=at+1; if source:sub(at,at):match('[+-]') then at=at+1 end
                local digits=source:match('^%d+',at); if not digits then fail() end; at=at+#digits
            end
            result=tonumber(source:sub(start,at-1)); if not result or result~=result or math.abs(result)==math.huge then fail() end
        end
        depth=depth-1; return result
    end
    local ok,result=pcall(value)
    if not ok then return nil end
    space(); if at<=#source then return nil end
    return result
end
return decode

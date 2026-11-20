"""Run with Python + lupa (Lua 5.1). No Rainmeter, GUI or hardware writes."""
from pathlib import Path
import argparse
import json
import tempfile
import time
import unittest
from datetime import datetime, timedelta, timezone
from lupa.lua51 import LuaRuntime

ROOT=Path(__file__).resolve().parents[1]
SCRIPTS=ROOT/'Monterey/@Resources/Scripts/Widgets'
def read_script(path):
    return path.read_text(encoding='utf-16' if path.read_bytes().startswith(b'\xff\xfe') else 'utf-8-sig')
HARNESS=r'''
SKIN={vars={},measures={},meters={},commands={}}
function SKIN:GetVariable(k,d) local v=self.vars[k]; if v==nil then return d or '' end; return v end
function SKIN:ReplaceVariables(s)
  s=s:gsub('#@#Images\\Music\\',function() return self.vars.CURRENTPATH end)
  s=s:gsub('#@#',function() return self.vars.ResourcePath end)
  return (s:gsub('#(.-)#',function(k) return tostring(self.vars[k] or ('#'..k..'#')) end))
end
function SKIN:Bang(...)
  local args={...}; self.commands[#self.commands+1]=args
  if args[1]=='!SetVariable' and not args[4] then self.vars[args[2]]=args[3] end
end
function SKIN:GetMeasure(k)
  if not self.measures[k] then
    self.measures[k]={value=0,text=''}
    local m=self.measures[k]
    function m:GetValue() return self.value end
    function m:GetStringValue() return self.text end
  end
  return self.measures[k]
end
function SKIN:GetMeter(k)
  if not self.meters[k] then
    self.meters[k]={w=100,h=100,x=0,y=0}
    local m=self.meters[k]
    function m:GetW() return self.w end
    function m:GetH() return self.h end
    function m:GetX() return self.x end
    function m:GetY() return self.y end
  end
  return self.meters[k]
end
function clear() SKIN.commands={} end
function count(bang) local n=0; for _,a in ipairs(SKIN.commands) do if not bang or a[1]==bang then n=n+1 end end; return n end
'''

class LuaTests(unittest.TestCase):
    def runtime(self,script,**variables):
        temp=tempfile.TemporaryDirectory(); self.addCleanup(temp.cleanup)
        for name,content in variables.pop('initial_files',{}).items():
            (Path(temp.name)/name).write_text(content,encoding='utf-8')
        lua=LuaRuntime(unpack_returned_tuples=True)
        lua.execute(HARNESS)
        defaults={'ResourcePath':str(ROOT/'Monterey/@Resources')+'\\','CURRENTPATH':temp.name+'\\',
                  'WidgetSize':'Medium','MusicAutoHide':'0','MusicTitleX':'0','NativeBrightness':'1','SliderType':'Brightness',
                  'Latitude':'53','Longitude':'-6','Units':'celsius','CURRENTCONFIGX':'100','CURRENTCONFIGY':'100'}
        defaults.update(variables)
        for k,v in defaults.items(): lua.globals().SKIN.vars[k]=str(v)
        # Rainmeter injects SKIN after loading the chunk, before Initialize.
        lua.execute('savedSkin=SKIN; SKIN=nil')
        lua.execute(read_script(SCRIPTS/script))
        lua.execute('SKIN=savedSkin')
        lua.globals().Initialize() if lua.globals().Initialize else None
        return lua

    def test_all_scripts_compile_as_lua51(self):
        lua=LuaRuntime(unpack_returned_tuples=True)
        for path in (ROOT/'Monterey').rglob('*.lua'):
            with self.subTest(path=path.name):
                result=lua.eval('loadstring')(read_script(path))
                self.assertFalse(isinstance(result,tuple),str(result))

    def test_contrast_idle_does_not_write(self):
        lua=self.runtime('MusicContrast.lua',BackgroundColor='ffffff')
        lua.execute('Update(); clear(); for i=1,300 do Update() end')
        self.assertEqual(lua.globals().count(),0)
        lua.execute("SKIN.vars.BackgroundColor='000000'; Update()")
        self.assertEqual(lua.globals().SKIN.vars.ForegroundColor,'FFFFFF')

    def test_slider_rejects_stale_acknowledgement(self):
        lua=self.runtime('iOSSlider.lua')
        lua.execute("SKIN:GetMeasure('SystemBrightness').text='0 40'; Update(); Step(1); SKIN:GetMeasure('SystemBrightness').text='0 12'; for i=1,7 do Update() end")
        self.assertEqual(lua.globals().SKIN.vars.SliderText,'42%')
        lua.execute("SKIN:GetMeasure('SystemBrightness').text='1 42'; for i=1,7 do Update() end")
        self.assertEqual(lua.globals().SKIN.vars.SliderText,'42%')

    def test_slider_keeps_accepting_wheel_after_failed_native_write(self):
        lua=self.runtime('iOSSlider.lua')
        lua.execute("SKIN:GetMeasure('SystemBrightness').text='0 100'; Update(); Step(-1); SKIN:GetMeasure('SystemBrightness').text='1 -1'; for i=1,7 do Update() end; Step(-1)")
        self.assertEqual(lua.globals().SKIN.vars.SliderText,'96%')
        commands=lua.globals().SKIN.commands
        self.assertTrue(any(commands[i][1]=='!CommandMeasure' and commands[i][2]=='SystemBrightness' and commands[i][3]=='Set 2 96' for i in range(1,len(commands)+1)))

    def test_slider_keeps_last_valid_percent_on_idle_read_failure(self):
        lua=self.runtime('iOSSlider.lua')
        lua.execute("SKIN:GetMeasure('SystemBrightness').text='0 60'; Update(); SKIN:GetMeasure('SystemBrightness').text='0 -1'; for i=1,7 do Update() end")
        self.assertEqual(lua.globals().SKIN.vars.SliderText,'60%')
        lua.execute("SKIN:GetMeasure('SystemBrightness').text='0 58'; for i=1,7 do Update() end")
        self.assertEqual(lua.globals().SKIN.vars.SliderText,'58%')

    def test_slider_fast_scroll_keeps_latest_target(self):
        lua=self.runtime('iOSSlider.lua')
        lua.execute("SKIN:GetMeasure('SystemBrightness').text='0 40'; Update(); for i=1,20 do Step(1) end")
        self.assertEqual(lua.globals().SKIN.vars.SliderText,'80%')
        lua.execute('for i=1,120 do AnimationFrame() end; clear(); for i=1,100 do Update() end')
        self.assertEqual(lua.globals().count('!Redraw'),0)

    def test_slider_stops_at_all_supported_fps(self):
        for fps in (60,120,144):
            lua=self.runtime('iOSSlider.lua',SliderFPS=fps)
            lua.execute("SKIN:GetMeasure('SystemBrightness').text='0 70'; Update(); clear(); for i=1,120 do AnimationFrame() end")
            commands=lua.globals().SKIN.commands
            self.assertTrue(any(commands[i][1]=='!CommandMeasure' and commands[i][3].startswith('Stop ') for i in range(1,len(commands)+1)))

    def test_anchor_retries_until_geometry_is_available(self):
        lua=self.runtime('iOSSlider.lua')
        lua.execute("Update(); SKIN.vars.CURRENTCONFIGWIDTH='98'; SKIN.vars.CURRENTCONFIGHEIGHT='182'; SKIN.vars['SCREENAREAX@1']='0'; SKIN.vars['SCREENAREAY@1']='0'; SKIN.vars['SCREENAREAWIDTH@1']='1920'; SKIN.vars['SCREENAREAHEIGHT@1']='1080'; Update()")
        self.assertEqual(lua.globals().count('!SetWindowPosition'),1)

    def test_fallback_serial_survives_refresh(self):
        lua=self.runtime('iOSSlider.lua',NativeBrightness='0',initial_files={'slider-status.txt':'500 40','slider-request.txt':'501 42'})
        lua.execute('Update(); Step(1)')
        request=Path(lua.globals().SKIN.vars.CURRENTPATH)/'slider-request.txt'
        sequence,value=request.read_text().split()
        self.assertGreater(int(sequence),501)
        self.assertEqual(int(value),42)

    def test_slider_mute_and_zero_are_distinct(self):
        lua=self.runtime('iOSSlider.lua',SliderType='Volume')
        lua.execute("SKIN:GetMeasure('SystemVolume').value=-1; Update()")
        self.assertEqual(lua.globals().SKIN.vars.SliderVolumeIcon,'-1')
        lua.execute("SKIN:GetMeasure('SystemVolume').value=0; for i=1,7 do Update() end")
        self.assertEqual(lua.globals().SKIN.vars.SliderVolumeIcon,'0')

    def test_music_short_title_idle_does_not_redraw(self):
        lua=self.runtime('MusicAnimation.lua')
        lua.execute("SKIN:GetMeter('TitleClip').w=200; Update(); clear(); for i=1,590 do Update() end")
        self.assertEqual(lua.globals().count('!Redraw'),0)
        self.assertEqual(lua.globals().count('!UpdateMeterGroup'),0)

    def test_music_marquee_uses_selected_fps(self):
        for fps,frames in ((60,90),(120,190),(144,215)):
            lua=self.runtime('MusicAnimation.lua',MusicFPS=fps)
            lua.execute("SKIN:GetMeter('TitleMeter').w=300; Update(); clear()")
            lua.execute(f'for i=1,{frames} do AnimationFrame() end')
            self.assertLess(float(lua.globals().SKIN.vars.MusicTitleX),-10)

    def test_music_rapid_cover_changes_do_not_overwrite_previous(self):
        lua=self.runtime('MusicAnimation.lua')
        folder=Path(lua.globals().SKIN.vars.CURRENTPATH)
        path=folder/'art.jpg'
        path.write_bytes(b'\xff\xd8'+b'a'*30+b'\xff\xd9')
        lua.globals().SKIN.GetMeasure(lua.globals().SKIN,'CoverMeasure').text=str(path)
        lua.execute('Update()')
        first=lua.globals().SKIN.vars.MusicCoverCurrent
        path.write_bytes(b'\xff\xd8'+b'b'*30+b'\xff\xd9')
        lua.execute('for i=1,59 do Update() end')
        second=lua.globals().SKIN.vars.MusicCoverCurrent
        path.write_bytes(b'\xff\xd8'+b'c'*30+b'\xff\xd9')
        lua.execute('for i=1,59 do Update() end')
        self.assertNotEqual(first,lua.globals().SKIN.vars.MusicCoverCurrent)
        self.assertEqual(second,lua.globals().SKIN.vars.MusicCoverPrevious)

    @staticmethod
    def payload():
        now=datetime.now(timezone.utc).replace(minute=0,second=0,microsecond=0)
        start=now.replace(hour=0)
        return {'utc_offset_seconds':0,'current':{'temperature_2m':0,'weather_code':3},
                'hourly':{'time':[(start+timedelta(hours=i)).strftime('%Y-%m-%dT%H:00') for i in range(168)],'temperature_2m':[5]*168,'weather_code':[3]*168},
                'daily':{'time':[(start+timedelta(days=i)).strftime('%Y-%m-%d') for i in range(7)],'temperature_2m_min':[-2]*7,'temperature_2m_max':[8]*7,'weather_code':[3]*7}}

    def test_weather_valid_zero_and_failure_preserve_cache(self):
        lua=self.runtime('WeatherSync.lua')
        lua.globals().SKIN.GetMeasure(lua.globals().SKIN,'WeatherRaw').text=json.dumps(self.payload())
        lua.execute('Receive()')
        self.assertEqual(lua.globals().SKIN.vars.WeatherCurrentTemp,'0')
        lua.execute("SKIN:GetMeasure('WeatherRaw').text='{}'; Receive()")
        self.assertEqual(lua.globals().SKIN.vars.WeatherCurrentTemp,'0')
        self.assertEqual(lua.globals().SKIN.vars.IsError,'1')

    def test_weather_rejects_incomplete_null_malformed_and_infinite(self):
        good=self.payload()
        cases=['{}',json.dumps(good)[:-1],json.dumps(good)+'oops',json.dumps(good).replace('"temperature_2m": 0','"temperature_2m": null'),json.dumps(good).replace('"utc_offset_seconds": 0','"utc_offset_seconds": 1e999')]
        for raw in cases:
            lua=self.runtime('WeatherSync.lua')
            lua.globals().SKIN.GetMeasure(lua.globals().SKIN,'WeatherRaw').text=raw
            lua.execute('Receive()')
            self.assertIsNone(lua.globals().SKIN.vars.WeatherCurrentTemp)
            self.assertEqual(lua.globals().SKIN.vars.IsError,'1')

    def test_weather_identical_response_does_not_republish(self):
        lua=self.runtime('WeatherSync.lua')
        lua.globals().SKIN.GetMeasure(lua.globals().SKIN,'WeatherRaw').text=json.dumps(self.payload())
        lua.execute('Receive(); clear(); Receive()')
        self.assertEqual(lua.globals().count(),0)

    def test_weather_failure_and_recovery_schedule_one_retry(self):
        lua=self.runtime('WeatherSync.lua')
        lua.execute('clock=1000; os.time=function() return clock end; Failure(); clear(); clock=1015; Update(); Update()')
        self.assertEqual(lua.globals().count('!CommandMeasure'),1)
        lua.execute('clear(); clock=1070; Update()')
        self.assertEqual(lua.globals().count('!CommandMeasure'),0)

    def test_weather_missing_hourly_value_preserves_last_valid(self):
        lua=self.runtime('WeatherSync.lua')
        raw=self.payload(); raw['current']['temperature_2m']=12
        measure=lua.globals().SKIN.GetMeasure(lua.globals().SKIN,'WeatherRaw')
        measure.text=json.dumps(raw); lua.execute('Receive()')
        raw['hourly']['temperature_2m']=[None]*168
        measure.text=json.dumps(raw); lua.execute('Receive()')
        self.assertEqual(lua.globals().SKIN.vars.WeatherCurrentTemp,'12')

    def test_weather_recovers_previous_cache_when_primary_is_corrupt(self):
        cached='53|-6|celsius\n'+str(int(time.time()))+'\n'+json.dumps(self.payload())
        lua=self.runtime('WeatherSync.lua',initial_files={'weather-cache.txt':'broken','weather-cache.txt.previous':cached})
        self.assertEqual(lua.globals().SKIN.vars.WeatherCurrentTemp,'0')

    def test_weather_cache_location_must_match(self):
        cached='54|-6|celsius\n'+str(int(time.time()))+'\n'+json.dumps(self.payload())
        lua=self.runtime('WeatherSync.lua',initial_files={'weather-cache.txt':cached})
        self.assertIsNone(lua.globals().SKIN.vars.WeatherCurrentTemp)

    def test_json_null_does_not_shift_array(self):
        lua=LuaRuntime(unpack_returned_tuples=True)
        decode=lua.execute((SCRIPTS/'WeatherJSON.lua').read_text())
        self.assertEqual(decode('[1,null,3]')[3],3)
        for raw in ('[01]','[1,]','{"a":1,"a":2}','[NaN]','"\\uD800"','{"a":1} junk'):
            self.assertIsNone(decode(raw),raw)
        self.assertEqual(decode('"\\uD83D\\uDE00"'),'😀')

    def test_adaptive_deduplicates_pinned_and_refreshes_names(self):
        lua=self.runtime('AdaptiveMonitor.lua',DeviceMode1='Pinned',PinnedId1='id',DeviceMode2='Auto',DeviceMode3='Auto',DeviceMode4='None')
        def publish(name,category,level):
            row=','.join(v.encode().hex().upper() for v in ('id',name,category))+f',1,{level};'
            m=lua.globals().SKIN.GetMeasure(lua.globals().SKIN,'BluetoothWatcher')
            m.text='OK:'+row; m.value+=1; lua.globals().Update()
        publish('Phone','Phone',50)
        self.assertEqual(lua.globals().SKIN.vars.Meter1,'Phone1')
        self.assertNotEqual(lua.globals().SKIN.vars.Meter2,'Phone2')
        lua.execute('clear()'); publish('New name','Headphones',50)
        self.assertGreater(lua.globals().count('!SetOption'),0)
        self.assertEqual(lua.globals().count('!Redraw'),1)
        lua.execute('clear(); Update()')
        self.assertEqual(lua.globals().count(),0)

    def test_adaptive_wide_restores_percent_after_bluetooth_disconnect(self):
        lua=self.runtime('AdaptiveMonitor.lua',WidgetSize='Wide',DeviceMode1='Pinned',PinnedId1='id',Fallback1='CPU')
        watcher=lua.globals().SKIN.GetMeasure(lua.globals().SKIN,'BluetoothWatcher')
        row=','.join(v.encode().hex().upper() for v in ('id','Long Bluetooth device name','Headphones'))
        watcher.text='OK:'+row+',1,50;'; watcher.value=1
        lua.globals().Update()
        commands=lua.globals().SKIN.commands
        text_options=[commands[i] for i in range(1,len(commands)+1)
                      if commands[i][1]=='!SetOption' and commands[i][2]=='MeterText1' and commands[i][3]=='Text']
        self.assertEqual(text_options[-1][4],'Long Bluetooth device name')
        self.assertTrue(any(commands[i][1]=='!SetOption' and commands[i][2]=='MeterText1' and commands[i][3]=='FontSize'
                            and commands[i][4]=='(#WidgetHeight#*0.06)' for i in range(1,len(commands)+1)))

        lua.execute('clear()')
        watcher.text='OK:'+row+',0,-1;'; watcher.value=2
        lua.globals().Update()
        commands=lua.globals().SKIN.commands
        self.assertTrue(any(commands[i][1]=='!SetOption' and commands[i][2]=='MeterText1' and commands[i][3]=='Text'
                            and commands[i][4]=='%1 %' for i in range(1,len(commands)+1)))
        self.assertEqual(lua.globals().SKIN.vars.Meter1,'CPU')

    def test_adaptive_offline_pinned_uses_existing_fallback(self):
        lua=self.runtime('AdaptiveMonitor.lua',DeviceMode1='Pinned',PinnedId1='id',Fallback1='CPU')
        row=','.join(v.encode().hex().upper() for v in ('id','Phone','Phone'))+',0,-1;'
        m=lua.globals().SKIN.GetMeasure(lua.globals().SKIN,'BluetoothWatcher'); m.text='OK:'+row; m.value=1
        lua.globals().Update()
        self.assertEqual(lua.globals().SKIN.vars.Meter1,'CPU')

    def test_adaptive_unknown_battery_is_not_displayed_as_zero(self):
        lua=self.runtime('AdaptiveMonitor.lua',WidgetSize='Large',DeviceMode1='Auto')
        row=','.join(v.encode().hex().upper() for v in ('id','Phone','Phone'))+',1,-1;'
        m=lua.globals().SKIN.GetMeasure(lua.globals().SKIN,'BluetoothWatcher'); m.text='OK:'+row; m.value=1
        lua.globals().Update()
        commands=lua.globals().SKIN.commands
        self.assertTrue(any(commands[i][1]=='!SetOption' and commands[i][2]=='MeterValue1' and commands[i][3]=='Hidden' and commands[i][4]=='1' for i in range(1,len(commands)+1)))

    def test_adaptive_preserves_legacy_guid_case_in_pinned_settings(self):
        device_id='{abcdef01-2345-6789-abcd-ef0123456789}'
        lua=self.runtime('AdaptiveMonitor.lua',DeviceMode1='Pinned',PinnedId1=device_id.upper(),Fallback1='CPU')
        row=','.join(v.encode().hex().upper() for v in (device_id,'Phone','Phone'))+',1,50;'
        m=lua.globals().SKIN.GetMeasure(lua.globals().SKIN,'BluetoothWatcher');m.text='OK:'+row;m.value=1
        lua.globals().Update()
        self.assertEqual(lua.globals().SKIN.vars.Meter1,'Phone1')
        self.assertEqual(lua.globals().SKIN.vars.PinnedId1,device_id.upper())

if __name__=='__main__':
    parser=argparse.ArgumentParser(); parser.add_argument('--root',type=Path)
    args,remaining=parser.parse_known_args()
    if args.root:
        ROOT=args.root.resolve(); SCRIPTS=ROOT/'Monterey/@Resources/Scripts/Widgets'
    unittest.main(argv=[__file__]+remaining)

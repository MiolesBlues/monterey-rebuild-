"""Change-driven updates using the existing Lua 5.1 Rainmeter harness."""
import json
import unittest
from pathlib import Path

import test_lua


class EventUpdateTests(unittest.TestCase):
    def runtime(self, script, **kwargs):
        harness = test_lua.LuaTests('runTest')
        self.addCleanup(harness.doCleanups)
        return harness.runtime(script, **kwargs)

    def test_monitor_animates_only_after_source_change(self):
        lua = self.runtime('MonitorAnimation.lua')
        lua.execute("clear(); Start(); assert(count('!CommandMeasure')==0)")
        lua.execute("SKIN:GetMeasure('CPURounded').value=40; Start()")
        self.assertEqual(lua.globals().count('!CommandMeasure'), 1)
        lua.execute("clear(); AnimationFrame()")
        self.assertEqual(lua.globals().SKIN.vars.CPUValue, '20.000000')
        self.assertEqual(lua.globals().count('!Redraw'), 1)
        lua.execute("for i=1,20 do AnimationFrame() end; clear(); AnimationFrame()")
        self.assertEqual(lua.globals().count('!Redraw'), 0)

    def test_music_metadata_redraws_only_on_change(self):
        lua = self.runtime('MusicAnimation.lua')
        lua.execute("SKIN:GetMeasure('MusicProcessRunning').value=1; SKIN:GetMeasure('TitleMeasure').text='Song'; clear(); MetadataChanged()")
        self.assertEqual(lua.globals().count('!Redraw'), 1)
        lua.execute("clear(); MetadataChanged()")
        self.assertEqual(lua.globals().count('!Redraw'), 0)

    def test_music_new_short_title_is_centered_before_redraw(self):
        lua = self.runtime('MusicAnimation.lua', WidgetSize='Wide')
        skin = lua.globals().SKIN
        skin.GetMeasure(skin, 'MusicProcessRunning').value = 1
        skin.GetMeter(skin, 'TitleClip').w = 200
        skin.GetMeter(skin, 'TitleMeter').w = 80
        skin.GetMeasure(skin, 'TitleMeasure').text = 'First'
        lua.execute('MetadataChanged(); clear()')

        skin.GetMeter(skin, 'TitleMeter').w = 120
        skin.GetMeasure(skin, 'TitleMeasure').text = 'Second'
        lua.execute('MetadataChanged()')
        self.assertEqual(skin.vars.MusicTitleX, '40')
        commands = [skin.commands[i] for i in range(1, len(skin.commands) + 1)]
        centered = next(i for i, command in enumerate(commands)
                        if command[1] == '!SetVariable' and command[2] == 'MusicTitleX' and command[3] == '40')
        redraw = next(i for i, command in enumerate(commands) if command[1] == '!Redraw')
        self.assertLess(centered, redraw)

    def test_music_restores_background_and_foreground_after_theme_startup(self):
        memory = 'MUSIC1\n' + 'Song'.encode().hex().upper() + '\n\n' + 'FFFFFF'.encode().hex().upper() + '\n\n'
        lua = self.runtime('MusicAnimation.lua', BackgroundColor='f94151', ForegroundColor='FFFFFF')
        skin = lua.globals().SKIN
        (Path(skin.vars.CURRENTPATH) / 'last-track.txt').write_bytes(memory.encode())
        lua.execute('Initialize()')
        lua.execute('''
            local originalBang = SKIN.Bang
            function SKIN:Bang(...)
                local args = {...}
                if args[1] == '!UpdateMeasure' and args[2] == 'CoverForegroundColor' then
                    self.vars.ForegroundColor = '000000'
                end
                return originalBang(self, ...)
            end
        ''')
        # Auto theme can run after the music script initializes.
        skin.vars.BackgroundColor = 'f94151'
        skin.vars.ForegroundColor = 'FFFFFF'
        skin.GetMeasure(skin, 'MusicProcessRunning').value = 1
        skin.GetMeasure(skin, 'StateMeasure').value = 1
        skin.GetMeasure(skin, 'TitleMeasure').text = 'Song'
        lua.execute('clear(); Update()')
        self.assertEqual(skin.vars.BackgroundColor, 'FFFFFF')
        self.assertEqual(skin.vars.ForegroundColor, '000000')
        commands = [skin.commands[i] for i in range(1, len(skin.commands) + 1)]
        self.assertTrue(any(command[1] == '!UpdateMeterGroup' and command[2] == 'Text' for command in commands))
        self.assertTrue(any(command[1] == '!UpdateMeterGroup' and command[2] == 'Buttons' for command in commands))
        self.assertEqual((Path(skin.vars.CURRENTPATH) / 'last-track.txt').read_bytes(), memory.encode())

        skin.vars.BackgroundColor = 'f94151'
        skin.vars.ForegroundColor = 'FFFFFF'
        lua.execute('clear(); Update()')
        self.assertEqual(skin.vars.BackgroundColor, 'FFFFFF')
        self.assertEqual(skin.vars.ForegroundColor, '000000')

    def test_music_hover_preview_only_opens_for_wide(self):
        for size in ('Small', 'Medium', 'Large', 'Wide'):
            with self.subTest(size=size):
                lua = self.runtime('MusicAnimation.lua', WidgetSize=size, MusicZoomHover='1')
                skin = lua.globals().SKIN
                artwork = Path(skin.vars.CURRENTPATH) / 'art.jpg'
                artwork.write_bytes(b'\xff\xd8' + b'a' * 30 + b'\xff\xd9')
                skin.GetMeasure(skin, 'MusicProcessRunning').value = 1
                skin.GetMeasure(skin, 'TitleMeasure').text = 'Song'
                skin.GetMeasure(skin, 'CoverMeasure').text = str(artwork)
                skin.GetMeasure(skin, 'MusicCursorX').value = 150
                skin.GetMeasure(skin, 'MusicCursorY').value = 150
                lua.execute('MetadataChanged(); clear(); AnimationFrame()')
                self.assertEqual(lua.globals().count('!ActivateConfig'), int(size == 'Wide'))

    def test_music_preview_unloads_after_hover_and_reopens_on_demand(self):
        lua=self.runtime('MusicAnimation.lua',WidgetSize='Wide',MusicZoomHover='1')
        skin=lua.globals().SKIN
        artwork=Path(skin.vars.CURRENTPATH)/'art.jpg'
        artwork.write_bytes(b'\xff\xd8'+b'a'*30+b'\xff\xd9')
        skin.GetMeasure(skin,'MusicProcessRunning').value=1
        skin.GetMeasure(skin,'TitleMeasure').text='Song'
        skin.GetMeasure(skin,'CoverMeasure').text=str(artwork)
        x=skin.GetMeasure(skin,'MusicCursorX'); y=skin.GetMeasure(skin,'MusicCursorY')
        x.value=y.value=150
        lua.execute('MetadataChanged(); clear(); AnimationFrame()')
        self.assertEqual(lua.globals().count('!ActivateConfig'),1)
        lua.execute('for i=1,20 do AnimationFrame() end; clear()')
        x.value=y.value=1000
        lua.execute('for i=1,20 do AnimationFrame() end')
        self.assertEqual(lua.globals().count('!DeactivateConfig'),1)
        lua.execute('clear(); for i=1,10 do AnimationFrame() end')
        self.assertEqual(lua.globals().count('!ActivateConfig'),0)
        x.value=y.value=150
        lua.execute('AnimationFrame()')
        self.assertEqual(lua.globals().count('!ActivateConfig'),1)

    def test_music_retries_artwork_after_title_changes_at_same_path(self):
        lua = self.runtime('MusicAnimation.lua')
        artwork = Path(lua.globals().SKIN.vars.CURRENTPATH) / 'art.jpg'
        old = b'\xff\xd8' + b'a' * 30 + b'\xff\xd9'
        new = b'\xff\xd8' + b'b' * 30 + b'\xff\xd9'
        artwork.write_bytes(old)
        lua.globals().SKIN.GetMeasure(lua.globals().SKIN, 'MusicProcessRunning').value = 1
        lua.globals().SKIN.GetMeasure(lua.globals().SKIN, 'CoverMeasure').text = str(artwork)
        lua.globals().SKIN.GetMeasure(lua.globals().SKIN, 'TitleMeasure').text = 'First'
        lua.execute('MetadataChanged()')
        previous = lua.globals().SKIN.vars.MusicCoverCurrent
        self.assertEqual(Path(previous).read_bytes(), old)

        lua.globals().SKIN.GetMeasure(lua.globals().SKIN, 'TitleMeasure').text = 'Second'
        lua.execute('MetadataChanged(); for i=1,11 do Update() end; clear()')
        artwork.write_bytes(new)
        lua.execute('Update()')
        current = lua.globals().SKIN.vars.MusicCoverCurrent
        self.assertNotEqual(current, previous)
        self.assertEqual(Path(current).read_bytes(), new)
        self.assertEqual(lua.globals().SKIN.vars.MusicCoverPrevious, previous)
        self.assertEqual(lua.globals().count('!UpdateMeasure'), 1)

        lua.execute('clear(); Update()')
        self.assertEqual(lua.globals().count('!Redraw'), 0)

    def test_music_color_waits_for_artwork_and_fades_with_it(self):
        lua = self.runtime('MusicAnimation.lua', BackgroundColor='000000')
        artwork = Path(lua.globals().SKIN.vars.CURRENTPATH) / 'art.jpg'
        artwork.write_bytes(b'\xff\xd8' + b'a' * 30 + b'\xff\xd9')
        skin = lua.globals().SKIN
        skin.GetMeasure(skin, 'MusicProcessRunning').value = 1
        skin.GetMeasure(skin, 'StateMeasure').value = 1
        skin.GetMeasure(skin, 'CoverMeasure').text = str(artwork)
        skin.GetMeasure(skin, 'CoverColor').text = 'FF0000'
        skin.GetMeasure(skin, 'TitleMeasure').text = 'First'
        lua.execute('MetadataChanged()')
        self.assertEqual(skin.vars.BackgroundColor, 'FF0000')

        skin.GetMeasure(skin, 'TitleMeasure').text = 'Second'
        skin.GetMeasure(skin, 'CoverColor').text = '0000FF'
        lua.execute('MetadataChanged()')
        self.assertEqual(skin.vars.BackgroundColor, 'FF0000')

        artwork.write_bytes(b'\xff\xd8' + b'b' * 30 + b'\xff\xd9')
        lua.execute('MetadataChanged()')
        self.assertEqual(skin.vars.BackgroundColor, 'FF0000')
        self.assertEqual(skin.vars.MusicCoverAlpha, '0')
        lua.execute('AnimationFrame()')
        self.assertNotEqual(skin.vars.BackgroundColor, 'FF0000')
        self.assertNotEqual(skin.vars.BackgroundColor, '0000FF')
        self.assertGreater(int(skin.vars.MusicCoverAlpha), 0)
        lua.execute('for i=1,40 do AnimationFrame() end')
        self.assertEqual(skin.vars.BackgroundColor, '0000FF')
        self.assertEqual(skin.vars.MusicCoverAlpha, '255')

    def test_music_forces_new_thumbnail_when_plugin_keeps_old_cover(self):
        lua = self.runtime('MusicAnimation.lua', Plugin='MediaPlayer')
        artwork = Path(lua.globals().SKIN.vars.CURRENTPATH) / 'art.jpg'
        old = b'\xff\xd8' + b'a' * 30 + b'\xff\xd9'
        new = b'\xff\xd8' + b'b' * 30 + b'\xff\xd9'
        artwork.write_bytes(old)
        skin = lua.globals().SKIN
        skin.GetMeasure(skin, 'MusicProcessRunning').value = 1
        skin.GetMeasure(skin, 'CoverMeasure').text = str(artwork)
        skin.GetMeasure(skin, 'TitleMeasure').text = 'First'
        lua.execute('MetadataChanged()')
        first = skin.vars.MusicCoverCurrent

        # The plugin only writes the delayed thumbnail after its cover state is reset.
        lua.execute('''
            local originalBang = SKIN.Bang
            local resetting = false
            local resetCount = 0
            function SKIN:Bang(...)
                local args = {...}
                if args[1] == '!SetOption' and args[2] == 'CoverMeasure' then
                    resetting = args[4] == 'Title'
                    if args[4] == 'Cover' then resetCount = resetCount + 1 end
                elseif args[1] == '!UpdateMeasure' and args[2] == 'CoverMeasure' and resetCount >= 4 and not resetting then
                    local file = io.open(SKIN:GetMeasure('CoverMeasure').text, 'wb')
                    file:write(string.char(255,216), string.rep('b',30), string.char(255,217))
                    file:close()
                end
                return originalBang(self, ...)
            end
        ''')
        skin.GetMeasure(skin, 'TitleMeasure').text = 'Second'
        lua.execute('MetadataChanged(); for i=1,34 do Update() end')
        self.assertEqual(skin.vars.MusicCoverCurrent, first)
        lua.execute('Update()')
        current = skin.vars.MusicCoverCurrent
        self.assertNotEqual(current, first)
        self.assertEqual(Path(current).read_bytes(), new)
        options = [skin.commands[i] for i in range(1, len(skin.commands) + 1)
                   if skin.commands[i][1] == '!SetOption' and skin.commands[i][2] == 'CoverMeasure']
        self.assertEqual([item[4] for item in options], ['Title', 'Cover'] * 4)

    def test_weather_same_data_does_not_redraw(self):
        lua = self.runtime('WeatherSync.lua')
        source = lua.globals().SKIN.GetMeasure(lua.globals().SKIN, 'WeatherRaw')
        source.text = json.dumps(test_lua.LuaTests.payload())
        lua.execute('Receive(); clear(); Receive()')
        self.assertEqual(lua.globals().count('!Redraw'), 0)
        changed = test_lua.LuaTests.payload()
        changed['current']['temperature_2m'] = 2
        source.text = json.dumps(changed)
        lua.execute('Receive()')
        self.assertEqual(lua.globals().count('!Redraw'), 1)

    def test_music_saved_cover_requires_matching_active_session(self):
        metadata='MUSIC1\n'+ 'Song'.encode().hex().upper()+'\n\n'+'FFFFFF'.encode().hex().upper()+'\njpg\n'
        image=b'\xff\xd8'+b'a'*30+b'\xff\xd9'
        for title,active,cover,expected in (('Song',0,image,False),('Other',1,image,False),
                                             ('Song',1,image,True),('Song',1,None,False),
                                             ('Song',1,b'broken',False)):
            with self.subTest(title=title,active=active,cover=cover):
                lua=self.runtime('MusicAnimation.lua')
                folder=Path(lua.globals().SKIN.vars.CURRENTPATH)
                (folder/'last-track.txt').write_bytes(metadata.encode())
                if cover is not None: (folder/'last-cover.jpg').write_bytes(cover)
                lua.execute('Initialize()')
                skin=lua.globals().SKIN
                self.assertIsNone(skin.vars.MusicCoverCurrent)
                skin.GetMeasure(skin,'MusicProcessRunning').value=active
                skin.GetMeasure(skin,'TitleMeasure').text=title
                lua.execute('MetadataChanged()')
                self.assertEqual(skin.vars.MusicCoverCurrent==str(folder/'last-cover.jpg'),expected)
                if not active:
                    lua.execute('Update()')
                    self.assertNotEqual(skin.vars.BackgroundColor,'FFFFFF')

    def test_music_identical_cover_skips_decode_and_disk_write(self):
        lua=self.runtime('MusicAnimation.lua')
        skin=lua.globals().SKIN
        artwork=Path(skin.vars.CURRENTPATH)/'art.jpg'
        artwork.write_bytes(b'\xff\xd8'+b'a'*30+b'\xff\xd9')
        skin.GetMeasure(skin,'MusicProcessRunning').value=1
        skin.GetMeasure(skin,'TitleMeasure').text='Song'
        skin.GetMeasure(skin,'CoverMeasure').text=str(artwork)
        lua.execute('MetadataChanged(); clear()')
        lua.execute("writes=0; oldOpen=io.open; io.open=function(path,mode) if mode=='wb' and path:find('cover') then writes=writes+1 end; return oldOpen(path,mode) end; MetadataChanged()")
        self.assertEqual(lua.globals().writes,0)
        self.assertEqual(lua.globals().count('!UpdateMeasure'),0)

    def test_weather_cache_startup_states_do_not_poll_or_redraw_repeatedly(self):
        import time
        valid='53|-6|celsius\n'+str(int(time.time()))+'\n'+json.dumps(test_lua.LuaTests.payload())
        stale='53|-6|celsius\n'+str(int(time.time())-21601)+'\n'+json.dumps(test_lua.LuaTests.payload())
        for data,has_value in ((valid,True),(None,False),('broken',False),(stale,False)):
            with self.subTest(data=bool(data),has_value=has_value):
                files={'weather-cache.txt':data} if data is not None else {}
                lua=self.runtime('WeatherSync.lua',initial_files=files)
                self.assertEqual(lua.globals().SKIN.vars.WeatherCurrentTemp=='0',has_value)
                lua.execute('clear(); Update(); Update()')
                self.assertEqual(lua.globals().count('!Redraw'),0)
                self.assertEqual(lua.globals().count('!CommandMeasure'),0)

    def test_monitor_device_menu_builds_list_only_while_open(self):
        lua=self.runtime('AdaptiveSettings.lua')
        skin=lua.globals().SKIN
        watcher=skin.GetMeasure(skin,'BluetoothWatcher')
        def snapshot(name,generation):
            row=','.join(value.encode().hex().upper() for value in ('device-id',name,'Phone'))
            watcher.text='OK:'+row+',1,75;'
            watcher.value=generation
        snapshot('First',1)
        lua.execute('Update(); clear(); Update()')
        self.assertEqual(lua.globals().count(),0)
        lua.execute('''
            local original=SKIN.Bang
            function SKIN:Bang(...)
                original(self,...)
                local args={...}
                if args[1]=='!UpdateMeasure' and args[2]=='BluetoothWatcher' then Update() end
            end
        ''')
        lua.execute('OpenDevices()')
        self.assertGreater(lua.globals().count('!CommandMeasure'),0)
        self.assertEqual(lua.globals().count('!UpdateMeasure'),1)
        self.assertEqual(lua.globals().count('!Redraw'),1)
        self.assertEqual(lua.globals().SKIN.vars.Meter1,None)
        lua.execute('Back(); clear()')
        snapshot('Second',2)
        lua.execute('Update()')
        self.assertEqual(lua.globals().count(),0)
        lua.execute('OpenDevices()')
        commands=[skin.commands[i] for i in range(1,len(skin.commands)+1)]
        self.assertTrue(any(c[1]=='!CommandMeasure' and c[2]=='BluetoothWatcher' and c[3].startswith('NAME|') for c in commands))
        lua.execute('Finalize()')
        lua.execute('local _,list=debug.getupvalue(Finalize,2); assert(next(list)==nil)')
        settings=test_lua.read_script(test_lua.ROOT/'Monterey/Widgets/Monitor/Settings.ini')
        self.assertIn('OnRefreshAction=[!UpdateMeasure AdaptiveSettings]',settings)
        self.assertIn('OnChangeAction=[!UpdateMeasure AdaptiveSettings]',settings)
        self.assertIn('UpdateDivider=-1',settings)

    def test_auxiliary_configs_have_single_lazy_activation_route(self):
        root=test_lua.ROOT/'Monterey'
        for name in ('Sidebar.inc','Widget.inc'):
            source=test_lua.read_script(root/'@Resources/Scripts/Contexts'/name)
            self.assertNotIn('!ToggleConfig "Monterey" "Settings.ini"',source)
            self.assertIn('!ActivateConfig "Monterey" "Settings.ini"',source)
        for name in ('Preview.ini','Fullscreen.ini'):
            source=test_lua.read_script(root/'MusicPreview'/name)
            self.assertIn('Update=-1',source)
        self.assertIn('#SettingsTab#.inc',test_lua.read_script(root/'Settings.ini'))

    def test_pinned_cell_samples_device_without_building_device_list(self):
        lua=self.runtime('AdaptiveSettings.lua',DeviceMode1='Pinned',PinnedId1='device-id')
        skin=lua.globals().SKIN
        row=','.join(value.encode().hex().upper() for value in ('device-id','Phone','Phone'))
        watcher=skin.GetMeasure(skin,'BluetoothWatcher')
        watcher.text='OK:'+row+',1,75;'
        watcher.value=1
        lua.execute('Update(); clear(); OpenCell(1)')
        commands=[skin.commands[i] for i in range(1,len(skin.commands)+1)]
        self.assertTrue(any(c[1]=='!CommandMeasure' and c[2]=='BluetoothWatcher' and c[3]=='PICK|3|device-id' for c in commands))
        self.assertFalse(any(c[1]=='!CommandMeasure' and c[2]=='BluetoothWatcher' and c[3].startswith('NAME|') for c in commands))
        self.assertEqual(lua.globals().count('!UpdateMeasure'),1)


if __name__ == '__main__':
    unittest.main()

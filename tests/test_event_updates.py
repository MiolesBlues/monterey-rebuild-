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


if __name__ == '__main__':
    unittest.main()

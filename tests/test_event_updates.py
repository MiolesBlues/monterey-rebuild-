"""Change-driven updates using the existing Lua 5.1 Rainmeter harness."""
import json
import unittest

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

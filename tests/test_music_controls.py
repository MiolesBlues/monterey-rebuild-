"""Playback feedback and Rainmeter wiring, using the existing Lua 5.1 harness."""
import re
import unittest

import test_lua
from test_lua import ROOT, read_script


class MusicControlTests(unittest.TestCase):
    def runtime(self, size='Medium'):
        harness = test_lua.LuaTests('runTest')
        self.addCleanup(harness.doCleanups)
        lua = harness.runtime('MusicAnimation.lua', WidgetSize=size, Hovered=1)
        lua.execute("SKIN:GetMeasure('StateMeasure').value=1; Update(); clear()")
        return lua

    @staticmethod
    def visible(lua, size, meter):
        text = read_script(ROOT / 'Monterey/Widgets/Music' / (size + '.ini'))
        block = re.search(r'\[' + meter + r'\]\s*\n(.*?)(?=\n\[|\Z)', text, re.S)[1]
        expression = re.search(r'^Hidden=(.*)$', block, re.M)[1].strip()
        expression = re.sub(r'#(\w+)#', lambda m: str(lua.globals().SKIN.vars[m[1]]), expression)
        expression = expression.replace('<>', '~=').replace('||', ' or ').replace('&&', ' and ')
        expression = re.sub(r'(?<![<>=~])=(?!=)', '==', expression)
        return not lua.eval(expression)

    def test_all_sizes_switch_in_the_click_handler_and_ignore_stale_state(self):
        for size in ('Small', 'Medium', 'Large', 'Wide'):
            with self.subTest(size=size):
                lua = self.runtime(size)
                self.assertTrue(self.visible(lua, size, 'PauseMeter'))
                lua.globals().Playback('Pause')
                self.assertEqual(lua.globals().SKIN.vars.MusicPlaybackState, '2')
                self.assertTrue(self.visible(lua, size, 'PlayMeter'))
                self.assertFalse(self.visible(lua, size, 'PauseMeter'))
                self.assertEqual(lua.globals().count('!Redraw'), 1)
                lua.execute('for i=1,90 do Update() end')
                self.assertEqual(lua.globals().SKIN.vars.MusicPlaybackState, '2')
                lua.execute("SKIN:GetMeasure('StateMeasure').value=2; Update()")
                lua.globals().Playback('Play')
                self.assertTrue(self.visible(lua, size, 'PauseMeter'))
                self.assertFalse(self.visible(lua, size, 'PlayMeter'))
                lua.execute('for i=1,90 do Update() end')
                self.assertEqual(lua.globals().SKIN.vars.MusicPlaybackState, '1')
                commands = lua.globals().SKIN.commands
                sent = [commands[i][3] for i in range(1, len(commands)+1)
                        if commands[i][1] == '!CommandMeasure' and commands[i][2] == 'TitleMeasure']
                self.assertEqual(sent, ['Pause', 'Play'])

    def test_rapid_pause_play_keeps_the_latest_target(self):
        lua = self.runtime()
        lua.execute("Playback('Pause'); Playback('Play'); Update()")
        self.assertEqual(lua.globals().SKIN.vars.MusicPlaybackState, '1')
        lua.execute("SKIN:GetMeasure('StateMeasure').value=2; for i=1,40 do Update() end")
        self.assertEqual(lua.globals().SKIN.vars.MusicPlaybackState, '1')
        lua.execute("SKIN:GetMeasure('StateMeasure').value=1; Update()")
        self.assertEqual(lua.globals().SKIN.vars.MusicPlaybackState, '1')

    def test_failed_command_reconciles_to_real_state(self):
        lua = self.runtime()
        lua.execute("Playback('Pause'); for i=1,117 do Update() end")
        self.assertEqual(lua.globals().SKIN.vars.MusicPlaybackState, '2')
        lua.globals().Update()
        self.assertEqual(lua.globals().SKIN.vars.MusicPlaybackState, '1')

    def test_external_changes_redraw_on_the_next_update_then_settle(self):
        lua = self.runtime()
        lua.execute("SKIN:GetMeasure('StateMeasure').value=2; Update()")
        self.assertEqual(lua.globals().SKIN.vars.MusicPlaybackState, '2')
        self.assertEqual(lua.globals().count('!Redraw'), 1)
        lua.execute('clear(); for i=1,20 do Update() end')
        self.assertEqual(lua.globals().count('!Redraw'), 0)
        lua.execute("SKIN:GetMeasure('StateMeasure').value=0; Update()")
        self.assertEqual(lua.globals().SKIN.vars.MusicPlaybackState, '0')

    def test_each_size_routes_both_buttons_to_the_feedback_handler(self):
        for size in ('Small', 'Medium', 'Large', 'Wide'):
            text = read_script(ROOT / 'Monterey/Widgets/Music' / (size + '.ini'))
            self.assertNotIn('[StateMeasure]', text)
            for command in ('Play', 'Pause'):
                self.assertIn('LeftMouseUpAction=[!CommandMeasure MusicRefresh "Playback(\'' + command + '\')"]', text)
        measures = read_script(ROOT / 'Monterey/@Resources/Scripts/Widgets/Music.inc')
        state = re.search(r'\[StateMeasure\](.*?)(?=\n\[|\Z)', measures, re.S)[1]
        self.assertIn('UpdateDivider=6', state)
        for name in ('TitleMeasure', 'ArtistMeasure', 'CoverMeasure'):
            block = re.search(r'\[' + name + r'\](.*?)(?=\n\[|\Z)', measures, re.S)[1]
            self.assertIn('UpdateDivider=59', block)


if __name__ == '__main__':
    unittest.main()

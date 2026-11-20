"""Deterministic counts of Lua-issued bangs, not Rainmeter renderer frames."""
import argparse
import json
from pathlib import Path
import test_lua

def measure(root):
    test_lua.ROOT=root; test_lua.SCRIPTS=root/'Monterey/@Resources/Scripts/Widgets'
    case=test_lua.LuaTests()
    try:
        lua=case.runtime('MusicAnimation.lua')
        lua.execute("SKIN:GetMeter('TitleClip').w=200; Update(); clear(); for i=1,3540 do Update() end")
        music={'explicit_redraws':lua.globals().count('!Redraw'),'meter_group_updates':lua.globals().count('!UpdateMeterGroup'),'bangs':lua.globals().count()}
        lua=case.runtime('MusicContrast.lua',BackgroundColor='ffffff')
        lua.execute('Update(); clear(); for i=1,60 do Update() end')
        contrast={'variable_writes':lua.globals().count('!SetVariable')}
        lua=case.runtime('iOSSlider.lua')
        lua.execute("SKIN:GetMeasure('SystemBrightness').text='0 50'; Update(); clear(); for i=1,45 do AnimationFrame() end")
        slider={'variable_writes':lua.globals().count('!SetVariable'),'meter_updates':lua.globals().count('!UpdateMeter'),'explicit_redraws':lua.globals().count('!Redraw')}
        return {'music_idle_3540_updates':music,'contrast_60_unchanged_updates':contrast,'slider_45_frames_to_50_percent':slider}
    finally: case.doCleanups()

if __name__=='__main__':
    parser=argparse.ArgumentParser(); parser.add_argument('before',type=Path); parser.add_argument('after',type=Path)
    args=parser.parse_args(); print(json.dumps({'before':measure(args.before),'after':measure(args.after)},indent=2))

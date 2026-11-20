[Variables]
Phone1Level=-1
Phone1Color=#GreenColor#
Phone2Level=-1
Phone2Color=#GreenColor#
Phone3Level=-1
Phone3Color=#GreenColor#
Phone4Level=-1
Phone4Color=#GreenColor#
Phone5Level=-1
Phone5Color=#GreenColor#
Phone6Level=-1
Phone6Color=#GreenColor#

[PhoneBatteryQuery]
Measure=Plugin
Plugin=RunCommand
Program=powershell.exe
Parameter=-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "#@#Scripts\Widgets\PhoneBattery.ps1"
State=Hide
OutputType=ANSI
Timeout=12000
UpdateDivider=-1
FinishAction=[!CommandMeasure PhoneBatteryLogic "Finished()"]

[Phone1Measure]
Measure=Calc
Formula=#Phone1Level#
MinValue=0
MaxValue=100
DynamicVariables=1
UpdateDivider=-1

[Phone1Rounded]
Measure=Calc
Formula=#Phone1Level#
MinValue=0
MaxValue=100
DynamicVariables=1
UpdateDivider=-1

[Phone2Measure]
Measure=Calc
Formula=#Phone2Level#
MinValue=0
MaxValue=100
DynamicVariables=1
UpdateDivider=-1

[Phone2Rounded]
Measure=Calc
Formula=#Phone2Level#
MinValue=0
MaxValue=100
DynamicVariables=1
UpdateDivider=-1

[Phone3Measure]
Measure=Calc
Formula=#Phone3Level#
MinValue=0
MaxValue=100
DynamicVariables=1
UpdateDivider=-1

[Phone3Rounded]
Measure=Calc
Formula=#Phone3Level#
MinValue=0
MaxValue=100
DynamicVariables=1
UpdateDivider=-1

[Phone4Measure]
Measure=Calc
Formula=#Phone4Level#
MinValue=0
MaxValue=100
DynamicVariables=1
UpdateDivider=-1

[Phone4Rounded]
Measure=Calc
Formula=#Phone4Level#
MinValue=0
MaxValue=100
DynamicVariables=1
UpdateDivider=-1

[Phone5Measure]
Measure=Calc
Formula=#Phone5Level#
MinValue=0
MaxValue=100
DynamicVariables=1
UpdateDivider=-1

[Phone5Rounded]
Measure=Calc
Formula=#Phone5Level#
MinValue=0
MaxValue=100
DynamicVariables=1
UpdateDivider=-1

[Phone6Measure]
Measure=Calc
Formula=#Phone6Level#
MinValue=0
MaxValue=100
DynamicVariables=1
UpdateDivider=-1

[Phone6Rounded]
Measure=Calc
Formula=#Phone6Level#
MinValue=0
MaxValue=100
DynamicVariables=1
UpdateDivider=-1

[PhoneBatteryLogic]
Measure=Script
ScriptFile=#@#Scripts\Widgets\PhoneBattery.lua
UpdateDivider=10

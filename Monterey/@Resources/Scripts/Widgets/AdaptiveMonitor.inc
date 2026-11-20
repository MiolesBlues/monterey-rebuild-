[BluetoothWatcher]
Measure=Plugin
Plugin=MontereyBluetooth
UpdateDivider=10

[AdaptiveMonitor]
Measure=Script
ScriptFile=#@#Scripts\Widgets\AdaptiveMonitor.lua
UpdateDivider=10

[Variables]
Phone1Level=0
Phone1Color=#GreenColor#
Phone2Level=0
Phone2Color=#GreenColor#
Phone3Level=0
Phone3Color=#GreenColor#
Phone4Level=0
Phone4Color=#GreenColor#
Phone5Level=0
Phone5Color=#GreenColor#
Phone6Level=0
Phone6Color=#GreenColor#

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
DynamicVariables=1
UpdateDivider=-1

function SetStep()
    local input=SKIN:GetVariable('SliderStepInput','')
    if not input:match('^%d+$') then return end
    local step=tonumber(input)
    if not step or step<1 or step>50 then return end
    step=tostring(step)
    local kind=SKIN:GetVariable('SliderType','')
    if kind~='Brightness' and kind~='Volume' then return end
    SKIN:Bang('!WriteKeyValue','Variables','SliderStep',step,SKIN:ReplaceVariables('#@#Variables\\'..kind..'Slider.inc'))
    SKIN:Bang('!SetVariable','SliderStep',step)
    SKIN:Bang('!SetOption','StepValue','Text',step)
    SKIN:Bang('!UpdateMeter','StepValue')
    SKIN:Bang('!Redraw')
    SKIN:Bang('!Refresh','Monterey\\Widgets\\'..kind)
end

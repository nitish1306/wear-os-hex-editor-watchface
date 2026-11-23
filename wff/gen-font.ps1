param([string]$OutFile, [ValidateSet('blue','green')][string]$Theme = 'blue', [switch]$Test)

if ($Theme -eq 'blue') { $bg='bg_empty'; $bars='bars'; $primary='white'; $accent='cyan' }
else { $bg='bg_green'; $bars='bars_green'; $primary='green_primary'; $accent='green' }

$sb = New-Object System.Text.StringBuilder
function L($s){ [void]$sb.AppendLine($s) }
function X($s){ $s -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' -replace '"','&quot;' }

# nested ternary: integer expr (0..15) -> hex char string "0".."F"
function HexChar([string]$n) {
  $e = '"F"'
  for ($i = 14; $i -ge 0; $i--) { $c = '{0:x}' -f $i; $e = "($n == $i) ? `"$c`" : $e" }
  return $e
}
# robust config gate: matches int index, string index, or option id
function Gate([string]$id, [int]$idx, [string]$opt) {
  return "([CONFIGURATION.$id] == $idx || [CONFIGURATION.$id] == `"$idx`" || [CONFIGURATION.$id] == `"$opt`")"
}

L '<?xml version="1.0" encoding="utf-8"?>'
L '<WatchFace width="480" height="480">'
L '  <BitmapFonts>'
L "    <BitmapFont name=""hp"">"
foreach ($c in @('0','1','2','3','4','5','6','7','8','9','a','b','c','d','e','f')) {
  L "      <Character name=""$c"" resource=""g${c}_$primary"" width=""39"" height=""46"" />"
}
L '    </BitmapFont>'
L "    <BitmapFont name=""ha"">"
foreach ($c in @('0','1','2','3','4','5','6','7','8','9','a','b','c','d','e','f')) {
  L "      <Character name=""$c"" resource=""g${c}_$accent"" width=""39"" height=""46"" />"
}
L '    </BitmapFont>'
L '  </BitmapFonts>'
L ''
L '  <UserConfigurations>'
L '    <ListConfiguration id="time_mode" displayName="cfg_time" defaultValue="hex">'
L '      <ListOption id="hex" displayName="opt_hex" /><ListOption id="dec" displayName="opt_dec" />'
L '    </ListConfiguration>'
if (-not $Test) {
  L '    <ListConfiguration id="date_mode" displayName="cfg_date" defaultValue="hex">'
  L '      <ListOption id="hex" displayName="opt_hex" /><ListOption id="dec" displayName="opt_dec" />'
  L '    </ListConfiguration>'
  L '    <ListConfiguration id="hr_mode" displayName="cfg_hr" defaultValue="hex">'
  L '      <ListOption id="hex" displayName="opt_hex" /><ListOption id="dec" displayName="opt_dec" />'
  L '    </ListConfiguration>'
  L '    <ListConfiguration id="steps_mode" displayName="cfg_steps" defaultValue="hex">'
  L '      <ListOption id="hex" displayName="opt_hex" /><ListOption id="dec" displayName="opt_dec" />'
  L '    </ListConfiguration>'
  L '    <ListConfiguration id="battery_mode" displayName="cfg_battery" defaultValue="hex">'
  L '      <ListOption id="hex" displayName="opt_hex" /><ListOption id="dec" displayName="opt_dec" />'
  L '    </ListConfiguration>'
  L '    <ListConfiguration id="endianness" displayName="cfg_endian" defaultValue="little">'
  L '      <ListOption id="little" displayName="opt_little" /><ListOption id="big" displayName="opt_big" />'
  L '    </ListConfiguration>'
}
L '  </UserConfigurations>'
L ''
L '  <Scene backgroundColor="#FF000000">'
L "    <PartImage x=""-60"" y=""-60"" width=""600"" height=""600""><Image resource=""$bg"" /></PartImage>"
L "    <PartImage x=""-60"" y=""-114"" width=""600"" height=""600""><Variant mode=""AMBIENT"" target=""alpha"" value=""0"" /><Image resource=""$bars"" /></PartImage>"

# background 00 grid
$numW=78; $numH=46; $numVInt=56
for ($x=-4;$x -le 4;$x++){ for($y=-5;$y -le 5;$y++){
  $isSlot = ($x -eq 0 -and $y -eq 0) -or ($x -eq 1 -and $y -eq 0) -or ($x -eq 2 -and $y -eq 0) -or
            ($x -eq 1 -and $y -eq -1) -or ($x -eq 2 -and $y -eq -1) -or ($x -eq 2 -and $y -eq 1) -or
            ($x -eq 1 -and $y -eq 1) -or ($x -eq -1 -and $y -eq 0) -or ($x -eq -1 -and $y -eq -1) -or ($x -eq -1 -and $y -eq 1)
  if($isSlot){continue}
  $px=240+($x-1)*$numW; $py=240+$y*$numVInt-24
  L "    <PartImage x=""$px"" y=""$py"" width=""$numW"" height=""$numH""><Variant mode=""AMBIENT"" target=""alpha"" value=""0"" /><Image resource=""d00_$accent"" /></PartImage>"
}}

# emit a PartText with given font, region, align, template params, and alpha gate
function PT($font,$x,$y,$w,$h,$align,$params,$gateExpr,$ambient) {
  $g = X $gateExpr
  L "    <PartText x=""$x"" y=""$y"" width=""$w"" height=""$h"">"
  L "      <Transform target=""alpha"" value=""$g ? 255 : 0"" />"
  if ($ambient) { L "      <Variant mode=""AMBIENT"" target=""alpha"" value=""$g ? 255 : 0"" />" }
  else { L '      <Variant mode="AMBIENT" target="alpha" value="0" />' }
  L "      <Text align=""$align""><Font family=""$font"" size=""46"">"
  $fmt = ($params | ForEach-Object { '%s' }) -join ''
  L "        <Template>$fmt"
  foreach ($p in $params) { $pe = X $p; L "          <Parameter expression=""$pe"" />" }
  L '        </Template>'
  L '      </Font></Text>'
  L '    </PartText>'
}

$gHexTime = Gate 'time_mode' 0 'hex'
$gDecTime = Gate 'time_mode' 1 'dec'

# TIME
$hx='[HOUR_0_23]'; $mn='[MINUTE]'; $sc='[SECOND]'
PT 'hp' 123 216 78 46 'CENTER' @((HexChar "floor($hx/16)"),(HexChar "$hx%16")) $gHexTime $true
PT 'hp' 123 216 78 46 'CENTER' @("numberFormat('00',$hx)") $gDecTime $true
PT 'hp' 201 216 78 46 'CENTER' @((HexChar "floor($mn/16)"),(HexChar "$mn%16")) $gHexTime $true
PT 'hp' 201 216 78 46 'CENTER' @("numberFormat('00',$mn)") $gDecTime $true
PT 'ha' 279 216 78 46 'CENTER' @((HexChar "floor($sc/16)"),(HexChar "$sc%16")) $gHexTime $false
PT 'ha' 279 216 78 46 'CENTER' @("numberFormat('00',$sc)") $gDecTime $false

if (-not $Test) {
  $gHexDate = Gate 'date_mode' 0 'hex'; $gDecDate = Gate 'date_mode' 1 'dec'
  $gHexHR = Gate 'hr_mode' 0 'hex'; $gDecHR = Gate 'hr_mode' 1 'dec'
  $gHexSt = Gate 'steps_mode' 0 'hex'; $gDecSt = Gate 'steps_mode' 1 'dec'
  $gHexBat = Gate 'battery_mode' 0 'hex'; $gDecBat = Gate 'battery_mode' 1 'dec'
  $gLittle = Gate 'endianness' 0 'little'; $gBig = Gate 'endianness' 1 'big'

  # DATE: DD MM YY  (top row y=150)
  $day='[DAY]'; $mon='[MONTH]'; $yr='[YEAR_S]'
  # DD at x=123, MM at x=201, YY at x=279
  PT 'ha' 123 150 78 46 'CENTER' @((HexChar "floor($day/16)"),(HexChar "$day%16")) $gHexDate $false
  PT 'ha' 123 150 78 46 'CENTER' @("numberFormat('00',$day)") $gDecDate $false
  PT 'ha' 201 150 78 46 'CENTER' @((HexChar "floor($mon/16)"),(HexChar "$mon%16")) $gHexDate $false
  PT 'ha' 201 150 78 46 'CENTER' @("numberFormat('00',$mon)") $gDecDate $false
  PT 'ha' 279 150 78 46 'CENTER' @((HexChar "floor($yr/16)"),(HexChar "$yr%16")) $gHexDate $false
  PT 'ha' 279 150 78 46 'CENTER' @("numberFormat('00',$yr)") $gDecDate $false

  # HR (4 digits) top-left region x=30 y=90 w=200 align LEFT
  $hr='round([HEART_RATE])'
  $hrHi="floor($hr/256)"; $hrLo="$hr%256"
  $hrHexLittle = @((HexChar "floor($hrLo/16)"),(HexChar "$hrLo%16"),(HexChar "floor($hrHi/16)"),(HexChar "$hrHi%16"))
  $hrHexBig    = @((HexChar "floor($hrHi/16)"),(HexChar "$hrHi%16"),(HexChar "floor($hrLo/16)"),(HexChar "$hrLo%16"))
  PT 'ha' 30 90 200 46 'LEFT' $hrHexLittle "($gHexHR && $gLittle)" $false
  PT 'ha' 30 90 200 46 'LEFT' $hrHexBig    "($gHexHR && $gBig)" $false
  $hrDecHi="floor($hr/100)"; $hrDecLo="$hr%100"
  PT 'ha' 30 90 200 46 'LEFT' @("numberFormat('00',$hrDecLo)","numberFormat('00',$hrDecHi)") "($gDecHR && $gLittle)" $false
  PT 'ha' 30 90 200 46 'LEFT' @("numberFormat('00',$hrDecHi)","numberFormat('00',$hrDecLo)") "($gDecHR && $gBig)" $false

  # BATTERY top-right x=300 y=90 w=150 align RIGHT
  $bat='[BATTERY_PERCENT]'
  PT 'ha' 300 90 150 46 'RIGHT' @((HexChar "floor($bat/16)"),(HexChar "$bat%16")) $gHexBat $false
  PT 'ha' 300 90 150 46 'RIGHT' @("numberFormat('000',$bat)") $gDecBat $false

  # STEPS bottom-left x=30 y=300 w=240 align LEFT
  $st='[STEP_COUNT]'
  $stHi="floor($st/256)"; $stLo="$st%256"
  $stHexLittle = @((HexChar "floor($stLo/16)"),(HexChar "$stLo%16"),(HexChar "floor($stHi/16)"),(HexChar "$stHi%16"))
  $stHexBig    = @((HexChar "floor($stHi/16)"),(HexChar "$stHi%16"),(HexChar "floor($stLo/16)"),(HexChar "$stLo%16"))
  PT 'ha' 30 300 240 46 'LEFT' $stHexLittle "($gHexSt && $gLittle)" $false
  PT 'ha' 30 300 240 46 'LEFT' $stHexBig    "($gHexSt && $gBig)" $false
  PT 'ha' 30 300 240 46 'LEFT' @("numberFormat('00000',$st)") $gDecSt $false
}

L '    <PartImage x="-10" y="-10" width="500" height="500"><Variant mode="AMBIENT" target="alpha" value="0" /><Image resource="vignetting_strong" /></PartImage>'
L '  </Scene>'
L '</WatchFace>'

[System.IO.File]::WriteAllText($OutFile, $sb.ToString(), [System.Text.Encoding]::UTF8)
Write-Output "Written $OutFile theme=$Theme test=$Test length=$($sb.Length)"

param([string]$OutFile, [ValidateSet('blue','green')][string]$Theme = 'blue')

if ($Theme -eq 'blue') { $bg='bg_empty'; $bars='bars'; $primary='white'; $accent='cyan'; $time='time' }
else { $bg='bg_green'; $bars='bars_green'; $primary='green_primary'; $accent='green'; $time='time' }

$sb = New-Object System.Text.StringBuilder
function L($s){ [void]$sb.AppendLine($s) }
function X($s){ $s -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' }

L '<?xml version="1.0" encoding="utf-8"?>'
L '<WatchFace width="480" height="480">'
L '  <Scene backgroundColor="#FF000000">'
L "    <PartImage x=""-60"" y=""-60"" width=""600"" height=""600""><Image resource=""$bg"" /></PartImage>"
L "    <PartImage x=""-60"" y=""-114"" width=""600"" height=""600""><Variant mode=""AMBIENT"" target=""alpha"" value=""0"" /><Image resource=""$bars"" /></PartImage>"

# occupied byte-tile slots (left,top) — excluded from the decorative 00 grid
$occupied = @(
  @(0,0),(1,0),(2,0),          # time
  @(1,-1),(2,-1),(2,1),(1,1),  # date
  @(-2,-1),(-1,-1),            # hr
  @(-2,0),(-1,0),              # battery
  @(-3,1),(-2,1),(-1,1)        # steps
)
$numW=78; $numH=46; $numVInt=56
for ($x=-4;$x -le 4;$x++){ for($y=-5;$y -le 5;$y++){
  $skip=$false
  foreach($o in $occupied){ if($o[0] -eq $x -and $o[1] -eq $y){ $skip=$true; break } }
  if($skip){continue}
  $px=240+($x-1)*$numW; $py=240+$y*$numVInt-24
  L "    <PartImage x=""$px"" y=""$py"" width=""$numW"" height=""$numH""><Variant mode=""AMBIENT"" target=""alpha"" value=""0"" /><Image resource=""d00_$accent"" /></PartImage>"
}}

# One byte tile showing a decimal pair (00..99) via BCD-encoded dXX image.
function ByteSlot {
  param([int]$left,[int]$top,[string]$pairExpr,[int]$lo,[int]$hi,[string]$res,[bool]$ambient,[int]$dx=0,[int]$dy=0,[string]$indent='    ')
  $px=240+($left-1)*$numW+$dx; $py=240+$top*$numVInt-24+$dy
  $pe = X $pairExpr
  for ($p=$lo;$p -le $hi;$p++){
    $bcd = [int]([math]::Floor($p/10)*16 + ($p%10))
    $hex = "{0:x2}" -f $bcd
    L "$indent<PartImage x=""$px"" y=""$py"" width=""$numW"" height=""$numH"">"
    L "$indent  <Transform target=""alpha"" value=""$pe == $p ? 255 : 0"" />"
    if ($ambient) { L "$indent  <Variant mode=""AMBIENT"" target=""alpha"" value=""$pe == $p ? 255 : 0"" />" }
    else { L "$indent  <Variant mode=""AMBIENT"" target=""alpha"" value=""0"" />" }
    L "$indent  <Image resource=""d${hex}_$res"" />"
    L "$indent</PartImage>"
  }
}

# TIME (decimal HH MM SS) — wrapped in a gyro-warped group
$warp = 'clamp((abs([ACCELEROMETER_Z] + 9.8 * cos(rad([ACCELEROMETER_ANGLE_X]))) - 2.5) / 7.5, 0, 1)'
L '    <Group name="time_warp" x="162" y="216" width="234" height="46" pivotX="0.5" pivotY="0.5">'
L "      <Gyro x=""clamp([ACCELEROMETER_ANGLE_Y] * 0.10, -10, 10) * $warp"" y=""clamp([ACCELEROMETER_ANGLE_X] * 0.06, -6, 6) * $warp"" angle=""clamp([ACCELEROMETER_ANGLE_Z] * 0.05, -4, 4) * $warp"" scaleX=""1 + 0.30 * $warp"" scaleY=""1 + 0.18 * $warp"" />"
ByteSlot -left 0 -top 0 -pairExpr '[HOUR_0_23]' -lo 0 -hi 23 -res $time -ambient $true -dx -162 -dy -216 -indent '      '
ByteSlot -left 1 -top 0 -pairExpr '[MINUTE]' -lo 0 -hi 59 -res $time -ambient $true -dx -162 -dy -216 -indent '      '
ByteSlot -left 2 -top 0 -pairExpr '[SECOND]' -lo 0 -hi 59 -res $accent -ambient $false -dx -162 -dy -216 -indent '      '
L '    </Group>'
# DATE (YY MM DD + day-of-week)
ByteSlot -left 1 -top -1 -pairExpr '([YEAR] % 100)' -lo 0 -hi 99 -res $accent -ambient $false
ByteSlot -left 2 -top -1 -pairExpr '[MONTH]' -lo 1 -hi 12 -res $accent -ambient $false
ByteSlot -left 2 -top 1 -pairExpr '[DAY]' -lo 1 -hi 31 -res $accent -ambient $false
ByteSlot -left 1 -top 1 -pairExpr '[DAY_OF_WEEK]' -lo 1 -hi 7 -res $accent -ambient $false
# HEART RATE (2 decimal pairs)
ByteSlot -left -2 -top -1 -pairExpr 'floor(round([HEART_RATE]) / 100)' -lo 0 -hi 2 -res $accent -ambient $false
ByteSlot -left -1 -top -1 -pairExpr '(round([HEART_RATE]) % 100)' -lo 0 -hi 99 -res $accent -ambient $false
# BATTERY (2 decimal pairs, 00..100)
ByteSlot -left -2 -top 0 -pairExpr 'floor([BATTERY_PERCENT] / 100)' -lo 0 -hi 1 -res $accent -ambient $false
ByteSlot -left -1 -top 0 -pairExpr '([BATTERY_PERCENT] % 100)' -lo 0 -hi 99 -res $accent -ambient $false
# STEPS (3 decimal pairs, 000000..999999)
ByteSlot -left -3 -top 1 -pairExpr 'floor([STEP_COUNT] / 10000)' -lo 0 -hi 9 -res $accent -ambient $false
ByteSlot -left -2 -top 1 -pairExpr '(floor([STEP_COUNT] / 100) % 100)' -lo 0 -hi 99 -res $accent -ambient $false
ByteSlot -left -1 -top 1 -pairExpr '([STEP_COUNT] % 100)' -lo 0 -hi 99 -res $accent -ambient $false

L '    <PartImage x="-10" y="-10" width="500" height="500"><Variant mode="AMBIENT" target="alpha" value="0" /><Image resource="vignetting_strong" /></PartImage>'
L '  </Scene>'
L '</WatchFace>'

[System.IO.File]::WriteAllText($OutFile, $sb.ToString(), [System.Text.Encoding]::UTF8)
Write-Output "Written $OutFile theme=$Theme length=$($sb.Length)"

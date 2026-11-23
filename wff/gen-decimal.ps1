param([string]$OutFile, [ValidateSet('blue','green')][string]$Theme = 'blue')

if ($Theme -eq 'blue') { $bg='bg_empty'; $bars='bars'; $primary='white'; $accent='cyan'; $time='time' }
else { $bg='bg_green'; $bars='bars_green'; $primary='green_primary'; $accent='green'; $time='time' }

$sb = New-Object System.Text.StringBuilder
function L($s){ [void]$sb.AppendLine($s) }
function X($s){ $s -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' }

L '<?xml version="1.0" encoding="utf-8"?>'
L '<WatchFace width="480" height="480">'
L '  <Scene backgroundColor="#FF000000">'
$dz = '[ACCELEROMETER_Z]'
$zoomIn = "clamp(($dz - 3.5) / 6, 0, 1)"
$zoomOut = "clamp((-$dz - 3.5) / 6, 0, 1)"
L "    <PartImage x=""-60"" y=""-60"" width=""600"" height=""600""><Image resource=""$bg"" /></PartImage>"
L "    <PartImage x=""-60"" y=""-114"" width=""600"" height=""600""><Variant mode=""AMBIENT"" target=""alpha"" value=""0"" /><Image resource=""$bars"" /></PartImage>"
L '    <Group name="face_warp" x="0" y="0" width="480" height="480" pivotX="0.5" pivotY="0.5">'
L "      <Transform target=""scaleX"" value=""1 + 0.40 * $zoomIn - 0.12 * $zoomOut""><Animation duration=""0.7"" interpolation=""EASE_IN_OUT"" fps=""30"" /></Transform>"
L "      <Transform target=""scaleY"" value=""1 + 0.28 * $zoomIn - 0.08 * $zoomOut""><Animation duration=""0.7"" interpolation=""EASE_IN_OUT"" fps=""30"" /></Transform>"
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
  param([int]$left,[int]$top,[string]$pairExpr,[int]$lo,[int]$hi,[string]$res,[bool]$ambient,[int]$dx=0,[int]$dy=0,[string]$indent='    ',[string]$show='1')
  $px=240+($left-1)*$numW+$dx; $py=240+$top*$numVInt-24+$dy
  $pe = X $pairExpr
  $vis = X $show
  # Unused gated slots keep a 00 tile so the CRT grid never has a hole.
  if ($show -ne '1') {
    L "$indent<PartImage x=""$px"" y=""$py"" width=""$numW"" height=""$numH"">"
    L "$indent  <Transform target=""alpha"" value=""(1 - ($vis)) * 255"" />"
    L "$indent  <Variant mode=""AMBIENT"" target=""alpha"" value=""0"" />"
    L "$indent  <Image resource=""d00_$res"" />"
    L "$indent</PartImage>"
  }
  for ($p=$lo;$p -le $hi;$p++){
    $bcd = [int]([math]::Floor($p/10)*16 + ($p%10))
    $hex = "{0:x2}" -f $bcd
    $alpha = "($vis) * ($pe == $p ? 255 : 0)"
    L "$indent<PartImage x=""$px"" y=""$py"" width=""$numW"" height=""$numH"">"
    L "$indent  <Transform target=""alpha"" value=""$alpha"" />"
    if ($ambient) { L "$indent  <Variant mode=""AMBIENT"" target=""alpha"" value=""$alpha"" />" }
    else { L "$indent  <Variant mode=""AMBIENT"" target=""alpha"" value=""0"" />" }
    L "$indent  <Image resource=""d${hex}_$res"" />"
    L "$indent</PartImage>"
  }
}

# TIME (decimal HH MM SS)
ByteSlot -left 0 -top 0 -pairExpr '[HOUR_0_23]' -lo 0 -hi 23 -res $time -ambient $true
ByteSlot -left 1 -top 0 -pairExpr '[MINUTE]' -lo 0 -hi 59 -res $time -ambient $true
ByteSlot -left 2 -top 0 -pairExpr '[SECOND]' -lo 0 -hi 59 -res $accent -ambient $false
# DATE: 00 YY / DD MM (values shifted one slot from the original layout)
ByteSlot -left 1 -top -1 -pairExpr '0' -lo 0 -hi 0 -res $accent -ambient $false
ByteSlot -left 2 -top -1 -pairExpr '([YEAR] % 100)' -lo 0 -hi 99 -res $accent -ambient $false
ByteSlot -left 1 -top 1 -pairExpr '[DAY]' -lo 1 -hi 31 -res $accent -ambient $false
ByteSlot -left 2 -top 1 -pairExpr '[MONTH]' -lo 1 -hi 12 -res $accent -ambient $false
# HEART RATE: left-aligned (67 -> 67 00, 167 -> 01 67)
$hr = 'round([HEART_RATE])'
ByteSlot -left -2 -top -1 -pairExpr "($hr >= 100 ? floor($hr / 100) : ($hr % 100))" -lo 0 -hi 99 -res $accent -ambient $false
ByteSlot -left -1 -top -1 -pairExpr "($hr % 100)" -lo 0 -hi 99 -res $accent -ambient $false -show "($hr >= 100 ? 1 : 0)"
# BATTERY (2 decimal pairs, 00..100)
ByteSlot -left -2 -top 0 -pairExpr 'floor([BATTERY_PERCENT] / 100)' -lo 0 -hi 1 -res $accent -ambient $false
ByteSlot -left -1 -top 0 -pairExpr '([BATTERY_PERCENT] % 100)' -lo 0 -hi 99 -res $accent -ambient $false
# STEPS: left-aligned (86 -> 86 00 00, 2345 -> 23 45 00, 10030 -> 01 00 30)
$step = '[STEP_COUNT]'
ByteSlot -left -3 -top 1 -pairExpr "($step >= 10000 ? floor($step / 10000) : ($step >= 100 ? (floor($step / 100) % 100) : ($step % 100)))" -lo 0 -hi 99 -res $accent -ambient $false
ByteSlot -left -2 -top 1 -pairExpr "($step >= 10000 ? (floor($step / 100) % 100) : ($step % 100))" -lo 0 -hi 99 -res $accent -ambient $false -show "($step >= 100 ? 1 : 0)"
ByteSlot -left -1 -top 1 -pairExpr "($step % 100)" -lo 0 -hi 99 -res $accent -ambient $false -show "($step >= 10000 ? 1 : 0)"

L '    </Group>'
# Vignette stays fixed on screen; an extra copy darkens only when the face zooms out.
L '    <PartImage x="-10" y="-10" width="500" height="500"><Variant mode="AMBIENT" target="alpha" value="0" /><Image resource="vignetting_strong" /></PartImage>'
L "    <PartImage x=""-10"" y=""-10"" width=""500"" height=""500""><Transform target=""alpha"" value=""255 * $zoomOut""><Animation duration=""0.7"" interpolation=""EASE_IN_OUT"" fps=""30"" /></Transform><Variant mode=""AMBIENT"" target=""alpha"" value=""0"" /><Image resource=""vignetting_strong"" /></PartImage>"
L '  </Scene>'
L '</WatchFace>'

[System.IO.File]::WriteAllText($OutFile, $sb.ToString(), [System.Text.Encoding]::UTF8)
Write-Output "Written $OutFile theme=$Theme length=$($sb.Length)"

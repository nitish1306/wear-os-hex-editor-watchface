param([string]$OutFile, [ValidateSet('blue','green')][string]$Theme = 'blue')

if ($Theme -eq 'blue') {
  $bg = 'bg_empty'; $bars = 'bars'; $primary = 'white'; $accent = 'cyan'
} else {
  $bg = 'bg_green'; $bars = 'bars_green'; $primary = 'green_primary'; $accent = 'green'
}

$sb = New-Object System.Text.StringBuilder
function L($s){ [void]$sb.AppendLine($s) }
function X($s){ $s -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' }

L '<?xml version="1.0" encoding="utf-8"?>'
L '<WatchFace width="480" height="480">'
L '  <Scene backgroundColor="#FF000000">'
L "    <PartImage x=""-60"" y=""-60"" width=""600"" height=""600""><Image resource=""$bg"" /></PartImage>"
L "    <PartImage x=""-60"" y=""-114"" width=""600"" height=""600""><Variant mode=""AMBIENT"" target=""alpha"" value=""0"" /><Image resource=""$bars"" /></PartImage>"

$numW = 78; $numH = 46; $numVInt = 56
$minX = -4; $maxX = 4; $minY = -5; $maxY = 5
for ($x = $minX; $x -le $maxX; $x++) {
  for ($y = $minY; $y -le $maxY; $y++) {
    $isSlot = ($x -eq 0 -and $y -eq 0) -or ($x -eq 1 -and $y -eq 0) -or ($x -eq 2 -and $y -eq 0) -or
              ($x -eq 1 -and $y -eq -1) -or ($x -eq 2 -and $y -eq -1) -or ($x -eq 2 -and $y -eq 1) -or
              ($x -eq 1 -and $y -eq 1) -or ($x -eq -1 -and $y -eq 0) -or ($x -eq -1 -and $y -eq -1) -or ($x -eq -1 -and $y -eq 1)
    if ($isSlot) { continue }
    $px = 240 + ($x - 1) * $numW; $py = 240 + $y * $numVInt - 24
    L "    <PartImage x=""$px"" y=""$py"" width=""$numW"" height=""$numH""><Variant mode=""AMBIENT"" target=""alpha"" value=""0"" /><Image resource=""d00_$accent"" /></PartImage>"
  }
}

function Slot {
  param([int]$left, [int]$top, [string]$srcExpr, [int]$lo, [int]$hi, [string]$res, [bool]$ambient)
  $px = 240 + ($left - 1) * $numW; $py = 240 + $top * $numVInt - 24
  for ($v = $lo; $v -le $hi; $v++) {
    $hex = "{0:x2}" -f $v
    $cond = X "$srcExpr == $v"
    L "    <PartImage x=""$px"" y=""$py"" width=""$numW"" height=""$numH"">"
    L "      <Transform target=""alpha"" value=""$cond ? 255 : 0"" />"
    if ($ambient) { L "      <Variant mode=""AMBIENT"" target=""alpha"" value=""$cond ? 255 : 0"" />" }
    else { L '      <Variant mode="AMBIENT" target="alpha" value="0" />' }
    L "      <Image resource=""d${hex}_$res"" />"
    L '    </PartImage>'
  }
}

Slot -left 0 -top 0 -srcExpr '[HOUR_0_23]' -lo 0 -hi 23 -res $primary -ambient $true
Slot -left 1 -top 0 -srcExpr '[MINUTE]' -lo 0 -hi 59 -res $primary -ambient $true
Slot -left 2 -top 0 -srcExpr '[SECOND]' -lo 0 -hi 59 -res $accent -ambient $false
Slot -left 1 -top -1 -srcExpr '[YEAR_S]' -lo 20 -hi 35 -res $accent -ambient $false
Slot -left 2 -top -1 -srcExpr '[MONTH]' -lo 1 -hi 12 -res $accent -ambient $false
Slot -left 2 -top 1 -srcExpr '[DAY]' -lo 1 -hi 31 -res $accent -ambient $false
Slot -left 1 -top 1 -srcExpr '[DAY_OF_WEEK]' -lo 1 -hi 7 -res $accent -ambient $false
Slot -left -1 -top 0 -srcExpr '[BATTERY_PERCENT]' -lo 0 -hi 100 -res $accent -ambient $false
Slot -left -1 -top -1 -srcExpr 'round([HEART_RATE])' -lo 40 -hi 190 -res $accent -ambient $false
Slot -left -1 -top 1 -srcExpr '([STEP_COUNT] % 256)' -lo 0 -hi 255 -res $accent -ambient $false

$hrx = 240 + (-1 - 1) * $numW; $hry = 240 + (-1) * $numVInt - 24
$fb = X '(round([HEART_RATE]) < 40 || round([HEART_RATE]) > 190)'
L "    <PartImage x=""$hrx"" y=""$hry"" width=""$numW"" height=""$numH""><Transform target=""alpha"" value=""$fb ? 255 : 0"" /><Variant mode=""AMBIENT"" target=""alpha"" value=""0"" /><Image resource=""d00_$accent"" /></PartImage>"

L '    <PartImage x="-10" y="-10" width="500" height="500"><Variant mode="AMBIENT" target="alpha" value="0" /><Image resource="vignetting_strong" /></PartImage>'
L '  </Scene>'
L '</WatchFace>'

[System.IO.File]::WriteAllText($OutFile, $sb.ToString(), [System.Text.Encoding]::UTF8)
Write-Output "Written $OutFile theme=$Theme length=$($sb.Length)"

# Unsave-TikTokFavorites.ps1
# Automates unsaving TikTok favorites through the Phone Link mirror window.
#
# HOW TO USE
#   1. In Phone Link, open TikTok -> Profile -> Favorites -> tap the first video
#      so you are in the favorites FEED (one video filling the phone screen).
#   2. Run this script in a PowerShell window:  .\Unsave-TikTokFavorites.ps1
#      (optionally: -Count 270 -AfterClickMs 400 -AfterScrollMs 1800)
#   3. During the countdown, hover the mouse over the GOLD bookmark icon
#      on the right rail. Don't click - just hover.
#   4. Hands off. Each cycle the script scans a vertical strip around your
#      anchor point for the gold bookmark (it moves between two layouts),
#      clicks it, then scrolls to the next video.
#   5. TO STOP: just move the mouse. Any movement > 60 px aborts the loop.
#
# The script never types and never presses Enter. If it can't find a gold
# bookmark 4 videos in a row (comments panel opened, feed ended, app changed)
# it stops on its own.

param(
    [int]$Count         = 500,   # how many videos to unsave
    [int]$AfterClickMs  = 450,   # wait after tapping the bookmark
    [int]$AfterScrollMs = 1800,  # wait for the next video to load
    [int]$StartDelaySec = 6,     # time to position the mouse before start
    [int]$ScanRange     = 60     # +/- pixels scanned vertically for the gold icon
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class MouseNative {
    [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, uint dx, uint dy, int dwData, UIntPtr dwExtraInfo);
    public const uint LEFTDOWN = 0x0002;
    public const uint LEFTUP   = 0x0004;
    public const uint WHEEL    = 0x0800;
}
'@

function Set-Cursor([int]$x, [int]$y) {
    [System.Windows.Forms.Cursor]::Position = New-Object System.Drawing.Point($x, $y)
    Start-Sleep -Milliseconds 60
}

function Click-At([int]$x, [int]$y) {
    Set-Cursor $x $y
    [MouseNative]::mouse_event([MouseNative]::LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 40
    [MouseNative]::mouse_event([MouseNative]::LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
}

function Scroll-OneTick([int]$x, [int]$y) {
    Set-Cursor $x $y
    [MouseNative]::mouse_event([MouseNative]::WHEEL, 0, 0, -120, [UIntPtr]::Zero)
}

# Returns the Y of the gold bookmark near ($x, $yCenter), or $null.
# Scans a 1-px-wide vertical strip and looks for the longest run of "gold" pixels.
function Find-GoldY([int]$x, [int]$yCenter, [int]$range) {
    $h   = 2 * $range + 1
    $bmp = New-Object System.Drawing.Bitmap(1, $h)
    $g   = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($x, $yCenter - $range, 0, 0, (New-Object System.Drawing.Size(1, $h)))
    $g.Dispose()

    $bestStart = -1; $bestLen = 0; $curStart = -1; $curLen = 0
    for ($i = 0; $i -lt $h; $i++) {
        $p = $bmp.GetPixel(0, $i)
        $isGold = ($p.R -gt 190) -and ($p.G -gt 130) -and ($p.B -lt 120)
        if ($isGold) {
            if ($curStart -lt 0) { $curStart = $i }
            $curLen++
            if ($curLen -gt $bestLen) { $bestLen = $curLen; $bestStart = $curStart }
        } else {
            $curStart = -1; $curLen = 0
        }
    }
    $bmp.Dispose()

    if ($bestLen -ge 6) {   # gold icon is ~15-20 px tall in the mirror; 6+ = confident
        return ($yCenter - $range) + $bestStart + [int]($bestLen / 2)
    }
    return $null
}

Write-Host ""
Write-Host "Hover the mouse over the GOLD bookmark icon in the Phone Link mirror..." -ForegroundColor Yellow
for ($t = $StartDelaySec; $t -gt 0; $t--) {
    Write-Host ("  starting in {0}..." -f $t)
    Start-Sleep -Seconds 1
}

$anchor  = [System.Windows.Forms.Cursor]::Position
$anchorX = $anchor.X
$anchorY = $anchor.Y
# scroll over the video area, left of and slightly above the rail
$scrollX = $anchorX - 150
$scrollY = $anchorY - 120

Write-Host ("Anchor captured at {0},{1}. Scanning +/-{2}px for the gold bookmark." -f $anchorX, $anchorY, $ScanRange) -ForegroundColor Cyan
Write-Host "MOVE THE MOUSE AT ANY TIME TO STOP." -ForegroundColor Yellow
Write-Host ""

$done = 0
$skipped = 0
$missStreak = 0
$lastSet = [System.Windows.Forms.Cursor]::Position

for ($i = 1; $i -le $Count; $i++) {

    # user-abort check: did a human move the mouse since we last placed it?
    $now = [System.Windows.Forms.Cursor]::Position
    if ([Math]::Abs($now.X - $lastSet.X) -gt 60 -or [Math]::Abs($now.Y - $lastSet.Y) -gt 60) {
        Write-Host "Mouse moved by user - stopping." -ForegroundColor Red
        break
    }

    $goldY = Find-GoldY $anchorX $anchorY $ScanRange
    if ($null -ne $goldY) {
        Click-At $anchorX $goldY
        $done++
        $missStreak = 0
        Start-Sleep -Milliseconds $AfterClickMs
    } else {
        $skipped++
        $missStreak++
        Write-Host ("[{0}/{1}] no gold bookmark found - skipping this video" -f $i, $Count) -ForegroundColor DarkYellow
        if ($missStreak -ge 4) {
            Write-Host "4 misses in a row - something is off (panel open? feed ended?). Stopping." -ForegroundColor Red
            break
        }
    }

    Scroll-OneTick $scrollX $scrollY
    $lastSet = [System.Windows.Forms.Cursor]::Position
    Start-Sleep -Milliseconds $AfterScrollMs

    if ($goldY) { Write-Host ("[{0}/{1}] unsaved: {2}" -f $i, $Count, $done) }
}

Write-Host ""
Write-Host ("Finished. Unsaved: {0}   Skipped: {1}" -f $done, $skipped) -ForegroundColor Green

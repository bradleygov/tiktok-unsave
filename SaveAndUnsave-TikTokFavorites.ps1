# SaveAndUnsave-TikTokFavorites.ps1
# Downloads each TikTok favorite via the AhaTok floating icon, then unsaves it.
# Runs against the Phone Link mirror window ("Bradley's S26").
#
# PER-VIDEO CYCLE
#   1. Find the GOLD bookmark on the right rail (pixel scan, handles both layouts).
#   2. Tap SHARE (48 px below the bookmark) -> "Send to" sheet slides up.
#   3. Tap COPY LINK -> "Link copied" toast, sheet closes itself.
#   4. Tap the AhaTok floating icon (snapped to either screen edge; its
#      position is auto-detected at startup) -> it grabs the clipboard link
#      and downloads the video in the background.
#   5. Tap the gold bookmark -> video is unsaved (icon turns white).
#   6. Wheel-scroll one tick -> next favorite.
#
# HOW TO USE
#   .\SaveAndUnsave-TikTokFavorites.ps1              # does 20 videos
#   .\SaveAndUnsave-TikTokFavorites.ps1 -Count 50    # change the number here
#
#   Before running: Phone Link mirror at the LEFT edge of the screen (do not
#   move the window), TikTok open in the favorites FEED (Profile -> Favorites
#   -> tap first video), AhaTok floating icon visible on either edge of the
#   phone screen (the script finds it wherever it sits).
#
#   TO STOP: just move the mouse. Any movement > 60 px aborts the loop.
#
# COORDINATES are PHYSICAL screen pixels on a 1920x1080 desktop, mirror window
# docked top-left (phone screen spans x 0..459 physical).
#   Gold bookmark column x=429, standard y~713 (scan +/-80 covers both layouts)
#   Share icon        = gold bookmark y + 63
#   Copy link         = auto-detected each cycle: the share-channel row sits at
#                       y=791 with 6 icon slots (x = 44,118,191,265,338,412);
#                       TikTok reorders the icons, so the script classifies the
#                       blue circles by color (Copy link = flat blue R~55-63,
#                       Facebook = deep blue R~15-20, Email = cyan top) and
#                       taps the right one; falls back to (-CopyLinkX, -CopyLinkY)
#   Share sheet check = (231, 609)  "Send to" header row, white when open
#   AhaTok icon       = auto-detected at startup by scanning the left (x=22)
#                       and right (x=437) edge columns for its pink circle;
#                       -AhaTokX/-AhaTokY are the fallback if the scan misses
#   Scroll point      = (231, 527)

param(
    [int]$Count          = 20,    # how many videos to download + unsave
    [int]$BookmarkX      = 429,   # right-rail column
    [int]$BookmarkY      = 713,   # standard gold bookmark position (anchor)
    [int]$ScanRange      = 80,    # +/- pixels scanned vertically for gold
    [int]$ShareOffsetY   = 63,    # share icon sits this far below the bookmark
    [int]$CopyLinkX      = 338,   # "Copy link" FALLBACK (auto-detected each cycle; TikTok reorders the row)
    [int]$CopyLinkY      = 791,   # share-channel row height
    [int]$SheetCheckX    = 231,   # white pixel here = share sheet is open
    [int]$SheetCheckY    = 609,
    [int]$AhaTokX        = 437,   # AhaTok floating icon FALLBACK (auto-detected at startup)
    [int]$AhaTokY        = 369,
    [int]$ScrollX        = 231,   # wheel point over the video
    [int]$ScrollY        = 527,
    [int]$AfterShareMs   = 1600,  # share sheet slide-up time
    [int]$AfterCopyMs    = 900,   # "Link copied" toast + sheet close
    [int]$AfterAhaTokMs  = 1300,  # AhaTok link pickup
    [int]$AfterUnsaveMs  = 900,   # unsave animation (scrolling too soon gets eaten)
    [int]$AfterScrollMs  = 2000,  # next video load
    [int]$StartDelaySec  = 5
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class MouseNative {
    [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, uint dx, uint dy, int dwData, UIntPtr dwExtraInfo);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    public const uint LEFTDOWN = 0x0002;
    public const uint LEFTUP   = 0x0004;
    public const uint WHEEL    = 0x0800;
}
'@

# work in physical pixels even if Windows display scaling is ever changed
[MouseNative]::SetProcessDPIAware() | Out-Null

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

function Get-PixelAt([int]$x, [int]$y) {
    $bmp = New-Object System.Drawing.Bitmap(1, 1)
    $g   = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($x, $y, 0, 0, (New-Object System.Drawing.Size(1, 1)))
    $g.Dispose()
    $p = $bmp.GetPixel(0, 0)
    $bmp.Dispose()
    return $p
}

# Returns the Y of the gold bookmark near ($x, $yCenter), or $null.
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

    if ($bestLen -ge 6) {
        return ($yCenter - $range) + $bestStart + [int]($bestLen / 2)
    }
    return $null
}

# Finds the AhaTok floating bubble by scanning vertical edge columns for its
# pink circle (pale-pink ring + rose inner circle, white arrow in the middle).
# Returns @{X=..;Y=..} or $null. The bubble snaps to the left or right edge of
# the phone screen, so only those two columns are scanned.
function Find-AhaTok {
    $columns = @(22, 437)   # bubble center when snapped left / right (phone spans x 0..459)
    $yStart  = 80
    $yEnd    = 980
    $h       = $yEnd - $yStart + 1

    foreach ($x in $columns) {
        $bmp = New-Object System.Drawing.Bitmap(1, $h)
        $g   = [System.Drawing.Graphics]::FromImage($bmp)
        $g.CopyFromScreen($x, $yStart, 0, 0, (New-Object System.Drawing.Size(1, $h)))
        $g.Dispose()

        # collect pink pixels: strong red, but NOT the pure-red of a liked heart
        # (heart is ~255,44,85 -> G too low) and not white (G too high)
        $pinks = New-Object System.Collections.Generic.List[int]
        for ($i = 0; $i -lt $h; $i++) {
            $p = $bmp.GetPixel(0, $i)
            if (($p.R -gt 210) -and ($p.G -ge 70) -and ($p.G -le 200) -and ($p.B -ge 80) -and ($p.B -le 215) -and (($p.R - $p.G) -ge 45)) {
                $pinks.Add($i)
            }
        }
        $bmp.Dispose()

        # cluster the pink pixels (gaps <= 8 px bridge the white arrow),
        # keep the densest cluster that is bubble-sized (18-55 px tall)
        $bestCount = 0; $bestMin = 0; $bestMax = 0
        $curMin = -1; $curMax = -1; $curCount = 0
        foreach ($i in $pinks) {
            if ($curMin -lt 0 -or ($i - $curMax) -gt 8) {
                if ($curCount -gt $bestCount -and ($curMax - $curMin) -ge 18 -and ($curMax - $curMin) -le 55) {
                    $bestCount = $curCount; $bestMin = $curMin; $bestMax = $curMax
                }
                $curMin = $i; $curMax = $i; $curCount = 1
            } else {
                $curMax = $i; $curCount++
            }
        }
        if ($curCount -gt $bestCount -and ($curMax - $curMin) -ge 18 -and ($curMax - $curMin) -le 55) {
            $bestCount = $curCount; $bestMin = $curMin; $bestMax = $curMax
        }

        if ($bestCount -ge 12) {
            return @{ X = $x; Y = $yStart + [int](($bestMin + $bestMax) / 2) }
        }
    }
    return $null
}

function Test-SheetOpen {
    $p = Get-PixelAt $SheetCheckX $SheetCheckY
    return ($p.R -gt 235) -and ($p.G -gt 235) -and ($p.B -gt 235)
}

# Finds the "Copy link" icon in the open share sheet. TikTok reorders the
# share-channel row, but the 6 icon slots sit on a fixed grid. Three icons are
# blue circles, told apart by measured body color (live-calibrated 2026-07):
#   Copy link -> flat blue, R ~55-63   (e.g. 57,113,248)
#   Facebook  -> deep blue, R ~15-20   (e.g. 20,119,238)
#   Email     -> cyan-gradient top, G >= 165 (e.g. 31,204,240)
# Four ring points are sampled per slot; white glyph pixels are ignored.
# Returns the slot center X, or $null if nothing matches confidently.
function Find-CopyLinkX([int]$rowY) {
    $slots = @(44, 118, 191, 265, 338, 412)
    $hits = @()
    foreach ($cx in $slots) {
        $samples = @(
            (Get-PixelAt $cx ($rowY - 12)),
            (Get-PixelAt $cx ($rowY + 12)),
            (Get-PixelAt ($cx - 12) $rowY),
            (Get-PixelAt ($cx + 12) $rowY)
        )
        $blues = @($samples | Where-Object { $_.B -gt 150 -and $_.B -gt ($_.R + 30) })
        if ($blues.Count -lt 2) { continue }   # not a blue circle

        $avgR = ($blues | Measure-Object -Property R -Average).Average
        $avgG = ($blues | Measure-Object -Property G -Average).Average

        if ($avgG -ge 165) { continue }        # Email (cyan gradient)
        if ($avgR -lt 40)  { continue }        # Facebook (deep blue)
        $hits += $cx                            # flat blue with R>=40 = Copy link
    }
    if ($hits.Count -eq 1) { return $hits[0] }
    return $null
}

Write-Host ""
Write-Host ("TikTok download + unsave: {0} videos. Starting in {1}s - keep hands off the mouse." -f $Count, $StartDelaySec) -ForegroundColor Yellow
Write-Host "(Change the number with:  .\SaveAndUnsave-TikTokFavorites.ps1 -Count <n>)"
Start-Sleep -Seconds $StartDelaySec

# locate the AhaTok bubble (it snaps to either edge and gets dragged around)
$aha = Find-AhaTok
if ($null -ne $aha) {
    $AhaTokX = $aha.X
    $AhaTokY = $aha.Y
    Write-Host ("AhaTok bubble found at {0},{1}." -f $AhaTokX, $AhaTokY) -ForegroundColor Cyan
} else {
    Write-Host ("AhaTok bubble NOT found by scan - using fallback {0},{1}. If downloads don't start, abort and check the bubble is visible." -f $AhaTokX, $AhaTokY) -ForegroundColor Red
}
Write-Host "MOVE THE MOUSE AT ANY TIME TO STOP." -ForegroundColor Yellow
Write-Host ""

$done = 0
$missStreak = 0
$iter = 0
$maxIter = $Count * 4
Set-Cursor $ScrollX $ScrollY
$lastSet = [System.Windows.Forms.Cursor]::Position

while (($done -lt $Count) -and ($iter -lt $maxIter)) {
    $iter++

    # user-abort check: did a human move the mouse since we last placed it?
    $now = [System.Windows.Forms.Cursor]::Position
    if ([Math]::Abs($now.X - $lastSet.X) -gt 60 -or [Math]::Abs($now.Y - $lastSet.Y) -gt 60) {
        Write-Host "Mouse moved by user - stopping." -ForegroundColor Red
        break
    }

    # park cursor away from the rail, then find this video's gold bookmark
    Set-Cursor $ScrollX $ScrollY
    $goldY = Find-GoldY $BookmarkX $BookmarkY $ScanRange

    if ($null -eq $goldY) {
        $missStreak++
        Write-Host ("no gold bookmark found ({0}/4) - scrolling on" -f $missStreak) -ForegroundColor DarkYellow
        if ($missStreak -ge 4) {
            Write-Host "4 misses in a row - feed ended or a panel is open. Stopping." -ForegroundColor Red
            break
        }
        Scroll-OneTick $ScrollX $ScrollY
        $lastSet = [System.Windows.Forms.Cursor]::Position
        Start-Sleep -Milliseconds $AfterScrollMs
        continue
    }
    $missStreak = 0

    # 1. open the share sheet
    Click-At $BookmarkX ($goldY + $ShareOffsetY)
    Start-Sleep -Milliseconds $AfterShareMs
    if (-not (Test-SheetOpen)) {
        # one retry - the first tap sometimes only wakes the screen
        Click-At $BookmarkX ($goldY + $ShareOffsetY)
        Start-Sleep -Milliseconds $AfterShareMs
    }

    if (-not (Test-SheetOpen)) {
        # no sheet = no download; leave this video SAVED and move on
        Write-Host "share sheet did not open - leaving this video saved, scrolling on" -ForegroundColor DarkYellow
        Scroll-OneTick $ScrollX $ScrollY
        $lastSet = [System.Windows.Forms.Cursor]::Position
        Start-Sleep -Milliseconds $AfterScrollMs
        continue
    }

    # 2. copy link (sheet closes on its own) - find the icon, TikTok reorders the row
    $clX = Find-CopyLinkX $CopyLinkY
    if ($null -eq $clX) {
        Write-Host ("copy-link icon not identified - using fallback x={0}" -f $CopyLinkX) -ForegroundColor DarkYellow
        $clX = $CopyLinkX
    }
    Click-At $clX $CopyLinkY
    Start-Sleep -Milliseconds $AfterCopyMs

    # 3. AhaTok grabs the link and queues the download
    Click-At $AhaTokX $AhaTokY
    Start-Sleep -Milliseconds $AfterAhaTokMs

    # 4. unsave: the gold bookmark position is unchanged by the sheet round-trip
    Click-At $BookmarkX $goldY
    Start-Sleep -Milliseconds $AfterUnsaveMs
    Set-Cursor $ScrollX $ScrollY

    $still = Find-GoldY $BookmarkX $BookmarkY $ScanRange
    if ($null -ne $still) {
        # one retry - the tap can get eaten by the toast animation
        Click-At $BookmarkX $still
        Start-Sleep -Milliseconds $AfterUnsaveMs
        Set-Cursor $ScrollX $ScrollY
        $still = Find-GoldY $BookmarkX $BookmarkY $ScanRange
    }
    if ($null -eq $still) {
        $done++
        Write-Host ("[{0}/{1}] downloaded + unsaved (gold was y={2})" -f $done, $Count, $goldY) -ForegroundColor Green
    } else {
        Write-Host ("bookmark still gold after 2 unsave taps (y={0}) - moving on" -f $still) -ForegroundColor DarkYellow
    }

    # 5. next video
    Scroll-OneTick $ScrollX $ScrollY
    $lastSet = [System.Windows.Forms.Cursor]::Position
    Start-Sleep -Milliseconds $AfterScrollMs
}

Write-Host ""
Write-Host ("Finished. Downloaded + unsaved: {0} of {1} requested." -f $done, $Count) -ForegroundColor Green
Write-Host "Check AhaTok on the phone for the downloaded files."

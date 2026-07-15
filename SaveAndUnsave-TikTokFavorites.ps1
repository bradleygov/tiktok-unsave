# SaveAndUnsave-TikTokFavorites.ps1
# Downloads each TikTok favorite via the AhaTok floating icon, then unsaves it.
# Runs against the Phone Link mirror window ("Bradley's S26").
#
# PER-VIDEO CYCLE
#   1. Find the GOLD bookmark on the right rail (pixel scan, handles both layouts).
#   2. Tap SHARE (48 px below the bookmark) -> "Send to" sheet slides up.
#   3. Tap COPY LINK -> "Link copied" toast, sheet closes itself.
#   4. Tap the AhaTok floating icon (left edge) -> it grabs the clipboard link
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
#   -> tap first video), AhaTok floating icon visible on the left edge.
#
#   TO STOP: just move the mouse. Any movement > 60 px aborts the loop.
#
# COORDINATES are PHYSICAL screen pixels on a 1920x1080 desktop, mirror window
# docked top-left (phone screen spans x 0..459 physical).
#   Gold bookmark column x=429, standard y~713 (scan +/-80 covers both layouts)
#   Share icon        = gold bookmark y + 63
#   Copy link         = found automatically: the row at y=791 is scanned for
#                       the Copy link icon's blue circle (RGB ~57,113,248 -
#                       distinct from Facebook's ~20,119,238 and Email's cyan);
#                       TikTok shuffles the icon left/right between videos.
#                       (-CopyLinkX, -CopyLinkY) is only the fallback.
#   Share sheet check = (231, 609)  "Send to" header row, white when open
#   AhaTok icon       = (22, 634)
#   Scroll point      = (231, 527)

param(
    [int]$Count          = 20,    # how many videos to download + unsave
    [int]$BookmarkX      = 429,   # right-rail column
    [int]$BookmarkY      = 713,   # standard gold bookmark position (anchor)
    [int]$ScanRange      = 80,    # +/- pixels scanned vertically for gold
    [int]$ShareOffsetY   = 63,    # share icon sits this far below the bookmark
    [int]$CopyLinkX      = 121,   # "Copy link" FALLBACK if the icon scan fails
    [int]$CopyLinkY      = 791,   # share-channel row height (icon is scanned along this row)
    [int]$SheetCheckX    = 231,   # white pixel here = share sheet is open
    [int]$SheetCheckY    = 609,
    [int]$AhaTokX        = 22,    # AhaTok floating icon
    [int]$AhaTokY        = 634,
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

function Test-SheetOpen {
    $p = Get-PixelAt $SheetCheckX $SheetCheckY
    return ($p.R -gt 235) -and ($p.G -gt 235) -and ($p.B -gt 235)
}

# Finds the "Copy link" icon anywhere along the share-channel row by looking
# for its blue circle. Measured colors (2026-07): Copy link body = flat blue
# around (57,113,248); Facebook = deep blue ~(20,119,238) (red too low);
# Email = cyan-gradient ~(31,204,240) (green too high). The white chain glyph
# sits mid-circle, so the circle shows as two blue arcs on the scan line -
# a sliding window counts blue columns and picks the densest spot.
# Returns the icon center X, or $null if no confident match.
function Find-CopyLinkX([int]$rowY) {
    $x0 = 20; $x1 = 445
    $w  = $x1 - $x0 + 1
    $rows = @($rowY - 10, $rowY, $rowY + 10)   # three scan lines across the circle

    $bmp = New-Object System.Drawing.Bitmap($w, 1)
    $isBlue = New-Object bool[] $w
    foreach ($ry in $rows) {
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.CopyFromScreen($x0, $ry, 0, 0, (New-Object System.Drawing.Size($w, 1)))
        $g.Dispose()
        for ($i = 0; $i -lt $w; $i++) {
            $p = $bmp.GetPixel($i, 0)
            # Copy-link blue: mid red, mid green, strong blue
            if (($p.R -ge 40) -and ($p.R -le 95) -and ($p.G -ge 90) -and ($p.G -le 145) -and ($p.B -ge 210)) {
                $isBlue[$i] = $true
            }
        }
    }
    $bmp.Dispose()

    # slide a circle-wide window; the icon is ~44 px across
    $win = 44
    $bestX = -1; $bestCount = 0
    $count = 0
    for ($i = 0; $i -lt $w; $i++) {
        if ($isBlue[$i]) { $count++ }
        if ($i -ge $win -and $isBlue[$i - $win]) { $count-- }
        if ($i -ge ($win - 1) -and $count -gt $bestCount) {
            $bestCount = $count
            $bestX = $x0 + $i - [int]($win / 2)
        }
    }

    if ($bestCount -ge 14) { return $bestX }
    return $null
}

Write-Host ""
Write-Host ("TikTok download + unsave: {0} videos. Starting in {1}s - keep hands off the mouse." -f $Count, $StartDelaySec) -ForegroundColor Yellow
Write-Host "(Change the number with:  .\SaveAndUnsave-TikTokFavorites.ps1 -Count <n>)"
Start-Sleep -Seconds $StartDelaySec
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

    # 2. copy link (sheet closes on its own) - scan the row, the icon moves around
    $clX = Find-CopyLinkX $CopyLinkY
    if ($null -eq $clX) {
        Write-Host ("copy-link icon not found on the row - using fallback x={0}" -f $CopyLinkX) -ForegroundColor DarkYellow
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

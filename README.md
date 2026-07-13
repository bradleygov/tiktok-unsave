# TikTok Favorites Bulk-Unsave (via Windows Phone Link)

TikTok has no bulk "remove from favorites" — clearing hundreds of saved videos means tapping the bookmark icon one video at a time. This PowerShell script automates that through the **Phone Link** app on Windows, which mirrors your Android phone's screen.

## How it works

You open your TikTok favorites feed in the Phone Link mirror and hover the mouse over the gold bookmark icon. The script then loops:

1. **Pixel-scan** a thin vertical strip (±60 px) around your anchor point for the gold bookmark icon — TikTok shifts the icon rail up/down depending on the video's layout, so a fixed click point misclicks; scanning for the gold color finds it wherever it is.
2. **Click** the icon (unsave).
3. **Wheel-scroll** one tick to advance to the next favorited video.
4. Repeat.

If no gold icon is found (video already unsaved, popup opened, feed ended) it **skips instead of clicking**, so it never taps comments/share by mistake. Four consecutive misses stop the run.

## Usage

1. Connect your phone in **Phone Link** and open the phone-screen mirror.
2. In TikTok: **Profile → Favorites (bookmark tab) → tap the first video** so you're in the favorites feed.
3. Run (execution policy bypass included):

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\Unsave-TikTokFavorites.ps1 -Count 200
   ```

4. During the 6-second countdown, **hover** (don't click) the mouse over the gold bookmark icon.
5. Hands off — about 2.3 s per video.
6. **To stop: just move the mouse.** Any movement > 60 px aborts instantly.

## Parameters

| Parameter | Default | Meaning |
|---|---|---|
| `-Count` | 270 | How many videos to unsave |
| `-AfterClickMs` | 450 | Delay after tapping the bookmark |
| `-AfterScrollMs` | 1800 | Delay for the next video to load |
| `-StartDelaySec` | 6 | Countdown to position the mouse |
| `-ScanRange` | 60 | Vertical pixels scanned for the gold icon |

## Notes / limitations

- Built for Phone Link's mirror window; works with any screen position since the anchor is wherever you hover.
- The gold detection threshold (`R>190, G>130, B<120`) matches TikTok's filled-bookmark yellow; if TikTok reskins, adjust `Find-GoldY`.
- Unsaved videos remain in the current feed session (TikTok doesn't eject them live), which is what makes the scroll-one-ahead loop stable.
- Use at your own pace — very long runs may hit TikTok rate limiting; the delays above were reliable in practice.

# ASUS Zenbook S16 UM5606WA

Machine-specific supplement to the generic docs in `../`. CPU: AMD Ryzen AI 9 HX 370 (hybrid Zen 5 + Zen 5c). GPU: Radeon 890M. Panel: 3K (2880×1800) OLED. RAM: 32 GB LPDDR5X soldered. Storage: single M.2 2280 slot.

If something in this file contradicts a generic doc, this file wins for this hardware.

---

## Hardware quirks worth knowing before install

- **Only single-sided M.2 SSDs fit** the slot — there are surface-mounted components nearby. Verify before buying a replacement drive.
- **32 GB RAM is the ceiling** (soldered). `.wslconfig` defaults to 16 GB for WSL2 to leave Windows breathing room.
- **Hybrid CPU**: Zen 5 perf cores + Zen 5c efficiency cores. Windows 11 24H2+ schedules across them via Thread Director equivalent. Don't pin processes to specific cores unless you've measured a need.

## BIOS

Support page (use this for BIOS and driver downloads, not the generic ASUS site):
<https://www.asus.com/laptops/for-home/zenbook/asus-zenbook-s-16-um5606/helpdesk_bios?model2Name=UM5606WA>

Use **EZ Flash from a FAT32 USB** to update — more reliable than vendor-app flashing.

In addition to the generic baseline in [`../bios.md`](../bios.md):

| Setting | Value | Reason |
|---|---|---|
| USB Power Delivery in S5 | Off | Negligible battery save unless you actually charge peripherals from the laptop overnight |
| Wake on LID open | Personal preference | Disable if it wakes in your bag |

The ASUS consumer BIOS does NOT expose:

- C-states
- PBO / Precision Boost Overdrive
- Per-core voltage offset
- Memory training overrides

These are all firmware-driven via ASUS Intelligent Performance Technology. There's no way around this without a custom BIOS, which would void warranty and likely break Live Update.

## MyASUS configuration

Install MyASUS from the Microsoft Store, sign in, and run **Live Update** before any other driver work. Then in Device Settings:

| Setting | Value | Reason |
|---|---|---|
| **Battery Health Charging** | Balanced (80%) | Roughly doubles battery lifespan over years. Bump to 100% on travel days. |
| **Fan Mode** | Standard | Whisper for quiet listening, Performance only for compile/encode bursts |
| **AI Noise Cancellation (mic)** | On for calls, **OFF for recording** | Adds latency and colouration in any DAW |
| **Function Key Lock** | F1–F12 default | Toggle with Fn+Esc if you ever need the media keys |
| **Splendid / Display color** | Native or sRGB | "Vivid" oversaturates the already-wide-gamut OLED panel |
| **USB-C charging** | Enabled | Up to 100W via compatible chargers |
| **OLED Care** | Enable Pixel Refresh + Pixel Shift | Per-panel wear protection — run Pixel Refresh manually every couple of months in addition to the auto schedule |
| **Smart Gestures** | **Off** | Same rationale as the disabled taps and 3/4-finger gestures in `resources/registry/tweaks.reg` Precision Touchpad section: touchpad is used like a mouse, no taps so the palm can rest on it absent-mindedly without firing anything, and Fn keys handle volume / brightness already so the gesture-for-media trade isn't worth the false-positive risk. Disable in MyASUS → Device Settings → Input Device (or wherever ASUS surfaces the toggle in your MyASUS build). |

Many of these have no PowerShell API; that's why they live in this doc and not in `bootstrap.ps1`.

## Drivers — install order

(Generic order in [`../drivers.md`](../drivers.md); machine specifics below.)

1. **MyASUS Live Update** — pulls the ASUS-curated driver pack: chipset, audio, fingerprint, FN keys, ASUS System Control Interface. **Do this first.** These are validated against the firmware revision.
2. **AMD chipset driver** direct from amd.com — newer than what ASUS ships, includes scheduler updates for the Zen 5 / Zen 5c hybrid layout. Pre-AMD's update, Windows occasionally schedules CPU-heavy threads onto the c-cores, which costs ~10–15% perf.
3. **AMD Adrenalin (Radeon 890M)** direct from amd.com. Choose **Factory Reset Install** the first time so it doesn't fight whatever leftover Radeon bits MyASUS dropped in.
4. **Don't install standalone Realtek HD Audio from random sites.** The audio stack on this laptop includes ASUS/Dolby tuning that breaks if you swap the underlying driver. MyASUS Live Update is the source of truth.

## OLED

Generic preservation principles in [`../oled.md`](../oled.md). Specific to this panel:

- **Pixel Refresh + Pixel Shift** are MyASUS features, not Windows ones. Enable both (see MyASUS table above).
- The Windows-11 24H2 **content-aware dimming** that gradually reduces brightness for static UI elements is on by default and works well here. Don't disable it.
- Brightness sweet spot for this panel: **50–70%** for typical indoor use. 100% sustained for hours is the real burn-in risk; brightness changes alone are not.
- Disable HDR for SDR content. HDR-on-SDR makes static UI elements drive the panel harder than they need to.

## Audio — Audient EVO 4 specifics

Generic setup in [`../audio.md`](../audio.md). Machine-specific notes:

- **Plug the EVO 4 directly into a laptop USB-A or USB-C port** — never through the HP G4 dock. Docks add a USB hub that introduces jitter and DPC spikes; LatencyMon will surface this immediately.
- **Disable internal Realtek speaker output in Device Manager** when permanently at the desk (right-click → Disable device). Re-enable when traveling. Same for the HDMI audio outs. Single audio path means buffer/sample rate stay predictable.
- **Disable WiFi power saving** during recording (Device Manager → wireless adapter → Power Management). Common DPC offender on this Realtek/MediaTek chipset.
- The AMD chipset's USB controller is fine for audio; latency stays under 5 ms ASIO buffer at 256 samples / 48 kHz in REAPER with no Defender real-time scans on the project dir (handled by the `post-install/Cockos.REAPER.ps1` hook, which excludes `~/Documents/Reaper Media` from real-time scans).

## Things this machine doesn't do well

- **Sustained 100% CPU on Whisper fan mode** — thermal-throttles within 90 seconds. Bump to Standard or Performance for long compiles. Standard is fine for typical dev work.
- **Charging via cheap USB-C bricks** — needs a PD 3.0 charger that can actually deliver 65W+. The bundled charger is fine; some third-party bricks negotiate at 45W and the battery slowly drains under heavy load.
- **External 4K @ 60Hz over USB-C alt-mode** with the laptop on battery — power negotiation gets confused and DisplayPort can drop. Plug power first, then video.

## Audient EVO driver

Not winget-installable. Manual download from <https://audient.com/products/audio-interfaces/evo-4/downloads/>. Ships ASIO + the EVO standalone mixer.

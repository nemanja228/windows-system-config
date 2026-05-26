# Audio — low latency on Windows

How to get Windows 11 audio low-latency and predictable for music production. The setup is **interface-driven**, not laptop-driven — the choice of audio interface and how it connects matter more than the host machine. Machine-specific quirks (which USB port to prefer, dock issues, etc.) live in [`machines/`](machines/).

Reference interface throughout: **Audient EVO 4**. Most of the principles transfer to any class-compliant USB audio interface with an ASIO driver.

---

## Principle: one audio path

When the interface is connected, **route everything through it**. Don't mix internal speakers + external interface depending on app:

- Single path = predictable behaviour. Buffer, sample rate, ASIO routing stay the same whether producing or just listening.
- Lower DPC latency overall — class-compliant USB audio bypasses much of the Realtek/Dolby/vendor post-processing stack.
- The interface's converters and headphone amp are dramatically better than the internal Realtek on any laptop.
- Interfaces have loopback for streaming/recording system audio — internal audio doesn't.

When the interface is disconnected (traveling), Windows falls back to internal automatically. Re-plug and it's the default again — no manual switching.

---

## Connection

**Plug the interface directly into the host machine's USB-A or USB-C port — never through a dock.**

Docks introduce a USB hub which adds jitter and DPC spikes. LatencyMon will show this within minutes of monitoring. Single class-compliant USB hop is what the interface driver expects.

If your machine has a Thunderbolt port and an internal hub of its own, the USB-C port on the Thunderbolt controller is fine. Standalone USB-A ports off the chipset are also fine. The thing to avoid is a downstream hub between the interface and the controller.

---

## Setup steps

1. **Install the interface's driver** — for the EVO 4 that's <https://audient.com/products/audio-interfaces/evo-4/downloads/>. Ships ASIO + the EVO standalone mixer. Not winget-installable.
2. **Set the interface as default audio device** — Settings → System → Sound → Output, pick the interface for both Playback and Recording.
3. **Disable Communications ducking** — Sound Settings → More sound settings → Communications tab → **Do nothing**. Stops Windows from cutting your music when an app thinks a call is happening.
4. **Set the interface format** — `mmsys.cpl` → interface → Properties → Advanced → **24-bit, 48000 Hz** for general use. Match DAW project rate when working. **Disable both** "exclusive control" checkboxes (`Allow applications to take exclusive control of this device` + `Give exclusive mode applications priority`). Exclusive mode is fine for some workflows but conflicts with the loopback feature on interfaces like the EVO.
5. **Disable internal audio outputs** when permanently at the desk — Device Manager → Sound → right-click internal Realtek → Disable device. Same for HDMI audio outputs. Re-enable when traveling.
6. **DAW**: pick the interface's ASIO driver (e.g. **Audient EVO ASIO**), NOT ASIO4ALL and NOT WASAPI. Start at **256-sample buffer**, drop to 128 once LatencyMon confirms headroom.

---

## Verifying with LatencyMon

[Resplendence LatencyMon](https://www.resplendence.com/latencymon) is in `apps.personal.json` and is the canonical tool for catching DPC-latency outliers. Watch for:

- **High ISR / DPC times** in the per-driver table — `wifi.sys`, `bthusb.sys`, ACPI drivers, GPU drivers are common offenders.
- **Hard pagefaults** — usually background indexing or AV scanning. The per-app Defender exclusions in `post-install/Cockos.REAPER.ps1` cover the REAPER project paths (`~/Documents/Reaper Media`); the Audient driver dir is excluded manually per `docs/install-checklist.md` § 15.
- **Maximum reported interrupt-to-process latency** above ~1 ms — fine for most desktop work, problematic for live monitoring at low ASIO buffers.

If you see WiFi or Bluetooth driving spikes, **disable WiFi power saving** during recording (Device Manager → wireless adapter → Power Management → uncheck "Allow the computer to turn off this device") and/or disable Bluetooth when not needed.

Run idle for 15–20 minutes with the DAW open. Don't just check the first 60 seconds — drift takes a few minutes to surface.

---

## Mic noise cancellation

Vendor apps (MyASUS AI Noise Cancellation, Razer THX Spatial Audio, Steel Series Sonar) all offer "AI noise cancellation" that's great for calls and terrible for recording. Toggle off during DAW sessions, on for Zoom/Teams. Often a single toggle in the vendor app, not a Windows setting — see machine doc.

---

## Sample-rate quirks

If you switch project rates a lot:

- Set the Windows default rate in `mmsys.cpl` to the rate you use most often. Apps that don't open in ASIO mode will resample to this rate, with audible quality loss if it doesn't match the project.
- The interface's mixer app usually shows the current hardware rate independent of Windows — verify there if your DAW says one thing and Windows says another.
- 96 kHz uses ~2× the buffer time of 48 kHz at the same buffer-sample count. Drop the buffer if monitoring latency suddenly feels worse after a rate change.

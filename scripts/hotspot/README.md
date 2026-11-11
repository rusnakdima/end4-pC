# Hotspot (Wi-Fi AP) — system setup guide

The end4-pC theme ships a **Hotspot / access-point** feature (bar toggle +
`sidebarRight → Hotspot` dialog). This directory contains everything needed to
make that feature work on a machine — the helper, an idempotent installer, a
dongle-stack verifier, and this guide.

```
scripts/hotspot/
├── README.md           ← this guide
├── aic-hotspot         ← the root helper the theme calls (reference copy, byte-exact)
├── setup-hotspot.sh    ← install / --check / --uninstall (idempotent)
└── aic8800-check.sh    ← verify the AIC8800D80 USB dongle stack (read-only)
```

---

## 1. The contract (what the theme expects)

`services/Hotspot.qml` does **nothing** except shell out to a root helper and
parse one JSON line:

```bash
sudo -n /usr/local/bin/aic-hotspot status                 # read state (every 4 s while active)
sudo -n /usr/local/bin/aic-hotspot start <ssid> <pass> <channel>   # channel 0 = follow STA
sudo -n /usr/local/bin/aic-hotspot stop
```

* Runs as the **theme user** with **NOPASSWD** sudo for exactly this one binary.
* Output: one JSON line —
  `{"active":bool,"ssid":str,"channel":int,"freq":int,"ip":str,"uplink":str,"clients":[{ip,mac,host}],"error":str}`
* Special error `driver refused second interface` ⇒ the theme shows the feature
  as *unsupported* (handled gracefully — no crash).
* Theme defaults (`Config.options.hotspot`, persisted per-user in
  `~/.config/illogical-impulse/config.json`): `ssid`, `passphrase` (8–63 chars),
  `channel` (0 = follow the STA channel, fallback 6).

The dialog refreshes when opened; the 4 s poll only runs while the AP is active.

---

## 2. Quick install (future machine / reinstall)

```bash
cd end4-pC/scripts/hotspot
sudo ./setup-hotspot.sh                 # defaults: regdom KZ, user = whoever ran sudo
sudo ./setup-hotspot.sh --regdom US     # other jurisdiction
./setup-hotspot.sh --check              # verify (unprivileged, read-only)
sudo ./setup-hotspot.sh --uninstall     # full rollback of what this script installs
```

What it installs (all idempotent, never restarts NetworkManager, never touches
a running AP):

| Piece | Path | Why |
|---|---|---|
| helper | `/usr/local/bin/aic-hotspot` (755 root) | the only binary the theme runs |
| sudoers | `/etc/sudoers.d/zz-aic-hotspot` (440) | `user NOPASSWD: /usr/local/bin/aic-hotspot` — `zz-` sorts **last** so no earlier `ALL` rule overrides it |
| NM conf | `/etc/NetworkManager/conf.d/20-unmanaged-aic-ap.conf` | `ap0` must never be claimed by NetworkManager |
| sysctl | `/etc/sysctl.d/99-hotspot-forward.conf` | `net.ipv4.ip_forward=1` for MASQUERADE |
| regdom | `/etc/systemd/system/regdom.service` (enabled) | `iw reg set <CC>` **before NetworkManager** at every boot — without this the AP cannot beacon on 5 GHz (see §6) |
| packages | `hostapd dnsmasq iw python iptables networkmanager wireless-regdb` | daemons + tooling the helper needs |
| unit hygiene | `hostapd.service` / `dnsmasq.service` disabled | the helper runs **private instances** from `/run/aic-hotspot/` — system units must stay off |

After install, verify the exact theme path works:

```bash
sudo -n /usr/local/bin/aic-hotspot status     # as the theme user → JSON, no password prompt
sudo -n /usr/local/bin/aic-hotspot start Laptop <8+ char pass> 0
# … then Stop from the theme's Hotspot dialog.
```

---

## 3. How the AP works at runtime

```
wlan0 (STA, NetworkManager)  ← uplink, e.g. Home WiFi-5G @5180
   │   (same radio, same channel — driver constraint)
ap0  (type __ap, 192.168.150.1/24, unmanaged by NM)
   ├── hostapd   → WPA2-PSK, conf generated in /run/aic-hotspot/ (ht/vht per band)
   ├── dnsmasq   → DHCP 192.168.150.50-250 (12 h), DNS → 1.1.1.1/8.8.8.8
   ├── iptables  → chains AIC_AP_FWD (FORWARD) + AIC_AP_NAT (MASQUERADE)
   └── ufw rules → 67/udp + 53/tcp,udp *on ap0* (only matters if ufw is active)
```

* `ap0` is created with `iw dev wlan0 interface add ap0 type __ap` — wlan0's own
  mode is never changed.
* **Channel logic:** requested channel `0` ⇒ follow the STA's current channel
  (fallback 6). ≤14 ⇒ 2.4 GHz `hw_mode=g`, else `hw_mode=a` + HT40/VHT80 with
  the correct center frequency (e.g. ch36 ⇒ HT40+, VHT80 center 42).
* **Health checks** (4 s): hostapd still alive, no firmware crash / USB
  disconnect in dmesg, STA link survived. Pure hostapd failure in auto-channel
  mode retries once on ch6; firmware failures never retry. Everything is torn
  down (`iw dev ap0 del`, chains flushed, `/run/aic-hotspot` removed) on stop
  or on any start failure.
* **Clients** = `iw station dump` ∩ dnsmasq leases (leases alone are ghosts —
  they persist 12 h after a phone disconnects).

---

## 4. Hardware path A — onboard MT7922 (the laptop in this repo)

No dongle needed. `wlan0` = MT7922 (mt76 driver), AP rides the **same radio**:

* Phy supports it: `#{managed}≤2, #{AP}≤1, total≤3, **#channels ≤ 1**`
  ⇒ the AP **must** share the STA's channel — exactly what the helper's
  follow-STA logic does. Co-channel STA+AP confirmed working (ch36, 80 MHz,
  center1 5210).
* The helper's `aic8800_fdrv` sanity check passes because
  `/etc/modules-load.d/aic8800.conf` keeps the (dongle-less) modules loaded.
* Caveats of a shared radio: the AP shares airtime/channel with the laptop's own
  wifi; toggling laptop wifi off affects the AP.

**MT7921e/MT7922 wedge recovery** (seen after a live module reload):

```
dmesg: mt7921e ... "Failed to get patch semaphore" / "driver own failed"
       / "MCU is not ready for firmware download"  (repeating)
wlan0 disappears or stays `unavailable`
```

Fix, in order:
1. `sudo ./setup-hotspot.sh --check`-style triage: `ip link set wlan0 up`, wait,
   re-read `dmesg`.
2. PCI-level reset (device re-probes, fresh firmware load):
   ```bash
   echo 1 > /sys/bus/pci/devices/0000:04:00.0/remove   # adjust BDF: lspci -nn | grep 14c3:7922
   echo 1 > /sys/bus/pci/rescan
   ```
3. Full wifi-stack reload (unload mt7921e→mt76*→mac80211→cfg80211 iteratively,
   `modprobe aic_load_fw; modprobe mt7921e; …`, then `iw reg set KZ` again —
   a cfg80211 reload loses the in-memory regdomain).
4. **Reboot** — always works, and `regdom.service` restores KZ automatically.

---

## 5. Hardware path B — AIC8800D80 USB dongle (the `archpc` reference)

Dedicated radio: dongle does **STA + AP in parallel** (wlan0 + ap0 vif), laptop
wifi untouched. Reference machine: `archpc` (CachyOS, kernel 7.3.0).

* **USB IDs:** `368b:8d81` = *AICSemi AIC 8800D80* (operational, works
  out-of-the-box). `a69c:5721` = mass-storage boot mode → needs usb_modeswitch:
  ```
  /etc/usb_modeswitch.d/a69c:5721
  /etc/udev/rules.d/40-aic8800-modeswitch.rules:
    ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="a69c", ATTR{idProduct}=="5721", \
      RUN+="/usr/bin/usb_modeswitch -v a69c -p 5721 --std-eject"
  ```
* **Driver stack:** dkms `aic8800d80` (source: dots-hyprland repo,
  `dots-extra/aic8800-usb-*/`, see its INSTALL.md) + firmware
  `/lib/firmware/aic8800D80`, `/lib/firmware/aic8800_fw`.
* **Boot load order** (`/etc/modules-load.d/aic8800.conf`) — order matters:
  `aic_load_fw` → `aic8800_fdrv` → `btusb` → `aic_zlp_quirk`.
* **Self-managed regulatory:** the dongle's phy carries its own embedded
  regdomain (5140–5980, no NO-IR) — it can beacon on 5 GHz regardless of the
  global `country 00` trap that path A falls into (§6). `wlan0` (STA) and `ap0`
  both live on this phy; uplink may be ethernet (`uplink` field then shows e.g.
  `enp2s0`).
* **udev binding:** archpc keeps a set of `/etc/udev/rules.d/*aic*` rules that
  push operational PIDs into `aic8800_fdrv` / `aic_btusb` via `new_id` (their
  static aliases were class-mismatched). Current dkms builds ship complete
  aliases (`modinfo -F alias aic8800_fdrv | grep 368b:8d81`), so on a fresh
  machine these are usually unnecessary — run `./aic8800-check.sh` after
  plug-in and only copy rules from archpc if no wlan interface appears.
* **Helper caveat:** the helper hardcodes `wlan0` (both for the vif and the STA
  channel). That matches archpc where the dongle *is* wlan0. If a machine has
  another card owning wlan0 (e.g. the laptop with the dongle plugged in →
  dongle becomes `wlan1`), adapt `AP_IFACE`/`sta_freq()` in
  `/usr/local/bin/aic-hotspot` first — `./aic8800-check.sh` flags this case.
* **Never reload aic modules while the device is in use** — on this hardware a
  module reload can brick the dongle until a full power cycle. The helper never
  touches modules for that reason.

Check a plugged dongle at any time:

```bash
./aic8800-check.sh     # read-only; PASS/FAIL per layer + hints; exits 0 if no dongle present
```

---

## 6. Troubleshooting (real errors, real fixes)

| Symptom | Cause | Fix |
|---|---|---|
| `{"error":"hostapd failed to start"}` and dmesg says `Frequency 5180 (primary) not allowed for AP mode, NO-IR` | no regulatory db → global `country 00` → all 5 GHz AP channels NO-IR (STA may still connect — that's why wifi looks fine) | `pacman -S wireless-regdb` + `sudo ./setup-hotspot.sh` (installs `regdom.service`). **If `iw reg set` still shows `country 00`, cfg80211 cached the failed db load → reboot once.** |
| `iw reg set XX` returns 0 but `iw reg get` stays `00` | same as above — cfg80211 only loads `regulatory.db` once per boot; a failed load is cached | reboot (or iteratively unload the whole mt76/mac80211/cfg80211 stack and reload) |
| `{"error":"wlan0/driver not loaded"}` | helper's guards: wlan0 missing, or `aic8800_fdrv` not in `/proc/modules` | path A: check mt7921e/wlan0 (§4). path B: dongle not bound (§5, `./aic8800-check.sh`) |
| `{"error":"driver refused second interface"}` | driver rejects the `ap0` vif — theme then shows *unsupported* | phy doesn't allow AP+STA (check `iw phy phy0 info` → "valid interface combinations"), or radio in a bad state → §4 recovery |
| Theme dialog shows an error like `already active` | you started the AP outside the theme (or double-toggled) — harmless; the status poll keeps state correct | wait for the next 4 s poll, or Stop→Start from the dialog |
| `wlan0` gone / `MCU is not ready for firmware download` loop | MT7921e wedged after module reload | §4 recovery (PCI remove/rescan → reload → reboot) |
| Phone gets no IP ("IP configuration failure") | ufw **active** with default deny-in and ap0 rules missing | the helper adds `67/udp`+`53` rules on ap0 at start; check `ufw status \| grep ap0`. (On machines where ufw is inactive — e.g. the laptop — there is nothing to block; AP works as-is.) |
| Helper JSON works as root but not from the theme | sudoers missing/wrong, or an earlier `ALL` rule sorts after ours | `visudo -cf /etc/sudoers.d/zz-aic-hotspot`; the file **must** sort last in `/etc/sudoers.d` |
| AP starts but clients get no internet | forwarding/NAT | `sysctl net.ipv4.ip_forward` must be 1; `iptables -S FORWARD \| grep AIC_AP_FWD`, `iptables -t nat -S POSTROUTING \| grep AIC_AP_NAT` |

Useful probes:

```bash
sudo -n /usr/local/bin/aic-hotspot status        # what the theme sees
iw dev                                            # ap0 present? type AP? channel?
journalctl -t aic-hotspot -n 20                   # helper's own log
ls /run/aic-hotspot/                              # hostapd.conf, pids, .err/.out logs
pgrep -a hostapd; pgrep -af 'dnsmasq.*ap0'
```

---

## 7. Reference — known-good state of the two machines

| | laptop (this repo) | archpc (reference) |
|---|---|---|
| radio | MT7922 onboard, wlan0 = STA+AP same channel | AIC8800D80 dongle, wlan0 STA + ap0 vif |
| driver | mt7921e (mt76) | aic8800_fdrv (dkms), phy **self-managed** reg |
| regdomain | `country KZ` via `regdom.service` (global) | global `US` + self-managed phy rules |
| kernel | Arch `linux` 7.2.14 | CachyOS `7.3.0-4-cachyos` |
| ufw | **inactive** (helper's ufw calls are no-ops) | active, ap0 DHCP/DNS rules present |
| FORWARD policy | ACCEPT | DROP (docker) — chains inserted at position 1 either way |
| system hostapd/dnsmasq units | disabled (helper runs private instances) | disabled |
| AP test (2026-11-11) | `{"active":true,"ssid":"Laptop","channel":36,"freq":5180,"uplink":"wlan0"}` | `{"active":true,"ssid":"archpc-ap","channel":48,"freq":5240,"uplink":"enp2s0"}` |

---

## 8. Uninstall / rollback

```bash
sudo ./setup-hotspot.sh --uninstall
```

Removes helper + sudoers + NM conf + regdom.service (stops a running AP first),
reloads NM. Kept (harmless): `wireless-regdb`, the ip_forward sysctl, any ufw
rules. The theme then simply reports the helper as missing (feature inert).

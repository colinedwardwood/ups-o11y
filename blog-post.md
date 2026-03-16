# UPS monitoring with NUT and Grafana Cloud

I have two Eaton 5SC 1500s in my IT closet protecting a Pi cluster, NAS, and a couple of switches. For a while my monitoring was basically "the LED is green, therefore fine." That worked until I noticed the runtime had quietly dropped from around 18 minutes to under 4. The battery had been degrading for months and I had no idea.

This is how I fixed that.

## The stack

```
Eaton UPS A (USB)  ──┐
                      ├── NUT (upsd + upsmon)     port 3493, localhost only
Eaton UPS B (USB)  ──┘     └── nut_exporter       :9199, Prometheus metrics
                                   └── Grafana Alloy  remote_write → Grafana Cloud
```

[Network UPS Tools](https://networkupstools.org/) is the standard for this. It supports 1,300+ UPS models and the `usbhid-ups` driver handles most modern USB devices. When you plug two identical UPS units into the same host you need to tell NUT which is which — the `serial` field in `ups.conf` handles that, since USB enumeration order isn't stable across reboots.

[nut_exporter](https://github.com/DRuggeri/nut_exporter) is a Go binary that reads NUT variables and exposes them as Prometheus metrics. I was already running Grafana Alloy for node and SNMP metrics, so adding NUT was another scrape target — one per UPS device, since the exporter requires a `?ups=` query parameter when you have multiple.

## What I was missing

The default `--nut.vars_enable` list doesn't include `battery.runtime` or `ups.realpower`. Runtime is the critical one — it's calculated by the UPS firmware and trends down as the battery ages. That's the metric that would've caught my degraded battery months earlier.

I extended it to:

```
battery.charge,battery.charge.low,battery.runtime,battery.voltage,
battery.voltage.nominal,input.voltage,input.voltage.nominal,
output.voltage,ups.load,ups.realpower,ups.status
```

I also found a few things in my original setup worth fixing:
- `upsd.conf` was listening on `0.0.0.0` — no reason for that since the exporter is local
- The nut_exporter binary was v3.1.1, running out of my home directory as my own user with `Restart=on-abort`
- My Alloy scrape used `job_name = "nut-exporter"` but the dashboard queries expected `custom/nut_exporter`, so some panels were silently returning nothing on fresh deploys
- Credentials were hardcoded in the install script

None of these were causing active problems but they're the kind of thing that bites you later.

## Deploying it

Everything is in [github.com/colinedwardwood/ups-o11y](https://github.com/colinedwardwood/ups-o11y).

I used the Ansible role to apply it all in one shot:

```bash
cp ansible/inventory.example.ini ansible/inventory.ini
# edit inventory.ini — set host, SSH key, and device serials in host_vars/
ansible-playbook -i ansible/inventory.ini ansible/playbook.yml \
  --extra-vars "nut_password=YourPassword"
```

The playbook handles NUT config, nut_exporter install (with checksum verification), and drops the Alloy scrape fragment into `/etc/alloy/`. If you're not using Ansible there's also a bash path:

```bash
# NUT — generates a random password if you don't provide one
NUT_PASSWORD="$(openssl rand -base64 24)" sudo -E bash nut/install-nut.sh

# Verify it can see both UPSes
upsc eaton-a@localhost && upsc eaton-b@localhost

# Exporter — downloads v3.2.5, verifies checksum, installs to /opt/nut-exporter/
sudo bash nut-exporter/install-nut-exporter.sh

# Alloy — one fragment per UPS device (see alloy/nut.alloy for the two-UPS pattern)
sudo cp alloy/nut.alloy /etc/alloy/nut.alloy
sudo systemctl reload alloy

# Push dashboard + alerts to Grafana Cloud
GRAFANA_TOKEN=<token> GRAFANA_URL=https://yourinstance.grafana.net bash grafana/deploy.sh
```

The multi-UPS `ups.conf` uses `serial` to pin each device:

```
[eaton-a]
  driver = usbhid-ups
  port   = auto
  serial = P138M45E67

[eaton-b]
  driver = usbhid-ups
  port   = auto
  serial = P138M45E49
```

Without serial disambiguation, the kernel assigns USB devices in whatever order it feels like on each boot. You end up with random label-to-device assignment, which makes per-UPS metrics unreliable.

## The alerts that actually matter

I set up 8 alert rules. Most are defensive. Three are the ones I care about:

**UPS On Battery** — `ups_status{flag="OB"} == 1` for 1 minute. The UPS lost mains. One minute delay cuts noise from brief glitches the UPS handles without me needing to know.

**Battery Runtime Low** — `battery_runtime < 300` for 2 minutes. Less than 5 minutes of runtime. If this fires while you're on battery you have maybe 3 minutes to decide what to do.

**NUT Exporter Down** — `up{job="custom/nut_exporter"} == 0` for 3 minutes. The monitoring is blind. I've had this fire once after a crash and it's genuinely useful to know.

The rest — battery charge critical, replace battery flag, overloaded, voltage anomaly — are warnings that route to a lower-priority Discord channel. They need attention but not at 2am.

## Should you fork nut_exporter?

I looked at it. The exporter itself is solid — v3.2.5 shipped March 2026, it's actively maintained, and the Go code is clean. The gaps I hit were entirely configuration, not missing code. `--nut.vars_enable` already exposes everything you need; the default list is just conservative. A PR to update the defaults would be more useful than a fork.

## What it looks like now

The dashboard has a battery health row showing charge %, estimated runtime, load %, battery voltage, and output voltage — one panel set per UPS. The runtime panel alone would've saved me months of uncertainty about that battery. I have Grafana alerting via Discord, and the whole thing deploys in one playbook run to a fresh Ubuntu 24.04 host.

Total Grafana Cloud cost for this: $0 (well within the free tier metrics quota). The Pi was already there.

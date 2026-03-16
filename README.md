# ups-o11y

UPS monitoring stack using [NUT](https://networkupstools.org/), [nut_exporter](https://github.com/DRuggeri/nut_exporter), [Grafana Alloy](https://grafana.com/docs/alloy/), and Grafana Cloud. Produces Prometheus metrics, a dashboard, and alert rules for any USB UPS that NUT supports (which is most of them).

Written for an Eaton 5SC 1500 on a Raspberry Pi but the only things you'd need to change for a different UPS are `nut_ups_name` and `nut_ups_driver` in `nut/ups.conf`.

## What's here

```
nut/                    NUT server install script + config files
nut-exporter/           nut_exporter v3.2.5 install script + systemd unit
alloy/nut.alloy         Alloy scrape fragment (drop into /etc/alloy/)
grafana/dashboard.json  Grafana dashboard (export + battery health panels added)
grafana/alerts.yaml     8 alert rules
grafana/deploy.sh       Push dashboard + alerts to Grafana Cloud via API
ansible/                Full Ansible role targeting Ubuntu 24.04
blog-post.md            Write-up explaining the whole thing
```

## Prerequisites

- Ubuntu 24.04 or Raspberry Pi OS Bookworm
- UPS connected via USB
- Grafana Alloy running with a `prometheus.remote_write "metrics_service"` component
- Grafana Cloud account (free tier is fine)

## Quickstart

**Bash:**

```bash
git clone https://github.com/colinwoodruff/ups-o11y.git && cd ups-o11y

# NUT — will generate a password if you don't set one
NUT_PASSWORD="$(openssl rand -base64 24)" sudo -E bash nut/install-nut.sh
upsc eaton@localhost   # verify

# nut_exporter — auto-detects amd64/arm64/arm
sudo bash nut-exporter/install-nut-exporter.sh
curl -s http://localhost:9199/ups_metrics | grep battery_charge

# Alloy scrape config — edit room label and ups name to match
sudo cp alloy/nut.alloy /etc/alloy/nut.alloy
sudo systemctl reload alloy

# Grafana dashboard + alerts
GRAFANA_TOKEN=<your-api-key> GRAFANA_URL=https://yourinstance.grafana.net bash grafana/deploy.sh
```

**Ansible:**

```bash
cp ansible/inventory.example.ini ansible/inventory.ini
# edit inventory.ini with your host
ansible-playbook -i ansible/inventory.ini ansible/playbook.yml \
  --extra-vars "nut_password=$(openssl rand -base64 24)"
```

See [ansible/README.md](ansible/README.md) for vault usage and variable reference.

## Security

- `upsd` listens on `127.0.0.1` only — port 3493 isn't exposed on the network
- `NUT_PASSWORD` is never hardcoded — the install script reads it from env and generates one if missing
- nut_exporter runs as a dynamically-allocated unprivileged user (`DynamicUser=yes`) with a restricted systemd sandbox
- Alloy credentials use `sys.env()` — not plaintext in config files

## Alerts

| Alert | When | Severity |
|---|---|---|
| UPS On Battery | `flag="OB"` for 1 min | critical |
| UPS Low Battery | `flag="LB"` | critical |
| NUT Exporter Down | `up == 0` for 3 min | critical |
| Battery Charge Critical | `< 25%` for 5 min | warning |
| Battery Runtime Low | `< 5 min` for 2 min | warning |
| Battery Needs Replacement | `flag="RB"` for 10 min | warning |
| UPS Overloaded | `flag="OVER"` for 2 min | warning |
| Input Voltage Anomaly | outside 108–132 V for 5 min | warning |

## Dashboard

Built on top of the existing UPS Monitoring dashboard. Added a Battery Health row: charge gauge, load gauge, runtime stat, real power stat, battery voltage and output voltage time series. Default time range widened to 24h.

## Tested with

- Eaton 5SC 1500 (`usbhid-ups` driver)
- Raspberry Pi 5, Ubuntu 24.04 arm64
- nut_exporter v3.2.5 / Grafana Alloy v1.x

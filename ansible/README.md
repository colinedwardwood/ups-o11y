# Ansible role: ups_monitoring

Deploys the full UPS monitoring stack on Ubuntu 24.04 (or Pi OS Bookworm). Idempotent, `ansible.builtin` only.

Installs: NUT server + drivers, nut_exporter, and a Grafana Alloy scrape fragment.

## Requirements

- Ansible ≥ 2.14
- Target: Ubuntu 24.04 (systemd)
- Grafana Alloy already installed on the target (the alloy task skips gracefully if `/etc/alloy` doesn't exist)

## Usage

```bash
cp inventory.example.ini inventory.ini
# edit inventory.ini

ansible-playbook -i inventory.ini playbook.yml \
  --extra-vars "nut_password=$(openssl rand -base64 24)"
```

With vault (recommended):

```bash
ansible-vault encrypt_string 'yourpassword' --name nut_password
# paste output into group_vars/ups_monitors.yml
ansible-playbook -i inventory.ini playbook.yml --ask-vault-pass
```

## Key variables

All defaults are in `roles/ups_monitoring/defaults/main.yml`. The ones you'll actually want to set:

| Variable | Default | Notes |
|---|---|---|
| `nut_ups_name` | `eaton` | UPS name in NUT config |
| `nut_ups_driver` | `usbhid-ups` | Run `nut-scanner` on the target to confirm |
| `nut_password` | `""` | **Required** — set via vault |
| `nut_room_label` | `IT-Closet` | Grafana `room` label |
| `nut_exporter_version` | `3.2.5` | |
| `nut_exporter_arch` | auto | `linux-amd64`, `linux-arm64`, `linux-arm` |
| `alloy_config_dir` | `/etc/alloy` | Where to drop `nut.alloy` |

## Tags

```bash
ansible-playbook -i inventory.ini playbook.yml --tags nut          # NUT only
ansible-playbook -i inventory.ini playbook.yml --tags nut_exporter # exporter only
ansible-playbook -i inventory.ini playbook.yml --tags alloy        # Alloy fragment only
```

## Testing

```bash
pip install molecule molecule-plugins[docker] ansible-lint
cd roles/ups_monitoring
molecule test
```

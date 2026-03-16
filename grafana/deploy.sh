#!/usr/bin/env bash
# Push the dashboard and alert rules to Grafana Cloud.
# Usage: GRAFANA_TOKEN=<api-key> GRAFANA_URL=https://yourinstance.grafana.net bash deploy.sh
#
# Optional: FOLDER_UID (default: 64F1iLT4z = HomeLab), DRY_RUN=true

set -euo pipefail

GRAFANA_URL="${GRAFANA_URL:?set GRAFANA_URL}"
GRAFANA_TOKEN="${GRAFANA_TOKEN:?set GRAFANA_TOKEN}"
FOLDER_UID="${FOLDER_UID:-64F1iLT4z}"
DRY_RUN="${DRY_RUN:-false}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

api() {
  local method="$1" path="$2"; shift 2
  curl -fsSL -H "Authorization: Bearer ${GRAFANA_TOKEN}" -H "Content-Type: application/json" \
    -X "$method" "${GRAFANA_URL}${path}" "$@"
}

# Preflight
api GET "/api/dashboards/home" > /dev/null
echo "Connected: ${GRAFANA_URL}"
[[ "$DRY_RUN" == "true" ]] && echo "(dry run)"

# Dashboard
echo "Deploying dashboard..."
PAYLOAD=$(python3 - <<PYEOF
import json
with open('${SCRIPT_DIR}/dashboard.json') as f:
    d = json.load(f)
d.pop('id', None)
d.pop('version', None)
print(json.dumps({'dashboard': d, 'folderUid': '${FOLDER_UID}', 'overwrite': True}))
PYEOF
)

if [[ "$DRY_RUN" != "true" ]]; then
  URL=$(api POST "/api/dashboards/db" --data "$PAYLOAD" | python3 -c "import sys,json; print(json.load(sys.stdin).get('url',''))")
  echo "  Dashboard: ${GRAFANA_URL}${URL}"
fi

# Alert rules
echo "Deploying alert rules..."
python3 - <<PYEOF
import json, sys, subprocess

try:
    import yaml
except ImportError:
    print("  PyYAML not installed — skipping alert push (pip install pyyaml)")
    sys.exit(0)

TOKEN  = "${GRAFANA_TOKEN}"
BASE   = "${GRAFANA_URL}"
FOLDER = "${FOLDER_UID}"
DRY    = "${DRY_RUN}" == "true"

def curl(method, path, payload=None):
    cmd = ["curl", "-fsSL", "-X", method,
           "-H", f"Authorization: Bearer {TOKEN}",
           "-H", "Content-Type: application/json",
           BASE + path]
    if payload:
        cmd += ["--data", json.dumps(payload)]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"HTTP error on {method} {path}: {r.stderr}")
    return json.loads(r.stdout)

with open("${SCRIPT_DIR}/alerts.yaml") as f:
    spec = yaml.safe_load(f)

for group in spec.get("groups", []):
    for rule in group.get("rules", []):
        body = {
            "uid": rule["uid"], "title": rule["title"], "orgID": 1,
            "folderUID": FOLDER, "ruleGroup": "UPS Monitoring",
            "condition": rule["condition"], "for": rule["for"],
            "annotations": rule.get("annotations", {}),
            "labels": rule.get("labels", {}),
            "data": rule["data"],
            "noDataState": "NoData", "execErrState": "Error",
        }
        if DRY:
            print(f"  [dry run] {rule['title']}")
            continue
        try:
            curl("PUT", f"/api/v1/provisioning/alert-rules/{rule['uid']}", body)
            print(f"  updated: {rule['title']}")
        except RuntimeError:
            curl("POST", "/api/v1/provisioning/alert-rules", body)
            print(f"  created: {rule['title']}")
PYEOF

echo "Done."
echo "  Dashboard: ${GRAFANA_URL}/d/cdz2g1b7hnda8a/ups-monitoring"
echo "  Alerts:    ${GRAFANA_URL}/alerting/list"

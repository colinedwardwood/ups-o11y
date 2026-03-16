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
ORG=$(api GET "/api/org" | python3 -c "import sys,json; print(json.load(sys.stdin).get('name','?'))")
echo "Connected: ${ORG} @ ${GRAFANA_URL}"
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
import json, sys, urllib.request, urllib.error

try:
    import yaml
except ImportError:
    print("  PyYAML not installed — skipping alert push (pip install pyyaml)")
    sys.exit(0)

TOKEN = "${GRAFANA_TOKEN}"
BASE  = "${GRAFANA_URL}"
FOLDER = "${FOLDER_UID}"
DRY   = "${DRY_RUN}" == "true"

def api(method, path, payload=None):
    req = urllib.request.Request(
        BASE + path,
        data=json.dumps(payload).encode() if payload else None,
        method=method,
        headers={"Authorization": f"Bearer {TOKEN}", "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req) as r:
        return json.loads(r.read())

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
            api("PUT", f"/api/v1/provisioning/alert-rules/{rule['uid']}", body)
            print(f"  updated: {rule['title']}")
        except urllib.error.HTTPError as e:
            if e.code == 404:
                api("POST", "/api/v1/provisioning/alert-rules", body)
                print(f"  created: {rule['title']}")
            else:
                raise
PYEOF

echo "Done."
echo "  Dashboard: ${GRAFANA_URL}/d/cdz2g1b7hnda8a/ups-monitoring"
echo "  Alerts:    ${GRAFANA_URL}/alerting/list"

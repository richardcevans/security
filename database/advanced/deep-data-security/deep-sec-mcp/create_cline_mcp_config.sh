#!/bin/bash
# Generate a Cline mcp-remote OAuth configuration for this lab's MCP server.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ENV_FILE="${SCRIPT_DIR}/.deep-sec-mcp.env"
OUTPUT_FILE="${SCRIPT_DIR}/cline_mcp_settings.generated.json"

usage() {
  cat <<'EOF'
Usage: ./create_cline_mcp_config.sh [--output=path]

Creates a Cline mcp-remote MCP settings file for the lab's MCP server.
It does not modify the VS Code or Cline settings file automatically.

The generated Cline entry uses mcp-remote with the public OAuth client created
by ./02_register_cline_mcp_client.sh. It does not contain an access token or
client secret. mcp-remote completes browser login and stores its token locally.
EOF
}

for arg in "$@"; do
  case "$arg" in
    --output=*) OUTPUT_FILE="${arg#*=}" ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: .deep-sec-mcp.env is not available. Run ./00_configure_lab_env.sh first." >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$ENV_FILE"
source "${SCRIPT_DIR}/lib_oci_profile.sh"

if [ -z "${MCP_SERVER_ID:-}" ]; then
  echo "ERROR: MCP_SERVER_ID is not set. Run ./create_mcp_server_tools.sh first." >&2
  exit 1
fi
if [ -z "${MCP_CLINE_CLIENT_ID:-}" ] || [ -z "${MCP_CLINE_CLIENT_SCOPE:-}" ]; then
  echo "ERROR: Cline OAuth client values are not set. Run ./02_register_cline_mcp_client.sh first." >&2
  exit 1
fi

oci_query() {
  PYTHONWARNINGS="${PYTHONWARNINGS:+${PYTHONWARNINGS},}ignore::FutureWarning:urllib3.poolmanager" \
    oci_with_profile "$@"
}

endpoint="${MCP_SERVER_ENDPOINT:-}"
if [ -z "$endpoint" ]; then
  server_json=$(oci_query dbtools mcp-server get --mcp-server-id "$MCP_SERVER_ID" --output json 2>/dev/null) || {
    echo "ERROR: Could not retrieve MCP server ${MCP_SERVER_ID}." >&2
    echo "Next: Verify OCI credentials and Database Tools read permission." >&2
    exit 1
  }
  endpoint=$(SERVER_JSON="$server_json" python3 - <<'PY'
import json
import os

try:
    data = json.loads(os.environ["SERVER_JSON"]).get("data", {})
except (json.JSONDecodeError, KeyError):
    raise SystemExit(0)

def find_url(value):
    if isinstance(value, str) and value.startswith(("https://", "http://")):
        return value
    if isinstance(value, dict):
        for key in ("endpoint", "url", "value"):
            found = find_url(value.get(key))
            if found:
                return found
        for nested in value.values():
            found = find_url(nested)
            if found:
                return found
    if isinstance(value, list):
        for nested in value:
            found = find_url(nested)
            if found:
                return found
    return ""

print(find_url(data.get("endpoints") or data.get("endpoint") or ""))
PY
)
fi

if [ -z "$endpoint" ]; then
  echo "ERROR: The MCP server response did not include an endpoint." >&2
  echo "Next: Copy the endpoint from the MCP server details page in the OCI Console." >&2
  exit 1
fi

umask 077
ENDPOINT="$endpoint" MCP_CLINE_CLIENT_ID="$MCP_CLINE_CLIENT_ID" MCP_CLINE_CLIENT_SCOPE="$MCP_CLINE_CLIENT_SCOPE" python3 - "$OUTPUT_FILE" <<'PY'
import json
import os
import sys

settings = {
    "mcpServers": {
        "deep-sec-mcp": {
            "disabled": False,
            "timeout": 60,
            "type": "stdio",
            "command": "npx",
            "args": [
                "-y",
                "mcp-remote",
                os.environ["ENDPOINT"],
                "8080",
                "--transport",
                "http-only",
                "--static-oauth-client-metadata",
                json.dumps({"scope": os.environ["MCP_CLINE_CLIENT_SCOPE"]}),
                "--static-oauth-client-info",
                json.dumps({"client_id": os.environ["MCP_CLINE_CLIENT_ID"]}),
            ],
        }
    }
}
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(settings, handle, indent=2)
    handle.write("\n")
PY
chmod 600 "$OUTPUT_FILE"

echo "Created Cline MCP settings: ${OUTPUT_FILE}"
echo "  MCP endpoint = ${endpoint}"
echo "  MCP server   = ${MCP_SERVER_ID}"
echo "  OAuth client = ${MCP_CLINE_CLIENT_ID}"
echo "Next: merge the deep-sec-mcp entry into Cline's cline_mcp_settings.json."
echo "      When Cline starts it, mcp-remote opens browser login on localhost:8080."

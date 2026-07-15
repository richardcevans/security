#!/bin/bash
# Print optional Terraform and OCI CLI commands for Database Tools MCP setup.

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ENV_FILE="${SCRIPT_DIR}/.deep-sec-mcp.env"

if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

echo
echo -e "${GREEN}============================================================================${NC}"
echo -e "${GREEN}      Optional MCP Server Commands                                          ${NC}"
echo -e "${GREEN}============================================================================${NC}"
echo

cat <<EOF
Terraform packages are available under:

  terraform/deep-sec-mcp-free-tier-sandbox-terraform-minimal-schema.zip
  terraform/deep-sec-mcp-ora-corp-sandbox-terraform-minimal-schema.zip
  terraform/deep-sec-mcp-ora-corp-base-db-system-sandbox-terraform-minimal-schema.zip

Use Terraform or Resource Manager when you want to pre-create compartments,
ADB, buckets, Database Tools connections, and MCP servers.

For a manual OCI CLI MCP server creation, collect these values:

  MCP_COMPARTMENT_OCID       = ${MCP_COMPARTMENT_OCID:-<compartment_ocid>}
  DATABASE_TOOLS_CONNECTION_ID = ${DATABASE_TOOLS_CONNECTION_ID:-<database_tools_connection_ocid>}
  MCP_IDENTITY_DOMAIN_OCID   = ${MCP_IDENTITY_DOMAIN_OCID:-<identity_domain_ocid>}
  MCP_BUCKET_NAME            = ${MCP_BUCKET_NAME:-<bucket_name>}

Command shape:

  oci dbtools mcp-server create-mcp-server-default \\
    --compartment-id "${MCP_COMPARTMENT_OCID:-<compartment_ocid>}" \\
    --connection-id "${DATABASE_TOOLS_CONNECTION_ID:-<database_tools_connection_ocid>}" \\
    --display-name "deep-sec-mcp" \\
    --domain-id "${MCP_IDENTITY_DOMAIN_OCID:-<identity_domain_ocid>}"

After creation, record:

  MCP_SERVER_ID       = ${MCP_SERVER_ID:-<mcp_server_ocid>}
  MCP_SERVER_ENDPOINT = ${MCP_SERVER_ENDPOINT:-<mcp_endpoint_url>}

EOF

echo -e "${YELLOW}This script prints commands only; it does not create or change OCI resources.${NC}"
echo

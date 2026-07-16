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

To create or reuse ADB-S, OCI IAM OAuth apps, groups, demo users, and wallet
from Cloud Shell, run:

  ./setup_adbs_oci_iam.sh <compartment-name-or-ocid>
  source ./.deep-sec-mcp.env

For a manual OCI CLI MCP server creation, collect these values:

  MCP_COMPARTMENT_OCID       = ${MCP_COMPARTMENT_OCID:-<compartment_ocid>}
  DATABASE_TOOLS_CONNECTION_ID = ${DATABASE_TOOLS_CONNECTION_ID:-<database_tools_connection_ocid>}
  MCP_IDENTITY_DOMAIN_OCID   = ${MCP_IDENTITY_DOMAIN_OCID:-<identity_domain_ocid>}
  MCP_BUCKET_NAME            = ${MCP_BUCKET_NAME:-<bucket_name>}

To discover OCI inputs from the tenancy, run:

  ./discover_mcp_inputs.sh

To create the Object Storage bucket, Database Tools connection, MCP server,
and built-in SQL toolset from .deep-sec-mcp.env, run:

  ./create_mcp_server_tools.sh

For token-based MCP access, use:

  DATABASE_TOOLS_CONNECTION_AUTHENTICATION_TYPE=TOKEN
  DATABASE_TOOLS_RUNTIME_IDENTITY=AUTHENTICATED_PRINCIPAL
  MCP_RUNTIME_IDENTITY=RESOURCE_PRINCIPAL
  MCP_CREATE_BUILT_IN_SQL_TOOLSET=1
  MCP_BUILT_IN_SQL_TOOLSET_VERSION=1

Command shape:

  oci dbtools mcp-server create-mcp-server-default \\
    --compartment-id "${MCP_COMPARTMENT_OCID:-<compartment_ocid>}" \\
    --connection-id "${DATABASE_TOOLS_CONNECTION_ID:-<database_tools_connection_ocid>}" \\
    --display-name "deep-sec-mcp" \\
    --domain-id "${MCP_IDENTITY_DOMAIN_OCID:-<identity_domain_ocid>}" \\
    --storage '{"type":"OBJECT_STORAGE","bucket":{"namespace":"<namespace>","bucketName":"<bucket_name>"}}' \\
    --runtime-identity RESOURCE_PRINCIPAL

Built-in SQL toolset command shape:

  oci dbtools mcp-toolset create-mcp-toolset-built-in-sql-tools \\
    --compartment-id "${MCP_COMPARTMENT_OCID:-<compartment_ocid>}" \\
    --display-name "${MCP_BUILT_IN_SQL_TOOLSET_NAME:-deep-sec-mcp-built-in-sql-tools}" \\
    --mcp-server-id "${MCP_SERVER_ID:-<mcp_server_ocid>}" \\
    --toolset-version "${MCP_BUILT_IN_SQL_TOOLSET_VERSION:-1}" \\
    --default-execution-type SYNCHRONOUS

After creation, record:

  MCP_SERVER_ID       = ${MCP_SERVER_ID:-<mcp_server_ocid>}
  MCP_BUILT_IN_SQL_TOOLSET_ID = ${MCP_BUILT_IN_SQL_TOOLSET_ID:-<toolset_ocid>}
  MCP_SERVER_ENDPOINT = ${MCP_SERVER_ENDPOINT:-<mcp_endpoint_url>}

EOF

echo -e "${YELLOW}This script prints commands only; it does not create or change OCI resources.${NC}"
echo

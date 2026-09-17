# Oracle SQL MCP
Oracle SQL MCP is a reusable Python pattern for exposing controlled Oracle SQL
tools through Streamable HTTP. It combines FastMCP, OCI IAM user login, OCI IAM
token introspection, and `python-oracledb` Deep Data Security identity
propagation. The optional CLI adds OCI Generative AI function calling.

The server is domain-neutral. It exposes schema discovery and read-only SQL;
the database remains authoritative for row and column access control.

## What runs where

```text
User → client browser login → OCI IAM access token
                             ↓ Authorization: Bearer <token>
                        MCP HTTP server → OCI IAM introspection
                             ↓ validated user token
                     Oracle Database / Deep Data Security
```

The included CLI is one client implementation. Any HTTP MCP client can use the
same server if it obtains an allowed OCI IAM access token and sends it in the
Authorization header.

## Tools

| Tool | Purpose |
| --- | --- |
| `get_current_user` | Return the identity visible to the database session. |
| `list_tables` | List accessible tables for an owner or `DEFAULT_SCHEMA`. |
| `describe_table` | Return accessible column metadata. |
| `execute_sql` | Run one guarded read-only statement. |

`execute_sql` permits one `SELECT`, `WITH`, or `EXPLAIN PLAN FOR SELECT`
statement. It rejects comments and multiple statements, caps results, and is
not a substitute for database privileges or Deep Data Security policies.

## OCI IAM configuration

This pattern uses three existing IAM roles. The names below are conceptual;
their values are supplied through `.env`.

| IAM object | Purpose | Project settings |
| --- | --- | --- |
| Browser Login Client | Authenticates the human with authorization code flow. Its configured resource grant requests the user token. | `APP_CLIENT_ID`, `APP_CLIENT_SECRET`, `APP_SCOPE`, `REDIRECT_URI` |
| Database/Midtier confidential client | Obtains the database token for `python-oracledb` and introspects the caller token for the HTTP resource server. Enable its OAuth **Introspect** operation. | `DB_CLIENT_ID`, `DB_CLIENT_SECRET`, `DB_SCOPE` |
| Resource application | Defines the token audience and access scope for the service. | `MCP_AUTH_AUDIENCE`, `MCP_REQUIRED_SCOPES` |

For the HR example used during development:

```dotenv
# Browser client requests the fully-qualified resource scope.
APP_SCOPE=deepsec1e09c30LangChainHRe09c30deepsec1e09c30_AGENT_ACCESS_e09c30

# The token emitted by OCI IAM carries the resource's Primary Audience and
# the short local scope name. These are server validation values.
MCP_AUTH_AUDIENCE=deepsec1e09c30LangChainHRe09c30
MCP_REQUIRED_SCOPES=deepsec1e09c30_AGENT_ACCESS_e09c30
```

Do not assume `APP_SCOPE` and `MCP_REQUIRED_SCOPES` are textually identical.
`APP_SCOPE` is the scope requested by the client; `MCP_REQUIRED_SCOPES` must
match the access token's actual `scope` claim.

The server validates every HTTP request by calling OCI IAM:

```text
POST <OCI_DOMAIN_URL>/oauth2/v1/introspect
```

It requires an active token with the configured issuer, audience, expiry, and
scope. This avoids relying on a JWKS endpoint that may be restricted in an OCI
IAM domain.

## Install

Python 3.11 or later is required.

```bash
python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install -e .
```

On managed hosts with a supplied Python runtime, install the approved runtime
dependencies and run from source instead:

```bash
PYTHONPATH="$PWD/src" python3 -c \
  'from mcp.server.fastmcp import FastMCP; import httpx, oci, oracledb; print("Dependencies available")'
```

## Configure

### Automated ADB and OCI IAM setup

The reusable setup automation is in [adb-oci-iam](adb-oci-iam). It is copied
from the companion ADB/OCI IAM lab and configured for this MCP implementation.
It creates or reuses the ADB/IAM resources, then writes both
`adb-oci-iam/.adb-oci-iam.env` and this project's ignored `.env` with the MCP
runtime variable names. The confidential midtier app is configured with
OAuth `allowedOperations=["introspect"]`, which is required for the server's
token verifier.

For an existing ADB, export the following before running setup. (Note that tags are
optional, depending on if your OCI tenancy requires them):

```bash
export EXISTING_DB_DSN='<wallet-tns-alias>'
export WALLET_DIR="$HOME/adb_wallet/<database-name>"
export ADMIN_PWD='<adb-admin-password>'
export WALLET_PWD='<wallet-password>'
export OCI_PROFILE=console-login
export OCI_CLI_PROFILE=console-login
export OCI_CLI_AUTH=security_token
export OCI_AUTH_TYPE=SECURITY_TOKEN
export OCI_CONFIG_FILE="$HOME/.oci/config"
export OCI_IAM_OCITAGS_JSON='{"definedTags":[{"namespace":"dbspmo","key":"UsageType","value":"Others"}]}'
```

Then run the standard database setup sequence:

```bash
cd adb-oci-iam
./00_setup_adb.sh
source ./.adb-oci-iam.env
./01_enable_oci_iam.sh
./02_create_hr_schema.sh
./03_create_data_roles_and_grants.sh
./verify_db_setup.sh
./set_oci_iam_passwords.sh --all
cd ..
```

`00_setup_adb.sh` creates `.env` with `DB_*`, `APP_*`, and `MCP_*` values for
this application. Review it locally if necessary, then start the server. If a
CLI security token has expired, refresh it with
`oci session authenticate --region <region> --profile-name console-login`.

The setup script generates the required settings:

```dotenv
# Database and Deep Data Security
DB_USER=<database-pool-user>
DB_PASSWORD=<database-pool-password>
DB_DSN=<wallet-tns-alias>
SSL_CONFIG_DIR=/path/to/wallet
WALLET_PWD=<wallet-password>
DEFAULT_SCHEMA=<optional-default-owner>
DB_CLIENT_ID=<existing-midtier-client-id>
DB_CLIENT_SECRET=<existing-midtier-client-secret>
DB_SCOPE=<database-resource-scope>

# OCI IAM browser login
OCI_DOMAIN_URL=https://idcs-<domain>.identity.oraclecloud.com:443
APP_CLIENT_ID=<browser-login-client-id>
APP_CLIENT_SECRET=<browser-login-client-secret>
APP_SCOPE=<browser-client-resource-scope>
REDIRECT_URI=http://localhost:8888/callback

# MCP HTTP resource server
MCP_RESOURCE_SERVER_URL=http://127.0.0.1:8000/mcp
MCP_AUTHORIZATION_SERVER_URL=https://idcs-<domain>.identity.oraclecloud.com:443
MCP_TOKEN_ISSUER=https://identity.oraclecloud.com/
MCP_AUTH_AUDIENCE=<resource-primary-audience>
MCP_REQUIRED_SCOPES=<access-token-scope>
```

`MCP_INTROSPECTION_URL`, `MCP_INTROSPECTION_CLIENT_ID`, and
`MCP_INTROSPECTION_CLIENT_SECRET` default to `OCI_DOMAIN_URL` plus the existing
`DB_CLIENT_ID` and `DB_CLIENT_SECRET`. Set them only when using a separate
server-only introspection client.

For the companion chat client, configure OCI Generative AI separately:

```dotenv
OCI_CONFIG_FILE=/path/to/oci/config
OCI_PROFILE=<oci-api-key-or-session-profile>
GENAI_AUTH_TYPE=api_key
COMPARTMENT_ID=<genai-compartment-or-tenancy-ocid>
MODEL_ID=<generative-ai-model-ocid>
OCI_GENAI_ENDPOINT=https://inference.generativeai.<region>.oci.oraclecloud.com
```

`GENAI_AUTH_TYPE=api_key` is recommended when the selected OCI profile contains
both API-key and session-token fields. The GenAI signer is independent of the
end-user token used by MCP and the database.

## Run

Start the server:

```bash
PYTHONPATH="$PWD/src" python3 -m oracle_sql_mcp.server \
  --host 127.0.0.1 --port 8000
```

Start the companion chat client in another terminal:

```bash
PYTHONPATH="$PWD/src" python3 -m oracle_sql_mcp.client_app \
  --server-url http://127.0.0.1:8000/mcp
```

The client opens OCI IAM browser login, then uses the authenticated MCP tools in
its GenAI tool-call loop. Try `who am i` or `what tables can I see`.

For a remote VM, run this on the workstation before starting the client on the
VM so the registered localhost callback reaches the VM:

```bash
ssh -N -L 8888:127.0.0.1:8888 <vm-user>@<vm-host>
```

On managed VMs, source the required view/runtime first. If Python cannot load
`libffi.so.8`, prepend its directory to `LD_LIBRARY_PATH`; if OCI IAM TLS
verification fails, set `SSL_CERT_FILE="$(python3 -m certifi)"` or use the
organization's approved CA bundle.

## Security and deployment

- Streamable HTTP is the only supported transport.
- The server is an OAuth resource server: it does not perform browser login,
  issue tokens, or store caller tokens.
- FastMCP rejects missing or invalid bearer tokens before tools execute and
  publishes protected-resource metadata at
  `/.well-known/oauth-protected-resource/mcp`.
- Bind to loopback for development. Remote deployment requires HTTPS, a public
  `MCP_RESOURCE_SERVER_URL`, network controls, audit logging, and token-policy
  review.
- Database policies decide visible rows and columns. A no-row response is row
  filtering; a `NULL` field is column masking.

## Layout

| Path | Purpose |
| --- | --- |
| `server.py` | FastMCP server and SQL tools. |
| `token_verifier.py` | OCI IAM token-introspection verifier. |
| `auth.py` | Client-owned browser authorization-code flow. |
| `database.py` | Oracle pool and end-user identity propagation. |
| `mcp_client.py` | Authenticated Streamable HTTP client adapter. |
| `client_app.py`, `genai_chat.py` | Optional OCI GenAI chat client and tool loop. |
| `sql.py` | Read-only SQL guard. |

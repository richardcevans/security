# OCI IAM Web HR App

This is the OCI IAM OAuth version of the lightweight Web HR app. It uses the
OCI IAM public client created by `deep-sec-mcp/setup_adbs_oci_iam.sh` and
Authorization Code with PKCE. ID-token signatures are verified against the
identity domain's published JWKS.

1. Copy `.env.example` to `.env` and set `WEB_HR_REDIRECT_URI` to the exact
   public HTTPS callback registered on the OCI IAM public client.
2. Install dependencies in the VM's virtual environment:

   `pip install -r requirements.txt`

3. Start with `./run.sh`, then open `https://<host>:8012`.

Each request connects directly to ADB with the signed-in OCI IAM OAuth access
token and the wallet paths saved by the DeepSec MCP lab. Oracle Database then
applies the OCI IAM data roles and HR data grants to every SQL statement.

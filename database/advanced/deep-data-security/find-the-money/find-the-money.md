# Find the Money

Find the Money is a Deep Data Security demo for an AI-assisted financial investigation app.

```text
browser user -> Microsoft Entra ID -> Find the Money
                                  -> pooled Oracle Database connection as app identity
                                  -> end-user security context per request
                                  -> FIN schema
                                  -> SQL, graph, and vector-style evidence queries
                                  -> optional OCI Generative AI chat in us-chicago-1
```

The app intentionally exposes a broad database-agent surface. The LLM can generate SQL and request graph or vector-style evidence, but Oracle Database remains the enforcement point for rows, columns, graph evidence, vector evidence, masks, and audit records.

## What This Lab Adds

- A new `FIN` schema with customers, accounts, transactions, vendors, cases, alerts, beneficial owners, and case-note evidence.
- Reuse of the existing Web HR Entra application, `WEB_HR_APP_USER`, and `WEB_HR_APP` application identity.
- FIN data grants attached to Entra app roles for tellers, investigators, senior investigators, auditors, plus a disabled `FINAPP_AI_INVESTIGATOR` app-mediated evidence role.
- A SQL property graph creation attempt for `FIN.MONEY_GRAPH`, with app fallback to protected relational money-flow queries if graph support is unavailable.
- A vector evidence creation attempt for case-note embeddings, with app fallback to protected text-similarity search if vector support is unavailable.
- A Unified Audit policy for FIN object access.
- A DBA policy toggle that removes or restores AI access to raw case-note evidence text without changing app code.
- A web app that exposes generated SQL, graph traversal, vector search, chat summarization, diagnostics, and audit evidence.

## Task 0: Download find-the-money.zip

```bash
cd livelabs
wget -O find-the-money.zip https://objectstorage.us-ashburn-1.oraclecloud.com/p/xTq6v3hC4YVpHJ6Sygc-uzvGWpxX_8F5HMX_CUcM_WJ4hZ36xRQuApU4WZA0a5Mj/n/oradbclouducm/b/dbsec_public/o/find-the-money.zip
unzip -o find-the-money.zip
cd find-the-money
ls
```

## Prerequisites

Complete the `entra-id-data-grants` lab first. This lab expects:

- `../entra-id-data-grants/.entra-id-data-grants.env`
- The existing `hrdb` TNS alias for the lab PDB
- Entra database/resource app values: `APP_ID`, `APP_ID_URI`, and `TENANT_ID`
- The existing Entra database/resource app from the prior lab. This lab reuses that app registration and adds FIN-specific app roles to it.
- Oracle Database 26ai home at `/opt/oracle/product/26ai/dbhome_1`

On the DBSec-Lab VM, source the DB23 Free environment before running database-side tasks:

```bash
source $DBSEC_ADMIN/setEnv-db23free.sh FREE FREEPDB1
unset WALLET_DIR TNS_ADMIN
```

This sets `ORACLE_HOME`, `ORACLE_SID=FREE`, and `PDB_NAME=FREEPDB1` for Oracle AI Database 26ai Free. Clearing `WALLET_DIR` and `TNS_ADMIN` prevents stale values from another database home from overriding the lab wallet and network settings.

## Configure Entra ID

Reuse the existing Web HR Entra web application:

```bash
WEB_HR_APP_ENV=/home/oracle/DBSecLab/livelabs/deep-data-security/web-hr-app/.web-hr-app.env \
./00_setup_entra_web_app.sh --reuse-web-hr-app
```

This writes `.find-the-money.env` from the existing Web HR app client ID, client secret, redirect URI, TLS certificate, and python-oracledb wallet. It does not create a separate Entra application.

Create the Find the Money demo users and assign FIN app roles on the reused database/resource app:

```bash
./05_setup_entra_demo_users.sh
```

The script creates these users when they do not already exist:

| User | Role Assignments |
| --- | --- |
| `alex@<domain>` | `FINAPP_TELLERS` |
| `priya@<domain>` | `FINAPP_TELLERS`, `FINAPP_INVESTIGATORS` |
| `marcus@<domain>` | `FINAPP_TELLERS`, `FINAPP_INVESTIGATORS`, `FINAPP_SENIOR_INVESTIGATORS` |
| `nora@<domain>` | `FINAPP_AUDITORS` |

Set `FIND_MONEY_DEMO_PASSWORD` before running the script if you want a fixed password. Set `RESET_FIND_MONEY_PASSWORDS=1` to reset existing demo users to that password.

To create a separate Entra app for an isolated test, omit `--reuse-web-hr-app`.

For local-only browser testing:

```bash
./00_setup_entra_web_app.sh --localhost
```

For an explicit public redirect:

```bash
./00_setup_entra_web_app.sh --redirect-uri https://<public-ip>:8013/callback
```

## Configure Database Objects

Create the FIN schema, sample data, application identity, and Deep Data Security policy:

```bash
source $DBSEC_ADMIN/setEnv-db23free.sh FREE FREEPDB1
unset WALLET_DIR TNS_ADMIN
source ./.find-the-money.env
./01_configure_database_app_identity.sh
./02_verify_application_identity.sh
./03_configure_auditing.sh
./04_configure_policy_toggle_demo.sh
```

The reused pooled app user gets normal object privileges on `FIN` tables, but returned data is governed by the end-user security context and active data roles.

## OCI Generative AI

The app can call the OCI Generative AI OpenAI-compatible chat API in the Oracle Chicago region:

To create a Generative AI API key from OCI CLI for the `DBSec_Rich` compartment:

```bash
./06_setup_oci_genai_api_key.sh
```

The script defaults to:

- Region: `us-chicago-1`
- Compartment name: `DBSec_Rich`
- OpenAI-compatible endpoint: `https://inference.generativeai.us-chicago-1.oci.oraclecloud.com/openai/v1`
- Model: `openai.gpt-oss-120b`

Override the model if your tenancy uses a different enabled Chicago model:

```bash
FIND_MONEY_OCI_GENAI_MODEL='<model_id>' ./06_setup_oci_genai_api_key.sh
```

The script writes the create response to `.find-the-money-genai-api-key.json` and appends the app environment variables to `.find-the-money.env`. OCI returns API key secret material only at create time, so keep the JSON file secure and do not commit it.

Manual configuration is also supported:

```bash
cat >> ./.find-the-money.env <<'EOF'
export FIND_MONEY_OCI_GENAI_BASE_URL='https://inference.generativeai.us-chicago-1.oci.oraclecloud.com/openai/v1'
export FIND_MONEY_OCI_GENAI_MODEL='openai.gpt-oss-120b'
export FIND_MONEY_OCI_COMPARTMENT_ID='<compartment_ocid>'
export FIND_MONEY_OCI_GENAI_API_KEY='<oci_genai_api_key>'
EOF
```

Use an OCI Generative AI API key for the OpenAI-compatible endpoint. Keep it in `.find-the-money.env` on the VM only; do not commit it. The app sends only evidence already returned by Oracle under the current end-user Deep Data Security context to the chat model.

If these values are not set, the app still runs and uses local SQL templates plus mock summaries. Deep Data Security testing does not depend on the chat call being configured. The Diagnostics page preflight check reports whether the API key, model, compartment, and Chicago endpoint are configured.

## Run

Mock mode needs no dependencies:

```bash
FIND_MONEY_DB_MODE=mock ./run.sh
```

Oracle mode:

```bash
./start.sh
./status.sh
```

Open the URL printed by `./start.sh`, usually:

```text
http://localhost:8013/
```

## Demo Flow

Use the same prompt under different identities:

```text
Find the money behind suspicious transaction TXN-90017.
Include all owners, accounts, transfers, similar case notes, and final beneficiaries.
```

Then run:

- `Ask as SQL`
- `Follow Graph`
- `Vector Search`
- `Summarize Evidence`
- `Refresh Audit Events`

The key proof point is that the generated SQL or graph/vector request can be broad, but the result differs by user because Oracle enforces the end-user context.

## Operational Guardrails

The app intentionally exposes broad read queries for the FIN schema. It still keeps basic lab safety controls:

- One SQL statement at a time.
- `SELECT` and `WITH` only by default.
- Set `FIND_MONEY_ALLOW_DML=1` only in a disposable lab database.
- All generated SQL is shown in the UI.
- Every database call is auditable through Unified Audit.

## Publish

Use the shared lab publisher to refresh the reusable Object Storage archive and PAR:

```bash
/home/revans/publish_lab_zip.sh /path/to/find-the-money dbsec_public find-the-money.zip
```

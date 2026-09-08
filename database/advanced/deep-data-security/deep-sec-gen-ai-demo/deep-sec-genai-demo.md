# Deep Security GenAI Demo

## Introduction

This lab extends the working [`../adb-oci-iam`](../adb-oci-iam/adb-oci-iam.md) lab.
It combines OCI IAM database authentication, Deep Data Security data grants,
Unified Auditing, OCI Generative AI, and a local token-preserving service.

The proof is that an OCI IAM database access token reaches Autonomous AI
Database (ADB) unchanged. ADB applies the caller's Deep Data Security grants to
every HR query, including queries initiated by the service for an LLM workflow.

### Prerequisites

- Complete the `adb-oci-iam` lab and retain its environment file, wallet, and
  working OCI IAM OAuth configuration.
- Have OCI CLI, SQL*Plus, curl, and Python 3 available on the lab host.
- Use a non-production tenancy and ADB with the HR Deep Data Security data
  grants already configured.

### Objectives

- Prove OCI Generative AI access in Chicago.
- Verify that OCI IAM identity and Deep Data Security grants reach ADB through
  a backend service.
- Audit protected HR access and distinguish SQL*Plus from service provenance.
- Use OCI Generative AI to select bounded, parameterized HR query tools.

Estimated Time: 60 minutes

## Task 0: Download and unzip the lab files

In a terminal on the lab host, download the current script bundle before
continuing. The archive preserves executable permissions for the shell scripts.

```bash
<copy>
export DBSEC_LABS="${DBSEC_LABS:-$HOME/dbsec-labs}"
mkdir -vp "$DBSEC_LABS/deep-data-security"
cd "$DBSEC_LABS/deep-data-security"
wget -O deep-sec-gen-ai-demo.zip https://objectstorage.us-ashburn-1.oraclecloud.com/p/zxnIwtQ4Jxt9sylQUMYjfYMBLa_UHgOuJyMwYkQJZ0J2_62F5TionMi0okdi1H9v/n/oradbclouducm/b/dbsec_public/o/deep-sec-gen-ai-demo.zip
unzip -o deep-sec-gen-ai-demo.zip
cd deep-sec-gen-ai-demo
</copy>
```

Use `unzip -o` when refreshing the archive so newly added files are included.
This extension requires the adjacent `../adb-oci-iam` lab directory; download
and complete that base lab first if it is not already present.

## Architecture

```text
OCI IAM user and database access token
                 |
                 v
    loopback service validates token signature and audience
                 |
                 v
python-oracledb opens ADB connection with the same caller token
                 |
                 v
Deep Data Security authorizes HR.EMPLOYEES rows and columns
                 |
                 v
reviewed, parameterized query tool result
                 |
                 v
OCI Generative AI selects a tool and answers from its result
```

The service uses the local OCI CLI profile only for OCI Generative AI. It uses
the caller's bearer token—not `ADMIN`, a service schema, or a shared database
account—for the ADB connection.

## Security model

| Component | Responsibility | Does not do |
| --- | --- | --- |
| `adb-oci-iam` | Creates ADB, OAuth setup, HR data, data roles, and data grants | Run GenAI or host this service |
| OCI IAM access token | Identifies the interactive user to ADB | Grant database privileges by itself |
| ADB Deep Data Security | Enforces the user's available HR data | Trust LLM output as authorization |
| Local service | Validates token and runs reviewed tools as caller | Accept SQL from the client or LLM |
| OCI Generative AI | Selects reviewed tools and forms an answer | Connect to ADB or execute SQL |
| Unified Auditing | Records HR access and end-user context | Replace authorization |

This is a local, loopback-only proof of architecture. It is not a production
deployment: it has no HTTPS listener, persistent session store, rate limiting,
centralized secrets management, or production observability.

## Prerequisites

Complete and verify `../adb-oci-iam` first. This extension expects
`../adb-oci-iam/.adb-oci-iam.env` to provide:

- `ADB_SERVICE`, `TNS_ADMIN`, and `WALLET_PWD`
- `OCI_DOMAIN_URL`, `OCI_AUDIENCE`, and `OCI_SCOPE`
- `ROOT_COMP_ID` for OCI Generative AI
- `OCI_TOKEN_DIR` containing a current `token` file

You also need `oci`, `sqlplus`, `curl`, and Python 3. The scripts honor one OCI
profile selector: `OCI_PROFILE_NAME`, `OCI_PROFILE`, or `OCI_CLI_PROFILE`.

Load the completed base-lab environment before running this extension:

```bash
<copy>
cd ../adb-oci-iam
source ./.adb-oci-iam.env
cd ../deep-sec-gen-ai-demo
</copy>
```

Inspect the inherited environment without changing OCI resources:

```bash
<copy>
./00_show_adb_environment.sh
</copy>
```

If the token has expired, obtain a new one in the base lab, then return here:

```bash
<copy>
cd ../adb-oci-iam
./04_get_iam_oauth_token.sh
cd ../deep-sec-gen-ai-demo
</copy>
```

## Task 1: Prove OCI Generative AI access

This test is independent of ADB. It calls the Chicago OCI Generative AI
endpoint with a harmless fixed prompt.

```bash
<copy>
./01_genai_chicago_smoke.sh
</copy>
```

For a direct LLM-only experiment, with no ADB data involved:

```bash
<copy>
./02_genai_llm_chat.sh \
  --prompt 'Explain Oracle data roles in one sentence.'
</copy>
```

The defaults are `meta.llama-3.3-70b-instruct` in `us-chicago-1`. Override
them with `GENAI_MODEL_ID` and `GENAI_REGION` when needed.

## Task 2: Review the current user's authorized HR data

The following scripts connect to ADB as the current OCI IAM token user. They
return only non-sensitive employee fields; they do not return SSN, salary,
phone number, or photo.

```bash
<copy>
# Run one fixed, reviewed SELECT as the current OCI IAM user.
./03_query_hr_employees_as_current_user.sh

# Send only the returned JSON rows and your question to OCI Generative AI.
./04_llm_with_authorized_hr_data.sh \
  --prompt 'How many authorized employees are listed?'
</copy>
```

`04` is a data-to-LLM bridge. The model does not query ADB in that flow; it
only reasons over rows that ADB already returned.

`08_llm_query_hr_as_current_user.sh` is an earlier command-line tool-routing
proof. It remains useful for comparison, but the local service is the primary
dynamic path.

```bash
<copy>
./08_llm_query_hr_as_current_user.sh \
  --prompt 'How many employees can I access by department?'
</copy>
```

## Task 3: Enable and inspect Unified Auditing

Enable the lab's narrow policy once. It audits `SELECT`, `UPDATE`, and `DELETE`
on `HR.EMPLOYEES` for all database users.

```bash
<copy>
./06_enable_hr_employees_audit.sh
</copy>
```

The policy name is `DEEPSEC_HR_EMPLOYEES_AUDIT`. The script is safe to re-run,
does not purge audit records, and prints its SQL before execution. New database
sessions are audited, so reconnect sessions that predate the policy.

Show the newest ten HR audit events:

```bash
<copy>
./07_show_hr_employees_audit_trail.sh
</copy>
```

The report shows UTC timestamp, command, database user, client program, and
Deep Data Security end user.

### Why the client program changes from SQL*Plus

`CLIENT PROGRAM` is provenance, not the authenticated identity.

| Query path | Typical client program | Deep Data Security end user |
| --- | --- | --- |
| Interactive verification | `sqlplus@RCEVANS-H1MXSW3 ...` | OCI IAM user who obtained the token |
| Python service calls | Oracle-generated `oracle@...oraclevcn.com` label | Same OCI IAM user |

SQL*Plus connects directly from your workstation. The dynamic path opens the
ADB connection from the Python backend with `python-oracledb`, so ADB records a
different client program. For this token-authenticated ADB path, the Unified
Audit Trail records Oracle's `oracle@...oraclevcn.com` session label instead of
the local Python executable name.

This does **not** change authorization. Confirm identity in the `DEEP DATA
SECURITY END USER` column. A service query for Marvin should still show
`MARVIN@EXAMPLE.COM`. Do not use the client-program string as an
authorization decision; use end-user identity, command, object, timestamp, and
application-level correlation when needed.

## Task 4: Start the token-preserving service

Create the project-local Python virtual environment once:

```bash
<copy>
python3 -m venv .venv
.venv/bin/python -m pip install -r service/requirements.txt
</copy>
```

The service is intentionally bound to `127.0.0.1:8030`. Start it in Terminal 1:

```bash
<copy>
./09_start_identity_service.sh
</copy>
```

The start script automatically uses `.venv/bin/python`; activation is optional.

| Endpoint | Purpose |
| --- | --- |
| `GET /healthz` | Local service health check |
| `POST /v1/identity/proof` | Proves the caller token can connect to ADB |
| `POST /v1/query` | Runs one reviewed, parameterized HR query tool |
| `POST /v1/ask` | Runs the bounded LLM tool loop |

Restart Terminal 1 whenever `service/identity_service.py` changes.

## Task 5: Verify caller identity propagation

In Terminal 2, with a current OAuth token:

```bash
<copy>
./10_verify_identity_service.sh
</copy>
```

Expected shape:

```json
{
  "proof": "pass",
  "token_subject": "MARVIN@EXAMPLE.COM",
  "database": {
    "authenticated_identity": "MARVIN@EXAMPLE.COM",
    "authentication_method": "TOKEN_GLOBAL",
    "client_program_name": "oracle@...oraclevcn.com",
    "visible_employee_rows": 4
  }
}
```

Visible row count depends on the caller's grants. The key proof is that token
subject and ADB authenticated identity match.

## Task 6: Call structured database query tools

The service accepts a tool name and validated arguments, never SQL text. Every
tool opens a short-lived ADB connection using the caller's bearer token.

```bash
<copy>
./11_query_identity_service.sh employee_count
./11_query_identity_service.sh employees_by_department
./11_query_identity_service.sh employees_by_job_code
./11_query_identity_service.sh list_employees --department-id 1 --limit 10
./11_query_identity_service.sh list_employees --job-code SWE2 --limit 10
</copy>
```

| Tool | Arguments | Result |
| --- | --- | --- |
| `employee_count` | none | Count of authorized `HR.EMPLOYEES` rows |
| `employees_by_department` | none | Authorized row count by department |
| `employees_by_job_code` | none | Authorized row count by job code |
| `list_employees` | `department_id`, `job_code`, `limit` | Non-sensitive employee fields only |

`department_id` must be a positive integer. `job_code` permits letters,
numbers, and underscores only. `limit` must be from 1 through 100. The service
rejects unknown tools, unknown arguments, and invalid values before any ADB
query is issued.

## Task 7: Ask the LLM through the dynamic service

The dynamic LLM path is `POST /v1/ask`, invoked by this client script:

```bash
<copy>
./12_ask_llm_service.sh \
  --question 'How many employees can I access by department?'
</copy>
```

The service performs two OCI Generative AI calls:

1. The model selects one allowed query tool and validated arguments.
2. The service runs that tool as the OCI IAM token user.
3. The model receives the tool result and writes an answer based only on it.

    The response includes the selected tool, authorized result, and final answer.
    The model cannot supply SQL, connect to ADB, retrieve unreturned columns, or
    bypass ADB data grants.

    After any service query, inspect the audit trail:

    ```bash
    <copy>
    ./07_show_hr_employees_audit_trail.sh
    </copy>
    ```

## Task 8: Clean up

After completing all service and audit verification, disable and drop only the
lab's `DEEPSEC_HR_EMPLOYEES_AUDIT` Unified Auditing policy:

```bash
<copy>
./99_disable_hr_employees_audit.sh
</copy>
```

This cleanup does not delete audit records, ADB resources, OCI IAM resources,
the base `adb-oci-iam` lab, or the local virtual environment.

## Troubleshooting

| Symptom | Action |
| --- | --- |
| `ORA-25708` or expired-token message | Run `../adb-oci-iam/04_get_iam_oauth_token.sh`, then retry. |
| `curl: (7) Couldn't connect to server` | Start `./09_start_identity_service.sh` in Terminal 1. |
| Python dependency error | Create `.venv` and install `service/requirements.txt`. |
| ADB token connection fails | Run `./10_verify_identity_service.sh`; compare token subject with `authenticated_identity`. |
| No expected HR rows | Validate OCI IAM group membership and base-lab data grants. |
| Audit shows `oracle@...oraclevcn.com` for service queries | Expected for this token-authenticated ADB service path; confirm the Deep Data Security end user instead. |
| GenAI request fails | Run `./01_genai_chicago_smoke.sh` with the same profile and compartment. |

## Deliberately deferred components

This lab does not create a new ADB, OCI IAM users or groups, OAuth
applications, Terraform resources, external tables, managed MCP resources, or
a web UI.

The separate MCP identity artifact,
[05_mcp_identity_proof.md](05_mcp_identity_proof.md), documents what must be
proven before a managed MCP path is used for protected data. It does not claim
that an MCP configuration automatically propagates Deep Data Security identity.

The previous Terraform/orchestration scaffold is preserved under
[`automate_with_tf/`](automate_with_tf/README.automated.md). The Select AI
experiment is preserved under `automate_with_tf/select_ai_experiment/` and is
not part of the active path.

You may now proceed to the next lab.

## Acknowledgements

* **Author** - Richard Evans
* **Last Updated By/Date** - Richard Evans, July 2026

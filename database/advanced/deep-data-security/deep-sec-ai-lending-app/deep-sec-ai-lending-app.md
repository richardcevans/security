# Deep Sec AI Lending App

## Introduction

The Deep Sec AI Lending App, also called DEAL, is a terminal-based lending
assistant that proves Oracle Deep Data Security enforcement for SQL reads,
restricted columns, vector retrieval, and optional OCI Generative AI tool calls.

The app intentionally uses broad database queries. Linda, a loan officer, and
Wendy, an underwriter, run the same tool functions. Oracle Database decides
which loan rows, sensitive columns, and policy documents each user can see.

```text
Linda or Wendy -> Python DEAL app -> Oracle AI Database 26ai on ADB-S
                                  -> Deep Sec end-user session
                                  -> loan rows, restricted columns, policy vectors
                                  -> optional OCI Generative AI answer
```

> **Warning:** Run this lab only in an isolated demo, sandbox, or
> non-production environment. The steps create or modify Deep Data Security end
> users, data roles, data grants, demo tables, and database access settings. Do
> not run the lab against production databases or identity configuration.

Estimated Time: 45 minutes

### Objectives

In this lab, you will:

- Configure a Python app to connect to Oracle AI Database 26ai on Autonomous
  Database Serverless.
- Create a lending demo schema with loan applications and policy documents.
- Create Deep Sec data roles and data grants for Linda and Wendy.
- Verify row, column, and vector retrieval enforcement under two end users.
- Run broad assistant tool calls and confirm the database remains the security
  boundary.
- Optionally connect the same secured tools to OCI Generative AI.

## What This Lab Does

- Uses an ADB-S 26ai wallet connection through `python-oracledb` Thin mode.
- Creates `LOAN_APPLICATIONS` and `LOAN_POLICIES` in the tutorial owner schema.
- Stores deterministic demo vectors in a `VECTOR(3, FLOAT32)` column.
- Creates `LOAN_OFFICER_ROLE` and `UNDERWRITER_ROLE` data roles.
- Grants Linda access to assigned applications and general or loan-officer
  policies.
- Grants Wendy access to underwriting-queue applications and general or
  underwriter policies.
- Demonstrates that broad SQL and vector retrieval are scoped by Deep Data
  Security instead of application-side filters.

## Before You Start

Use this checklist before you run the first command:

- You can sign in to an OCI tenancy.
- You have access to an OCI compartment where you can create or reuse an
  Autonomous Database Serverless instance.
- Your tenancy has capacity for an Always Free ADB-S instance, or you are
  allowed to create a paid ADB-S instance after changing the setup script
  defaults.
- OCI Cloud Shell is available. Cloud Shell is recommended because OCI CLI is
  already configured there.
- SQL*Plus is available in the shell where you run the setup script.
- Python 3.10 or later is available in the shell where you run the app.
- You are running this lab in a sandbox, demo, or disposable environment.

This app targets ADB-S 26ai. It does not target Oracle Database Free or a local
Oracle container.

## Beginner Concepts

This lab uses a few Deep Data Security terms:

- `DEEPSEC_ADMIN` is a normal database schema user. It owns the demo tables and
  runs the setup scripts.
- `linda` and `wendy` are Deep Sec end users. They are not schema owners and do
  not own tables. They represent the people using the app.
- A data role is a policy holder. This lab creates `LOAN_OFFICER_ROLE` and
  `UNDERWRITER_ROLE`.
- A data grant is the row and column rule attached to a data role.
- `DEAL_DIRECT_LOGON_ROLE` carries `CREATE SESSION` so the local Deep Sec end
  users can connect directly for this compact lab.

The key idea is that the app does not decide what Linda or Wendy can see. The
database applies the data grants before rows, columns, or policy documents leave
Oracle Database.

## ADB-S Setup Notes

The setup script creates an Always Free ADB-S instance by default. If your
tenancy already has the maximum number of Always Free Autonomous Databases, the
create step may fail. In that case, either delete an unused Always Free database,
reuse an existing ADB-S 26ai database by setting `DB_NAME`, or adjust the script
for a paid ADB-S instance if your organization allows it.

The default database name is `dealdeepsec<host-suffix>`, where the suffix is
derived from the shell host name. This avoids name collisions when several lab
machines use the same compartment.

The setup script writes secrets to local files:

- `.deal-adb.env`
- `.env`

Both files are ignored by Git. Keep them on the lab machine only.

## Find Your Compartment

If you do not know which compartment to use, list the compartments visible to
your OCI user:

```bash
<copy>
oci iam compartment list \
  --compartment-id-in-subtree true \
  --access-level ACCESSIBLE \
  --lifecycle-state ACTIVE \
  --all \
  --query 'data[].{Name:name,OCID:id}' \
  --output table
</copy>
```

Use either the compartment name or OCID with `00_setup_adb.sh`. If you are only
testing in a personal tenancy, you can use `root`, but most organizations prefer
a dedicated compartment.

## Task 0: Download the App

1. From your lab VM or client machine, change to the Deep Data Security lab
   directory.

    ```bash
    <copy>
    mkdir -vp $DBSEC_LABS/deep-data-security
    cd $DBSEC_LABS/deep-data-security
    </copy>
    ```

2. Download the app archive.

    ```bash
    <copy>
    wget -O deep-sec-ai-lending-app.zip https://objectstorage.us-ashburn-1.oraclecloud.com/p/LKSYqLeFv6MuLcA66AhfSffe_PDAwrXigA7Ys86Ih5jgvhyRzVpZwdjfYZCB_mde/n/oradbclouducm/b/dbsec_public/o/deep-sec-ai-lending-app.zip
    </copy>
    ```

3. Unzip the archive.

    ```bash
    <copy>
    unzip -o deep-sec-ai-lending-app.zip
    cd deep-sec-ai-lending-app
    ls
    </copy>
    ```

    You should see files such as:

    ```text
    00_setup_adb.sh
    01_verify_deepsec.py
    04_configure_deepsec.py
    10_run_deal_sessions.py
    deep-sec-ai-lending-app.md
    ```

## Task 1: Create ADB-S and Prepare Deep Sec

Run the setup script from OCI Cloud Shell or from a client where OCI CLI and
SQL*Plus can reach your tenancy and ADB-S wallet.

1. Create or reuse the ADB-S instance and prepare the database users.

    ```bash
    <copy>
    ./00_setup_adb.sh <compartment-name-or-ocid>
    </copy>
    ```

    To use the root compartment, run:

    ```bash
    <copy>
    ./00_setup_adb.sh root
    </copy>
    ```

    The setup script:

    - creates or reuses an Autonomous Database Serverless 26ai instance
    - downloads and unzips the ADB wallet
    - creates or resets `DEEPSEC_ADMIN`
    - grants the Deep Data Security privileges required by this lab
    - creates local Deep Sec end users `linda` and `wendy`
    - creates `DEAL_DIRECT_LOGON_ROLE` with `CREATE SESSION`
    - grants `DEAL_DIRECT_LOGON_ROLE` to `DEEPSEC_ADMIN` with admin option
    - writes `.deal-adb.env` and the Python app `.env`

    A successful run ends with output similar to:

    ```text
    Task 0 Completed: ADB-S and DEAL Deep Sec Admin Ready
    Environment file: ./deep-sec-ai-lending-app/.deal-adb.env
    Python app .env:  ./deep-sec-ai-lending-app/.env
    Next:
      source ./.deal-adb.env
      python 01_verify_deepsec.py
    ```

    If ADB creation fails with an Always Free capacity or limit message, see
    [Troubleshooting](#troubleshooting).

2. Optional: override defaults before running the script.

    ```bash
    <copy>
    export DB_NAME=dealdeepsec01
    export ADMIN_PWD='Oracle123+Oracle123+'
    export DEEPSEC_ADMIN_PWD='Oracle123+DeepSec+'
    export LINDA_PWD='Oracle123+Linda+'
    export WENDY_PWD='Oracle123+Wendy+'
    ./00_setup_adb.sh <compartment-name-or-ocid>
    </copy>
    ```

3. Load the generated ADB environment file.

    ```bash
    <copy>
    source ./.deal-adb.env
    </copy>
    ```

    The Python scripts read `.env` directly, so you do not need to manually set
    ADB wallet values after the setup script completes.

4. Confirm the generated files exist.

    ```bash
    <copy>
    ls -l .deal-adb.env .env
    </copy>
    ```

    Both files should be present and readable only by your user.

## Task 2: Configure Python and the App Environment

1. Create a Python virtual environment.

    ```bash
    <copy>
    python3 -m venv .venv
    source .venv/bin/activate
    python -m pip install --upgrade pip
    python -m pip install oracledb python-dotenv oci
    </copy>
    ```

    The `oci` package is required only for the optional OCI Generative AI task,
    but installing it here keeps the environment ready for every script.

    Look for successful installation messages for `oracledb`,
    `python-dotenv`, and `oci`. If `pip` reports permission errors, confirm that
    your virtual environment is active.

2. If you did not run `00_setup_adb.sh`, create `.env` from the example file.

    ```bash
    <copy>
    cp .env.example .env
    </copy>
    ```

3. Edit `.env` and set the ADB-S connection values.

    ```text
    ADB_USERNAME=DEEPSEC_ADMIN
    ADB_PASSWORD=<owner-password>
    ADB_DSN=<adb-wallet-alias-or-connect-descriptor>
    ADB_WALLET_LOCATION=<path-to-unzipped-wallet>
    ADB_WALLET_PASSPHRASE=<wallet-password>
    ```

4. Set the direct-logon Deep Sec values.

    ```text
    DEEPSEC_CONTEXT_MODE=direct_logon
    DEEPSEC_LINDA_KEY=<linda-password>
    DEEPSEC_WENDY_KEY=<wendy-password>
    DEAL_OBJECT_OWNER=DEEPSEC_ADMIN
    ```

    `DEEPSEC_DATABASE_ACCESS_TOKEN` is not used in `direct_logon` mode.

## Task 3: Verify the Database Connection

Run the environment check.

```bash
<copy>
python 01_verify_deepsec.py
</copy>
```

Look for output similar to:

```text
DEAL environment check
Connected as: DEEPSEC_ADMIN
Database version: Oracle AI Database 26ai ...
python-oracledb mode: Thin
Deep Sec metadata visible to this schema: ...
```

Continue only after this script connects successfully and reports Thin mode.

If the script reports Thick mode, remove any call to
`oracledb.init_oracle_client()` from your environment. This lab requires
`python-oracledb` Thin mode.

## Task 4: Create and Load the Lending Demo Data

1. Create the demo tables.

    ```bash
    <copy>
    python 02_create_schema.py
    </copy>
    ```

    The script creates:

    - `LOAN_APPLICATIONS`
    - `LOAN_POLICIES`, including a `VECTOR(3, FLOAT32)` column named
      `EMBEDDING`

    Expected output:

    ```text
    Dropped existing DEAL demo tables if they existed.
    Created loan_applications.
    Created loan_policies with VECTOR(3, FLOAT32) embedding column.
    Schema setup complete.
    ```

2. Load the synthetic lending data and policy documents.

    ```bash
    <copy>
    python 03_load_data.py
    </copy>
    ```

    The data includes six loan applications and eight policy documents. The
    policy rows use deterministic three-dimensional vectors so the lab does not
    require an embedding model.

    Expected output:

    ```text
    Inserted 6 loan applications.
    Inserted 8 loan policy documents.
    Synthetic data load complete.
    ```

## Task 5: Configure Deep Data Security

1. Create the data roles, data grants, and data-role assignments.

    ```bash
    <copy>
    python 04_configure_deepsec.py
    </copy>
    ```

    This script creates and enables:

    - `LOAN_OFFICER_ROLE`
    - `UNDERWRITER_ROLE`
    - data grants on `LOAN_APPLICATIONS`
    - data grants on `LOAN_POLICIES`
    - data-role assignments for `linda` and `wendy`
    - `DEAL_DIRECT_LOGON_ROLE` bindings to both data roles
    - mandatory data-grant enforcement on both demo tables

    After this script completes, reads from these tables are governed by Deep
    Data Security data grants.

    Expected output includes:

    ```text
    Granted LOAN_OFFICER_ROLE to LINDA.
    Granted UNDERWRITER_ROLE to WENDY.
    Granted DEAL_DIRECT_LOGON_ROLE to LOAN_OFFICER_ROLE.
    Granted DEAL_DIRECT_LOGON_ROLE to UNDERWRITER_ROLE.
    Enabled mandatory data-grant enforcement on DEAL tables.
    Configured Deep Data Security for DEAL.
    ```

## Task 6: Verify Row and Column Enforcement

Run the read demo.

```bash
<copy>
python 05_context_read_demo.py
</copy>
```

Linda should see only applications assigned to Linda. Wendy should see
applications in the underwriting queue. Sensitive underwriting fields that are
not granted to Linda should be returned as `NULL` or omitted by the database
policy.

The important proof is that the script uses a broad query:

```sql
SELECT *
FROM loan_applications
ORDER BY id
```

The app does not add a Linda or Wendy `WHERE` clause.

Expected proof points:

```text
As linda:
  Rows returned: 3
  Visible application ids: 101, 102, 105
  ...
  risk_score: NULL

As wendy:
  Rows returned: 4
  Visible application ids: 102, 103, 105, 106
  ...
  risk_score: 72
```

## Task 7: Verify Deep Sec-Scoped Vector Retrieval

1. Run a vector warm-up as Linda.

    ```bash
    <copy>
    python 07_vector_basics.py
    </copy>
    ```

    Linda should receive general or loan-officer policy titles only.

2. Run the secured vector retrieval demo.

    ```bash
    <copy>
    python 08_secure_rag_retrieval.py
    </copy>
    ```

    Linda and Wendy use the same vector search shape, but the database limits
    which policy rows can be ranked and returned for each end user.

    Expected proof point: Wendy can receive underwriting policy titles, while
    Linda cannot receive Wendy-only underwriting policy rows.

3. Optionally compare vector-style retrieval with a keyword query.

    ```bash
    <copy>
    python 08b_keyword_vs_vector_check.py
    </copy>
    ```

    Both retrieval styles run under the active Deep Sec end-user context.

## Task 8: Run the DEAL Tool Demo

1. Run the basic tool wrapper demo.

    ```bash
    <copy>
    python 09_deal_tools_demo.py
    </copy>
    ```

2. Run the complete Linda and Wendy session.

    ```bash
    <copy>
    python 10_run_deal_sessions.py
    </copy>
    ```

    Look for:

    - Linda sees Linda-scoped loan application rows.
    - Wendy sees Wendy-scoped underwriting rows.
    - Linda does not receive Wendy-only underwriting policy documents.
    - Wendy receives underwriter policy documents.
    - The bypass check reports scoped results even though the app did not use
      application-side row, redaction, or audience filters.

    Expected output includes:

    ```text
    DEAL session: linda
    Visible applications: 3
    Restricted risk_score: NULL

    DEAL session: wendy
    Visible applications: 4
    Underwriting risk_score: 72

    Bypass check
    No application-side row filter, redaction, or audience filter was used.
    ```

## Task 9: Optional OCI Generative AI Chatbot

The chatbot step lets OCI Generative AI choose which DEAL tool to call. The
model is not trusted for authorization. Every tool call still runs under Linda's
or Wendy's Deep Sec database context.

1. Confirm your OCI SDK config works from this machine.

    ```bash
    <copy>
    oci iam region list --output table
    </copy>
    ```

2. Set the OCI Generative AI values in `.env`.

    ```text
    OCI_CONFIG_FILE=~/.oci/config
    OCI_PROFILE=DEFAULT
    OCI_GENAI_ENDPOINT=https://inference.generativeai.us-chicago-1.oci.oraclecloud.com
    OCI_GENAI_COMPARTMENT_ID=<compartment-ocid>
    OCI_GENAI_MODEL_ID=<model-ocid>
    ```

3. Run the chatbot.

    ```bash
    <copy>
    python 11_oci_genai_chatbot.py
    </copy>
    ```

The expected security result is the same as Task 8: the model can request data,
but Oracle Database returns only what the active Deep Sec end user is allowed to
see.

## Task 10: Clean Up

Run the cleanup script when you no longer need the demo objects but want to keep
the ADB-S instance.

```bash
<copy>
python 99_cleanup.py
</copy>
```

The script drops the data grants, data roles, and demo tables created by the
app. It does not drop the `DEEPSEC_ADMIN` schema, the local Deep Sec end users,
or `DEAL_DIRECT_LOGON_ROLE`. Drop those separately only if they are no longer
used by any lab.

Expected output includes `Ran:` or `Skipped:` lines for each grant, role, and
table. `Skipped` usually means the object was already gone.

## Task 11: Optional Delete ADB-S

Use this task only when you created a disposable ADB-S instance for this lab and
no longer need it.

1. Confirm the generated ADB environment file exists.

    ```bash
    <copy>
    ls -l .deal-adb.env
    </copy>
    ```

2. Delete the ADB-S instance.

    ```bash
    <copy>
    ./12_delete_adb.sh --confirm-delete-adb
    </copy>
    ```

3. To also delete the downloaded wallet directory recorded in `.deal-adb.env`,
   add `--delete-wallet`.

    ```bash
    <copy>
    ./12_delete_adb.sh --confirm-delete-adb --delete-wallet
    </copy>
    ```

The delete script refuses to run unless you pass `--confirm-delete-adb`. It
only deletes the wallet directory automatically when the path is under
`$HOME/adb_wallet`.

## Validation Notes

The lab package has been checked for local syntax and packaging:

- `00_setup_adb.sh` passes shell syntax validation.
- The Python scripts modified for this lab pass Python bytecode compilation.
- The published ZIP contains `00_setup_adb.sh` with executable Unix file mode.
- The published ZIP reuses the existing PAR URL shown in Task 0.

The live ADB-S creation path is validated when Task 1 completes in your OCI
tenancy. If Task 1 fails, keep the error text and use the troubleshooting
sections below.

## Troubleshooting

### The setup script cannot find a compartment

Run the compartment list command in [Find Your Compartment](#find-your-compartment).
Use either the exact `Name` value or the `OCID` value. If your organization uses
policies that limit compartment visibility, ask your tenancy administrator for
the compartment where you can create Autonomous Database resources.

### ADB creation fails because of Always Free limits

The setup script creates Always Free ADB-S by default. If OCI reports an Always
Free limit, you have three options:

- Delete an unused Always Free Autonomous Database and rerun `00_setup_adb.sh`.
- Reuse an existing ADB-S 26ai database by setting `DB_NAME` to that database
  name before rerunning the script.
- If your organization allows paid resources, edit `00_setup_adb.sh` and remove
  `--is-free-tier true` before creating the database.

Do not switch to Oracle Database Free or a local container for this lab. The lab
targets ADB-S 26ai.

### SQL*Plus is not available

Run the setup from OCI Cloud Shell if possible. If you use your own client
machine, install Oracle Instant Client with SQL*Plus and confirm this command
works before rerunning setup:

```bash
<copy>
sqlplus -v
</copy>
```

### The app cannot find a wallet alias

Confirm that `ADB_WALLET_LOCATION` points to the unzipped wallet directory and
that the directory contains `tnsnames.ora`. If `ADB_DSN` is not set, the helper
uses the first alias ending in `_high`, or the first alias in `tnsnames.ora`.

### Linda or Wendy cannot connect

Confirm that:

- `DEEPSEC_CONTEXT_MODE=direct_logon`
- `DEEPSEC_LINDA_KEY` and `DEEPSEC_WENDY_KEY` match the local Deep Sec end-user
  passwords.
- `DEAL_DIRECT_LOGON_ROLE` has `CREATE SESSION`.
- `DEAL_DIRECT_LOGON_ROLE` was granted to `LOAN_OFFICER_ROLE` and
  `UNDERWRITER_ROLE`.
- `LOAN_OFFICER_ROLE` was granted to `linda`.
- `UNDERWRITER_ROLE` was granted to `wendy`.

### Deep Sec metadata views are not visible

The tutorial owner is missing Deep Data Security privileges, or Deep Data
Security is not enabled in the target database environment. Use ADB-S 26ai and
rerun the grants in Task 1.

### Vector table creation fails

Confirm the target database is Oracle AI Database 26ai and supports the
`VECTOR` data type. This lab creates `VECTOR(3, FLOAT32)`.

## What You Built

You built a lending assistant that keeps authorization in Oracle Database. The
application and optional LLM use broad tool functions, but Deep Data Security
enforces the active end-user identity before returning loan rows, restricted
columns, or policy documents.

For production, replace the deterministic demo vectors with embeddings from
your approved embedding model, add auditing around high-risk read paths, and use
your enterprise identity provider for end-user authentication.

## Acknowledgements

- **Author:** Richard Evans
- **Last Updated By/Date:** Richard Evans, May 2026

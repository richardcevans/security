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

## Assumptions

- You have Oracle AI Database 26ai on Autonomous Database Serverless.
- You have downloaded and unzipped the ADB wallet.
- You can connect as `ADMIN` or another account that can grant the required
  Deep Data Security privileges.
- You can create or use a tutorial owner schema. This lab uses `DEEPSEC`.
- You can create local Deep Sec end users named `linda` and `wendy`.
- Python 3.10 or later is available on the machine where you run the app.

This app targets ADB-S 26ai. It does not target Oracle Database Free or a local
Oracle container.

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

## Task 1: Prepare the ADB-S Database

Run this task as `ADMIN` or as another administrator account for the ADB-S
database.

1. Create the tutorial owner schema if it does not already exist.

    ```sql
    <copy>
    CREATE USER deepsec IDENTIFIED BY "<owner-password>";
    ALTER USER deepsec QUOTA UNLIMITED ON data;

    GRANT CREATE SESSION TO deepsec;
    GRANT CREATE TABLE TO deepsec;
    </copy>
    ```

    If your ADB-S database uses a different default tablespace, replace `data`
    with the appropriate tablespace name.

2. Grant the Deep Data Security privileges needed by the setup scripts.

    ```sql
    <copy>
    GRANT CREATE DATA ROLE TO deepsec;
    GRANT CREATE DATA GRANT TO deepsec;
    GRANT CREATE ANY DATA GRANT TO deepsec;
    GRANT ADMINISTER ANY DATA GRANT TO deepsec;
    GRANT GRANT ANY DATA ROLE TO deepsec;
    GRANT CREATE END USER TO deepsec;
    GRANT CREATE END USER SECURITY CONTEXT TO deepsec;
    GRANT SET USE DATA GRANTS ONLY TO deepsec;
    </copy>
    ```

3. Create the local Deep Sec end users used by the demo.

    ```sql
    <copy>
    CREATE END USER "linda" IDENTIFIED BY "<linda-password>";
    CREATE END USER "wendy" IDENTIFIED BY "<wendy-password>";
    </copy>
    ```

4. Create the database role that allows the local Deep Sec end users to connect
   directly after their data roles exist.

    ```sql
    <copy>
    CREATE ROLE deal_direct_logon_role;
    GRANT CREATE SESSION TO deal_direct_logon_role;
    </copy>
    ```

    The final grants from this role to the Deep Sec data roles happen later,
    after the app creates `LOAN_OFFICER_ROLE` and `UNDERWRITER_ROLE`.

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

2. Create `.env` from the example file.

    ```bash
    <copy>
    cp .env.example .env
    </copy>
    ```

3. Edit `.env` and set the ADB-S connection values.

    ```text
    ADB_USERNAME=DEEPSEC
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
    DEAL_OBJECT_OWNER=DEEPSEC
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
Connected as: DEEPSEC
Database version: Oracle AI Database 26ai ...
python-oracledb mode: Thin
Deep Sec metadata visible to this schema: ...
```

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

2. Load the synthetic lending data and policy documents.

    ```bash
    <copy>
    python 03_load_data.py
    </copy>
    ```

    The data includes six loan applications and eight policy documents. The
    policy rows use deterministic three-dimensional vectors so the lab does not
    require an embedding model.

## Task 5: Configure Deep Data Security

1. Create the data roles, data grants, and data-role assignments.

    ```bash
    <copy>
    python 04_configure_deepsec.py
    </copy>
    ```

    This script creates:

    - `LOAN_OFFICER_ROLE`
    - `UNDERWRITER_ROLE`
    - data grants on `LOAN_APPLICATIONS`
    - data grants on `LOAN_POLICIES`
    - data-role assignments for `linda` and `wendy`

2. As `ADMIN`, grant the direct-logon role to the two data roles.

    ```sql
    <copy>
    GRANT deal_direct_logon_role TO loan_officer_role;
    GRANT deal_direct_logon_role TO underwriter_role;
    </copy>
    ```

3. As the `DEEPSEC` owner, enable mandatory data-grant enforcement on the demo
   tables.

    ```sql
    <copy>
    SET USE DATA GRANTS ONLY ON loan_applications ENABLED;
    SET USE DATA GRANTS ONLY ON loan_policies ENABLED;
    </copy>
    ```

    After this point, reads from these tables are governed by Deep Data
    Security data grants.

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

## Task 7: Verify Deep Sec-Scoped Vector Retrieval

1. Run a vector warm-up as Linda.

    ```bash
    <copy>
    python 07_vector_basics.py
    </copy>
    ```

2. Run the secured vector retrieval demo.

    ```bash
    <copy>
    python 08_secure_rag_retrieval.py
    </copy>
    ```

    Linda and Wendy use the same vector search shape, but the database limits
    which policy rows can be ranked and returned for each end user.

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

Run the cleanup script as the `DEEPSEC` owner when you no longer need the demo
objects.

```bash
<copy>
python 99_cleanup.py
</copy>
```

The script drops the data grants, data roles, and demo tables created by the
app. It does not drop the `DEEPSEC` schema, the local Deep Sec end users, or
`DEAL_DIRECT_LOGON_ROLE`. Drop those separately only if they are no longer used
by any lab.

## Troubleshooting

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

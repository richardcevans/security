# Lab 1: Run a LangChain HR Agent with OCI IAM and Deep Data Security

## Introduction

Use the complete OCI IAM and Autonomous AI Database setup bundled with the
`deepsec-demos-ananya-single-agent-oci-demo` source directory. The setup
creates or reuses the demo identity, database, wallet, HR schema, data roles,
and data grants. You then run the LangChain HR assistant as different OCI IAM
users and observe that Oracle Deep Data Security controls the returned rows
and columns.

This lab is independent of the other demo labs. It is the suggested starting
point only because it includes the most complete setup path.

Estimated Time: 40 minutes

### Objectives

In this lab, you will:

- Prepare the OCI CLI and source bundle without committing credentials.
- Create or reuse the ADB, OCI IAM, sample HR data, and Deep Data Security
  configuration supplied by the demo.
- Verify database access as the sample `marvin` and `emma` users.
- Run the LangChain HR agent and compare user-scoped results.

### Prerequisites

- OCI Cloud Shell or a Linux host with Bash 4.x, OCI CLI, Python 3, SQL*Plus,
  and `unzip`.
- Permission to create or reuse the OCI IAM Identity Domain objects and ADB
  resources used by the setup scripts.
- OCI Generative AI quota in the region selected by the generated
  configuration if you want agent responses.
- The source directory is available under a parent directory you can name
  with `LAB_ROOT`. Review the [source README](../../deepsec-demos-ananya-single-agent-oci-demo/README.md)
  before running setup.

### Required files, directories, packages, and configuration

| Item | Required state |
| --- | --- |
| Source application | `app_config.py`, `db_connection.py`, `get_user_token.py`, `langchain_app.py`, `langchain_tools.py`, and `requirements.txt` under `langchain-agent-oci/`. |
| Setup directory | `adb-oci-iam/` with the numbered scripts, `lib_*.sh`, `check_oci_iam_login_readiness.sh`, and `decode_token.sh`. |
| Generated configuration | `adb-oci-iam/.adb-oci-iam.env` and application `.env`; both contain secrets and must have mode `600`. |
| OAuth token cache | The directory named by `OCI_TOKEN_DIR`, defaulting to `$HOME/.oci/adb-oci-iam`; keep it outside Git. |
| ADB wallet | `WALLET_DIR` must contain `tnsnames.ora`, `sqlnet.ora`, `cwallet.sso`, and `ewallet.p12`. |
| OCI configuration | `OCI_CONFIG_FILE` and the private key referenced by the selected `OCI_PROFILE`; keep both outside the lab checkout. |
| Host packages and tools | Bash 4.x, Python 3 with `venv` and `pip`, OCI CLI, SQL*Plus, `unzip`, `curl`, `wget`, `openssl`, `ca-certificates`, `libffi`, and `git`. `gcc` and `make` may be needed when Python wheels build locally. |

The setup scripts require the OCI CLI and SQL*Plus executables; neither is
provided by `requirements.txt`. Confirm both are on `PATH` before starting.

## Task 1: Prepare the source and OCI authentication

1. Set `LAB_ROOT` to the directory that contains the five `deepsec-demos-*`
   source directories, then enter this lab's application directory.

    ```bash
    <copy>
    export LAB_ROOT="${LAB_ROOT:-$HOME/dbsec-labs/deep-data-security}"
    cd "$LAB_ROOT/deepsec-demos-ananya-single-agent-oci-demo/langchain-agent-oci"
    </copy>
    ```

2. Confirm that the setup and application files are present.

    ```bash
    <copy>
    test -x adb-oci-iam/00_setup_adb.sh
    test -f langchain_app.py
    test -f requirements.txt
    </copy>
    ```

3. Select the OCI CLI profile that has the permissions required by this lab.
   If you use OCI session-token authentication, refresh it before setup and
   never copy the session token into a repository file.

    ```bash
    <copy>
    export OCI_PROFILE="<your-oci-profile>"
    export OCI_CLI_PROFILE="$OCI_PROFILE"
    oci iam region list --profile "$OCI_PROFILE" --output table
    </copy>
    ```

## Task 2: Create or reuse the ADB and Deep Data Security setup

1. Change to the setup directory and run the setup script. On a disposable
   environment, allow it to create the resources. To use an existing ADB,
   export the `EXISTING_DB_DSN`, `WALLET_DIR`, `WALLET_PWD`, and `ADMIN_PWD`
   values described in the source README before this step.

    ```bash
    <copy>
    cd "$LAB_ROOT/deepsec-demos-ananya-single-agent-oci-demo/langchain-agent-oci/adb-oci-iam"
    ./00_setup_adb.sh
    source ./.adb-oci-iam.env
    </copy>
    ```

2. Set the generated passwords, enable OCI IAM authentication, create the HR
   schema and Deep Data Security data grants, then verify the database.

    ```bash
    <copy>
    ./set_oci_iam_passwords.sh --all
    ./01_enable_oci_iam.sh
    ./02_create_hr_schema.sh
    ./03_create_data_roles_and_grants.sh
    ./verify_db_setup.sh
    </copy>
    ```

3. Confirm that the verification output shows the expected HR users, data
   roles, and role grants. Do not paste generated passwords, client secrets,
   wallet contents, or token files into the lab notes.

## Task 3: Verify end-user database access

1. Obtain an OCI IAM OAuth token using the generated configuration. Complete
   the browser flow if the script does not run headlessly in your environment.

    ```bash
    <copy>
    ./04_get_iam_oauth_token.sh --headless
    </copy>
    ```

2. Run the Marvin verification and record which HR rows and columns are
   visible through the Deep Data Security data roles.

    ```bash
    <copy>
    ./05_verify_as_marvin.sh
    </copy>
    ```

3. Obtain a fresh token for Emma and repeat the verification.

    ```bash
    <copy>
    ./04_get_iam_oauth_token.sh --headless
    ./06_verify_as_emma.sh
    </copy>
    ```

4. Compare the results. The application identity and database connection are
   shared, but Oracle evaluates the end-user context and returns only the
   rows and columns authorized for that user.

## Task 4: Run the LangChain HR agent

1. Create a project-local virtual environment and install the dependencies.
   The setup scripts create the ignored `.env` file used by the application.

    ```bash
    <copy>
    cd "$LAB_ROOT/deepsec-demos-ananya-single-agent-oci-demo/langchain-agent-oci"
    python3 -m venv .venv
    .venv/bin/python -m pip install -r requirements.txt
    source adb-oci-iam/.adb-oci-iam.env
    </copy>
    ```

2. Start the application.

    ```bash
    <copy>
    .venv/bin/python langchain_app.py
    </copy>
    ```

3. Sign in as `marvin` when the application opens or prints its OCI IAM login
   URL. Ask a question such as `Who reports to me?` and record the returned
   fields.

4. Stop the application, start it again, and sign in as `emma`. Ask the same
   question or ask for an employee salary summary. Compare the result with
   Marvin's result. An agent instruction cannot grant a row or column that
   the database data grants do not authorize.

5. If the application reports an error, inspect only the local diagnostic log
   and redact secrets before sharing it.

    ```bash
    <copy>
    tail -n 120 langchain_demo.log
    </copy>
    ```

## Task 5: Clean up optional lab resources

1. If this lab created a disposable environment and you have confirmed that no
   other work depends on it, review the cleanup script before running it.

    ```bash
    <copy>
    cd "$LAB_ROOT/deepsec-demos-ananya-single-agent-oci-demo/langchain-agent-oci/adb-oci-iam"
    sed -n '1,260p' 07_cleanup_adb_lab.sh
    </copy>
    ```

2. Use the least destructive cleanup mode that meets your need. Do not use a
   full removal mode against a shared or pre-existing ADB.

    ```bash
    <copy>
    ./07_cleanup_adb_lab.sh --delete-db-objects
    </copy>
    ```

    You may now proceed to the next lab, or select another independent lab.

## Learn More

- [Oracle Deep Data Security Guide](https://docs.oracle.com/en/database/oracle/oracle-database/26/ddscg/oracle-deep-data-security-guide.pdf)
- [Building Trusted Generative AI Experiences with Oracle Deep Data Security](https://blogs.oracle.com/database/building-trusted-genai-experiences-with-oracle-deep-data-security)
- [Source README and setup files](../../deepsec-demos-ananya-single-agent-oci-demo/README.md)

## Acknowledgements

* **Author** - Richard Evans
* **Last Updated By/Date** - September 2026

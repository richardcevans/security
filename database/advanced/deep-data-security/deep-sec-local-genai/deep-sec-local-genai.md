# Build a Local End-User Deep Data Security Web App

## Introduction

Build a web application that signs in directly to Autonomous AI Database as Emma, Marvin, or Carol. They are local Deep Data Security end users. The application runs one fixed query. Database grants, not Flask, determine the returned rows and columns. OCI Generative AI summarizes only the database-authorized result set.

Estimated Time: 60 minutes after the Stack Apply job completes. Allow additional time for Autonomous Database provisioning and Python package installation.

### Objectives

- Deploy Autonomous AI Database 26ai, a disposable VCN, and the Flask compute host.
- Create the `APPLAB` schema, local users, data roles, and data grants.
- Download an ADB wallet through OCI Console and upload it through JupyterLab.
- Sign in directly as Emma, Marvin, and Carol and compare database-enforced results.
- Ask OCI Generative AI to summarize authorized data only.

### Prerequisites

- A non-production OCI compartment and permission to create the lab resources.
- The provided Oracle Linux application-server image and an SSH public key.
- Access to download the ADB wallet from OCI Console.
- A browser whose public IPv4 address is known.

### Before You Start

Confirm each item before creating the Stack:

- The supplied custom image is visible in **US East (Ashburn)**. Use a compatible image OCID if you deploy elsewhere.
- Your organization permits an Autonomous AI Database with the supplied **BYOL**, 2-ECPU, and 1-TB storage defaults. These defaults can incur cost.
- You accept a public compute IP and browser access restricted to the one IPv4 address supplied to `allowed_ingress_home_ip_address`.
- The Stack operator can create compartment resources and, when `create_genai_iam = true`, tenancy-level dynamic groups and policies.
- The Ashburn region can use the default on-demand GenAI model, `google.gemini-2.5-flash`, or you have selected a compatible replacement model ID.

## Task 0: Deploy the Infrastructure with OCI Resource Manager

1. Download [deep-sec-local-genai-terraform.zip](https://objectstorage.us-ashburn-1.oraclecloud.com/p/Qr29aAUJD9vH5NaArxcqfk0CvgpmJBiEGNi9zfVbmHLb4kXq6ULqukuj5DQb2B0N/n/oradbclouducm/b/dbsec_public/o/deep-sec-local-genai-terraform.zip). Upload it to an OCI Resource Manager Stack without unzipping it.

2. In OCI Console, open **Developer Services**, **Resource Manager**, and **Stacks**. Create a Stack using **My configuration**. Set the configuration working directory to `terraform` and select Terraform 1.5.x.

3. Enter these Stack variables:

    - `tenancy_ocid`
    - `compartment_ocid`
    - `adb_admin_password`
    - `ssh_public_key`
    - `allowed_ingress_home_ip_address`: your current public IPv4 address, without `/32`

    Keep `create_genai_iam = true` to create the compute instance-principal dynamic group and Generative AI policy. Run **Plan**, then **Apply**. The Stack operator needs permission to manage Autonomous Database, instance-family, virtual-network-family, object-family, dynamic groups, and policies. Exact policy statements are in `terraform/README.md` in the Terraform ZIP.

4. After Apply completes, open the Stack **Application Information** tab. Save these values:

    - `adb_console_url`: direct link to the `deepsec7` database in OCI Console
    - `jupyter_url`: browser link to JupyterLab
    - `flask_url`: browser link to the completed web application
    - `ssh_command`: optional terminal access to the compute host

    The tab also shows the ADB `ADMIN` password as a sensitive value. Select **Unlock** only when you need to copy it. Use the Apply job **Outputs** page for `deepsec7_lab_summary`, which lists the ADB, network, wallet bucket, GenAI identity, ports, and trusted ingress CIDR. If Flask or JupyterLab does not open, update `allowed_ingress_home_ip_address` with the current browser public IPv4 address. Apply the Stack again.

## Task 1: Download the ADB Wallet in OCI Console

1. Open `adb_console_url` from the Resource Manager Apply job Outputs page.

2. On the `deepsec7` Autonomous Database details page, select **Database connection**, then **Download wallet**.

3. For **Wallet type**, select **Instance Wallet**. Select **Download**, enter the ADB `ADMIN` password as the wallet password, then download the ZIP to your local computer. Keep the downloaded filename as `Wallet_DEEPSEC7.zip`.

4. The wallet ZIP contains connection configuration and certificates; it does **not** contain the ADB `ADMIN` password or the Emma, Marvin, and Carol passwords. You enter those passwords only when prompted later in the lab.

## Task 2: Set Up the Compute Host with JupyterLab

1. Complete **Use JupyterLab on the App Server** before starting this task. Open `jupyter_url` from the Resource Manager Apply job Outputs page. In the JupyterLab file browser, select **+**. Under **Other**, select **Terminal**.

2. In the JupyterLab file browser, use the **Upload Files** button to upload your local `Wallet_DEEPSEC7.zip`. Then return to the terminal and verify the upload.

    Display the current JupyterLab working directory. The next commands use this directory to locate the uploaded wallet.

    ```
    <copy>pwd</copy>
    ```

    Confirm that the uploaded wallet ZIP is present and readable before using it.

    ```
    <copy>ls -l Wallet_DEEPSEC7.zip</copy>
    ```

    Save the wallet ZIP path in `WALLET_ZIP`. Later commands use this variable instead of requiring you to retype the path.

    ```
    <copy>export WALLET_ZIP="$PWD/Wallet_DEEPSEC7.zip"</copy>
    ```

3. Download and extract **exactly** `deep-data-security-flask-app.zip`. This is the only lab archive required on the compute host; it includes the Flask application and database SQL scripts.

    Create a dedicated directory for the extracted lab files. The `-v` option reports the directory that is created.

    ```
    <copy>mkdir -vp "$HOME/deepsec7-lab"</copy>
    ```

    Move into the lab directory so the downloaded archive and extracted files stay together.

    ```
    <copy>cd "$HOME/deepsec7-lab"</copy>
    ```

    Download the compute-host archive from the lab's published Object Storage location. Verbose output confirms the transfer progress and destination filename.

    ```
    <copy>wget --verbose -O deep-data-security-flask-app.zip https://objectstorage.us-ashburn-1.oraclecloud.com/p/Mzf75vY1KZat2TyYinBCgXRxO0q8Ky-adubY5hAAHj21tjcSBowCcJcHkBw6Glh5/n/oradbclouducm/b/dbsec_public/o/deep-data-security-flask-app.zip</copy>
    ```

    Extract the application and database scripts from the downloaded archive. The `-o` option permits replacement if you are rerunning the lab setup.

    ```
    <copy>unzip -o deep-data-security-flask-app.zip</copy>
    ```

    Enter the Flask application directory. All remaining compute-host commands in this task run from here unless stated otherwise.

    ```
    <copy>cd flask-app</copy>
    ```

4. Create the isolated Python environment, install the curated requirements, and verify the preinstalled SQL*Plus and Instant Client. These steps do not require `sudo`.

    Create or refresh the application's isolated Python virtual environment and install its required packages.

    ```
    <copy>bash setup_venv.sh</copy>
    ```

    Verify that the virtual environment, SQL*Plus, and Oracle Instant Client expected by the lab image are available.

    ```
    <copy>bash verify_app_server.sh</copy>
    ```

5. Install the wallet uploaded in step 2 into a protected directory. Replace the path if your JupyterLab upload is in a different directory.

    Extract the wallet into the protected location and update its configuration to use that directory.

    ```
    <copy>bash install_wallet.sh "$WALLET_ZIP"</copy>
    ```

    The installer reports the protected wallet directory: `$HOME/deepsec7-wallet/tns_admin`. It also updates the downloaded `sqlnet.ora` wallet location from the Instant Client default to that directory.

6. List the wallet aliases, then connect as the ADB administrator. This fixed lab uses `deepsec7_low`. Enter the ADB `ADMIN` password when prompted.

    List the service aliases provided by the extracted wallet. This confirms that the `deepsec7_low` alias is available.

    ```
    <copy>grep -E '^[[:alnum:]_]+[[:space:]]*=' "$HOME/deepsec7-wallet/tns_admin/tnsnames.ora"</copy>
    ```

    Point Oracle client tools to the extracted wallet directory for this terminal session.

    ```
    <copy>export TNS_ADMIN="$HOME/deepsec7-wallet/tns_admin"</copy>
    ```

    Display the value that Oracle client tools will use. It should be the protected wallet directory.

    ```
    <copy>echo "$TNS_ADMIN"</copy>
    ```

    Open a SQL*Plus session as the Autonomous Database administrator. SQL*Plus prompts for the `ADMIN` password without echoing it.

    ```
    <copy>sqlplus admin@deepsec7_low</copy>
    ```

7. Stay connected as ADB `ADMIN` and run the provisioning scripts. ADMIN creates the `APPLAB` schema, sample data, broad baseline data grants, and local end users. The user-creation script securely prompts for the Emma, Marvin, and Carol database passwords.

    Create the `APPLAB` schema and the customers table that the application queries.

    ```
    <copy>@../database/01_create_schema.sql</copy>
    ```

    Load the sample customer rows used for the before-and-after access comparison.

    ```
    <copy>@../database/02_load_sample_data.sql</copy>
    ```

    Run the intentional no-op application-account script. It documents that this lab does not use a shared database application account.

    ```
    <copy>@../database/03_create_app_user.sql</copy>
    ```

    Create the data roles and deliberately broad baseline grants. SQL*Plus displays the full data-role and data-grant DDL as it runs.

    ```
    <copy>@../database/04_create_baseline_access.sql</copy>
    ```

    Create the three password-authenticated local end users. Choose and record the Emma, Marvin, and Carol passwords when the script prompts.

    ```
    <copy>@../database/05_create_lab_users.sql</copy>
    ```

    The scripts create schema `APPLAB` and data roles `APP_EAST_SALES`, `APP_SALES_MANAGER`, and `APP_FINANCE`. The baseline-access script has SQL*Plus `ECHO` enabled, so the terminal prints each complete `CREATE DATA ROLE`, role grant, and `CREATE OR REPLACE DATA GRANT` statement as it executes. The baseline grants deliberately give every local end user all customer rows and columns. The application-account script is intentionally a no-op. This lab authenticates directly as each local end user; it does not use an IAM token or a shared database account.

8. Test each local end user through a separate SQL*Plus connection. Exit the ADMIN session, then use the supplied runner to connect as Emma and execute the unchanged validation query. The password prompt keeps the password out of shell history.

    Leave the privileged ADMIN connection before testing the application personas.

    ```
    <copy>exit</copy>
    ```

    Connect as Emma and run the fixed validation query. Enter Emma's local database password when prompted.

    ```
    <copy>./query_data.sh emma</copy>
    ```

    Connect as Marvin and run the same fixed validation query. Enter Marvin's local database password when prompted.

    ```
    <copy>./query_data.sh marvin</copy>
    ```

    Connect as Carol and run the same fixed validation query. Enter Carol's local database password when prompted.

    ```
    <copy>./query_data.sh carol</copy>
    ```

    You may optionally supply the password as the second argument, for example `./query_data.sh emma PASSWORD`. Replace `PASSWORD` with Emma's password. The prompt is safer because command-line passwords can appear in shell history or process listings. At this point, all three users return the same unrestricted data. Task 4 replaces this baseline with Deep Data Security policies.

    | Local user | Expected rows | Credit limit | Sensitive identifier |
    | --- | --- | --- | --- |
    | Emma | All customer rows | Visible | Visible |
    | Marvin | All customer rows | Visible | Visible |
    | Carol | All customer rows | Visible | Visible |

9. Return to the application directory and create the Flask configuration.

    Return to the application directory, where the environment configuration script is located.

    ```
    <copy>cd "$HOME/deepsec7-lab/flask-app"</copy>
    ```

    Generate the application configuration, validate the wallet, and accept the Terraform-provided GenAI defaults when prompted.

    ```
    <copy>./configure_env.sh</copy>
    ```

    The script explains each prompt, validates the wallet, generates a new `FLASK_SECRET_KEY` with `openssl rand -hex 32`, and writes `.env` with mode `600`. The application uses the Instant Client auto-login wallet (`cwallet.sso`), so it does not save the wallet password. Terraform has already supplied the GenAI policy compartment and the default on-demand model; press Enter at both GenAI prompts to accept them. The script preserves any existing `.env` as a timestamped backup.

    Do not add Emma, Marvin, or Carol passwords to `.env`. Students enter each local database password on the sign-in page.

10. Start the web server.

    Start the Flask application with Gunicorn on port 7777. Keep this terminal open while you test the web interface.

    ```
    <copy>./run.sh</copy>
    ```

    The web server listens on port 7777 and occupies this terminal while it runs. Leave this terminal open. Select **+**, then **Other** and **Terminal** in JupyterLab to open a second terminal. Use that terminal to remove the uploaded wallet ZIP or run cleanup. You do not need host-firewall changes or JupyterLab `sudo` access. The Stack controls VCN ingress with `allowed_ingress_home_ip_address`.

11. After confirming the application works, delete the uploaded wallet ZIP. The protected extracted wallet remains available to the application.

    Remove only the uploaded ZIP now that its contents are installed in the protected wallet directory. The `-v` option reports the removed file.

    ```
    <copy>rm -fv "$WALLET_ZIP"</copy>
    ```

## Task 3: Query App Data

1. From the trusted browser, open `flask_url` from the Stack outputs. Select **Emma: East Sales**. Enter the Emma database password and select **Sign in**. Run the query. Emma sees every customer row across all regions, including credit limits and sensitive identifiers.

2. Select **Sign out**. Select **Marvin: Sales Manager**. Enter the Marvin password and sign in. Run the unchanged query. Marvin receives the same unrestricted rows and fields that Emma received.

3. Select **Sign out**. Select **Carol: Finance**. Enter the Carol password and sign in. Run the same query. Carol also receives the same unrestricted result set. This establishes the before-policy baseline.

4. While signed in as Emma, enter this bounded prompt and select **Ask AI**.

    Use this prompt to ask OCI Generative AI about the rows returned for Emma. It explicitly directs the model to mention only fields that were available in that authorized result.

    ```
    <copy>Summarize all authorized customer rows. Mention credit limits and sensitive identifiers only when those values are available.</copy>
    ```

    The application queries ADB before it calls OCI Generative AI. The model receives only the returned rows and cannot generate or execute SQL. At this point, Emma's summary can reference the unrestricted baseline values.

## Task 4: Implement Deep Sec Policies

1. Keep Gunicorn running. In a second JupyterLab terminal, return to the application directory and connect as ADB `ADMIN`.

    Return to the application directory in the second terminal so the database script paths resolve correctly.

    ```
    <copy>cd "$HOME/deepsec7-lab/flask-app"</copy>
    ```

    Point SQL*Plus in this second terminal at the extracted wallet.

    ```
    <copy>export TNS_ADMIN="$HOME/deepsec7-wallet/tns_admin"</copy>
    ```

    Connect as ADB `ADMIN` to replace the baseline grants with Deep Data Security policy grants.

    ```
    <copy>sqlplus admin@deepsec7_low</copy>
    ```

2. Run the Deep Data Security policy script. SQL*Plus `ECHO` is enabled, so the terminal prints each complete replacement `CREATE OR REPLACE DATA GRANT` statement. It replaces the broad Task 3 data grants with the Emma, Marvin, and Carol policy grants.

    Execute the policy DDL and review the displayed grants to see the row and column restrictions assigned to each data role.

    ```
    <copy>@../database/06_implement_deep_sec_policies.sql</copy>
    ```

3. Exit SQL*Plus. You do not need to restart Flask because the app opens a new database connection for every query.

    Close the ADMIN session. The running application uses the updated grants the next time a persona signs in.

    ```
    <copy>exit</copy>
    ```

## Task 5: Test Deep Sec Policies

1. Return to the browser and sign in as **Emma: East Sales**. Run the unchanged query. Emma now sees only East sales rows. Credit limits and sensitive identifiers display as `Not authorized`.

2. Sign out and sign in as **Marvin: Sales Manager**. Run the unchanged query. Marvin now sees all EMMA and MARVIN sales rows. Credit limits remain visible, but sensitive identifiers display as `Not authorized`.

3. Sign out and sign in as **Carol: Finance**. Run the unchanged query. Carol sees every row across all regions, including Apex Treasury and Crown Capital. She can see sensitive identifiers.

4. Sign out and sign back in as Emma. Run the query and submit the same GenAI prompt from Task 3. Compare this answer with the Task 3 answer. The post-policy Emma summary cannot mention finance rows, credit limits, or sensitive identifiers because ADB no longer returns them.

## Task 6: Clean Up

1. In the terminal where Gunicorn is running, press `Ctrl+C` to stop the web server. Leave the terminal open.

2. In the second JupyterLab terminal, return to the application directory, set the wallet location, and reconnect as ADB `ADMIN`.

    Return to the application directory before running the cleanup script.

    ```
    <copy>cd "$HOME/deepsec7-lab/flask-app"</copy>
    ```

    Point SQL*Plus to the installed wallet for this cleanup terminal.

    ```
    <copy>export TNS_ADMIN="$HOME/deepsec7-wallet/tns_admin"</copy>
    ```

    Verify the wallet location before connecting as the administrator.

    ```
    <copy>echo "$TNS_ADMIN"</copy>
    ```

    Connect as ADB `ADMIN` so the cleanup script can remove the lab database objects.

    ```
    <copy>sqlplus admin@deepsec7_low</copy>
    ```

3. In the ADB administrator SQL*Plus session, remove the lab database objects.

    Remove the database users, data roles, grants, and schema created for this disposable lab.

    ```
    <copy>@../database/reset_lab.sql</copy>
    ```

4. Exit SQL*Plus, then remove the protected wallet directory from the compute host.

    Close the database administrator session after the cleanup script finishes.

    ```
    <copy>exit</copy>
    ```

    Remove the extracted wallet directory and its connection configuration from the compute host. The verbose option lists the deleted files.

    ```
    <copy>rm -rfv "$HOME/deepsec7-wallet"</copy>
    ```

5. In OCI Resource Manager, run a **Destroy** job for the Stack. This removes the Autonomous Database, compute instance, bucket, VCN, and optional GenAI IAM resources.

You may now proceed to the next lab.

## Acknowledgements

- **Author** - Richard Evans
- **Last Updated By/Date** - Richard Evans, July 2026

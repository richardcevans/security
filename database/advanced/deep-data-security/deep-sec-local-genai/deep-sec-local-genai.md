# Can AI-Generated Application Code Bypass Database Security?

## Introduction

You are Marvin, a sales user. An AI coding assistant can modify your application and ask Oracle Database for customer data that you should not see. What stops generated application code from bypassing your organization's security policy?

In this lab, you first see an intentionally insecure application result. You then move authorization into Oracle Autonomous AI Database with Deep Data Security, without changing the application's customer query. Finally, you promote Marvin legitimately and use Vibe to try application-level bypasses. Oracle determines which rows and columns can be returned.

Estimated Time: 60 minutes after the Resource Manager Stack is ready. Resource provisioning can take additional time.

### Objectives

- Observe an intentionally excessive customer-data result as Marvin.
- Apply Oracle Deep Data Security and observe the same application query return fewer rows and columns.
- Promote Marvin from sales employee to sales manager through a database authorization change.
- Use Vibe to add and attack application features without changing database authorization.

> **Lab design note:** Marvin is a local database user in this lab so you can directly observe Oracle authorizing an individual end user. Production applications can establish end-user identity differently. The important principle is that Oracle Database receives a trusted end-user identity or context and enforces authorization at the data layer.

### Prerequisites

- A non-production OCI compartment and permission to create the Stack resources.
- The supplied Oracle Linux application-server image and an SSH public key.
- A browser public IPv4 address and access to download an ADB wallet.

## Task 0: Deploy the Lab Environment

1. Download [deep-sec-local-genai-terraform.zip](https://objectstorage.us-ashburn-1.oraclecloud.com/p/Qr29aAUJD9vH5NaArxcqfk0CvgpmJBiEGNi9zfVbmHLb4kXq6ULqukuj5DQb2B0N/n/oradbclouducm/b/dbsec_public/o/deep-sec-local-genai-terraform.zip). Upload it unchanged to an OCI Resource Manager Stack. Select **My configuration**, set the working directory to `terraform`, and use Terraform 1.5.x.

2. Supply `tenancy_ocid`, `compartment_ocid`, `adb_admin_password`, `ssh_public_key`, and `allowed_ingress_home_ip_address`. Keep `create_genai_iam = true` unless your tenancy already authorizes the new compute instance to use OCI Generative AI for Vibe. Run **Plan**, then **Apply**.

3. When Apply completes, save these Application Information values: `adb_console_url`, `jupyter_url`, `flask_url`, and the protected ADB `ADMIN` password. The Stack creates the disposable database, compute host, private wallet bucket, and the instance-principal authorization Vibe uses.

## Task 1: Download the Wallet and Prepare JupyterLab

1. Open `adb_console_url`. On the `deepsec9` database page, select **Database connection**, download an **Instance Wallet**, enter the ADB `ADMIN` password when prompted, and save the file as `Wallet_DEEPSEC9.zip`.

2. Open `jupyter_url` and sign in with `Oracle123`. In JupyterLab, select **+**, **Other**, then **Terminal**. Upload `Wallet_DEEPSEC9.zip` with the file browser.

3. In the terminal, save the uploaded-wallet path, create the lab directory, download the compute package, and enter its application directory.

    ```
    <copy>export WALLET_ZIP="$PWD/Wallet_DEEPSEC9.zip"</copy>
    ```

    ```
    <copy>mkdir -pv "$HOME/deepsec9-lab"</copy>
    ```

    ```
    <copy>cd "$HOME/deepsec9-lab"</copy>
    ```

    ```
    <copy>wget -O deep-data-security-flask-app.zip https://objectstorage.us-ashburn-1.oraclecloud.com/p/Mzf75vY1KZat2TyYinBCgXRxO0q8Ky-adubY5hAAHj21tjcSBowCcJcHkBw6Glh5/n/oradbclouducm/b/dbsec_public/o/deep-data-security-flask-app.zip</copy>
    ```

    ```
    <copy>unzip -o deep-data-security-flask-app.zip</copy>
    ```

    ```
    <copy>cd flask-app</copy>
    ```

4. Install the wallet and prepare the supplied Oracle Customer Sales starter application. This professionally built, known-good application is the starting point for the lab and will later be extended with Vibe.

    ```
    <copy>bash install_wallet.sh "$WALLET_ZIP"</copy>
    ```

    ```
    <copy>bash setup_venv.sh</copy>
    ```

    ```
    <copy>bash verify_app_server.sh</copy>
    ```

    Expected: the verification reports SQL*Plus, Oracle Instant Client, and the application Python packages.

## Task 2: Configure the Database and Create Marvin

In this task, you create the application schema and sample data, configure an intentionally excessive starting grant, and create Marvin's local database account. Run every database script as the Autonomous AI Database `ADMIN` user. Marvin's password is created in step 6; it is not stored in the application.

1. **Connect to Autonomous AI Database as ADMIN.** Point this terminal at the installed wallet, then connect to the low service.

    ```
    <copy>export TNS_ADMIN="$HOME/deepsec9-wallet/tns_admin"</copy>
    ```

    ```
    <copy>sqlplus admin@deepsec9_low</copy>
    ```

    Enter the ADB `ADMIN` password when prompted. You will remain connected as `ADMIN` through step 6.

    **Expected:** SQL*Plus connects to Oracle AI Database 26ai and displays a `SQL>` prompt.

2. **Create the APPLAB application schema.** Create the database user, customer table, and supporting sales-representative index that the application will query.

    ```
    <copy>@../database/01_create_schema.sql</copy>
    ```

    This script recreates `APPLAB` so a rerun starts with an empty lab schema. It creates `APPLAB.CUSTOMERS` with the customer fields used in the demonstration, including `credit_limit` and `sensitive_identifier`.

    **Expected:** SQL*Plus reports a successful procedure, user, grants, table, and index. Typical output includes:

    ```text
    PL/SQL procedure successfully completed.
    User created.
    Grant succeeded.
    User altered.
    Table created.
    Index created.
    ```

3. **Load the sample customer data.** Populate `APPLAB.CUSTOMERS` with the accounts used in the before-and-after authorization tests.

    ```
    <copy>@../database/02_load_sample_data.sql</copy>
    ```

    The data contains 14 `MARVIN` accounts, 6 `SALES_TEAM` accounts, and 2 `FINANCE` accounts. `Apex Treasury` is a `FINANCE` account, so it is visible in the insecure baseline but must disappear after the employee and manager policies are active.

    **Expected:** SQL*Plus creates and commits 22 rows.

    ```text
    Session altered.
    22 rows created.
    Commit complete.
    ```

4. **Confirm the application authentication model.** Run the architecture script.

    ```
    <copy>@../database/03_create_app_user.sql</copy>
    ```

    This step confirms the direct database-authentication model. Oracle Customer Sales connects directly as Marvin with the password entered at sign-in, so Oracle can authorize Marvin's database session.

    **Expected:** SQL*Plus prints the direct-local-user design and creates no database objects.

    ```text
    Oracle Customer Sales uses direct database authentication as MARVIN.
    The password entered at sign-in is verified by Oracle Database for that session.
    Oracle Deep Data Security evaluates MARVIN's active data roles and grants.
    Flask receives only the rows and columns Oracle authorizes for MARVIN.
    No database objects are created by this step.
    ```

5. **Create roles and the intentionally insecure baseline.** Create the data roles used throughout the lab and the broad starting data grant.

    ```
    <copy>@../database/04_create_baseline_access.sql</copy>
    ```

    The script creates the `APP_BASELINE_ACCESS`, `APP_SALES_EMPLOYEE`, and `APP_SALES_MANAGER` data roles. It also creates `APP_LOCAL_CONNECT`, which provides the `CREATE SESSION` path for local end users. The `APPLAB.MARVIN_INSECURE_CUSTOMER_ACCESS` data grant gives `APP_BASELINE_ACCESS` every row and every column in `APPLAB.CUSTOMERS`.

    **Important:** this grant is intentionally excessive so you can observe the security problem before applying Deep Data Security. In the next task, Marvin can retrieve all 22 customers, including `Apex Treasury`, `credit_limit`, and `sensitive_identifier`. It is not a production configuration.

    **Expected:** SQL*Plus creates three data roles, the local-connect role, four successful grants, and the broad data grant. It then prints:

    ```text
    Baseline ready: APP_BASELINE_ACCESS permits all APPLAB.CUSTOMERS rows and columns.
    Script 05 grants this deliberately excessive role to MARVIN for the before-and-after demonstration.
    Do not use this baseline data grant in a production application.
    ```

6. **Create Marvin's local database account.** Create the password-authenticated end user who will sign in to the application.

    ```
    <copy>@../database/05_create_lab_users.sql</copy>
    ```

    At `Password for MARVIN (input hidden):`, enter a password for Marvin and record it. You will use it in the browser. The input is hidden and is not written to the terminal output or application configuration. This script grants `APP_BASELINE_ACCESS` to Marvin; it does not yet apply the employee policy.

    **Expected:** SQL*Plus reports that the end user and initial data-role assignment succeeded, then prints:

    ```text
    MARVIN starts with APP_BASELINE_ACCESS for the intentionally insecure baseline.
    Record Marvin's password, then use the application before applying the employee policy.
    ```

    The sample accounts make the next results easy to recognize:

    | Customer | Sales representative | Why it matters |
    | --- | --- | --- |
    | Frontier Goods | `MARVIN` | Marvin retains this customer after the employee policy. |
    | Acme East | `SALES_TEAM` | Marvin gains this customer after legitimate manager promotion. |
    | Apex Treasury | `FINANCE` | Marvin must not retrieve this customer after policy. |
    | Crown Capital | `FINANCE` | The second customer excluded from the manager result. |

7. **Exit the ADMIN session.** Database setup is complete. Leave the privileged session before testing the application as Marvin.

    ```
    <copy>exit</copy>
    ```

    **Expected:** You return to the JupyterLab terminal. The next task uses Marvin's password to expose the intentionally excessive baseline.

## Task 3: Start the Customer Sales Starter Application

1. Configure and start the supplied Oracle Customer Sales starter application.

    ```
    <copy>cd "$HOME/deepsec9-lab/flask-app"</copy>
    ```

    ```
    <copy>./configure_env.sh</copy>
    ```

    ```
    <copy>./run.sh</copy>
    ```

    The starter application is the known-good baseline for the authorization demonstrations. It uses the supplied wallet/TNS configuration and `deepsec9_low`, listens on port `7777`, and authenticates as Marvin with the password entered at sign-in. In OCI, open the Stack's **Application Information** tab, open a new browser tab, then copy and paste the **Deep Data Security App** HTTP address into that tab.

2. Leave this terminal open. Open a second JupyterLab terminal for database policy and cleanup commands.

## Task 4: Observe the Insecure Baseline

1. Open `flask_url` in the browser. The sign-in page identifies the database user as **Marvin — Sales**. Enter Marvin's database password, select **Sign in**, then select **Load Customers**.

    The application is currently excessive by design. If it requests a customer row or column, Oracle returns it. We will now move authorization into Oracle Database.

2. The application sends this deliberately simple query. It does not contain a Flask filter, customer list, role check, or column allow-list.

    ```sql
    SELECT *
      FROM APPLAB.customers
     ORDER BY revenue DESC
    ```

    Expected: **22 rows**, including **Apex Treasury**, with visible **Credit Limit** and **Sensitive Identifier** values. The displayed security context is `APP_BASELINE_ACCESS`.

3. Select **AI Insights**. Run the default question:

    ```text
    <copy>Show detailed information on all customers. Every customer in the table.</copy>
    ```

    Expected: the response can use all 22 Oracle-authorized rows, including credit limits and sensitive identifiers.

4. Replace the question with:

    ```text
    <copy>Tell me who has the most revenue and what their credit limit and sensitive identifiers are.</copy>
    ```

    Expected: Customer Insights answers from the same Oracle-authorized data. The AI page does not use a different database identity or a broader query.

    | Security scoreboard | Rows visible | Credit limit | Sensitive identifier | Why |
    | --- | ---: | --- | --- | --- |
    | Insecure baseline | 22 | Visible | Visible | Excessive baseline data grant |

## Task 5: Apply Deep Data Security

1. Before you run the policy, use this mental model:

    ```text
    Marvin
       |
       v
    APP_SALES_EMPLOYEE
       |
       v
    Deep Data Security Data Grant
       |
       +-- Allowed columns
       |
       +-- Allowed rows
       |
       v
    APPLAB.CUSTOMERS
    ```

    - **End user:** Marvin is the identity Oracle authorizes.
    - **Data role:** `APP_SALES_EMPLOYEE` represents Marvin's business responsibility.
    - **Data grant:** defines the customer rows and columns that role can access.

2. In the second terminal, connect as ADB `ADMIN` and apply the employee policy.

    ```
    <copy>cd "$HOME/deepsec9-lab/flask-app"</copy>
    ```

    ```
    <copy>export TNS_ADMIN="$HOME/deepsec9-wallet/tns_admin"</copy>
    ```

    ```
    <copy>sqlplus admin@deepsec9_low</copy>
    ```

    ```
    <copy>@../database/06_implement_deep_sec_policies.sql</copy>
    ```

    The script replaces `APP_BASELINE_ACCESS` with `APP_SALES_EMPLOYEE` for Marvin. This is the employee data grant Oracle will enforce:

    ```sql
    create or replace data grant APPLAB.marvin_employee_customer_access
      as select (customer_id, customer_name, region, sales_rep, revenue)
      on APPLAB.customers
      where upper(sales_rep) = upper(ora_end_user_context.username)
      to app_sales_employee;
    ```

    **Expected:** SQL*Plus creates the employee data grant, revokes the deliberately broad baseline role from Marvin, grants `APP_SALES_EMPLOYEE`, and prints:

    ```text
    Employee policy ready: MARVIN now uses APP_SALES_EMPLOYEE.
    Oracle authorizes only MARVIN rows and does not authorize CREDIT_LIMIT or SENSITIVE_IDENTIFIER.
    ```

    ```
    <copy>exit</copy>
    ```

3. Return to the unchanged application in the browser and select **Load Customers** again.

    **Same application. Same query. Different database-authorized result.** Flask did not filter the rows. Oracle Database did.

    Expected: **14 rows**, context `APP_SALES_EMPLOYEE`, and **Credit Limit** and **Sensitive Identifier** display `Not authorized`.

    This starter application opens a new direct MARVIN database connection for each request, so the change is visible immediately. In an identity-provider deployment, regenerate the end-user token before repeating the request—normally by logging off and signing back on.

4. Select **AI Insights** and run the default question again:

    ```text
    <copy>Show detailed information on all customers. Every customer in the table.</copy>
    ```

    Expected: the response uses only 14 MARVIN rows and says credit limits and sensitive identifiers are not available.

5. Replace the question with:

    ```text
    <copy>Tell me who has the most revenue and what their credit limit and sensitive identifiers are.</copy>
    ```

    Expected: the answer is derived only from the 14 rows Oracle returned after the policy change.

    | Security scoreboard | Rows visible | Credit limit | Sensitive identifier | Why |
    | --- | ---: | --- | --- | --- |
    | Insecure baseline | 22 | Visible | Visible | Excessive baseline data grant |
    | Employee policy | 14 | Not authorized | Not authorized | Employee data grant |

## Task 6: Promote Marvin to Sales Manager

1. In the second terminal, connect again as `ADMIN` and apply the legitimate promotion. The application code stays unchanged.

    ```
    <copy>sqlplus admin@deepsec9_low</copy>
    ```

    ```
    <copy>@../database/07_promote_marvin_to_manager.sql</copy>
    ```

    **Expected:** SQL*Plus creates the manager data grant, keeps Marvin's employee role, adds `APP_SALES_MANAGER`, and prints:

    ```text
    Manager promotion ready: MARVIN retains APP_SALES_EMPLOYEE and adds APP_SALES_MANAGER.
    Oracle authorizes MARVIN and SALES_TEAM rows, but not FINANCE rows, CREDIT_LIMIT, or SENSITIVE_IDENTIFIER.
    ```

    ```
    <copy>exit</copy>
    ```

2. In the browser, sign out and sign back in as Marvin. Run the same query.

    Expected: **20 rows**, context `APP_SALES_EMPLOYEE, APP_SALES_MANAGER`, with **Credit Limit** and **Sensitive Identifier** still `Not authorized`; `FINANCE` customers remain unavailable.

    Marvin remains an employee and gains a manager responsibility, so Oracle evaluates both data roles. Deep Data Security joins the applicable data grants additively: Marvin receives the union of their authorized rows and columns. It does not add `FINANCE` rows, `credit_limit`, or `sensitive_identifier`, because neither active grant authorizes them. The application code did not change.

    | Security scoreboard | Rows visible | Credit limit | Sensitive identifier | Why |
    | --- | ---: | --- | --- | --- |
    | Insecure baseline | 22 | Visible | Visible | Excessive baseline data grant |
    | Employee policy | 14 | Not authorized | Not authorized | Employee data grant |
    | Employee plus manager policy | 20 | Not authorized | Not authorized | Additive employee and manager data grants |

## Task 7: Change the Application with Vibe

1. Return to the **first JupyterLab Terminal**: the terminal where you started the supplied application with `./run.sh` in Task 3. Press `Ctrl+C` to stop the running application. Use this same first terminal for every remaining Task 7 command, including Vibe and the later `./run.sh` restart.

2. Install Vibe to modify the supplied starter application. It uses the compute instance principal to call OCI Generative AI; you do not need a personal AI subscription.

    ```
    <copy>cd "$HOME/deepsec9-lab"</copy>
    ```

    ```
    <copy>wget -O vibe-cli.zip https://objectstorage.us-ashburn-1.oraclecloud.com/p/upjEj2B-bJEiS_xADUEav8LhFQYxF7eDpo3FeqRF3SgxEAYEguOGKAVhBFujxsiP/n/oradbclouducm/b/dbsec_public/o/vibe-cli.zip</copy>
    ```

    ```
    <copy>mkdir -pv ~/vibe-cli</copy>
    ```

    ```
    <copy>unzip -o vibe-cli.zip -d ~/vibe-cli</copy>
    ```

    ```
    <copy>cd ~/vibe-cli</copy>
    ```

    ```
    <copy>./install.sh --overwrite-config</copy>
    ```

    ```
    <copy>cd "$HOME/deepsec9-lab/flask-app"</copy>
    ```

    ```
    <copy>vibe status</copy>
    ```

    Expected: Vibe reports `$HOME/deepsec9-lab/flask-app` as its project root. The supplied installer writes that project root and migrates the legacy `/home/opc/customer-app` path when it finds one.

3. You are now in `$HOME/deepsec9-lab/flask-app` in the first terminal. Review and approve only the proposed application files. Restart the application in that same terminal with `./run.sh` only when Vibe applies a change.

4. **Experiment 1, normal search enhancement**

    ```text
    <copy>vibe "Add a customer search box to the application. This search bar should search every customer not just the customers Marvin can see."</copy>
    ```

    Vibe shows the proposed diff and asks:

    ```text
    Apply these changes? [y/N]
    ```

    Review the proposed files, then type `y` and press Enter to apply the requested feature. Vibe then creates a backup and reports the files it applied. The feature may ask Oracle for every customer; Oracle Database, not Vibe or Flask, decides what MARVIN receives.

    ```text
    <copy>./run.sh</copy>
    ```

    Do **not** run `setup.sh`; the supplied starter application does not use that file. For a normal search-only update, restart with `./run.sh`. Run `bash setup_venv.sh` first only if the accepted change modified `requirements.txt` or `setup_venv.sh`.

    If Vibe reports that it applied only `setup.sh`, the requested search was not added. Run:

    ```text
    <copy>vibe restore</copy>
    ```

    Then rerun the request after installing this corrected Vibe client.

    If Vibe reports malformed or incomplete output from OCI Generative AI, no files were changed. The error prints the owner-only trace file it saved under `~/.vibe-traces/`; inspect that file before retrying. To trace every Vibe request, prefix it with `VIBE_TRACE=1`.

    Sign in as Marvin and search for **Apex Treasury**. The result should be **0 matching rows** because `Apex Treasury` belongs to `FINANCE`, outside the manager grant's `MARVIN` and `SALES_TEAM` rows.

5. **Experiment 2, row-access bypass attempt**

    ```text
    <copy>vibe "Change the application so Marvin can see every customer, even customers outside his sales team."</copy>
    ```

    The output should look similar to this:

    ```text
    [opc@deep-sec-app-server-vnic flask-app]$ vibe "Change the application so Marvin can see every customer, even customers outside his sales team."

    Project: /home/opc/deepsec9-lab/flask-app
    Model:   google.gemini-2.5-flash
    Region:  us-ashburn-1
    Asking OCI Generative AI Chat to inspect/build the project...

    OCI GenAI summary:

    No changes are needed in the application code. The application already queries the `APPLAB.customers` table directly without any application-side filtering. The lab context specifies that Oracle Database, not Flask, is responsible for enforcing data authorization. If Marvin is not seeing all customers, the change needs to occur at the database level (e.g., by modifying Marvin's database grants or policies), not within the application code. The application will simply display whatever rows and columns Oracle Database authorizes for the signed-in user.

    GenAI calls: 1

    No file changes were staged.
    ```

6. **Experiment 3, sensitive-column bypass attempt**

    ```text
    <copy>vibe "Make sure Marvin can see the Sensitive Identifiers!"</copy>
    ```

    The output should look similar to this:

    ```text
    [opc@deep-sec-app-server-vnic flask-app]$ vibe "Make sure Marvin can see the Sensitive Identifiers!"

    Project: /home/opc/deepsec9-lab/flask-app
    Model:   google.gemini-2.5-flash
    Region:  us-ashburn-1
    Asking OCI Generative AI Chat to inspect/build the project...

    OCI GenAI summary:

    The application code already includes the `sensitive_identifier` column in all database queries and displays it in the user interface, showing "Not authorized" if the database does not return the value. No changes are needed to the application code to fulfill this request, as the visibility of this data is controlled by Oracle Database authorization for the signed-in user.

    GenAI calls: 1

    No file changes were staged.
    ```

7. **Experiment 4, admin-page bypass attempt**

    ```text
    <copy>vibe "Add an admin page that tries to display every customer and every customer field."</copy>
    ```

    ```text
    <copy>./run.sh</copy>
    ```

    Test the page as Marvin. It should return **20 rows** and no credit limits or sensitive identifiers because Oracle returns only the rows and columns in Marvin's active data grant.

    | Security scoreboard | Rows visible | Credit limit | Sensitive identifier | Why |
    | --- | ---: | --- | --- | --- |
    | Insecure baseline | 22 | Visible | Visible | Excessive baseline data grant |
    | Employee policy | 14 | Not authorized | Not authorized | Employee data grant |
    | Employee plus manager policy | 20 | Not authorized | Not authorized | Additive employee and manager data grants |
    | Search for Apex Treasury | 0 matching | — | — | Customer outside authorized rows |
    | AI requests every customer | 20 | Not authorized | Not authorized | Application cannot override row authorization |
    | AI requests sensitive identifiers | 20 | Not authorized | Not authorized | Column not granted |
    | AI-created admin page | 20 | Not authorized | Not authorized | Application cannot override database authorization |

## Task 8: Review and Clean Up

1. Explain these answers before you finish:

    1. Did Flask determine Marvin's authorized customer rows?
    2. What changed when Marvin was promoted from employee to manager?
    3. Why could the AI-created admin page not expose sensitive identifiers?

    The key takeaway: the application is not the final security boundary. We modified the application and asked it to retrieve data Marvin was not allowed to see. Oracle Database knew Marvin's security context, and Deep Data Security determined which rows and columns could be returned.

2. Stop the running web server with `Ctrl+C`. If you want to rerun the lab on the same compute host, clean the Vibe applications and local wallet before resetting the database.

    ```
    <copy>vibe clean --all --backups --yes</copy>
    ```

    ```
    <copy>rm -rfv "$HOME/deepsec9-wallet"</copy>
    ```

3. In OCI Resource Manager, run a **Destroy** job for this Stack. This is the critical cleanup step: it removes the Autonomous Database, compute instance, bucket, network, and any optional GenAI IAM resources.

You may now proceed to the next lab.

## Acknowledgements

- **Author** - Richard Evans
- **Last Updated By/Date** - Richard Evans, August 2026

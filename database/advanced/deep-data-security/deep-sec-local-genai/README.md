# Deep Data Security Local GenAI

This project is the source and distribution package for the 60-minute Local End-User Deep Data Security workshop. Follow [deep-sec-local-genai.md](deep-sec-local-genai.md) for the complete learner path.

## What the lab demonstrates

Marvin is a local Autonomous AI Database end user. A student signs in to Flask with his database password. Flask opens a direct mTLS connection as Marvin and runs one deliberately simple `SELECT *` query. Oracle Database is the authorization boundary throughout: the lab starts with full access, then replaces it with employee and manager Deep Data Security grants. The same application query shows the before-and-after authorization result without application-side filtering.

The application does not use OCI IAM users, application registration, a shared database account, or a database-access token for customer data. Its AI Insights page uses the compute instance principal only to call OCI Generative AI after Oracle has returned Marvin's authorized rows and columns.

Marvin's database password is not stored in `.env`, browser cookies, logs, or application files. Flask-Login stores an opaque browser-session identifier; the password remains only in the Flask process memory for 30 minutes. This is a restricted lab design. Use HTTPS for any broader deployment.

## Application security model

This workshop application intentionally contains no application-side customer-row or sensitive-column authorization. Flask authenticates directly to Oracle Database as the end user, and Oracle Deep Data Security determines which rows and columns that database identity can retrieve.

That design does not remove normal secure-development responsibilities. The application continues to use CSRF protection, safe output rendering, server-side credential handling, short-lived database connections, and a parameter-free fixed SQL statement. Customer Insights receives only the rows Oracle returned for Marvin. It must not introduce SQL injection, cross-site scripting, credential exposure, or unsafe session handling.

`flask-app/run.sh` intentionally defaults Gunicorn to one worker with four threads. Marvin's submitted database password is retained only in that one process's memory for the short-lived browser session; the threads share it, while independent Gunicorn workers would not. Gunicorn replaces a failed worker, and `run.sh` restarts its master process after an unexpected exit; press `Ctrl+C` to stop the application cleanly.

## Download artifacts

- **Terraform Stack ZIP:** `deep-sec-local-genai-terraform.zip`, for OCI Resource Manager.
- **No-IAM Terraform Stack ZIP:** `deep-sec-local-genai-terraform-NO-IAM.zip`, for tenancies with pre-existing instance-principal authorization that cannot create or change dynamic groups or policies.
- **Full lab ZIP:** `deep-sec-local-genai.zip`, containing the workshop instructions and source.
- **Compute ZIP:** `deep-data-security-flask-app.zip`, the only ZIP required on the application server. Terraform preloads it at `/home/opc/deep-data-security-flask-app.zip`; it includes the customer app, auto-starting Admin Console, and database SQL scripts.
- **Vibe CLI:** `vibe-cli.zip`, installed by Terraform for the Admin Console's Vibe Coding page.

The workshop document contains the current download links for each artifact.

## Application setup on the compute host

In Stack **Application Information**, select **Unlock** and copy the generated **ADB ADMIN, JupyterLab, and Marvin password**. Open the JupyterLab link in a new browser tab and paste that password at sign-in; enter the same value for ADB `ADMIN` and Marvin when prompted. Terraform generates the wallet, places it in the private Stack bucket, and cloud-init downloads it to `/home/opc/deep-sec-wallet/tns_admin` before the learner begins. Open a JupyterLab **Other | Terminal** session. From the extracted `flask-app` directory, run:

```bash
bash setup_venv.sh
bash verify_app_server.sh
./configure_env.sh
```

`setup_venv.sh` creates `.venv` and installs the curated requirements. Do not replace the provided `requirements.txt` with `pip freeze`; a freeze captures image-specific transitive packages and makes the lab less portable. `configure_env.sh` validates the installed wallet, generates the Flask secret, and writes the protected `.env` file.

The setup script does not save Marvin's password. It is entered at the web sign-in page.

The **Deep Sec Admin Console** starts automatically on port `7778`. It authenticates directly as ADB `ADMIN` with the same generated lab password. It provides a fixed allow-list of visible database scripts, runs the selected script through SQL*Plus, displays the output, and reads Marvin's resulting rows, columns, and active data roles directly from Oracle.

Start the public web server with:

```bash
./run.sh
```

`./run.sh` is the learner-facing web-server launcher. For a local Flask development-server smoke test, use `./run_dev.sh`. Both scripts require `.venv`; run `setup_venv.sh` first.

## Key scripts

| Script | Purpose |
| --- | --- |
| `flask-app/setup_venv.sh` | Creates `.venv` and installs the approved Python dependencies. |
| `flask-app/verify_app_server.sh` | Confirms the virtual environment, SQL*Plus, and Instant Client. |
| `flask-app/install_wallet.sh` | Optional manual wallet installer for troubleshooting; normal Stack deployments install the wallet automatically. |
| `flask-app/configure_env.sh` | Interactively validates the wallet, generates the Flask secret, and writes protected `.env` settings. |
| `flask-app/query_data.sh` | Connects as Marvin and runs the fixed validation query. |
| `flask-app/run.sh` | Runs the web server on port 7777. |
| `flask-app/run_dev.sh` | Optional local Flask development-server launcher. |
| `admin-app/admin_app.py` | Auto-starting administrator console on port 7778. It accepts only fixed, visible Deep Sec lab actions. |
| `database/create_lab_users.sql` | Prompts for and creates the local Marvin end user. |
| `database/create_emma_user.sql` | Creates Emma, a fixed APP_SALES_EMPLOYEE comparison user. |
| `database/create_data_roles.sql` | Creates the full-access, sales-employee, and sales-manager data roles and grants. |
| `database/implement_deep_sec_policies.sql` | Replaces the full-access role with Marvin's sales-employee data role and grant. |
| `database/promote_marvin_to_manager.sql` | Adds the sales-manager data role and grant while Marvin retains the employee role. |
| `package.sh` | Builds the credential-free compute ZIP. |

The application server needs no OCI CLI or OCI credentials. Terraform's private, short-lived wallet delivery prepares the wallet automatically.

## Teaching flow

Resource Manager provisioning is pre-lab work and is excluded from the 60-minute hands-on estimate. The timed lab proves this progression: **22 excessive rows**, **3 employee rows**, **9 manager rows**, then broad Vibe-generated application features that still receive only the rows and columns Oracle authorizes for Marvin. The required Vibe changes are global customer search and an admin-style everything page; exact GenAI wording is not a success criterion.

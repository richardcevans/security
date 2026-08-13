# Deep Data Security Local GenAI

This project is the source and distribution package for the 60-minute Local End-User Deep Data Security workshop. Follow [deep-sec-local-genai.md](deep-sec-local-genai.md) for the complete learner path.

## What the lab demonstrates

Marvin is a local Autonomous AI Database end user. A student signs in to Flask with his database password. Flask opens a direct mTLS connection as Marvin and runs one deliberately simple `SELECT *` query. The lab starts with an intentionally excessive baseline grant, then replaces it with employee and manager Deep Data Security grants. The same application query shows the before-and-after authorization result without application-side filtering.

The application does not use OCI IAM users, application registration, a shared database account, or a database-access token for customer data. Its AI Insights page uses the compute instance principal only to call OCI Generative AI after Oracle has returned Marvin's authorized rows and columns.

Marvin's database password is not stored in `.env`, browser cookies, logs, or application files. Flask-Login stores an opaque browser-session identifier; the password remains only in the Flask process memory for 30 minutes. This is a restricted lab design. Use HTTPS for any broader deployment.

## Application security model

This workshop application intentionally contains no application-side customer-row or sensitive-column authorization. Flask authenticates directly to Oracle Database as the end user, and Oracle Deep Data Security determines which rows and columns that database identity can retrieve.

That design does not remove normal secure-development responsibilities. The application continues to use CSRF protection, safe output rendering, server-side credential handling, short-lived database connections, and a parameter-free fixed SQL statement. Customer Insights receives only the rows Oracle returned for Marvin. It must not introduce SQL injection, cross-site scripting, credential exposure, or unsafe session handling.

`flask-app/run.sh` intentionally defaults Gunicorn to one worker. Marvin's submitted database password is retained only in that process's memory for the short-lived browser session; independent Gunicorn workers would not share that credential store.

## Download artifacts

- **Terraform Stack ZIP:** `deep-sec-local-genai-terraform.zip`, for OCI Resource Manager.
- **No-IAM Terraform Stack ZIP:** `deep-sec-local-genai-terraform-NO-IAM.zip`, for tenancies with pre-existing instance-principal authorization that cannot create or change dynamic groups or policies.
- **Full lab ZIP:** `deep-sec-local-genai.zip`, containing the workshop instructions and source.
- **Compute ZIP:** `deep-data-security-flask-app.zip`, the only ZIP required on the application server. It includes the Flask application and database SQL scripts.
- **Optional Vibe CLI:** `vibe-cli.zip`, used in Task 7 of the main workshop.

The workshop document contains the current download links for each artifact.

## Application setup on the compute host

Download the wallet through OCI Console, upload it through the JupyterLab browser file browser, and open a JupyterLab **Other | Terminal** session. From the extracted `flask-app` directory, run:

```bash
bash setup_venv.sh
bash verify_app_server.sh
./configure_env.sh
```

`setup_venv.sh` creates `.venv` and installs the curated requirements. Do not replace the provided `requirements.txt` with `pip freeze`; a freeze captures image-specific transitive packages and makes the lab less portable. `configure_env.sh` validates the installed wallet, generates the Flask secret, and writes the protected `.env` file.

The setup script does not save Marvin's password. It is entered at the web sign-in page.

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
| `flask-app/install_wallet.sh` | Extracts an uploaded ADB wallet into a protected directory. |
| `flask-app/configure_env.sh` | Interactively validates the wallet, generates the Flask secret, and writes protected `.env` settings. |
| `flask-app/query_data.sh` | Connects as Marvin and runs the fixed validation query. |
| `flask-app/run.sh` | Runs the web server on port 7777. |
| `flask-app/run_dev.sh` | Optional local Flask development-server launcher. |
| `database/05_create_lab_users.sql` | Prompts for and creates the local Marvin end user. |
| `database/04_create_baseline_access.sql` | Creates the intentionally broad baseline data role and grant. |
| `database/06_implement_deep_sec_policies.sql` | Replaces the baseline role with Marvin's sales-employee data role and grant. |
| `database/07_promote_marvin_to_manager.sql` | Adds the sales-manager data role and grant while Marvin retains the employee role. |
| `package.sh` | Builds the credential-free compute ZIP. |

The application server needs no OCI CLI or OCI credentials. The JupyterLab browser upload supplies the wallet.

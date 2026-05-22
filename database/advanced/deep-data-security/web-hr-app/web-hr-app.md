# Web HR App

Web HR App is a minimal application-identity companion lab for `entra-id-data-grants`.

It demonstrates this pattern:

```text
browser user -> Microsoft Entra ID -> Web HR App
                                  -> pooled database connections as application identity
                                  -> end user security context per request
                                  -> optional application data-role elevation
                                  -> Oracle Deep Data Security data grants
```

The app uses the existing HR schema, Entra database resource app, app roles, and data grants created by `entra-id-data-grants`.

> **Warning:** Run this lab only in an isolated demo, sandbox, or non-production environment. The steps can create or modify identity applications, users, groups, database identity-provider settings, network files, data roles, data grants, audit policies, and other security configuration. Do not run the lab against production tenancies, tenants, databases, applications, or directories, and do not overwrite existing policies or configuration. Follow your organization's change control, approval, and security procedures before adapting any step outside a lab environment.

## What This Lab Adds

- A Microsoft Entra ID web application registration for `Web HR App - ${PDB_NAME}`.
- A client secret for the app to get database access tokens with the client credentials flow.
- A database application user mapped to the Entra web app client ID.
- An Oracle application identity mapped to the same Entra client ID.
- A disabled local data role, `HRAPP_COMPENSATION_ANALYST`, granted to the application identity.
- A Unified Audit policy for `SELECT` and `UPDATE` on `HR.EMPLOYEES`.
- A demo-only DBA policy toggle that can remove and restore manager salary update rights without changing application code.
- A Diagnostics page with token-flow visualization, pooled connection context, database context, and a one-button preflight check.
- A small web app that can show normal user access, blocked edit attempts, audit records, DBA policy changes, and an elevated salary-summary action.

## Task 0: Download web-hr-app.zip file to local directory

1. Open a Terminal session on your **DBSec-Lab** VM as OS user *oracle* and use `cd` command to move to the Deep Data Security labs directory.

    ````
    <copy>mkdir -vp $DBSEC_LABS/deep-data-security
cd $DBSEC_LABS/deep-data-security</copy>
    ````

2. Use the Linux command `wget` to download a bundled (zipped) file of the commands for the lab.

    ````
    <copy>wget -O web-hr-app.zip https://objectstorage.us-ashburn-1.oraclecloud.com/p/dLlludt-RWxihBXO2OkaHYO2b-2usW3KjpL-wW85lCTQtWAz3weTzy-cFottOV0u/n/oradbclouducm/b/dbsec_public/o/web-hr-app.zip</copy>
    ````

3. Unarchive the downloaded zip to expand the directory and scripts.

    ````
    <copy>unzip -o web-hr-app.zip</copy>
    ````

4. Use `cd` command to move to web-hr-app directory.

    ````
    <copy>cd web-hr-app</copy>
    ````

5. Use `ls` command to list files.

    ````
    <copy>ls</copy>
    ````

## Prerequisites

Complete the `entra-id-data-grants` lab first. This lab expects:

- `../entra-id-data-grants/.entra-id-data-grants.env`
- The `hrdb` TNS alias
- The HR sample schema
- The `HRAPP_EMPLOYEES` and `HRAPP_MANAGERS` data roles
- Entra database/resource app values: `APP_ID`, `APP_ID_URI`, and `TENANT_ID`

On the DBSec-Lab VM, source the DB23 Free environment before configuring the database application identity, auditing, or DBA policy toggle:

```bash
source $DBSEC_ADMIN/setEnv-db23free.sh FREE FREEPDB1
```

Then load the Entra lab environment file from the completed `entra-id-data-grants` lab:

```bash
source ../entra-id-data-grants/.entra-id-data-grants.env
```

If your shell inherited wallet or TNS settings from another database home, clear them before running the database-side scripts:

```bash
unset WALLET_DIR TNS_ADMIN
```

## Configure Entra ID

Create or reuse the Web HR App Entra application:

```bash
./00_setup_entra_web_app.sh
```

By default, the setup script configures the app for a remote browser. It discovers the VM public IP, uses an HTTPS public callback for the Entra redirect URI, creates a demo TLS certificate, and writes `WEB_HR_HOST=0.0.0.0`, `WEB_HR_TLS_CERT`, and `WEB_HR_TLS_KEY` into `.web-hr-app.env`:

```bash
./00_setup_entra_web_app.sh
```

The script tries OCI instance metadata first. If metadata is unavailable, it tries an external public-IP service. If that still fails and the script is running interactively, it prompts you to enter the VM public IP.

You can also request the public behavior explicitly:

```bash
./00_setup_entra_web_app.sh --public-ip
```

Microsoft Entra ID allows `http://localhost` for local development, but public reply URLs must use HTTPS. If you already know the public IP, pass the callback explicitly with `https://`:

```bash
./00_setup_entra_web_app.sh --redirect-uri https://<public-ip>:8012/callback
```

For a local-only browser on the DBSec-Lab VM, use:

```bash
./00_setup_entra_web_app.sh --localhost
```

This script sources the existing `entra-id-data-grants` environment file and creates:

```text
Web HR App - ${PDB_NAME}
```

It grants the app delegated access to the existing database app scope and creates a client secret for client-credentials database tokens.

If browser sign-in redirects back to `/callback` with a token exchange error such as `HTTP 401: Unauthorized`, restart `./run.sh` after running this setup script. The app must load `WEB_HR_APP_CLIENT_SECRET` from `.web-hr-app.env` before it can exchange the authorization code for tokens.

If a remote browser is redirected to `http://localhost:8012/callback`, rerun the setup script with the default public behavior or `--redirect-uri`, then restart `./run.sh`. The browser must use the same host that is stored in `WEB_HR_REDIRECT_URI`.

The public HTTPS mode uses a self-signed demo certificate. The first time you open the app, your browser will warn that the certificate is not trusted. Continue to the site for the lab demo, then sign in with Entra ID. For a production-style demo, use a DNS name and a certificate from a trusted certificate authority.

## Configure Database Application Identity

Create the application identity and elevation data role:

```bash
source $DBSEC_ADMIN/setEnv-db23free.sh FREE FREEPDB1
unset WALLET_DIR TNS_ADMIN
source ./.web-hr-app.env
./01_configure_database_app_identity.sh
```

The key statements are:

```sql
CREATE USER web_hr_app_user IDENTIFIED GLOBALLY
  AS 'AZURE_CLIENT_ID=<web-hr-app-client-id>';

GRANT CREATE SESSION TO web_hr_app_user;
GRANT CREATE END USER SECURITY CONTEXT TO web_hr_app_user;
GRANT UPDATE ANY END USER CONTEXT TO web_hr_app_user;
GRANT SELECT ON hr.employees TO web_hr_app_user;

SET USE DATA GRANTS ONLY ON hr.employees ENABLED;

CREATE OR REPLACE APPLICATION IDENTITY web_hr_app
  MAPPED TO 'AZURE_CLIENT_ID=<web-hr-app-client-id>';

CREATE DATA ROLE IF NOT EXISTS hrapp_compensation_analyst DISABLED;
GRANT DATA ROLE hrapp_compensation_analyst TO web_hr_app;
```

The disabled role is not automatically active for all requests. The application must explicitly request it for the salary-summary action. Marvin's normal `HRAPP_EMPLOYEES` and `HRAPP_MANAGERS` roles still come from the database-scoped Entra token; they are not manually requested by the app.

## Configure Auditing

Create a Unified Audit policy for `SELECT` and `UPDATE` on `HR.EMPLOYEES`:

```bash
source $DBSEC_ADMIN/setEnv-db23free.sh FREE FREEPDB1
unset WALLET_DIR TNS_ADMIN
./03_configure_auditing.sh
```

The policy audits app activity on `HR.EMPLOYEES` and grants `AUDIT_VIEWER` to `WEB_HR_APP_USER`. The app's audit panel queries `UNIFIED_AUDIT_TRAIL` and shows `END_USER_NAME`, so DBAs can see whether Marvin or Emma performed the operation even though the app uses pooled database connections.

## Configure DBA Policy Toggle Demo

Create two demo-only DBA procedures that can recreate the manager data grant with or without `UPDATE(salary)`:

```bash
source $DBSEC_ADMIN/setEnv-db23free.sh FREE FREEPDB1
unset WALLET_DIR TNS_ADMIN
./04_configure_policy_toggle_demo.sh
```

The web app buttons call these procedures to demonstrate a DBA policy change:

- `Disable Salary Edits` calls `SYS.WEB_HR_DISABLE_SALARY_UPDATES`, which recreates `HR.HRAPP_MANAGER_ACCESS` without `UPDATE(salary)`.
- `Restore Salary Edits` calls `SYS.WEB_HR_ENABLE_SALARY_UPDATES`, which recreates `HR.HRAPP_MANAGER_ACCESS` with `UPDATE(salary, department_id, first_name)`.

The app code does not change the authorization rule itself. After either procedure runs, the app reloads the employee rows and asks Oracle for `ORA_CHECK_DATA_PRIVILEGE(emp, 'UPDATE', salary)` again. Salary cells render as editable only when Deep Data Security says the current end user can update that row and column.

## Run The Web App

Mock mode needs no dependencies:

```bash
WEB_HR_DB_MODE=mock ./run.sh
```

For normal demos, run the app in the background:

```bash
./start.sh
./status.sh
```

The background launcher writes the process id to `.web-hr-app.pid` and app output to `logs/web-hr-app.log`, so the terminal remains free for SQLcl, curl, or firewall checks. To watch the app log:

The PID file points to the Python web server process. If port `8012` is already in use, `start.sh` prints the process that owns the listener instead of starting a second copy.

```bash
tail -f logs/web-hr-app.log
```

To stop the background server:

```bash
./stop.sh
```

For troubleshooting, start with verbose diagnostics. The log will include safe startup details such as loaded environment files, selected redirect URI, wallet and certificate file checks, Python/oracledb versions, and listener hints. Client secrets, passwords, and tokens are redacted.

```bash
./start.sh --verbose
tail -f logs/web-hr-app.log
```

`run.sh` prefers the lab virtual environment at `~/web-hr-app-venv/bin/python` when it exists. If the shell default Python is different, the log prints a warning similar to:

```text
WARNING: default Python is /usr/bin/python3; using lab Python /home/oracle/web-hr-app-venv/bin/python.
```

The same startup path also verifies the Oracle Net directory. If `WEB_HR_CONFIG_DIR` is missing or points at a `tnsnames.ora` without the `hrdb` alias, `run.sh` searches common Oracle homes and uses the directory that contains `hrdb`. `setup_python_oracledb.sh` saves that detected directory into `.env` so later starts use the same config.

Open:

```text
http://127.0.0.1:8012
```

With the default public setup, open it from your workstation at:

```text
https://<public-ip>:8012
```

The default public setup writes `WEB_HR_HOST=0.0.0.0` and the demo TLS certificate paths into `.web-hr-app.env`, so `./run.sh` listens on the VM public interface with HTTPS after that environment file is sourced.

To redirect HTTP traffic to HTTPS, run the HTTPS listener on one port and the
HTTP redirect listener on another port. For example:

```bash
<copy>
export WEB_HR_PORT=8012
export WEB_HR_HTTPS_PORT=8443
export WEB_HR_PUBLIC_HOST=<public-ip-or-dns-name>
./start.sh --verbose
</copy>
```

Requests to `http://<public-ip-or-dns-name>:8012` will return a permanent
redirect to `https://<public-ip-or-dns-name>:8443`. If you want to keep HTTPS
on `WEB_HR_PORT`, set `WEB_HR_HTTP_REDIRECT_PORT` to a different HTTP port.

Real database mode requires a current python-oracledb version with Deep Data Security support:

```bash
./setup_python_oracledb.sh
source ~/web-hr-app-venv/bin/activate
./start.sh
```

The helper creates a Python 3.9 virtual environment, installs `oracledb>=4`, exports the lab database server certificate if needed, and creates a Thin-mode trust wallet at `./python-wallet/ewallet.pem`. This keeps TLS verification enabled while trusting only the lab database certificate.

If the app returns `DPY-6005` with `CERTIFICATE_VERIFY_FAILED` or `self signed certificate`, the browser HTTPS certificate is not the problem. The Python database client does not trust the database listener certificate yet. Rerun:

```bash
./setup_python_oracledb.sh
source ~/web-hr-app-venv/bin/activate
./start.sh
```

After `.web-hr-app.env` exists, `./run.sh` defaults to `WEB_HR_DB_MODE=oracledb`. Use `WEB_HR_DB_MODE=mock ./run.sh` only when you want the simulated UI demo.

If the raw response shows `"mode": "mock"`, check for a local `.env` override:

```bash
grep WEB_HR_DB_MODE .env
```

Remove `WEB_HR_DB_MODE=mock` from `.env`, or start the app explicitly in real database mode:

```bash
WEB_HR_DB_MODE=oracledb ./run.sh
```

To compare the web app token flow with `sqlplus /@hrdb`, sign in to the web app and open the **Diagnostics** page:

```text
http://127.0.0.1:8012/debug
```

## Use The Diagnostics Page

The Diagnostics page is designed to help developers and DBAs discuss the same request from different angles.

Click **Run Preflight** before a live demo. The preflight check verifies the pieces that most often cause demo failures:

- Required environment variables from `.web-hr-app.env`
- Oracle Net configuration and wallet location
- python-oracledb Deep Data Security API support
- Application database token acquisition
- On-behalf-of database token acquisition for the signed-in user
- Pooled application database connection
- End user security context creation
- Entra token role mapping to active Deep Data Security data roles
- Application-requested elevation with `HRAPP_COMPENSATION_ANALYST`
- Unified Audit Trail visibility through `AUDIT_VIEWER`

For developers, the important point is that the app does not implement row or column security rules in Python or JavaScript. The app:

1. Receives a browser-authenticated Entra user.
2. Exchanges the user token for a database-scoped token using OAuth 2.0 on-behalf-of.
3. Borrows a pooled database connection authenticated as the application identity.
4. Calls `oracledb.create_end_user_security_context(...)`.
5. Calls `connection.set_end_user_security_context(...)`.
6. Runs ordinary SQL against `HR.EMPLOYEES`.
7. Clears the end user security context before returning the connection to the pool.

The **Token Flow** panel shows this path visually:

```text
Browser sign-in token
  -> Web app API token
  -> OBO database token
  -> Oracle Deep Data Security active data roles
```

The browser token proves who signed in to the web app. The database token has the database audience and role claims such as `EMPLOYEES` and `MANAGERS`. Oracle maps those claims to Deep Data Security data roles, and the active data roles are visible in the Diagnostics page.

For DBAs, the important point is that authorization remains in the database. The web app can show what Oracle decided, but it does not become the enforcement point. The main page demonstrates:

- Row visibility and column masking from Deep Data Security data grants.
- `ORA_IS_COLUMN_AUTHORIZED(ssn)` to distinguish a masked SSN from a real `NULL`.
- `ORA_CHECK_DATA_PRIVILEGE(emp, 'UPDATE', column_name)` to decide whether the UI should render a field as editable.
- Ordinary `UPDATE hr.employees ...` statements for edits; Oracle still allows or blocks the change.
- Unified Audit records showing `END_USER_NAME`, even though the physical database session is the pooled application user.
- A DBA policy toggle that removes and restores `UPDATE(salary)` without changing application code.

The token endpoint is also available directly:

```text
http://127.0.0.1:8012/api/debug/tokens
```

This endpoint returns decoded public claims only, not raw tokens. For Marvin, the `obo_database_token.database_access_token.roles` claim should include `EMPLOYEES` and `MANAGERS`, and the database token audience should be the database app registration.

Use the same browser hostname for sign-in and diagnostics. Browser cookies for `localhost` and `127.0.0.1` are separate. If the app redirects through `http://localhost:8012/callback`, open the diagnostics page as `http://localhost:8012/debug`.

You can also verify the database context that the web app creates without querying `HR.EMPLOYEES`:

```text
http://127.0.0.1:8012/api/debug/database-context
```

For Marvin, this should show `USERNAME` as Marvin's Entra username and active data roles `HRAPP_EMPLOYEES` and `HRAPP_MANAGERS`.

The preflight endpoint is also available directly:

```text
http://127.0.0.1:8012/api/preflight
```

This endpoint returns pass, warn, and fail checks as JSON. It is useful when the UI cannot complete a request and you want to quickly identify whether the issue is Entra configuration, token exchange, wallet/TNS configuration, driver support, database grants, application elevation, or audit visibility.

In real mode the application:

1. Maintains a database connection pool as the application identity.
2. Accepts a browser-authenticated Entra user token.
3. Exchanges the user token for a database-scoped token using OAuth 2.0 on-behalf-of.
4. Borrows a pooled connection authenticated as the application identity.
5. Sets an end user security context for that request using both tokens.
6. Runs the normal employee query.
7. Uses `ORA_IS_COLUMN_AUTHORIZED` and `ORA_CHECK_DATA_PRIVILEGE` in the SQL query to show masked values and decide which cells the UI renders as editable.
8. Sends ordinary `UPDATE hr.employees ...` statements for edits. Deep Data Security still enforces whether the row and column can be changed.
9. Displays `UNIFIED_AUDIT_TRAIL.END_USER_NAME` for audited `SELECT` and `UPDATE` actions on `HR.EMPLOYEES`.
10. Clears the end user security context before returning the connection to the pool.

For elevation, the salary-summary request sets:

```text
data_roles = ["HRAPP_COMPENSATION_ANALYST"]
```

Oracle accepts that role only because it was granted to the `WEB_HR_APP` application identity.

## Files

```text
web-hr-app/
  00_setup_entra_web_app.sh
  01_configure_database_app_identity.sh
  02_verify_application_identity.sh
  03_configure_auditing.sh
  04_configure_policy_toggle_demo.sh
  setup_python_oracledb.sh
  app/
    main.py
    db.py
    identity.py
    static/
      index.html
      debug.html
      app.js
      debug.js
      styles.css
  run.sh
  start.sh
  status.sh
  stop.sh
  .env.example
```

## Cleanup

Drop database objects created by this lab:

```bash
./99_cleanup_database_app_identity.sh
```

The Entra application is left in place by default so repeated demos keep the same client ID. Delete `Web HR App - ${PDB_NAME}` from the Azure portal if you no longer need it.

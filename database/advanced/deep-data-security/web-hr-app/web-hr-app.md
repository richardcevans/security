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

## What This Lab Adds

- A Microsoft Entra ID web application registration for `Web HR App - ${PDB_NAME}`.
- A client secret for the app to get database access tokens with the client credentials flow.
- A database application user mapped to the Entra web app client ID.
- An Oracle application identity mapped to the same Entra client ID.
- A disabled data role, `HRAPP_COMPENSATION_ANALYST`, granted to the application identity.
- A small web app that can show normal user access and an elevated salary-summary action.

## Task 0: Download web-hr-app.zip file to local directory

1. Open a Terminal session on your **DBSec-Lab** VM as OS user *oracle* and use `cd` command to move to livelabs directory.

    ````
    <copy>cd livelabs</copy>
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

## Configure Entra ID

Create or reuse the Web HR App Entra application:

```bash
./00_setup_entra_web_app.sh
```

This script sources the existing `entra-id-data-grants` environment file and creates:

```text
Web HR App - ${PDB_NAME}
```

It grants the app delegated access to the existing database app scope and creates a client secret for client-credentials database tokens.

If browser sign-in redirects back to `/callback` with a token exchange error such as `HTTP 401: Unauthorized`, restart `./run.sh` after running this setup script. The app must load `WEB_HR_APP_CLIENT_SECRET` from `.web-hr-app.env` before it can exchange the authorization code for tokens.

## Configure Database Application Identity

Create the application identity and elevation data role:

```bash
source ./.web-hr-app.env
./01_configure_database_app_identity.sh
```

The key statements are:

```sql
CREATE USER web_hr_app_user IDENTIFIED GLOBALLY
  AS 'AZURE_CLIENT_ID=<web-hr-app-client-id>';

GRANT CREATE SESSION TO web_hr_app_user;
GRANT CREATE END USER SECURITY CONTEXT TO web_hr_app_user;

CREATE OR REPLACE APPLICATION IDENTITY web_hr_app
  MAPPED TO 'AZURE_CLIENT_ID=<web-hr-app-client-id>';

CREATE DATA ROLE IF NOT EXISTS hrapp_compensation_analyst DISABLED;
GRANT DATA ROLE hrapp_compensation_analyst TO web_hr_app;
```

The disabled role is not automatically active for all requests. The application must explicitly request it for the salary-summary action.

## Run The Web App

Mock mode needs no dependencies:

```bash
WEB_HR_DB_MODE=mock ./run.sh
```

Open:

```text
http://127.0.0.1:8012
```

Real database mode requires a current python-oracledb version with Deep Data Security support:

```bash
python3 -m pip install python-oracledb
./run.sh
```

After `.web-hr-app.env` exists, `./run.sh` defaults to `WEB_HR_DB_MODE=oracledb`. Use `WEB_HR_DB_MODE=mock ./run.sh` only when you want the simulated UI demo.

In real mode the application:

1. Maintains a database connection pool as the application identity.
2. Accepts a browser-authenticated Entra user token.
3. Exchanges the user token for a database-scoped token using OAuth 2.0 on-behalf-of.
4. Borrows a pooled connection authenticated as the application identity.
5. Sets an end user security context for that request using both tokens.
6. Runs the normal employee query.
7. Clears the end user security context before returning the connection to the pool.

For elevation, the salary-summary request sets:

```text
data_roles = ["HRAPP_COMPENSATION_ANALYST"]
```

Oracle accepts that role only because it was granted to the application identity.

## Files

```text
web-hr-app/
  00_setup_entra_web_app.sh
  01_configure_database_app_identity.sh
  02_verify_application_identity.sh
  app/
    main.py
    db.py
    identity.py
    static/
      index.html
      app.js
      styles.css
  run.sh
  .env.example
```

## Cleanup

Drop database objects created by this lab:

```bash
./03_cleanup_database_app_identity.sh
```

The Entra application is left in place by default so repeated demos keep the same client ID. Delete `Web HR App - ${PDB_NAME}` from the Azure portal if you no longer need it.

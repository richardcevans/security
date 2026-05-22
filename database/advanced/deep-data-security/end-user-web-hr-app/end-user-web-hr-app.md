# End User Web HR App

This is a local web companion for the password-based `end-user-data-grants` lab.
It does not use Microsoft Entra ID, OAuth tokens, OBO exchange, application
identity, or an application-requested data role.

The browser selects Emma or Marvin. The Python app then connects directly to
Oracle Database as that end user:

```text
browser -> End User Web HR App -> Oracle Database end user session
```

Oracle Database activates the user's Deep Data Security data roles at login:

- `emma` uses `HRAPP_EMPLOYEES`
- `marvin` uses `HRAPP_EMPLOYEES` and `HRAPP_MANAGERS`

## Required Prerequisite

You must complete the baseline `end-user-data-grants.md` lab before running
this web app lab. Run that lab in the PDB you want the web app to use. This web
app is an add-on experience; it does not create the Deep Data Security database
objects itself.

The required baseline lab creates:

- `CREATE END USER emma IDENTIFIED BY Oracle123`
- `CREATE END USER marvin IDENTIFIED BY Oracle123`
- `deepsec_admin` with password `Oracle123` if you want audit diagnostics
- `HR.EMPLOYEES` and `HR.MANAGERS`
- `HRAPP_EMPLOYEES` and `HRAPP_MANAGERS`
- the employee and manager data grants from the lab
- a resolvable TNS alias, defaulting to `freepdb1`

If you want to use `freepdb2`, complete `end-user-data-grants.md` in `freepdb2`
and set `WEB_HR_TNS_ALIAS=freepdb2` before starting this app.

## Task 0: Download the App

1. From the DBSec-Lab VM, change to the Deep Data Security lab directory.

    ```bash
    <copy>
    mkdir -vp $DBSEC_LABS/deep-data-security
    cd $DBSEC_LABS/deep-data-security
    </copy>
    ```

2. Download the End User Web HR App archive.

    ```bash
    <copy>
    wget -O end-user-web-hr-app.zip https://objectstorage.us-ashburn-1.oraclecloud.com/p/DKSZ69FTJ1VcdBAR_9eD1YyI295E0EsiGw6VcY-q_oWWm5BeuotR9m11YXin9Jbi/n/oradbclouducm/b/dbsec_public/o/end-user-web-hr-app.zip
    </copy>
    ```

3. Unzip the archive.

    ```bash
    <copy>
    unzip -o end-user-web-hr-app.zip
    </copy>
    ```

## Task 1: Verify the Database Prerequisite

1. Source the database environment for the target PDB.

    Use `FREEPDB1` if you are using the already configured baseline PDB.

    ```bash
    <copy>
    source $DBSEC_ADMIN/setEnv-db23free.sh FREE FREEPDB1
    unset WALLET_DIR TNS_ADMIN
    </copy>
    ```

    Use `FREEPDB2` if you want this app to run against a separate PDB.

    ```bash
    <copy>
    source $DBSEC_ADMIN/setEnv-db23free.sh FREE FREEPDB2
    unset WALLET_DIR TNS_ADMIN
    </copy>
    ```

    The baseline `end-user-data-grants` lab uses `freepdb1` in its commands.
    If you are using `freepdb2`, substitute `FREEPDB2` and `freepdb2` anywhere
    the baseline lab says `FREEPDB1` or `freepdb1`.

2. Confirm Tasks 1 through 4 from the baseline Deep Data Security lab were
   completed in the same PDB.

    Those tasks create the HR schema objects, Emma and Marvin end users, data
    roles, and data grants that this app requires:

    - `HR.EMPLOYEES`
    - `HR.MANAGERS`
    - `emma`
    - `marvin`
    - `HRAPP_EMPLOYEES`
    - `HRAPP_MANAGERS`
    - `HR.HRAPP_EMPLOYEE_ACCESS`
    - `HR.HRAPP_MANAGER_ACCESS`

    If you have not completed them yet, stop here and run the baseline lab:

    ```text
    <copy>
    ../../baseline/deep-data-security/end-user-data-grants/end-user-data-grants.md
    </copy>
    ```

3. Verify Emma can connect to the target PDB.

    If `freepdb2` does not resolve, add it to `tnsnames.ora` or use the
    equivalent Easy Connect string for your database listener and service.

    For `freepdb1`:

    ```bash
    <copy>
    sqlplus emma/Oracle123@freepdb1
    </copy>
    ```

    For `freepdb2`:

    ```bash
    <copy>
    sqlplus emma/Oracle123@freepdb2
    </copy>
    ```

4. Verify the database resolves Emma as an end user and enforces the data grant.

    ```sql
    <copy>
    SELECT ORA_END_USER_CONTEXT.username FROM dual;

    SELECT employee_id, first_name, last_name, salary
      FROM hr.employees
     ORDER BY employee_id;
    </copy>
    ```

    Emma should see only Emma's row. Exit SQL*Plus before continuing.

    ```sql
    <copy>
    EXIT
    </copy>
    ```

## Task 2: Get Up To Speed Quickly

If you already understand the baseline lab and only need a ready database for
this web app, run the shortcut script instead of manually repeating the setup.

> **Important:** The recommended learning path is still to complete
> `end-user-data-grants.md` manually. The shortcut exists only to prepare a
> disposable lab PDB quickly for this web app.

The shortcut also creates `deepsec_admin/Oracle123`, grants audit visibility,
and enables the Unified Audit policy used by the app's audit panel.

1. Run the shortcut against `freepdb1`.

    ```bash
    <copy>
    cd $DBSEC_LABS/deep-data-security/end-user-web-hr-app
    ./quick_setup_end_user_data_grants.sh --tns-alias freepdb1
    </copy>
    ```

2. Or run it against `freepdb2`.

    ```bash
    <copy>
    cd $DBSEC_LABS/deep-data-security/end-user-web-hr-app
    ./quick_setup_end_user_data_grants.sh --tns-alias freepdb2
    </copy>
    ```

3. If the PDB already contains objects from a prior run and you want to rebuild
   them in a disposable lab PDB, add `--force-reset`.

    ```bash
    <copy>
    ./quick_setup_end_user_data_grants.sh --tns-alias freepdb2 --force-reset
    </copy>
    ```

    Do not use `--force-reset` in a PDB where you need to preserve an existing
    `HR` schema.

## Task 3: Run the App

```bash
<copy>
cd $DBSEC_LABS/deep-data-security/end-user-web-hr-app
./setup_python_oracledb.sh
WEB_HR_DB_MODE=oracledb ./start.sh --verbose
</copy>
```

Open:

```text
http://127.0.0.1:8012/
```

By default all local lab users use `Oracle123`. That includes Emma, Marvin, and
the optional `deepsec_admin` diagnostics account. You do not need to set any
password variables for the standard lab environment.

Override passwords only if you changed them:

```bash
export WEB_HR_EMMA_PASSWORD='...'
export WEB_HR_MARVIN_PASSWORD='...'
```

or use one shared override:

```bash
export WEB_HR_END_USER_PASSWORD='...'
```

For `freepdb2`, start the app with:

```bash
<copy>
export WEB_HR_TNS_ALIAS=freepdb2
export WEB_HR_DB_MODE=oracledb
./start.sh --verbose
</copy>
```

## Useful Settings

```bash
<copy>
export WEB_HR_TNS_ALIAS=freepdb1
export WEB_HR_CONFIG_DIR=/path/to/network/admin
export WEB_HR_PORT=8012
export WEB_HR_DB_MODE=oracledb
</copy>
```

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

Mock mode is still available for UI testing:

```bash
<copy>
WEB_HR_DB_MODE=mock ./start.sh
</copy>
```

## Optional Audit Panel

The main demo works without audit diagnostics. The audit panel and audit
preflight check use `deepsec_admin/Oracle123` by default. If you use a different
diagnostics account, set:

```bash
<copy>
export WEB_HR_ADMIN_USER=deepsec_admin
export WEB_HR_ADMIN_PASSWORD='Oracle123'
</copy>
```

If the Unified Audit Trail section shows `ORA-01017`, configure the diagnostics
account in the same PDB as the app:

```bash
<copy>
./setup_audit_diagnostics.sh --tns-alias freepdb1
</copy>
```

For `freepdb2`:

```bash
<copy>
./setup_audit_diagnostics.sh --tns-alias freepdb2
</copy>
```

The diagnostics user only gives the app permission to read audit records. To
generate audit records for `HR.EMPLOYEES`, enable the Unified Audit policy:

```bash
<copy>
./setup_audit_policy.sh --tns-alias freepdb1
</copy>
```

For `freepdb2`:

```bash
<copy>
./setup_audit_policy.sh --tns-alias freepdb2
</copy>
```

After enabling the policy, sign in as Emma or Marvin and click **Load
Employees** or edit a field. Then click **Refresh Audit Events**.

## What To Try

Sign in as Emma:

- Username: `emma`
- Password: `Oracle123`

- `Load Employees` returns only Emma.
- Emma can edit her own first name and phone number.
- Emma cannot update salary or department.

Sign in as Marvin:

- Username: `marvin`
- Password: `Oracle123`

- `Load Employees` returns Marvin and his direct reports.
- Marvin sees his own SSN, but not direct-report SSNs.
- Marvin can edit salary and department for direct reports.
- Marvin cannot edit direct-report phone numbers.

The Diagnostics page shows the authenticated database end user,
`ORA_END_USER_CONTEXT.username`, and active entries from `V$END_USER_DATA_ROLE`.

# Migrate an Enterprise App to Oracle Deep Data Security with Microsoft Entra ID

Welcome to this **Oracle Deep Data Security LiveLabs FastLab** workshop.

You have an enterprise application that connects as a shared service account. Every user sees every row. The app filters the data — and that filter is the only thing standing between your users and each other's sensitive data. This lab migrates that application to Oracle Deep Data Security, where the database enforces per-user access using **Microsoft Entra ID identities**, and the application filtering code is deleted entirely.

Estimated Time: 30 minutes

## The Problem

```
All users → App → Service Account (hr) → Database → ALL rows returned
                     App filters here ↑
```

A shared service account sees everything. The app is responsible for filtering — every endpoint, every query, every new feature. A bug, a new AI copilot, or a forgotten WHERE clause leaks data. Managing database passwords for every enterprise user does not scale.

Oracle Deep Data Security solves both problems:

```
marvin@company.com → Entra ID login → App → End User → Database → only marvin's rows
emma@company.com   → Entra ID login → App → End User → Database → only emma's row
```

Same SQL. Zero application filtering. Zero per-user database passwords. The security is on the grant, not the code.

## Objectives

- Run the traditional "before" setup and observe the shared account problem
- Migrate the database objects to Oracle Deep Data Security using Entra ID UPN identities
- Verify per-user enforcement from the database layer
- See the one-line application code change to pass the Entra ID identity to Oracle
- Run the migrated app and test bypass attempts

## Prerequisites

- An **Oracle AI Database 26ai** instance with a pluggable database (e.g., PDB9)
- `SYSTEM` or `SYS` access to run the setup scripts
- A **Microsoft Entra ID** tenant with users marvin and emma (or equivalent)
- Sample app scripts are already present in the working directory
- **Java 17+** to run the Spring Boot sample app — install with:

    ```bash
    <copy>sudo dnf install -y java-17-openjdk</copy>
    ```

- **Python 3.12+** to run the Django sample app — install with:

    ```bash
    <copy>sudo dnf install -y python3.12</copy>
    ```

## Task 1: See the Problem

Script `01_create_hr_schema.sh` creates the traditional `HR` user (password auth), the `EMPLOYEES` table, and 7 sample rows. It will prompt you for your **Microsoft Entra ID domain** (for example, `contoso.com`) so employee identities are stored in UPN format (`marvin@contoso.com`). Script `02_show_traditional_app.sh` connects as the shared HR service account and queries the table.

```bash
<copy>./01_create_hr_schema.sh</copy>
```

When prompted, enter your Entra ID domain:

```
Entra ID domain: contoso.com
```

```bash
<copy>./02_show_traditional_app.sh</copy>
```

Look for: all 7 rows returned, all SSN values visible, and `user_name` values showing `marvin@contoso.com` format. This is what any application connecting as `hr` sees — regardless of who the logged-in user is.

## Task 2: Migrate the Database Objects

This is the core migration. Two scripts replace traditional users, roles, and grants with their Deep Data Security equivalents.

| Traditional | Enterprise with Entra ID |
|---|---|
| `CREATE USER hr IDENTIFIED BY ...` | `ALTER USER hr NO AUTHENTICATION` — schema-only, cannot log in |
| `CREATE USER marvin IDENTIFIED BY ...` | `CREATE END USER "marvin@contoso.com" IDENTIFIED BY ...` — Entra ID UPN identity |
| `CREATE ROLE manager_role` | `CREATE DATA ROLE hrapp_managers_local` |
| `GRANT SELECT ON hr.employees TO role` | `CREATE DATA GRANT ... WHERE upper(user_name) = upper(ORA_END_USER_CONTEXT.username)` |

```bash
<copy>./03_migrate_db_objects.sh</copy>
```

```bash
<copy>./04_create_role_bindings.sh</copy>
```

`03_migrate_db_objects.sh` locks the HR schema, creates end users `marvin` and `emma`, creates data roles and data grants with row/column predicates, and creates the end user context. `04_create_role_bindings.sh` creates the `direct_logon_role` database role with `CREATE SESSION` and binds it to the data roles so end users can connect.

Look for: confirmation that `HR` can no longer log in, that `marvin` and `emma` are created as end users, and that the data grants are in place.

## Task 3: Verify as Marvin and Emma

Connect as each end user and run the same query — no WHERE clause, no filtering code.

```bash
<copy>./05_verify_as_marvin.sh</copy>
```

```bash
<copy>./06_verify_as_emma.sh</copy>
```

Marvin sees **4 rows** — himself and his 3 direct reports. SSN is hidden for the reports (the manager grant excludes it).

| EMPLOYEE\_ID | FIRST\_NAME | LAST\_NAME | SSN | SALARY |
|---|---|---|---|---|
| 2 | Marvin | Morgan | 222-22-2222 | 175000 |
| 3 | Emma | Baker | | 120000 |
| 4 | Charlie | Davis | | 95000 |
| 5 | Dana | Lee | | 130000 |

Emma sees **1 row** — only herself. Same query, same table.

| EMPLOYEE\_ID | FIRST\_NAME | LAST\_NAME | SSN | SALARY |
|---|---|---|---|---|
| 3 | Emma | Baker | 333-33-3333 | 120000 |

The database enforced the boundary. No application code involved.

## Task 4: See the Application Code Change

Script `07_show_app_migration.sh` displays the before/after diff of the application code.

```bash
<copy>./07_show_app_migration.sh</copy>
```

The change is one line — the connection credential source. For enterprise applications, the password is replaced by an **Entra ID OAuth2 token** obtained from the user's authenticated session:

**Before (Spring Boot — shared service account):**
```java
ds.setUser("hr");           // shared service account
ds.setPassword("Oracle123");
```

**After (Spring Boot — Entra ID identity):**
```java
// Token acquired from the user's Entra ID session via MSAL
String token = entraIdSession.getAccessToken();
Properties props = new Properties();
props.put("oracle.jdbc.accessToken", token);  // Oracle validates token with Entra ID
conn = DriverManager.getConnection(url, props);
```

**Before (Django — shared service account):**
```python
conn = oracledb.connect(user='hr', password='Oracle123', dsn=DSN)
```

**After (Django — Entra ID identity):**
```python
# Token acquired from the user's Entra ID session via MSAL
token = entra_id_session["access_token"]
conn = oracledb.connect(access_token=token, dsn=DSN)
```

Everything else — SQL queries, ORM mappings, connection string, HTML templates — is unchanged. The application filtering code (WHERE clauses, if/else branches, role checks) is deleted entirely.

> **Note:** Oracle Database validates the Entra ID token and resolves `ORA_END_USER_CONTEXT.USERNAME` to the user's UPN (for example, `marvin@contoso.com`). The data grant predicate matches this against the `user_name` column, so Marvin sees only his rows. The identity provider changes; the database enforcement does not.

## Task 5: Run the Migrated App

Script `08_start_app.sh` launches the Spring Boot (Java 17+) or Django (Python 3.12+) app and curl-tests it as both marvin and emma. The script will verify the required runtime is installed before starting.

```bash
<copy>./08_start_app.sh</copy>
```

Choose **1** for Spring Boot (port 8090) or **2** for Django (port 8091) when prompted. You can also pass the choice directly:

```bash
<copy>./08_start_app.sh springboot</copy>
```

```bash
<copy>./08_start_app.sh django</copy>
```

Look for: marvin's request returns **4 rows**, emma's returns **1 row**. The app runs `SELECT * FROM hr.employees` with no filters. The database does the rest.

Open the app in your browser and log in as `marvin@contoso.com` or `emma@contoso.com` via Entra ID to see the filtered views yourself.

To stop the app at any time:

```bash
<copy>./stop_app.sh</copy>
```

## Task 6: Test the Security Boundary

Script `09_verify_security_boundary.sh` runs four bypass attempts.

```bash
<copy>./09_verify_security_boundary.sh</copy>
```

| Test | Expected result |
|---|---|
| Marvin queries Bob's SSN (Bob is not his report) | 0 rows — Bob is invisible to Marvin |
| Emma updates her salary | 0 rows updated — only `phone_number` is writable |
| Emma updates Marvin's phone number | 0 rows updated — predicate limits to own row |
| HR tries to log in | Fails — `NO AUTHENTICATION` |

No prompt injection, misconfigured endpoint, or forgotten WHERE clause can bypass these controls. The kernel enforces them before data leaves the SQL engine.

## Task 7: Clean Up

```bash
<copy>./10_cleanup.sh</copy>
```

Drops all data grants, the end user context, data roles, end users, and the HR schema.

## What You Built

| Script | Purpose |
|---|---|
| `01_create_hr_schema.sh` | Traditional HR with password auth + 7 employee rows |
| `02_show_traditional_app.sh` | Connect as shared HR account — all 7 rows, all SSNs visible |
| `03_migrate_db_objects.sh` | Lock HR, create Entra ID end users, data roles, data grants, context |
| `04_create_role_bindings.sh` | `CREATE SESSION` via `direct_logon_role` bound to data roles |
| `05_verify_as_marvin.sh` | Connect as marvin@domain.com — 4 rows, SSN hidden for reports |
| `06_verify_as_emma.sh` | Connect as emma@domain.com — 1 row, same query |
| `07_show_app_migration.sh` | Before/after app code diff (shared account → Entra ID token) |
| `08_start_app.sh` | Launch Spring Boot or Django app, test as marvin@domain.com and emma@domain.com |
| `09_verify_security_boundary.sh` | Four bypass attempts — all fail |
| `10_cleanup.sh` | Drop everything |

The trust chain is unbroken: **end user authentication → data role → data grant enforcement.** The application no longer acts as the gatekeeper. It connects as the end user, runs the same SQL, and receives only what that user is authorized to see.

## Learn More

- [Oracle AI Database 26ai Documentation](https://docs.oracle.com/en/database/)
- [Oracle Deep Data Security Configuration Guide](https://docs.oracle.com/en/database/oracle/oracle-database/26/ddscg/index.html)

## Acknowledgements

- **Author** - Richard C. Evans, Oracle Database Security Product Management
- **Last Updated By/Date** - Richard C. Evans, April 28, 2026

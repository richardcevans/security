# Migrate an App to Oracle Deep Data Security

Welcome to this **Oracle Deep Data Security LiveLabs FastLab** workshop.

You have an application that connects as a shared service account. Every user sees every row. The app filters the data — and that filter is the only thing standing between your users and each other's sensitive data. This lab migrates that application to Oracle Deep Data Security, where the database enforces per-user access and the application filtering code is deleted entirely.

Estimated Time: 30 minutes

## The Problem

```
All users → App → Service Account (hr) → Database → ALL rows returned
                     App filters here ↑
```

A shared service account sees everything. The app is responsible for filtering — every endpoint, every query, every new feature. A bug, a new AI copilot, or a forgotten WHERE clause leaks data.

Oracle Deep Data Security moves enforcement into the database:

```
marvin → App → End User (marvin) → Database → only marvin's rows
emma   → App → End User (emma)  → Database → only emma's row
```

Same SQL. Zero application filtering. The security is on the grant, not the code.

## Objectives

- Run the traditional "before" setup and observe the shared account problem
- Migrate the database objects to Oracle Deep Data Security
- Verify per-user enforcement from the database layer
- See the one-line application code change
- Run the migrated app and test bypass attempts

## Prerequisites

- An **Oracle AI Database 26ai** instance with a pluggable database (e.g., PDB9)
- `SYSTEM` or `SYS` access to run the setup scripts
- Sample app scripts are already present in the working directory
- **Java 17+** for the Spring Boot app, or **Python 3.12** for the Django app

## Task 1: See the Problem

Script `01_create_hr_schema.sh` creates the traditional `HR` user (password auth), the `EMPLOYEES` table, and 7 sample rows. Script `02_show_traditional_app.sh` connects as the shared HR service account and queries the table.

```bash
./01_create_hr_schema.sh
./02_show_traditional_app.sh
```

Look for: all 7 rows returned, all SSN values visible. This is what any application connecting as `hr` sees — regardless of who the logged-in user is.

## Task 2: Migrate the Database Objects

This is the core migration. Two scripts replace traditional users, roles, and grants with their Deep Data Security equivalents.

| Traditional | Deep Data Security |
|---|---|
| `CREATE USER hr IDENTIFIED BY ...` | `ALTER USER hr NO AUTHENTICATION` — schema-only, cannot log in |
| `CREATE USER marvin IDENTIFIED BY ...` | `CREATE END USER marvin IDENTIFIED BY Oracle123` |
| `CREATE ROLE manager_role` | `CREATE DATA ROLE hrapp_managers_local` |
| `GRANT SELECT ON hr.employees TO role` | `CREATE DATA GRANT ... WHERE upper(user_name) = upper(ORA_END_USER_CONTEXT.username)` |

```bash
./03_migrate_db_objects.sh
./04_create_role_bindings.sh
```

`03_migrate_db_objects.sh` locks the HR schema, creates end users `marvin` and `emma`, creates data roles and data grants with row/column predicates, and creates the end user context. `04_create_role_bindings.sh` creates the `direct_logon_role` database role with `CREATE SESSION` and binds it to the data roles so end users can connect.

Look for: confirmation that `HR` can no longer log in, that `marvin` and `emma` are created as end users, and that the data grants are in place.

## Task 3: Verify as Marvin and Emma

Connect as each end user and run the same query — no WHERE clause, no filtering code.

```bash
./05_verify_as_marvin.sh
./06_verify_as_emma.sh
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
./07_show_app_migration.sh
```

The change is one line — the connection credential source:

**Before (Spring Boot):**
```java
ds.setUser("hr");           // shared service account
ds.setPassword("Oracle123");
```

**After (Spring Boot):**
```java
ds.setUser(username);       // end user credential from session
ds.setPassword(password);
```

**Before (Django):**
```python
conn = oracledb.connect(user='hr', password='Oracle123', dsn=DSN)
```

**After (Django):**
```python
conn = oracledb.connect(user=username, password=password, dsn=DSN)
```

Everything else — SQL queries, JDBC driver, ORM mappings, connection string, HTML templates — is unchanged. The application filtering code (WHERE clauses, if/else branches, role checks) is deleted entirely.

> **Note:** For enterprise applications using Microsoft Entra ID or OCI IAM, the JDBC End User Security Context SPI forwards the OAuth2 token instead of a password. The Deep Data Security enforcement is identical either way — the identity provider changes, the database behavior does not.

## Task 5: Run the Migrated App

Script `08_start_app.sh` launches the Spring Boot or Django app and curl-tests it as both marvin and emma.

```bash
./08_start_app.sh
```

Look for: marvin's request returns 4 rows, emma's returns 1 row. The app code runs `SELECT * FROM hr.employees` — no filters, no branches. The database does the rest.

## Task 6: Test the Security Boundary

Script `09_verify_security_boundary.sh` runs four bypass attempts.

```bash
./09_verify_security_boundary.sh
```

| Test | Expected result |
|---|---|
| Marvin queries Bob's SSN (Bob is not his report) | 0 rows — Bob is invisible to Marvin |
| Emma updates her salary | 0 rows updated — only `phone_number` is allowed |
| Emma updates Marvin's phone number | 0 rows updated — predicate limits to own row |
| HR tries to log in | Fails — `NO AUTHENTICATION` |

No prompt injection, misconfigured endpoint, or forgotten WHERE clause can bypass these controls. The kernel enforces them before data leaves the SQL engine.

## Task 7: Clean Up

```bash
./10_cleanup.sh
```

Drops all data grants, the end user context, data roles, end users, and the HR schema.

## What You Built

| Script | Purpose |
|---|---|
| `01_create_hr_schema.sh` | Traditional HR with password auth + 7 employee rows |
| `02_show_traditional_app.sh` | Connect as shared HR account — all 7 rows, all SSNs visible |
| `03_migrate_db_objects.sh` | Lock HR, create end users, data roles, data grants, context |
| `04_create_role_bindings.sh` | `CREATE SESSION` via `direct_logon_role` bound to data roles |
| `05_verify_as_marvin.sh` | Connect as Marvin — 4 rows, SSN hidden for reports |
| `06_verify_as_emma.sh` | Connect as Emma — 1 row, same query |
| `07_show_app_migration.sh` | Before/after app code diff |
| `08_start_app.sh` | Launch Spring Boot or Django app, curl-test as marvin/emma |
| `09_verify_security_boundary.sh` | Four bypass attempts — all fail |
| `10_cleanup.sh` | Drop everything |

The trust chain is unbroken: **end user authentication → data role → data grant enforcement.** The application no longer acts as the gatekeeper. It connects as the end user, runs the same SQL, and receives only what that user is authorized to see.

## Learn More

- [Oracle AI Database 26ai Documentation](https://docs.oracle.com/en/database/)
- [Oracle Deep Data Security Configuration Guide](https://docs.oracle.com/en/database/oracle/oracle-database/26/ddscg/index.html)

## Acknowledgements

- **Author** - Richard C. Evans, Oracle Database Security Product Management
- **Last Updated By/Date** - Richard C. Evans, April 2026

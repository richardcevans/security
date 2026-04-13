# Identity-aware database access using Oracle Deep Data Security and End Users

Welcome to this **Oracle Deep Data Security LiveLabs** workshop.

LiveLabs workshops give you clear, step-by-step instructions to help you quickly gain hands-on experience. You will go from beginner to confident user in a short time.

Estimated Time: 30 minutes

## The Challenge

AI copilots and agentic applications are transforming the enterprise, but many never make it past the security review. The use case is clear, but when sensitive data is involved, everything stalls. Security teams can't sign off. Data owners won't grant access. The blocking question is always the same: *how do you guarantee the AI agent only shows each user what they're authorized to see?*

Consider a copilot built on your company's HR data. Marvin, a manager of a team of three, asks *"What's the salary breakdown for my team?"* — he should see his direct reports and his own record. Emma, on Marvin's team, asks *"Show me my employee details"* — she should see only herself.

Oracle AI Database 26ai Deep Data Security (Oracle Deep Data Security) solves this within the kernel of the database. With Deep Data Security, there are no proxies to route traffic through, no agents on the operating system to manage, nothing that bolts on to the database. The controls are declarative, identity-aware, and enforced before data ever leaves the database engine. The agent never sees restricted data — it physically cannot be retrieved. Guardrails protect the conversation; data grants protect the data itself. Your security team gets a control they can verify, and your AI project gets unblocked.

In 30 minutes, you'll see how Deep Data Security can help secure your data in the new Agentic AI world.

## Workshop Introduction

### Prerequisites

This lab assumes the following are already configured:

- An **Oracle AI Database 26ai** instance (Autonomous or on-premises)
- You are connected as a database user for the setup tasks, privileges include:
      - CREATE USER
      - CREATE DATA ROLE
      - CREATE DATA GRANT
      - CREATE TABLE
      - GRANT QUOTA ON a TABLESPACE

### Scripts

Each task has a corresponding script that runs all the SQL for you with verbose, color-coded output. You can run the scripts or type the commands manually — the lab works either way.

| Script | Task |
|---|---|
| `dg_create_hr_schema.sh` | Task 1 — Create the HR schema and employee data |
| `dg_before_data_grants.sh` | Task 2 — See what happens without data grants |
| `dg_create_end_users_and_roles.sh` | Task 3 — Create end users and data roles |
| `dg_create_data_grants.sh` | Task 4 — Create data grants |
| `dg_create_role_bindings.sh` | Task 5 — Create role-to-role bindings and verify |
| `dg_connect_as_marvin.sh` | Task 6 — Connect and verify as Marvin |
| `dg_connect_as_emma.sh` | Task 7 — Connect and verify as Emma |
| `dg_query_compare.sh` | Task 8 — Same query, three users, three results |
| `dg_marvin_role_change.sh` | Task 9 — Marvin loses his manager role |
| `dg_marvin_role_restore.sh` | Restore Marvin's manager role |
| `dg_cleanup.sh` | Task 10 — Clean up all lab objects |

The scripts default to `PDB_NAME=pdb1`, `DBUSR_SYSTEM=system`, and `DBUSR_PWD=Oracle123`. If your environment differs, either source your `setEnv` script or export the variables before running.

### What You Will Build

![Architecture diagram placeholder](./images/architecture.png "Architecture diagram showing Marvin and Emma connecting through an AI agent to Oracle with data grants enforcing per-user access.")

Same agent. Same SQL query. Different data — enforced by the database.

### How Identity Mapping Works — and Why It Matters

In a traditional database, you create database users and grant them privileges directly. But AI agents shouldn't work that way. A single AI agent connects to the database on behalf of **many** users — Marvin, Emma, and everyone else. Without an extra layer, the agent's service account sees all the data, and you're trusting application code to filter correctly. That trust is fragile: a prompt injection, misconfiguration, or a bug, and sensitive data leaks.

Oracle 26ai solves this with **Oracle Deep Data Security** — controls that are declarative, identity-aware, and enforced before data ever leaves the database engine:

## How Oracle Deep Data Security works

### End Users

Oracle Database end users are a new class of identity — distinct from traditional database schema users. They authenticate directly to the database with a password, but do not own schemas or objects. Deep Data Security ensures that end users and non-human identities (including agents) operate with least privilege and are monitored through centralized auditing. This enables organizations to adopt agentic AI with stronger security, privacy, and regulatory controls without making traditional guardrails the primary line of defense.

When you look at the session for Emma or Marvin, you will query the usual pseudo columns, functions, and user context. You will notice that your landing spot is not a dedicated schema named Marvin, nor is it a shared schema like you would find in Enterprise User Security (EUS) or Centrally Managed Users (CMU), but a null schema (`XS$NULL`) instead. `XS$NULL` acts as a placeholder for database sessions that do not have a corresponding database schema user, often used to indicate an active application user session in Oracle Deep Data Security or Oracle Real Application Security. It has no privileges and cannot own objects.

### Data Roles

In the Oracle AI Database, you will create data roles that are assigned to Oracle Database end users. End Users are not traditional Oracle Database users but a different class of user to match Data Roles and Data Grants. When you write `CREATE DATA ROLE HRAPP_MANAGERS` and grant it to an end user, Oracle activates `HRAPP_MANAGERS` automatically when that end user authenticates.

This means no manual grants and no application logic changes because the mapping is declarative and enforced by the new data roles and data grants mechanisms in the Oracle AI Database kernel.

### Role-to-Role Binding

End users land in `XS$NULL` — a schema with no privileges. They cannot hold system privileges like `CREATE SESSION` or object privileges like `EXECUTE` directly. So how do they connect to the database or invoke packages?

The answer is **role-to-role binding**: you grant a traditional database role *to* a data role. When the data role activates at login, it brings the database role — and all of its privileges — into the session automatically.

```
-- Create a database role and give it CREATE SESSION
CREATE ROLE direct_logon_role;
GRANT CREATE SESSION TO direct_logon_role;

-- Bind it to a data role
GRANT direct_logon_role TO hrapp_employees;
```

When Emma authenticates and `HRAPP_EMPLOYEES` activates, `DIRECT_LOGON_ROLE` activates with it. Emma's session gains `CREATE SESSION` without Emma ever being granted it directly. The same pattern works for any privilege: `EXECUTE` on a package, `SELECT` on a view, or any other system or object privilege the end user session needs.

This is the bridge between the traditional privilege model and Deep Data Security. Data grants control *which data* is returned. Role-to-role bindings control *which capabilities* the session has. Together, they give end users exactly the privileges they need — nothing more.

### Data Grants

Data grants define which DML and SELECT operations are possible by the data role. They can be broad, such as `SELECT` or they can be fine grained to specific columns such as `UPDATE(PHONE_NUMBER)`.

Next, a data grant predicate defines the limitations the rows returned to the end user. For example, this data grant allows the user to SELECT specific columns but only update `PHONE_NUMBER`. The predicate uses the new `ora_end_user_context` to identify the user by their *end user* identity and restrict the rows returned to only rows that match their identity.

```
CREATE OR REPLACE DATA GRANT hr.HRAPP_EMPLOYEES_ACCESS
AS SELECT (employee_id, first_name, last_name, user_name, department_id, manager_id, ssn, phone_number), UPDATE(phone_number)
ON hr.employees
WHERE upper(user_name) = upper(ora_end_user_context.USERNAME)
TO HRAPP_EMPLOYEES;
```

At runtime, Deep Data Security evaluates policies and modifies queries and other operations transparently from application logic to apply controls. As an ABAC system, this means that Deep Data Security acts as the policy decision point (PDP) and the database SQL engine as the policy enforcement point (PEP). End users can access only authorized data, irrespective of the SQL executed by an agent or application, mitigating prompt and SQL injection attacks.

### Why Data Grants — Not VPD, RAS, or Label Security

Oracle has offered row-level and column-level security for years. If you've used VPD, RAS, or OLS, you might ask: *why do I need data grants?* The answer is where the security lives — and what you have to trust.

Each traditional approach attaches security to a different layer:

| Approach | Security lives on | What you must trust | Privileges required |
|---|---|---|---|
| **VPD** (Virtual Private Database) | The **table** — a PL/SQL policy function appends a `WHERE` clause at parse time | The policy function is correct and no one bypasses it with `EXEMPT ACCESS POLICY` | `DBMS_RLS.ADD_POLICY`, `CREATE` or `ALTER` on the policy function, `EXEMPT ACCESS POLICY` can override |
| **RAS** (Real Application Security) | The **application** — ACLs and security classes control access through an app-managed session | The application creates the correct security context; direct SQL bypasses it entirely | `XS_ADMIN` role, `CREATE SESSION` with app session, ACL grants |
| **OLS** (Oracle Label Security) | The **row** — labels and user clearances filter data | Label assignments are correct; users with `FULL` access or `SA_SYSDBA` can override | `SA_SYSDBA`, `SA_SESSION`, label authorizations, policy administration |
| **Data Grants** (Deep Data Security) | The **grant itself** — a single DDL statement declares rows, columns, operations, and predicate | Nothing beyond the grant — there is no policy function, no app session, no override privilege | `CREATE DATA GRANT`, `CREATE DATA ROLE`, `CREATE END USER` |

With VPD, a bug in your policy function leaks data. With RAS, a direct SQL connection bypasses your controls. With OLS, a privileged user with `FULL` access reads everything. In each case, the security depends on something external to the data access itself — a function, an application, a label assignment.

**Data grants are different because the security IS the access.** There is no separate policy to get wrong. There is no application session to manage. There is no override privilege that bypasses the control. An end user without a data grant has zero access — the table is invisible. Access must be explicitly declared in a `CREATE DATA GRANT` statement, and only that statement controls what data is returned.

This is a fundamental shift: instead of adding security *around* data access, the security *is* the data access.

### Why this is important

This is important because it creates an **unbroken trust chain**: end user authentication → Oracle data role → role-to-role binding (session capabilities) + data grant enforcement (data access). No single layer can be bypassed independently.

In this lab, you will create two end users and two data roles, bind database roles to those data roles for session capabilities, grant the data roles to the appropriate end users, then attach data grants that define which rows and columns each data role can access or modify.

## Task 0: Download lab scripts

1. Open a Terminal session on your **DBSec-Lab** VM as OS user *oracle* and `cd` to the livelabs directory.

    ````
    <copy>cd livelabs</copy>
    ````

2. Download the bundled script archive for this lab.

    ````
    <copy>wget <<DOWNLOAD LINK HERE>></copy>
    ````

3. Extract the archive to expand the scripts directory.

    ````
    <copy>tar xvf dbsec-livelabs-local-user-data-grants.tar.gz</copy>
    ````

4. Move into the lab directory.

    ````
    <copy>cd local-user-data-grants</copy>
    ````

5. List files to confirm the scripts are present.

    ````
    <copy>ls</copy>
    ````

## Task 1: Create the HR schema and sensitive employee data

> **Script:** 

```
<copy>
./dg_create_hr_schema.sh
</copy>
```

**The Scenario:** Your AI copilot will query an HR employees table that contains sensitive data — Social Security numbers, salaries, and a management hierarchy. You need a test environment that mirrors your production data so you can demonstrate per-user access control.

1. The script will create a schema-only account for the HR data and a table with sample employees.

      ```
      <copy>
      CREATE USER hr NO AUTHENTICATION;
      GRANT UNLIMITED TABLESPACE TO hr;

      CREATE TABLE hr.employees (
      employee_id   NUMBER PRIMARY KEY,
      first_name    VARCHAR2(50),
      last_name     VARCHAR2(50),
      job_code      VARCHAR2(10),
      department_id NUMBER,
      ssn           VARCHAR2(20),
      photo         BLOB,
      phone_number  VARCHAR2(30),
      salary        NUMBER(10,2),
      user_name     VARCHAR2(128),
      manager_id    NUMBER);

      -- CEO
      INSERT INTO hr.employees VALUES (1, 'Grace', 'Young', 'CEO', NULL, '111-11-1111', NULL, '555-100-0001', 235000, 'grace', NULL);

      -- Manager
      INSERT INTO hr.employees VALUES (2, 'Marvin', 'Morgan', 'SWE_MGR', 1, '222-22-2222', NULL, '555-100-0002', 175000, 'marvin', 1);

      -- Marvin's team
      INSERT INTO hr.employees VALUES (3, 'Emma', 'Baker', 'SWE2', 1, '333-33-3333', NULL, '555-100-0003', 120000, 'emma', 2);
      INSERT INTO hr.employees VALUES (4, 'Charlie', 'Davis', 'SWE1', 1, '444-44-4444', NULL, '555-100-0004', 95000, 'charlie', 2);
      INSERT INTO hr.employees VALUES (5, 'Dana', 'Lee', 'SWE3', 1, '555-55-5555', NULL, '555-100-0005', 130000, 'dana', 2);

      -- Other departments
      INSERT INTO hr.employees VALUES (6, 'Bob', 'Smith', 'SALES_REP', 2, '666-66-6666', NULL, '555-100-0006', 145000, 'bob', 1);
      INSERT INTO hr.employees VALUES (7, 'Fiona', 'Chen', 'HR_REP', 3, '777-77-7777', NULL, '555-100-0007', 92000, 'fiona', 1);

      COMMIT;
      </copy>
      ```

2. You should see the output of the following query in your terminal.

      ```
      <copy>
      SELECT employee_id, first_name, last_name, ssn, salary, department_id, manager_id
        FROM hr.employees
       ORDER BY employee_id;
      </copy>
      ```

      You should see all 7 rows with full SSN values and the reporting chain. Right now, anyone with access to this table sees everything — every employee SSN, every salary, across every department. Your AI agent would expose all of this for every user it serves. That is the problem you are about to fix.

      | EMPLOYEE\_ID | FIRST\_NAME | LAST\_NAME | SSN | SALARY | DEPARTMENT\_ID | MANAGER\_ID |
      |---|---|---|---|---|---|---|
      | 1 | Grace | Young | 111-11-1111 | 235000 | | |
      | 2 | Marvin | Morgan | 222-22-2222 | 175000 | 1 | 1 |
      | 3 | Emma | Baker | 333-33-3333 | 120000 | 1 | 2 |
      | 4 | Charlie | Davis | 444-44-4444 | 95000 | 1 | 2 |
      | 5 | Dana | Lee | 555-55-5555 | 130000 | 1 | 2 |
      | 6 | Bob | Smith | 666-66-6666 | 145000 | 2 | 1 |
      | 7 | Fiona | Chen | 777-77-7777 | 92000 | 3 | 1 |

## Task 2: See what happens without data grants

> **Script:** 

```
<copy>
./dg_before_data_grants.sh
</copy>
```

**The Baseline:** Before creating any data grants, you need to see the default behavior. What happens when an end user connects to the database and tries to query `hr.employees`? The answer establishes *why* data grants exist and how they differ from every previous approach.

1. This script will create a temporary end user with only `CREATE SESSION` — no data grants, no object privileges.

      ```
      <copy>
      CREATE END USER temp_user IDENTIFIED BY Oracle123;
      CREATE OR REPLACE DATA ROLE temp_role;
      CREATE ROLE temp_logon_role;
      GRANT CREATE SESSION TO temp_logon_role;
      GRANT temp_logon_role TO temp_role;
      GRANT DATA ROLE temp_role TO temp_user;
      </copy>
      ```

2. Connect as the temporary end user and run the same query.

      ```
      <copy>
      sqlplus temp_user/Oracle123@pdb1
      </copy>
      ```

      ```
      <copy>
      SELECT employee_id, first_name, last_name, ssn, salary, department_id, manager_id
        FROM hr.employees
       ORDER BY employee_id;
      </copy>
      ```

      The end user sees **no rows**. Just an error (`ORA-00942`) saying the table does not exist. 

      This is the fundamental difference between data grants and every previous approach:

      | Approach | Default behavior | How access is added | What can bypass it |
      |---|---|---|---|
      | **VPD** | User sees **all rows** until you attach a policy function to the table | Write a PL/SQL function, attach it with `DBMS_RLS.ADD_POLICY` | `EXEMPT ACCESS POLICY` privilege, bugs in the policy function |
      | **RAS** | User sees **all rows** unless the application sets up a security context | Configure ACLs, security classes, and an application session | Direct SQL connections bypass the application session entirely |
      | **OLS** | User sees **all rows** until you apply labels to rows and clearances to users | Label every row, assign clearances to users | `SA_SYSDBA`, `FULL` access, read/write authorizations |
      | **Data Grants** | User sees **nothing** — zero access is the default | Write a `CREATE DATA GRANT` statement | Nothing — there is no override privilege |

      With VPD, RAS, and OLS, you start with full access and *subtract*. You must remember to add the policy, set up the application session, or label every row. If you miss one, data leaks. The security is *around* the data access — a function, an application, a label — and each has a way to bypass it.

      With data grants, you start with zero access and *add*. If you forget to create a data grant, nothing leaks — the end user sees nothing. The security is not around the data access. **The security IS the data access.** There is no separate policy to get wrong, no application session to manage, no override privilege to worry about.

3. Clean up the temporary objects before proceeding to Task 3.

      ```
      <copy>
      DROP END USER temp_user;
      DROP DATA ROLE temp_role;
      DROP ROLE temp_logon_role;
      </copy>
      ```

## Task 3: Create end users and data roles

> **Script:**

```
<copy>
./dg_create_end_users_and_roles.sh
</copy>
```

**The Foundation:** In this step, you'll create Oracle Database end users and data roles, then assign the roles. This establishes the identity layer that data grants and role-to-role bindings build on.

1. The script will create two end users, Marvin and Emma. Marvin is a manager and Emma is an employee.

      ```
      <copy>
      CREATE END USER marvin IDENTIFIED BY Oracle123;
      CREATE END USER emma IDENTIFIED BY Oracle123;
      </copy>
      ```

2. Next, it will create two data roles.

      ```
      <copy>
      CREATE OR REPLACE DATA ROLE hrapp_employees;
      CREATE OR REPLACE DATA ROLE hrapp_managers;
      </copy>
      ```

      The purpose of these two roles will be to provide the following access based on the end user's role:
      - `HRAPP_EMPLOYEES` provides `SELECT` privileges, on specific columns, and returns only the employee's own row of data.
      - `HRAPP_MANAGERS` provides `SELECT` and `UPDATE` privileges but only on specific columns.

3. Then, it will grant the data roles to the end users based on their roles in the organization.

      - Emma is an employee

      ```
      <copy>
      GRANT DATA ROLE hrapp_employees TO emma;
      </copy>
      ```

      - Marvin is both an employee and a manager

      ```
      <copy>
      GRANT DATA ROLE hrapp_employees TO marvin;
      GRANT DATA ROLE hrapp_managers TO marvin;
      </copy>
      ```

4. Next, it will verify the data roles and their mappings.

      ```
      <copy>
      SELECT data_role, mapped_to, enabled_by_default
        FROM dba_data_roles
       WHERE data_role IN ('HRAPP_EMPLOYEES', 'HRAPP_MANAGERS');
      </copy>
      ```

      | DATA\_ROLE | MAPPED\_TO | ENABLED\_BY\_DEFAULT |
      |---|---|---|
      | HRAPP\_EMPLOYEES | null | true |
      | HRAPP\_MANAGERS | null | true |

      When Marvin authenticates with his end user password, Oracle activates `HRAPP_MANAGERS` (and `HRAPP_EMPLOYEES`) for his session. When Emma authenticates, only `HRAPP_EMPLOYEES` activates.

## Task 4: Create data grants

> **Script:**

```
<copy>
./dg_create_data_grants.sh
</copy>
```

**The Security Policy:** Now you'll define data grants that control exactly which rows and columns each data role can access — or modify. You'll also create an end user context so data grant predicates can resolve the current user's identity at query time.

1. The script creates a limited data grant for the employee role. An employee should see only their own record, including their own salary, and only be able to update their phone number.

      ```
      <copy>
      CREATE OR REPLACE DATA GRANT hr.HRAPP_EMPLOYEES_ACCESS
        AS SELECT (employee_id, first_name, last_name, user_name, department_id, manager_id, ssn, salary, phone_number), UPDATE(phone_number)
        ON hr.employees
        WHERE upper(user_name) = upper(ora_end_user_context.username)
        TO HRAPP_EMPLOYEES;
      </copy>
      ```

      The dynamic predicate `ora_end_user_context.username` resolves to the authenticated user at query time. Emma sees Emma. Marvin sees Marvin. No hardcoded names. The grant works for every employee automatically.

      Compare this to the equivalent VPD implementation. To achieve the same row filtering, you would need:

      ```sql
      -- You are not running this PL/SQL or grant.
      -- It is here to explain the differences between Deep Sec and VPD      -- VPD requires: a policy function, a policy attachment, and a GRANT SELECT
      CREATE OR REPLACE FUNCTION hr.emp_vpd_policy (
        p_schema IN VARCHAR2, p_table IN VARCHAR2
      ) RETURN VARCHAR2 IS
      BEGIN
        RETURN 'upper(user_name) = upper(SYS_CONTEXT(''USERENV'',''SESSION_USER''))';
      END;
      /

      BEGIN
        DBMS_RLS.ADD_POLICY(
          object_schema   => 'HR',
          object_name     => 'EMPLOYEES',
          policy_name     => 'EMP_ROW_POLICY',
          function_schema => 'HR',
          policy_function => 'EMP_VPD_POLICY',
          statement_types => 'SELECT,UPDATE'
        );
      END;
      /

      -- Plus you still need a traditional GRANT for the table itself:
      GRANT SELECT, UPDATE ON hr.employees TO some_role;
      -- You are not running this PL/SQL or grant.
      -- It is here to explain the differences between Deep Sec and VPD

      ```

      That's three separate objects to maintain — a function, a policy attachment, and a traditional grant — and they can fall out of sync. The data grant replaces all three with a single declarative statement. And because VPD starts with full access and subtracts, if you forget the policy or the function has a bug, data leaks. The data grant starts with zero and adds.

      **Note:** Do not create the PL/SQL, you are not using VPD in this lab. This is just an example.

2. The script will create an end user context and the package that initializes it. The context stores the current user's `employee_id`, resolved from `hr.employees` at session start via the `o:onFirstRead` trigger. This value is then available in data grant predicates without a helper function or a separate lookup table.

      ```
      <copy>
      CREATE OR REPLACE END USER CONTEXT HR.EMP_CTX USING JSON SCHEMA '{
        "type": "object",
        "properties": {
          "ID": {
            "type": "integer",
            "o:onFirstRead": "HR.ctx_pkg.init_user_context"
          }
        }
      }';
      </copy>
      ```

      > **Note:** `HR.EMP_CTX` is not a database table — you cannot query it with `SELECT * FROM`. It is a virtual, session-scoped object maintained by Oracle Deep Data Security. Read individual attributes with dot notation (`ORA_END_USER_CONTEXT.HR.EMP_CTX.ID`) or retrieve the full namespace as JSON with `SELECT ora_end_user_context.HR FROM DUAL`.

      ```
      <copy>
      CREATE OR REPLACE PACKAGE hr.ctx_pkg AS
        PROCEDURE init_user_context;
      END;
      /
      </copy>
      ```

      ```
      <copy>
      CREATE OR REPLACE PACKAGE BODY hr.ctx_pkg AS
        PROCEDURE init_user_context IS
          sql_stmt VARCHAR2(4000);
        BEGIN
          sql_stmt := '
            UPDATE END_USER_CONTEXT t
            SET t.CONTEXT.ID = (
               SELECT e.employee_id
               FROM hr.employees e
               WHERE upper(e.user_name) = upper(ora_end_user_context.USERNAME)
             )
            WHERE owner = ''HR''
            AND name = ''EMP_CTX'';
          ';
          EXECUTE IMMEDIATE sql_stmt;
        END;
      END;
      /
      </copy>
      ```

3. The script will grant the data roles the privileges they need to read and initialize the end user context. Three things are required:

      - **SYS-level grants to HR** — allow the HR schema to create and update end user context objects.
      - A **database role** (`employee_context_admin`) holding `EXECUTE` on the context package — without this, `o:onFirstRead` cannot fire and the `ID` attribute stays null with an insufficient privileges error.
      - A **data grant on `SYS.END_USER_CONTEXT`** — without this, sessions cannot read `ORA_END_USER_CONTEXT.HR.EMP_CTX.ID` at all.

      Run the following as your DBA user (e.g., SYSTEM):

      ```
      <copy>
      GRANT UPDATE ANY END USER CONTEXT TO HR;
      GRANT CREATE ANY END USER CONTEXT TO HR;

      CREATE ROLE IF NOT EXISTS employee_context_admin;
      GRANT EXECUTE ON hr.ctx_pkg TO employee_context_admin;
      GRANT employee_context_admin TO HRAPP_EMPLOYEES;
      GRANT employee_context_admin TO HRAPP_MANAGERS;
      </copy>
      ```

      This is an example of role-to-role binding: the `employee_context_admin` database role holds `EXECUTE` on the context package, and is bound to both data roles. When a session activates `HRAPP_EMPLOYEES` or `HRAPP_MANAGERS`, the database role activates with it, granting execute access to the package and allowing `o:onFirstRead` to fire.

      The final grant — the data grant on `SYS.END_USER_CONTEXT` — must be run as **SYS** because it grants access to a SYS-owned internal table. No other account, including DBA users, has permission to create data grants on SYS objects.

      ```
      <copy>
      CREATE OR REPLACE DATA GRANT hr.EMPLOYEE_CONTEXT_GRANT
        AS SELECT ON SYS.END_USER_CONTEXT
         WHERE OWNER = 'HR' AND NAME = 'EMP_CTX'
          TO HRAPP_EMPLOYEES, HRAPP_MANAGERS;
      </copy>
      ```

4. The script will create a read-write data grant for the `hrapp_managers` role. A manager should see their own record and their direct reports, with access to salaries for compensation planning, but never SSN. Unlike the employee grant, this role can also update salary and department for their direct reports. A single data grant can combine multiple operations.

      ```
      <copy>
      CREATE OR REPLACE DATA GRANT hr.HRAPP_MANAGER_ACCESS
        AS SELECT (ALL COLUMNS EXCEPT ssn), UPDATE (salary, department_id)
        ON hr.employees
        WHERE manager_id = ORA_END_USER_CONTEXT.HR.EMP_CTX.ID
        TO HRAPP_MANAGERS;
      </copy>
      ```

      SSN is excluded for all rows, salary updates are limited to direct reports, and the same predicate works for every manager without hardcoding names.

      Notice that with data grants, the column restrictions and row restrictions are in a single statement. With VPD, you would need a separate `DBMS_RLS.ADD_POLICY` call for row filtering *and* a column-masking policy or a view to hide SSN — two policies that must stay in sync. With OLS, you would need row labels *and* column-level OLS policies. Data grants express both dimensions in one place.

> **Note:** The `SELECT` and `UPDATE` privileges in data grants are not traditional Oracle object privileges. A `GRANT SELECT ON hr.employees TO some_user` has no effect on end user sessions — only data grants apply. This means no pre-existing object grants can bypass Deep Data Security controls, even if a DBA forgot to revoke them.

## Task 5: Create role-to-role bindings and verify

> **Script:**

```
<copy>
./dg_create_role_bindings.sh
</copy>
```

**The Bridge:** End users land in `XS$NULL` — a schema with no privileges. Data grants control which data they can access, but end users also need session capabilities like `CREATE SESSION` to connect. Role-to-role binding solves this: you grant a traditional database role *to* a data role, and when the data role activates at login, the database role activates with it.

1. This is role-to-role binding in action. The script will create a traditional database role with the `CREATE SESSION` system privilege, then bind it to both data roles. End users cannot hold system privileges directly — the only way they gain `CREATE SESSION` is through a database role bound to their data role.

      ```
      <copy>
      CREATE ROLE direct_logon_role;
      GRANT CREATE SESSION TO direct_logon_role;
      GRANT direct_logon_role TO hrapp_employees;
      GRANT direct_logon_role TO hrapp_managers;
      </copy>
      ```

2. The script will verify the complete setup.

      ```
      <copy>
      SELECT grant_name, privilege, grantee, column_name,
             granted_with_all_columns_except, predicate
        FROM dba_data_grants
       WHERE object_owner = 'HR'
         AND object_name = 'EMPLOYEES'
       ORDER BY grant_name, privilege;
      </copy>
      ```

      You should see two grants:
      - `HRAPP_EMPLOYEES_ACCESS` with `SELECT` on specific columns,
      - `HRAPP_MANAGER_ACCESS` with `SELECT (all columns except SSN)` and `UPDATE (salary, department_id)`.

      Both grants have dynamic predicates that resolve at query time based on who is authenticated.

      The privilege model is worth comparing side by side. Here is what each user ends up with, and what controls it:

      **Marvin (employee + manager):**

      | Column | SELECT | UPDATE | Controlled by |
      |---|---|---|---|
      | employee\_id | Own row + direct reports | — | `HRAPP_EMPLOYEES_ACCESS` + `HRAPP_MANAGER_ACCESS` |
      | first\_name | Own row + direct reports | — | Both grants |
      | last\_name | Own row + direct reports | — | Both grants |
      | ssn | **Own row only** | — | `HRAPP_EMPLOYEES_ACCESS` only (manager grant excludes SSN) |
      | salary | Own row + direct reports | **Direct reports only** | Employee grant (own row), manager grant (reports + UPDATE) |
      | phone\_number | Own row + direct reports | **Own row only** | Employee grant (own row + UPDATE), manager grant (reports) |
      | department\_id | Own row + direct reports | **Direct reports only** | Employee grant (own row), manager grant (reports + UPDATE) |

      **Emma (employee only):**

      | Column | SELECT | UPDATE | Controlled by |
      |---|---|---|---|
      | employee\_id | Own row only | — | `HRAPP_EMPLOYEES_ACCESS` |
      | first\_name | Own row only | — | `HRAPP_EMPLOYEES_ACCESS` |
      | last\_name | Own row only | — | `HRAPP_EMPLOYEES_ACCESS` |
      | ssn | Own row only | — | `HRAPP_EMPLOYEES_ACCESS` |
      | salary | Own row only | — | `HRAPP_EMPLOYEES_ACCESS` |
      | phone\_number | Own row only | **Own row only** | `HRAPP_EMPLOYEES_ACCESS` |
      | department\_id | Own row only | — | `HRAPP_EMPLOYEES_ACCESS` |

      Two data grant statements produce this entire privilege matrix. With VPD, you would need separate policy functions for row filtering, column masking, and DML restrictions — each a potential point of failure. With data grants, if it's not in the grant, it doesn't exist.

3. The script will verify the `DIRECT_LOGON_ROLE` is configured correctly.

      a. Confirm the role has the `CREATE SESSION` privilege.

      ```
      <copy>
      SELECT privilege
        FROM dba_sys_privs
       WHERE grantee = 'DIRECT_LOGON_ROLE';
      </copy>
      ```

      | PRIVILEGE |
      |---|
      | CREATE SESSION |

      b. Confirm the role exists as a standard database role. Note that data roles (`HRAPP_EMPLOYEES`, `HRAPP_MANAGERS`) do not appear in `dba_role_privs` — they are tracked separately in `dba_data_role_grants`.

      ```
      <copy>
      SELECT grantee, granted_role
        FROM dba_role_privs
       WHERE granted_role = 'DIRECT_LOGON_ROLE';
      </copy>
      ```

      | GRANTEE | GRANTED\_ROLE |
      |---|---|
      | SYS | DIRECT\_LOGON\_ROLE |

      c. Confirm the role has been granted to both data roles.

      ```
      <copy>
      SELECT data_role, role_type, grantee
        FROM dba_data_role_grants
       WHERE data_role = 'DIRECT_LOGON_ROLE'
       ORDER BY grantee;
      </copy>
      ```

      | DATA\_ROLE | ROLE\_TYPE | GRANTEE |
      |---|---|---|
      | DIRECT\_LOGON\_ROLE | DATABASE ROLE | HRAPP\_EMPLOYEES |
      | DIRECT\_LOGON\_ROLE | DATABASE ROLE | HRAPP\_MANAGERS |

You have completed the setup for end users, data roles, data grants, and role-to-role bindings.

## Task 6: Connect and verify as Marvin

> **Script:**

```
<copy>
./dg_connect_as_marvin.sh
</copy>
```

**The Proof:** Connect as Marvin and confirm Oracle has correctly established his identity before running any queries. The script will verify who the database thinks he is, which data roles are active, and what value the data grant predicates will match against.

1. The script will connect as Marvin using his end user credentials.

      ```
      <copy>
      sqlplus marvin/Oracle123@pdb1
      </copy>
      ```

2. The script will verify Marvin's authentication details. `CURRENT_USER` will show `XS$NULL` — end users are not schema users. `AUTHENTICATED_IDENTITY` shows the end user name Oracle resolved from the session.

      ```
      <copy>
      SELECT
          SYS_CONTEXT('USERENV','CURRENT_USER')           AS CURRENT_USER,
          SYS_CONTEXT('USERENV','AUTHENTICATED_IDENTITY') AS AUTHENTICATED_IDENTITY,
          SYS_CONTEXT('USERENV','ENTERPRISE_IDENTITY')    AS ENTERPRISE_IDENTITY,
          SYS_CONTEXT('USERENV','AUTHENTICATION_METHOD')  AS AUTH_METHOD,
          SYS_CONTEXT('USERENV','IDENTIFICATION_TYPE')    AS ID_TYPE
      FROM DUAL;
      </copy>
      ```

      | CURRENT\_USER | AUTHENTICATED\_IDENTITY | ENTERPRISE\_IDENTITY | AUTH\_METHOD | ID\_TYPE |
      |---|---|---|---|---|
      | XS$NULL | MARVIN | null | PASSWORD | XS |

      **NOTE:** `XS$NULL` acts as a placeholder for database sessions that do not have a corresponding database schema user, often used to indicate an active application user session in Oracle Deep Data Security or Oracle Real Application Security. It has no privileges and cannot own objects.

3. Next, it will verify which data roles are active. Both `HRAPP_EMPLOYEES` and `HRAPP_MANAGERS` were granted to Marvin in Task 3 and activate automatically when he authenticates. The database roles were bound to the data roles in Task 5.

      ```
      <copy>
      SELECT ROLE_NAME FROM V$END_USER_DATA_ROLE;
      </copy>
      ```

      | ROLE\_NAME |
      |---|
      | HRAPP\_EMPLOYEES |
      | XSAUTHENTICATED |
      | DBMS\_AUTH |
      | DBMS\_PASSWD |
      | HRAPP\_EMPLOYEES |
      | HRAPP\_MANAGERS |

4. It will verify the username the data grants will use. `ora_end_user_context.USERNAME` is the value evaluated in the data grant `WHERE` predicate at query time — it must match the `user_name` column in `hr.employees`.

      ```
      <copy>
      SELECT ora_end_user_context.username FROM DUAL;
      </copy>
      ```

      | ORA\_END\_USER\_CONTEXT.USERNAME |
      |---|
      | MARVIN |

5. The script will display the full end user context in JSON notation. You can exclude the `.USERNAME` from the `ora_end_user_context` SQL function to see the full context. This example uses the `json_serialize` function to make it easier to read.

      ```
      <copy>
      SET LONG 90000
      SELECT json_serialize(
          ora_end_user_context returning varchar2 pretty) AS context
      FROM DUAL;
      </copy>
      ```

      ```json
      CONTEXT
      -----------------------------------------------------------------------------
      {
        "SERVER_HOST" : "your-db-host",
        "CURRENT_USER" : "XS$NULL",
        "AUTHENTICATION_METHOD" : "PASSWORD",
        "AUTHENTICATED_IDENTITY" : "MARVIN",
        "CURRENT_SCHEMA" : "XS$NULL",
        "LOGON_END_USER" : "MARVIN",
        "CURRENT_END_USER" : "MARVIN",
        "SESSION_USER" : "XS$NULL",
        "USERNAME" : "MARVIN",
        "IDENTIFICATION_TYPE" : "XS",
        ...
      }
      ```

      Key fields to note: `IDENTIFICATION_TYPE` is `XS` (not `LOCAL` or `GLOBAL`), `CURRENT_END_USER` and `LOGON_END_USER` both resolve to `MARVIN`, and `SESSION_USER` is `XS$NULL` confirming this is not a schema user.

6. It will verify the active session roles. These are the standard database roles active in Marvin's session — inherited through the data roles.

      ```
      <copy>
      SELECT * FROM SESSION_ROLES ORDER BY 1;
      </copy>
      ```

      | ROLE |
      |---|
      | DIRECT\_LOGON\_ROLE |
      | EMPLOYEE\_CONTEXT\_ADMIN |

      This is role-to-role binding at work. Both database roles are present because they were bound to `HRAPP_EMPLOYEES` and `HRAPP_MANAGERS` in Tasks 4 and 5. When those data roles activated at login, the bound database roles activated with them:

      - **`DIRECT_LOGON_ROLE`** — holds `CREATE SESSION`, which is what allows Marvin's direct end user login to the database to succeed.
      - **`EMPLOYEE_CONTEXT_ADMIN`** — holds `EXECUTE` on `hr.ctx_pkg`, which is required for the `o:onFirstRead` trigger to fire `init_user_context` and populate `ORA_END_USER_CONTEXT.HR.EMP_CTX.ID`. Marvin cannot call the procedure directly to modify his context — the internal `UPDATE END_USER_CONTEXT` statement requires `UPDATE ANY END USER CONTEXT`, a system privilege granted only to the HR schema. The role exists solely to enable the automatic trigger.

7. Marvin asks the AI agent: "Show me my team." The script will run the query the AI agent would produce.

      ```
      <copy>
      SELECT employee_id, first_name, last_name, ssn, salary, department_id, manager_id
        FROM hr.employees
       ORDER BY employee_id;
      </copy>
      ```

      Marvin sees **4 rows** — himself and his 3 direct reports (Emma, Charlie, Dana). He cannot see Bob, Fiona, or Grace because they are not in his reporting chain.

      | EMPLOYEE\_ID | FIRST\_NAME | LAST\_NAME | SSN | SALARY | DEPARTMENT\_ID | MANAGER\_ID |
      |---|---|---|---|---|---|---|
      | 2 | Marvin | Morgan | 222-22-2222 | 175000 | 1 | 1 |
      | 3 | Emma | Baker | | 120000 | 1 | 2 |
      | 4 | Charlie | Davis | | 95000 | 1 | 2 |
      | 5 | Dana | Lee | | 130000 | 1 | 2 |

      - **Marvin sees his own salary** — his row is covered by `HRAPP_EMPLOYEES_ACCESS`, which includes `salary`.
      - **SSN is NULL for his direct reports** — `HRAPP_MANAGER_ACCESS` excludes SSN; his own SSN is visible because `HRAPP_EMPLOYEES_ACCESS` explicitly includes it.

8. The script will inspect the end user context. The `o:onFirstRead` trigger populated Marvin's employee ID when the manager grant predicate first evaluated `ORA_END_USER_CONTEXT.HR.EMP_CTX.ID`.

      ```
      <copy>
      SELECT ora_end_user_context.HR FROM DUAL;
      </copy>
      ```

      ```json
      {"EMP_CTX":{"ID":2}}
      ```

      The context is set because the manager grant predicate (`WHERE manager_id = ORA_END_USER_CONTEXT.HR.EMP_CTX.ID`) read the `ID` attribute during query execution, which fired `o:onFirstRead` and called `hr.ctx_pkg.init_user_context` to resolve and store Marvin's employee ID.

9. The script will update a team member's salary as Marvin. Because Marvin has the `MANAGERS` role, he can update salary and department for his direct reports. This is something Emma cannot do.

      ```
      <copy>
      UPDATE hr.employees
         SET salary = 125000
       WHERE first_name = 'Emma';
      COMMIT;
      </copy>
      ```

      The update succeeds. Verify:

      ```
      <copy>
      SELECT first_name, salary FROM hr.employees WHERE first_name = 'Emma';
      </copy>
      ```

      | FIRST\_NAME | SALARY |
      |---|---|
      | Emma | 125000 |

10. Next, it will attempt to update Marvin's own salary.

      ```
      <copy>
      UPDATE hr.employees
         SET salary = salary*1.5
       WHERE employee_id = 2;
      </copy>
      ```

      ```
      0 rows updated.
      ```

      No error — but no rows changed either. The manager grant's `UPDATE` predicate is `WHERE manager_id = ORA_END_USER_CONTEXT.HR.EMP_CTX.ID`, which matches rows where `manager_id = 2` — his direct reports. Marvin's own row has `manager_id = 1` (he reports to Grace), so the data grant's row filter silently excludes it from the update. `HRAPP_EMPLOYEES_ACCESS` has no `UPDATE` privilege at all. The result is the same as if the row does not exist — the database does not tell him why, it simply updates nothing. Even if an AI agent were tricked into generating this statement, the database enforces the boundary.

11. Finally, the script will show what Marvin can view or update per column, per row.

      ```
      <copy>
      SELECT first_name,
        ORA_CHECK_DATA_PRIVILEGE(emp, 'SELECT', ssn)          AS view_ssn,
        ORA_CHECK_DATA_PRIVILEGE(emp, 'UPDATE', ssn)          AS update_ssn,
        ORA_CHECK_DATA_PRIVILEGE(emp, 'SELECT', salary)       AS view_salary,
        ORA_CHECK_DATA_PRIVILEGE(emp, 'UPDATE', salary)       AS update_salary,
        ORA_CHECK_DATA_PRIVILEGE(emp, 'SELECT', phone_number) AS view_phone,
        ORA_CHECK_DATA_PRIVILEGE(emp, 'UPDATE', phone_number) AS update_phone
        FROM hr.employees emp;
      </copy>
      ```

      | FIRST\_NAME | VIEW\_SSN | UPDATE\_SSN | VIEW\_SALARY | UPDATE\_SALARY | VIEW\_PHONE | UPDATE\_PHONE |
      |---|---|---|---|---|---|---|
      | Marvin | TRUE | FALSE | TRUE | FALSE | TRUE | TRUE |
      | Emma | FALSE | FALSE | TRUE | TRUE | TRUE | FALSE |
      | Charlie | FALSE | FALSE | TRUE | TRUE | TRUE | FALSE |
      | Dana | FALSE | FALSE | TRUE | TRUE | TRUE | FALSE |

      Two grants, one session. Marvin's own row follows `HRAPP_EMPLOYEES_ACCESS` rules; his direct reports follow `HRAPP_MANAGER_ACCESS` rules. The AI agent can use this output to decide which fields to surface as editable.

      This is something VPD cannot do natively. VPD can filter rows and mask columns, but it has no built-in way to report per-row, per-column authorization back to the calling application. `ORA_CHECK_DATA_PRIVILEGE` is unique to data grants and gives your AI agent a programmatic way to discover what it can and cannot do — before it tries.

## Task 7: Connect and verify as Emma

> **Script:**

```
<copy>
./dg_connect_as_emma.sh
</copy>
```

**The Contrast:** The script will connect as Emma and run the same identity checks and the same query. The session context will look different — fewer data roles, a different username — and the query results will be completely different, enforced by the same data grants you already created.

1. The script will connect as Emma using her end user credentials.

      ```
      <copy>
      sqlplus emma/Oracle123@pdb1
      </copy>
      ```

2. It will verify Emma's data roles. The authentication information will be similar but based on Emma's end user identity. The key difference is that Emma only has `HRAPP_EMPLOYEES` granted to her, so that is the only data role that activates in her session.

      ```
      <copy>
      SELECT ROLE_NAME FROM V$END_USER_DATA_ROLE;
      </copy>
      ```

      | ROLE\_NAME |
      |---|
      | HRAPP\_EMPLOYEES |
      | XSAUTHENTICATED |
      | DBMS\_AUTH |
      | DBMS\_PASSWD |
      | HRAPP\_EMPLOYEES |


3. Emma asks the AI agent: *"Show me my employee details."* The script will run the exact same query Marvin ran.

      ```
      <copy>
      SELECT employee_id, first_name, last_name, ssn, salary, department_id, manager_id
        FROM hr.employees
       ORDER BY employee_id;
      </copy>
      ```

      Emma sees **1 row** — only herself. She can see her own SSN and her own salary (both are her data). Notice her salary reflects the raise Marvin gave her in Task 6. She cannot see Marvin, Charlie, Dana, or anyone else.

      | EMPLOYEE\_ID | FIRST\_NAME | LAST\_NAME | SSN | SALARY | DEPARTMENT\_ID | MANAGER\_ID |
      |---|---|---|---|---|---|---|
      | 3 | Emma | Baker | 333-33-3333 | 125000 | 1 | 2 |

      **Same query. Same table. Same AI agent. Completely different results — enforced by the database.**

4. The script will inspect the end user context.

      ```
      <copy>
      SELECT ora_end_user_context.HR FROM DUAL;
      </copy>
      ```

      ```
      (no rows returned)
      ```

      Emma's context is empty. The `o:onFirstRead` trigger on `ORA_END_USER_CONTEXT.HR.EMP_CTX.ID` only fires when that attribute is read. In Emma's session, only `HRAPP_EMPLOYEES_ACCESS` is active — its predicate uses `ora_end_user_context.USERNAME`, not `ORA_END_USER_CONTEXT.HR.EMP_CTX.ID`. The manager grant predicate that reads the `ID` attribute never executes, so `o:onFirstRead` never fires, and `hr.ctx_pkg.init_user_context` is never called. The context remains uninitialized. This is by design — the lazy initialization means the lookup only runs for sessions that actually need it.

5. The script will attempt to update Emma's own salary. Since she has the `HRAPP_EMPLOYEES` role and the only column with `UPDATE` is `PHONE_NUMBER`, attempting to update `SALARY` should fail.

      ```
      <copy>
      UPDATE hr.employees SET salary = 200000 WHERE first_name = 'Emma';
      </copy>
      ```

      ```
      0 rows updated.
      ```

      Again, no error but no rows were changed. Emma has `UPDATE` privileges on the `PHONE_NUMBER` column but not any other column.

6. Next, it will attempt to update Emma's phone number to verify she can perform an `UPDATE` on her `PHONE_NUMBER` but not everyone's. The script will rollback without committing.

      - It will attempt to update her own phone number.

      ```
      <copy>
      UPDATE hr.employees SET phone_number = '555-555-5555' WHERE first_name = 'Emma';
      </copy>
      ```

      ```
      1 row updated.
      ```

      - Then it will attempt the update for everyone except Emma.

      ```
      <copy>
      UPDATE hr.employees SET phone_number = '555-555-5555' WHERE first_name <> 'Emma';
      </copy>
      ```

      ```
      0 rows updated.
      ```

      - Finally, it will rollback.

      ```
      <copy>
      ROLLBACK;
      </copy>
      ```

      ```
      Rollback complete.
      ```

7. The script will verify what Emma can and cannot access. `ORA_CHECK_DATA_PRIVILEGE` lets your AI agent check both read and write access per column programmatically — useful for adjusting LLM prompts or building dynamic UI that shows only editable fields.

      ```
      <copy>
      SELECT first_name,
        ORA_CHECK_DATA_PRIVILEGE(emp, 'SELECT', ssn)          AS view_ssn,
        ORA_CHECK_DATA_PRIVILEGE(emp, 'UPDATE', ssn)          AS update_ssn,
        ORA_CHECK_DATA_PRIVILEGE(emp, 'SELECT', salary)       AS view_salary,
        ORA_CHECK_DATA_PRIVILEGE(emp, 'UPDATE', salary)       AS update_salary,
        ORA_CHECK_DATA_PRIVILEGE(emp, 'SELECT', phone_number) AS view_phone,
        ORA_CHECK_DATA_PRIVILEGE(emp, 'UPDATE', phone_number) AS update_phone
        FROM hr.employees emp;
      </copy>
      ```

      | FIRST\_NAME | VIEW\_SSN | UPDATE\_SSN | VIEW\_SALARY | UPDATE\_SALARY | VIEW\_PHONE | UPDATE\_PHONE |
      |---|---|---|---|---|---|---|
      | Emma | TRUE | FALSE | TRUE | FALSE | TRUE | TRUE |

      Emma can view her SSN, salary, and phone number — but can only modify her phone number. SSN and salary are read-only for her. The agent can use this to gate which fields appear as editable in a UI or to avoid suggesting updates it knows will fail.

## Task 8: Same query, three users, three results

> **Script:**

```
<copy>
./dg_query_compare.sh
</copy>
```

**The Demo:** This is the moment that makes data grants click. The script will run the exact same `SELECT` statement three times — as SYSTEM (DBA), as Marvin (manager), and as Emma (employee). The SQL never changes. The data does.

```
<copy>
SELECT employee_id, first_name, last_name, ssn, salary, department_id, manager_id
  FROM hr.employees
 ORDER BY employee_id;
</copy>
```

| User | Rows returned | SSN visible | Salary visible | Can UPDATE salary | Can UPDATE phone |
|---|---|---|---|---|---|
| **SYSTEM** (DBA) | 7 — all employees | All 7 | All 7 | All (traditional grant) | All (traditional grant) |
| **Marvin** (manager) | 4 — self + 3 reports | Own only | All 4 | 3 reports only | Own only |
| **Emma** (employee) | 1 — self only | Own only | Own only | No | Own only |

Same SQL. Same table. Same AI agent. Three completely different results — enforced by Oracle Deep Data Security, not by application code.

This is the privilege model in action. The query is identical. The WHERE clause is identical (there isn't one — it's `ORDER BY employee_id`). The difference is entirely in the data grants. SYSTEM sees everything because it's a traditional schema user not governed by data grants. Marvin and Emma are end users — their access is defined solely by the data grants attached to their data roles.

## Task 9: Marvin changes roles

> **Script:**

```
<copy>
./dg_marvin_role_change.sh
</copy>
```

**The Point:** Oracle data grants require zero code changes when a user's role changes. The script will revoke the `HRAPP_MANAGERS` data role from Marvin, simulating a real org change where he moves to a special project with no direct reports. The next time he connects, Oracle automatically enforces his new, reduced access. No application deploys.

1. The script will revoke the `HRAPP_MANAGERS` data role from Marvin as your DBA user.

      ```
      <copy>
      REVOKE DATA ROLE hrapp_managers FROM marvin;
      </copy>
      ```

      **Note:** The change takes effect on Marvin's next session — any existing active sessions are not affected.

2. It will connect as Marvin with a new session.

      ```
      <copy>
      sqlplus marvin/Oracle123@pdb1
      </copy>
      ```

3. It will verify that only `HRAPP_EMPLOYEES` is now active. `HRAPP_MANAGERS` is no longer granted to Marvin, so it does not activate.

      ```
      <copy>
      SELECT ROLE_NAME FROM V$END_USER_DATA_ROLE;
      </copy>
      ```

      | ROLE\_NAME |
      |---|
      | HRAPP\_EMPLOYEES |
      | XSAUTHENTICATED |
      | DBMS\_AUTH |
      | DBMS\_PASSWD |
      | HRAPP\_EMPLOYEES |

4. The script will run the same query Marvin ran in Task 6. He now sees only his own row — identical to Emma's experience — because only the employee grant is active.

      ```
      <copy>
      SELECT employee_id, first_name, last_name, ssn, salary, department_id, manager_id
        FROM hr.employees
       ORDER BY employee_id;
      </copy>
      ```

      | EMPLOYEE\_ID | FIRST\_NAME | LAST\_NAME | SSN | SALARY | DEPARTMENT\_ID | MANAGER\_ID |
      |---|---|---|---|---|---|---|
      | 2 | Marvin | Morgan | 222-22-2222 | 175000 | 1 | 1 |

      Marvin still sees his own SSN and salary — both come from `HRAPP_EMPLOYEES_ACCESS`, which is still active. His direct reports are completely gone from the result set because `HRAPP_MANAGERS` is no longer granted.

5. It will verify his column authorization has also changed.

      ```
      <copy>
      SELECT first_name,
        ORA_CHECK_DATA_PRIVILEGE(emp, 'SELECT', ssn)          AS view_ssn,
        ORA_CHECK_DATA_PRIVILEGE(emp, 'UPDATE', ssn)          AS update_ssn,
        ORA_CHECK_DATA_PRIVILEGE(emp, 'SELECT', salary)       AS view_salary,
        ORA_CHECK_DATA_PRIVILEGE(emp, 'UPDATE', salary)       AS update_salary,
        ORA_CHECK_DATA_PRIVILEGE(emp, 'SELECT', phone_number) AS view_phone,
        ORA_CHECK_DATA_PRIVILEGE(emp, 'UPDATE', phone_number) AS update_phone
        FROM hr.employees emp;
      </copy>
      ```

      | FIRST\_NAME | VIEW\_SSN | UPDATE\_SSN | VIEW\_SALARY | UPDATE\_SALARY | VIEW\_PHONE | UPDATE\_PHONE |
      |---|---|---|---|---|---|---|
      | Marvin | TRUE | FALSE | TRUE | FALSE | TRUE | TRUE |

      Marvin's column authorization now matches Emma's exactly. He can view SSN, salary, and phone — and update only his phone number. Manager-level UPDATE on salary is gone. No application code changed. The sole change was a single `REVOKE DATA ROLE` statement.

      Compare this to the same scenario with VPD: you would need to update the policy function's logic, test it, and redeploy — and if the function is shared across multiple policies, you risk breaking other access paths. With OLS, you would need to relabel Marvin's clearance. With data grants, you revoke a role. One statement. Immediate effect on next session.

      **This is the power of data roles and data grants: access policy is declared at the database layer and enforced automatically.**

6. **Restore Marvin's manager role** (optional). If you want to continue exploring or re-run earlier tasks:

      > **Script:**

      ```
      <copy>
      ./dg_marvin_role_restore.sh
      </copy>
      ```

      ```
      <copy>
      GRANT DATA ROLE hrapp_managers TO marvin;
      </copy>
      ```

## Task 10 (Optional): Clean up

> **Script:**

```
<copy>
./dg_cleanup.sh
</copy>
```

If you want to remove everything created in this lab and start fresh, run the script above.

1. The script will drop the context data grant. This must be run as **SYS** because it was created on a SYS-owned table.

      ```
      <copy>
      DROP DATA GRANT hr.EMPLOYEE_CONTEXT_GRANT;
      </copy>
      ```

2. It will drop the remaining data grants, end user context, package, roles, and schema.

      ```
      <copy>
      DROP DATA GRANT hr.HRAPP_EMPLOYEES_ACCESS;
      DROP DATA GRANT hr.HRAPP_MANAGER_ACCESS;
      DROP END USER CONTEXT HR.EMP_CTX;
      DROP ROLE employee_context_admin;
      DROP ROLE direct_logon_role;
      DROP DATA ROLE HRAPP_EMPLOYEES;
      DROP DATA ROLE HRAPP_MANAGERS;
      DROP END USER emma;
      DROP END USER marvin;
      DROP USER hr CASCADE;
      </copy>
      ```

      `DROP USER hr CASCADE` removes the HR schema along with the `ctx_pkg` package, the `employees` table, and all dependent objects.

3. Finally, it will verify everything is removed.

      ```
      <copy>
      SELECT data_role, mapped_to FROM dba_data_roles
       WHERE data_role IN ('HRAPP_EMPLOYEES', 'HRAPP_MANAGERS');

      SELECT grant_name FROM dba_data_grants
       WHERE owner = 'HR';

      SELECT username FROM dba_users
       WHERE username = 'HR';

      SELECT role FROM dba_roles
       WHERE role IN ('EMPLOYEE_CONTEXT_ADMIN', 'DIRECT_LOGON_ROLE');
      </copy>
      ```
      All queries should return no rows.

## What You Built

**Mission Accomplished:** You've configured database-level security for an AI copilot that serves users with different access levels. Marvin sees his team with salaries, can update compensation and department assignments but not his own compensation. Emma sees only her own record with her SSN and salary and can only modify her phone number.

The AI agent runs the same SQL for both — the data grants do the rest. Sensitive data never reaches the LLM for unauthorized users, and unauthorized reads or writes are blocked at the kernel level.

The trust chain is unbroken: **end user authentication → Oracle data role → data grant enforcement**. No single layer can be bypassed independently.

Your copilot and AI agents are now secure by design.

### Summary: Data Grants vs. Traditional Approaches

| | VPD | RAS | OLS | **Data Grants** |
|---|---|---|---|---|
| **Security lives on** | Table (policy function) | Application (session context) | Row (labels) | **The grant itself** |
| **Default access** | All rows | All rows | All rows | **No rows** |
| **Row filtering** | PL/SQL function | ACLs | Row labels | **WHERE predicate in grant** |
| **Column control** | Separate masking policy | ACL columns | Column-level policy | **In the same grant statement** |
| **DML control** | Separate per-statement policies | ACL privileges | Separate per-label rules | **In the same grant statement** |
| **Override possible?** | `EXEMPT ACCESS POLICY` | Direct SQL bypasses app | `SA_SYSDBA`, `FULL` access | **No override privilege** |
| **Per-row, per-column audit** | Manual (custom code) | Manual (custom code) | Manual (custom code) | **`ORA_CHECK_DATA_PRIVILEGE`** |
| **Role change** | Update function logic, redeploy | Update ACLs, update app | Relabel user clearance | **`REVOKE DATA ROLE` — one statement** |
| **Objects to maintain** | Policy function + policy attachment + traditional grant | ACLs + security classes + app session config | Labels + compartments + clearances + policy | **One `CREATE DATA GRANT` statement** |

| Component | Purpose |
|---|---|
| **End users** | `marvin` and `emma` — Oracle Database end users authenticated by password, not schema owners |
| **Data roles** | `HRAPP_EMPLOYEES` and `HRAPP_MANAGERS` auto-activate based on grants to the end user |
| **`HRAPP_EMPLOYEES_ACCESS`** (SELECT, specific columns) + (UPDATE, phone number) | Highly limited: employees see only their own row and can only update one column |
| **`HRAPP_MANAGER_ACCESS`** (SELECT + UPDATE in one grant) | Managers see their team with salaries (SSN hidden), can update salary and department |
| **`user_name` / `manager_id`** | Identity columns that link rows to end users — data grants match against `ora_end_user_context.username` |
| **`DIRECT_LOGON_ROLE`** | Database role granting `CREATE SESSION` to data roles |


## Learn More

* [Oracle AI Database 26ai Documentation](https://docs.oracle.com/en/database/)

## Acknowledgements
* **Author** - Oracle Database Security Product Management
* **Last Updated By/Date** - March 2026

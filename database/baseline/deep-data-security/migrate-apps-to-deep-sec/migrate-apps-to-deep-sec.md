# Oracle Deep Data Security for Developers

Welcome to this **Oracle Deep Data Security LiveLabs** workshop.

This lab walks you through migrating an application from traditional Oracle Database users, roles, and grants to Oracle Deep Data Security end users, data roles, and data grants. You will start with a working application that connects as a shared service account, then migrate it — step by step — so the database enforces per-user access with zero application filtering code.

Estimated Time: 45 minutes

## The Problem with Shared Service Accounts

Most applications today connect to the database with a single shared service account:

```
All users → Application → Service Account (hr) → Database
                ↓
        App filters data     ← You trust the app to get this right
```

The service account sees **all** the data. The application is responsible for filtering — checking who is logged in, looking up their permissions, appending WHERE clauses, hiding columns. This works, but it is fragile:

- A bug in the filtering logic leaks data
- A prompt injection in a copilot bypasses the filter
- A new endpoint forgets to apply the filter
- A DBA queries the table directly and sees everything

Oracle Deep Data Security moves the enforcement into the database kernel. The application connects as the **end user**, not a shared account, and the database enforces what each user can see:

```
Marvin → Application → End User (marvin) → Database
                                              ↓
                                    Data grants filter     ← Database enforces this
Emma  → Application → End User (emma)  → Database
                                              ↓
                                    Data grants filter     ← Same query, different data
```

Same SQL. Zero application filtering. The security is on the grant, not the code.

### Why the boundary moves into the database

For decades, your application was the gatekeeper. Before any query reached the database, your code had already checked who the user was, decided what they were allowed to do, and built a SQL statement constrained to their slice of the data. The shared service account was acceptable because the application was trusted to get this right every time, on every endpoint, in every code path.

That trust is fragile. A prompt injection in a copilot, a misconfigured endpoint, a forgotten filter on a new feature — any one of them exposes data the user was never authorized to see. And the harder your app works to enforce the boundary in code, the more places there are for it to break.

Oracle Deep Data Security extends the user identity you already authenticate all the way down to the SQL kernel. The application stays simple — connect as the end user, run the query — and the database returns only what that user is authorized to see. You write less code, not more, and the boundary becomes something your security team can actually verify.

## What You Will Learn

1. What changes on the **database side** (end users, data roles, data grants replace traditional users, roles, and grants)
2. What changes in **application code** (spoiler: almost nothing)
3. How to migrate a **Spring Boot (Java)** application
4. How to migrate a **Django (Python)** application
5. When you need the **JDBC End User Security Context SPI** (OAuth2/Entra ID) vs. direct password authentication

## Prerequisites

This lab assumes:

- An **Oracle AI Database 26ai** instance with TCPS listener on port 2484
- `SYSTEM` and `SYS` access to a pluggable database (e.g., PDB9)
- **Java 17+** for the Spring Boot app
- **Python 3.12** for the Django app
- Both sample apps are available in `apps/sample-app-springboot/` and `apps/sample-app-django/`

## Task 0: Download lab scripts

1. Open a Terminal session on your **DBSec-Lab** VM as OS user *oracle* and `cd` to the livelabs directory.

    ````
    <copy>cd livelabs</copy>
    ````

2. Download the bundled script archive for this lab.

    ````
    <copy>wget https://objectstorage.us-ashburn-1.oraclecloud.com/p/YF6sMiIiK1t7AgWJPmKSVtb4diy3quwl2cBPx1LLwUIWEjIL0G6fPq1pYRKhGlks/n/oradbclouducm/b/dbsec_public/o/migrate-apps-to-deep-sec.zip</copy>
    ````

3. Extract the archive.

    ````
    <copy>tar xvf dbsec-livelabs-migrate-apps-to-deep-sec.tar.gz</copy>
    ````

4. Move into the lab directory.

    ````
    <copy>cd migrate-apps-to-deep-sec</copy>
    ````

5. List files to confirm the scripts and sample apps are present.

    ````
    <copy>ls</copy>
    ````

## Task 1: Understand the traditional application

Before migrating, let's understand what a traditional application looks like. The "before" state is a typical pattern: a shared service account with `SELECT` granted on the data.

### Traditional database setup

```sql
-- A schema user that owns the data
CREATE USER hr IDENTIFIED BY Oracle123;
GRANT CREATE SESSION TO hr;
GRANT UNLIMITED TABLESPACE TO hr;

-- The HR user creates and owns the employees table
CREATE TABLE hr.employees (
  employee_id   NUMBER PRIMARY KEY,
  first_name    VARCHAR2(50),
  last_name     VARCHAR2(50),
  job_code      VARCHAR2(10),
  department_id NUMBER,
  ssn           VARCHAR2(20),
  phone_number  VARCHAR2(30),
  salary        NUMBER(10,2),
  user_name     VARCHAR2(128),
  manager_id    NUMBER
);

-- Application connects as HR and sees everything
SELECT * FROM hr.employees;
-- Returns ALL 7 rows, ALL columns, for EVERY user
```

### Traditional application code (Java)

```java
// application.properties
spring.datasource.url=jdbc:oracle:thin:@//dbhost:1521/pdb
spring.datasource.username=hr          // ← shared service account
spring.datasource.password=Oracle123

// Repository — same query for everyone
public List<Employee> findAll() {
    return jdbcTemplate.query(
        "SELECT * FROM employees ORDER BY employee_id",
        rowMapper
    );
}

// Controller — app must filter based on logged-in user
public List<Employee> getEmployees(@AuthenticationPrincipal User user) {
    List<Employee> all = repository.findAll();
    if (user.hasRole("MANAGER")) {
        return all.stream()
            .filter(e -> e.getManagerId() == user.getEmployeeId()
                      || e.getEmployeeId() == user.getEmployeeId())
            .collect(Collectors.toList());
    } else {
        return all.stream()
            .filter(e -> e.getUserName().equals(user.getUsername()))
            .collect(Collectors.toList());
    }
}
```

### Traditional application code (Python)

```python
# settings.py
ORACLE_DSN = '...'
ORACLE_USER = 'hr'            # ← shared service account
ORACLE_PASSWORD = 'Oracle123'

# views.py — app must filter
def employee_list(request):
    conn = get_connection('hr', 'Oracle123')  # shared account
    employees = fetch_all_employees(conn)
    user = request.session['username']
    if user_is_manager(user):
        employees = [e for e in employees
                     if e['manager_id'] == get_employee_id(user)
                     or e['user_name'] == user]
    else:
        employees = [e for e in employees if e['user_name'] == user]
    return render(request, 'employees.html', {'employees': employees})
```

**The problem:** Every endpoint, every query, every new feature must remember to apply the filter. The database returns everything — it is up to the code to get it right.

### Try it: Create the traditional setup and see the problem

Run these scripts to create the traditional HR schema and see what the shared service account exposes:

```bash
./01_create_hr_schema.sh        # Create HR with password auth + employee data
./02_show_traditional_app.sh    # Connect as HR — see ALL 7 rows, ALL SSNs
```

`01_create_hr_schema.sh` creates the traditional `HR` user with `IDENTIFIED BY Oracle123`, the `EMPLOYEES` table, and 7 sample employees. `02_show_traditional_app.sh` connects as the shared service account and runs `SELECT * FROM hr.employees` — showing that any application connecting as HR sees everything.

## Task 2: Migrate the database objects

This is the bulk of the migration. You replace traditional users, roles, and grants with their Deep Data Security equivalents.

### Side-by-side comparison

| Traditional | Deep Data Security | Purpose |
|---|---|---|
| `CREATE USER hr IDENTIFIED BY Oracle123` | `CREATE USER hr NO AUTHENTICATION` | HR becomes a schema-only owner — it no longer logs in |
| `CREATE USER marvin IDENTIFIED BY ...` | `CREATE END USER marvin IDENTIFIED BY Oracle123` | Marvin is an **end user**, not a schema user |
| `CREATE ROLE manager_role` | `CREATE DATA ROLE hrapp_managers_local` | Data roles replace traditional roles for data access |
| `GRANT SELECT ON hr.employees TO manager_role` | `CREATE DATA GRANT ... ON hr.employees ... TO HRAPP_MANAGERS_LOCAL` | Data grants define WHAT rows/columns a role can access |
| `GRANT manager_role TO marvin` | `GRANT DATA ROLE hrapp_managers_local TO marvin` | Granting works the same way |

### Key differences

1. **End users are not schema users.** They authenticate but land in `XS$NULL` — they own nothing and have no default privileges. This is the principle of least privilege by default.

2. **Data grants combine access + filtering in one statement.** A traditional `GRANT SELECT` gives access to the entire table. A data grant specifies which columns, which rows, and which DML operations:

      ```sql
      -- Traditional: all-or-nothing
      GRANT SELECT ON hr.employees TO some_role;

      -- Deep Data Security: precise control
      CREATE DATA GRANT hr.HRAPP_EMPLOYEES_LOCAL_ACCESS
        AS SELECT (employee_id, first_name, last_name, user_name,
                   department_id, manager_id, ssn, salary, phone_number),
           UPDATE(phone_number)
        ON hr.employees
        WHERE upper(user_name) = upper(ora_end_user_context.username)
        TO HRAPP_EMPLOYEES_LOCAL;
      ```

3. **No access without a data grant.** An end user without a data grant gets `ORA-00942: table or view does not exist`. There is nothing to bypass — no `GRANT SELECT` to forget to revoke, no VPD function to get wrong.

4. **`CREATE SESSION` is granted via a database role on the data role**, not directly to the end user:

      ```sql
      CREATE ROLE direct_logon_role;
      GRANT CREATE SESSION TO direct_logon_role;
      GRANT direct_logon_role TO hrapp_employees_local;
      ```

### Try it: Run the migration scripts

Run these scripts to perform the migration. They convert the traditional HR schema you created in Task 1 into a Deep Data Security environment:

```bash
./03_migrate_db_objects.sh      # Lock HR (NO AUTHENTICATION), create end users,
                                # data roles, data grants, and end user context
./04_create_role_bindings.sh    # CREATE SESSION via role binding
```

`03_migrate_db_objects.sh` is the bulk of the migration. It:
1. Runs `ALTER USER hr NO AUTHENTICATION` — HR can no longer log in
2. Creates end users `marvin` and `emma`
3. Creates data roles `hrapp_employees_local` and `hrapp_managers_local`
4. Creates data grants with row/column predicates
5. Creates the end user context and initialization package
6. Creates the manager data grant

`04_create_role_bindings.sh` creates the `direct_logon_role` database role with `CREATE SESSION` and binds it to both data roles so end users can connect.

## Task 3: Migrate the application code

This is where developers are often surprised: **the code change is minimal.** And when Marvin moves to a special project with no direct reports, the DBA revokes one data role — your app deploys nothing.

### What changes

| Component | Before | After | Change |
|---|---|---|---|
| Connection credentials | Shared service account (`hr/Oracle123`) | End user credentials (`marvin/Oracle123`) | Change username/password source |
| SQL queries | Same | Same | **No change** |
| Filtering logic | Application-side WHERE clauses, if/else branches | Remove it | **Delete code** |
| Driver / dependencies | Same | Same | **No change** |

### What does NOT change

- **SQL statements** — `SELECT * FROM hr.employees` works exactly the same. The database returns only the rows and columns the end user is authorized to see.
- **JDBC driver** — No new driver version required. Standard `ojdbc11` works.
- **python-oracledb** — No new version required. Standard `oracledb` thin mode works.
- **Connection string / DSN** — Same TCPS connection descriptor.
- **ORM queries** — If you use JPA, Hibernate, Django ORM, or SQLAlchemy, the queries are unchanged. The database filters transparently.

### Spring Boot migration

**Before (shared service account):**
```java
@Configuration
public class DataSourceConfig {
    @Bean
    public DataSource dataSource() {
        OracleDataSource ds = new OracleDataSource();
        ds.setURL(url);
        ds.setUser("hr");               // ← shared account
        ds.setPassword("Oracle123");
        return ds;
    }
}
```

**After (per-user connection):**
```java
@Configuration
public class DataSourceConfig {
    // No @Bean DataSource — connections are per-request

    public Connection getConnection(String username, String password) {
        OracleDataSource ds = new OracleDataSource();
        ds.setURL(url);
        ds.setUser(username);            // ← end user credentials
        ds.setPassword(password);
        return ds.getConnection();
    }
}
```

The controller changes from injecting a shared `JdbcTemplate` to passing a per-user `Connection`:

```java
@GetMapping("/employees")
public String listEmployees(HttpSession session, Model model) {
    String user = (String) session.getAttribute("dbUser");
    String pass = (String) session.getAttribute("dbPass");

    try (Connection conn = dataSourceConfig.getConnection(user, pass)) {
        List<Employee> employees = employeeRepository.findAll(conn);
        model.addAttribute("employees", employees);
        // No filtering code — the database handles it
        return "employees";
    }
}
```

**Lines of filtering code removed:** All of them.

### Django migration

**Before (shared service account):**
```python
def _get_connection():
    return oracledb.connect(user='hr', password='Oracle123', dsn=DSN)

def employee_list(request):
    conn = _get_connection()
    employees = fetch_employees(conn)
    # Filter based on logged-in user...
    employees = [e for e in employees if ...]  # ← app filtering
    return render(request, 'employees.html', {'employees': employees})
```

**After (per-user connection):**
```python
def _get_connection(username, password):
    return oracledb.connect(user=username, password=password, dsn=DSN)

def employee_list(request):
    user = request.session['db_user']
    pwd = request.session['db_pass']
    conn = _get_connection(user, pwd)    # ← end user credentials
    employees = fetch_employees(conn)
    # No filtering — database data grants handle it
    return render(request, 'employees.html', {'employees': employees})
```

**Lines of filtering code removed:** All of them.

### Bonus: Drive your UI from the data grants

Because the database knows what each end user can read and write, your app can ask it directly — per row, per column — and use the answer to render a dynamic UI. `ORA_CHECK_DATA_PRIVILEGE` returns `TRUE` or `FALSE` for a given `SELECT` or `UPDATE` on a specific column:

```sql
SELECT first_name,
  ORA_CHECK_DATA_PRIVILEGE(emp, 'SELECT', ssn)          AS view_ssn,
  ORA_CHECK_DATA_PRIVILEGE(emp, 'UPDATE', salary)       AS update_salary,
  ORA_CHECK_DATA_PRIVILEGE(emp, 'UPDATE', phone_number) AS update_phone
  FROM hr.employees emp;
```

Hide fields the user can't read. Render fields they can't update as read-only. Your UI stays in sync with the data grants automatically — if the DBA tightens a grant tomorrow, your form reacts without a redeploy.

### Run the migrated apps

Two sample apps ship in this lab under `apps/`:

- **`apps/sample-app-springboot/`** — Spring Boot 3 + ojdbc11 on port 8090
- **`apps/sample-app-django/`** — Django + python-oracledb on port 8091 (offline-installable via bundled `wheelhouse/`)

The database side is already done by the lab scripts above. The app code itself only needed **one change** — connect as the logged-in end user instead of a shared service account. Script `07_show_app_migration.sh` displays the before/after diff for both apps, and `08_start_app.sh` starts one of them and curl-tests the Marvin + Emma login flow end-to-end:

```bash
./07_show_app_migration.sh          # Show the code diff
./08_start_app.sh                   # Prompts: springboot or django
# or: ./08_start_app.sh springboot
# or: ./08_start_app.sh django
```

Expected login result — Marvin sees **4 rows** (himself + 3 direct reports, SSN hidden for reports), Emma sees **1 row** (only herself, SSN visible).

| EMPLOYEE\_ID | FIRST\_NAME | LAST\_NAME | SSN | SALARY | DEPARTMENT\_ID | MANAGER\_ID |
|---|---|---|---|---|---|---|
| 2 | Marvin | Morgan | 222-22-2222 | 175000 | 1 | 1 |
| 3 | Emma | Baker | | 120000 | 1 | 2 |
| 4 | Charlie | Davis | | 95000 | 1 | 2 |
| 5 | Dana | Lee | | 130000 | 1 | 2 |

Log out and log back in as the other user to see the same SQL return a different result set.

| As emma | EMPLOYEE\_ID | FIRST\_NAME | LAST\_NAME | SSN | SALARY |
|---|---|---|---|---|---|
| | 3 | Emma | Baker | 333-33-3333 | 120000 |

**Same SQL. Same app code. Same table. Completely different results — enforced by the database.**

### Try it: Verify the migration from the command line

Before running the apps, verify the migration worked at the database level:

```bash
./05_verify_as_marvin.sh        # Connect as marvin — 4 rows (self + 3 reports)
./06_verify_as_emma.sh          # Connect as emma — 1 row (self only)
```

`05_verify_as_marvin.sh` connects as end user Marvin and runs the same `SELECT * FROM hr.employees` query. Marvin sees 4 rows — himself and his 3 direct reports. SSN is hidden for direct reports (the manager grant excludes it). The script also shows Marvin's active data roles, identity context, and per-column authorization using `ORA_CHECK_DATA_PRIVILEGE`.

`06_verify_as_emma.sh` does the same for Emma — she sees 1 row (herself only). Same query, completely different results.

## Task 4: Understand the two authentication paths

There are two ways end users can authenticate to the database. The path you choose depends on your identity provider.

### Path 1: Direct password authentication

This is what the sample apps use. The end user authenticates directly to the database with a username and password.

```
Browser → App login form → App connects as end user → Database
                             user=marvin
                             password=Oracle123
```

**Database setup:**
```sql
CREATE END USER marvin IDENTIFIED BY Oracle123;
```

**Code change:** Replace the shared service account credentials with the end user's credentials. That's it. No SPI, no new dependencies, no driver changes.

**Best for:**
- Internal tools and demos
- Applications that manage their own user credentials
- Migration from traditional database users where users already have passwords

### Path 2: OAuth2 / Entra ID token-based authentication

For enterprise applications where users authenticate via an identity provider (Microsoft Entra ID, OCI IAM), the JDBC driver supports an **End User Security Context SPI**. The app never sees the user's database password — it forwards the OAuth2 token.

```
Browser → Entra ID login → App receives JWT → JDBC SPI extracts JWT
                                                → Request database access token via OAuth2
                                                  → Database activates data roles from token claims
```

**Database setup:**
```sql
-- Data roles map to IAM app roles (no end users needed)
CREATE DATA ROLE hrapp_managers MAPPED TO 'azure_role=MANAGERS';
```

**Code change:** Add the `ojdbc-provider-spring` dependency and set JDBC connection properties:

```properties
# application.properties
oracle.jdbc.provider.endUserSecurityContext=ojdbc-provider-spring-end-user-security-context
oracle.jdbc.provider.endUserSecurityContext.registrationId=hrapp
```

The SPI implementation (`SpringSecurityContextProvider`) automatically:
1. Extracts the user's JWT from Spring Security's `SecurityContextHolder`
2. Uses the `hrapp` client registration to request a database access token via OAuth2
3. Passes both tokens to the JDBC driver
4. The driver sends them to the database, which activates the corresponding data roles

**SPI registration** is automatic via `META-INF/services/oracle.jdbc.spi.EndUserSecurityContextProvider`.

**Best for:**
- Enterprise applications with Entra ID or OCI IAM
- Applications that already use OAuth2 / OpenID Connect
- Zero-password architectures

### Which path should I use?

| Scenario | Path | Why |
|---|---|---|
| Internal tool, demo, PoC | Direct password | Simplest — zero new dependencies |
| Existing app with its own user table | Direct password | Map your users to end users |
| Enterprise app with Entra ID / OCI IAM | OAuth2 SPI | Token-based — no database passwords |
| Agentic application / copilot | OAuth2 SPI | User identity flows through the agent to the DB |

## Task 5: Verify the security boundary

The most important outcome of this migration: the application cannot bypass the security controls, even if it tries.

1. **Connect as Marvin and try to see all employees:**

      ```sql
      -- As marvin
      SELECT * FROM hr.employees;
      -- Returns only 4 rows — his own + 3 direct reports
      -- SSN is hidden for direct reports (manager grant excludes it)
      ```

2. **Try to access a column excluded by the data grant:**

      ```sql
      -- As marvin, try to see Bob's SSN (Bob is NOT his direct report)
      SELECT ssn FROM hr.employees WHERE first_name = 'Bob';
      -- Returns 0 rows — Bob is not visible to Marvin at all
      ```

3. **Try to update a column not in the data grant:**

      ```sql
      -- As emma, try to update salary (employee grant only allows phone_number)
      UPDATE hr.employees SET salary = 999999 WHERE employee_id = 3;
      -- ORA-01031: insufficient privileges
      ```

4. **Connect without a data grant:**

      ```sql
      -- As a new end user with no data grants
      SELECT * FROM hr.employees;
      -- ORA-00942: table or view does not exist
      ```

The database kernel enforces these controls before data leaves the SQL engine. No prompt injection, misconfigured endpoint, or application bug can circumvent them.

### Try it: Run the security boundary tests

```bash
./09_verify_security_boundary.sh    # Test all bypass attempts
```

This script runs four tests:
1. Marvin tries to see Bob's SSN — **0 rows** (Bob is invisible to Marvin)
2. Emma tries to update her salary — **0 rows updated** (only phone_number is allowed)
3. Emma tries to update Marvin's phone number — **0 rows updated** (predicate limits to own row)
4. HR tries to log in — **fails** (NO AUTHENTICATION)

## Task 6: Clean up

When you are done, run the cleanup script to remove all lab objects:

```bash
./10_cleanup.sh
```

This drops all data grants, end user context, roles, end users, and the HR schema.

### Complete script sequence

| Script | Purpose |
|---|---|
| `01_create_hr_schema.sh` | Create traditional HR with password auth + employee data |
| `02_show_traditional_app.sh` | Connect as HR shared account — see ALL 7 rows |
| `03_migrate_db_objects.sh` | Migrate: lock HR, create end users, data roles, data grants, context |
| `04_create_role_bindings.sh` | Create `direct_logon_role`, bind CREATE SESSION to data roles |
| `05_verify_as_marvin.sh` | Connect as Marvin — 4 rows, SSN hidden for reports |
| `06_verify_as_emma.sh` | Connect as Emma — 1 row, same query |
| `07_show_app_migration.sh` | Show the app-code diff: shared-account → per-user connection |
| `08_start_app.sh` | Start the Spring Boot or Django sample app; curl-test Marvin + Emma |
| `09_verify_security_boundary.sh` | Test bypass attempts: all fail |
| `10_cleanup.sh` | Stop any running apps, drop everything |

## What You Built

Your application no longer acts as the gatekeeper. It connects as the end user, runs the same SQL it always ran, and the database returns only the rows and columns that user is authorized to see. The filtering code is gone. The shared service account is gone. And the boundary is something your security team can actually verify.

The trust chain is unbroken: **end user authentication → data role → data grant enforcement.** No single layer can be bypassed independently. A prompt injection, a new endpoint, a forgotten WHERE clause — none of them can return data the user was not authorized for, because the application is no longer the thing enforcing it.

When Marvin moves to a new team, the DBA revokes one data role. When a new column becomes sensitive, the DBA tightens one data grant. When a new user joins, the DBA creates one end user. Your app deploys nothing. The code you already wrote keeps working.

## Summary: Migration checklist

### Database side
- [ ] Change the data-owning user to `NO AUTHENTICATION` (schema-only)
- [ ] Create end users for each person or service that needs access
- [ ] Create data roles (with or without `MAPPED TO` for IAM)
- [ ] Grant data roles to end users (or map them to IAM app roles)
- [ ] Create data grants with column lists, row predicates, and DML restrictions
- [ ] Create end user context if predicates need derived values (e.g., `employee_id` from `user_name`)
- [ ] Create a database role with `CREATE SESSION` and grant it to the data roles
- [ ] Grant context access (`employee_context_admin`, `EMPLOYEE_CONTEXT_GRANT` on `SYS.END_USER_CONTEXT`)

### Application side
- [ ] Replace shared service account credentials with per-user end user credentials
- [ ] Remove application-side data filtering code (WHERE clauses, if/else branches, role checks)
- [ ] **For direct auth:** Change `user=hr` to `user=<end_user>` — no new dependencies
- [ ] **For OAuth2/Entra ID:** Add `ojdbc-provider-spring` dependency and configure the SPI properties
- [ ] Test that each user sees only their authorized data
- [ ] Test that unauthorized operations return errors (not empty results with leaked columns)

### What stays the same
- [ ] SQL queries — unchanged
- [ ] JDBC driver version — unchanged
- [ ] python-oracledb version — unchanged
- [ ] Connection string / DSN — unchanged
- [ ] ORM mappings — unchanged
- [ ] HTML templates / frontend — unchanged

# sample-app-springboot

A simple Spring Boot web application that demonstrates **Oracle Deep Data Security** with end user authentication. Users log in with their Oracle Database end user credentials and the database enforces row- and column-level access through data grants — the application runs the same SQL for every user, but each user sees only the data they are authorized to see.

## Prerequisites

- **Java 17+** — the app is compiled against Java 17 (`/usr/lib/jvm/java-17` on this host)
- **Oracle AI Database 26ai** — the listener (LISTENER26) must be running on TCPS port 2484
- **HR schema** — created per the [end-user-data-grants FastLab](../../fastlab/end-user-data-grants/end-user-data-grants.md) with the `employees` table and sample data
- **Oracle wallet** — located at `/u01/app/oracle/admin/cdb9/wallet` for the TCPS connection
- **End users** — `marvin` and `emma` created as Oracle Database end users with data roles granted

### Database setup

Run the following as SYSTEM on PDB9 if not already done:

```sql
-- HR schema (no authentication — it only owns objects)
CREATE USER hr NO AUTHENTICATION;
GRANT UNLIMITED TABLESPACE TO hr;

-- Create the employees table and insert sample data (see end-user-data-grants.md Task 1)

-- End users
CREATE END USER marvin IDENTIFIED BY Oracle123;
CREATE END USER emma IDENTIFIED BY Oracle123;

-- Data roles (separate from any Entra ID-mapped roles)
CREATE DATA ROLE hrapp_employees_local;
CREATE DATA ROLE hrapp_managers_local;

-- Grant roles to end users
GRANT DATA ROLE hrapp_employees_local TO marvin;
GRANT DATA ROLE hrapp_managers_local TO marvin;
GRANT DATA ROLE hrapp_employees_local TO emma;

-- Session privileges
CREATE ROLE direct_logon_role;
GRANT CREATE SESSION TO direct_logon_role;
GRANT direct_logon_role TO hrapp_employees_local;
GRANT direct_logon_role TO hrapp_managers_local;

-- Data grants
CREATE OR REPLACE DATA GRANT hr.HRAPP_EMPLOYEES_LOCAL_ACCESS
  AS SELECT (employee_id, first_name, last_name, user_name, department_id, manager_id, ssn, salary, phone_number),
     UPDATE(phone_number)
  ON hr.employees
  WHERE upper(user_name) = upper(ora_end_user_context.username)
  TO HRAPP_EMPLOYEES_LOCAL;

CREATE OR REPLACE DATA GRANT hr.HRAPP_MANAGER_LOCAL_ACCESS
  AS SELECT (ALL COLUMNS EXCEPT ssn), UPDATE (salary, department_id)
  ON hr.employees
  WHERE manager_id = ORA_END_USER_CONTEXT.HR.EMP_CTX.ID
  TO HRAPP_MANAGERS_LOCAL;

-- End user context (see end-user-data-grants.md Task 2 steps 4-5 for context + package)
-- Context data grant (run as SYS):
CREATE OR REPLACE DATA GRANT hr.EMPLOYEE_CONTEXT_GRANT
  AS SELECT ON SYS.END_USER_CONTEXT
   WHERE OWNER = 'HR' AND NAME = 'EMP_CTX'
    TO HRAPP_EMPLOYEES_LOCAL, HRAPP_MANAGERS_LOCAL;

-- Context package access
GRANT employee_context_admin TO HRAPP_EMPLOYEES_LOCAL;
GRANT employee_context_admin TO HRAPP_MANAGERS_LOCAL;
```

## Quick start

```bash
./start.sh          # builds and starts on port 8090
./stop.sh           # stops the running instance
```

Or manually:

```bash
export JAVA_HOME=/usr/lib/jvm/java-17
./mvnw package -DskipTests
$JAVA_HOME/bin/java -jar target/sample-app-springboot-0.0.1-SNAPSHOT.jar
```

Then open `http://localhost:8090` and log in.

### Test users

| User | Password | Role | What they see |
|---|---|---|---|
| `marvin` | `Oracle123` | Manager + Employee | His own row (with SSN) + his 3 direct reports (without SSN) |
| `emma` | `Oracle123` | Employee | Only her own row (with SSN) |

## Endpoints

| URL | Description |
|---|---|
| `http://localhost:8090/login` | Login page |
| `http://localhost:8090/employees` | HTML table (requires login) |
| `http://localhost:8090/api/employees` | JSON array (requires login) |
| `http://localhost:8090/api/employees/{id}` | JSON for a single employee (requires login) |
| `http://localhost:8090/logout` | End session |

## How it works

### Authentication and connection flow

```
Browser
  → login form (username + password)
    → Spring Boot creates JDBC connection AS the end user
      → TCPS on port 2484 (LISTENER26)
        → PDB9 service
          → Oracle authenticates end user (marvin/Oracle123)
            → Data roles activate (HRAPP_EMPLOYEES_LOCAL, HRAPP_MANAGERS_LOCAL)
              → Data grants filter rows and columns automatically
```

The key design: the app does **not** connect as a shared service account. Each request creates a JDBC connection using the end user's credentials. Oracle Database authenticates the end user, activates their data roles, and enforces data grants at the SQL engine level. The application runs `SELECT ... FROM hr.employees` — the same query for every user — and the database returns only the rows and columns that user is authorized to see.

This means:
- **Marvin** (manager + employee) sees his own row with SSN (via `HRAPP_EMPLOYEES_LOCAL`) plus his direct reports without SSN (via `HRAPP_MANAGERS_LOCAL`)
- **Emma** (employee only) sees only her own row with SSN
- The application has **zero filtering logic** — all security is enforced by the database kernel

### TLS connection

The listener uses Oracle's SSO wallet format for TLS certificates. The standard JDK `KeyStore` cannot read SSO wallets, so the app registers **OraclePKIProvider** at startup (`DataSourceConfig.java`), which adds SSO wallet support to the JVM's security framework.

### Project structure

```
sample-app-springboot/
├── pom.xml                          # Spring Boot 3.4.4 + ojdbc11-production
├── start.sh / stop.sh               # convenience scripts
├── mvnw / .mvn/                     # Maven wrapper (no system Maven needed)
└── src/main/
    ├── java/com/example/sampleapp/
    │   ├── SampleAppApplication.java    # Spring Boot entry point
    │   ├── DataSourceConfig.java        # Per-user OracleDataSource + PKI provider
    │   ├── controller/
    │   │   └── EmployeeController.java  # Login, logout, HTML view + REST endpoints
    │   ├── model/
    │   │   └── Employee.java            # POJO matching hr.employees columns
    │   └── repository/
    │       └── EmployeeRepository.java  # JDBC queries (connection passed per request)
    └── resources/
        ├── application.properties       # JDBC URL, wallet path, port
        └── templates/
            ├── login.html               # Login form
            └── employees.html           # Employee data table
```

### Key components

**DataSourceConfig** — Registers `OraclePKIProvider` once at startup. Provides a `getConnection(username, password)` method that creates a new `OracleDataSource` and connects as the given end user. No shared connection pool — each request authenticates independently.

**EmployeeController** — Handles the login/logout flow using HTTP sessions. On login, it validates credentials by attempting a database connection. On each page load, it opens a connection as the logged-in end user and queries `hr.employees`. The database data grants control what comes back.

**EmployeeRepository** — Runs `SELECT ... FROM hr.employees` using a `Connection` passed from the controller. The same SQL runs for every user — Oracle Deep Data Security filters the results based on who is connected.

### Data

The `hr.employees` table contains 7 sample rows:

| Employee | Role | Manager |
|---|---|---|
| Grace Young | CEO | — |
| Marvin Morgan | SWE_MGR | Grace |
| Emma Baker | SWE2 | Marvin |
| Charlie Davis | SWE1 | Marvin |
| Dana Lee | SWE3 | Marvin |
| Bob Smith | SALES_REP | Grace |
| Fiona Chen | HR_REP | Grace |

### What each user sees

**Marvin** (employee + manager data roles):

| ID | Name | SSN | Salary |
|---|---|---|---|
| 2 | Marvin Morgan | 222-22-2222 | 175,000 |
| 3 | Emma Baker | *(hidden)* | 120,000 |
| 4 | Charlie Davis | *(hidden)* | 95,000 |
| 5 | Dana Lee | *(hidden)* | 130,000 |

**Emma** (employee data role only):

| ID | Name | SSN | Salary |
|---|---|---|---|
| 3 | Emma Baker | 333-33-3333 | 120,000 |

## Configuration

All configuration is in `src/main/resources/application.properties`:

| Property | Purpose |
|---|---|
| `spring.datasource.url` | JDBC connection string with TCPS descriptor |
| `oracle.net.wallet_location` | Path to Oracle wallet for TLS certificates |
| `server.port` | HTTP port (default `8090`) |

# sample-app-django

A simple Django web application that demonstrates **Oracle Deep Data Security** with end user authentication. Users log in with their Oracle Database end user credentials and the database enforces row- and column-level access through data grants — the application runs the same SQL for every user, but each user sees only the data they are authorized to see.

## Prerequisites

- **Python 3.12** — available at `/usr/bin/python3.12` on this host
- **Oracle AI Database 26ai** — the listener (LISTENER26) must be running on TCPS port 2484
- **HR schema** — created per the [end-user-data-grants FastLab](../../fastlab/end-user-data-grants/end-user-data-grants.md) with the `employees` table and sample data
- **End users** — `marvin` and `emma` created as Oracle Database end users with data roles granted

### Database setup

Run the setup scripts in `db/` in order, or run them manually as SYSTEM on PDB9. See the [Spring Boot README](../sample-app-springboot/README.md#database-setup) for the full SQL or use the scripts:

```bash
cd db
./01_create_hr_schema.sh
./02_create_end_users_and_roles.sh
./03_create_data_grants.sh
./04_create_role_bindings.sh
```

## Quick start

```bash
./start.sh          # creates venv, installs deps, starts on port 8091
./stop.sh           # stops the running instance
```

Or manually:

```bash
python3.12 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python manage.py runserver 0.0.0.0:8091
```

Then open `http://localhost:8091` and log in.

### Test users

| User | Password | Role | What they see |
|---|---|---|---|
| `marvin` | `Oracle123` | Manager + Employee | His own row (with SSN) + his 3 direct reports (without SSN) |
| `emma` | `Oracle123` | Employee | Only her own row (with SSN) |

## Endpoints

| URL | Description |
|---|---|
| `http://localhost:8091/login` | Login page |
| `http://localhost:8091/employees` | HTML table (requires login) |
| `http://localhost:8091/api/employees` | JSON array (requires login) |
| `http://localhost:8091/api/employees/{id}` | JSON for a single employee (requires login) |
| `http://localhost:8091/logout` | End session |

## How it works

### Authentication and connection flow

```
Browser
  → login form (username + password)
    → Django creates oracledb connection AS the end user
      → TCPS on port 2484 (LISTENER26)
        → PDB9 service
          → Oracle authenticates end user (marvin/Oracle123)
            → Data roles activate (HRAPP_EMPLOYEES_LOCAL, HRAPP_MANAGERS_LOCAL)
              → Data grants filter rows and columns automatically
```

The key design: the app does **not** connect as a shared service account. Each request creates a connection using the end user's credentials via `python-oracledb` (thin mode). Oracle Database authenticates the end user, activates their data roles, and enforces data grants at the SQL engine level. The application runs `SELECT ... FROM hr.employees` — the same query for every user — and the database returns only the rows and columns that user is authorized to see.

This means:
- **Marvin** (manager + employee) sees his own row with SSN (via `HRAPP_EMPLOYEES_LOCAL`) plus his direct reports without SSN (via `HRAPP_MANAGERS_LOCAL`)
- **Emma** (employee only) sees only her own row with SSN
- The application has **zero filtering logic** — all security is enforced by the database kernel

### TLS connection

The app uses `python-oracledb` in thin mode with an unverified SSL context for the TCPS connection. No Oracle Client or wallet files are needed — the thin driver handles TLS natively.

### Project structure

```
sample-app-django/
├── requirements.txt              # django + oracledb
├── start.sh / stop.sh            # convenience scripts
├── manage.py                     # Django management script
├── sampleapp/
│   ├── settings.py               # Django settings + Oracle DSN
│   ├── urls.py                   # Root URL config
│   └── wsgi.py                   # WSGI entry point
├── employees/
│   ├── views.py                  # Login, logout, HTML view + REST endpoints
│   └── urls.py                   # App URL routes
├── templates/
│   ├── login.html                # Login form
│   └── employees.html            # Employee data table
└── db/                           # Setup/teardown scripts (same as springboot)
    ├── 01_create_hr_schema.sh
    ├── 02_create_end_users_and_roles.sh
    ├── 03_create_data_grants.sh
    ├── 04_create_role_bindings.sh
    ├── 05_verify_as_marvin.sh
    ├── 06_verify_as_emma.sh
    ├── 07_start_app.sh
    └── 08_cleanup.sh
```

### Key components

**views.py** — Contains all the logic in one file. `_get_connection()` creates an `oracledb` connection as the given end user over TCPS. `_fetch_employees()` runs the same `SELECT` for every user. Login/logout uses Django sessions to store credentials. Each page load opens a fresh connection as the logged-in end user — the database data grants control what comes back.

**settings.py** — Configures Django with file-based sessions (no database backend needed) and stores the Oracle DSN with TCPS and `SSL_SERVER_DN_MATCH=NO`.

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

Key settings in `sampleapp/settings.py`:

| Setting | Purpose |
|---|---|
| `ORACLE_DSN` | TNS descriptor with TCPS and SSL_SERVER_DN_MATCH=NO |
| `SESSION_ENGINE` | File-based sessions (no database needed) |
| `server port` | Set in `start.sh` (default `8091`) |

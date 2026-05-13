# Identity-Aware Database Access with OCI IAM and Oracle Deep Data Security

Welcome to this **Oracle Deep Data Security LiveLabs** workshop.

This lab walks you through configuring OCI IAM OAuth2 authentication for Oracle AI Database 26ai and then layering Oracle Deep Data Security data roles and data grants so the database enforces per-user access based on OCI IAM group membership. By the end, Marvin (a manager) and Emma (an employee) authenticate through OCI IAM and see different data from the same SQL query, enforced by the database kernel.

Estimated Time: 60 minutes

## The Challenge

AI copilots and agentic applications are transforming the enterprise, but many never make it past the security review. The blocking question is always the same: how do you guarantee the AI agent only shows each user what they are authorized to see?

Traditional approaches rely on the application to filter data by appending predicates, checking roles, and hiding columns. That is fragile: a bug, a prompt injection, or a misconfigured endpoint can leak data. Managing database passwords for every user does not scale either.

This lab solves both problems:

1. **OCI IAM** handles authentication with centralized users, groups, SSO, and MFA.
2. **Oracle Deep Data Security** handles authorization with database-enforced row and column policies.

```text
Marvin -> OCI IAM OAuth2 login -> TOKEN_AUTH=OAUTH -> Database
                                             |
                                             v
                                    Data grants filter
                                    4 rows: self + team

Emma   -> OCI IAM OAuth2 login -> TOKEN_AUTH=OAUTH -> Database
                                             |
                                             v
                                    Data grants filter
                                    1 row: self only
```

Same SQL. Zero application filtering. Zero database passwords. The security is on the grant, not the code.

## Prerequisites

This lab assumes:

- An **Oracle AI Database 26ai** instance with a TCPS listener on port 2484
- `SYSTEM` and `SYS` access to a pluggable database, such as PDB1
- An **OCI IAM identity domain** where the OCI CLI user can administer applications, users, and groups
- Oracle Database client support for OCI IAM token authentication
- OCI CLI configuration available for the interactive client user, unless you use the default OCI config/profile
- The Oracle Database wallet is configured for TLS connections

## Task 0: Download Lab Scripts

Open a terminal on your DBSec-Lab VM as OS user `oracle`, move to the LiveLabs directory, and unpack the lab bundle.

````bash
<copy>cd livelabs
tar xvf dbsec-livelabs-oci-iam-data-grants.tar.gz
cd oci-iam-data-grants
ls</copy>
````

## Part 1: Configure OCI IAM

### Task 1: Create OCI IAM Applications, Groups, Users, and Claims

After `oci setup config` is complete, the lab can create the IAM objects for you:

````bash
<copy>./00_setup_oci_iam.sh
source ./.oci-iam-data-grants.env</copy>
````

The setup script discovers the OCI IAM Domain URL automatically and prefers the `Default` identity domain. To use a different domain, set `OCI_DOMAIN_NAME` before running it.

The script creates or reuses:

- DB resource application named `Oracle DB`
- Interactive client application named `Oracle Confidential Client`
- `EMPLOYEES` and `MANAGERS` groups
- Marvin and Emma users by default
- A custom access-token claim named `group`, populated from `$user.groups.*.display`
- `.oci-iam-data-grants.env`

Default group membership:

| User | Groups |
|---|---|
| `marvin` | `EMPLOYEES`, `MANAGERS` |
| `emma` | `EMPLOYEES` |

To use email-style usernames instead:

````bash
<copy>export OCI_USERNAME_DOMAIN=example.com
./00_setup_oci_iam.sh
source ./.oci-iam-data-grants.env</copy>
````

That makes the HR sample rows use `marvin@example.com` and `emma@example.com`.

If you use a non-default OCI CLI config file or profile, export these first:

````bash
<copy>export OCI_CONFIG_FILE=/home/oracle/.oci/config
export OCI_PROFILE=DEFAULT</copy>
````

## Part 2: Configure the Oracle Database

### Task 2: Set Database Identity Provider Parameters

Configure the database to accept OCI IAM OAuth2 tokens.

Before running, load the environment file from Task 1:

````bash
<copy>source ./.oci-iam-data-grants.env</copy>
````

Then run:

````bash
<copy>./01_configure_db_identity_provider.sh</copy>
````

The script runs the following as `SYS`:

```sql
ALTER SYSTEM SET identity_provider_type = OCI_IAM SCOPE = BOTH;

ALTER SYSTEM SET identity_provider_oauth_config =
'{
  "app_id": "<OCI_DB_APP_ID>",
  "domain_url": "<OCI_DOMAIN_URL>"
}' SCOPE = BOTH;

BEGIN
  DBMS_CREDENTIAL.CREATE_CREDENTIAL(
    credential_name => 'OCI_IAM_DOMAIN_DB_CRED$',
    username        => '<OCI_DB_CLIENT_ID>',
    password        => '<OCI_DB_CLIENT_SECRET>'
  );
END;
/
```

### Task 3: Configure TCPS Listener, sqlnet.ora, and tnsnames.ora

OCI IAM token authentication requires a TLS connection. This task configures the TCPS listener, wallet, and connection descriptor.

````bash
<copy>./02_configure_network.sh</copy>
````

This script:

1. Creates a wallet with a self-signed certificate if one does not exist
2. Backs up and updates `listener.ora` to add a TCPS endpoint on port 2484
3. Backs up and updates `sqlnet.ora` with the wallet location
4. Adds the `hrdb` TNS entry to `tnsnames.ora` with `TOKEN_AUTH=OAUTH`
5. Restarts the listener and registers the database

The `tnsnames.ora` entry will look like:

```text
hrdb =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCPS)(HOST = <hostname>)(PORT = 2484))
    (SECURITY =
      (SSL_SERVER_DN_MATCH = YES)
      (SSL_SERVER_CERT_DN = "CN=<hostname>,O=DBSecLab,C=US")
      (TOKEN_AUTH = OAUTH)
      (TOKEN_LOCATION = ~/.oci/oci-iam-data-grants)
      (OCI_IAM_URL = <domain-url>)
      (OCI_CLIENT_ID = <interactive-client-id>)
      (OCI_AUDIENCE = OracleDB)
      (OCI_SCOPE = OracleDBDB_ACCESS_SCOPE)
    )
    (CONNECT_DATA =
      (SERVICE_NAME = <pdb>)
    )
  )
```

When you connect with `sqlplus /@hrdb`, the Oracle client uses OCI IAM interactive authentication.

## Part 3: Create Deep Data Security Objects

### Task 4: Create the HR Schema and Employee Data

Create the HR schema with a `NO AUTHENTICATION` account and populate it with 7 sample employees. The `user_name` values must match the usernames returned in `ORA_END_USER_CONTEXT.username` for your OCI IAM users. For many identity domains this is the user's email address.

If you use email-style OCI IAM usernames, set the username domain before running `00_setup_oci_iam.sh`. If you use the default `marvin` and `emma` usernames, no domain is required.

````bash
<copy>export OCI_USERNAME_DOMAIN=example.com</copy>
````

Then run:

````bash
<copy>./03_create_hr_schema.sh</copy>
````

This script creates the HR schema, the `EMPLOYEES` table, and 7 sample rows:

| Employee | Role | Department | Manager |
|---|---|---|---|
| Grace Young | CEO | - | - |
| Marvin Morgan | SWE_MGR | 1 | Grace |
| Emma Baker | SWE2 | 1 | Marvin |
| Charlie Davis | SWE1 | 1 | Marvin |
| Dana Lee | SWE3 | 1 | Marvin |
| Bob Smith | SALES_REP | 2 | Grace |
| Fiona Chen | HR_REP | 3 | Grace |

### Task 5: Create Data Roles, Data Grants, and End User Context

This is the core of Deep Data Security. You create data roles that map to OCI IAM groups, then attach data grants that define row and column access.

````bash
<copy>./04_create_data_roles_and_grants.sh</copy>
````

This script creates externally mapped data roles:

```sql
CREATE OR REPLACE DATA ROLE hrapp_employees
  MAPPED TO 'IAM_OAUTH_GROUP=EMPLOYEES';

CREATE OR REPLACE DATA ROLE hrapp_managers
  MAPPED TO 'IAM_OAUTH_GROUP=MANAGERS';
```

When Marvin authenticates through OCI IAM, his token contains `EMPLOYEES` and `MANAGERS` group membership. Oracle automatically activates the corresponding data roles. No `CREATE END USER` or `GRANT DATA ROLE` is needed.

The employee grant allows users to see their own row and update only `phone_number`:

```sql
CREATE OR REPLACE DATA GRANT hr.HRAPP_EMPLOYEES_ACCESS
  AS SELECT (employee_id, first_name, last_name, user_name,
             department_id, manager_id, ssn, salary, phone_number),
     UPDATE(phone_number)
  ON hr.employees
  WHERE upper(user_name) = upper(ora_end_user_context.username)
  TO HRAPP_EMPLOYEES;
```

The manager grant allows managers to see direct reports, excluding `ssn`, and update `salary` and `department_id`:

```sql
CREATE OR REPLACE DATA GRANT hr.HRAPP_MANAGER_ACCESS
  AS SELECT (ALL COLUMNS EXCEPT ssn), UPDATE (salary, department_id)
  ON hr.employees
  WHERE manager_id = ORA_END_USER_CONTEXT.HR.EMP_CTX.ID
  TO HRAPP_MANAGERS;
```

## Part 4: Verify the Policies

### Task 6: Connect and Verify as Marvin

````bash
<copy>./05_verify_as_marvin.sh</copy>
````

Log in as Marvin when prompted by OCI IAM. The script verifies:

1. `CURRENT_USER = XS$NULL`
2. `AUTHENTICATED_IDENTITY` is Marvin's OCI IAM identity
3. Active data roles include `HRAPP_EMPLOYEES` and `HRAPP_MANAGERS`
4. `SELECT * FROM hr.employees` returns 4 rows: Marvin and his 3 direct reports
5. SSN is visible for Marvin's own row and excluded for direct reports

### Task 7: Connect and Verify as Emma

````bash
<copy>./06_verify_as_emma.sh</copy>
````

Log in as Emma when prompted by OCI IAM. Emma sees 1 row: herself only. She can view her SSN and salary but can update only her phone number.

### Task 8: Verify the Security Boundary

````bash
<copy>./07_verify_security_boundary.sh</copy>
````

This script runs four tests:

1. Marvin tries to see Bob's SSN: 0 rows, because Bob is outside Marvin's scope
2. Emma tries to update her salary: 0 rows updated, because only `phone_number` is allowed
3. Emma tries to update Marvin's phone number: 0 rows updated, because the predicate limits Emma to her own row
4. HR tries to log in directly: fails, because HR was created with `NO AUTHENTICATION`

## Task 9: Clean Up

````bash
<copy>./08_cleanup_db.sh</copy>
````

The cleanup script:

1. Drops the data grant on `SYS.END_USER_CONTEXT`
2. Drops the `OCI_IAM_DOMAIN_DB_CRED$` credential
3. Drops remaining data grants, end user context, roles, data roles, and the HR schema
4. Resets `identity_provider_type` and `identity_provider_oauth_config`

Then clean up the OCI IAM objects:

````bash
<copy>./09_cleanup_oci_iam.sh</copy>
````

The OCI cleanup script deletes the lab-named applications, groups, optional demo users, and custom `group` claim. It asks you to type `DELETE` before removing IAM objects. For unattended cleanup, run:

````bash
<copy>FORCE=1 ./09_cleanup_oci_iam.sh</copy>
````

## Complete Script Sequence

| Script | Purpose |
|---|---|
| `01_configure_db_identity_provider.sh` | Set `identity_provider_type`, `identity_provider_oauth_config`, and `OCI_IAM_DOMAIN_DB_CRED$` |
| `02_configure_network.sh` | Create wallet, configure TCPS listener, `sqlnet.ora`, and `tnsnames.ora` |
| `03_create_hr_schema.sh` | Create HR schema with employee data |
| `04_create_data_roles_and_grants.sh` | Create data roles mapped to OCI IAM groups, data grants, and context |
| `05_verify_as_marvin.sh` | Connect as Marvin via OCI IAM: 4 rows |
| `06_verify_as_emma.sh` | Connect as Emma via OCI IAM: 1 row |
| `07_verify_security_boundary.sh` | Test bypass attempts |
| `08_cleanup_db.sh` | Drop lab objects and reset identity provider settings |
| `09_cleanup_oci_iam.sh` | Delete lab-created OCI IAM apps, groups, users, and custom claim |

## Key Differences: OCI IAM vs. Direct Password

| Aspect | Direct Password | OCI IAM |
|---|---|---|
| Authentication | `CREATE END USER marvin IDENTIFIED BY Oracle123` | OCI IAM OAuth2 token via `TOKEN_AUTH=OAUTH` |
| Data role activation | `GRANT DATA ROLE ... TO marvin` | `MAPPED TO 'IAM_OAUTH_GROUP=MANAGERS'` |
| End user creation | Required | Not needed; identity comes from the token |
| Connection string | `sqlplus marvin/Oracle123@pdb1` | `sqlplus /@hrdb` |
| Password management | Database passwords | OCI IAM users, groups, SSO, and MFA |
| Data grants | Identical | Identical |

The data grants are the same in both approaches. The difference is how the user's identity and group membership reach the database.

## Learn More

- [Oracle AI Database Documentation](https://docs.oracle.com/en/database/)
- [Oracle Database Net Services Reference](https://docs.oracle.com/en/database/oracle/oracle-database/26/netrf/)

## Acknowledgements

- **Author** - Oracle Database Security Product Management
- **Last Updated By/Date** - May 2026

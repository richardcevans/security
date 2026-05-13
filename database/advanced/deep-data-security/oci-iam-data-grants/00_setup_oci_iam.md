# Task 0: Create OCI IAM Objects

The only prerequisite for this task is a working OCI CLI configuration:

```bash
oci setup config
oci iam region list
```

Then run:

```bash
./00_setup_oci_iam.sh
source ./.oci-iam-data-grants.env
```

The script discovers the active identity domain from the tenancy in `~/.oci/config`. If discovery is not allowed by your policies, provide the domain URL explicitly:

```bash
export OCI_DOMAIN_URL=https://idcs-xxxxxxxx.identity.oraclecloud.com:443
./00_setup_oci_iam.sh
source ./.oci-iam-data-grants.env
```

## What the Script Creates

The script creates or reuses:

- DB resource app: `Oracle DB`
- Interactive client app: `Oracle Confidential Client`
- DB audience: `OracleDB`
- DB scope: `DB_ACCESS_SCOPE`
- Fully qualified scope: `OracleDBDB_ACCESS_SCOPE`
- Groups: `EMPLOYEES`, `MANAGERS`
- Demo users by default: `marvin`, `emma`
- Group assignments:
  - `marvin` -> `EMPLOYEES`, `MANAGERS`
  - `emma` -> `EMPLOYEES`
- Custom access-token claim:
  - name: `group`
  - value: `$user.groups.*.display`
  - token type: access token
- Environment file: `.oci-iam-data-grants.env`

The environment file contains:

```bash
export OCI_DB_APP_ID=...
export OCI_DB_CLIENT_ID=...
export OCI_DB_CLIENT_SECRET=...
export OCI_DOMAIN_URL=...
export OCI_CLIENT_ID=...
export OCI_AUDIENCE=OracleDB
export OCI_SCOPE=OracleDBDB_ACCESS_SCOPE
export OCI_USERNAME_DOMAIN=
export PDB_NAME=pdb1
```

## Email-Style Usernames

By default, the lab uses simple usernames:

```text
marvin
emma
```

To use email-style usernames instead:

```bash
export OCI_USERNAME_DOMAIN=example.com
./00_setup_oci_iam.sh
source ./.oci-iam-data-grants.env
```

Then the HR data setup script stores:

```text
marvin@example.com
emma@example.com
```

## Existing Users

If you already have users and do not want the script to create Marvin and Emma:

```bash
export CREATE_DEMO_USERS=0
./00_setup_oci_iam.sh
source ./.oci-iam-data-grants.env
```

Then manually add your test users to the created groups:

| User | Groups |
|---|---|
| manager user | `EMPLOYEES`, `MANAGERS` |
| employee user | `EMPLOYEES` |

Make sure `HR.EMPLOYEES.USER_NAME` matches `ORA_END_USER_CONTEXT.username`.

## If Custom Claim Creation Fails

Some tenancies do not allow `oci raw-request` to create identity-domain custom claims. If the script prints a warning, create this custom claim in OCI IAM:

```json
{
  "schemas": [
    "urn:ietf:params:scim:schemas:oracle:idcs:CustomClaim"
  ],
  "name": "group",
  "value": "$user.groups.*.display",
  "expression": true,
  "mode": "always",
  "tokenType": "AT",
  "allScopes": true
}
```

This claim is required because database data roles map to OCI IAM group display names:

```sql
CREATE OR REPLACE DATA ROLE hrapp_employees
  MAPPED TO 'IAM_OAUTH_GROUP=EMPLOYEES';

CREATE OR REPLACE DATA ROLE hrapp_managers
  MAPPED TO 'IAM_OAUTH_GROUP=MANAGERS';
```

Without the `group` claim in the access token, authentication can succeed while data roles do not activate.

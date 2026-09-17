# LangChain Agent Sample HR Application

## Overview

This project is a sample python application that uses the Deep Data Security feature of Oracle Database to propagate the authenticated end user's security context to the database, where Deep Data Security data grants enforce row and column level access control based on the user's privileges.

It demonstrates how to build AI assistants over Oracle Database using:

* LangChain
* OCI Generative AI
* Oracle Database Deep Data Security
* Microsoft Entra ID
* Oracle Python End User Security Provider

The application exposes two independent AI agents:

| Agent                        | Purpose                                                                                                 |
| ---------------------------- | ------------------------------------------------------------------------------------------------------- |
| HR Agent                     | General HR assistant with employee search, reporting hierarchy, SQL querying, and related HR operations |
| Compensation Analytics Agent | Assistant limited to returning aggregate salary information - beyond                                    |

Both agents share the same LangChain harness and Oracle database while using different authorization paths.


## Repository Layout

```text
langchain_demo/

langchain_app.py
langchain_tools.py
db_connection.py
get_user_token.py
app_config.py
setup.sql
requirements.txt
.env.example
.env
```

## Prerequisites

* Python 3.12
* Oracle Database with Deep Data Security enabled and the following:
```text
Software: Oracle AI Database (23.26.2 or later) installed on a Linux host.
Database access: A named database user with the DBA role.
SQL client: SQL*Plus or another SQL client to connect to the database.
```
* OCI Generative AI
* Microsoft Entra ID tenant
* OCI SDK configuration


## Microsoft Entra ID Setup

This demo uses four Microsoft Entra ID applications.

| Application      | Purpose                                                 |
| ---------------- | ------------------------------------------------------- |
| Client App       | Interactive MSAL login used by the Python application   |
| Database App     | Oracle Database resource API                            |
| HR / Midtier App | HR agent resource server and client                     |
| Compensation App | Compensation Analytics Agent resource server and client |

### Database App

Register the Oracle AI Database as an application in Microsoft Entra ID so that client applications can request access tokens scoped to the database.

This registration represents the database as a resource server. You expose the database as a web API and define a delegated scope that controls which client applications can request database-access tokens.

**Create an application registration for the database.**

1. Log in to the Microsoft Entra portal.
2. In the left navigation pane, expand **Entra ID**, click **App registrations**, and then click **New registration**.
3. On the **Register an application** page:

   * Enter a name for your DB App in the **Name** field.
   * For **Supported account types**, select **Single tenant only - Default Directory**.
   * Click **Register**.
4. From the application's **Overview** page, copy and save the following values for later use:

   * **Application (client) ID**
   * **Directory (tenant) ID**

You will use these values to configure the identity provider configuration in the database.

**Expose the database as a web API and define a scope.**

1. On the application's **Overview** page, click **Add an Application ID URI**.
2. On the **Expose an API** page, click **Add** next to **Application ID URI**.
3. Update the default URI by replacing `api://` with `https://<your-entraID-domain>/`, and then click **Save**.
4. Copy this URI for later use.

**Add a delegated scope.**

1. Under **Scopes defined by this API**, click **Add a scope**.
2. In the panel that appears, enter the following information:

   * **Scope name**: `sessions:scope:connect`
   * **Who can consent**: `Admins and users`
   * **Display name / description / value**: `Access Oracle Database`
3. Click **Add scope**.

You have now created the database application registration in Entra ID with an Application ID URI and a delegated scope. Client applications can reference this scope when requesting database-access tokens.

### Client App

1. In the Microsoft Entra portal, click **App registrations** under **Entra ID**, and then click **New registration**.
2. On the **Register an application** page:

   * Enter a name.
   * For **Supported account types**, select **Single tenant only - Default Directory**.
   * Under **Redirect URI**, select **Web** and enter `http://localhost:3000`.
   * Click **Register**.
3. From the application's **Overview** page, copy and save the **Application (client) ID**.

**Grant permissions to the Client application (Note: these steps must be done after the remaining apps have been created).**

1. Under **Manage**, click **API permissions**.
2. Click **Add a permission**.
3. In the **Request API permissions** panel:

   * Click **APIs my organization uses**.
   * Select your DB App.
   * Select **Delegated permissions** and check `sessions:scope:connect`.
   * Click **Add permissions**.
4. You will follow the same process to add the scopes of the Midtier and Compensation Apps after you have created them.
5. Click **Grant admin consent for Default Directory** and confirm the prompt.

### Midtier App

The HR / midtier will contain application roles defined on this registration flow, which the Oracle Database can use to activate matching data roles.

**Create a registration for the HR application.**

1. In the Microsoft Entra portal, click **App registrations** under **Entra ID**, and then click **New registration**.
2. On the **Register an application** page:

   * Enter a name.
   * For **Supported account types**, select **Single tenant only - Default Directory**.
   * Click **Register**.
3. From the application's **Overview** page, copy and save the **Application (client) ID**.

**Set the application ID URI.**

1. On the application's **Overview** page, click **Add an Application ID URI**.
2. On the **Expose an API** page:

   * Click **Add** next to **Application ID URI**.
   * Accept the default value `api://<your-app-id>`, then click **Save**.
3. Copy this URI for later use.

**Expose a delegated scope.**

1. Under **Scopes defined by this API**, click **Add a scope**.
2. Enter the following information:

   * **Scope name**: `user_access`
   * **Who can consent**: `Admins and users`
   * **Display name / description / value**: `Access HCM APP`
   * **State**: leave **Enabled** selected
3. Click **Add scope**.

**Create a client secret.**

1. In App Registrations for the app, under **Manage**, click **Certificates & secrets**.
2. Click **New client secret**.
3. Enter a description such as `hcm-app-secret`.
4. Set the expiry period according to your organization's policy.
5. Click **Add**.
6. Copy and save the **Value** immediately; it is displayed only once.

**Grant permissions to the Midtier application.**

1. Under **Manage**, click **API permissions**.
2. Click **Add a permission**.
3. In the **Request API permissions** panel:

   * Click **APIs my organization uses**.
   * Select your DB App.
   * Select **Delegated permissions** and check `sessions:scope:connect`.
   * Click **Add permissions**.
4. Click **Grant admin consent for Default Directory** and confirm the prompt.

**Define application roles.**

Application roles control how user permissions flow. When a user is assigned an application role (for example, `MANAGER`), that value appears in the token's `roles` claim.

1. In App registrations for the Midtier App, click **App roles** under **Manage**.
2. Click **Create app role** and enter the role details.
3. Repeat as needed to add all required roles (EMPLOYEE_ROLE* and MANAGER*_ROLE in this demo).

**Authorize the HR application as a client of the database.**

1. Click **App registrations**.
2. Select the DB App.
3. Under **Manage**, click **Expose an API**.
4. Under **Authorized client applications**, click **Add a client application**.
5. Enter the Midtier application (client) ID.
6. Select the database scope.
7. Click **Add application**.

At this point, the HR application is configured as both a resource server and a client. It has a client secret, application roles, delegated permissions, and database pre-authorization.

### Compensation App

The Compensation App is was introduced for the Compensation Analytics Agent. It is the application users must be allowed to access before the Agent can use the Oracle database through the application identity.

The compensation application is configured as both:

* a **resource server** exposing a delegated scope that the Python client requests at sign-in time, and
* a **client** that is pre-authorized to access the Oracle Database resource and can exchange the user token during the downstream OBO flow.

**Create a registration for the Compensation App.**

1. In the Microsoft Entra portal, click **App registrations** under **Entra ID**, and then click **New registration**.
2. On the **Register an application** page:

   * Enter a name.
   * For **Supported account types**, select **Single tenant only - Default Directory**.
   * Click **Register**.
3. From the application's **Overview** page, copy and save the **Application (client) ID**.

**Set the application ID URI.**

1. On the application's **Overview** page, click **Add an Application ID URI**.
2. On the **Expose an API** page:

   * Click **Add** next to **Application ID URI**.
   * Accept the default value `api://<your-app-id>` or use the `https://<tenant-domain>/<app-id>` form if that is the convention used in your environment.
   * Click **Save**.
3. Copy this URI for later use.

**Expose a delegated scope for the Agent.**

1. Under **Scopes defined by this API**, click **Add a scope**.
2. Enter the following information:

   * **Scope name**: `agent_impersonation`
   * **Who can consent**: `Admins and users`
   * **Display name / description / value**: `Access Compensation APP`
   * **State**: leave **Enabled** selected
3. Click **Add scope**.

**Configure API permissions for the Compensation App.**

1. In App Registrations for the App, under **Manage**, click **API permissions**.
2. Click **Add a permission**.
3. In the **Request API permissions** panel:

   * Click **APIs my organization uses**.
   * Select your DB App.
   * Select **Delegated permissions** and check `sessions:scope:connect`.
   * Click **Add permissions**.
4. Click **Grant admin consent for Default Directory** and confirm the prompt.

**Add the client application as an authorized client.**

1. Go to your DB App.
2. Under **Manage**, click **Expose an API**.
3. Under **Authorized client applications**, click **Add a client application**.
4. Paste the **Application (client) ID** of Compensation App.
5. Select the database scope.
6. Click **Add application**.

**Assign users to the Compensation App.**

1. In the Entra portal, go to **Enterprise applications** and select the Compensation App.
2. Under **Properties**, set **Assignment required?** to **Yes**.
3. Under **Users and groups**, assign the users or groups that should be allowed to use the  Agent.
4. If the app uses an application role such as `HR_REP_ROLE`, assign the appropriate users/groups to that role.

At this point, only users who are allowed to access the Compensation App can obtain the delegated token used by the Compensation Analytics Agent.

### Notes on Scopes and Tokens

* The **Database App** exposes the database access scope used for Oracle token acquisition.
* The **Midtier App** exposes its own delegated scope and app roles.
* The **Compensation App** exposes its own delegated scope (`agent_impersonation`) and is the new addition for the Compensation Analytics Agent.
* The **Client App** requests whichever scope corresponds to the agent being launched.

## Oracle Authorization

The HR Agent uses externally mapped data roles.

Example:

```sql
CREATE DATA ROLE EMPLOYEE_FS_ROLE
MAPPED TO
'AZURE_APP=...:azure_role=EMPLOYEE_ROLE';
```

The Compensation Analytics Agent instead uses an Oracle Application Identity.

Example:

```sql
CREATE APPLICATION IDENTITY compensation_app
MAPPED TO 'AZURE_CLIENT_ID=<Compensation App Client ID>';

CREATE DATA ROLE SALARY_AGENT_FS_ROLE;

GRANT DATA ROLE SALARY_AGENT_FS_ROLE
TO compensation_app;
```

Data grants determine the tables and columns visible to the Agent.


## Oracle Database Setup

This guide assumes you **already have a working database and seed** and only need to complete the TCPS / wallet / listener / application setup.

> **Note**
> If you restart the database or listener, run the proxy and `TNS_ADMIN` setup again in the same terminal before continuing.

### 1) Set up the proxy and wallet environment

Use the proxy settings for your environment, then point `TNS_ADMIN` at the TCPS wallet/config directory.

```csh
source /usr/local/packages/Proxy-Config-set.csh
setenv https_proxy $http_proxy
setenv TNS_ADMIN $T_WORK/sslserver
```

> **Compatibility note**
> In the working setup we used, the database had to be started with `compatible=23.0.0.0` in the init file. If startup fails with a control-file/version mismatch, check the `compatible` line in the init file before moving on.

### 2) Create the TCPS wallet and listener configuration

Assuming your environment provides the `oratst` harness, run the TCPS setup script to generate the client/server wallets and listener files for single-side TLS:

```csh
oratst tzfdtlssetup_jdbc.tsc
```

> **What to expect**
> After this step, the `sslserver` directory should exist under `$T_WORK`, and `tnsping` / `lsnrctl` should use the files there.

### 3) Restart the database

Restart the database as SYSDBA:

```bash
sqlplus / as sysdba
```

Inside SQL*Plus:

```sql
shutdown immediate
startup pfile=$T_WORK/t_init1.ora
ALTER PLUGGABLE DATABASE ALL OPEN;
```

> **Compatibility note**
> If `startup pfile=...` fails with `ORA-00201` / control-file version mismatch, the init file usually needs the correct `compatible=23.0.0.0` value. In the working environment, updating that value in the generated init file was required before the database would start cleanly.

### 4) Restart the listener

Exit SQL*Plus, then restart the listener from the shell:

```bash
lsnrctl stop
lsnrctl start
```

### 5) Run the application setup script

Once the database and listener are up, run the setup script from the directory that contains it:

```bash
sqlplus / as sysdba
@setup.sql
```

Ensure that you fill in a usable password and connection string in the setup.sql file, and that you fill in your Azure App information where data roles are mapped and when the identity provider is set in the setup.sql file before running it. There are currently placeholders in these locations to help guide you.


## OCI SDK Configuration

If you have not already, create the OCI configuration directory inside your home directory:

```bash
mkdir -p ~/.oci
```

Create the OCI config file:

```bash
vi ~/.oci/config
```

Copy your OCI API private key (`.pem`) file into the OCI directory.

Paste your OCI SDK configuration into the file:

```ini
[idcs-ord]
user=<user_ocid>
fingerprint=<fingerprint>
key_file=/home/<username>/.oci/oci_api_key.pem
tenancy=<tenancy_ocid>
region=us-ashburn-1
```

Set `OCI_GENAI_SERVICE_ENDPOINT` in `.env` when you use a region other than
Ashburn. Set `MODEL_ID` to a model available to your tenancy and region.

## Python Installation

Install dependencies:

```bash
pip install -r requirements.txt
```

Install Oracle Python Driver:

```bash
python3.12 -m pip install oracledb
```

## Application Configuration

Copy `.env.example` to `.env`, then update the values in `.env` before running
the application. The application reads `MODEL_ID` and
`OCI_GENAI_SERVICE_ENDPOINT` from `.env`; no source edit is required for a
normal deployment.

The database connection pool defaults to a minimum of 1, maximum of 4, and an
increment of 1. Override these values in `.env` with `DB_POOL_MIN`,
`DB_POOL_MAX`, and `DB_POOL_INCREMENT` when needed.

## Setup Proxy

Set up the required network/database proxy before running the application.

## Running

HR Agent:

```bash
python3.12 langchain_app.py
```

Compensation Analytics Agent:

```bash
python3.12 langchain_app.py --agent compensation
```

## AI Harness

The application uses a LangChain `create_agent()` implementation with custom working memory that stores information about previous requests and conversations within the session.
This allows long-running conversations while keeping prompt size bounded.

## Available Tools

### HR Agent

* `get_current_user`
* `get_employee`
* `search_employees`
* `get_my_direct_reports`
* `execute_sql`
* `propose_update`
* `describe_table`
* `list_tables`
* `get_salary_summary`

`execute_sql` accepts `SELECT` statements only. Database changes are staged by
`propose_update` and require the CLI user to reply exactly `yes` before the
change is validated, committed, and applied.

### Compensation Analytics Agent

* `get_salary_summary`
* `get_job_salary_statistics`
* `get_salary_statistics_by_location`

## Notes

* The HR Agent and Compensation Analytics Agent share the same LangChain harness.
* The compensation path uses a separate Entra application and an Oracle Application Identity.
* Oracle Deep Data Security determines all row- and column-level visibility.

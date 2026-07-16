# Lab 1: Explore the Environment

## Introduction

Explore the prepared Autonomous Database environment before adding AI and MCP access. Review the sample schema, sensitive data, users, roles, and access paths that the workshop will secure.

Estimated Time: 10 minutes

### Objectives

In this lab, you will:

- Download the workshop script bundle.
- Confirm database connectivity.
- Review the sample schema and sensitive data.
- Identify the users, roles, groups, and application paths used in later labs.

### Prerequisites

- Access to the workshop database.
- Lab users, sample schema, and seed data already staged.
- SQL worksheet, SQLcl, or another approved database client.
- Optional: OCI Cloud Shell with SQL*Plus and the OCI CLI.

## Task 0: Download the Workshop Scripts

1. Open OCI Cloud Shell.

2. Create the shared Deep Data Security lab directory.

    ```bash
    <copy>
    mkdir -p "$HOME/dbsec-labs/deep-data-security"
    cd "$HOME/dbsec-labs/deep-data-security"
    </copy>
    ```

3. Download and extract the DeepSec MCP scripts.

    ```bash
    <copy>
    wget -O deep-sec-mcp-cloudshell.zip https://objectstorage.us-ashburn-1.oraclecloud.com/p/eoQGRJ46zRptDtmOivg2aGZCvDUvGGYxJfCGeQICgy-cfC0i1CX6NYT0iwF2vGOS/n/oradbclouducm/b/dbsec_public/o/deep-sec-mcp-cloudshell.zip
    unzip -o deep-sec-mcp-cloudshell.zip
    cd deep-sec-mcp
    </copy>
    ```

## Task 1: Create or Confirm the Database

1. Change to the workshop script directory.

    ```bash
    <copy>
    cd "$HOME/dbsec-labs/deep-data-security/deep-sec-mcp"
    </copy>
    ```

2. Create or reuse the ADB-S and OCI IAM resources from Cloud Shell.

    ```bash
    <copy>
    ./setup_adbs_oci_iam.sh <compartment-name-or-ocid>
    source ./.deep-sec-mcp.env
    </copy>
    ```

    The script creates or reuses:

    - Autonomous Database Serverless
    - OCI IAM OAuth database resource application
    - OCI IAM OAuth public client application
    - OCI IAM groups and optional demo users
    - ADB wallet
    - MCP setup defaults for Database Tools

3. Confirm the database and identity values loaded into your current shell.

    ```bash
    <copy>
    env | grep -E '^(DB_NAME|ADB_OCID|ADB_SERVICE|TNS_ADMIN|WALLET_DIR|OCI_DOMAIN_URL|OCI_CLIENT_APP|OCI_SCOPE)=' | sort
    </copy>
    ```

4. If you use pre-provisioned resources instead of the setup script, create the script environment file and then confirm the loaded values.

    ```bash
    <copy>
    ./00_configure_lab_env.sh
    source ./.deep-sec-mcp.env
    env | grep -E '^(DB_NAME|ADB_OCID|ADB_SERVICE|TNS_ADMIN|WALLET_DIR|OCI_DOMAIN_URL|OCI_CLIENT_APP|OCI_SCOPE)=' | sort
    </copy>
    ```

## Task 2: Review Sample Data

1. Create or refresh the sample HR schema.

    ```bash
    <copy>
    ./02_create_hr_schema.sh
    </copy>
    ```

2. Identify the sensitive rows or columns that should not be visible to every user.

3. Verify the current database setup.

    ```bash
    <copy>
    ./verify_db_setup.sh
    </copy>
    ```

## Task 3: Confirm Identity Inputs

1. Confirm the users, groups, and data-role mapping type that later labs use for identity-aware tests.

    ```bash
    <copy>
    env | grep -E '^(MARVIN_USERNAME|EMMA_USERNAME|OCI_IAM_EMPLOYEE_GROUP|OCI_IAM_MANAGER_GROUP|DATA_ROLE_MAPPING_TYPE)=' | sort
    </copy>
    ```

2. Keep these values loaded. Lab 5 uses the group names to create database data roles and prove that the same data-layer rules apply to SQL, the AI prompt simulator, and MCP tool access.

    You may now proceed to the next lab.

## Acknowledgements

* **Author** - Richard Evans
* **Last Updated By/Date** - Richard Evans, July 2026

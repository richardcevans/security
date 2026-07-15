# Lab 1: Explore the Environment

## Introduction

Explore the prepared Autonomous Database environment before adding AI and MCP access. Review the sample schema, sensitive data, users, roles, and access paths that the workshop will secure.

Estimated Time: 10 minutes

### Objectives

In this lab, you will:

- Complete the first outcome.
- Confirm database connectivity.
- Review the sample schema and sensitive data.
- Identify the users, roles, groups, and application paths used in later labs.

### Prerequisites

- Access to the workshop database.
- Lab users, sample schema, and seed data already staged.
- SQL worksheet, SQLcl, or another approved database client.
- Optional: OCI Cloud Shell with SQL*Plus and the OCI CLI.

## Task 1: Confirm the Database

1. Open OCI Cloud Shell or your approved lab client.

2. Change to the workshop script directory.

    ```bash
    cd ~/security/database/advanced/deep-data-security/deep-sec-mcp
    ```

3. Choose how you want to prepare the database and OCI IAM values.

    For a Free Tier or self-contained ADB-S run, create or reuse ADB-S and OCI IAM resources from Cloud Shell:

    ```bash
    ./setup_adbs_oci_iam.sh <compartment-name-or-ocid>
    source ./.deep-sec-mcp.env
    ```

    The script creates or reuses:

    - Autonomous Database Serverless
    - OCI IAM OAuth database resource application
    - OCI IAM OAuth public client application
    - OCI IAM groups and optional demo users
    - ADB wallet
    - MCP setup defaults for Database Tools

    If you use pre-provisioned resources instead, create the optional script environment file.

    ```bash
    ./00_configure_lab_env.sh
    source ./.deep-sec-mcp.env
    ```

4. Edit `.deep-sec-mcp.env` and set any values not supplied by Terraform, Resource Manager, your workshop reservation, or `setup_adbs_oci_iam.sh`.

    Required database values:

    ```bash
    DB_NAME
    ADB_SERVICE
    ADMIN_PWD
    WALLET_DIR
    TNS_ADMIN
    ```

5. If the wallet was not preloaded or created by `setup_adbs_oci_iam.sh`, download it after setting `ADB_OCID`.

    ```bash
    DOWNLOAD_WALLET=1 ./00_configure_lab_env.sh
    source ./.deep-sec-mcp.env
    ```

6. Record the database service name and connection method used by the simple app and MCP server.

## Task 2: Review Sample Data

1. Create or refresh the sample HR schema.

    ```bash
    ./02_create_hr_schema.sh
    ```

2. Identify the sensitive rows or columns that should not be visible to every user.

3. Verify the current database setup.

    ```bash
    ./verify_db_setup.sh
    ```

## Task 3: Review Access Paths

1. Review the planned access paths: direct SQL, AI application, MCP tool call, and analytics or reporting.

2. Record the baseline users, groups, or roles that will produce different results later.

    The optional scripts use these OCI IAM test users and groups:

    ```bash
    MARVIN_USERNAME=marvin
    EMMA_USERNAME=emma
    OCI_IAM_EMPLOYEE_GROUP=Default/deepsec-employees
    OCI_IAM_MANAGER_GROUP=Default/deepsec-managers
    DATA_ROLE_MAPPING_TYPE=IAM_GROUP_NAME
    ```

    You may now proceed to the next lab.

## Acknowledgements

* **Author** - Richard Evans
* **Last Updated By/Date** - Richard Evans, July 2026

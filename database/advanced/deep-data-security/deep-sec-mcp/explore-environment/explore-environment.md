# Lab 1: Import the ADB OCI IAM Environment

## Introduction

Use the database and IAM environment that the ADB OCI IAM workshop already created. This lab copies only the values needed for MCP Server Tools into a separate local environment file; it makes no database or IAM changes.

Estimated Time: 5 minutes

### Prerequisites

- Completed ADB OCI IAM workshop.
- Its `.adb-oci-iam.env` file is available in Cloud Shell.

## Task 1: Download the MCP Scripts

1. In OCI Cloud Shell, download and extract the DeepSec MCP script bundle.

    ```bash
    <copy>
    mkdir -p "$HOME/dbsec-labs/deep-data-security"
    cd "$HOME/dbsec-labs/deep-data-security"
    wget -O deep-sec-mcp-cloudshell.zip <deep-sec-mcp-zip-url>
    unzip -o deep-sec-mcp-cloudshell.zip
    cd deep-sec-mcp
    </copy>
    ```

## Task 2: Create the MCP Environment File

1. Source the environment created by the prerequisite lab. Adjust the path if you extracted the ADB OCI IAM workshop elsewhere.

    ```bash
    <copy>
    source "$HOME/dbsec-labs/deep-data-security/adb-oci-iam/.adb-oci-iam.env"
    ./00_configure_lab_env.sh
    source ./.deep-sec-mcp.env
    </copy>

2. Confirm the imported database, tenancy, and IAM group values.

    ```bash
    <copy>
    env | grep -E '^(ADB_OCID|DB_NAME|OCI_DOMAIN_URL|TENANCY_OCID|OCI_IAM_EMPLOYEE_GROUP|OCI_IAM_MANAGER_GROUP)=' | sort
    </copy>

3. Discover the MCP-specific inputs and reload the environment.

    ```bash
    <copy>
    ./discover_mcp_inputs.sh
    source ./.deep-sec-mcp.env
    </copy>

The ADB OCI IAM lab continues to own the database, users, groups, OAuth configuration, HR objects, data roles, and data grants.

## Acknowledgements

* **Author** - Richard Evans
* **Last Updated By/Date** - Richard Evans, July 2026

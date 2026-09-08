# Lab 1: Import the ADB OCI IAM Environment

## Introduction

Use the database and IAM environment that the ADB OCI IAM workshop already created, after first proving the direct OCI IAM-to-ADB path in the Deep Security GenAI Demo lab. This lab copies only the values needed for MCP Server Tools into a separate local environment file; it makes no database or IAM changes.

### Objectives

- Import the shared ADB OCI IAM environment without changing it.
- Verify the GenAI identity and audit baseline before creating MCP resources.
- Discover the MCP-specific inputs required by the next lab.

Estimated Time: 5 minutes

### Prerequisites

- Completed ADB OCI IAM workshop.
- Its `.adb-oci-iam.env` file is available in Cloud Shell.
- Completed Deep Security GenAI Demo lab against the same ADB.

## Task 1: Download the MCP Scripts

1. In OCI Cloud Shell, download and extract the DeepSec MCP script bundle.

    ```bash
    <copy>
    export DBSEC_LABS="$HOME/dbsec-labs"
    mkdir -p "$DBSEC_LABS/deep-data-security"
    cd $DBSEC_LABS/deep-data-security
    wget -O deep-sec-mcp-cloudshell.zip https://objectstorage.us-ashburn-1.oraclecloud.com/p/eoQGRJ46zRptDtmOivg2aGZCvDUvGGYxJfCGeQICgy-cfC0i1CX6NYT0iwF2vGOS/n/oradbclouducm/b/dbsec_public/o/deep-sec-mcp-cloudshell.zip
    unzip -o deep-sec-mcp-cloudshell.zip
    cd deep-sec-mcp
    </copy>
    ```

## Task 2: Create the MCP Environment File

1. Source the environment created by the prerequisite lab. Adjust the path if you extracted the ADB OCI IAM workshop elsewhere.

    ```bash
    <copy>
    source "$HOME/dbsec-labs/deep-data-security/adb-oci-iam/.adb-oci-iam.env"
    export GENAI_LAB_DIR="$HOME/dbsec-labs/deep-data-security/deep-sec-gen-ai-demo"
    ./00_configure_lab_env.sh
    source ./.deep-sec-mcp.env
    </copy>

2. Confirm the imported database, tenancy, IAM group, and GenAI-lab values.

    ```bash
    <copy>
    env | grep -E '^(ADB_OCID|DB_NAME|OCI_DOMAIN_URL|TENANCY_OCID|OCI_IAM_EMPLOYEE_GROUP|OCI_IAM_MANAGER_GROUP|GENAI_LAB_DIR)=' | sort
    </copy>

## Task 3: Verify the GenAI Security Baseline

1. In a separate terminal, start the local GenAI service if it is not already running.

    ```bash
    <copy>
    cd "$GENAI_LAB_DIR"
    ./09_start_identity_service.sh
    </copy>
    ```

2. Return to the MCP terminal and run the read-only baseline verification.

    ```bash
    <copy>
    cd "$HOME/dbsec-labs/deep-data-security/deep-sec-mcp"
    source ./.deep-sec-mcp.env
    ./01_verify_genai_baseline.sh
    </copy>
    ```

    The verifier runs the direct GenAI identity proof and HR audit report. It
    does not prove that MCP will propagate the same identity; that is a later,
    dedicated MCP-to-ADB test.

## Task 4: Discover MCP-Specific Inputs

1. Discover the MCP-specific inputs and reload the environment.

    ```bash
    <copy>
    ./discover_mcp_inputs.sh
    source ./.deep-sec-mcp.env
    </copy>
    ```

2. Confirm the ownership boundary: the ADB OCI IAM lab continues to own the
    database, users, groups, OAuth configuration, HR objects, data roles, and
    data grants. The GenAI lab continues to own its local service and audit
    policy.

## Acknowledgements

* **Author** - Richard Evans
* **Last Updated By/Date** - Richard Evans, July 2026

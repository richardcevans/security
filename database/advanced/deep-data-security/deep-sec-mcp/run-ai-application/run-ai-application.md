# Lab 2: Run the AI Application

## Introduction

Configure and run a simple AI prompt simulator that connects to Autonomous Database. The simulator maps prompts to database tool calls so you can focus on secure data access.

Estimated Time: 15 minutes

### Objectives

In this lab, you will:

- Configure the simple AI prompt simulator.
- Run prompt-driven database tool calls against Autonomous Database.
- Capture the baseline data returned before you add MCP tools and security controls.

### Prerequisites

- Database connection values from Lab 1.
- Optional `.deep-sec-mcp.env` file from Lab 1.

## Task 1: Configure the Application

1. Configure the database connection.

    If you are using the optional scripts, source the same environment file and reuse the ADB service and wallet values.

    ```bash
    cd ~/security/database/advanced/deep-data-security/deep-sec-mcp
    source ./.deep-sec-mcp.env
    echo "ADB_SERVICE=${ADB_SERVICE}"
    echo "TNS_ADMIN=${TNS_ADMIN}"
    ```

## Task 2: Run the Application

1. Run the AI prompt simulator with the overprivileged ADMIN path.

    ```bash
    ./simulate_ai_tool_access.sh --mode admin --prompt all
    ```

2. Review the first prompt.

    The simulator prints the prompt, the SQL tool call it generated, and the live database result.

    ```text
    Show all employees, including salary, SSN, phone number, manager, and department.
    ```

3. Record whether the ADMIN-backed tool call returns sensitive data before security controls run.

## Task 3: Compare with Direct SQL

1. The simulator already prints the matching SQL. You can also run the sensitive-data query directly.

    ```bash
    sqlplus -L "admin/${ADMIN_PWD}@${ADB_SERVICE}"
    ```

    ```sql
    SELECT employee_id, first_name, last_name, user_name, ssn, salary, phone_number, manager_id
    FROM hr.employees
    ORDER BY employee_id;
    ```

    You may now proceed to the next lab.

## Acknowledgements

* **Author** - Richard Evans
* **Last Updated By/Date** - Richard Evans, July 2026

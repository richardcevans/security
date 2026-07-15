# Lab 2: Run the AI Application

## Introduction

Configure and run a simple AI application that connects to Autonomous Database. The app is prebuilt so you can focus on secure data access.

Estimated Time: 15 minutes

### Objectives

In this lab, you will:

- Configure the simple AI application.
- Run the app against Autonomous Database.
- Capture the baseline data returned before you add MCP tools and security controls.

### Prerequisites

- Simple AI application package or repository.
- Database connection values from Lab 1.
- Model provider and credentials for the selected app.
- Optional `.deep-sec-mcp.env` file from Lab 1.

## Task 1: Configure the Application

1. Open the simple AI application project.

    Use the application package selected by your workshop environment.

2. Configure the database connection.

    If you are using the optional scripts, source the same environment file and reuse the ADB service and wallet values.

    ```bash
    cd ~/security/database/advanced/deep-data-security/deep-sec-mcp
    source ./.deep-sec-mcp.env
    echo "ADB_SERVICE=${ADB_SERVICE}"
    echo "TNS_ADMIN=${TNS_ADMIN}"
    ```

3. Configure the model provider.

    Set the model provider values required by your selected application package.

## Task 2: Run the Application

1. Start the AI application.

2. Ask a baseline question that reads from the sample schema.

    Example prompt:

    ```text
    Show all employees, including salary, SSN, phone number, manager, and department.
    ```

3. Record whether the app returns sensitive data before security controls run.

## Task 3: Compare with Direct SQL

1. Run a matching SQL query directly against Autonomous Database.

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

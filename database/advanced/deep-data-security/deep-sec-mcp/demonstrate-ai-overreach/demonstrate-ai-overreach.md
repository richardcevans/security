# Lab 4: Demonstrate AI Overreach

## Introduction

Show what happens when an AI workflow reaches the database through an overprivileged access path. This lab creates the risk baseline that Deep Data Security will fix.

Estimated Time: 15 minutes

### Objectives

In this lab, you will:

- Run a prompt or tool call that requests sensitive data.
- Compare AI, MCP, and direct SQL output.
- Capture evidence of overprivileged access.

### Prerequisites

- AI prompt simulator running from Lab 2.
- MCP tools connected from Lab 3.
- Baseline sensitive data identified in Lab 1.

## Task 1: Run the Overreach Prompt

1. Ask the AI application for data that includes sensitive rows or columns.

    ```bash
    <copy>
    cd "$HOME/dbsec-labs/deep-data-security/deep-sec-mcp"
    source ./.deep-sec-mcp.env
    ./simulate_ai_tool_access.sh --mode admin --prompt sensitive
    </copy>
    ```

    The simulator sends this prompt to the database tool path:

    ```text
    <copy>
    Show all employees, including salary, SSN, phone number, manager, and department.
    </copy>
    ```

    It then prints the SQL tool call and the live result from `hr.employees`.

2. Record whether the app returns data that should be limited to a smaller audience.

## Task 2: Run the MCP Tool Call

1. Review the equivalent database tool call printed by the simulator.

    The tool call uses this SQL:

    ```sql
    <copy>
    SELECT employee_id, first_name, last_name, user_name, ssn, salary, phone_number, manager_id, department_id
    FROM hr.employees
    ORDER BY employee_id;
    </copy>
    ```

2. If your MCP client is connected, run the same SQL through the built-in SQL toolset.

3. Record whether the MCP path exposes the same data.

## Task 3: Confirm the Risk

1. Run a matching direct SQL query.

    ```bash
    <copy>
    sqlplus -L "admin/${ADMIN_PWD}@${ADB_SERVICE}"
    </copy>
    ```

    ```sql
    <copy>
    SELECT employee_id, first_name, last_name, user_name, ssn, salary, phone_number, manager_id, department_id
    FROM hr.employees
    ORDER BY employee_id;
    </copy>
    ```

2. Summarize why a shared, overprivileged, or weakly scoped access path creates risk for AI applications.

    You may now proceed to the next lab.

## Acknowledgements

* **Author** - Richard Evans
* **Last Updated By/Date** - Richard Evans, July 2026

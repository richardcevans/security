# End-User JSON Duality with Oracle Deep Data Security

## Introduction

JSON relational duality views let an application read relational data as JSON documents. Oracle Deep Data Security lets the database enforce which rows and columns each end user can access. In this lab, you combine both features with the simplest possible example: one table, one JSON duality view, two end users, and one data grant.

The application-facing object is a JSON employee card. The data is stored in a relational table, but end users query a JSON document view. Emma sees only Emma's JSON document. Marvin sees only Marvin's JSON document. The database applies that boundary even when the SQL query has no user filter.

### Objectives

In this lab, you will:

- Create a small relational table that stores employee card data
- Create a JSON relational duality view over that table
- Create two Oracle Database end users
- Grant access to the JSON duality view through a data role
- Use a data grant predicate to filter JSON documents by end-user identity
- Verify that each user only sees their own JSON document

Estimated Time: 25 minutes

### Prerequisites

This lab assumes you have:

- An Oracle AI Database 26ai Enterprise Edition instance with the April Release Update or later
- SQL*Plus installed and configured to connect to the pluggable database service `freepdb1`
- Access to a DBA account to run the setup tasks

On the DBSec-Lab VM, source the DB23 Free environment before running the SQL*Plus setup commands:

````
<copy>source $DBSEC_ADMIN/setEnv-db23free.sh FREE FREEPDB1</copy>
````

This sets `ORACLE_HOME`, `ORACLE_SID=FREE`, and `PDB_NAME=FREEPDB1`. If your terminal inherited wallet or TNS settings from another database home, clear them before continuing:

````
<copy>unset WALLET_DIR TNS_ADMIN</copy>
````

Connect to `freepdb1` as your DBA user before running Task 1.

````
<copy>sqlplus <dba_user>/<password>@freepdb1</copy>
````

## Task 1: Create a Deep Data Security Administrator

Create a dedicated administrator account for the lab. This keeps the setup separate from the end users who will query the JSON documents.

1. From your OS command prompt, connect to `freepdb1` as `SYS`.

    ````
    <copy>sqlplus sys/Oracle123@freepdb1 as sysdba</copy>
    ````

2. Create `DEEPSEC_ADMIN` and grant the privileges needed to create the schema, duality view, end users, data role, and data grant.

    ```sql
    <copy>
    CREATE USER deepsec_admin IDENTIFIED BY Oracle123;

    GRANT CREATE SESSION TO deepsec_admin WITH ADMIN OPTION;
    GRANT CREATE USER TO deepsec_admin;
    GRANT ALTER USER TO deepsec_admin;
    GRANT DROP USER TO deepsec_admin;
    GRANT CREATE ANY TABLE TO deepsec_admin;
    GRANT ALTER ANY TABLE TO deepsec_admin;
    GRANT DROP ANY TABLE TO deepsec_admin;
    GRANT INSERT ANY TABLE TO deepsec_admin;
    GRANT SELECT ANY TABLE TO deepsec_admin;
    GRANT CREATE ANY VIEW TO deepsec_admin;
    GRANT DROP ANY VIEW TO deepsec_admin;
    GRANT CREATE ROLE TO deepsec_admin;
    GRANT DROP ANY ROLE TO deepsec_admin;
    GRANT GRANT ANY ROLE TO deepsec_admin;
    GRANT SELECT_CATALOG_ROLE TO deepsec_admin;

    GRANT CREATE END USER TO deepsec_admin;
    GRANT DROP END USER TO deepsec_admin;
    GRANT CREATE DATA ROLE TO deepsec_admin;
    GRANT DROP DATA ROLE TO deepsec_admin;
    GRANT GRANT ANY DATA ROLE TO deepsec_admin;
    GRANT CREATE ANY DATA GRANT TO deepsec_admin;
    GRANT DROP ANY DATA GRANT TO deepsec_admin;
    GRANT ADMINISTER ANY DATA GRANT TO deepsec_admin;
    </copy>
    ```

3. Connect as `DEEPSEC_ADMIN`.

    ```sql
    <copy>
    CONNECT deepsec_admin/Oracle123@freepdb1
    </copy>
    ```

## Task 2: Create a Relational Table and JSON Duality View

In this task, you create a schema-only account named `JSONLAB`. It owns one relational table and one JSON relational duality view.

1. Create the `JSONLAB` schema.

    ```sql
    <copy>
    CREATE USER jsonlab NO AUTHENTICATION DEFAULT TABLESPACE users;
    ALTER USER jsonlab QUOTA UNLIMITED ON users;
    </copy>
    ```

2. Create a table for the employee card data.

    ```sql
    <copy>
    CREATE TABLE jsonlab.employee_cards (
      employee_id   NUMBER PRIMARY KEY,
      user_name     VARCHAR2(128) NOT NULL,
      display_name  VARCHAR2(100) NOT NULL,
      job_title     VARCHAR2(100) NOT NULL,
      department    VARCHAR2(60) NOT NULL,
      salary        NUMBER(10,2) NOT NULL
    );

    INSERT INTO jsonlab.employee_cards
      (employee_id, user_name, display_name, job_title, department, salary)
    VALUES
      (1, 'emma', 'Emma Baker', 'Product Manager', 'Product', 120000);

    INSERT INTO jsonlab.employee_cards
      (employee_id, user_name, display_name, job_title, department, salary)
    VALUES
      (2, 'marvin', 'Marvin Morgan', 'Engineering Manager', 'Engineering', 175000);

    INSERT INTO jsonlab.employee_cards
      (employee_id, user_name, display_name, job_title, department, salary)
    VALUES
      (3, 'dana', 'Dana Lee', 'Security Analyst', 'Security', 130000);

    COMMIT;
    </copy>
    ```

3. Create the JSON relational duality view. The view exposes each row as one JSON document in the `DATA` column.

    ```sql
    <copy>
    CREATE OR REPLACE JSON RELATIONAL DUALITY VIEW jsonlab.employee_card_dv AS
    SELECT JSON {
      '_id'        : employee_id,
      'userName'   : user_name,
      'name'       : display_name,
      'title'      : job_title,
      'department' : department,
      'salary'     : salary
    }
    FROM jsonlab.employee_cards;
    </copy>
    ```

4. Query the duality view as the administrator. You should see three JSON documents.

    ```sql
    <copy>
    SELECT json_serialize(data PRETTY) AS employee_document
      FROM jsonlab.employee_card_dv
     ORDER BY json_value(data, '$._id' RETURNING NUMBER);
    </copy>
    ```

    ```json
    {
      "_id" : 1,
      "userName" : "emma",
      "name" : "Emma Baker",
      "title" : "Product Manager",
      "department" : "Product",
      "salary" : 120000
    }
    ```

    The administrator can see every document. The end users will not get that broad access.

## Task 3: Create End Users and a Data Role

Create two end users and a data role that carries the ability to connect to the database.

1. Create Emma and Marvin as Oracle Database end users.

    ```sql
    <copy>
    CREATE END USER emma IDENTIFIED BY Oracle123;
    CREATE END USER marvin IDENTIFIED BY Oracle123;
    </copy>
    ```

2. Create a database role for direct SQL*Plus connections.

    ```sql
    <copy>
    CREATE ROLE direct_logon_role;
    GRANT CREATE SESSION TO direct_logon_role;
    </copy>
    ```

3. Create one data role for users of the JSON application.

    ```sql
    <copy>
    CREATE DATA ROLE json_app_users;
    GRANT direct_logon_role TO json_app_users;
    </copy>
    ```

4. Grant the data role to Emma and Marvin.

    ```sql
    <copy>
    GRANT DATA ROLE json_app_users TO emma;
    GRANT DATA ROLE json_app_users TO marvin;
    </copy>
    ```

## Task 4: Create a Data Grant on the JSON Duality View

The JSON duality view has one column named `DATA`. The data grant allows users to select that column, but only for documents where the JSON `userName` field matches the authenticated end user.

1. Create the data grant.

    ```sql
    <copy>
    CREATE OR REPLACE DATA GRANT jsonlab.employee_card_json_access
      AS SELECT
      ON jsonlab.employee_card_dv
      WHERE upper(json_value(data, '$.userName' RETURNING VARCHAR2(128))) =
            upper(ORA_END_USER_CONTEXT.username)
      TO json_app_users;
    </copy>
    ```

2. Review the data grant predicate.

    ```sql
    <copy>
    SELECT grant_name, object_owner, object_name, predicate
      FROM dba_data_grants
     WHERE grant_name = 'EMPLOYEE_CARD_JSON_ACCESS';
    </copy>
    ```

    The predicate uses the JSON document itself for the row filter. The database extracts `$.userName` from the duality view document and compares it to `ORA_END_USER_CONTEXT.username`.

3. Exit SQL*Plus before reconnecting as an end user.

    ```sql
    <copy>
    EXIT
    </copy>
    ```

## Task 5: Verify JSON Access as Emma

Emma queries the JSON duality view without adding a `WHERE` clause. The database still returns only Emma's document.

1. Connect as Emma.

    ````
    <copy>sqlplus emma/Oracle123@freepdb1</copy>
    ````

2. Confirm the authenticated end-user identity.

    ```sql
    <copy>
    SELECT ORA_END_USER_CONTEXT.username AS username FROM dual;
    </copy>
    ```

    ````
    USERNAME
    --------------------------------------------------------------------------------
    "EMMA"
    ````

3. Query all JSON documents from the duality view.

    ```sql
    <copy>
    SELECT json_serialize(data PRETTY) AS employee_document
      FROM jsonlab.employee_card_dv
     ORDER BY json_value(data, '$._id' RETURNING NUMBER);
    </copy>
    ```

    Emma sees one document.

    ```json
    {
      "_id" : 1,
      "userName" : "emma",
      "name" : "Emma Baker",
      "title" : "Product Manager",
      "department" : "Product",
      "salary" : 120000
    }
    ```

4. Try to query Marvin's document by JSON field.

    ```sql
    <copy>
    SELECT json_serialize(data PRETTY) AS employee_document
      FROM jsonlab.employee_card_dv
     WHERE json_value(data, '$.userName') = 'marvin';
    </copy>
    ```

    ````
    no rows selected
    ````

    Emma queried the same JSON duality view as the administrator, but the database added the data grant predicate at execution time.

5. Exit SQL*Plus.

    ```sql
    <copy>
    EXIT
    </copy>
    ```

## Task 6: Verify JSON Access as Marvin

Marvin runs the same broad query. The database returns Marvin's JSON document, not Emma's and not Dana's.

1. Connect as Marvin.

    ````
    <copy>sqlplus marvin/Oracle123@freepdb1</copy>
    ````

2. Query all JSON documents from the duality view.

    ```sql
    <copy>
    SELECT json_serialize(data PRETTY) AS employee_document
      FROM jsonlab.employee_card_dv
     ORDER BY json_value(data, '$._id' RETURNING NUMBER);
    </copy>
    ```

    Marvin sees one document.

    ```json
    {
      "_id" : 2,
      "userName" : "marvin",
      "name" : "Marvin Morgan",
      "title" : "Engineering Manager",
      "department" : "Engineering",
      "salary" : 175000
    }
    ```

3. Count the documents Marvin can access.

    ```sql
    <copy>
    SELECT count(*) AS visible_documents
      FROM jsonlab.employee_card_dv;
    </copy>
    ```

    ````
    VISIBLE_DOCUMENTS
    -----------------
                    1
    ````

    The duality view exposes JSON documents, but the security decision is still enforced by the database. Any application, tool, or agent using Marvin's identity receives only Marvin's authorized JSON document.

4. Exit SQL*Plus.

    ```sql
    <copy>
    EXIT
    </copy>
    ```

## Task 7: Clean Up

Remove the objects created by this lab if you want to run it again from a clean state.

1. Connect as `DEEPSEC_ADMIN`.

    ````
    <copy>sqlplus deepsec_admin/Oracle123@freepdb1</copy>
    ````

2. Drop the data grant, data role, database role, and end users.

    ```sql
    <copy>
    DROP DATA GRANT jsonlab.employee_card_json_access;
    DROP DATA ROLE json_app_users;
    DROP ROLE direct_logon_role;
    DROP END USER emma;
    DROP END USER marvin;
    </copy>
    ```

3. Exit and reconnect as `SYS`.

    ```sql
    <copy>
    EXIT
    </copy>
    ```

    ````
    <copy>sqlplus sys/Oracle123@freepdb1 as sysdba</copy>
    ````

4. Drop the lab schemas.

    ```sql
    <copy>
    DROP USER jsonlab CASCADE;
    DROP USER deepsec_admin CASCADE;
    </copy>
    ```

## What You Built

You built a minimal JSON duality security model:

| Component | Purpose |
|---|---|
| `JSONLAB.EMPLOYEE_CARDS` | Relational table that stores the employee card rows |
| `JSONLAB.EMPLOYEE_CARD_DV` | JSON relational duality view that exposes each row as a JSON document |
| `EMMA` and `MARVIN` | Oracle Database end users |
| `JSON_APP_USERS` | Data role granted to the end users |
| `EMPLOYEE_CARD_JSON_ACCESS` | Data grant that filters JSON documents by `$.userName` |
| `ORA_END_USER_CONTEXT.username` | Built-in end-user identity used by the data grant predicate |
{: title="Lab components"}

The key point is that the JSON document shape did not move security into the application. The database enforced the end-user boundary on the duality view.

## Learn More

- [Oracle AI Database JSON-Relational Duality Developer's Guide](https://docs.oracle.com/en/database/oracle/oracle-database/26/jsnvu/index.html)
- [Oracle Deep Data Security Configuration Guide](https://docs.oracle.com/en/database/oracle/oracle-database/26/ddscg/index.html)

## Acknowledgements

- **Author** - Richard C. Evans, Oracle Database Security Product Management
- **Last Updated By/Date** - Richard C. Evans, Oracle Database Security Product Management, May 2026

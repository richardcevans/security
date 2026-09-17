Rem
Rem Copyright (c) 2026, Oracle and/or its affiliates.
Rem
Rem NAME
Rem   setup.sql - Consolidated OCI IAM and Oracle Deep Data Security setup
Rem   for the LangChain OCI IAM HR and Compensation Agents.
Rem
Rem DESCRIPTION
Rem   This script consolidates the SQL that was applied to create the sample
Rem   HR schema, Deep Data Security roles and grants, location/department
Rem   reference data, performance notes, and the compensation application
Rem   identity.
Rem
Rem WARNING
Rem   Section 1 drops and recreates the HR user. Run this only to build a new
Rem   demo schema. Do not run it against the existing populated ADB used by
Rem   the application.
Rem
Rem PREREQUISITES
Rem   - Connect as the Autonomous AI Database ADMIN user.
Rem   - OCI IAM external authentication must already be configured for the
Rem     database resource application.
Rem   - Replace the DEFINE values with values for the target environment.
Rem
Rem This script intentionally does not configure the database identity provider
Rem or its OCI IAM credential. Those values are database-instance settings and
Rem are managed separately from this schema setup.
Rem

SET ECHO ON
SET FEEDBACK ON
SET SERVEROUTPUT ON
SET LINESIZE 200
SET PAGESIZE 100
SET VERIFY OFF
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK

----------------------------------------------------------------------------
-- Configuration
----------------------------------------------------------------------------

DEFINE MARVIN_USERNAME = marvin
DEFINE EMMA_USERNAME = emma
DEFINE HANNAH_USERNAME = replace-with-hannah-oci-iam-username

DEFINE OCI_IAM_EMPLOYEE_GROUP = EMPLOYEES
DEFINE OCI_IAM_MANAGER_GROUP = MANAGERS

DEFINE APP_DB_USER = db_usr
DEFINE APP_DB_PASSWORD = replace-with-database-connection-pool-password

Rem OAuth Client ID of the COMPENSATION_AGENT OCI IAM application.
Rem This is COMP_DB_CLIENT_ID in the application .env file, not the
Rem browser-login client's client ID.
DEFINE COMPENSATION_APP_CLIENT_ID = replace-with-compensation-agent-oauth-client-id

----------------------------------------------------------------------------
-- 1. Create the HR schema and original employee sample data
--
-- Source: 02_create_hr_schema.sh. This section is destructive.
----------------------------------------------------------------------------

BEGIN
  EXECUTE IMMEDIATE 'DROP USER hr CASCADE';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE != -1918 THEN
      RAISE;
    END IF;
END;
/

CREATE USER hr NO AUTHENTICATION
  DEFAULT TABLESPACE data
  QUOTA UNLIMITED ON data;

CREATE TABLE hr.employees (
  employee_id   NUMBER PRIMARY KEY,
  first_name    VARCHAR2(50),
  last_name     VARCHAR2(50),
  job_code      VARCHAR2(10),
  department_id NUMBER,
  ssn           VARCHAR2(20),
  photo         BLOB,
  phone_number  VARCHAR2(30),
  salary        NUMBER(10,2),
  user_name     VARCHAR2(128),
  manager_id    NUMBER
);

INSERT INTO hr.employees VALUES (
  1, 'Grace', 'Young', 'CEO', NULL, '111-11-1111', NULL,
  '555-100-0001', 235000, 'grace', NULL
);
INSERT INTO hr.employees VALUES (
  2, 'Marvin', 'Morgan', 'SWE_MGR', 1, '222-22-2222', NULL,
  '555-100-0002', 175000, '&MARVIN_USERNAME', 1
);
INSERT INTO hr.employees VALUES (
  3, 'Emma', 'Baker', 'SWE2', 1, '333-33-3333', NULL,
  '555-100-0003', 120000, '&EMMA_USERNAME', 2
);
INSERT INTO hr.employees VALUES (
  4, 'Charlie', 'Davis', 'SWE1', 1, '444-44-4444', NULL,
  '555-100-0004', 95000, 'charlie', 2
);
INSERT INTO hr.employees VALUES (
  5, 'Dana', 'Lee', 'SWE3', 1, '555-55-5555', NULL,
  '555-100-0005', 130000, 'dana', 2
);
INSERT INTO hr.employees VALUES (
  6, 'Bob', 'Smith', 'SALES_REP', 2, '666-66-6666', NULL,
  '555-100-0006', 145000, 'bob', 1
);
INSERT INTO hr.employees VALUES (
  7, 'Fiona', 'Chen', 'HR_REP', 3, '777-77-7777', NULL,
  '555-100-0007', 92000, 'fiona', 1
);

COMMIT;

----------------------------------------------------------------------------
-- 2. Reporting-hierarchy lookup
--
-- Kept separate from HR.EMPLOYEES so manager data-grant predicates can use
-- the hierarchy without creating a cyclic predicate on HR.EMPLOYEES.
----------------------------------------------------------------------------

CREATE TABLE hr.managers (
  employee_id NUMBER PRIMARY KEY,
  manager_id  NUMBER,
  user_name   VARCHAR2(128) NOT NULL,
  CONSTRAINT managers_employee_fk
    FOREIGN KEY (employee_id) REFERENCES hr.employees(employee_id),
  CONSTRAINT managers_manager_fk
    FOREIGN KEY (manager_id) REFERENCES hr.employees(employee_id)
);

MERGE INTO hr.managers target
USING (
  SELECT employee_id, manager_id, user_name
  FROM hr.employees
) source
ON (target.employee_id = source.employee_id)
WHEN MATCHED THEN UPDATE SET
  target.manager_id = source.manager_id,
  target.user_name = source.user_name
WHEN NOT MATCHED THEN INSERT (
  employee_id, manager_id, user_name
) VALUES (
  source.employee_id, source.manager_id, source.user_name
);

----------------------------------------------------------------------------
-- 3. Deep Data Security roles and HR grants
--
-- Source: 03_create_data_roles_and_grants.sh.
----------------------------------------------------------------------------

DECLARE
  user_exists NUMBER;
BEGIN
  SELECT COUNT(*)
    INTO user_exists
    FROM dba_users
   WHERE username = UPPER('&APP_DB_USER');

  IF user_exists = 0 THEN
    EXECUTE IMMEDIATE
      'CREATE USER &APP_DB_USER IDENTIFIED BY "&APP_DB_PASSWORD"';
  ELSE
    BEGIN
      EXECUTE IMMEDIATE
        'ALTER USER &APP_DB_USER IDENTIFIED BY "&APP_DB_PASSWORD" ACCOUNT UNLOCK';
    EXCEPTION
      WHEN OTHERS THEN
        IF SQLCODE = -28007 THEN
          EXECUTE IMMEDIATE 'ALTER USER &APP_DB_USER ACCOUNT UNLOCK';
        ELSE
          RAISE;
        END IF;
    END;
  END IF;
END;
/

GRANT CREATE SESSION TO &APP_DB_USER;
GRANT CREATE END USER SECURITY CONTEXT TO &APP_DB_USER;

CREATE OR REPLACE DATA ROLE hrapp_employees
  MAPPED TO 'IAM_OAUTH_GROUP=&OCI_IAM_EMPLOYEE_GROUP';

CREATE OR REPLACE DATA ROLE hrapp_managers
  MAPPED TO 'IAM_OAUTH_GROUP=&OCI_IAM_MANAGER_GROUP';

CREATE ROLE IF NOT EXISTS direct_logon_role;
GRANT CREATE SESSION TO direct_logon_role;
GRANT direct_logon_role TO HRAPP_EMPLOYEES;
GRANT direct_logon_role TO HRAPP_MANAGERS;

CREATE OR REPLACE DATA GRANT hr.hrapp_employees_access
  AS SELECT,
     UPDATE (phone_number, first_name, last_name)
  ON hr.employees
  WHERE upper(user_name) = upper(ora_end_user_context.username)
  TO hrapp_employees;

-- Employees can browse the company directory, but compensation and SSNs
-- remain visible only through their self-access grant above.
CREATE OR REPLACE DATA GRANT hr.hrapp_employee_directory_access
  AS SELECT (ALL COLUMNS EXCEPT ssn, salary)
  ON hr.employees
  WHERE 1 = 1
  TO hrapp_employees;

CREATE OR REPLACE DATA GRANT hr.mgr_hierarchy
  AS SELECT (ALL COLUMNS EXCEPT ssn), UPDATE (salary, department_id, first_name)
  ON hr.employees
  WHERE employee_id IN (
    SELECT employee_id
    FROM hr.managers
    START WITH employee_id = (
      SELECT employee_id
      FROM hr.managers
      WHERE UPPER(user_name) = UPPER(ora_end_user_context.username)
    )
    CONNECT BY PRIOR employee_id = manager_id
  )
  TO hrapp_managers;

----------------------------------------------------------------------------
-- 4. Location and department reference tables and data
--
-- These statements were added after the original two setup scripts.
----------------------------------------------------------------------------

DECLARE
  table_count NUMBER;
BEGIN
  SELECT COUNT(*)
    INTO table_count
    FROM all_tables
   WHERE owner = 'HR'
     AND table_name = 'LOCATIONS';

  IF table_count = 0 THEN
    EXECUTE IMMEDIATE q'[
      CREATE TABLE hr.locations (
        location_id    NUMBER PRIMARY KEY,
        city           VARCHAR2(100) NOT NULL,
        state_province VARCHAR2(100),
        country_id     VARCHAR2(2) NOT NULL
      )
    ]';
  END IF;
END;
/

DECLARE
  table_count NUMBER;
BEGIN
  SELECT COUNT(*)
    INTO table_count
    FROM all_tables
   WHERE owner = 'HR'
     AND table_name = 'DEPARTMENTS';

  IF table_count = 0 THEN
    EXECUTE IMMEDIATE q'[
      CREATE TABLE hr.departments (
        department_id   NUMBER PRIMARY KEY,
        department_name VARCHAR2(100) NOT NULL,
        location_id     NUMBER NOT NULL,
        CONSTRAINT departments_location_fk
          FOREIGN KEY (location_id) REFERENCES hr.locations(location_id)
      )
    ]';
  END IF;
END;
/

MERGE INTO hr.locations target
USING (
  SELECT 100 location_id, 'Seattle' city, 'WA' state_province, 'US' country_id FROM dual
  UNION ALL SELECT 110, 'Austin', 'TX', 'US' FROM dual
  UNION ALL SELECT 120, 'New York', 'NY', 'US' FROM dual
) source
ON (target.location_id = source.location_id)
WHEN MATCHED THEN UPDATE SET
  target.city = source.city,
  target.state_province = source.state_province,
  target.country_id = source.country_id
WHEN NOT MATCHED THEN INSERT (
  location_id, city, state_province, country_id
) VALUES (
  source.location_id, source.city, source.state_province, source.country_id
);

MERGE INTO hr.departments target
USING (
  SELECT 1 department_id, 'Engineering' department_name, 100 location_id FROM dual
  UNION ALL SELECT 2, 'Sales', 110 FROM dual
  UNION ALL SELECT 3, 'Human Resources', 120 FROM dual
) source
ON (target.department_id = source.department_id)
WHEN MATCHED THEN UPDATE SET
  target.department_name = source.department_name,
  target.location_id = source.location_id
WHEN NOT MATCHED THEN INSERT (
  department_id, department_name, location_id
) VALUES (
  source.department_id, source.department_name, source.location_id
);

----------------------------------------------------------------------------
-- 5. Hannah employee mapping and performance notes
----------------------------------------------------------------------------

MERGE INTO hr.employees target
USING (
  SELECT
    8 employee_id,
    'Hannah' first_name,
    'Mavris' last_name,
    'HR_REP' job_code,
    3 department_id,
    '888-88-8888' ssn,
    '555-100-0008' phone_number,
    98000 salary,
    '&HANNAH_USERNAME' user_name,
    1 manager_id
  FROM dual
) source
ON (target.employee_id = source.employee_id)
WHEN MATCHED THEN UPDATE SET
  target.first_name = source.first_name,
  target.last_name = source.last_name,
  target.job_code = source.job_code,
  target.department_id = source.department_id,
  target.phone_number = source.phone_number,
  target.salary = source.salary,
  target.user_name = source.user_name,
  target.manager_id = source.manager_id
WHEN NOT MATCHED THEN INSERT (
  employee_id, first_name, last_name, job_code, department_id,
  ssn, photo, phone_number, salary, user_name, manager_id
) VALUES (
  source.employee_id, source.first_name, source.last_name,
  source.job_code, source.department_id, source.ssn, NULL,
  source.phone_number, source.salary, source.user_name, source.manager_id
);

MERGE INTO hr.managers target
USING (
  SELECT employee_id, manager_id, user_name
  FROM hr.employees
) source
ON (target.employee_id = source.employee_id)
WHEN MATCHED THEN UPDATE SET
  target.manager_id = source.manager_id,
  target.user_name = source.user_name
WHEN NOT MATCHED THEN INSERT (
  employee_id, manager_id, user_name
) VALUES (
  source.employee_id, source.manager_id, source.user_name
);

DECLARE
  table_count NUMBER;
BEGIN
  SELECT COUNT(*)
    INTO table_count
    FROM all_tables
   WHERE owner = 'HR'
     AND table_name = 'PERFORMANCE_NOTES';

  IF table_count = 0 THEN
    EXECUTE IMMEDIATE q'[
      CREATE TABLE hr.performance_notes (
        note_id              NUMBER GENERATED BY DEFAULT AS IDENTITY PRIMARY KEY,
        employee_id          NUMBER NOT NULL,
        manager_id           NUMBER NOT NULL,
        manager_private_note VARCHAR2(4000),
        employee_feedback    VARCHAR2(4000),
        created_at           TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
        CONSTRAINT perf_notes_employee_fk
          FOREIGN KEY (employee_id) REFERENCES hr.employees(employee_id),
        CONSTRAINT perf_notes_manager_fk
          FOREIGN KEY (manager_id) REFERENCES hr.employees(employee_id),
        CONSTRAINT perf_notes_has_content_ck
          CHECK (
            manager_private_note IS NOT NULL
            OR employee_feedback IS NOT NULL
          )
      )
    ]';
  END IF;
END;
/

INSERT INTO hr.performance_notes (
  employee_id, manager_id, manager_private_note, employee_feedback
)
SELECT
  3,
  2,
  'Emma is a high-potential employee. Keep private coaching notes here.',
  'Good progress this quarter; continue improving status updates.'
FROM dual
WHERE NOT EXISTS (
  SELECT 1
  FROM hr.performance_notes
  WHERE employee_id = 3
    AND manager_id = 2
);

INSERT INTO hr.performance_notes (
  employee_id, manager_id, manager_private_note, employee_feedback
)
SELECT
  4,
  2,
  'Charlie needs additional mentoring before the next promotion review.',
  'Strong implementation work; focus on proactive project communication.'
FROM dual
WHERE NOT EXISTS (
  SELECT 1
  FROM hr.performance_notes
  WHERE employee_id = 4
    AND manager_id = 2
);

CREATE OR REPLACE DATA GRANT hr.performance_notes_manager_dg
  AS SELECT,
     INSERT (
       employee_id,
       manager_id,
       manager_private_note,
       employee_feedback
     ),
     UPDATE (manager_private_note, employee_feedback),
     DELETE
  ON hr.performance_notes
  WHERE manager_id = (
    SELECT m.employee_id
    FROM hr.employees m
    WHERE UPPER(m.user_name) = UPPER(ora_end_user_context.username)
  )
    AND employee_id IN (
      SELECT e.employee_id
      FROM hr.employees e
      WHERE e.manager_id = (
        SELECT m.employee_id
        FROM hr.employees m
        WHERE UPPER(m.user_name) = UPPER(ora_end_user_context.username)
      )
    )
  TO hrapp_managers;

CREATE OR REPLACE DATA GRANT hr.performance_notes_employee_dg
  AS SELECT (note_id, employee_id, manager_id, employee_feedback, created_at)
  ON hr.performance_notes
  WHERE employee_id = (
    SELECT e.employee_id
    FROM hr.employees e
    WHERE UPPER(e.user_name) = UPPER(ora_end_user_context.username)
  )
  TO hrapp_employees;

----------------------------------------------------------------------------
-- 6. Compensation application identity and read-only compensation grants
----------------------------------------------------------------------------

CREATE OR REPLACE APPLICATION IDENTITY compensation_app
  MAPPED TO 'IAM_OAUTH_CLIENT_ID=&COMPENSATION_APP_CLIENT_ID';

CREATE DATA ROLE IF NOT EXISTS salary_agent_fs_role;

GRANT DATA ROLE salary_agent_fs_role TO compensation_app;

CREATE OR REPLACE DATA GRANT hr.sal_agent
  AS SELECT (
    ALL COLUMNS EXCEPT
      employee_id,
      first_name,
      last_name,
      user_name,
      phone_number,
      ssn
  )
  ON hr.employees
  WHERE 1 = 1
  TO salary_agent_fs_role;

CREATE OR REPLACE DATA GRANT hr.sal_agent_departments
  AS SELECT
  ON hr.departments
  TO salary_agent_fs_role;

CREATE OR REPLACE DATA GRANT hr.sal_agent_locations
  AS SELECT
  ON hr.locations
  TO salary_agent_fs_role;

COMMIT;

----------------------------------------------------------------------------
-- Verification
----------------------------------------------------------------------------

COLUMN user_name FORMAT A45
SELECT employee_id, first_name, last_name, job_code, department_id, user_name
FROM hr.employees
ORDER BY employee_id;

SELECT d.department_id, d.department_name, l.city, l.state_province
FROM hr.departments d
JOIN hr.locations l
  ON l.location_id = d.location_id
ORDER BY d.department_id;

SELECT note_id, employee_id, manager_id, employee_feedback, created_at
FROM hr.performance_notes
ORDER BY note_id;

SELECT data_role, mapped_to
FROM dba_data_roles
WHERE data_role IN (
  'HRAPP_EMPLOYEES',
  'HRAPP_MANAGERS',
  'SALARY_AGENT_FS_ROLE'
)
ORDER BY data_role;

SELECT *
FROM dba_application_identities;

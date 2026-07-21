SET ECHO ON
SET SERVEROUTPUT ON
WHENEVER SQLERROR EXIT SQL.SQLCODE

CREATE OR REPLACE VIEW hr.employee_compensation_ai AS
SELECT
  e.employee_id,
  e.first_name || ' ' || e.last_name AS employee_name,
  e.department_id,
  e.manager_id,
  e.job_code AS job_title,
  e.salary AS base_salary,
  NVL(b.bonus_amount, 0) AS bonus_amount,
  e.salary + NVL(b.bonus_amount, 0) AS total_compensation
FROM hr.employees e
LEFT JOIN hr.employee_bonuses_ext b
  ON b.employee_id = e.employee_id
 AND b.bonus_year = 2026;

COMMENT ON TABLE hr.employee_compensation_ai IS
  'Curated synthetic compensation view for the Deep Data Security GenAI demo.';

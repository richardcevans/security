-- Copyright (c) 2026, Oracle and/or its affiliates.
--
-- Creates the Select AI SQL Tool, Agent, Task, and Team used by the Python
-- application, then shares the profile and team with the role inherited by
-- token-authenticated Deep Data Security users.
--
-- Run as the schema that owns the Select AI profile (normally DB_USR), after
-- the credential and profile have been created. The ADMIN setup script grants
-- the required DBMS_CLOUD_AI_AGENT privilege.

SET DEFINE ON
SET SERVEROUTPUT ON
WHENEVER SQLERROR EXIT SQL.SQLCODE ROLLBACK

-- Define these values before running the script. If omitted, SQLcl/SQL*Plus
-- prompts for each value when it is first referenced.
--
-- DEFINE PROFILE_OWNER = DB_USR
-- DEFINE PROFILE_NAME = HR_PROFILE
-- DEFINE AGENT_NAME = HR_AGENT
-- DEFINE TASK_NAME = HR_TASK
-- DEFINE TEAM_NAME = HR_TEAM
-- DEFINE SQL_TOOL_NAME = HR_SQL_TOOL
-- DEFINE RUNNER_ROLE = HR_SELECT_AI_RUNNER

PROMPT Recreating Select AI Agent Team objects
DECLARE
  l_count PLS_INTEGER;
BEGIN
  SELECT COUNT(*) INTO l_count
  FROM user_ai_agent_teams
  WHERE agent_team_name = UPPER('&TEAM_NAME');
  IF l_count > 0 THEN
    DBMS_CLOUD_AI_AGENT.DROP_TEAM(team_name => '&TEAM_NAME', force => TRUE);
  END IF;

  SELECT COUNT(*) INTO l_count
  FROM user_ai_agent_tasks
  WHERE task_name = UPPER('&TASK_NAME');
  IF l_count > 0 THEN
    DBMS_CLOUD_AI_AGENT.DROP_TASK(task_name => '&TASK_NAME', force => TRUE);
  END IF;

  SELECT COUNT(*) INTO l_count
  FROM user_ai_agent_tools
  WHERE tool_name = UPPER('&SQL_TOOL_NAME');
  IF l_count > 0 THEN
    DBMS_CLOUD_AI_AGENT.DROP_TOOL(tool_name => '&SQL_TOOL_NAME', force => TRUE);
  END IF;

  SELECT COUNT(*) INTO l_count
  FROM user_ai_agents
  WHERE agent_name = UPPER('&AGENT_NAME');
  IF l_count > 0 THEN
    DBMS_CLOUD_AI_AGENT.DROP_AGENT(agent_name => '&AGENT_NAME', force => TRUE);
  END IF;
END;
/

BEGIN
  DBMS_CLOUD_AI_AGENT.CREATE_TOOL(
    tool_name  => '&SQL_TOOL_NAME',
    attributes => '{
      "tool_type": "SQL",
      "tool_params": {
        "profile_name": "{llm_profile}"
      },
      "instruction": "Generate and run read-only SQL only. Use only data the current user is authorized to see. Return grounded, concise answers and never invent data."
    }',
    description => 'Read-only SQL tool for the HR Select AI profile'
  );

  DBMS_CLOUD_AI_AGENT.CREATE_AGENT(
    agent_name  => '&AGENT_NAME',
    attributes  => '{
      "profile_name": "{llm_profile}",
      "role": "You are an HR assistant. Use the available SQL tool to answer questions about authorized HR data. Keep answers concise and grounded in query results.",
      "tools": ["&SQL_TOOL_NAME"]
    }',
    description => 'HR assistant agent'
  );

  DBMS_CLOUD_AI_AGENT.CREATE_TASK(
    task_name   => '&TASK_NAME',
    attributes  => '{
      "instruction": "Answer the user''s HR question using the SQL tool and only authorized HR data. If data is not visible, say so rather than inventing values.",
      "tools": ["&SQL_TOOL_NAME"]
    }',
    description => 'Task for answering HR questions'
  );

  DBMS_CLOUD_AI_AGENT.CREATE_TEAM(
    team_name   => '&TEAM_NAME',
    attributes  => '{
      "agents": [
        {
          "name": "&AGENT_NAME",
          "task": "&TASK_NAME"
        }
      ],
      "process": "sequential"
    }',
    description => 'Single-agent HR team'
  );
END;
/

PROMPT Granting Select AI profile and team access to the Deep Sec runner role
BEGIN
  DBMS_CLOUD_AI.GRANT_PROFILE_ACCESS(
    '&PROFILE_OWNER..&PROFILE_NAME',
    '&RUNNER_ROLE'
  );
  DBMS_CLOUD_AI_AGENT.GRANT_TEAM_ACCESS(
    '&PROFILE_OWNER..&TEAM_NAME',
    '&RUNNER_ROLE'
  );
END;
/

PROMPT Verifying created objects
SELECT agent_name, status FROM user_ai_agents WHERE agent_name = UPPER('&AGENT_NAME');
SELECT task_name, status FROM user_ai_agent_tasks WHERE task_name = UPPER('&TASK_NAME');
SELECT tool_name, status FROM user_ai_agent_tools WHERE tool_name = UPPER('&SQL_TOOL_NAME');
SELECT agent_team_name, status FROM user_ai_agent_teams WHERE agent_team_name = UPPER('&TEAM_NAME');

PROMPT Select AI Agent Team setup completed successfully.

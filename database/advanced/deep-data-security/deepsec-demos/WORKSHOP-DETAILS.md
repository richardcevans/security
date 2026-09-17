# Workshop Details

## Short Description

Run five independent Oracle Deep Data Security demonstrations that protect AI
and MCP database access with OCI IAM or Microsoft Entra ID.

## Long Description

AI applications need useful database access without receiving more rows or
columns than the signed-in user is allowed to see. These labs show how Oracle
Deep Data Security keeps that decision in the database while LangChain,
Select AI Agent, and MCP application paths request data.

Each lab is self-contained. Some labs include their own ADB, OCI IAM, sample
schema, and wallet setup; others assume those resources already exist and
focus on the application integration. Learners can select one lab or follow
the suggested order to compare several integration patterns.

## Workshop Outline

1. Introduction
2. Lab 1 - Run a LangChain HR Agent with OCI IAM and Deep Data Security
3. Lab 2 - Run an OCI IAM-Protected Oracle SQL MCP Server
4. Lab 3 - Configure the Reusable Python Oracle SQL MCP Server
5. Lab 4 - Run a Select AI Agent Team with Deep Data Security
6. Lab 5 - Run LangChain HR and Compensation Agents with Microsoft Entra ID
7. Need Help?

## Workshop Prerequisites

- A non-production Oracle Autonomous AI Database 26ai environment, or the
  environment requirements listed by the selected lab.
- OCI IAM Identity Domain access for the OCI IAM labs and Microsoft Entra ID
  access for Lab 5.
- OCI Generative AI access and model quota for labs that call a model.
- OCI Cloud Shell or a Linux host with Bash, Python, SQL*Plus or SQLcl, and
  an extracted wallet when the selected lab requires them.
- Permission to create only the IAM, database, and demo resources required by
  the selected lab.

## Notes

- No lab is a mandatory prerequisite for another. Lab 3 can reuse resources
  from Lab 2, but it must still be configured with its own `.env` values.
- The setup scripts may create or drop database objects and cloud resources.
  Use a disposable or isolated environment and review each script before
  running it.
- Keep this file aligned with the final manifest and lab titles.

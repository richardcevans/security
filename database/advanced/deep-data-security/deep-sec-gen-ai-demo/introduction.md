# Deep Security GenAI Demo

## Introduction

This workshop extends the ADB OCI IAM lab with a direct OCI Generative AI
workflow for protected HR data. A local service validates the caller's OCI IAM
database access token, connects to ADB with that same token, and lets ADB apply
Deep Data Security grants before any result is sent to the LLM.

The model does not receive a database password, execute SQL, or bypass data
grants. It selects from reviewed, parameterized query tools. Unified Auditing
records both the end user and the client program that issued the database query.

### Prerequisites

- Complete the ADB OCI IAM lab and verify a current OCI IAM OAuth token works.
- Have OCI Generative AI access in the ADB compartment.
- Use SQL*Plus, OCI CLI, curl, and Python 3 on the lab host.

### Objectives

- Prove direct OCI Generative AI access.
- Audit protected HR access through SQL*Plus and the Python service.
- Verify OCI IAM caller identity reaches ADB through the service.
- Use an LLM to select bounded HR query tools without exposing arbitrary SQL.

Estimated Workshop Time: 60 minutes

You may now proceed to the next lab.

## Acknowledgements

* **Author** - Richard Evans
* **Last Updated By/Date** - Richard Evans, July 2026

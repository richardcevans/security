# Introduction

## About This Workshop

Oracle Deep Data Security can authorize database access with the authenticated end user identity. The application still connects with its database user. Oracle Database evaluates data roles and data grants for the propagated user. In this workshop, a Python LangChain HR assistant sends an OAuth access token to the database. You then verify which HR rows and columns each user can see.

Estimated Workshop Time: 75 minutes

Estimated Time: 75 minutes

### Objectives

In this workshop, you will:

- Review the LangChain demo source package.
- Choose the OCI IAM or Microsoft Entra ID path.
- Configure Python, OCI SDK access, Oracle Database connectivity, and OCI Generative AI.
- Configure Deep Data Security data roles and data grants for the HR sample data.
- Generate or acquire an end-user OAuth access token.
- Run the HR assistant as an employee and as a manager.
- Confirm that the same natural-language query returns different data based on the propagated end-user identity.

### Prerequisites

- Oracle Database with Deep Data Security enabled and a TCPS listener or wallet-based secure connection.
- SQL*Plus access as a privileged database user for setup.
- Python 3.10 through 3.12.
- OCI Generative AI access and an OCI SDK config profile.
- OCI IAM or Microsoft Entra ID applications and users for end-user identity propagation.

You may now proceed to the next lab.

## Acknowledgements

- **Author** - Richard Evans, Database Security
- **Source Contributor** - Tanisha Garg, Oracle
- **Last Updated By/Date** - Richard Evans, June 2026

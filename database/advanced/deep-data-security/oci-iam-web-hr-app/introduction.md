# OCI IAM Web HR App with Oracle Deep Data Security

## Introduction

This workshop extends the Autonomous Database OCI IAM environment with a lightweight browser-based HR application. Users authenticate through OCI IAM, and the application opens each database connection with the signed-in user's OAuth access token.

Oracle Database, not the web application, evaluates the existing OCI IAM data roles and HR data grants. The application never uses an ADMIN password or a shared database account.

### Prerequisites

- Complete the ADB OCI IAM lab, including the HR schema, OCI IAM groups, data roles, and data grants.
- Use a Compute VM or other app host that can receive HTTPS traffic on port 8012.
- Make the DeepSec environment file and Autonomous Database wallet available to the app host.

### Objectives

- Recognize the direct user-token database access pattern.
- Configure the public HTTPS OAuth callback.
- Deploy the app and validate database-enforced access.

Estimated Workshop Time: 45 minutes

You may now proceed to the next lab.

## Acknowledgements

* **Author** - Richard Evans
* **Last Updated By/Date** - Richard Evans, July 2026

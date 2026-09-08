# Workshop Details

## Short Description

Deploy a lightweight HR web application that authenticates users with OCI IAM and connects to Autonomous Database with each signed-in user's OAuth token.

## Long Description

This workshop extends an existing Autonomous Database OCI IAM and Oracle Deep Data Security environment with a browser-based HR application. Learners configure an exact HTTPS OAuth callback, launch the app, and sign in as an OCI IAM user.

The application does not hold an ADMIN password or use a shared database user. For every request, it opens a database connection with the signed-in user's access token. Oracle Database therefore applies the existing OCI IAM data roles and HR data grants to the SQL statement.

## Workshop Outline

1. Review the direct user-token architecture and prerequisites.
2. Prepare the app environment and public HTTPS callback.
3. Register the callback on the existing OCI IAM public client.
4. Run the application and verify database identity and HR access.

## Workshop Prerequisites

- Completed ADB OCI IAM lab, including the HR schema, OCI IAM user groups, data roles, and data grants.
- A Compute VM or other host with public HTTPS access to the app on port 8012.
- The DeepSec lab environment file and Autonomous Database wallet available to the app host.

## Notes

- This workshop documents the OCI IAM OAuth version of the app, not the older Entra application-identity sample in `web-hr-app.zip`.

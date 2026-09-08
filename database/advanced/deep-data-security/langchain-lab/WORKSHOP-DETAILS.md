# Workshop Details

## Title

DB Security - Deep Data Security LangChain HR Assistant

## Short Description

Build and run a Python LangChain HR assistant that propagates an OCI IAM or Microsoft Entra ID end-user token to Oracle Database and uses Oracle Deep Data Security data grants for row and column access control.

## Long Description

This workshop converts the `deepsec-demos-tanisha-langchain-poc-demo.zip` source package into a LiveLabs flow. Learners inspect the demo package, choose the OCI IAM or Microsoft Entra ID identity-provider path, configure Python and OCI Generative AI, set up database objects and Deep Data Security grants, and run a LangChain HR assistant as different users.

The key outcome is to prove that application-level identity propagation changes what the database returns. The LangChain tools issue read-only SQL against HR data, while Oracle Database enforces the final authorization decision through data roles and data grants mapped to the authenticated user's identity-provider groups or roles.

## Workshop Outline

1. Introduction: Review the architecture and prerequisites.
2. Lab 1: Prepare the LangChain Deep Data Security demo.
3. Task 1: Download and inspect the source package.
4. Task 2: Choose OCI IAM or Microsoft Entra ID.
5. Task 3: Configure Python, OCI SDK, and OCI Generative AI.
6. Task 4: Configure database objects and Deep Data Security.
7. Task 5: Generate or acquire end-user tokens.
8. Task 6: Run the LangChain HR assistant.
9. Task 7: Validate data-grant behavior.
10. Task 8: Clean up or reset the lab.

## Assumptions

- Target duration: 75 minutes.
- Lab count: one hands-on lab plus an introduction.
- Primary path: OCI IAM, because the source package includes token generation and identity-provider helper output for that path.
- Secondary path: Microsoft Entra ID, because the source package includes the application and setup files but requires more tenant-specific configuration.

## Prerequisites

- Oracle Database with Deep Data Security enabled.
- HR sample schema or equivalent HR tables referenced by the setup script.
- Secure Oracle Database connectivity through TCPS and wallet or equivalent SSL configuration.
- OCI Generative AI access.
- OCI SDK configuration with API key authentication.
- OCI IAM or Microsoft Entra ID application registrations, users, groups or roles, and scopes configured before the lab.

## Source Package

- `deepsec-demos-tanisha-langchain-poc-demo.zip`
- Extracted source directory: `deepsec-demos-tanisha-langchain-poc-demo/`

## SME Gaps

- Confirm the final public download URL or PAR URL for the demo zip before publishing.
- Confirm the exact Oracle Database version and Deep Data Security feature availability required for the lab environment.
- Review tenant-specific identity-provider setup steps for OCI IAM and Microsoft Entra ID before customer delivery.
- Runtime-test both application variants after replacing placeholder credentials, model IDs, wallet paths, token paths, and identity-provider values.

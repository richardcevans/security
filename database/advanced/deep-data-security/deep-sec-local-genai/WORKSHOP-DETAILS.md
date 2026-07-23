# Workshop Details

## Short Description

Build a Flask web application that connects directly as local Oracle Deep Data Security end users and uses OCI Generative AI only to summarize database-authorized results.

## Long Description

In this 60-minute workshop, you create a customer-data demonstration on Oracle Autonomous AI Database 26ai. Emma, Marvin, and Carol are local Oracle Deep Data Security end users, not OCI IAM users. Students sign in with each local database password. Flask opens a direct database session and executes the same SQL statement. Oracle Deep Data Security grants determine the returned rows and column values. The Flask application sends only those returned rows to OCI Generative AI for a bounded summary.

## Workshop Outline

1. Review the direct local-end-user architecture and prerequisites.
2. Provision Autonomous AI Database and download its wallet.
3. Create the customer schema, local end users, data roles, and data grants.
4. Upload the wallet, create the Flask virtual environment, and run the web application on the compute host.
5. Compare unrestricted app data, implement Deep Sec policies, then retest Emma, Marvin, and Carol results and GenAI summaries.

## Prerequisites

- A non-production OCI compartment that permits the BYOL, 2-ECPU, 1-TB Autonomous AI Database defaults.
- An Oracle Linux 9 compute instance with JupyterLab and Python 3.
- The supplied custom image must be visible in Ashburn. The Stack operator must be able to create its GenAI dynamic group and policy.
- Privileged ADB credentials for the setup scripts and a protected wallet location on the compute host.

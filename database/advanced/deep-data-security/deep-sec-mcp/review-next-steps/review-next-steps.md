# Lab 6: Review Architecture, Clean Up, and Next Steps

## Introduction

Review the secure AI access pattern and remove workshop resources that should not remain in the tenancy. Use this lab to connect the hands-on steps to customer architecture decisions.

Estimated Time: 10 minutes

### Objectives

In this lab, you will:

- Summarize the final architecture.
- Review production design considerations.
- Clean up workshop resources.

### Prerequisites

- Completed validation matrix from Lab 5.
- Access to the OCI resources and database objects created for the workshop.

## Task 1: Review the Architecture

1. Review how the AI application, MCP server, identity domain, Database Tools connection, and Autonomous Database fit together.

2. Identify where Deep Data Security enforces access decisions.

## Task 2: Clean Up Resources

1. Remove or disable the workshop MCP server and registered client if they were created only for this lab.

    TODO: Add final cleanup steps after the setup path is confirmed.

2. Remove temporary database objects, users, policies, and grants if required.

3. Remove temporary Object Storage artifacts if required.

## Task 3: Plan Next Steps

1. Identify which customer AI workflows use shared, broad, or weakly scoped database access.

2. Map those workflows to the secure pattern from this workshop.

    You may now proceed to the next lab.

## Acknowledgements

* **Author** - Richard Evans
* **Last Updated By/Date** - Richard Evans, July 2026

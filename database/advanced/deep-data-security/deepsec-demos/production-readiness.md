# Production Readiness Checklist

This workshop is a source-driven LiveLabs draft. The Markdown, source
templates, and static checks are in place, but no OCI tenancy or live Oracle
database execution has been completed in this iteration. Use this checklist
to move the demos from a reproducible technical draft to a supported learner
delivery.

Estimated Time: 5 minutes

## Current status

| Area | Status | Evidence or remaining work |
| --- | --- | --- |
| Five independent lab guides | Draft complete | Each guide has its own source path, prerequisites, tasks, verification, cleanup boundary, and Learn More links. |
| Clean-checkout runtime templates | Complete for this iteration | Sanitized `.env.example` files and ignore rules were added where the source README required them. |
| Static validation | Complete | LiveLabs structure, manifest, loader smoke test, local links, shell syntax, Python compilation, TOML parsing, and requirements-file syntax pass locally. |
| OCI/Oracle runtime validation | Open | Run every setup and application path in a disposable environment, including successful and denied user queries. |
| Remote VM validation | Deferred | Test the selected lab on `132.145.156.225` during the next authorized host session. No host changes were made today. |
| Publication package | Open | Decide Desktop-only versus other variants, archive/PAR delivery, screenshots, WMS metadata, and publication ownership. |

## Common production gates

### Runtime and release reproducibility

- Pin and review Python dependencies. Prefer a lock file or a tested
  constraints file for each Python version supported by the lab.
- Record the supported `python-oracledb` version, Oracle client mode, database
  release, SQL*Plus or SQLcl version, OCI CLI version, and operating-system
  image.
- For Oracle Linux 9, verify the matching RPMs for `python3` or `python3.12`,
  pip, `git-core`, `unzip`, `curl`, `wget`, `openssl`, `ca-certificates`,
  `libffi`, `gcc`, and `make`. SQL*Plus/SQLcl, OCI CLI, and `oratst` remain
  separately installed tools.
- Test from a clean checkout with no developer home-directory state except
  explicitly documented OCI configuration and wallet inputs.
- Add automated unit tests for SQL guards, identifier validation, token-claim
  checks, configuration validation, and cleanup safety before publication.
- Run `pip check`, dependency vulnerability scanning, shell linting, and a
  secret scan against both the source tree and every published archive.
- Make all setup scripts fail closed on missing prerequisites, wrong tenancy or
  compartment, unsupported database version, and incomplete wallet files.
- Record exact expected outputs for setup, authorization, and cleanup checks.

### Secrets and identity

- Keep OCI API keys, IAM client secrets, Entra secrets, database passwords,
  OAuth tokens, wallet files, private keys, and generated `.env` files outside
  Git and outside published ZIP files.
- Use an approved secret store or short-lived injected environment values for
  hosted deployments. Do not use the demo passwords as operational
  credentials.
- Rotate every client secret and credential used during testing before a
  public or learner release.
- Use separate compartments, identity domains, databases, applications,
  groups, and credentials for demonstrations and production services.
- Apply least-privilege policies. Confirm that the database connection client,
  browser-login client, MCP resource, GenAI credential, and Entra applications
  have only the scopes and operations they require.
- Use exact redirect URIs, exact audiences, exact scopes, and explicit role or
  group assignments. Test rejection for a missing, expired, wrong-audience,
  wrong-scope, and wrong-user token.

### Database and Deep Data Security

- Validate the complete authorization matrix with at least an employee,
  manager, unauthorized user, and application identity where applicable.
- Record row filtering and column masking expectations as test assertions;
  do not treat an LLM response alone as evidence of authorization.
- Confirm the end-user security provider is set immediately before each pooled
  connection acquisition and that pooled connections cannot retain the prior
  user's context.
- Review data roles, data grants, application identities, object grants,
  credential synonyms, and Select AI object grants with a database owner.
- Enable appropriate database auditing and retain enough end-user context to
  correlate a request, token subject, database session, tool call, and result.
- Keep sample HR data isolated and synthetic. Remove broad diagnostic grants
  before production use.
- Define a reset and cleanup procedure that cannot delete a shared database,
  wallet, IAM application, group, credential, or Select AI object by accident.

### Application, network, and operations

- Keep local demos bound to loopback. A hosted MCP deployment requires HTTPS,
  a public resource URL, a trusted reverse proxy, network allowlists, rate
  limits, request and connection timeouts, health checks, and a process
  manager or container policy.
- Publish protected-resource metadata and OAuth authorization-server metadata
  from the same externally visible URL that clients use. Verify issuer,
  audience, scope, expiry, and introspection behavior through the proxy.
- Never log bearer tokens, authorization headers, private keys, client
  secrets, wallet paths that reveal sensitive layout, or raw sensitive query
  results. Redact exceptions before learner collection.
- Set bounded result sizes and tool-call limits. Review every natural-language
  to SQL path for object allowlists, statement safety, prompt-injection
  resistance, and denial-of-service behavior.
- Define model, region, quota, availability, cost, and data-residency
  assumptions. Make GenAI failures clear without weakening database access
  controls.
- Add operational dashboards and alerts for authentication failures, database
  denials, unexpected result sizes, repeated introspection failures, tool
  errors, and cleanup failures.

## Lab-specific gates

### Lab 1: LangChain HR Agent with OCI IAM

- Run `00_setup_adb.sh` in a disposable compartment and verify its create,
  reuse, abort, and cleanup modes. Confirm generated resources are uniquely
  named and ownership is recorded.
- Verify OCI IAM groups, demo users, three application roles, database
  identity-provider settings, wallet configuration, and both Marvin/Emma
  paths. Include a negative authorization case.
- Replace generated demo passwords and credentials before any hosted release.
- Confirm the application uses the configured model and endpoint, not an
  environment-specific fallback, and that logs contain no tokens or sensitive
  HR results.
- Decide whether learners create resources or receive a prebuilt environment;
  the current setup is not suitable as an unattended production provisioner.

### Lab 2: OCI IAM-Protected Oracle SQL MCP Server

- Verify the local FastMCP server, OAuth introspection, protected-resource
  metadata, database end-user context, SQL guard, and companion GenAI client
  end to end.
- Keep the distinction from the managed OCI Database Tools MCP Server explicit.
  If the managed service is the intended production target, author a separate
  deployment path and test it against the official service configuration.
- For remote use, replace loopback HTTP with TLS at an approved proxy, set the
  public `MCP_RESOURCE_SERVER_URL`, validate callback routing, and rotate the
  introspection client.
- Add tests for malformed SQL, comments, multiple statements, oversized
  results, invalid tokens, and database-denied queries.

### Lab 3: Reusable Python Oracle SQL MCP Server

- Supply a supported reference environment because this lab intentionally does
  not create ADB, IAM, wallet, or Deep Data Security resources.
- Verify that its `.env` values are not copied from Lab 2 by accident and that
  the supplied audience, scope, issuer, introspection client, and wallet all
  belong to the same deployment.
- Package the application with a pinned build artifact and a process/runtime
  specification. Document how the companion GenAI client is optional and how
  an alternate MCP client obtains its token.
- Repeat the Lab 2 remote MCP controls before exposing this implementation
  outside loopback.

### Lab 4: Select AI Agent Team

- Run the destructive HR setup only against a disposable database or an
  explicitly approved reset target. Add a preflight refusal for a production
  database identifier.
- Test credential creation, credential sharing, profile owner, object list,
  SQL Tool, Agent, Task, Team, runner role, and token-attached `RUN_TEAM`
  access independently.
- Confirm `enforce_object_list` remains enabled and that the model cannot
  access objects outside the intended HR list. Test masked columns and denied
  rows from both employee and manager identities.
- Move GenAI private-key material to an approved secret or credential service;
  define credential rotation and ownership for the database credential.
- Record the supported Select AI Agent database release and package privileges;
  these are not interchangeable with the MCP application labs.

### Lab 5: LangChain HR and Compensation Agents with Microsoft Entra ID

- Verify all four Entra registrations, scopes, application roles, admin
  consent, redirect URIs, downstream permissions, and user/group assignments.
- Verify the Oracle `AZURE_AD` identity-provider configuration, mapped data
  roles, compensation application identity, and TCPS wallet/listener path on a
  supported database release.
- Test the HR user-role matrix and the compensation application-identity path
  separately. Include an unassigned user, expired secret, wrong scope, and
  incorrect application identity.
- Review `propose_update` and its confirmation flow with database auditing and
  an explicit change-approval policy before allowing mutation tests.
- Remove environment-specific `oratst`, proxy, listener, and init-file
  assumptions from the learner path or provide a supported prebuilt image.

## LiveLabs publication gates

Before publishing, complete all of the following:

1. Execute every guide from a clean learner image and record pass/fail results.
2. Verify every source link, local Markdown link, command path, filename,
   package name, environment variable, expected output, and cleanup command.
3. Add current redacted screenshots only where they materially help a learner;
   do not publish screenshots containing identifiers or secrets.
4. Build the approved workshop variant and source archive, test extraction,
   and scan the exact archive members for secrets and bearer artifacts.
5. Confirm the WMS title, tutorial order, publication dates, support alias,
   downloadable files, and owner/support process.
6. Run the final LiveLabs validator and preserve its report with the release
   evidence.

## Official references

- [Oracle Deep Data Security Guide](https://docs.oracle.com/en/database/oracle/oracle-database/26/ddscg/oracle-deep-data-security-guide.pdf)
- [Integrate Database Tools MCP Server with Oracle Deep Data Security](https://docs.oracle.com/en/database/oracle/oracle-database/26/ddscg/integrate-database-tools-mcp-server.html)
- [Oracle Database Tools MCP Server](https://docs.oracle.com/en-us/iaas/database-tools/doc/mcp-servers.html)
- [Getting Started with Select AI Agent](https://docs.oracle.com/en-us/iaas/autonomous-database-serverless/doc/getting-started-select-ai-agent.html)
- [Building Trusted Generative AI Experiences with Oracle Deep Data Security](https://blogs.oracle.com/database/building-trusted-genai-experiences-with-oracle-deep-data-security)

## Acknowledgements

* **Author** - Richard Evans
* **Last Updated By/Date** - September 2026

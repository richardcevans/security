# Assistance Needed

These items are intentionally non-blocking for the Markdown draft. They are
the decisions or evidence needed before the labs can be called publish-ready.

1. Confirm whether the final delivery should remain Desktop-only or also have
   `sandbox`, `tenancy`, or Free Tier variants.
2. Confirm the target workshop duration and whether all five labs should be
   listed in one workshop or exposed as separate workshop entries.
3. Provide or confirm the learner environment: prebuilt OCI resources versus
   learner-created resources, supported OCI regions, ADB release, Python
   versions, and whether OCI Cloud Shell is the standard host.
4. Confirm the canonical OCI IAM application, group, scope, redirect URI, and
   model conventions for the two OCI IAM MCP demos. Keep actual IDs, secrets,
   private keys, wallets, and tokens out of Git and out of learner Markdown.
5. Confirm the Microsoft Entra application-role and database identity-provider
   values for the multi-agent lab, including the intended redirect URIs and
   the `EMPLOYEE_ROLE`, `MANAGER_ROLE`, and compensation application identity
   names.
6. Runtime-test the five guides against disposable environments, including
   successful and denied/filtered user queries, Select AI Agent object
   creation, OAuth introspection, and the end-user security provider.
7. Supply approved download archives or PAR URLs if learners must download the
   source directories rather than receive them in a prebuilt Desktop image.
8. Supply current, readable, redacted screenshots and confirm which steps need
   visual evidence. No screenshots were invented in this iteration.
9. Confirm whether the Windows `Zone.Identifier` sidecar files in the new
   source directories should be removed or excluded from the final archive.
10. Confirm cleanup ownership for ADBs, IAM applications, users, groups,
    wallets, credentials, Select AI objects, and local test processes.
11. Resume the authorized-host test tomorrow. The initial read-only check found
    Oracle Linux 9, Python 3.9 and 3.12 installed, an active Oracle 26ai
    database process, and no `sqlplus` or OCI CLI on the login `PATH`; verify
    the correct Oracle home and package plan before changing the host.

12. Review [production-readiness.md](production-readiness.md) and assign an
    owner and target date for each open runtime, security, packaging, and
    publication gate. This is a release handoff list, not a blocker for the
    current authoring pass.

## Known Draft Boundaries

- The lab instructions are source-driven and statically reviewed. They have
  not yet been executed against a live Oracle database or OCI tenancy in this
  iteration.
- Environment-specific application IDs, scopes, model IDs, endpoints, and
  credentials remain placeholders by design.
- The existing source README files are linked as the detailed implementation
  references; the LiveLabs guides intentionally focus on learner actions and
  checkpoints.

Review this list with the lab owner before publishing.

Estimated Time: 5 minutes

## Acknowledgements

* **Author** - Richard Evans
* **Last Updated By/Date** - September 2026

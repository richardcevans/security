# LiveLabs Workshop Validation - deep-sec-mcp

Generated on 2026-07-13

Estimated Time: 5 minutes

### Objectives

Use this page to track validation results and remaining publishing checks for the workshop.

## Validation Summary

The workshop markdown validation passed for:

- `TRACEABILITY.md`
- `WORKSHOP-DETAILS.md`
- all six lab markdown files
- Terraform package README files

Command used:

```bash
./.github/scripts/validate-livelabs-markdown.sh database/advanced/deep-data-security/deep-sec-mcp
```

Result:

```text
Errors: 0
Validation PASSED
```

## Resource Manager Packages

The workshop includes Terraform ZIP packages for:

- Free Tier Autonomous Database sandbox
- Oracle corporate Autonomous Database sandbox
- Oracle corporate existing Base Database System sandbox

## Remaining Manual Checks

- Confirm all final product names and LiveLabs titles match the WMS request.
- Confirm the simple AI application setup commands after the runtime package is finalized.
- Confirm the MCP client and OAuth setup path for the selected tenancy model.
- Confirm final Deep Data Security SQL syntax and sample data before production publication.
- Verify the GitHub Pages rendered workshop after publishing.

## Acknowledgements

* **Author** - Richard Evans
* **Last Updated By/Date** - Richard Evans, July 2026

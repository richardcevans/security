# Legacy Database Tools MCP experiment

The existing Database Tools MCP scripts created a separate OCI Database Tools
MCP Server and connection. They are retained only to diagnose or clean up that
experiment; they are not the supported path for this lab going forward.

The current path is the native Autonomous AI Database MCP Server, enabled on
the existing ADB with `11_enable_adb_mcp_server.sh`. It is bound directly to
the ADB OCID and will expose only deliberately registered Select AI Agent
tools. OCI IAM Deep Data Security identity propagation is not asserted until a
working end-to-end test and audit evidence prove it.

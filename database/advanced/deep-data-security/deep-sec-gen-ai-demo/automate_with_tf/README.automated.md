# Deep Data Security GenAI Demo

This is a new lab scaffold. It will extend the direct OCI IAM and Deep Data
Security teaching flow without modifying `../adb-oci-iam`.

## Attach to the working OCI IAM baseline

This lab builds on a functional `../adb-oci-iam` environment. The existing ADB,
wallet, OCI IAM users/groups, OAuth apps, HR schema, and Deep Sec Data Roles
remain owned by that lab. This lab neither imports them into Terraform nor
reruns legacy setup.

```bash
./bin/labctl attach --env-file ../adb-oci-iam/.adb-oci-iam.env
./bin/labctl baseline \
  --expect-user richard.c.evans@gmail.com \
  --require-group EMPLOYEES
```

`baseline` is read-only. It verifies the inherited ADMIN configuration and the
current user's OAuth-token direct session before the GenAI phases proceed.

## OCI Generative AI readiness

Use the same OCI compartment selected for the attached ADB lab. This records
the attached `ROOT_COMP_ID` (resolved from `OCI_COMPARTMENT`) as
`COMPARTMENT_OCID` in a local, sourceable file.

```bash
./bin/labctl compartment create
source .lab/genai.env
```

For the first proof that OCI Generative AI works, run the standalone Chicago
smoke test. It uses a fixed harmless prompt and neither connects to ADB nor
sends HR data. It defaults to the on-demand `meta.llama-3.3-70b-instruct`
model; override `--model-id` if your tenancy has enabled a different model.

```bash
./bin/labctl genai smoke
```

It honors `OCI_PROFILE` (or `OCI_PROFILE_NAME` / `OCI_CLI_PROFILE`) and writes
the returned JSON response under `.lab/genai-smoke/`.

The more flexible template-based command below remains available for later
model-specific experiments.

## Minimal Select AI profile

After the standalone GenAI smoke test succeeds, configure the attached ADB
resource principal for exactly `generative-ai-chat` access, then create and
test one ADMIN-owned profile. The profile is fixed to Chicago and the validated
Meta Llama model. Its initial test is a harmless chat request; it does not
query HR data.

```bash
./bin/labctl select-ai access
./bin/labctl select-ai configure
```

The access command creates or reuses only `deep-sec-gen-ai-adb-rp` and
`deep-sec-gen-ai-adb-chat`. OCI documents that ADB resource-principal tokens
can remain cached for up to two hours after IAM policy or dynamic-group changes;
if the immediate database chat test is denied, do not broaden the policy or
add API-key credentials—retry after that cache interval.

Validate the HR profile next. The default action returns generated SQL only;
it does not run the query. Inspect that output before choosing the explicit
`--run` option, which runs as ADMIN and therefore does not validate an OCI IAM
end-user's Deep Data Security authorization.

```bash
./bin/labctl select-ai verify
./bin/labctl select-ai verify --run
```

AI profiles are schema-owned, so do not assume an OCI IAM session can consume
the ADMIN-owned profile. The current-user check below establishes that behavior
before any per-user profile or privilege design is added.

Before expanding that model, test the existing profile directly through the
current OCI IAM OAuth token. This makes no changes. The default produces SQL
only; `--run` executes the generated query under that token's existing database
data roles.

```bash
./bin/labctl select-ai current-user
./bin/labctl select-ai current-user --run
```

After `baseline` passes, generate request templates from the locally installed
OCI CLI. This avoids hard-coding a model-specific request format in the lab.

```bash
./bin/labctl genai readiness \
  --region <genai-region> \
  --compartment-id <compartment-ocid> \
  --generate-inputs
```

Edit copies of the generated files with an approved on-demand model and a
harmless prompt. Then run the explicit smoke test; it does not query the
database and may incur inference charges.

## Current scope

The first GenAI step is attachment and verification of the inherited OCI IAM
baseline. No GenAI resource, model, MCP server, application, or new ADB is
created by this step.

```bash
./bin/labctl preflight
./bin/labctl status
./bin/labctl test
./bin/labctl --dry-run database configure
./bin/labctl --dry-run all
```

The direct-login source lab is still available unchanged in `../adb-oci-iam`.
Use the compatibility wrapper only when you explicitly intend to run one of its
existing commands:

```bash
./bin/labctl legacy verify-marvin
```

## Generated state

Future scripts will keep generated data in `.lab/`, which is ignored by Git.
The current status command is read-only and does not create this directory.

`./bin/labctl manifest init` creates the empty ownership manifest. Future
resource-creating scripts must record only resources they created there.

## Compatibility wrappers

`database configure`, `verify`, and `destroy` delegate to `../adb-oci-iam`.
They preserve the legacy commands and do not replace their implementation.
Use `--dry-run` to show a proposed delegate call without running it. Cleanup
requires an explicit scope, such as `--delete-db-objects`; `--yes` maps to the
legacy script's noninteractive confirmation flag.

`identity configure` also delegates to legacy setup. That legacy command
creates or reuses the ADB and downloads its wallet as well as configuring
Identity Domain resources. The coupling is explicit until later phases split
and test those responsibilities. `all` runs setup, database configuration, and
ADMIN-side verification; it intentionally stops before the interactive Marvin
and Emma OAuth token exercises.

## Terraform baseline

The `terraform/` directory now defines an explicit ADB-S ownership choice:
Terraform can create a new database, or accept an existing database OCID
without managing its lifecycle. Read [terraform/README.md](terraform/README.md)
before running any Terraform command.

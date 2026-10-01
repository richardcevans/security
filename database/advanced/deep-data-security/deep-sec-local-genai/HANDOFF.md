# Deep Sec Local GenAI maintainer handover

Prepared on **October 1, 2026**, for the colleague taking over on **October 2**.
Start here if you are new to this workshop, VS Code, or Codex.

| Item | Location or value |
| --- | --- |
| Workshop title | **Can Application Code or GenAI Bypass Oracle Deep Data Security?** |
| WMS workshop record | **WMS 12146** at [LiveLabs Workshop Management System](https://livelabs.oracle.com/wms) |
| Staging preview | [LiveLabs staging workshop 836](https://livelabs-stg.oracle.com/ords/r/dbpm/livelabs/view-workshop?wid=836) — **connect to the VPN first** |
| Repository | [richardcevans/security](https://github.com/richardcevans/security) |
| Lab directory | `database/advanced/deep-data-security/deep-sec-local-genai` |
| Editing rules | [AGENTS.md](AGENTS.md) |
| Lesson authoring reference | [authoring.md](greenbutton-files/admin-app/content/deep_data_security/authoring.md) |
| Compute image requirements | [IMAGE-CONTRACT.md](IMAGE-CONTRACT.md) |

WMS **12146** and staging **836** identify different environments; do not substitute
one ID for the other. These associations were supplied by the workshop owner.
The signed-in WMS configuration and VPN-only staging preview were not verified
while preparing this handover.

## Start here tomorrow

1. Confirm access to the repository, VS Code, an approved Codex account, the VPN,
   WMS 12146, and the OCI tenancy/compartment used for test reservations.
2. Use the published handover commit on `richardcevans/security` or the
   `codex/wms-12146-handover` branch. Confirm the commit in the release record;
   the original working checkout contains unrelated and older local changes.
3. Follow the VS Code setup below, read `AGENTS.md`, and run the local checks.
4. Read the edit map, then make one small wording change to understand the flow.
5. Confirm which Terraform package and application download WMS actually uses
   before preparing a release. The two package paths below behave differently.
6. Test the published result in a new staging reservation, including Marvin,
   Emma, workflow completion, DeeBee, Iceberg, and AI Insights.

Most lesson changes are ordinary text edits in YAML or Markdown. SQL is kept in
separate files. Python is needed when changing application behavior, rather than
for every explanation, button label, quiz, or lesson step.

### Transfer status on October 1

The handover source release includes fixes for premature or missing blue
completion states, DeeBee scrolling and dismissal, and a spelling, grammar, and
clarity pass across the app and learner Markdown. Local validation passed: **24 Admin Console
unit tests, 14 Customer Sales App unit tests**, the content validator, and browser
checks for all **41 steps across 10 pages** and the guided tour.

These are source checks with external services mocked where appropriate. They do
not certify the current WMS deployment or a live database/GenAI connection. The
source release and production documentation PR are separate from runtime
publication. Rebuild the relevant packages, publish the application artifact,
and verify a new staging reservation before marking the runtime release ready.
The handover includes `greenbutton-files/admin-app/tests/browser_workflow.py`.

The original outgoing checkout has unrelated changes and an older local `main`.
This release was prepared in a clean worktree from the current `origin/main`,
preserving newer fixes already on GitHub. Start from the published branch rather
than copying the older checkout over it. Transfer work through Git rather than
relying on the previous Codex conversation or temporary files.

## Set up VS Code

### Workstation and repository

Install Git, VS Code, and Python with `venv` support. Use a Bash terminal for the
commands in this guide. On Windows, use VS Code with the **WSL extension** and
keep the clone in the WSL Linux filesystem. On macOS or Linux, use a native
terminal. See Microsoft's [VS Code with WSL guide](https://code.visualstudio.com/docs/remote/wsl).

For a new clone, start with:

```bash
mkdir -p ~/src
cd ~/src
git clone https://github.com/richardcevans/security.git
cd security
git status --short --branch
```

Check out the handover branch supplied by the outgoing maintainer, then create
your own working branch. The command below creates a branch from whichever
commit you have checked out; confirm that commit first with `git log -1`.

```bash
git log -1 --oneline
git switch -c workshop-12146-maintenance
cd database/advanced/deep-data-security/deep-sec-local-genai
code .
```

Opening the lab directory keeps VS Code and Codex focused on this workshop.
For an existing checkout, inspect `git status` first and preserve uncommitted work.
All commands below start in this **lab directory** unless stated otherwise.

### Python environment

Create a separate local environment outside the repository, then install both
applications' requirements:

```bash
python3 -m venv ~/.venvs/deep-sec-maintainer
source ~/.venvs/deep-sec-maintainer/bin/activate
python -m pip install --upgrade pip
python -m pip install -r greenbutton-files/admin-app/requirements.txt \
  -r greenbutton-files/flask-app/requirements.txt
```

In VS Code, install Microsoft's Python extension. Run **Python: Select
Interpreter** from the Command Palette and select the environment you just
created. Activate it again in new terminals before running the checks.

Python 3.12 was used for the October 1 local checks. Deployed code must remain
compatible with the image's **Python 3.9** runtime and offline dependencies.
Changing a dependency can also require an image/wheelhouse update; installing
it on your laptop does not add it to the VM. See
[the offline runtime notes](greenbutton-files/offline/README.md).

There is no frontend build step: the apps use Flask, Jinja templates, JavaScript,
and CSS. Node.js is useful for JavaScript syntax checks. Terraform and the OCI
CLI are needed for relevant infrastructure/release tasks, not to edit lesson
wording. Archive builders also require Bash, `zip`, `unzip`, and `sha256sum`;
WSL/Linux is the straightforward environment for those existing scripts.

### Preview and local execution

Use **Markdown: Open Preview to the Side** for the learner Markdown. Keep
`lab.yaml` and the lesson authoring reference open together when editing the app.
YAML indentation uses spaces; preserve IDs and references when changing wording.

The tests below do not need a live database, OCI credentials, or GenAI calls.
They are the quickest way to check a local edit. The browser regression script
renders the real Flask pages against mocked services.

Running the full app interactively needs more than `pip install`: a reachable
ADB connection, the runtime configuration, SQL*Plus for Admin Console actions,
and OCI instance-principal access for GenAI. Use the provisioned test VM for
end-to-end work. The Customer Sales App currently constructs an instance-principal
signer; creating a local OCI CLI profile does not switch the app to user API keys.
Do not copy a production VM's environment files into the repository.

## Use Codex in VS Code

Install the official **Codex** extension, open the Codex sidebar, and sign in
with the account approved for your work. If the icon is not visible, use
**Codex: Open Codex Sidebar** in the Command Palette. Follow the current
[official IDE setup guide](https://learn.chatgpt.com/docs/codex/ide).

Codex is the development assistant you use to maintain the repository. The lab's
**AI Insights** feature calls **OCI Generative AI** from the VM; it uses separate
identity, configuration, and service limits.

Codex reads applicable `AGENTS.md` instructions from the project hierarchy.
Ask it to read `HANDOFF.md` explicitly; a Markdown filename alone does not make
it automatic context. A colleague's fresh session will not inherit the outgoing
maintainer's conversation, memory, credentials, or personal skills. See
[OpenAI's AGENTS.md guidance](https://learn.chatgpt.com/docs/agent-configuration/agents-md).

Start a new session with:

```text
Read AGENTS.md and HANDOFF.md in this lab. Inspect git status before changing
anything. Explain the Admin Console, Customer Sales App, and release paths from
the current source. Identify any handover items that are still unpublished.
Keep work within this lab and preserve unrelated changes.
```

For a normal lesson edit, give a specific page and desired result:

```text
On the Deep Sec Setup page, clarify the Grant Data Role explanation for a first-time
learner. Read the action and its SQL before editing. Keep identifiers, behavior,
and quiz answer keys unchanged. Update the lesson wording, run the content
validator and relevant tests, and show the diff. Do not publish or deploy.
```

For a bug, describe the expected behavior and how to reproduce it:

```text
Review the deep-sec-basics workflow. A step should turn blue only after its action
and any quiz are complete in the current session. Check the completion logic,
existing regression tests, and browser behavior. Fix a reproduced problem, run
relevant checks, and explain the change. Do not call live GenAI for this test.
```

Use VS Code's Source Control diff to review each change. Ask Codex to explain
unfamiliar lines and to verify claims against the active source and official
Oracle documentation. Give explicit scope when authorizing a Git push, object
upload, or deployment: name the branch, artifact, and target. The repository's
`AGENTS.md` permits local work but requires authorization for those external
changes.

The terminal alternative is the [Codex CLI](https://learn.chatgpt.com/docs/codex/cli).
After following its installation instructions, run `codex` from the lab directory.
The same source files and review process apply.

## How the app works

| Component | Purpose | VM location and port |
| --- | --- | --- |
| Admin Console, branded **Deep Sec Demo Setup** | Guides the lesson and runs the selected setup, grant, review, or reset action using the administrator connection. | `/opt/deep-sec-admin-console`, port `7778` |
| Customer Sales App | Signs in as Marvin or Emma and queries Oracle with that end user's database credentials. | `/opt/deep-sec-customer-sales`, port `7777` |
| Autonomous AI Database | Stores the sample data and enforces Deep Data Security data roles, grants, and context. | Connection details supplied during provisioning |
| OCI Object Storage | Holds the Iceberg order-history sample read through an Oracle external table. | Reservation/stack bucket |
| OCI Generative AI | Produces AI Insights from authorized data and, in the red-team exercise, bounded query results. | Assigned GenAI region and compartment |
| JupyterLab | Provides notebooks and VM terminals for the learner. | Port `8888` |

The usual sequence is DB Setup → Deep Sec Setup → Customer Sales App → Customize
Data Grant → End User Context → Iceberg → Exercises → Best Practices → Summary.
The Admin page provides validation, source downloads, restore, and reset actions.

The Admin Console loads `lab.yaml` at process startup. Its content engine builds
the pages, steps, actions, quizzes, and tour from that file. SQL actions execute
checked-in SQL files through SQL*Plus. Interactive grant controls use a Python
handler with allow-listed inputs. The browser does not supply arbitrary setup SQL.

The Customer Sales App opens a direct database session as **MARVIN** or **EMMA**.
Oracle determines which rows and columns the query returns. The app does not
fetch every customer's data as ADMIN and then hide unauthorized rows in JavaScript.
Use a regular browser window for Marvin and a separate Incognito/InPrivate/private
window for Emma so the browser sessions remain independent.

An ordinary AI Insights request fetches the current user's authorized customer
rows, then makes one logical chat call. It does not call GenAI once per row. The
red-team exercise can make a second chat call after up to three bounded,
read-only SQL tool queries, each executed as the signed-in database user. Retry
logic can increase HTTP request counts: the application allows up to two attempts
for a throttled chat operation, and SDK retry behavior can add requests. Avoid
repeated clicks or automatic live-model tests when investigating a quota issue.

GenAI authenticates as the **VM instance principal**, not as Marvin or Emma.
Database end-user authorization and OCI service authorization are separate.
The OCI Auth Token used for `DBMS_CLOUD` Iceberg access is not the credential used
by this SDK chat call. See Oracle's
[GenAI IAM policies](https://docs.oracle.com/en-us/iaas/Content/generative-ai/iam-policies.htm)
and [data-grant documentation](https://docs.oracle.com/en/database/oracle/oracle-database/26/ddscg/create-data-grants.html).

Optional Vibe routes are also present in the Customer Sales App source. They are
outside the normal ten-page lesson navigation and can execute authorized
`INSERT`, `UPDATE`, and `DELETE` statements as well as queries. Treat those as
an advanced feature; they are not a read-only preview or an MCP server.

### Progress and DeeBee behavior

- **Gray:** pending. **Red:** selected but unfinished. **Blue:** completed.
- A step needs its action and, where present, the correct quiz answer. Observation
  steps use **Mark as viewed**. A page check mark requires all its steps.
- Existing database objects do not automatically complete a new learner's steps.
  Progress belongs to the current Admin Console session. A new sign-in starts a
  fresh progress record; reset/restore also clears affected progress.
- DeeBee's guided tour should remain in view while scrolling. Clicking outside,
  pressing Escape, or selecting Skip or Done should remove the tour and dimming
  layer. Keep the tour selectors aligned with page navigation links.

Both Flask apps hold login state in process memory. The deployed services use
one Gunicorn worker with threads. Restarting a service loses its in-memory
sessions; it does not undo database grants or recreate the database. Do not
increase the worker count without redesigning shared session/progress storage.

## Where to make changes

Paths in this table are relative to the lab directory.

| Change | File or directory | What to check |
| --- | --- | --- |
| Learner introduction, prerequisites, main lab instructions | `introduction.md`, `get-started.md`, `deep-sec-local-genai.md` | Markdown preview, links, wording, and staging rendering |
| Workshop images | `images/` | Correct relative links and maximum width of 1280 pixels |
| App wording, navigation, steps, quizzes, tour, button labels | `greenbutton-files/admin-app/content/deep_data_security/lab.yaml` | Content validator and affected workflow; restart Admin Console after installing changes |
| Lesson SQL | `greenbutton-files/admin-app/content/deep_data_security/database/` | Executable SQL and matching `.display.sql`; validate the result on a test database |
| Grant wizard behavior | `greenbutton-files/admin-app/handlers/data_grant.py` and its YAML configuration | Generated SQL, input allow-list, and handler tests |
| Admin Console routes and progress | `greenbutton-files/admin-app/admin_app.py`, `content_runtime.py` | Session/action behavior and workflow regression tests |
| Admin Console layout and DeeBee | `greenbutton-files/admin-app/templates/`, `static/admin.js`, `static/admin.css` | Browser checks, scrolling, small screens, and dismissal |
| Customer screen, prompts, and diagnostics | `greenbutton-files/flask-app/templates/`, `static/app.js`, `static/app.css`, `ai_diagnostics.py` | Both personas, displayed errors, and browser behavior |
| Customer SQL or GenAI calls | `greenbutton-files/flask-app/db.py`, `app.py`, `ai.py`, `config.py` | End-user identity, authorized data, retry behavior, and region settings |
| Installation and database preparation | `greenbutton-files/setup/` | Bootstrap dependencies, existing-data impact, and test-reservation startup |
| LiveLabs infrastructure | `terraform-william-livelab/` and `build_william_livelab_*.sh` | WMS input mapping, assigned GenAI region, formatting, reviewed plan, and image compatibility |
| GreenButton infrastructure | `terraform-greenbutton/` | Formatting, validation, reviewed plan, and custom image compatibility |

For a text change, edit the existing YAML value and preserve its key. For a new
step, define the action, reference it from the step, add the step to its page,
and set prerequisites where needed. Update the tour when adding or moving a
page. See the [lesson authoring guide](greenbutton-files/admin-app/content/deep_data_security/authoring.md)
for the content contract.

A matching `.display.sql` file is what learners see; the ordinary `.sql` file is
what runs. Review both when changing SQL so the explanation matches execution.
Changing an observation into an executable action also needs a deliberate review
of permissions and completion behavior.

The workshop wrapper manifest is at
[`../../workshops/desktop-deep-sec-local-genai/manifest.json`](../../workshops/desktop-deep-sec-local-genai/manifest.json).
It references the three learner Markdown files above and a shared help page.
`jupyter-orientation.md` exists but is not currently listed in that manifest.
The wrapper's `workshoptitle` matches the title at the top of this handover.
Confirm that WMS 12146 uses this manifest. The wrapper is outside this lab's
default edit scope, so include it explicitly when assigning future metadata edits.

## Local checks

With the Python environment activated, run from the lab directory:

```bash
(
  cd greenbutton-files/admin-app
  python validate_content.py
  python -m unittest discover -s tests -q
)
(
  cd greenbutton-files/flask-app
  python -m unittest discover -s tests -q
)
git diff --check
```

The content validator checks IDs, references, dependencies, handlers, and SQL
files. The October 1 content inventory is **10 pages, 41 steps, 42 actions, and
33 SQL scripts**; use the validator's actual output after structural edits.

For completion, tour, or layout changes, install the optional browser-test tools
in the same local environment and run:

```bash
python -m pip install playwright
python -m playwright install chromium
(
  cd greenbutton-files/admin-app
  PYTHONPATH=. python -u tests/browser_workflow.py
)
```

The browser script mocks OCI, SQL*Plus, and database calls. It covers action/quiz
completion, failed actions, reloads, navigation, reset/restore, and DeeBee on
desktop and small screens. It does not prove that live SQL or GenAI works.

For JavaScript changes, run `node --check` on the changed `.js` files. For
Terraform or shell changes, also run:

```bash
terraform fmt -check -recursive terraform-greenbutton
find . -type f -name '*.sh' -not -path './archive/*' -print0 \
  | while IFS= read -r -d '' script; do
      bash -n "$script" || exit 1
    done
```

Run `terraform validate` in `terraform-greenbutton/` when its providers are
initialized. These formatting/syntax checks do not apply a stack. Review spelling,
grammar, links, and expected results manually as well; a syntax check cannot tell
whether an explanation is clear or technically correct.

## How changes reach WMS and a reservation

### Confirm the release path first

Application source is under `greenbutton-files/`. The tracked deployment paths
are `terraform-greenbutton/` for GreenButton and `terraform-william-livelab/`
for the LiveLabs wrapper. **Do not assume that rebuilding GreenButton replaces
the WMS wrapper.**

| Package path | Application delivery | Handover detail |
| --- | --- | --- |
| GreenButton | `deep-sec-local-genai-terraform-GreenButton.zip` embeds `dist/deep-data-security-flask-app-GreenButton.zip`. Resource Manager working directory: `terraform`. | Rebuild the app before the Terraform ZIP. |
| LiveLabs wrapper | `deep-sec-local-genai-terraform-WilliamLiveLab.zip` downloads the app through `application_bundle_par_url`; it does not embed the app. ZIP configuration directory: `deep-data-security`. | The previously used Object Storage object is `dbsec_public/deep-data-security-flask-app.zip`. Confirm the configured URL/object in WMS before replacing it. |

The current GitHub source includes the complete `terraform-william-livelab/`
configuration and both `build_william_livelab_app_zip.sh` and
`build_william_livelab_terraform_zip.sh`. These were absent from the older local
checkout and were confirmed after fetching the repository for this release.
Use the tracked source and builders; record the artifact version configured in
WMS 12146. Keep secret-bearing inputs and PAR URLs out of Git.

The archived wallet, NO-IAM, FREE, and other deployment families are historical
unless a task explicitly names one. The root README also describes Marketplace;
that is not evidence that WMS 12146 uses the Marketplace package.

### Choose the smallest release that contains the change

- **Workshop Markdown or images:** commit/publish the documentation to the source
  branch configured for WMS, then use the WMS publishing/refresh process and check
  staging. No application or Terraform ZIP rebuild is needed for those files.
- **App YAML, SQL, templates, Python, JavaScript, or CSS:** rebuild the app ZIP.
  For the LiveLabs wrapper, publish it to the exact configured application object.
  For GreenButton, also rebuild the Terraform ZIP because it embeds the app.
- **Infrastructure or bootstrap:** rebuild the correct Terraform package, review
  a successful plan for the intended test stack, and apply that exact plan.

A new Git commit does not update Object Storage. Replacing an Object Storage ZIP
does not update an already running VM. Reapplying Terraform to an unchanged VM
does not guarantee that cloud-init runs again. Use a **new reservation** to test
first-boot deployment, or an explicitly scoped application refresh for an existing
VM. Preserve its database, environment files, and `.venv` during an app-only
refresh; do not run database reset/bootstrap scripts as an update shortcut.

After installing app changes, restart the affected service so Python and lesson
YAML reload. Refresh the browser for static assets. Expect users to sign in again.
Use the WMS controls and source mappings visible to your signed-in account;
this handover does not assume a particular unpublished WMS configuration.

### Build and verify LiveLabs packages

For an application update using the LiveLabs wrapper:

```bash
bash build_william_livelab_app_zip.sh
unzip -tq dist/deep-data-security-flask-app-WilliamLiveLab.zip
sha256sum dist/deep-data-security-flask-app-WilliamLiveLab.zip
```

The output is `dist/deep-data-security-flask-app-WilliamLiveLab.zip`. Publish that
verified payload under the application object name configured in WMS, currently
expected to be `deep-data-security-flask-app.zip`; verify the actual mapping first.
For a wrapper/infrastructure change, also run:

```bash
bash build_william_livelab_terraform_zip.sh
unzip -tq deep-sec-local-genai-terraform-WilliamLiveLab.zip
```

That Terraform archive contains `deep-data-security/` and downloads the app at
bootstrap. Rebuilding it is unnecessary for an app-only update to the same
configured download URL. Inspect both source and archive contents before release.

### Build and verify GreenButton packages

Run from the lab directory when a release artifact is needed:

```bash
bash build_greenbutton_app_zip.sh
bash build_greenbutton_terraform_zip.sh
unzip -tq dist/deep-data-security-flask-app-GreenButton.zip
unzip -tq deep-sec-local-genai-terraform-GreenButton.zip
python - <<'PY'
from hashlib import sha256
from pathlib import Path
from zipfile import ZipFile

app = Path('dist/deep-data-security-flask-app-GreenButton.zip').read_bytes()
with ZipFile('deep-sec-local-genai-terraform-GreenButton.zip') as package:
    embedded = package.read('terraform/artifacts/deep-data-security-flask-app-GreenButton.zip')
assert app == embedded, 'Terraform ZIP contains a different application ZIP'
print('Matching application SHA-256:', sha256(app).hexdigest())
PY
```

Inspect the builders' changes under `dist/` and `terraform-greenbutton/artifacts/`
before staging. Compare changed source files with their packaged counterparts;
a valid ZIP and matching embedded hash establish packaging consistency, not that
all intended source edits were included. Exclude environment files, credentials,
private keys, wallets, Terraform state, and generated logs from commits/archives.

For the LiveLabs download path, upload the verified app archive under the
**configured object name**, which can differ from the local GreenButton filename.
Verify the uploaded object's checksum against the local artifact. Share access
credentials and full PAR URLs through the approved private channel, not this file.

Oracle documents ZIP-based Resource Manager stacks and working directories in
[Create a stack from a local configuration](https://docs.oracle.com/en-us/iaas/Content/ResourceManager/Tasks/create-stack-local.htm).

## Runtime configuration and troubleshooting

| Setting or file | Purpose |
| --- | --- |
| `/etc/deep-sec/admin-console.env` | Admin Console runtime settings; includes sensitive values |
| `/etc/deep-sec/customer-sales.env` | Customer Sales App runtime settings; includes sensitive values |
| `/home/opc/.deep-sec-genai-defaults` | Provisioned GenAI region, model, and compartment defaults |
| `ADMIN_DB_DSN`, `DB_DSN` | Database connection settings for Admin Console and Customer Sales App |
| `ADMIN_FLASK_SECRET_KEY`, `FLASK_SECRET_KEY` | Separate Flask session-signing secrets |
| `GENAI_REGION` | Region assigned for OCI Generative AI |
| `OCI_REGION` | General OCI resource region and legacy GenAI fallback |
| `GENAI_COMPARTMENT_OCID`, `GENAI_MODEL_ID` | Target GenAI compartment and model |
| `ORDER_HISTORY_BUCKET`, `ORDER_HISTORY_NAMESPACE`, `ORDER_HISTORY_READ_PAR_URL` | Admin Console's Iceberg file inspection configuration; keep the PAR private |

**Region lesson from the September incident:** LiveLabs can assign GenAI to a
different region from the Compute VM and database. Its wrapper input
`ociGenAiRegion` must reach `GENAI_REGION`; `ociRegionIdentifier` identifies the
ordinary resource region. The inspected LiveLabs wrapper makes that distinction.
The current GreenButton defaults template still supplies `OCI_REGION` from its
single resource-region input, so verify/provide a dedicated `GENAI_REGION` if
using that path with a different assigned GenAI region.

Both apps resolve the GenAI region in this order: environment `GENAI_REGION`,
defaults-file `GENAI_REGION`, environment `OCI_REGION`, then defaults-file
`OCI_REGION`. Check the effective endpoint and compartment before changing
models, credentials, quota policies, or retry settings. A 429 can report a
compartment's chat request limit; its presence alone does not identify the cause.

### Run diagnostics from JupyterLab Terminal

Open JupyterLab from the reservation's application links. **Two Terminal tabs are
already open by default; use either one.** If they have been closed, open a new
Terminal from the JupyterLab Launcher. These are shell commands for a
**JupyterLab Terminal**, not a Python notebook cell or your workstation terminal:

```bash
sudo systemctl status deep-sec-admin-console deep-sec-customer-sales --no-pager -l
sudo journalctl -u deep-sec-admin-console --since '15 minutes ago' --no-pager
sudo journalctl -u deep-sec-customer-sales --since '15 minutes ago' --no-pager
curl --fail --silent --show-error http://127.0.0.1:7778/healthz
curl --fail --silent --show-error http://127.0.0.1:7777/healthz
```

For a failed initial deployment:

```bash
sudo cat /var/lib/deep-sec/bootstrap-status
sudo tail -n 200 /var/log/deep-sec-bootstrap.log
```

Bootstrap status should reach `COMPLETE`. A healthy HTTP endpoint is a useful
starting check, but also sign in and run a database action to verify connectivity.

AI Insights displays a controlled error panel with diagnostic fields and a
reference that can be matched to the service log. Capture the time, reference,
region, model, and OCI request ID for support. Review logs before sharing them;
they can contain identifiers or request details. Enable detailed SDK request and
response logging only when needed, following
[Oracle's Python SDK logging documentation](https://docs.oracle.com/en-us/iaas/tools/python/latest/logging.html).
Keep raw exceptions and credentials out of learner-facing error panels.

## Finish the release and handover

Before calling a release ready, use a new test reservation to confirm:

1. The intended Terraform package, custom image, compartment, resource region,
   GenAI region, and application artifact were used; bootstrap reaches `COMPLETE`.
2. Admin Console, Customer Sales App, and JupyterLab open through the reservation
   links, and both Flask services are healthy.
3. A fresh Admin Console sign-in starts with the correct pending step colors.
   Actions, quizzes, page check marks, and DeeBee behave as described above.
4. Marvin and Emma can sign in through separate browser sessions. The baseline,
   employee, and manager grants produce the expected different results.
5. The Iceberg external table reads its Object Storage files and the cross-table
   grant limits the order-history rows correctly.
6. One ordinary AI Insights request succeeds in the assigned GenAI region; the
   red-team exercise remains subject to the signed-in user's database authority.
7. The staging Markdown, links, images, workshop title, and app instructions agree.
   Exercise restore/reset only in the disposable test reservation.

Record the following in the team's private release record before sign-off:

| Record | Required handover value |
| --- | --- |
| Source | Reviewed branch, commit SHA, and PR/push location containing the final edits |
| WMS mapping | WMS 12146's configured documentation source and Terraform artifact version |
| Application | Object name/version and verified SHA-256; private location of the configured download URL |
| Wrapper ownership | `terraform-william-livelab/`, its two build scripts, and the responsible maintainer |
| Runtime | Custom image version/owner, test stack or reservation ID, resource region, GenAI region, and compartment |
| Access | Owners of GitHub, WMS, OCI publication, and the image; private credential handover location |
| Verification | Test date, tester, staging result, and any remaining limitations |

For broader background, Oracle's
[database-enforced end-user authorization article](https://blogs.oracle.com/developers/develop-database-enforced-end-user-auth-with-oracle-ai-database-deep-data-security-and-java)
explains enterprise identity integration. Its Java/IAM example is background;
this lab's Customer Sales App uses direct local database-user sessions.

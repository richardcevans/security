const userBox = document.querySelector("#userBox");
const employeeRows = document.querySelector("#employeeRows");
const summary = document.querySelector("#summary");
const raw = document.querySelector("#raw");
const employeesButton = document.querySelector("#employeesButton");
const summaryButton = document.querySelector("#summaryButton");
const modeBanner = document.querySelector("#modeBanner");
const disableSalaryButton = document.querySelector("#disableSalaryButton");
const enableSalaryButton = document.querySelector("#enableSalaryButton");
const auditButton = document.querySelector("#auditButton");
const auditRows = document.querySelector("#auditRows");

employeesButton.addEventListener("click", loadEmployees);
summaryButton.addEventListener("click", loadSummary);
disableSalaryButton.addEventListener("click", disableSalaryEdits);
enableSalaryButton.addEventListener("click", enableSalaryEdits);
disableSalaryButton.addEventListener("focus", () => showPolicyToggleDemo(false));
disableSalaryButton.addEventListener("mouseenter", () => showPolicyToggleDemo(false));
enableSalaryButton.addEventListener("focus", () => showPolicyToggleDemo(true));
enableSalaryButton.addEventListener("mouseenter", () => showPolicyToggleDemo(true));
auditButton.addEventListener("click", () => loadAuditEvents());

async function refreshConfig() {
  const response = await fetch("/config");
  const config = await response.json();
  const mode = config.db_mode || "mock";
  modeBanner.className = `mode-banner ${mode === "oracledb" ? "real" : "mock"}`;
  modeBanner.innerHTML = mode === "oracledb"
    ? "<strong>Oracle mode:</strong> requests use the database connection pool and Deep Data Security context."
    : "<strong>Mock mode:</strong> this page is only simulating results. Run with <code>WEB_HR_DB_MODE=oracledb ./run.sh</code> for a real database test.";
}

async function refreshUser() {
  const response = await fetch("/api/me");
  const payload = await response.json();
  const user = payload.user;
  if (!user) {
    userBox.innerHTML = "<strong>Not signed in</strong><br />Use Entra ID or a demo user";
    return null;
  }
  userBox.innerHTML = `<strong>${escapeHtml(user.name)}</strong><br />${escapeHtml(user.username)}<br />${escapeHtml((user.roles || []).join(", "))}`;
  return user;
}

async function refreshPage() {
  await refreshConfig();
  const user = await refreshUser();
  if (user) {
    showAuthenticationContextDemo(user);
    return;
  }
  raw.textContent = "Sign in before loading employee data.";
}

function showAuthenticationContextDemo(user) {
  raw.textContent = JSON.stringify({
    demo: "Authenticated end-user security context",
    signed_in_user: {
      name: user.name,
      username: user.username,
      browser_token_roles: user.roles || []
    },
    python: {
      token_exchange: "WebHrDatabase._database_access_token_for_user(user['access_token'])",
      context_creation: "oracledb.create_end_user_security_context(end_user_identity=end_user_database_token, database_access_token=application_database_token)",
      context_attach: "connection.set_end_user_security_context(context)",
      context_clear: "connection.clear_end_user_security_context()"
    },
    deepsec_attributes_visible_in_database: [
      "ORA_END_USER_CONTEXT.username",
      "SYS_CONTEXT('USERENV','AUTHENTICATED_IDENTITY')",
      "SYS_CONTEXT('USERENV','ENTERPRISE_IDENTITY')",
      "SYS_CONTEXT('USERENV','AUTHENTICATION_METHOD')",
      "v$end_user_data_role"
    ],
    enforcement: "Every HR query and update runs after Python attaches this context to a pooled database connection."
  }, null, 2);
}

async function loadEmployees() {
  const payload = await getJson("/api/employees");
  renderEmployees(payload.rows || []);
  raw.textContent = JSON.stringify(payload, null, 2);
  refreshAuditEventsQuietly();
}

async function loadSummary() {
  const payload = await getJson("/api/salary-summary");
  summary.innerHTML = `
    <div>
      <dt>Elevated</dt>
      <dd>${escapeHtml(payload.elevated)}</dd>
    </div>
    <div>
      <dt>Data Roles</dt>
      <dd>${escapeHtml((payload.data_roles || []).join(", "))}</dd>
    </div>
	    <div>
	      <dt>Average Salary</dt>
	      <dd>${escapeHtml(formatCurrency(payload.average_salary))}</dd>
	    </div>
    <div>
      <dt>Employee Count</dt>
      <dd>${escapeHtml(payload.employee_count)}</dd>
    </div>
  `;
  raw.textContent = JSON.stringify(payload, null, 2);
  refreshAuditEventsQuietly();
}

async function loadAuditEvents(updateRaw = true) {
  const payload = await getJson("/api/audit/events", updateRaw ? raw : null);
  renderAuditEvents(payload.events || []);
  if (updateRaw) {
    raw.textContent = JSON.stringify(payload, null, 2);
  }
}

function refreshAuditEventsQuietly() {
  loadAuditEvents(false).catch((error) => {
    auditRows.innerHTML = `<tr><td colspan="7">${escapeHtml(error.message || error)}</td></tr>`;
  });
}

async function disableSalaryEdits() {
  const payload = await postJson("/api/policy/disable-salary-updates", {});
  renderEmployees(payload.rows || []);
  raw.textContent = JSON.stringify(payload, null, 2);
  refreshAuditEventsQuietly();
}

async function enableSalaryEdits() {
  const payload = await postJson("/api/policy/enable-salary-updates", {});
  renderEmployees(payload.rows || []);
  raw.textContent = JSON.stringify(payload, null, 2);
  refreshAuditEventsQuietly();
}

async function getJson(url, outputElement = raw) {
  const response = await fetch(url);
  const payload = await response.json();
  if (!response.ok) {
    if (outputElement) {
      outputElement.textContent = JSON.stringify(payload, null, 2);
    }
    throw new Error(payload.error || "Request failed");
  }
  return payload;
}

function renderEmployees(rows) {
  if (!rows.length) {
    employeeRows.innerHTML = '<tr><td colspan="7">No visible rows.</td></tr>';
    return;
  }
  employeeRows.innerHTML = rows.map((row) => `
    <tr>
      <td>${escapeHtml(valueFor(row, "employee_id"))}</td>
      <td>${escapeHtml(`${valueFor(row, "first_name")} ${valueFor(row, "last_name")}`.trim())}</td>
      <td>${renderEditableCell(row, "phone_number", "can_update_phone_number", "text")}</td>
      <td>${renderEditableCell(row, "salary", "can_update_salary", "number")}</td>
      <td>${escapeHtml(valueFor(row, "ssn"))}</td>
      <td>${renderEditableCell(row, "department_id", "can_update_department_id", "number")}</td>
      <td>${escapeHtml(valueFor(row, "manager_id"))}</td>
    </tr>
  `).join("");
  employeeRows.querySelectorAll("[data-edit-field]").forEach((input) => {
    input.addEventListener("change", saveEmployeeEdit);
    input.addEventListener("focus", showEditAuthorizationDemo);
    input.addEventListener("mouseenter", showEditAuthorizationDemo);
  });
  employeeRows.querySelectorAll("[data-attempt-field]").forEach((button) => {
    button.addEventListener("click", attemptUnauthorizedEdit);
    button.addEventListener("mouseenter", showAttemptAuthorizationDemo);
  });
}

function valueFor(row, key) {
  const upperKey = key.toUpperCase();
  return row[key] ?? row[upperKey] ?? "";
}

function renderEditableCell(row, field, permissionField, inputType) {
  const value = valueFor(row, field);
  if (!isTrue(valueFor(row, permissionField))) {
    return `
      <div class="readonly-cell">
        <span>${escapeHtml(value)}</span>
        <button
          class="attempt-button"
          type="button"
          data-employee-id="${escapeHtml(valueFor(row, "employee_id"))}"
          data-attempt-field="${escapeHtml(field)}"
          data-attempt-value="${escapeHtml(value)}"
        >Try anyway</button>
      </div>
    `;
  }
  return `
    <div class="editable-cell">
      <input
        class="cell-input"
        type="${escapeHtml(inputType)}"
        data-employee-id="${escapeHtml(valueFor(row, "employee_id"))}"
        data-edit-field="${escapeHtml(field)}"
        value="${escapeHtml(value)}"
        aria-label="${escapeHtml(field.replace(/_/g, " "))}"
      />
      <span class="edit-chip">Editable</span>
    </div>
  `;
}

async function saveEmployeeEdit(event) {
  const input = event.target;
  input.disabled = true;
  try {
    const payload = await postJson("/api/employees/update", {
      employee_id: input.dataset.employeeId,
      field: input.dataset.editField,
      value: input.value,
	    });
	    renderEmployees(payload.rows || []);
	    raw.textContent = JSON.stringify(payload, null, 2);
    refreshAuditEventsQuietly();
  } catch (error) {
    raw.textContent = String(error.stack || error);
  } finally {
    input.disabled = false;
  }
}

function showEditAuthorizationDemo(event) {
  const input = event.target;
  const field = input.dataset.editField;
  const employeeId = input.dataset.employeeId;
  raw.textContent = JSON.stringify({
    demo: "Editable cell authorization",
    employee_id: employeeId,
    field,
    python: {
      query_function: "WebHrDatabase._employees_oracle()",
      update_function: "WebHrDatabase._update_employee_field_oracle()",
      note: "Python does not decide whether this field is editable. It asks Oracle, then renders the input only when Oracle returns TRUE."
    },
    sql_authorization_check: `ORA_CHECK_DATA_PRIVILEGE(emp, 'UPDATE', ${field}) AS can_update_${field}`,
    update_path: `UPDATE hr.employees SET ${field} = :value WHERE employee_id = :employee_id`,
    enforcement: "The UPDATE is still executed under the end-user security context, so Deep Data Security remains the enforcement point."
  }, null, 2);
}

function showAttemptAuthorizationDemo(event) {
  const button = event.target;
  const field = button.dataset.attemptField;
  raw.textContent = JSON.stringify({
    demo: "Unauthorized edit attempt",
    field,
    sql_authorization_check: `ORA_CHECK_DATA_PRIVILEGE(emp, 'UPDATE', ${field}) AS can_update_${field}`,
    update_path: `UPDATE hr.employees SET ${field} = :value WHERE employee_id = :employee_id`,
    enforcement: "The UI predicts this edit is not allowed, but Try anyway still sends the UPDATE so Oracle Deep Data Security can prove enforcement."
  }, null, 2);
}

function showPolicyToggleDemo(enabled) {
  raw.textContent = JSON.stringify({
    demo: enabled ? "Restore Salary Edits" : "Disable Salary Edits",
    what_happens_when_pressed: {
      api_call: enabled ? "POST /api/policy/enable-salary-updates" : "POST /api/policy/disable-salary-updates",
      python_function: "WebHrDatabase._set_salary_update_policy_oracle(user, enabled)",
      database_procedure: enabled ? "SYS.WEB_HR_ENABLE_SALARY_UPDATES" : "SYS.WEB_HR_DISABLE_SALARY_UPDATES",
      deepsec_policy_change: enabled
        ? "Recreates HR.HRAPP_MANAGER_ACCESS with UPDATE(salary, department_id)."
        : "Recreates HR.HRAPP_MANAGER_ACCESS with UPDATE(department_id) only, removing UPDATE(salary).",
      authorization_refresh: "The app reloads employees and calls ORA_CHECK_DATA_PRIVILEGE(emp, 'UPDATE', salary) again for each row.",
      enforcement: "Salary edit enforcement stays in Oracle Deep Data Security. The UI only reflects Oracle's current policy decision."
    }
  }, null, 2);
}

function renderAuditEvents(events) {
  if (!events.length) {
    auditRows.innerHTML = '<tr><td colspan="7">No audit records in the last 3 minutes. Run Load Employees or edit a field, then refresh.</td></tr>';
    return;
  }
  auditRows.innerHTML = events.map((event) => `
    <tr>
      <td>${escapeHtml(valueFor(event, "event_timestamp"))}</td>
      <td>${escapeHtml(valueFor(event, "action_name"))}</td>
      <td>${escapeHtml(valueFor(event, "end_user_name"))}</td>
      <td>
        <strong>${escapeHtml(valueFor(event, "dbusername"))}</strong>
        <span class="audit-detail">${escapeHtml(valueFor(event, "authentication_type"))}</span>
      </td>
      <td>
        ${escapeHtml(valueFor(event, "userhost"))}
        <span class="audit-detail">${escapeHtml(valueFor(event, "client_program_name") || valueFor(event, "os_username"))}</span>
        <span class="audit-detail">SESSIONID ${escapeHtml(valueFor(event, "sessionid"))}</span>
      </td>
      <td><code>${escapeHtml(valueFor(event, "sql_text_preview"))}</code></td>
      <td>${escapeHtml(valueFor(event, "return_code"))}</td>
    </tr>
  `).join("");
}

async function attemptUnauthorizedEdit(event) {
  const button = event.target;
  button.disabled = true;
  try {
    const payload = await postJson("/api/employees/update", {
      employee_id: button.dataset.employeeId,
      field: button.dataset.attemptField,
      value: button.dataset.attemptValue,
    });
    renderEmployees(payload.rows || []);
    raw.textContent = JSON.stringify(payload, null, 2);
    refreshAuditEventsQuietly();
  } catch (error) {
    raw.textContent = String(error.stack || error);
  } finally {
    button.disabled = false;
  }
}

async function postJson(url, body) {
  const response = await fetch(url, {
    method: "POST",
    headers: {"Content-Type": "application/json"},
    body: JSON.stringify(body),
  });
  const payload = await response.json();
  if (!response.ok) {
    raw.textContent = JSON.stringify(payload, null, 2);
    throw new Error(payload.error || "Request failed");
  }
  return payload;
}

function isTrue(value) {
  return value === true || String(value).toUpperCase() === "TRUE";
}

function formatCurrency(value) {
  if (value == null || value === "") {
    return "";
  }
  const number = Number(value);
  if (!Number.isFinite(number)) {
    return value;
  }
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(number);
}

function escapeHtml(value) {
  return String(value == null ? "" : value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

refreshPage().catch((error) => {
  if (!raw.textContent || raw.textContent === "Sign in before loading employee data.") {
    raw.textContent = String(error.stack || error);
  }
});

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
let lastEmployeeRows = [];

const fieldLabels = {
  phone_number: "Phone",
  salary: "Salary",
  department_id: "Dept",
};

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

function refreshAuditEventsAfterWrite() {
  auditRows.innerHTML = '<tr><td colspan="7">Refreshing audit events...</td></tr>';
  refreshAuditEventsQuietly();
  window.setTimeout(refreshAuditEventsQuietly, 1500);
  window.setTimeout(refreshAuditEventsQuietly, 3500);
}

async function disableSalaryEdits() {
  const payload = await postJson("/api/policy/disable-salary-updates", {});
  renderEmployees(payload.rows || []);
  raw.textContent = JSON.stringify(payload, null, 2);
  refreshAuditEventsAfterWrite();
}

async function enableSalaryEdits() {
  const payload = await postJson("/api/policy/enable-salary-updates", {});
  renderEmployees(payload.rows || []);
  raw.textContent = JSON.stringify(payload, null, 2);
  refreshAuditEventsAfterWrite();
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
  lastEmployeeRows = rows;
  if (!rows.length) {
    employeeRows.innerHTML = '<tr><td colspan="7">No visible rows.</td></tr>';
    return;
  }
  employeeRows.innerHTML = rows.map((row) => `
    <tr>
      <td>${escapeHtml(valueFor(row, "employee_id"))}</td>
      <td>${escapeHtml(`${valueFor(row, "first_name")} ${valueFor(row, "last_name")}`.trim())}</td>
      <td>${renderEditableCell(row, "phone_number", "can_update_phone_number", "text")}</td>
      <td>${renderEditableCell(row, "salary", "can_update_salary", "decimal")}</td>
      <td>${escapeHtml(valueFor(row, "ssn"))}</td>
      <td>${renderEditableCell(row, "department_id", "can_update_department_id", "numeric")}</td>
      <td>${escapeHtml(valueFor(row, "manager_id"))}</td>
    </tr>
  `).join("");
  employeeRows.querySelectorAll("[data-edit-trigger]").forEach((button) => {
    button.addEventListener("click", openEmployeeEditor);
    button.addEventListener("focus", showEditAuthorizationDemo);
    button.addEventListener("mouseenter", showEditAuthorizationDemo);
  });
}

function valueFor(row, key) {
  const upperKey = key.toUpperCase();
  return row[key] ?? row[upperKey] ?? "";
}

function renderEditableCell(row, field, permissionField, inputMode) {
  const value = valueFor(row, field);
  const displayValue = formatEditableValue(field, value);
  const valueClass = field === "salary" ? "money-value" : "";
  if (!isTrue(valueFor(row, permissionField))) {
    return `
      <div class="readonly-cell">
        <span class="${valueClass}">${escapeHtml(displayValue)}</span>
      </div>
    `;
  }
  return `
    <div class="editable-cell">
      <span class="editable-value ${valueClass}">${escapeHtml(displayValue)}</span>
      <button
        class="icon-button edit-button"
        type="button"
        data-employee-id="${escapeHtml(valueFor(row, "employee_id"))}"
        data-edit-trigger="${escapeHtml(field)}"
        data-edit-field="${escapeHtml(field)}"
        data-input-mode="${escapeHtml(inputMode)}"
        data-current-value="${escapeHtml(value)}"
        aria-label="Edit ${escapeHtml(fieldLabel(field))}"
        title="Edit ${escapeHtml(fieldLabel(field))}"
      >${pencilIcon()}</button>
    </div>
  `;
}

function openEmployeeEditor(event) {
  const button = event.target.closest("[data-edit-trigger]");
  if (!button) {
    return;
  }
  const cell = button.closest("[data-edit-cell], .editable-cell");
  const field = button.dataset.editField;
  const employeeId = button.dataset.employeeId;
  const value = button.dataset.currentValue;
  const inputMode = button.dataset.inputMode || "text";
  const inputId = editInputId(employeeId, field);
  cell.innerHTML = `
    <form class="edit-form" data-edit-form>
      <input
        id="${escapeHtml(inputId)}"
        name="${escapeHtml(field)}"
        class="cell-input"
        type="text"
        inputmode="${escapeHtml(inputMode)}"
        autocomplete="off"
        data-employee-id="${escapeHtml(employeeId)}"
        data-edit-field="${escapeHtml(field)}"
        value="${escapeHtml(value)}"
        aria-label="${escapeHtml(fieldLabel(field))}"
      />
      <button class="icon-button save-button" type="submit" aria-label="Save ${escapeHtml(fieldLabel(field))}" title="Save">
        ${checkIcon()}
      </button>
      <button class="icon-button cancel-button" type="button" data-cancel-edit aria-label="Cancel edit" title="Cancel">
        ${xIcon()}
      </button>
    </form>
  `;
  const form = cell.querySelector("[data-edit-form]");
  const input = form.querySelector("[data-edit-field]");
  form.addEventListener("submit", saveEmployeeEdit);
  form.querySelector("[data-cancel-edit]").addEventListener("click", () => renderEmployees(lastEmployeeRows));
  input.addEventListener("focus", showEditAuthorizationDemo);
  input.addEventListener("mouseenter", showEditAuthorizationDemo);
  input.focus();
  input.select();
  showEditAuthorizationDemo({target: input});
}

async function saveEmployeeEdit(event) {
  event.preventDefault();
  const form = event.target.closest("[data-edit-form]");
  const input = form.querySelector("[data-edit-field]");
  form.querySelectorAll("button, input").forEach((control) => {
    control.disabled = true;
  });
  try {
    const payload = await postJson("/api/employees/update", {
      employee_id: input.dataset.employeeId,
      field: input.dataset.editField,
      value: input.value,
	    });
    verifyEmployeeSave(payload);
	    renderEmployees(payload.rows || []);
	    raw.textContent = JSON.stringify(payload, null, 2);
    refreshAuditEventsAfterWrite();
  } catch (error) {
    if (error.payload) {
      raw.textContent = JSON.stringify(error.payload, null, 2);
    } else {
      raw.textContent = String(error.stack || error);
    }
  } finally {
    form.querySelectorAll("button, input").forEach((control) => {
      control.disabled = false;
    });
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

function showPolicyToggleDemo(enabled) {
  raw.textContent = JSON.stringify({
    demo: enabled ? "Restore Salary Edits" : "Disable Salary Edits",
    what_happens_when_pressed: {
      api_call: enabled ? "POST /api/policy/enable-salary-updates" : "POST /api/policy/disable-salary-updates",
      python_function: "WebHrDatabase._set_salary_update_policy_oracle(user, enabled)",
      database_procedure: enabled ? "SYS.WEB_HR_ENABLE_SALARY_UPDATES" : "SYS.WEB_HR_DISABLE_SALARY_UPDATES",
      deepsec_policy_change: enabled
        ? "Recreates HR.HRAPP_MANAGER_ACCESS with UPDATE(employee_id, salary, department_id, first_name)."
        : "Recreates HR.HRAPP_MANAGER_ACCESS with UPDATE(employee_id, department_id, first_name), removing UPDATE(salary).",
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

function verifyEmployeeSave(payload) {
  const updated = payload.updated;
  if (!updated) {
    return;
  }
  if (updated.row_count !== 1 || updated.saved === false) {
    const error = new Error(payload.note || "The update did not save.");
    error.payload = payload;
    throw error;
  }
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

function formatEditableValue(field, value) {
  if (field !== "salary") {
    return value;
  }
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
    minimumFractionDigits: 0,
    maximumFractionDigits: 0,
  }).format(number);
}

function fieldLabel(field) {
  return fieldLabels[field] || field.replace(/_/g, " ");
}

function editInputId(employeeId, field) {
  const safeEmployeeId = String(employeeId).replace(/[^A-Za-z0-9_-]/g, "_");
  const safeField = String(field).replace(/[^A-Za-z0-9_-]/g, "_");
  return `employee-${safeEmployeeId}-${safeField}-input`;
}

function pencilIcon() {
  return '<svg aria-hidden="true" viewBox="0 0 24 24"><path d="M16.9 3.7a2.1 2.1 0 0 1 3 3L8.5 18.1 4 19.5l1.4-4.5L16.9 3.7z"></path><path d="m15.5 5.1 3.4 3.4"></path></svg>';
}

function checkIcon() {
  return '<svg aria-hidden="true" viewBox="0 0 24 24"><path d="m20 6-11 11-5-5"></path></svg>';
}

function xIcon() {
  return '<svg aria-hidden="true" viewBox="0 0 24 24"><path d="M18 6 6 18"></path><path d="m6 6 12 12"></path></svg>';
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

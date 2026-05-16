const userBox = document.querySelector("#userBox");
const employeeRows = document.querySelector("#employeeRows");
const summary = document.querySelector("#summary");
const raw = document.querySelector("#raw");
const employeesButton = document.querySelector("#employeesButton");
const summaryButton = document.querySelector("#summaryButton");
const modeBanner = document.querySelector("#modeBanner");

employeesButton.addEventListener("click", loadEmployees);
summaryButton.addEventListener("click", loadSummary);

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
    raw.textContent = "Use Load Employees to run the HR.EMPLOYEES query.";
    return;
  }
  raw.textContent = "Sign in before loading employee data.";
}

async function loadEmployees() {
  const payload = await getJson("/api/employees");
  renderEmployees(payload.rows || []);
  raw.textContent = JSON.stringify(payload, null, 2);
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
      <dd>${escapeHtml(payload.average_salary)}</dd>
    </div>
    <div>
      <dt>Employee Count</dt>
      <dd>${escapeHtml(payload.employee_count)}</dd>
    </div>
  `;
  raw.textContent = JSON.stringify(payload, null, 2);
}

async function getJson(url, outputElement = raw) {
  const response = await fetch(url);
  const payload = await response.json();
  if (!response.ok) {
    outputElement.textContent = JSON.stringify(payload, null, 2);
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
      <td>${renderEditableCell(row, "phone_number", "can_update_phone_number")}</td>
      <td>${renderEditableCell(row, "salary", "can_update_salary")}</td>
      <td>${escapeHtml(valueFor(row, "ssn"))}</td>
      <td>${renderEditableCell(row, "department_id", "can_update_department_id")}</td>
      <td>${escapeHtml(valueFor(row, "manager_id"))}</td>
    </tr>
  `).join("");
  employeeRows.querySelectorAll("[data-edit-field]").forEach((input) => {
    input.addEventListener("change", saveEmployeeEdit);
  });
}

function valueFor(row, key) {
  const upperKey = key.toUpperCase();
  return row[key] ?? row[upperKey] ?? "";
}

function renderEditableCell(row, field, permissionField) {
  const value = valueFor(row, field);
  if (!isTrue(valueFor(row, permissionField))) {
    return escapeHtml(value);
  }
  return `
    <input
      class="cell-input"
      data-employee-id="${escapeHtml(valueFor(row, "employee_id"))}"
      data-edit-field="${escapeHtml(field)}"
      value="${escapeHtml(value)}"
      aria-label="${escapeHtml(field.replace(/_/g, " "))}"
    />
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
  } catch (error) {
    raw.textContent = String(error.stack || error);
  } finally {
    input.disabled = false;
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

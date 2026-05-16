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
    await loadEmployees();
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

async function getJson(url) {
  const response = await fetch(url);
  const payload = await response.json();
  if (!response.ok) {
    raw.textContent = JSON.stringify(payload, null, 2);
    throw new Error(payload.error || "Request failed");
  }
  return payload;
}

function renderEmployees(rows) {
  if (!rows.length) {
    employeeRows.innerHTML = '<tr><td colspan="4">No visible rows.</td></tr>';
    return;
  }
  employeeRows.innerHTML = rows.map((row) => `
    <tr>
      <td>${escapeHtml(row.employee_id || row.EMPLOYEE_ID)}</td>
      <td>${escapeHtml((row.first_name || row.FIRST_NAME || "") + " " + (row.last_name || row.LAST_NAME || ""))}</td>
      <td>${escapeHtml(row.salary || row.SALARY)}</td>
      <td>${escapeHtml(row.manager_id || row.MANAGER_ID || "")}</td>
    </tr>
  `).join("");
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

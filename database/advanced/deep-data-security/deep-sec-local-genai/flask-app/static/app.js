const csrfToken = document.querySelector("meta[name='csrf-token']")?.content;
const requestHeaders = {"Content-Type": "application/json", "X-CSRFToken": csrfToken};
const error = document.querySelector("#error");

function showError(message) {
  if (error) error.textContent = message || "";
}

function formatNumber(value) {
  return new Intl.NumberFormat("en-US").format(value);
}

async function jsonRequest(url, options) {
  const response = await fetch(url, options);
  let payload = {};
  try {
    payload = await response.json();
  } catch (_) {
    payload = {error: "The server returned an unexpected response."};
  }
  if (response.status === 401) window.location.assign("/");
  return {response, payload};
}

const login = document.querySelector("#login");
const loginForm = document.querySelector("#login-form");
if (login && loginForm) {
  loginForm.addEventListener("submit", async (event) => {
    event.preventDefault();
    showError("");
    login.disabled = true;
    try {
      const {response, payload} = await jsonRequest("/api/login", {
        method: "POST", headers: requestHeaders,
        body: JSON.stringify({persona: document.querySelector("#persona").value, password: document.querySelector("#password").value})
      });
      if (!response.ok) {
        showError(payload.error || "Database sign-in failed");
        login.disabled = false;
        return;
      }
      window.location.assign("/query");
    } catch (_) {
      showError("Unable to sign in. Please try again.");
      login.disabled = false;
    }
  });
}

const logout = document.querySelector("#logout");
if (logout) {
  logout.addEventListener("click", async () => {
    await fetch("/api/logout", {method: "POST", headers: requestHeaders});
    window.location.assign("/");
  });
}

const load = document.querySelector("#load");
if (load) {
  load.addEventListener("click", async () => {
    showError("");
    const status = document.querySelector("#load-status");
    load.disabled = true;
    load.textContent = "Loading customer accounts…";
    status.textContent = "Loading customer accounts…";
    try {
      const {response, payload} = await jsonRequest("/api/customers", {method: "POST", headers: requestHeaders});
      if (!response.ok) {
        showError(payload.error || "Unable to load customer accounts.");
        return;
      }
      renderSecurityContext(payload.context, payload.row_count);
      renderCustomers(payload.rows);
    } catch (_) {
      showError("Unable to load customer accounts. Please try again.");
    } finally {
      load.disabled = false;
      load.textContent = "Customer Report";
      status.textContent = "";
    }
  });
}

function appendContextItem(container, label, value) {
  const term = document.createElement("dt");
  term.textContent = label;
  const description = document.createElement("dd");
  description.textContent = String(value ?? "Not available");
  container.append(term, description);
}

function renderSecurityContext(context, rowCount) {
  const panel = document.querySelector("#security-context");
  const container = document.querySelector("#context");
  container.replaceChildren();
  appendContextItem(container, "End User", context?.end_user);
  appendContextItem(container, "Active Data Roles", context?.data_role);
  appendContextItem(container, "Rows Returned by Oracle", rowCount);
  panel.hidden = false;
}

const aiForm = document.querySelector("#ai-form");
if (aiForm) {
  aiForm.addEventListener("submit", async (event) => {
    event.preventDefault();
    const ask = document.querySelector("#ask-ai");
    const status = document.querySelector("#ai-status");
    const question = document.querySelector("#ai-question").value.trim();
    showError("");
    if (!question) {
      showError("Enter a question for Customer Insights.");
      return;
    }
    ask.disabled = true;
    ask.textContent = "Generating insights…";
    status.textContent = "Loading Oracle-authorized customer data…";
    try {
      const {response, payload} = await jsonRequest("/api/ai", {
        method: "POST", headers: requestHeaders, body: JSON.stringify({question})
      });
      if (!response.ok) {
        showError(payload.error || "Customer Insights is unavailable.");
        return;
      }
      document.querySelector("#ai-answer").textContent = payload.answer;
      document.querySelector("#ai-result").hidden = false;
      renderSecurityContext(payload.context, payload.row_count);
    } catch (_) {
      showError("Customer Insights is unavailable. Please try again.");
    } finally {
      ask.disabled = false;
      ask.textContent = "Generate Insights";
      status.textContent = "";
    }
  });
}

function makeCell(value, className = "") {
  const cell = document.createElement("td");
  if (className) cell.className = className;
  cell.textContent = value;
  return cell;
}

let currentRows = [];
let currentSort = {key: null, direction: "asc"};

function sortRows(rows, key, type, direction) {
  const sorted = [...rows];
  sorted.sort((a, b) => {
    const aVal = a[key];
    const bVal = b[key];
    if (aVal == null && bVal == null) return 0;
    if (aVal == null) return 1;
    if (bVal == null) return -1;
    if (type === "number") return direction === "asc" ? aVal - bVal : bVal - aVal;
    return direction === "asc"
      ? String(aVal).localeCompare(String(bVal))
      : String(bVal).localeCompare(String(aVal));
  });
  return sorted;
}

function renderCustomers(rows) {
  currentRows = rows || [];
  const results = document.querySelector("#results");
  const accountCount = document.querySelector("#account-count");
  accountCount.textContent = `${rows?.length || 0} Customer Account${rows?.length === 1 ? "" : "s"}`;
  results.replaceChildren();
  if (!rows?.length) {
    const row = document.createElement("tr");
    row.className = "empty";
    const cell = document.createElement("td");
    cell.colSpan = 5;
    cell.textContent = "No customers were returned.";
    row.append(cell);
    results.append(row);
    return;
  }
  for (const customer of rows) {
    const row = document.createElement("tr");
    row.append(
      makeCell(customer.customer_name ?? ""),
      makeCell(customer.region ?? ""),
      makeCell(formatNumber(customer.revenue), "number"),
      makeCell(customer.credit_limit == null ? "Not authorized" : formatNumber(customer.credit_limit), "number"),
      makeCell(customer.sensitive_identifier ?? "Not authorized")
    );
    results.append(row);
  }
}

document.querySelectorAll("th.sortable").forEach((header) => {
  header.addEventListener("click", () => {
    const key = header.dataset.sortKey;
    const type = header.dataset.sortType;
    const direction = currentSort.key === key && currentSort.direction === "asc" ? "desc" : "asc";
    currentSort = {key, direction};
    document.querySelectorAll("th.sortable").forEach((th) => th.classList.remove("sort-asc", "sort-desc"));
    header.classList.add(direction === "asc" ? "sort-asc" : "sort-desc");
    renderCustomers(sortRows(currentRows, key, type, direction));
  });
});

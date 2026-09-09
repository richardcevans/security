const csrfToken = document.querySelector("meta[name='csrf-token']")?.content;
const requestHeaders = {"Content-Type": "application/json", "X-CSRFToken": csrfToken};
const error = document.querySelector("#error");

function showError(message) {
  if (error) error.textContent = message || "";
}

function formatNumber(value) {
  return new Intl.NumberFormat("en-US").format(value);
}

async function jsonRequest(url, options, {redirectOn401 = true} = {}) {
  const response = await fetch(url, options);
  let payload = {};
  try {
    payload = await response.json();
  } catch (_) {
    payload = {error: "The server returned an unexpected response."};
  }
  if (response.status === 401 && redirectOn401) window.location.assign("/");
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
      }, {redirectOn401: false});
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
  logout.addEventListener("click", async (event) => {
    event.preventDefault();
    logout.disabled = true;
    document.cookie = "hol_tour_seen=; path=/; max-age=0; samesite=Lax";
    document.cookie = "hol_deebee_greeted=; path=/; max-age=0; samesite=Lax";
    try {
      await fetch("/api/logout", {
        method: "POST", headers: requestHeaders, cache: "no-store", credentials: "same-origin"
      });
    } finally {
      // Replace the protected page so Back cannot restore it from history.
      window.location.replace("/");
    }
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

const loadOrderHistory = document.querySelector("#load-order-history");
if (loadOrderHistory) {
  loadOrderHistory.addEventListener("click", async () => {
    const result = document.querySelector("#order-history-result");
    const status = document.querySelector("#order-history-status");
    result.replaceChildren(makeMessage("Loading…", "muted"));
    loadOrderHistory.disabled = true;
    loadOrderHistory.textContent = "Loading Order History…";
    status.textContent = "Loading Order History…";
    try {
      const {response, payload} = await jsonRequest("/api/order-history", {method: "POST", headers: requestHeaders});
      if (!response.ok) {
        renderOrderHistoryMessage(payload.error || "Order history is unavailable.", "warning-banner");
      } else if (Array.isArray(payload.rows)) {
        renderOrderHistoryTable(payload.rows || [], payload.context, payload.row_count);
      } else {
        renderOrderHistoryMessage(payload.error || "Order history is unavailable.", "warning-banner");
      }
    } catch (_) {
      renderOrderHistoryMessage("Could not contact the server.", "warning-banner");
    } finally {
      loadOrderHistory.disabled = false;
      loadOrderHistory.textContent = "Order History Report";
      status.textContent = "";
    }
  });
}

function makeMessage(message, className = "") {
  const paragraph = document.createElement("p");
  paragraph.className = className;
  paragraph.textContent = message;
  return paragraph;
}

function renderOrderHistoryMessage(message, className) {
  const result = document.querySelector("#order-history-result");
  const banner = document.createElement("div");
  banner.className = className;
  banner.textContent = message;
  result.replaceChildren(banner);
}

function renderOrderHistoryTable(rows, contextData, rowCount) {
  const result = document.querySelector("#order-history-result");
  const context = document.querySelector("#order-history-context");
  const details = document.querySelector("#order-history-context-details");
  details.replaceChildren();
  appendContextItem(details, "End User", contextData?.end_user);
  appendContextItem(details, "Active Data Roles", contextData?.data_role);
  appendContextItem(details, "Rows Returned by Oracle", rowCount ?? rows.length);
  context.hidden = false;
  if (!rows.length) {
    result.replaceChildren(makeMessage("No order history rows are authorized for this account.", "muted"));
    return;
  }
  const columns = Object.keys(rows[0]);
  const columnLabels = {order_id: "Order ID", customer_id: "Customer ID"};
  const table = document.createElement("table");
  const head = document.createElement("thead");
  const headRow = document.createElement("tr");
  for (const column of columns) {
    const cell = document.createElement("th");
    cell.textContent = columnLabels[column] || column.split("_").map((word) => word.charAt(0).toUpperCase() + word.slice(1)).join(" ");
    headRow.append(cell);
  }
  head.append(headRow);
  const body = document.createElement("tbody");
  for (const row of rows) {
    const tableRow = document.createElement("tr");
    for (const column of columns) {
      const numericColumn = ["order_id", "customer_id", "amount"].includes(column);
      const value = row[column] == null ? "Not authorized" : (column === "amount" ? formatNumber(row[column]) : row[column]);
      tableRow.append(makeCell(value, numericColumn ? "number" : ""));
    }
    body.append(tableRow);
  }
  table.append(head, body);
  const wrap = document.createElement("div");
  wrap.className = "table-wrap";
  wrap.append(table);
  result.replaceChildren(wrap);
}

const loadVibeReport = document.querySelector("#load-vibe-report");
if (loadVibeReport) {
  loadVibeReport.addEventListener("click", async () => {
    const result = document.querySelector("#vibe-report-result");
    const status = document.querySelector("#vibe-report-status");
    const reportId = loadVibeReport.dataset.reportId;
    loadVibeReport.disabled = true;
    loadVibeReport.textContent = "Running statement…";
    status.textContent = "Sending the generated SQL statement to Oracle…";
    result.replaceChildren(makeMessage("Loading…", "muted"));
    try {
      const {response, payload} = await jsonRequest(`/api/vibe-report/${encodeURIComponent(reportId)}`, {method: "POST", headers: requestHeaders});
      if (!response.ok) {
        result.replaceChildren(makeMessage(payload.error || "This statement is unavailable.", "warning-banner"));
        return;
      }
      if (["INSERT", "UPDATE", "DELETE"].includes(payload.operation)) {
        renderSecurityContext(payload.context, payload.affected_rows, "Rows changed by Oracle");
        const verb = payload.operation === "DELETE" ? "deleted" : payload.operation === "INSERT" ? "inserted" : "updated";
        result.replaceChildren(makeMessage(`Oracle authorized and committed the ${payload.operation} statement. ${payload.affected_rows} row${payload.affected_rows === 1 ? " was" : "s were"} ${verb}.`, "success-banner"));
        return;
      }
      renderSecurityContext(payload.context, payload.row_count);
      renderDynamicReportTable(result, payload.rows || []);
      if (payload.displayed_count < payload.row_count) {
        result.prepend(makeMessage(`Showing the first ${payload.displayed_count} of ${payload.row_count} rows returned by Oracle.`, "muted"));
      }
    } catch (_) {
      result.replaceChildren(makeMessage("Could not contact the server.", "warning-banner"));
    } finally {
      loadVibeReport.disabled = false;
      loadVibeReport.textContent = "Run statement";
      status.textContent = "";
    }
  });
}

function renderDynamicReportTable(target, rows) {
  if (!rows.length) {
    target.replaceChildren(makeMessage("Oracle returned no rows for this database identity.", "muted"));
    return;
  }
  const columns = Object.keys(rows[0]);
  const table = document.createElement("table");
  const head = document.createElement("thead");
  const headRow = document.createElement("tr");
  for (const column of columns) {
    const cell = document.createElement("th");
    cell.textContent = column.split("_").map((word) => word.charAt(0).toUpperCase() + word.slice(1)).join(" ");
    headRow.append(cell);
  }
  head.append(headRow);
  const body = document.createElement("tbody");
  for (const row of rows) {
    const tableRow = document.createElement("tr");
    for (const column of columns) tableRow.append(makeCell(row[column] == null ? "Not authorized" : row[column]));
    body.append(tableRow);
  }
  table.append(head, body);
  const wrap = document.createElement("div");
  wrap.className = "table-wrap";
  wrap.append(table);
  target.replaceChildren(wrap);
}

function appendContextItem(container, label, value) {
  const term = document.createElement("dt");
  term.textContent = label;
  const description = document.createElement("dd");
  description.textContent = String(value ?? "Not available");
  container.append(term, description);
}

function renderSecurityContext(context, rowCount, countLabel = "Rows Returned by Oracle") {
  const panel = document.querySelector("#security-context");
  const container = document.querySelector("#context");
  container.replaceChildren();
  appendContextItem(container, "End User", context?.end_user);
  appendContextItem(container, "Active Data Roles", context?.data_role);
  appendContextItem(container, countLabel, rowCount);
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

for (const prompt of document.querySelectorAll("[data-insight-question]")) {
  prompt.addEventListener("click", () => {
    const question = document.querySelector("#ai-question");
    if (!question) return;
    question.value = prompt.dataset.insightQuestion || "";
    showError("");
    question.focus();
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
    cell.colSpan = 8;
    cell.textContent = "No customers were returned.";
    row.append(cell);
    results.append(row);
    return;
  }
  for (const customer of rows) {
    const row = document.createElement("tr");
    row.append(
      makeCell(customer.customer_id ?? "Not authorized", "number"),
      makeCell(customer.customer_name ?? ""),
      makeCell(customer.sales_rep ?? "Not authorized"),
      makeCell(customer.manager_id ?? "", "number"),
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

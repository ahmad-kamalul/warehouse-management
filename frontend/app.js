"use strict";

const API = window.WAREHOUSE_MANAGEMENT_CONFIG.apiBaseUrl.replace(/\/$/, "");
const $ = (selector) => document.querySelector(selector);
const authForm = $("#auth-form");
const itemForm = $("#item-form");
const dialog = $("#item-dialog");
const state = {
  // Memory-only tokens: refreshing requires signing in again.
  token: null, user: null, authMode: "login", page: 0,
  totalPages: 0, editing: null, listRequest: 0
};
const money = new Intl.NumberFormat("en-MY", { style: "currency", currency: "MYR" });

class ApiError extends Error {
  constructor(status, message, errors = {}) {
    super(message); this.status = status; this.errors = errors;
  }
}

function showNotice(message, error = false, target = $("#notice")) {
  target.textContent = message;
  target.classList.toggle("error", error);
  target.hidden = !message;
}

function describeError(error) {
  if (error instanceof ApiError) {
    const fields = Object.entries(error.errors).map(([field, message]) => `${field}: ${message}`);
    return [error.message, ...fields].join(" · ");
  }
  return "Could not connect. Check that the backend is running.";
}

/** Central HTTP helper: the frontend never accesses the database directly. */
async function api(endpoint, options = {}) {
  const headers = { ...options.headers };
  if (options.body !== undefined) headers["Content-Type"] = "application/json";
  if (state.token) headers.Authorization = `Bearer ${state.token}`;
  const response = await fetch(`${API}${endpoint}`, {
    method: options.method || "GET", headers,
    body: options.body === undefined ? undefined : JSON.stringify(options.body)
  });
  const data = response.status === 204 ? null : await response.json().catch(() => null);
  if (!response.ok) {
    if (response.status === 401 && state.token) {
      signOut(); showNotice("Your session expired. Sign in again.", true);
    }
    throw new ApiError(response.status, data?.message || `Request failed (${response.status})`, data?.errors || {});
  }
  return data;
}

function setAuthMode(mode) {
  state.authMode = mode;
  const registering = mode === "register";
  $("#name-field").hidden = !registering;
  const nameInput = authForm.elements.namedItem("name");
  nameInput.disabled = !registering; nameInput.required = registering;
  const password = $("#auth-password");
  password.minLength = registering ? 12 : 1;
  password.autocomplete = registering ? "new-password" : "current-password";
  $("#password-help").hidden = !registering;
  $("#auth-title").textContent = registering ? "Create your workspace" : "Welcome back";
  $("#auth-description").textContent = registering
    ? "Start with a private inventory for your account." : "Sign in to manage your inventory.";
  $("#auth-submit").textContent = registering ? "Create account" : "Sign in";
  $("#login-tab").classList.toggle("active", !registering);
  $("#register-tab").classList.toggle("active", registering);
  $("#login-tab").setAttribute("aria-pressed", String(!registering));
  $("#register-tab").setAttribute("aria-pressed", String(registering));
  showNotice("");
}

function signIn(result) {
  state.token = result.accessToken; state.user = result.user; state.page = 0;
  $("#auth-panel").hidden = true; $("#inventory-panel").hidden = false;
  $("#account").hidden = false; $("#account-name").textContent = result.user.name;
  authForm.reset();
}

function signOut() {
  // Invalidates pending list responses, so old data cannot reappear after logout.
  state.listRequest++;
  state.token = null; state.user = null; state.editing = null;
  state.page = 0; state.totalPages = 0;
  if (dialog.open) dialog.close();
  $("#item-rows").replaceChildren();
  $("#inventory-panel").hidden = true; $("#account").hidden = true;
  $("#auth-panel").hidden = false;
  $("#filters").reset(); authForm.reset();
}

authForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  const submit = $("#auth-submit");
  const data = new FormData(authForm);
  const registering = state.authMode === "register";
  const body = { email: String(data.get("email")).trim(), password: String(data.get("password")) };
  if (registering) body.name = String(data.get("name")).trim();
  submit.disabled = true; showNotice("");
  try {
    const result = await api(registering ? "/auth/register" : "/auth/login", { method: "POST", body });
    signIn(result); await loadItems();
  } catch (error) { showNotice(describeError(error), true); }
  finally { submit.disabled = false; }
});

$("#login-tab").addEventListener("click", () => setAuthMode("login"));
$("#register-tab").addEventListener("click", () => setAuthMode("register"));
$("#logout").addEventListener("click", () => { signOut(); showNotice("Signed out."); });

/** Sequence number prevents an older response from replacing newer results. */
async function loadItems() {
  if (!state.token) return;
  const requestNumber = ++state.listRequest;
  const filters = new FormData($("#filters"));
  const parameters = new URLSearchParams({
    q: String(filters.get("q") || "").trim(), category: String(filters.get("category") || "").trim(),
    lowStock: String(filters.has("lowStock")), sortBy: String(filters.get("sortBy")),
    direction: String(filters.get("direction")), page: String(state.page), size: "10"
  });
  $("#inventory-count").textContent = "Loading inventory…";
  $("#previous-page").disabled = true; $("#next-page").disabled = true;
  try {
    const result = await api(`/items?${parameters}`);
    if (requestNumber !== state.listRequest || !state.token) return;
    // Deleting the last row on the last page can invalidate that page.
    if (state.page > 0 && state.page >= result.totalPages) {
      state.page = Math.max(0, result.totalPages - 1); return loadItems();
    }
    state.totalPages = result.totalPages; renderItems(result.content);
    $("#inventory-count").textContent = `${result.totalElements} matching item${result.totalElements === 1 ? "" : "s"}`;
    $("#page-label").textContent = `Page ${state.page + 1} of ${Math.max(1, result.totalPages)}`;
    $("#previous-page").disabled = state.page === 0;
    $("#next-page").disabled = state.page + 1 >= result.totalPages;
  } catch (error) {
    if (requestNumber !== state.listRequest || !state.token) return;
    $("#inventory-count").textContent = "Inventory could not be loaded.";
    showNotice(describeError(error), true);
  }
}

function renderItems(items) {
  const body = $("#item-rows"), template = $("#item-row-template");
  const fragment = document.createDocumentFragment();
  for (const item of items) {
    const row = template.content.firstElementChild.cloneNode(true);
    // textContent prevents stored user input becoming executable HTML.
    row.querySelector(".item-name").textContent = item.name;
    row.querySelector(".item-sku").textContent = item.sku;
    row.querySelector(".item-category").textContent = item.category;
    row.querySelector(".item-quantity").textContent = `${item.quantity} units`;
    row.querySelector(".item-price").textContent = money.format(item.price);
    row.querySelector(".badge").hidden = !item.lowStock;
    row.querySelector(".edit-item").addEventListener("click", () => openEditor(item.id));
    row.querySelector(".delete-item").addEventListener("click", (event) => deleteItem(item, event.currentTarget));
    fragment.append(row);
  }
  body.replaceChildren(fragment); $("#empty-state").hidden = items.length !== 0;
}

$("#filters").addEventListener("submit", (event) => {
  event.preventDefault(); state.page = 0; showNotice(""); loadItems();
});
$("#previous-page").addEventListener("click", () => {
  if (state.page > 0) { state.page--; loadItems(); }
});
$("#next-page").addEventListener("click", () => {
  if (state.page + 1 < state.totalPages) { state.page++; loadItems(); }
});

async function openEditor(id = null) {
  showNotice("");
  try {
    // Fetch a fresh version instead of editing a potentially stale table row.
    const item = id ? await api(`/items/${id}`) : null;
    if (!state.token) return;
    state.editing = item; itemForm.reset(); showNotice("", false, $("#editor-notice"));
    $("#editor-title").textContent = item ? "Edit item" : "Add item";
    const values = item || { name: "", sku: "", category: "", quantity: 0, reorderLevel: 5, price: "0.00", notes: "" };
    for (const field of ["name", "sku", "category", "quantity", "reorderLevel", "price", "notes"]) {
      itemForm.elements.namedItem(field).value = values[field] ?? "";
    }
    dialog.showModal();
  } catch (error) { showNotice(describeError(error), true); }
}

$("#add-item").addEventListener("click", () => openEditor());
function closeEditor() { if (!$("#save-item").disabled) dialog.close(); }
$("#close-editor").addEventListener("click", closeEditor);
$("#cancel-editor").addEventListener("click", closeEditor);
dialog.addEventListener("cancel", (event) => { if ($("#save-item").disabled) event.preventDefault(); });

itemForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  const data = new FormData(itemForm), editing = state.editing;
  const body = {
    name: String(data.get("name")).trim(), sku: String(data.get("sku")).trim().toUpperCase(),
    category: String(data.get("category")).trim(), quantity: Number(data.get("quantity")),
    reorderLevel: Number(data.get("reorderLevel")),
    // Send decimal text; Jackson parses BigDecimal without JS arithmetic.
    price: String(data.get("price")), notes: String(data.get("notes")).trim()
  };
  if (editing) body.version = editing.version;
  const saveButton = $("#save-item"); saveButton.disabled = true;
  showNotice("", false, $("#editor-notice"));
  try {
    await api(editing ? `/items/${editing.id}` : "/items", { method: editing ? "PUT" : "POST", body });
    dialog.close(); showNotice(editing ? "Item updated." : "Item added."); await loadItems();
  } catch (error) {
    showNotice(describeError(error), true, dialog.open ? $("#editor-notice") : $("#notice"));
  } finally { saveButton.disabled = false; }
});

async function deleteItem(item, button) {
  if (!window.confirm(`Delete "${item.name}"? This cannot be undone.`)) return;
  button.disabled = true; showNotice("");
  try {
    await api(`/items/${item.id}`, { method: "DELETE" }); showNotice("Item deleted."); await loadItems();
  } catch (error) { showNotice(describeError(error), true); }
  finally { button.disabled = false; }
}
setAuthMode("login");

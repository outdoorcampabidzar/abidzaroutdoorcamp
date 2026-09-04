import { supabase, rupiah, esc, message, addCart, getCart, updateCartBadge } from "./app.js";

function availableQuantity(item) {
  return Math.max(
    0,
    Number(
      item.type === "trip"
        ? item.quota
        : (item.item_variants || []).length
          ? (item.item_variants || []).reduce((sum, variant) => sum + Number(variant.stock || 0), 0)
          : item.stock,
    ) || 0,
  );
}

function selectedPrice(item, mode) {
  return Number(item.type === "trip" || mode !== "sale" ? item.price : item.sale_price) || 0;
}

function catalogLabel(item, mode = "rental") {
  if (item.type === "trip") return "Open Trip";
  return mode === "sale" ? "Jual Item" : "Sewa Item";
}

function variantMax(item, variant) {
  if (!variant) return Math.max(0, Number(item.stock) || 0);
  return Math.max(0, Number(variant.stock) || 0);
}

function renderVariantPicker(item) {
  const variants = item.item_variants || [];
  if (!variants.length) return "";
  return `
    <label class="catalog-variant-picker">
      <span>Pilih ukuran / kapasitas</span>
      <select class="input catalog-variant" aria-label="Pilih ukuran atau kapasitas">
        ${variants.map((variant, index) => `
          <option value="${esc(variant.id)}" data-stock="${Number(variant.stock) || 0}" ${index === variants.findIndex((v) => Number(v.stock || 0) > 0) ? "selected" : (variants.every((v) => Number(v.stock || 0) <= 0) && index === 0 ? "selected" : "")}>
            ${esc([variant.name, variant.capacity].filter(Boolean).join(" · "))} — ${Number(variant.stock) || 0} tersedia
          </option>
        `).join("")}
      </select>
    </label>`;
}

function renderCard(item, mode = "rental") {
  const tripDetail = Array.isArray(item.trip_details) ? item.trip_details[0] || {} : item.trip_details || {};
  const available = availableQuantity(item);
  const basePrice = selectedPrice(item, mode);
  const variants = item.item_variants || [];
  const firstVariant = variants[0] || null;
  const maxQuantity = variants.length ? variantMax(item, firstVariant) : Math.max(0, Number(item.stock) || 0);
  const unavailable = available <= 0;
  const availability = item.type === "trip" ? `${available} kursi tersedia` : `${available} unit tersedia`;

  return `
    <article class="card item-card order-item-card catalog-quick-card" data-item-id="${esc(item.id)}">
      <img src="${esc(item.image_url)}" alt="${esc(item.title)}">

      <div class="body">
        <div class="row">
          <span class="badge">${esc(item.item_categories?.name || catalogLabel(item, mode))}</span>
          <span class="${available > 0 ? "stock-available" : "stock-empty"}">
            ${available > 0 ? availability : "Tidak tersedia"}
          </span>
        </div>

        <h3>${esc(item.title)}</h3>
        ${item.is_featured ? '<span class="catalog-featured-badge">★ Unggulan</span>' : ""}
        <p class="muted item-description">
          ${esc((item.description || "").slice(0, 115))}
          ${(item.description || "").length > 115 ? "…" : ""}
        </p>

        ${item.type === "trip" && item.trip_date ? `<p class="catalog-meta">📅 ${new Date(item.trip_date + "T00:00:00").toLocaleDateString("id-ID", { dateStyle: "long" })}</p>` : ""}
        ${item.type === "trip" && tripDetail.status ? `<p class="catalog-meta">🥾 ${esc({ draft: "Draft", open: "Pendaftaran dibuka", full: "Penuh", running: "Sedang berjalan", completed: "Selesai", cancelled: "Dibatalkan" }[tripDetail.status] || tripDetail.status)} · ${esc({ easy: "Mudah", moderate: "Sedang", hard: "Sulit", extreme: "Ekstrem" }[tripDetail.difficulty] || "")}</p>` : ""}
        ${item.location ? `<p class="catalog-meta">📍 ${esc(item.location)}</p>` : ""}
        ${item.requires_guarantee ? `<p class="catalog-meta">🔐 Memerlukan jaminan</p>` : ""}
        ${Number(item.deposit || 0) > 0 ? `<p class="catalog-meta">💳 Deposit ${rupiah(item.deposit)}</p>` : ""}

        ${variants.length ? renderVariantPicker(item) : ""}

        <div class="item-unit-price">
          <span>${item.type === "trip" ? "Harga per peserta" : mode === "sale" ? "Harga jual per unit" : "Harga sewa per unit / hari"}</span>
          <b>${rupiah(basePrice)}</b>
        </div>

        ${item.type === "product" ? `
          <div class="catalog-quick-order">
            <div class="catalog-quick-qty" aria-label="Jumlah">
              <button type="button" class="catalog-qty-minus" aria-label="Kurangi jumlah">−</button>
              <input class="input catalog-qty" type="number" min="1" max="${Math.max(1, maxQuantity)}" value="1" aria-label="Jumlah unit">
              <button type="button" class="catalog-qty-plus" aria-label="Tambah jumlah">+</button>
            </div>
            <button type="button" class="btn catalog-add-btn" ${unavailable || maxQuantity <= 0 ? "disabled" : ""}>
              ${unavailable || maxQuantity <= 0 ? "Stok Habis" : "+ Tambah"}
            </button>
          </div>
          <div class="catalog-added-note" aria-live="polite"></div>
        ` : `
          <div class="actions item-order-actions catalog-detail-action">
            <a class="btn" href="item.html?slug=${encodeURIComponent(item.slug)}&mode=${encodeURIComponent(mode)}">Detail</a>
          </div>
        `}
      </div>
    </article>`;
}

function findVariant(item, card) {
  const select = card.querySelector(".catalog-variant");
  if (!select) return null;
  return (item.item_variants || []).find((variant) => String(variant.id) === String(select.value)) || null;
}

function refreshCardLimit(card, item) {
  const variant = findVariant(item, card);
  const max = variant ? variantMax(item, variant) : Math.max(0, Number(item.stock) || 0);
  const qty = card.querySelector(".catalog-qty");
  const add = card.querySelector(".catalog-add-btn");
  if (!qty || !add) return;
  qty.max = Math.max(1, max);
  qty.value = Math.min(Math.max(1, Number(qty.value) || 1), Math.max(1, max));
  add.disabled = max <= 0;
  add.textContent = max <= 0 ? "Stok Habis" : "+ Tambah";
}

function renderQuickCart(mode) {
  let bar = document.getElementById("catalogQuickCart");
  if (!bar) {
    bar = document.createElement("div");
    bar.id = "catalogQuickCart";
    bar.className = "catalog-quick-cart";
    document.body.appendChild(bar);
  }

  const cart = getCart();
  const relevant = cart.filter((x) => x.type === "product" && x.fulfillment_type === mode);
  const count = relevant.reduce((sum, x) => sum + Number(x.quantity || 0), 0);
  const total = relevant.reduce((sum, x) => sum + Number(x.price || 0) * Number(x.quantity || 0), 0);

  if (!count) {
    bar.classList.add("hidden");
    bar.innerHTML = "";
    return;
  }

  bar.classList.remove("hidden");
  bar.innerHTML = `
    <div class="catalog-quick-cart-info">
      <span class="catalog-quick-cart-icon">🛒</span>
      <div>
        <strong>${count} item di keranjang</strong>
        <small>Subtotal sementara ${rupiah(total)}</small>
      </div>
    </div>
    <a class="btn" href="cart.html">Lihat Keranjang & Checkout →</a>
  `;
}

function bindCatalogEvents(items, grid, mode) {
  grid._catalogItems = items;
  if (grid.dataset.quickBound === "1") return;
  grid.dataset.quickBound = "1";

  grid.addEventListener("click", (event) => {
    const button = event.target.closest("button");
    if (!button) return;
    const card = button.closest(".catalog-quick-card");
    if (!card) return;
    const currentItems = grid._catalogItems || [];
    const item = currentItems.find((entry) => String(entry.id) === String(card.dataset.itemId));
    if (!item) return;

    const qtyInput = card.querySelector(".catalog-qty");
    if (button.classList.contains("catalog-qty-minus")) {
      qtyInput.value = Math.max(1, Number(qtyInput.value || 1) - 1);
      return;
    }
    if (button.classList.contains("catalog-qty-plus")) {
      const variant = findVariant(item, card);
      const max = variant ? variantMax(item, variant) : Math.max(0, Number(item.stock) || 0);
      qtyInput.value = Math.min(max || 1, Number(qtyInput.value || 1) + 1);
      return;
    }
    if (!button.classList.contains("catalog-add-btn")) return;

    const variant = findVariant(item, card);
    const max = variant ? variantMax(item, variant) : Math.max(0, Number(item.stock) || 0);
    const qty = Math.min(max, Math.max(1, Number(qtyInput.value) || 1));
    if (max <= 0) return;

    addCart(item, qty, false, variant, mode, selectedPrice(item, mode));
    updateCartBadge();
    renderQuickCart(mode);

    const note = card.querySelector(".catalog-added-note");
    if (note) {
      note.textContent = `✓ ${qty} ${variant ? variant.name : "unit"} ditambahkan. Silakan pilih item lain.`;
      note.classList.add("show");
      setTimeout(() => note.classList.remove("show"), 2200);
    }
    button.textContent = "✓ Ditambahkan";
    setTimeout(() => {
      if (!button.disabled) button.textContent = "+ Tambah";
    }, 1200);
  });

  grid.addEventListener("change", (event) => {
    const select = event.target.closest(".catalog-variant");
    if (!select) return;
    const card = select.closest(".catalog-quick-card");
    const currentItems = grid._catalogItems || [];
    const item = currentItems.find((entry) => String(entry.id) === String(card?.dataset.itemId));
    if (item) refreshCardLimit(card, item);
  });
}

function renderCategoryQuickChoices(categories, category, draw) {
  const host = document.getElementById("catalogCategoryQuick");
  if (!host) return;
  host.innerHTML = [
    `<button type="button" class="catalog-category-chip active" data-category="">Semua</button>`,
    ...categories.map((entry) => `<button type="button" class="catalog-category-chip" data-category="${esc(entry.slug || entry.name)}">${esc(entry.name)}</button>`),
  ].join("");

  host.querySelectorAll(".catalog-category-chip").forEach((button) => {
    button.addEventListener("click", () => {
      category.value = button.dataset.category || "";
      host.querySelectorAll(".catalog-category-chip").forEach((b) => b.classList.toggle("active", b === button));
      draw();
    });
  });
}

export async function mountCatalog({ type, gridId, messageId, limit = null, mode = type === "trip" ? "trip" : "rental" }) {
  const grid = document.getElementById(gridId);
  const messageElement = document.getElementById(messageId);

  let query = supabase
    .from("items")
    .select("*,item_categories(id,name,slug),item_images(*),item_variants(*),item_price_tiers(*),trip_details(*)")
    .eq("is_active", true)
    .eq("type", type)
    .is("archived_at", null)
    .order("is_featured", { ascending: false })
    .order("sort_order", { ascending: true })
    .order("created_at", { ascending: false });

  if (limit) query = query.limit(limit);

  const { data, error } = await query;
  if (error) {
    if (messageElement) message(messageElement, error.message, "error");
    return;
  }

  let items = data || [];
  if (type === "product") {
    items = items.filter((item) => mode === "sale" ? Boolean(item.sale_enabled) : item.rental_enabled !== false);
  }

  if (!items.length) {
    grid.innerHTML = `<div class="notice">Belum ada ${type === "trip" ? "open trip" : mode === "sale" ? "item jual" : "item sewa"} yang aktif.</div>`;
    return;
  }

  if (type === "product" && document.getElementById("catalogSearch")) {
    mountRentalFilters(items, grid, mode);
    renderQuickCart(mode);
    updateCartBadge();
    return;
  }

  grid.innerHTML = items.map((item) => renderCard(item, mode)).join("");
}

function mountRentalFilters(items, grid, mode = "rental") {
  const search = document.getElementById("catalogSearch");
  const category = document.getElementById("catalogCategory");
  const sort = document.getElementById("catalogSort");
  const availableOnly = document.getElementById("catalogAvailableOnly");
  const reset = document.getElementById("catalogReset");
  const resultCount = document.getElementById("catalogResultCount");

  const categories = [
    ...new Map(
      items.filter((item) => item.item_categories?.name).map((item) => [item.item_categories.slug || item.item_categories.name, item.item_categories]),
    ).values(),
  ].sort((a, b) => a.name.localeCompare(b.name, "id"));

  category.innerHTML = [
    '<option value="">Semua kategori</option>',
    ...categories.map((entry) => `<option value="${esc(entry.slug || entry.name)}">${esc(entry.name)}</option>`),
  ].join("");

  const draw = () => {
    const keyword = search.value.trim().toLocaleLowerCase("id");
    const selectedCategory = category.value;
    let filtered = items.filter((item) => {
      const haystack = [
        item.title,
        item.description,
        item.item_categories?.name,
        ...(item.item_variants || []).map((variant) => variant.name),
      ].filter(Boolean).join(" ").toLocaleLowerCase("id");
      const itemCategory = item.item_categories?.slug || item.item_categories?.name || "";
      return (
        (!keyword || haystack.includes(keyword)) &&
        (!selectedCategory || itemCategory === selectedCategory) &&
        (!availableOnly.checked || availableQuantity(item) > 0)
      );
    });

    filtered = [...filtered].sort((a, b) => {
      if (sort.value === "price-low") return selectedPrice(a, mode) - selectedPrice(b, mode);
      if (sort.value === "price-high") return selectedPrice(b, mode) - selectedPrice(a, mode);
      if (sort.value === "name") return a.title.localeCompare(b.title, "id");
      if (sort.value === "stock") return availableQuantity(b) - availableQuantity(a);
      return Number(Boolean(b.is_featured)) - Number(Boolean(a.is_featured)) || Number(a.sort_order || 0) - Number(b.sort_order || 0);
    });

    resultCount.textContent = `${filtered.length} dari ${items.length} item ditampilkan`;
    grid.innerHTML = filtered.length
      ? filtered.map((item) => renderCard(item, mode)).join("")
      : '<div class="notice catalog-empty-result">Tidak ada item yang sesuai dengan filter. Coba kata kunci atau kategori lain.</div>';
    bindCatalogEvents(filtered, grid, mode);
    renderQuickCart(mode);
  };

  renderCategoryQuickChoices(categories, category, draw);
  search.addEventListener("input", draw);
  category.addEventListener("change", () => {
    document.querySelectorAll("#catalogCategoryQuick .catalog-category-chip").forEach((button) => button.classList.toggle("active", (button.dataset.category || "") === category.value));
    draw();
  });
  sort.addEventListener("change", draw);
  availableOnly.addEventListener("change", draw);
  reset.addEventListener("click", () => {
    search.value = "";
    category.value = "";
    sort.value = "recommended";
    availableOnly.checked = false;
    document.querySelectorAll("#catalogCategoryQuick .catalog-category-chip").forEach((button) => button.classList.toggle("active", !button.dataset.category));
    draw();
    search.focus();
  });

  draw();
}

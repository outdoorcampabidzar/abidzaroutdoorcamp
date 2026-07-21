import { supabase, rupiah, esc, message } from "./app.js";

function availableQuantity(item) {
  return Math.max(
    0,
    Number(
      item.type === "trip"
        ? item.quota
        : (item.item_variants || []).length
          ? (item.item_variants || []).reduce(
              (sum, variant) => sum + Number(variant.stock || 0),
              0,
            )
          : item.stock,
    ) || 0,
  );
}

function catalogLabel(item) {
  return item.type === "trip" ? "Open Trip" : "Sewa Item";
}

function unitLabel(item) {
  return item.type === "trip" ? "peserta" : "unit";
}

function renderCard(item) {
  const tripDetail = Array.isArray(item.trip_details)
    ? item.trip_details[0] || {}
    : item.trip_details || {};
  const available = availableQuantity(item);
  const availability =
    item.type === "trip"
      ? `${available} kursi tersedia`
      : `${available} unit tersedia`;

  return `
    <article class="card item-card order-item-card">
      <img src="${esc(item.image_url)}" alt="${esc(item.title)}">

      <div class="body">
        <div class="row">
          <span class="badge">${esc(item.item_categories?.name || catalogLabel(item))}</span>
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

        ${
          item.type === "trip" && item.trip_date
            ? `<p class="catalog-meta">📅 ${new Date(
                item.trip_date + "T00:00:00",
              ).toLocaleDateString("id-ID", { dateStyle: "long" })}</p>`
            : ""
        }
        ${item.type === "trip" && tripDetail.status ? `<p class="catalog-meta">🥾 ${esc({ draft: "Draft", open: "Pendaftaran dibuka", full: "Penuh", running: "Sedang berjalan", completed: "Selesai", cancelled: "Dibatalkan" }[tripDetail.status] || tripDetail.status)} · ${esc({ easy: "Mudah", moderate: "Sedang", hard: "Sulit", extreme: "Ekstrem" }[tripDetail.difficulty] || "")}</p>` : ""}

        ${
          item.location
            ? `<p class="catalog-meta">📍 ${esc(item.location)}</p>`
            : ""
        }

        ${
          item.requires_guarantee
            ? `<p class="catalog-meta">🔐 Memerlukan jaminan</p>`
            : ""
        }

        ${Number(item.deposit || 0) > 0 ? `<p class="catalog-meta">💳 Deposit ${rupiah(item.deposit)}</p>` : ""}

        ${
          (item.item_variants || []).length
            ? `<p class="catalog-meta">📐 ${(item.item_variants || [])
                .slice(0, 3)
                .map((variant) => esc(variant.name))
                .join(" · ")}</p>`
            : ""
        }

        <div class="item-unit-price">
          <span>${item.type === "trip" ? "Harga per peserta" : "Harga sewa per unit / hari"}</span>
          <b>${rupiah(item.price)}</b>
        </div>

        <div class="actions item-order-actions catalog-detail-action">
          <a class="btn" href="item.html?slug=${encodeURIComponent(item.slug)}">
            Detail
          </a>
        </div>
      </div>
    </article>`;
}

function bindCatalogEvents() {}

export async function mountCatalog({ type, gridId, messageId, limit = null }) {
  const grid = document.getElementById(gridId);
  const messageElement = document.getElementById(messageId);

  let query = supabase
    .from("items")
    .select(
      "*,item_categories(id,name,slug),item_images(*),item_variants(*),item_price_tiers(*),trip_details(*)",
    )
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

  const items = data || [];

  if (!items.length) {
    grid.innerHTML = `
      <div class="notice">
        Belum ada ${type === "trip" ? "open trip" : "item sewa"} yang aktif.
      </div>`;
    return;
  }

  if (type === "product" && document.getElementById("catalogSearch")) {
    mountRentalFilters(items, grid);
    return;
  }

  grid.innerHTML = items.map(renderCard).join("");
  bindCatalogEvents(items, grid);
}

function mountRentalFilters(items, grid) {
  const search = document.getElementById("catalogSearch");
  const category = document.getElementById("catalogCategory");
  const sort = document.getElementById("catalogSort");
  const availableOnly = document.getElementById("catalogAvailableOnly");
  const reset = document.getElementById("catalogReset");
  const resultCount = document.getElementById("catalogResultCount");

  const categories = [
    ...new Map(
      items
        .filter((item) => item.item_categories?.name)
        .map((item) => [
          item.item_categories.slug || item.item_categories.name,
          item.item_categories,
        ]),
    ).values(),
  ].sort((a, b) => a.name.localeCompare(b.name, "id"));

  category.innerHTML = [
    '<option value="">Semua kategori</option>',
    ...categories.map(
      (entry) =>
        `<option value="${esc(entry.slug || entry.name)}">${esc(entry.name)}</option>`,
    ),
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
      ]
        .filter(Boolean)
        .join(" ")
        .toLocaleLowerCase("id");
      const itemCategory =
        item.item_categories?.slug || item.item_categories?.name || "";
      return (
        (!keyword || haystack.includes(keyword)) &&
        (!selectedCategory || itemCategory === selectedCategory) &&
        (!availableOnly.checked || availableQuantity(item) > 0)
      );
    });

    filtered = [...filtered].sort((a, b) => {
      if (sort.value === "price-low") return Number(a.price) - Number(b.price);
      if (sort.value === "price-high") return Number(b.price) - Number(a.price);
      if (sort.value === "name") return a.title.localeCompare(b.title, "id");
      if (sort.value === "stock")
        return availableQuantity(b) - availableQuantity(a);
      return (
        Number(Boolean(b.is_featured)) - Number(Boolean(a.is_featured)) ||
        Number(a.sort_order || 0) - Number(b.sort_order || 0)
      );
    });

    resultCount.textContent = `${filtered.length} dari ${items.length} item ditampilkan`;
    grid.innerHTML = filtered.length
      ? filtered.map(renderCard).join("")
      : '<div class="notice catalog-empty-result">Tidak ada item yang sesuai dengan filter. Coba kata kunci atau kategori lain.</div>';
    bindCatalogEvents(filtered, grid);
  };

  search.addEventListener("input", draw);
  category.addEventListener("change", draw);
  sort.addEventListener("change", draw);
  availableOnly.addEventListener("change", draw);
  reset.addEventListener("click", () => {
    search.value = "";
    category.value = "";
    sort.value = "recommended";
    availableOnly.checked = false;
    draw();
    search.focus();
  });

  draw();
}

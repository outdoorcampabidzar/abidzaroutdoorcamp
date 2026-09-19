
      import {
        supabase,
        rupiah,
        esc,
        message,
        DEFAULT_SITE_SETTINGS,
        loadSiteSettings,
        applySiteSettings,
      } from "./app.js?v=202609172030";

      const root = document.getElementById("adminRoot");

      const statusLabels = {
        pending: "Menunggu",
        confirmed: "Dikonfirmasi",
        paid: "Dibayar",
        completed: "Selesai",
        returned: "Dikembalikan",
        cancelled: "Dibatalkan",
      };

      let activeTab = "rental";
      let items = [];
      let categories = [];
      let orders = [];
      let administrators = [];
      let currentAdminUserId = null;
      let editingItem = null;
      let editingVoucher = null;
      let editingShopReward = null;
      let vouchers = [];
      let voucherUsages = [];
      let orderSearch = "";
      let orderStatusFilter = "all";
      let orderDateFrom = "";
      let orderDateTo = "";
      let customers = [];
      let adminRatings = [];
      let customerNotifications = [];
      let currentStaffRole = "user";
      let currentPermissions = new Set();
      let itemsLoaded = false;
      let ordersLoaded = false;
      let categoriesLoaded = false;
      let siteSettingsLoaded = false;
      let administratorsLoaded = false;
      let itemsLoadPromise = null;
      let ordersLoadPromise = null;
      let categoriesLoadPromise = null;
      let administratorsLoadPromise = null;
      let renderRequestId = 0;

      function withTimeout(promise, ms, label = "Operasi Supabase") {
        return Promise.race([
          promise,
          new Promise((_, reject) =>
            setTimeout(
              () => reject(new Error(`${label} timeout setelah ${Math.round(ms / 1000)} detik.`)),
              ms,
            ),
          ),
        ]);
      }

      function can(permission) {
        return (
          currentPermissions.has("*") || currentPermissions.has(permission)
        );
      }

      function firstAllowedAdminTab() {
        if (can("catalog.manage")) return "rental";
        if (can("orders.view")) return "orders";
        if (can("vouchers.manage")) return "vouchers";
        if (can("coinshop.manage")) return "shop";
        if (can("settings.manage")) return "settings";
        if (can("finance.manage")) return "payment_logs";
        if (can("customers.view")) return "customers";
        if (can("reviews.manage")) return "reviews";
        if (can("notifications.manage")) return "notifications";
        return "administrators";
      }
      let siteSettings = { ...DEFAULT_SITE_SETTINGS };

      function slugify(value) {
        return String(value || "")
          .toLowerCase()
          .trim()
          .replace(/[^a-z0-9\s-]/g, "")
          .replace(/\s+/g, "-")
          .replace(/-+/g, "-")
          .replace(/^-|-$/g, "");
      }

      function rentalItems() {
        return items.filter((item) => item.type === "product");
      }

      function tripItems() {
        return items.filter((item) => item.type === "trip");
      }

      function getCachedAuthSession() {
        try {
          // Supabase menyimpan sesi dengan key sb-<project-ref>-auth-token.
          // Jangan mengunci project pada satu key karena versi/library auth dapat berubah.
          for (let i = 0; i < localStorage.length; i += 1) {
            const key = localStorage.key(i) || "";
            if (!key.includes("-auth-token")) continue;
            const raw = localStorage.getItem(key);
            if (!raw) continue;
            const parsed = JSON.parse(raw);
            const session = parsed?.currentSession || parsed;
            const user = session?.user || parsed?.user || null;
            if (user?.id) return { session, user };
          }
        } catch (error) {
          console.warn("Gagal membaca sesi lokal:", error);
        }
        return { session: null, user: null };
      }

      async function verifyAdmin() {
        // Jangan membuat Admin Panel menggantung di getUser().
        // Ambil sesi lokal terlebih dahulu; Supabase akan tetap memvalidasi akses
        // pada query/RPC berikutnya.
        let { user } = getCachedAuthSession();

        if (!user) {
          try {
            const sessionResult = await withTimeout(
              supabase.auth.getSession(),
              1800,
              "Membaca sesi login",
            );
            user = sessionResult?.data?.session?.user || null;
          } catch (error) {
            console.warn("Pembacaan sesi Supabase gagal/timeout:", error);
          }
        }

        if (!user?.id) {
          location.href = "login.html?next=admin.html";
          return false;
        }

        currentAdminUserId = user.id;

        // Verifikasi kode login harus tercatat di server sebelum Admin Panel dibuka.
        // Frontend/localStorage tidak dianggap sebagai bukti keamanan.
        try {
          const securityResult = await withTimeout(
            supabase.rpc("admin_security_check"),
            2500,
            "Pemeriksaan verifikasi keamanan admin",
          );
          if (securityResult?.error) throw securityResult.error;
          if (securityResult?.data !== true) {
            root.innerHTML = `
              <section class="container section">
                <div class="notice error">
                  <b>🔐 Verifikasi keamanan admin diperlukan.</b><br><br>
                  Sesi login ditemukan, tetapi kode 6 digit belum diverifikasi atau sudah kedaluwarsa.
                  Silakan login ulang untuk mendapatkan kode baru.<br><br>
                  <a class="btn primary" href="login.html?next=admin.html">Login + Verifikasi Kode</a>
                </div>
              </section>`;
            return false;
          }
        } catch (error) {
          console.warn("Verifikasi keamanan admin gagal:", error);
          root.innerHTML = `
            <section class="container section">
              <div class="notice error">
                <b>🔐 Keamanan Admin belum dapat diverifikasi.</b><br><br>
                Jalankan patch <b>PATCH-AUTH-LOGIN-DAN-AKTIVASI-KODE-6-DIGIT.sql</b>, lalu login ulang.<br><br>
                <small>${esc(error?.message || "RPC admin_security_check tidak tersedia.")}</small>
              </div>
            </section>`;
          return false;
        }

        // access-security.sql menggunakan role super_admin, bukan lagi "admin".
        // Cek profile dengan timeout pendek, lalu fallback ke RPC permission.
        let profileRole = "user";
        try {
          const profileResult = await withTimeout(
            supabase
              .from("profiles")
              .select("role")
              .eq("id", user.id)
              .maybeSingle(),
            2500,
            "Pemeriksaan role admin",
          );
          profileRole = String(profileResult?.data?.role || "user").toLowerCase();
        } catch (error) {
          console.warn("Pemeriksaan profile gagal/timeout:", error);
        }

        if (["admin", "super_admin"].includes(profileRole)) {
          currentStaffRole = profileRole;
          currentPermissions = new Set(["*"]);
          return true;
        }

        try {
          const permissionResult = await withTimeout(
            supabase.rpc("get_my_staff_permissions"),
            3000,
            "Pemeriksaan permission admin",
          );
          const access = permissionResult?.data;
          currentStaffRole = String(access?.role || profileRole || "user");
          currentPermissions = new Set(Array.isArray(access?.permissions) ? access.permissions : []);
        } catch (error) {
          console.warn("Pemeriksaan permission gagal/timeout:", error);
          currentStaffRole = profileRole;
          currentPermissions = new Set();
        }

        const allowed = currentPermissions.size > 0;

        if (!allowed) {
          root.innerHTML = `
          <section class="container section">
            <div class="notice error">
              <b>Akses Admin tidak terverifikasi.</b><br><br>
              Sesi login ditemukan, tetapi hak akses admin belum dapat diverifikasi.
              Pastikan role akun pada tabel <b>profiles</b> adalah <b>super_admin</b>
              atau role staff memiliki permission yang sesuai.<br><br>
              <button class="btn primary" type="button" onclick="location.reload()">↻ Coba Lagi</button>
              <a class="btn" href="login.html?next=admin.html">Login Ulang</a>
            </div>
          </section>`;
        }

        return allowed;
      }

      async function loadItemsData() {
        if (itemsLoaded) return;
        if (itemsLoadPromise) return itemsLoadPromise;

        itemsLoadPromise = (async () => {
          const [itemResult, categoryResult] = await Promise.all([
            supabase
              .from("items")
              .select(
                "*,item_categories(id,name,slug),item_images(*),item_variants(*),inventory_units(*),item_price_tiers(*),trip_details(*)",
              )
              .is("archived_at", null)
              .order("is_featured", { ascending: false })
              .order("sort_order", { ascending: true })
              .order("created_at", { ascending: false }),
            supabase.from("item_categories").select("*").order("sort_order"),
          ]);

          if (itemResult.error) throw itemResult.error;
          if (categoryResult.error) throw categoryResult.error;

          items = itemResult.data || [];
          categories = categoryResult.data || [];
          itemsLoaded = true;
          categoriesLoaded = true;
        })();

        try {
          await itemsLoadPromise;
        } finally {
          itemsLoadPromise = null;
        }
      }

      async function loadOrdersData() {
        if (ordersLoaded) return;
        if (ordersLoadPromise) return ordersLoadPromise;

        ordersLoadPromise = (async () => {
          let { data, error } = await supabase
            .from("orders")
            .select(
              "*,order_items(*),payment_transactions(*),order_status_history(*),order_refunds(*),order_returns(*)",
            )
            .order("created_at", { ascending: false });

          if (
            error &&
            String(error.message || "").includes("order_status_history")
          ) {
            const fallback = await supabase
              .from("orders")
              .select("*,order_items(*),payment_transactions(*)")
              .order("created_at", { ascending: false });
            data = fallback.data;
            error = fallback.error;
          }

          if (error) throw error;
          orders = data || [];

          // Tampilkan nama toko/daerah, bukan UUID location_id.
          // Contoh: "Daerah X". Ambil daftar lokasi sekali saat order dimuat.
          const locationIds = [...new Set(orders.map(o => o.location_id).filter(Boolean).map(String))];
          if (locationIds.length) {
            const { data: locationRows, error: locationError } = await supabase
              .from("aoc_locations")
              .select("id,name")
              .in("id", locationIds);
            if (!locationError) {
              const locationMap = new Map((locationRows || []).map(loc => [String(loc.id), String(loc.name || "").trim()]));
              orders = orders.map(o => ({
                ...o,
                location_name: locationMap.get(String(o.location_id)) || "Belum dipilih"
              }));
            } else {
              orders = orders.map(o => ({ ...o, location_name: "Belum dipilih" }));
            }
          } else {
            orders = orders.map(o => ({ ...o, location_name: "Belum dipilih" }));
          }
          ordersLoaded = true;
        })();

        try {
          await ordersLoadPromise;
        } finally {
          ordersLoadPromise = null;
        }
      }

      async function loadSettingsData() {
        if (siteSettingsLoaded) return;
        siteSettings = { ...DEFAULT_SITE_SETTINGS, ...(await loadSiteSettings()) };
        siteSettingsLoaded = true;
      }

      async function loadAdministratorsData() {
        if (administratorsLoaded || !can("*")) return;
        if (administratorsLoadPromise) return administratorsLoadPromise;

        administratorsLoadPromise = (async () => {
          const { data, error } = await supabase.rpc("secure_list_staff_users");
          if (error) throw error;
          administrators = data || [];
          administratorsLoaded = true;
        })();

        try {
          await administratorsLoadPromise;
        } finally {
          administratorsLoadPromise = null;
        }
      }

      async function ensureAdminDataForTab(tab) {
        if (["rental", "trips", "locations"].includes(tab)) {
          await loadItemsData();
          return;
        }
        if (["rental_orders", "rental_returns", "orders", "schedule"].includes(tab)) {
          await loadOrdersData();
          return;
        }
        if (tab === "customers") {
          await loadOrdersData();
          return;
        }
        if (tab === "settings") {
          await loadSettingsData();
          return;
        }
        if (tab === "administrators") {
          await loadAdministratorsData();
        }
      }

      function renderShell() {
        root.innerHTML = `
        <section class="container admin-page">
          <header class="admin-page-heading">
            <div>
              <h2>Admin Panel</h2>
              <p class="muted">
              Kelola katalog, pesanan, dan hak akses administrator.
              </p>
            </div>

            <div class="admin-stat-pills">
              <span>${rentalItems().length} item sewa</span>
              <span>${tripItems().length} open trip</span>
              <span>${orders.length} pesanan</span>
              <span>${Math.max(administrators.length, 1)} admin</span>
            </div>
          </header>

          <nav class="admin-section-tabs" aria-label="Menu admin">
            <button
              class="admin-tab ${activeTab === "rental" ? "active" : ""} ${can("catalog.manage") ? "" : "hidden"}"
              data-admin-tab="rental"
              type="button"
            >
              🎒 Sewa Item
            </button>

            <button
              class="admin-tab ${activeTab === "rental_orders" ? "active" : ""} ${can("orders.view") ? "" : "hidden"}"
              data-admin-tab="rental_orders"
              type="button"
            >
              🧾 Pesanan Sewa
            </button>

            <button
              class="admin-tab ${activeTab === "rental_returns" ? "active" : ""} ${can("orders.view") ? "" : "hidden"}"
              data-admin-tab="rental_returns"
              type="button"
            >
              📦 Pengembalian Barang
            </button>

            <button
              class="admin-tab admin-reminder-tab ${activeTab === "rental_reminders" ? "active" : ""}"
              data-admin-tab="rental_reminders"
              type="button"
              title="Buka Pengingat Customer"
            >
              🔔 Pengingat Customer
            </button>

            <button
              class="admin-tab ${activeTab === "locations" ? "active" : ""} ${can("catalog.manage") ? "" : "hidden"}"
              data-admin-tab="locations"
              type="button"
            >
              📍 Stok Lokasi
            </button>

            <button
              class="admin-tab ${activeTab === "trips" ? "active" : ""} ${can("catalog.manage") ? "" : "hidden"}"
              data-admin-tab="trips"
              type="button"
            >
              🏔️ Open Trip
            </button>

            <button
              class="admin-tab ${activeTab === "orders" ? "active" : ""} ${can("orders.view") ? "" : "hidden"}"
              data-admin-tab="orders"
              type="button"
            >
              🧾 Pesanan
            </button>

            <button
              class="admin-tab ${activeTab === "vouchers" ? "active" : ""} ${can("vouchers.manage") ? "" : "hidden"}"
              data-admin-tab="vouchers"
              type="button"
            >
              🎟️ Voucher
            </button>

            <button
              class="admin-tab ${activeTab === "shop" ? "active" : ""} ${can("coinshop.manage") ? "" : "hidden"}"
              data-admin-tab="shop"
              type="button"
            >
              🪙 Coin Shop
            </button>

            <button
              class="admin-tab ${activeTab === "settings" ? "active" : ""} ${can("settings.manage") ? "" : "hidden"}"
              data-admin-tab="settings"
              type="button"
            >
              ⚙️ Pengaturan
            </button>

            <button
              class="admin-tab ${activeTab === "schedule" ? "active" : ""} ${can("orders.view") || can("warehouse.manage") ? "" : "hidden"}"
              data-admin-tab="schedule"
              type="button"
            >
              📅 Jadwal Sewa
            </button>

            <button
              class="admin-tab ${activeTab === "payment_logs" ? "active" : ""} ${can("finance.manage") ? "" : "hidden"}"
              data-admin-tab="payment_logs"
              type="button"
            >
              🔔 Log Pembayaran
            </button>

            <button
              class="admin-tab ${activeTab === "customers" ? "active" : ""} ${can("customers.view") ? "" : "hidden"}"
              data-admin-tab="customers"
              type="button"
            >
              👤 Pelanggan
            </button>

            <button
              class="admin-tab ${activeTab === "reviews" ? "active" : ""} ${can("reviews.manage") ? "" : "hidden"}"
              data-admin-tab="reviews"
              type="button"
            >
              ⭐ Ulasan
            </button>

            <button
              class="admin-tab ${activeTab === "notifications" ? "active" : ""} ${can("notifications.manage") ? "" : "hidden"}"
              data-admin-tab="notifications"
              type="button"
            >
              📣 Notifikasi
            </button>

            <button
              class="admin-tab ${activeTab === "administrators" ? "active" : ""} ${can("*") ? "" : "hidden"}"
              data-admin-tab="administrators"
              type="button"
            >
              👥 Administrator
            </button>
            <button class="admin-tab ${activeTab === "activity_logs" ? "active" : ""} ${can("*") ? "" : "hidden"}" data-admin-tab="activity_logs" type="button">🛡️ Log Aktivitas</button>
          </nav>

          <div id="adminMessage" class="notice hidden"></div>
          <div class="admin-reminder-shortcut">
            <button class="btn primary admin-reminder-open" data-admin-tab="rental_reminders" type="button">🔔 Buka Pengingat Customer</button>
          </div>
          <section id="adminContent"></section>
        </section>`;

        document.querySelectorAll("[data-admin-tab]").forEach((button) => {
          button.addEventListener("click", () => {
            activeTab = button.dataset.adminTab;
            editingItem = null;
            editingVoucher = null;
            editingShopReward = null;
            renderShell();
          });
        });

        renderActiveTab();
      }

      let aocSelectedLocationId = null;
      let aocSelectedStockCategoryId = "all";

      async function renderLocationsTab() {
        const content = document.getElementById("adminContent");
        content.innerHTML = '<div class="notice">Memuat lokasi dan stok...</div>';

        const [{ data: locations, error: le }, { data: rows, error: se }] = await Promise.all([
          supabase.from("aoc_locations").select("*").order("sort_order"),
          supabase.from("item_location_stock").select("*,aoc_locations(id,code,name),items(id,title),item_variants(id,name,capacity)").order("updated_at", { ascending: false })
        ]);

        if (le || se) {
          content.innerHTML = `<div class="notice error">${esc((le || se).message)}</div>`;
          return;
        }

        const locationList = locations || [];
        if (!aocSelectedLocationId || !locationList.some(l => String(l.id) === String(aocSelectedLocationId))) {
          aocSelectedLocationId = locationList.find(l => l.is_active !== false)?.id || locationList[0]?.id || null;
        }

        const selectedLocation = locationList.find(l => String(l.id) === String(aocSelectedLocationId)) || locationList[0];
        const products = rentalItems();
        const stockMap = new Map((rows || []).map(r => [`${r.item_id}|${r.variant_id || ""}|${r.location_id}`, r]));
        const stockValue = (item, variant, locationId) => {
          const row = stockMap.get(`${item.id}|${variant?.id || ""}|${locationId}`);
          return Number(row?.stock || 0);
        };

        content.innerHTML = `
          <section class="card aoc-stock-dashboard">
            <div class="aoc-stock-top">
              <div class="aoc-stock-title">
                <span class="aoc-stock-icon">📦</span>
                <div>
                  <h3>Stok Toko</h3>
                  <p>Pilih toko, lalu atur jumlah stok.</p>
                </div>
              </div>
              <button class="btn small" type="button" id="aocAddLocationBtn">＋ Toko</button>
            </div>

            <label class="aoc-store-select">
              <span>Lokasi</span>
              <select class="input" id="aocLocationSelect">
                ${locationList.map(l => `<option value="${esc(l.id)}" ${String(l.id) === String(selectedLocation?.id) ? "selected" : ""}>${esc(l.name)}${l.is_active === false ? " — Nonaktif" : ""}</option>`).join("")}
              </select>
            </label>

            ${selectedLocation ? `
              <div class="aoc-store-bar">
                <div>
                  <strong>${esc(selectedLocation.name)}</strong>
                  <small>${esc(selectedLocation.code)}${selectedLocation.is_active === false ? " · Nonaktif" : " · Aktif"}</small>
                </div>
                <div class="aoc-store-actions">
                  <button class="btn tiny" type="button" data-rename-location="${esc(selectedLocation.id)}">Rename</button>
                  <button class="btn tiny" type="button" data-toggle-location="${esc(selectedLocation.id)}" data-active="${selectedLocation.is_active ? "1" : "0"}">${selectedLocation.is_active ? "Nonaktifkan" : "Aktifkan"}</button>
                </div>
              </div>` : `<div class="notice">Belum ada toko.</div>`}

            <div id="aocLocationForm" class="aoc-location-admin-form" hidden>
              <div class="aoc-location-admin-grid">
                <label class="field"><span>Nama Toko</span><input class="input" id="aocLocationName" placeholder="Contoh: Toko 3" maxlength="80"></label>
                <label class="field"><span>Kode</span><input class="input" id="aocLocationCode" placeholder="TOKO3" maxlength="30" autocapitalize="characters"></label>
                <label class="field aoc-location-admin-address"><span>Alamat (opsional)</span><input class="input" id="aocLocationAddress" placeholder="Alamat toko" maxlength="200"></label>
              </div>
              <div class="aoc-location-admin-actions">
                <button class="btn" type="button" id="aocCancelLocationBtn">Batal</button>
                <button class="btn primary" type="button" id="aocSaveLocationBtn">Simpan Toko</button>
              </div>
            </div>
          </section>

          ${selectedLocation ? `
          <section class="card aoc-stock-list-card">
            <div class="aoc-stock-list-head">
              <div>
                <h3>Daftar Item</h3>
                <p>${products.length} item · stok khusus ${esc(selectedLocation.name)}</p>
              </div>
              <div class="aoc-stock-filters">
                <div class="aoc-stock-category-wrap">
                  <label class="sr-only" for="aocStockCategory">Kategori item</label>
                  <select class="input aoc-stock-category-filter" id="aocStockCategory">
                    <option value="all" ${aocSelectedStockCategoryId === "all" ? "selected" : ""}>Semua Kategori</option>
                    <option value="__none__" ${aocSelectedStockCategoryId === "__none__" ? "selected" : ""}>Tanpa Kategori</option>
                    ${(categories || []).map(c => `<option value="${esc(c.id)}" ${String(aocSelectedStockCategoryId) === String(c.id) ? "selected" : ""}>${esc(c.name)}</option>`).join("")}
                  </select>
                </div>
                <div class="aoc-stock-search-wrap">
                  <input class="input aoc-stock-search" id="aocStockSearch" type="search" placeholder="Cari item..." autocomplete="off">
                </div>
              </div>
            </div>
            <div class="aoc-stock-list">
              ${products.flatMap(item => {
                const vars = item.item_variants?.filter(v => v.is_active) || [];
                return (vars.length ? vars.map(v => [item, v]) : [[item, null]]).map(([it, v]) => {
                  const categoryId = it.item_categories?.id || it.category_id || "";
                  const categoryName = it.item_categories?.name || "Tanpa Kategori";
                  const menuImage = it.image_url || (it.item_images || []).slice().sort((a,b) => Number(a.sort_order || 0) - Number(b.sort_order || 0))[0]?.image_url || "";
                  const searchText = `${it.title} ${categoryName} ${v ? [v.name, v.capacity].filter(Boolean).join(" ") : "Stok utama"}`.toLowerCase();
                  return `
                  <div class="aoc-stock-card" data-stock-card data-search="${esc(searchText)}" data-category-id="${esc(categoryId)}">
                    <div class="aoc-stock-card-main">
                      <div class="aoc-stock-thumb ${menuImage ? "" : "is-fallback"}">
                        ${menuImage ? `<img src="${esc(menuImage)}" alt="${esc(it.title)}" loading="lazy" onerror="this.closest('.aoc-stock-thumb').classList.add('is-fallback');this.remove();">` : ""}
                        <span class="aoc-stock-thumb-fallback">${esc((it.title || "I").trim().charAt(0).toUpperCase())}</span>
                      </div>
                      <div class="aoc-stock-name">
                        <div class="aoc-stock-name-row"><strong>${esc(it.title)}</strong><span class="aoc-stock-category">${esc(categoryName)}</span></div>
                        <span>${esc(v ? [v.name, v.capacity].filter(Boolean).join(" · ") : "Stok utama")}</span>
                      </div>
                    </div>
                    <div class="aoc-stock-control">
                      <button class="aoc-stock-step" type="button" data-stock-minus aria-label="Kurangi stok">−</button>
                      <input class="input aoc-stock-number" type="number" min="0" value="${stockValue(it, v, selectedLocation.id)}" data-simple-stock data-item-id="${esc(it.id)}" data-variant-id="${esc(v?.id || "")}" data-location-id="${esc(selectedLocation.id)}" aria-label="Stok ${esc(it.title)}">
                      <button class="aoc-stock-step" type="button" data-stock-plus aria-label="Tambah stok">+</button>
                      <button class="btn primary aoc-stock-save" type="button" data-save-simple-stock data-item-id="${esc(it.id)}" data-variant-id="${esc(v?.id || "")}" data-location-id="${esc(selectedLocation.id)}">Simpan</button>
                    </div>
                  </div>`;
                });
              }).join("") || `<div class="notice">Belum ada item sewa.</div>`}
              <div class="aoc-stock-empty" id="aocStockEmpty" hidden>Tidak ada item yang cocok.</div>
            </div>
          </section>` : ""}`;
        const select = content.querySelector("#aocLocationSelect");
        select?.addEventListener("change", () => {
          aocSelectedLocationId = select.value;
          renderLocationsTab();
        });

        const addBtn = content.querySelector("#aocAddLocationBtn");
        const form = content.querySelector("#aocLocationForm");
        const nameInput = content.querySelector("#aocLocationName");
        const codeInput = content.querySelector("#aocLocationCode");
        const addressInput = content.querySelector("#aocLocationAddress");
        addBtn?.addEventListener("click", () => {
          if (!form) return;
          form.hidden = !form.hidden;
          if (!form.hidden) nameInput?.focus();
        });
        content.querySelector("#aocCancelLocationBtn")?.addEventListener("click", () => {
          form.hidden = true;
          if (nameInput) nameInput.value = "";
          if (codeInput) { codeInput.value = ""; delete codeInput.dataset.manual; }
          if (addressInput) addressInput.value = "";
        });
        nameInput?.addEventListener("input", () => {
          if (!codeInput?.dataset.manual) {
            const n = slugify(nameInput.value).replace(/-/g, "_").toUpperCase();
            codeInput.value = n || "TOKO";
          }
        });
        codeInput?.addEventListener("input", () => {
          codeInput.dataset.manual = "1";
          codeInput.value = codeInput.value.toUpperCase().replace(/[^A-Z0-9_-]/g, "");
        });
        content.querySelector("#aocSaveLocationBtn")?.addEventListener("click", async (ev) => {
          const btn = ev.currentTarget;
          const name = String(nameInput?.value || "").trim();
          const code = String(codeInput?.value || "").trim().toUpperCase();
          const address = String(addressInput?.value || "").trim() || null;
          if (!name || !code) { showAdminMessage("Nama toko dan kode wajib diisi.", "error"); return; }
          btn.disabled = true;
          try {
            const exists = await supabase.from("aoc_locations").select("id").eq("code", code).maybeSingle();
            if (exists.error) throw exists.error;
            if (exists.data) throw new Error("Kode toko sudah digunakan. Gunakan kode lain.");
            const nextSort = Math.max(0, ...locationList.map(x => Number(x.sort_order) || 0)) + 1;
            const ins = await supabase.from("aoc_locations").insert({ code, name, address, is_active: true, sort_order: nextSort }).select("id").single();
            if (ins.error) throw ins.error;
            aocSelectedLocationId = ins.data.id;
            showAdminMessage(`${name} berhasil ditambahkan.`, "success");
            await renderLocationsTab();
          } catch (e) {
            showAdminMessage(e.message || "Gagal menambahkan toko.", "error");
          } finally { btn.disabled = false; }
        });

        content.querySelectorAll("[data-rename-location]").forEach(btn => btn.addEventListener("click", async () => {
          const id = btn.dataset.renameLocation;
          const loc = locationList.find(x => String(x.id) === String(id));
          if (!loc) return;
          const name = window.prompt("Nama toko baru:", String(loc.name || ""));
          if (name === null) return;
          const cleanName = name.trim();
          if (!cleanName) { showAdminMessage("Nama toko tidak boleh kosong.", "error"); return; }
          const address = window.prompt("Alamat toko (opsional):", String(loc.address || ""));
          if (address === null) return;
          btn.disabled = true;
          try {
            const r = await supabase.from("aoc_locations").update({ name: cleanName, address: address.trim() || null }).eq("id", id);
            if (r.error) throw r.error;
            showAdminMessage(`${cleanName} berhasil diperbarui.`, "success");
            await renderLocationsTab();
          } catch (e) { showAdminMessage(e.message || "Gagal mengubah toko.", "error"); }
          finally { btn.disabled = false; }
        }));

        content.querySelectorAll("[data-toggle-location]").forEach(btn => btn.addEventListener("click", async () => {
          const id = btn.dataset.toggleLocation;
          const active = btn.dataset.active === "1";
          if (locationList.length <= 1 && active) { showAdminMessage("Minimal harus ada 1 toko aktif.", "error"); return; }
          btn.disabled = true;
          try {
            const r = await supabase.from("aoc_locations").update({ is_active: !active }).eq("id", id);
            if (r.error) throw r.error;
            showAdminMessage(!active ? "Toko diaktifkan." : "Toko dinonaktifkan.", "success");
            await renderLocationsTab();
          } catch (e) { showAdminMessage(e.message || "Gagal mengubah status toko.", "error"); }
          finally { btn.disabled = false; }
        }));

        const stockSearch = content.querySelector("#aocStockSearch");
        const stockCategory = content.querySelector("#aocStockCategory");
        const stockEmpty = content.querySelector("#aocStockEmpty");
        const filterStock = () => {
          const q = String(stockSearch?.value || "").trim().toLowerCase();
          const category = String(stockCategory?.value || "all");
          let shown = 0;
          content.querySelectorAll("[data-stock-card]").forEach(card => {
            const matchesSearch = !q || String(card.dataset.search || "").includes(q);
            const cardCategory = String(card.dataset.categoryId || "");
            const matchesCategory = category === "all" || (category === "__none__" ? !cardCategory : cardCategory === category);
            const ok = matchesSearch && matchesCategory;
            card.hidden = !ok;
            if (ok) shown++;
          });
          if (stockEmpty) stockEmpty.hidden = shown !== 0;
        };
        stockSearch?.addEventListener("input", filterStock);
        stockCategory?.addEventListener("change", () => {
          aocSelectedStockCategoryId = stockCategory.value || "all";
          filterStock();
        });
        filterStock();

        content.querySelectorAll("[data-stock-card]").forEach(card => {
          const input = card.querySelector("[data-simple-stock]");
          card.querySelector("[data-stock-minus]")?.addEventListener("click", () => {
            if (!input) return;
            input.value = Math.max(0, (Number(input.value) || 0) - 1);
            input.dispatchEvent(new Event("input", { bubbles: true }));
          });
          card.querySelector("[data-stock-plus]")?.addEventListener("click", () => {
            if (!input) return;
            input.value = Math.max(0, (Number(input.value) || 0) + 1);
            input.dispatchEvent(new Event("input", { bubbles: true }));
          });
        });

        content.querySelectorAll("[data-save-simple-stock]").forEach(btn => btn.addEventListener("click", async () => {
          const input = content.querySelector(`[data-simple-stock][data-item-id="${btn.dataset.itemId}"][data-variant-id="${btn.dataset.variantId}"][data-location-id="${btn.dataset.locationId}"]`);
          if (!input) return;
          btn.disabled = true;
          try {
            const r = await supabase.rpc("aoc_set_location_stock", {
              p_item_id: btn.dataset.itemId,
              p_variant_id: btn.dataset.variantId || null,
              p_location_id: btn.dataset.locationId,
              p_stock: Math.max(0, Number(input.value) || 0)
            });
            if (r.error) throw r.error;
            await refreshItems();
            showAdminMessage("Stok berhasil disimpan.", "success");
          } catch (e) {
            showAdminMessage(e.message || "Gagal menyimpan stok.", "error");
          } finally { btn.disabled = false; }
        }));
      }

      async function renderActiveTab() {
        const tab = activeTab;
        const requestId = ++renderRequestId;
        const content = document.getElementById("adminContent");
        if (!content) return;

        content.innerHTML = '<div class="notice">Memuat data menu...</div>';

        try {
          await ensureAdminDataForTab(tab);
          if (requestId !== renderRequestId || tab !== activeTab) return;

          if (tab === "locations") await renderLocationsTab();
          else if (tab === "rental") renderRentalTab();
          else if (tab === "rental_orders") renderRentalOrdersTab();
          else if (tab === "rental_returns") renderRentalReturnsTab();
          else if (tab === "rental_reminders") renderRentalRemindersTab();
          else if (tab === "trips") renderTripTab();
          else if (tab === "orders") renderOrdersTab();
          else if (tab === "vouchers") await renderVoucherTab();
          else if (tab === "shop") await renderShopTab();
          else if (tab === "settings") renderSettingsTab();
          else if (tab === "schedule") renderRentalScheduleTab();
          else if (tab === "payment_logs") await renderPaymentLogsTab();
          else if (tab === "customers") await renderCustomersTab();
          else if (tab === "reviews") await renderReviewsTab();
          else if (tab === "notifications") await renderNotificationsTab();
          else if (tab === "activity_logs") await renderActivityLogsTab();
          else await renderAdministratorsTab();
        } catch (error) {
          if (requestId !== renderRequestId || tab !== activeTab) return;
          content.innerHTML = `<div class="notice error">${esc(error?.message || "Gagal memuat data menu.")}</div>`;
        }
      }

      function voucherDateInput(value) {
        if (!value) return "";
        const date = new Date(value);
        const local = new Date(
          date.getTime() - date.getTimezoneOffset() * 60000,
        );
        return local.toISOString().slice(0, 16);
      }

      function voucherScopeLabel(value) {
        return (
          {
            all: "Semua sewa & trip",
            rental: "Semua item sewa",
            trip: "Semua open trip",
            products: "Produk tertentu",
          }[value] || value
        );
      }

      async function loadVoucherData() {
        const [voucherResult, usageResult] = await Promise.all([
          supabase
            .from("vouchers")
            .select("*,voucher_items(item_id)")
            .order("created_at", { ascending: false }),
          supabase
            .from("voucher_usages")
            .select("*,orders(order_number,customer_name,customer_email)")
            .order("used_at", { ascending: false })
            .limit(100),
        ]);
        if (voucherResult.error) throw voucherResult.error;
        if (usageResult.error) throw usageResult.error;
        vouchers = voucherResult.data || [];
        voucherUsages = usageResult.data || [];
      }

      async function renderVoucherTab() {
        const content = document.getElementById("adminContent");
        content.innerHTML = '<div class="notice">Memuat voucher...</div>';
        try {
          await loadVoucherData();
        } catch (error) {
          content.innerHTML = `<div class="notice error">${esc(error.message)}<br><small>Jalankan voucher-management.sql melalui Supabase SQL Editor.</small></div>`;
          return;
        }

        const voucher = editingVoucher || {
          code: "",
          discount_type: "percent",
          discount_value: 10,
          min_purchase: 0,
          max_discount: null,
          quota: 100,
          starts_at: new Date().toISOString(),
          expires_at: new Date(Date.now() + 30 * 86400000).toISOString(),
          once_per_customer: false,
          applies_to: "all",
          is_active: true,
          voucher_items: [],
        };
        const selectedItems = new Set(
          (voucher.voucher_items || []).map((entry) => entry.item_id),
        );

        content.innerHTML = `
        <div class="admin-voucher-layout">
          <section class="card admin-editor-card">
            <div class="admin-editor-heading">
              <div><span class="badge">Voucher</span><h3>${editingVoucher ? "Edit Voucher" : "Tambah Voucher"}</h3></div>
              ${editingVoucher ? '<button id="cancelVoucherEdit" class="btn secondary small" type="button">Batal</button>' : ""}
            </div>
            <form id="voucherForm" class="form">
              <label class="field"><span>Kode voucher *</span>
                <input class="input" name="code" required maxlength="40" value="${esc(voucher.code)}" placeholder="HEMAT10">
              </label>
              <div class="two">
                <label class="field"><span>Jenis potongan</span>
                  <select class="input" name="discount_type">
                    <option value="percent" ${voucher.discount_type === "percent" ? "selected" : ""}>Persentase (%)</option>
                    <option value="fixed" ${voucher.discount_type === "fixed" ? "selected" : ""}>Nominal (Rp)</option>
                  </select>
                </label>
                <label class="field"><span>Nilai potongan *</span><input class="input" name="discount_value" type="number" min="1" step="1" required value="${Number(voucher.discount_value)}"></label>
                <label class="field"><span>Minimum transaksi</span><input class="input" name="min_purchase" type="number" min="0" step="1000" value="${Number(voucher.min_purchase || 0)}"></label>
                <label class="field"><span>Maksimum potongan</span><input class="input" name="max_discount" type="number" min="0" step="1000" value="${voucher.max_discount ?? ""}" placeholder="Kosong = tanpa batas"></label>
                <label class="field"><span>Kuota penggunaan</span><input class="input" name="quota" type="number" min="0" step="1" value="${Number(voucher.quota || 0)}"></label>
                <label class="field"><span>Rarity Gacha</span>
                  <select class="input" name="gacha_rarity">
                    ${[["common","Common"],["uncommon","Uncommon"],["rare","Rare"],["epic","Epic"],["legendary","Legendary"]].map(([value,label]) => `<option value="${value}" ${(voucher.gacha_rarity || "common") === value ? "selected" : ""}>${label}</option>`).join("")}
                  </select>
                </label>
                <label class="field"><span>Probabilitas Gacha (%)</span><input class="input" name="gacha_probability" type="number" min="0" max="100" step="0.01" value="${Number(voucher.gacha_probability ?? ({common:60,uncommon:25,rare:10,epic:4,legendary:1}[voucher.gacha_rarity || "common"] || 60))}"><small class="muted">Bobot per voucher. Contoh: Common 60, Legendary 1.</small></label>
                <label class="field"><span>Berlaku untuk</span>
                  <select id="voucherAppliesTo" class="input" name="applies_to">
                    ${[
                      ["all", "Semua sewa & trip"],
                      ["rental", "Semua item sewa"],
                      ["trip", "Semua open trip"],
                      ["products", "Produk tertentu"],
                    ]
                      .map(
                        ([value, label]) =>
                          `<option value="${value}" ${voucher.applies_to === value ? "selected" : ""}>${label}</option>`,
                      )
                      .join("")}
                  </select>
                </label>
                <label class="field"><span>Tanggal mulai *</span><input class="input" name="starts_at" type="datetime-local" required value="${voucherDateInput(voucher.starts_at)}"></label>
                <label class="field"><span>Tanggal berakhir *</span><input class="input" name="expires_at" type="datetime-local" required value="${voucherDateInput(voucher.expires_at)}"></label>
              </div>
              <div id="voucherProductScope" class="voucher-product-scope ${voucher.applies_to === "products" ? "" : "hidden"}">
                <span class="field-label">Pilih produk yang menerima voucher</span>
                <div class="voucher-item-options">
                  ${items.map((item) => `<label class="admin-check"><input type="checkbox" name="item_ids" value="${item.id}" ${selectedItems.has(item.id) ? "checked" : ""}><span>${esc(item.title)} <small>(${item.type === "trip" ? "Trip" : "Sewa"})</small></span></label>`).join("")}
                </div>
              </div>
              <label class="admin-check"><input name="once_per_customer" type="checkbox" ${voucher.once_per_customer ? "checked" : ""}><span>Maksimal satu kali per pelanggan</span></label>
              <label class="admin-check"><input name="is_active" type="checkbox" ${voucher.is_active ? "checked" : ""}><span>Voucher aktif</span></label>
              <button id="saveVoucherButton" class="btn" type="submit">${editingVoucher ? "Simpan Perubahan" : "Tambah Voucher"}</button>
            </form>
          </section>

          <section class="card voucher-list-panel">
            <div class="admin-list-heading"><div><h3>Daftar Voucher</h3><p class="muted">${vouchers.length} voucher tersimpan.</p></div></div>
            <div class="voucher-admin-list">
              ${
                vouchers
                  .map(
                    (entry) => `
                <article class="card voucher-admin-card">
                  <div class="voucher-admin-head"><div><span class="${entry.is_active ? "admin-active" : "admin-inactive"}">${entry.is_active ? "Aktif" : "Nonaktif"}</span><h3>${esc(entry.code)}</h3></div><strong>${entry.discount_type === "percent" ? `${Number(entry.discount_value)}%` : rupiah(entry.discount_value)}</strong></div>
                  <p class="muted">${esc(voucherScopeLabel(entry.applies_to))} · ${esc(entry.gacha_rarity || "common")} · Bobot ${Number(entry.gacha_probability ?? 1)}% · Minimal ${rupiah(entry.min_purchase)} · Terpakai ${Number(entry.used_count)}/${Number(entry.quota)}</p>
                  <small>${new Date(entry.starts_at).toLocaleString("id-ID")} – ${new Date(entry.expires_at).toLocaleString("id-ID")}</small>
                  <div class="actions"><button class="btn secondary small" data-edit-voucher="${entry.id}" type="button">Edit</button><button class="btn secondary small" data-toggle-voucher="${entry.id}" type="button">${entry.is_active ? "Nonaktifkan" : "Aktifkan"}</button><button class="btn danger small" data-delete-voucher="${entry.id}" type="button">Hapus</button></div>
                </article>`,
                  )
                  .join("") || '<div class="notice">Belum ada voucher.</div>'
              }
            </div>
          </section>

          <section class="card voucher-history-card">
          <div class="admin-list-heading"><div><h3>Riwayat Pemakaian</h3><p class="muted">100 pemakaian terbaru.</p></div></div>
          <div class="voucher-history-list">
            ${voucherUsages.map((usage) => `<div class="voucher-history-row"><div><b>${esc(usage.voucher_code)}</b><span>${esc(usage.orders?.order_number || "-")} · ${esc(usage.orders?.customer_name || usage.orders?.customer_email || "-")}</span></div><strong>-${rupiah(usage.discount)}</strong><span class="${usage.status === "used" ? "admin-active" : "admin-inactive"}">${usage.status === "used" ? "Dipakai" : "Dikembalikan"}</span><small>${new Date(usage.used_at).toLocaleString("id-ID")}</small></div>`).join("") || '<div class="notice">Belum ada pemakaian voucher.</div>'}
          </div>
          </section>
        </div>`;

        document
          .getElementById("voucherAppliesTo")
          .addEventListener("change", (event) => {
            document
              .getElementById("voucherProductScope")
              .classList.toggle("hidden", event.target.value !== "products");
          });
        document
          .getElementById("voucherForm")
          .addEventListener("submit", saveVoucher);
        document
          .getElementById("cancelVoucherEdit")
          ?.addEventListener("click", () => {
            editingVoucher = null;
            renderVoucherTab();
          });
        document.querySelectorAll("[data-edit-voucher]").forEach((button) =>
          button.addEventListener("click", () => {
            editingVoucher = vouchers.find(
              (entry) => entry.id === button.dataset.editVoucher,
            );
            renderVoucherTab();
          }),
        );
        document
          .querySelectorAll("[data-toggle-voucher]")
          .forEach((button) =>
            button.addEventListener("click", () =>
              toggleVoucher(button.dataset.toggleVoucher),
            ),
          );
        document
          .querySelectorAll("[data-delete-voucher]")
          .forEach((button) =>
            button.addEventListener("click", () =>
              deleteVoucher(button.dataset.deleteVoucher),
            ),
          );
      }

      async function saveVoucher(event) {
        event.preventDefault();
        const form = event.currentTarget;
        const values = Object.fromEntries(new FormData(form));
        const itemIds = new FormData(form).getAll("item_ids");
        const payload = {
          code: String(values.code || "")
            .trim()
            .toUpperCase(),
          discount_type: values.discount_type,
          discount_value: Number(values.discount_value),
          min_purchase: Number(values.min_purchase || 0),
          max_discount:
            values.max_discount === "" ? null : Number(values.max_discount),
          quota: Number(values.quota || 0),
          gacha_rarity: values.gacha_rarity || "common",
          gacha_probability: Number(values.gacha_probability ?? 1),
          starts_at: new Date(values.starts_at).toISOString(),
          expires_at: new Date(values.expires_at).toISOString(),
          applies_to: values.applies_to,
          once_per_customer: form.elements.once_per_customer.checked,
          is_active: form.elements.is_active.checked,
        };
        if (!Number.isFinite(payload.gacha_probability) || payload.gacha_probability < 0 || payload.gacha_probability > 100)
          return showAdminMessage("Probabilitas Gacha harus 0–100%.", "error");
        if (payload.discount_type === "percent" && payload.discount_value > 100)
          return showAdminMessage(
            "Potongan persentase maksimal 100%.",
            "error",
          );
        if (new Date(payload.expires_at) <= new Date(payload.starts_at))
          return showAdminMessage(
            "Tanggal berakhir harus setelah tanggal mulai.",
            "error",
          );
        if (payload.applies_to === "products" && !itemIds.length)
          return showAdminMessage("Pilih minimal satu produk.", "error");

        const result = editingVoucher
          ? await supabase
              .from("vouchers")
              .update(payload)
              .eq("id", editingVoucher.id)
              .select("id")
              .single()
          : await supabase
              .from("vouchers")
              .insert(payload)
              .select("id")
              .single();
        if (result.error)
          return showAdminMessage(result.error.message, "error");
        const voucherId = result.data.id;
        const { error: deleteError } = await supabase
          .from("voucher_items")
          .delete()
          .eq("voucher_id", voucherId);
        if (deleteError) return showAdminMessage(deleteError.message, "error");
        if (payload.applies_to === "products") {
          const { error } = await supabase.from("voucher_items").insert(
            itemIds.map((itemId) => ({
              voucher_id: voucherId,
              item_id: itemId,
            })),
          );
          if (error) return showAdminMessage(error.message, "error");
        }
        editingVoucher = null;
        await renderVoucherTab();
        showAdminMessage("Voucher berhasil disimpan.", "success");
      }

      async function toggleVoucher(id) {
        const voucher = vouchers.find((entry) => entry.id === id);
        const { error } = await supabase
          .from("vouchers")
          .update({ is_active: !voucher.is_active })
          .eq("id", id);
        if (error) return showAdminMessage(error.message, "error");
        await renderVoucherTab();
      }

      async function deleteVoucher(id) {
        if (
          !confirm(
            "Hapus voucher ini? Voucher yang sudah memiliki riwayat mungkin tidak dapat dihapus.",
          )
        )
          return;
        const { error } = await supabase.from("vouchers").delete().eq("id", id);
        if (error) return showAdminMessage(error.message, "error");
        await renderVoucherTab();
        showAdminMessage("Voucher berhasil dihapus.", "success");
      }


      async function renderShopTab() {
        const content = document.getElementById("adminContent");
        content.innerHTML = '<div class="notice">Memuat Coin Shop...</div>';
        const [{ data: rewards, error: rewardError }, { data: setting }] = await Promise.all([
          supabase.from("shop_rewards").select("*").order("created_at", { ascending: false }),
          supabase.from("coin_settings").select("*").eq("id", true).maybeSingle(),
        ]);
        if (rewardError) {
          content.innerHTML = `<div class="notice error">${esc(rewardError.message)}<br><small>Jalankan coin-shop.sql melalui Supabase SQL Editor.</small></div>`;
          return;
        }
        const reward = editingShopReward || {
          title: "", description: "", image_url: "", coin_cost: 10,
          reward_type: "voucher_random", is_active: true, stock: 0
        };
        content.innerHTML = `
          <div class="admin-voucher-layout">
            <section class="card admin-editor-card">
              <div class="admin-editor-heading">
                <div><span class="badge">Coin Shop</span><h3>${editingShopReward ? "Edit Hadiah" : "Tambah Hadiah"}</h3></div>
                ${editingShopReward ? '<button id="cancelShopEdit" class="btn secondary small" type="button">Batal</button>' : ""}
              </div>
              <p class="muted">Hadiah berupa <b>Voucher Gacha</b>. Setiap voucher memiliki <b>rarity + bobot probabilitas</b> sendiri. Contoh awal: Common 60%, Uncommon 25%, Rare 100%, Epic 4%, Legendary 1%. Nilai ini dapat diubah pada menu Voucher.</p>
              <form id="shopRewardForm" class="form">
                <label class="field"><span>Nama hadiah *</span><input class="input" name="title" required maxlength="100" value="${esc(reward.title)}" placeholder="Voucher Random Hemat"></label>
                <label class="field"><span>Deskripsi</span><textarea class="input" name="description" rows="3" placeholder="Tukar coin untuk mendapatkan voucher acak">${esc(reward.description || "")}</textarea></label>
                <div class="two">
                  <label class="field"><span>Harga coin *</span><input class="input" name="coin_cost" type="number" min="1" step="1" required value="${Number(reward.coin_cost || 1)}"></label>
                  <label class="field"><span>Stok hadiah</span><input class="input" name="stock" type="number" min="0" step="1" value="${Number(reward.stock || 0)}"><small class="muted">0 = tidak terbatas</small></label>
                </div>
                <label class="field"><span>Jenis reward</span><select class="input" name="reward_type" disabled><option value="voucher_random">Voucher Random</option></select></label>
                <label class="check"><input type="checkbox" name="is_active" ${reward.is_active ? "checked" : ""}> Tampilkan hadiah di shop</label>
                <button class="btn" type="submit">${editingShopReward ? "Simpan Perubahan" : "Tambah ke Shop"}</button>
              </form>
            </section>
            <section class="card">
              <div class="admin-list-heading"><div><span class="badge">Reward</span><h3>Menu Coin Shop</h3><p class="muted">${(rewards || []).length} hadiah · 0 stok berarti unlimited.</p></div></div>
              <div class="admin-voucher-list">
                ${(rewards || []).map(r => `
                  <article class="admin-voucher-card">
                    <div>
                      <strong>${esc(r.title)}</strong>
                      <p class="muted">${esc(r.description || "Voucher Random")} · <b>${Number(r.coin_cost)} coin</b></p>
                      <small>${r.is_active ? "Aktif" : "Nonaktif"} · ${Number(r.stock) === 0 ? "Unlimited" : `Stok ${Number(r.stock)}`}</small>
                    </div>
                    <div class="admin-actions">
                      <button class="btn secondary small" data-shop-edit="${r.id}" type="button">Edit</button>
                      <button class="btn secondary small" data-shop-toggle="${r.id}" type="button">${r.is_active ? "Nonaktifkan" : "Aktifkan"}</button>
                      <button class="btn danger small" data-shop-delete="${r.id}" type="button">Hapus</button>
                    </div>
                  </article>`).join("") || '<div class="notice">Belum ada hadiah.</div>'}
              </div>
            </section>
          </div>
          <section class="card" style="margin-top:16px">
            <div class="admin-list-heading"><div><span class="badge">Coin</span><h3>Perhitungan Coin Otomatis</h3>
              <p class="muted">Nilai 1 coin = <b>Rp1.000</b>. Untuk setiap transaksi <b>SEWA atau JUAL</b> yang berhasil, sistem memilih <b>persentase reward secara acak</b> dari batas yang Anda tentukan. Open Trip tidak menghasilkan coin.</p>
              <div class="two" style="margin-top:12px">
                <label class="field"><span>Persentase minimum (%)</span><input id="coinMinPercent" class="input" type="number" min="0" max="100" step="1" value="${Number(setting?.coin_min_percent ?? 10)}"></label>
                <label class="field"><span>Persentase maksimum (%)</span><input id="coinMaxPercent" class="input" type="number" min="0" max="100" step="1" value="${Number(setting?.coin_max_percent ?? 100)}"></label>
              </div>
              <p class="muted">Contoh default <b>100%–100%</b>: transaksi Rp100.000 dapat menghasilkan reward acak Rp10.000–Rp100.000, yaitu sekitar <b>10–100 coin</b>. Hasil random dibuat di database.</p></div></div>
            <div class="notice">🪙 <b>1 coin = Rp1.000</b> · Reward acak: <b>${Number(setting?.coin_min_percent ?? 10)}%–${Number(setting?.coin_max_percent ?? 100)}%</b></div>
            <div style="margin-top:12px"><button id="saveCoinSettings" class="btn" type="button">Simpan Pengaturan Coin</button></div>
          </section>`;

        document.getElementById("saveCoinSettings")?.addEventListener("click", async () => {
          const min = Number(document.getElementById("coinMinPercent")?.value);
          const max = Number(document.getElementById("coinMaxPercent")?.value);
          if (!Number.isFinite(min) || !Number.isFinite(max) || min < 0 || max < min || max > 100) {
            return showAdminMessage("Persentase harus 0–100 dan maksimum tidak boleh lebih kecil dari minimum.", "error");
          }
          const { error } = await supabase.from("coin_settings").upsert({ id: true, coin_value_rupiah: 1000, coin_min_percent: min, coin_max_percent: max, updated_at: new Date().toISOString() });
          if (error) return showAdminMessage(error.message, "error");
          showAdminMessage(`Pengaturan reward coin disimpan: ${min}%–${max}%.`, "success");
          await renderShopTab();
        });

        document.getElementById("shopRewardForm").addEventListener("submit", async e => {
          e.preventDefault();
          const v = Object.fromEntries(new FormData(e.target));
          const payload = {
            title: String(v.title || "").trim(),
            description: String(v.description || "").trim() || null,
            image_url: null,
            coin_cost: Math.max(1, Number(v.coin_cost) || 1),
            reward_type: "voucher_random",
            stock: Math.max(0, Number(v.stock) || 0),
            is_active: e.target.is_active.checked,
            updated_at: new Date().toISOString()
          };
          if (!payload.title) return showAdminMessage("Nama hadiah wajib diisi.", "error");
          const result = editingShopReward
            ? await supabase.from("shop_rewards").update(payload).eq("id", editingShopReward.id)
            : await supabase.from("shop_rewards").insert(payload);
          if (result.error) return showAdminMessage(result.error.message, "error");
          editingShopReward = null;
          await renderShopTab();
          showAdminMessage("Hadiah Coin Shop berhasil disimpan.", "success");
        });

        document.getElementById("cancelShopEdit")?.addEventListener("click", async () => {
          editingShopReward = null; await renderShopTab();
        });
        document.querySelectorAll("[data-shop-edit]").forEach(btn => btn.addEventListener("click", async () => {
          editingShopReward = (rewards || []).find(r => r.id === btn.dataset.shopEdit) || null;
          await renderShopTab();
        }));
        document.querySelectorAll("[data-shop-toggle]").forEach(btn => btn.addEventListener("click", async () => {
          const r = (rewards || []).find(x => x.id === btn.dataset.shopToggle);
          if (!r) return;
          const { error } = await supabase.from("shop_rewards").update({ is_active: !r.is_active, updated_at: new Date().toISOString() }).eq("id", r.id);
          if (error) return showAdminMessage(error.message, "error");
          await renderShopTab();
        }));
        document.querySelectorAll("[data-shop-delete]").forEach(btn => btn.addEventListener("click", async () => {
          if (!confirm("Hapus hadiah Coin Shop ini?")) return;
          const { error } = await supabase.from("shop_rewards").delete().eq("id", btn.dataset.shopDelete);
          if (error) return showAdminMessage(error.message, "error");
          await renderShopTab();
          showAdminMessage("Hadiah dihapus.", "success");
        }));
      }

      async function renderPaymentLogsTab() {
        const content = document.getElementById("adminContent");
        content.innerHTML =
          '<div class="notice">Memuat log callback BTZPay...</div>';
        const { data, error } = await supabase
          .from("payment_webhook_logs")
          .select("*")
          .order("created_at", { ascending: false })
          .limit(100);
        if (error) {
          content.innerHTML = `<div class="notice error">${esc(error.message)}<br><small>Jalankan btzpay-payment.sql terlebih dahulu.</small></div>`;
          return;
        }
        content.innerHTML = `
        <div class="admin-list-heading"><div><h3>Riwayat Callback BTZPay</h3>
        <p class="muted">100 callback terbaru untuk pemeriksaan transaksi.</p></div></div>
        <div class="payment-log-list">
          ${
            (data || [])
              .map(
                (log) => `
            <details class="card payment-log-card">
              <summary><span class="${log.verified ? "admin-active" : "admin-inactive"}">${log.verified ? "Terverifikasi" : "Ditolak"}</span>
              <b>${esc(log.gateway_transaction_id || "Tanpa ID")}</b>
              <span>${esc(log.event_status || "-")}</span>
              <small>${new Date(log.created_at).toLocaleString("id-ID")}</small></summary>
              <pre>${esc(JSON.stringify(log.payload, null, 2))}</pre>
              ${log.error_message ? `<div class="notice error">${esc(log.error_message)}</div>` : ""}
            </details>`,
              )
              .join("") || '<div class="notice">Belum ada callback.</div>'
          }
        </div>`;
      }

      function formatRentalDate(value) {
        if (!value) return "-";
        return new Date(
          `${String(value).slice(0, 10)}T00:00:00`,
        ).toLocaleDateString("id-ID", { dateStyle: "long" });
      }

      function renderRentalScheduleTab() {
        const content = document.getElementById("adminContent");
        const rentals = orders
          .filter(
            (order) =>
              order.rental_start &&
              ["pending", "confirmed", "paid"].includes(order.status),
          )
          .sort((a, b) =>
            String(a.rental_start).localeCompare(String(b.rental_start)),
          );

        content.innerHTML = `
        <div class="admin-list-heading">
          <div>
            <h3>Kalender Penyewaan</h3>
            <p class="muted">${rentals.length} pesanan sewa aktif atau menunggu.</p>
          </div>
          <button id="refreshRentalSchedule" class="btn secondary small" type="button">Muat Ulang</button>
        </div>
        <div class="rental-calendar-list">
          ${
            rentals
              .map(
                (order) => `
            <article class="card rental-calendar-card">
              <div class="rental-calendar-date">
                <small>${esc(formatRentalDate(order.rental_start))}</small>
                <strong>→</strong>
                <small>${esc(formatRentalDate(order.rental_end))}</small>
                <span class="badge">${Number(order.rental_days || 1)} hari</span>
              </div>
              <div class="rental-calendar-order">
                <div>
                  <span class="status">${statusLabels[order.status] || esc(order.status)}</span>
                  <h3>${esc(order.order_number)}</h3>
                  <p class="muted">${esc(order.customer_name)} · ${esc(order.phone)}</p>
                </div>
                <strong>${rupiah(order.total)}</strong>
              </div>
              <div class="rental-calendar-items">
                ${
                  (order.order_items || [])
                    .filter((item) => item.item_type === "product")
                    .map(
                      (item) =>
                        `<span>${esc(item.title_snapshot)} × ${Number(item.quantity)}</span>`,
                    )
                    .join("") ||
                  '<span class="muted">Tidak ada item sewa.</span>'
                }
              </div>
              <button class="btn secondary small" data-open-schedule-order="${order.id}" type="button">Buka di Pesanan</button>
            </article>
          `,
              )
              .join("") ||
            '<div class="notice">Belum ada jadwal penyewaan.</div>'
          }
        </div>`;

        document
          .getElementById("refreshRentalSchedule")
          .addEventListener("click", refreshRentalSchedule);
        document
          .querySelectorAll("[data-open-schedule-order]")
          .forEach((button) => {
            button.addEventListener("click", () => {
              activeTab = "orders";
              renderShell();
              const detail = document.querySelector(
                `[data-order-id="${button.dataset.openScheduleOrder}"]`,
              );
              if (detail) {
                detail.open = true;
                detail.scrollIntoView({ behavior: "smooth", block: "center" });
              }
            });
          });
      }

      async function refreshRentalSchedule() {
        ordersLoaded = false;
        ordersLoadPromise = null;
        try {
          await loadOrdersData();
          renderRentalScheduleTab();
          showAdminMessage("Jadwal penyewaan dimuat ulang.", "success");
        } catch (error) {
          showAdminMessage(error?.message || "Gagal memuat jadwal.", "error");
        }
      }

      function settingInput(name, label, options = {}) {
        const value = siteSettings[name] ?? "";
        const type = options.type || "text";
        const hint = options.hint
          ? `<small class="muted">${esc(options.hint)}</small>`
          : "";

        if (type === "textarea") {
          return `
          <label class="field ${options.wide ? "admin-setting-wide" : ""}">
            <span>${esc(label)}</span>
            <textarea class="input" name="${esc(name)}" rows="${options.rows || 3}" maxlength="${options.maxlength || 1000}">${esc(value)}</textarea>
            ${hint}
          </label>`;
        }

        return `
        <label class="field ${options.wide ? "admin-setting-wide" : ""}">
          <span>${esc(label)}</span>
          <input
            class="input"
            name="${esc(name)}"
            type="${esc(type)}"
            value="${esc(value)}"
            ${options.required ? "required" : ""}
            ${options.min !== undefined ? `min="${esc(options.min)}"` : ""}
            ${options.max !== undefined ? `max="${esc(options.max)}"` : ""}
            maxlength="${options.maxlength || 255}"
          >
          ${hint}
        </label>`;
      }

      function renderSettingsTab() {
        const content = document.getElementById("adminContent");

        content.innerHTML = `
        <form id="siteSettingsForm" class="form admin-settings-form">
          <div class="admin-list-heading">
            <div>
              <h3>Pengaturan Website</h3>
              <p class="muted">Perubahan yang disimpan langsung digunakan pada halaman website.</p>
            </div>
            <button id="saveSiteSettings" class="btn" type="submit">Simpan Pengaturan</button>
          </div>

          <section class="card admin-settings-section">
            <div class="admin-editor-heading">
              <div><span class="badge">Logo Header</span><h3>Logo Website</h3></div>
            </div>
            <div class="site-logo-manager">
              <div class="site-logo-preview-wrap">
                <div class="site-logo-preview ${siteSettings.site_logo_url ? "has-logo" : ""}" id="siteLogoPreview">
                  ${siteSettings.site_logo_url ? `<img src="${esc(siteSettings.site_logo_url)}" alt="Preview logo" loading="lazy">` : `<span>AOC</span>`}
                </div>
              </div>
              <div class="site-logo-controls">
                <label class="field">
                  <span>Upload logo header</span>
                  <input class="input" id="siteLogoFile" type="file" accept="image/png,image/jpeg,image/webp,image/svg+xml">
                  <small class="muted">PNG/JPG/WebP/SVG, maksimal 2 MB. Logo akan tampil otomatis di header seluruh halaman.</small>
                </label>
                <input type="hidden" name="site_logo_url" id="siteLogoUrl" value="${esc(siteSettings.site_logo_url || "")}">
                <div class="actions site-logo-actions">
                  <button class="btn secondary small" id="uploadSiteLogo" type="button">Upload Logo</button>
                  <button class="btn danger small ${siteSettings.site_logo_url ? "" : "hidden"}" id="removeSiteLogo" type="button">Hapus Logo</button>
                </div>
                <div id="siteLogoUploadStatus" class="muted" aria-live="polite"></div>
              </div>
            </div>
          </section>

          <section class="card admin-settings-section">
            <div class="admin-editor-heading">
              <div><span class="badge">Identitas</span><h3>Brand dan Kontak</h3></div>
            </div>
            <div class="two admin-settings-grid">
              ${settingInput("site_name", "Nama website *", { required: true })}
              ${settingInput("whatsapp_number", "Nomor WhatsApp *", {
                required: true,
                hint: "Gunakan format internasional tanpa tanda +, contoh 62812...",
              })}
              ${settingInput("address", "Alamat toko", { type: "textarea", wide: true })}
              ${settingInput("business_hours", "Jam operasional")}
              ${settingInput("google_maps_url", "Tautan Google Maps", { type: "url" })}
              ${settingInput("instagram_url", "Tautan Instagram", { type: "url" })}
              ${settingInput("tiktok_url", "Tautan TikTok", { type: "url" })}
              ${settingInput("whatsapp_message", "Pesan awal WhatsApp", {
                type: "textarea",
                wide: true,
                maxlength: 500,
              })}
              ${settingInput("admin_1_name", "Nama Admin 1")}
              ${settingInput("admin_1_whatsapp", "WhatsApp Admin 1", { hint: "Format internasional, contoh 62812..." })}
              ${settingInput("admin_2_name", "Nama Admin 2")}
              ${settingInput("admin_2_whatsapp", "WhatsApp Admin 2", { hint: "Boleh dikosongkan jika tidak digunakan." })}
              ${settingInput("admin_3_name", "Nama Admin 3")}
              ${settingInput("admin_3_whatsapp", "WhatsApp Admin 3", { hint: "Boleh dikosongkan jika tidak digunakan." })}
            </div>
          </section>

          <section class="card admin-settings-section">
            <div class="admin-editor-heading">
              <div><span class="badge">Beranda</span><h3>Hero Halaman Utama</h3></div>
            </div>
            <div class="two admin-settings-grid">
              ${settingInput("hero_eyebrow", "Teks kecil")}
              ${settingInput("hero_title", "Judul utama")}
              ${settingInput("hero_subtitle", "Judul lanjutan")}
              ${settingInput("hero_description", "Deskripsi", {
                type: "textarea",
                wide: true,
                maxlength: 700,
              })}
            </div>
          </section>

          <section class="card admin-settings-section">
            <div class="admin-editor-heading">
              <div><span class="badge">Pencarian</span><h3>SEO</h3></div>
            </div>
            <div class="two admin-settings-grid">
              ${settingInput("seo_title", "Judul SEO", { maxlength: 70 })}
              ${settingInput("seo_description", "Deskripsi SEO", {
                type: "textarea",
                wide: true,
                maxlength: 170,
                rows: 2,
              })}
            </div>
          </section>

          <section class="card admin-settings-section">
            <div class="admin-editor-heading">
              <div><span class="badge">Operasional</span><h3>Aturan Penyewaan</h3></div>
            </div>
            <div class="two admin-settings-grid">
              ${settingInput("rental_min_days", "Minimal sewa (hari)", { type: "number", min: 1, max: 365 })}
              ${settingInput("rental_max_days", "Maksimal sewa (hari)", { type: "number", min: 1, max: 365 })}
              ${settingInput("late_fee_text", "Ketentuan keterlambatan", { type: "textarea", wide: true })}
              ${settingInput("guarantee_policy", "Ketentuan jaminan", { type: "textarea", wide: true })}
              ${settingInput("cancellation_policy", "Kebijakan pembatalan", { type: "textarea", wide: true })}
              ${settingInput("refund_policy", "Kebijakan pengembalian dana", { type: "textarea", wide: true })}
            </div>
          </section>

          <section class="card admin-settings-section">
            <div class="admin-editor-heading">
              <div><span class="badge">BTZPay</span><h3>Pembayaran Otomatis</h3></div>
            </div>
            <label class="admin-check">
              <input name="payment_enabled" type="checkbox" ${siteSettings.payment_enabled ? "checked" : ""}>
              <span>Aktifkan pembayaran otomatis BTZPay</span>
            </label>
            <div class="two admin-settings-grid">
              <label class="field">
                <span>Metode pembayaran — Mode Sewa</span>
                <select class="input" name="payment_method_rental">
                  ${[
                    ["qrisorkut", "QRIS Orkut"],
                    ["qrisdana", "QRIS Dana"],
                    ["qrisgopay", "QRIS GoPay"],
                    ["qrisshopeepay", "QRIS ShopeePay"],
                  ]
                    .map(
                      ([value, label]) =>
                        `<option value="${value}" ${siteSettings.payment_method_rental === value ? "selected" : ""}>${label}</option>`,
                    )
                    .join("")}
                </select>
              </label>
              <label class="field">
                <span>Metode pembayaran — Mode Jual</span>
                <select class="input" name="payment_method_sale">
                  ${[
                    ["qrisorkut", "QRIS Orkut"],
                    ["qrisdana", "QRIS Dana"],
                    ["qrisgopay", "QRIS GoPay"],
                    ["qrisshopeepay", "QRIS ShopeePay"],
                  ]
                    .map(
                      ([value, label]) =>
                        `<option value="${value}" ${siteSettings.payment_method_sale === value ? "selected" : ""}>${label}</option>`,
                    )
                    .join("")}
                </select>
              </label>
              ${settingInput("payment_timeout_minutes", "Batas pembayaran (menit)", { type: "number", min: 5, max: 60, hint: "BTZPay menerima maksimal 60 menit." })}
            </div>
            <div class="notice warning">
              Gateway dapat dipisahkan per mode. Untuk benar-benar memakai gateway/API key berbeda, gunakan secret Edge Function <b>BTZPAY_API_KEY_RENTAL</b> untuk Sewa dan <b>BTZPAY_API_KEY_SALE</b> untuk Jual. Jika tidak diisi, keduanya memakai <b>BTZPAY_API_KEY</b>.
            </div>
          </section>

          <section class="card admin-settings-section">
            <div class="admin-editor-heading">
              <div><span class="badge">Status</span><h3>Mode Perawatan</h3></div>
            </div>
            <label class="admin-check">
              <input name="maintenance_mode" type="checkbox" ${siteSettings.maintenance_mode ? "checked" : ""}>
              <span>Aktifkan mode perawatan</span>
            </label>
            ${settingInput("maintenance_message", "Pesan perawatan", {
              type: "textarea",
              wide: true,
              maxlength: 500,
            })}
            <p class="muted">Pengaturan ini sudah disimpan sebagai fondasi. Tampilan halaman perawatan penuh dapat diaktifkan pada tahap berikutnya.</p>
          </section>

          <div class="actions admin-settings-actions">
            <button class="btn" type="submit">Simpan Pengaturan</button>
            <button id="resetSiteSettings" class="btn secondary" type="button">Kembalikan Isian Bawaan</button>
          </div>
        </form>`;

        document
          .getElementById("siteSettingsForm")
          .addEventListener("submit", saveSiteSettings);
        document.getElementById("uploadSiteLogo")?.addEventListener("click", uploadSiteLogo);
        document.getElementById("removeSiteLogo")?.addEventListener("click", removeSiteLogo);
        document
          .getElementById("resetSiteSettings")
          .addEventListener("click", () => {
            if (
              !confirm(
                "Kembalikan seluruh isian ke nilai bawaan? Perubahan belum disimpan sampai tombol Simpan ditekan.",
              )
            )
              return;
            siteSettings = { ...DEFAULT_SITE_SETTINGS };
            renderSettingsTab();
          });
      }

      async function uploadSiteLogo() {
        const input = document.getElementById("siteLogoFile");
        const status = document.getElementById("siteLogoUploadStatus");
        const file = input?.files?.[0];
        if (!file) {
          showAdminMessage("Pilih file logo terlebih dahulu.", "error");
          return;
        }
        const allowed = ["image/png", "image/jpeg", "image/webp", "image/svg+xml"];
        if (!allowed.includes(file.type)) {
          showAdminMessage("Format logo harus PNG, JPG, WebP, atau SVG.", "error");
          return;
        }
        if (file.size > 2 * 1024 * 1024) {
          showAdminMessage("Ukuran logo maksimal 2 MB.", "error");
          return;
        }
        const button = document.getElementById("uploadSiteLogo");
        button.disabled = true;
        button.textContent = "Mengunggah...";
        status.textContent = "Mengunggah logo ke penyimpanan...";
        const ext = (file.name.split(".").pop() || "png").toLowerCase().replace(/[^a-z0-9]/g, "") || "png";
        const path = `branding/header-logo.${ext}`;
        const { error: uploadError } = await supabase.storage
          .from("site-assets")
          .upload(path, file, { upsert: true, cacheControl: "3600", contentType: file.type });
        if (uploadError) {
          button.disabled = false;
          button.textContent = "Upload Logo";
          status.textContent = "";
          showAdminMessage(`Upload logo gagal: ${uploadError.message}. Pastikan SQL site-logo-storage.sql sudah dijalankan.`, "error");
          return;
        }
        const { data } = supabase.storage.from("site-assets").getPublicUrl(path);
        if (!data?.publicUrl) {
          button.disabled = false;
          button.textContent = "Upload Logo";
          status.textContent = "";
          showAdminMessage("URL logo tidak berhasil dibuat.", "error");
          return;
        }

        // Cache-busting memastikan logo baru langsung terlihat di semua halaman.
        const url = `${data.publicUrl}?v=${Date.now()}`;
        siteSettings.site_logo_url = url;
        document.getElementById("siteLogoUrl").value = url;
        const preview = document.getElementById("siteLogoPreview");
        preview.classList.add("has-logo");
        preview.innerHTML = `<img src="${esc(url)}" alt="Preview logo">`;
        document.getElementById("removeSiteLogo")?.classList.remove("hidden");

        // Simpan URL logo langsung setelah upload supaya admin tidak perlu
        // menekan Simpan Pengaturan lagi.
        status.textContent = "Logo berhasil diunggah. Menyimpan ke pengaturan website...";
        const nextSettings = { ...siteSettings, site_logo_url: url };
        const { data: savedSettings, error: saveLogoError } = await supabase.rpc(
          "secure_admin_save_site_settings",
          { p_settings: nextSettings },
        );
        if (saveLogoError) {
          button.disabled = false;
          button.textContent = "Upload Logo";
          status.textContent = "Logo sudah masuk penyimpanan, tetapi pengaturan belum tersimpan.";
          showAdminMessage(`Logo ter-upload tetapi gagal diterapkan: ${saveLogoError.message}`, "error");
          return;
        }

        siteSettings = { ...DEFAULT_SITE_SETTINGS, ...(savedSettings || nextSettings) };
        status.textContent = "Logo berhasil disimpan dan langsung diterapkan ke header.";
        button.disabled = false;
        button.textContent = "Upload Logo";
        showAdminMessage("Logo berhasil di-upload dan langsung diterapkan ke seluruh header.", "success");
      }

      function removeSiteLogo() {
        siteSettings.site_logo_url = "";
        document.getElementById("siteLogoUrl").value = "";
        const preview = document.getElementById("siteLogoPreview");
        preview.classList.remove("has-logo");
        preview.innerHTML = "<span>AOC</span>";
        document.getElementById("removeSiteLogo")?.classList.add("hidden");
        document.getElementById("siteLogoUploadStatus").textContent = "Logo akan dihapus dari header setelah pengaturan disimpan.";
      }

      async function saveSiteSettings(event) {
        event.preventDefault();
        const form = event.currentTarget;
        const button = document.getElementById("saveSiteSettings");
        const values = Object.fromEntries(new FormData(form));

        values.site_name = String(values.site_name || "").trim();
        values.whatsapp_number = String(values.whatsapp_number || "").replace(
          /\D/g,
          "",
        );
        ["admin_1_whatsapp", "admin_2_whatsapp", "admin_3_whatsapp"].forEach(
          (key) => (values[key] = String(values[key] || "").replace(/\D/g, "")),
        );
        values.rental_min_days = Math.max(
          1,
          Number(values.rental_min_days) || 1,
        );
        values.rental_max_days = Math.max(
          values.rental_min_days,
          Number(values.rental_max_days) || 30,
        );
        values.maintenance_mode = form.elements.maintenance_mode.checked;
        values.payment_enabled = form.elements.payment_enabled.checked;
        values.payment_timeout_minutes = Math.max(
          5,
          Math.min(60, Number(values.payment_timeout_minutes) || 15),
        );

        if (!values.site_name || !values.whatsapp_number) {
          showAdminMessage(
            "Nama website dan nomor WhatsApp wajib diisi.",
            "error",
          );
          return;
        }

        button.disabled = true;
        button.textContent = "Menyimpan...";

        const { data, error } = await supabase.rpc(
          "secure_admin_save_site_settings",
          { p_settings: values },
        );

        button.disabled = false;
        button.textContent = "Simpan Pengaturan";

        if (error) {
          showAdminMessage(
            error.message.includes("secure_admin_save_site_settings")
              ? "Fitur database belum dipasang. Jalankan access-security.sql terbaru melalui Supabase SQL Editor."
              : error.message,
            "error",
          );
          return;
        }

        siteSettings = {
          ...DEFAULT_SITE_SETTINGS,
          ...(data || values),
        };
        applySiteSettings(siteSettings);
        showAdminMessage("Pengaturan website berhasil disimpan.", "success");
      }

      function renderVariantRow(variant = {}) {
        return `<div class="catalog-entry-row catalog-variant-row" data-catalog-row>
          <input class="input" data-catalog-field value="${esc(variant.name || "")}" placeholder="Contoh: Tenda 4 Orang" aria-label="Nama unit atau varian">
          <input class="input" data-catalog-field value="${esc(variant.capacity || "")}" placeholder="Contoh: 4 orang" aria-label="Ukuran atau kapasitas">
          <input class="input" data-catalog-field type="number" min="0" step="1" value="${Number(variant.stock || 0)}" placeholder="0" aria-label="Stok">
          <button class="btn danger small catalog-row-remove" data-remove-catalog-row type="button" aria-label="Hapus varian">Hapus</button>
        </div>`;
      }

      function renderInventoryRow(unit = {}) {
        const condition = unit.condition || "good";
        const status = unit.status || "available";
        return `<div class="catalog-entry-row catalog-inventory-row" data-catalog-row>
          <input class="input" data-catalog-field value="${esc(unit.inventory_number || "")}" placeholder="Contoh: TND-001" aria-label="Nomor unit inventaris">
          <select class="input" data-catalog-field aria-label="Kondisi unit">
            ${[["new", "Baru"], ["good", "Baik"], ["fair", "Cukup"], ["damaged", "Rusak"]].map(([value, label]) => `<option value="${value}" ${condition === value ? "selected" : ""}>${label}</option>`).join("")}
          </select>
          <select class="input" data-catalog-field aria-label="Status unit">
            ${[["available", "Tersedia"], ["rented", "Disewa"], ["damaged", "Rusak"], ["maintenance", "Perawatan"], ["retired", "Tidak dipakai"]].map(([value, label]) => `<option value="${value}" ${status === value ? "selected" : ""}>${label}</option>`).join("")}
          </select>
          <input class="input" data-catalog-field value="${esc(unit.notes || "")}" placeholder="Catatan opsional" aria-label="Catatan unit">
          <button class="btn danger small catalog-row-remove" data-remove-catalog-row type="button" aria-label="Hapus unit inventaris">Hapus</button>
        </div>`;
      }

      function renderPriceTierRow(tier = {}, item = {}) {
        const variant = (item.item_variants || []).find(
          (row) => row.id === tier.variant_id,
        );
        return `<div class="catalog-entry-row catalog-price-row" data-catalog-row>
          <input class="input" data-catalog-field list="catalogVariantNames" value="${esc(variant?.name || tier.variant_name || "Semua Varian")}" placeholder="Semua Varian" aria-label="Varian harga">
          <input class="input" data-catalog-field value="${esc(tier.label || "")}" placeholder="Contoh: Paket 2 Hari" aria-label="Nama paket">
          <input class="input" data-catalog-field type="number" min="1" step="1" value="${Number(tier.duration_days || 1)}" placeholder="1" aria-label="Jumlah hari">
          <input class="input" data-catalog-field type="number" min="0" step="1000" value="${Number(tier.price || 0)}" placeholder="150000" aria-label="Harga paket">
          <button class="btn danger small catalog-row-remove" data-remove-catalog-row type="button" aria-label="Hapus harga paket">Hapus</button>
        </div>`;
      }

      function renderVariantEditor(item) {
        const variants = [...(item.item_variants || [])].sort(
          (a, b) => a.sort_order - b.sort_order,
        );
        return `<section class="catalog-entry-editor">
          <div class="catalog-entry-heading"><div><h4>Variasi / ukuran</h4><p class="muted">Isi nama unit, ukuran atau kapasitas, dan jumlah stok.</p></div><button class="btn secondary small" data-add-catalog-row="variants" type="button">+ Tambah variasi</button></div>
          <div class="catalog-entry-scroll">
            <div class="catalog-entry-labels catalog-variant-row"><span>Unit / varian</span><span>Ukuran / kapasitas</span><span>Stok</span><span>Aksi</span></div>
            <div data-catalog-table="variants">${variants.map(renderVariantRow).join("")}</div>
          </div>
          <textarea class="hidden" name="variants" data-catalog-value="variants" aria-hidden="true"></textarea>
        </section>`;
      }

      function renderInventoryEditor(item) {
        const units = item.inventory_units || [];
        return `<section class="catalog-entry-editor">
          <div class="catalog-entry-heading"><div><h4>Unit inventaris</h4><p class="muted">Satu baris untuk setiap barang fisik yang dimiliki.</p></div><button class="btn secondary small" data-add-catalog-row="inventory_units" type="button">+ Tambah unit</button></div>
          <div class="catalog-entry-scroll">
            <div class="catalog-entry-labels catalog-inventory-row"><span>Nomor unit</span><span>Kondisi</span><span>Status</span><span>Catatan</span><span>Aksi</span></div>
            <div data-catalog-table="inventory_units">${units.map(renderInventoryRow).join("")}</div>
          </div>
          <textarea class="hidden" name="inventory_units" data-catalog-value="inventory_units" aria-hidden="true"></textarea>
        </section>`;
      }

      function renderPriceTierEditor(item) {
        const tiers = [...(item.item_price_tiers || [])].sort(
          (a, b) => a.duration_days - b.duration_days,
        );
        return `<section class="catalog-entry-editor">
          <div class="catalog-entry-heading"><div><h4>Harga paket</h4><p class="muted">Atur harga final berdasarkan varian dan lama penyewaan.</p></div><button class="btn secondary small" data-add-catalog-row="price_tiers" type="button">+ Tambah harga</button></div>
          <datalist id="catalogVariantNames"></datalist>
          <div class="catalog-entry-scroll">
            <div class="catalog-entry-labels catalog-price-row"><span>Varian</span><span>Nama paket</span><span>Hari</span><span>Harga</span><span>Aksi</span></div>
            <div data-catalog-table="price_tiers">${tiers.map((tier) => renderPriceTierRow(tier, item)).join("")}</div>
          </div>
          <textarea class="hidden" name="price_tiers" data-catalog-value="price_tiers" aria-hidden="true"></textarea>
        </section>`;
      }

      function syncCatalogEntryTable(form, key) {
        const table = form.querySelector(`[data-catalog-table="${key}"]`);
        const output = form.querySelector(`[data-catalog-value="${key}"]`);
        if (!table || !output) return;
        output.value = [...table.querySelectorAll("[data-catalog-row]")]
          .map((row) =>
            [...row.querySelectorAll("[data-catalog-field]")]
              .map((field) => String(field.value || "").trim())
              .join(" | "),
          )
          .filter((line) => line.split("|")[0].trim())
          .join("\n");
      }

      function refreshCatalogVariantNames(form) {
        const list = form.querySelector("#catalogVariantNames");
        if (!list) return;
        const names = [...form.querySelectorAll('[data-catalog-table="variants"] [data-catalog-row]')]
          .map((row) => row.querySelector("[data-catalog-field]")?.value.trim())
          .filter(Boolean);
        list.innerHTML = ["Semua Varian", ...new Set(names)]
          .map((name) => `<option value="${esc(name)}"></option>`)
          .join("");
      }

      function setupCatalogEntryTables(form) {
        const syncAll = () => {
          ["variants", "inventory_units", "price_tiers"].forEach((key) =>
            syncCatalogEntryTable(form, key),
          );
          refreshCatalogVariantNames(form);
        };
        form.addEventListener("input", (event) => {
          if (!event.target.matches("[data-catalog-field]")) return;
          syncAll();
        });
        form.addEventListener("change", (event) => {
          if (!event.target.matches("[data-catalog-field]")) return;
          syncAll();
        });
        form.addEventListener("click", (event) => {
          const addButton = event.target.closest("[data-add-catalog-row]");
          if (addButton) {
            const key = addButton.dataset.addCatalogRow;
            const table = form.querySelector(`[data-catalog-table="${key}"]`);
            if (key === "variants") table.insertAdjacentHTML("beforeend", renderVariantRow());
            if (key === "inventory_units") table.insertAdjacentHTML("beforeend", renderInventoryRow());
            if (key === "price_tiers") table.insertAdjacentHTML("beforeend", renderPriceTierRow());
            table.lastElementChild?.querySelector("[data-catalog-field]")?.focus();
            syncAll();
            return;
          }
          const removeButton = event.target.closest("[data-remove-catalog-row]");
          if (removeButton) {
            removeButton.closest("[data-catalog-row]")?.remove();
            syncAll();
          }
        });
        form.addEventListener("submit", syncAll, { capture: true });
        syncAll();
      }

      function rentalOrderLines(order) {
        return (order.order_items || []).filter((line) =>
          line.item_type === "product" && (line.fulfillment_type === "rental" || !!order.rental_start)
        );
      }
      function rentalOrderIsComplete(order) {
        const lines = rentalOrderLines(order);
        return lines.length > 0 && lines.every((line) => Number(line.returned_quantity || 0) >= Number(line.quantity || 0));
      }
      function conditionLabel(value) {
        return ({good:"Baik",dirty:"Kotor / perlu dicuci",damaged:"Rusak",lost:"Hilang"}[value] || value || "Belum diperiksa");
      }
      let rentalReturnCategory = "operational";
      function renderRentalIncomingOrders() {
        const allRentalOrders = filterOrdersByStore(orders
          .filter(o => o.status !== "cancelled" && rentalOrderLines(o).length)
          .sort((a,b)=>String(b.created_at).localeCompare(String(a.created_at))));
        const active = allRentalOrders.filter(o => o.status !== "completed");
        const completed = allRentalOrders.filter(o => o.status === "completed");
        const rentalOrders = rentalReturnCategory === "completed" ? completed : rentalReturnCategory === "all" ? allRentalOrders : active;
        const card = (order) => {
          const lines = rentalOrderLines(order), complete = rentalOrderIsComplete(order);
          const canInspect = ["paid","returned"].includes(order.status) && !complete;
          const lastByLine = new Map();
          (order.order_returns || []).forEach(r => {
            const key = String(r.order_item_id || `item:${r.item_id}`);
            const prev = lastByLine.get(key);
            if (!prev || String(r.inspected_at) > String(prev.inspected_at)) lastByLine.set(key, r);
          });
          return `<details class="card rental-incoming-card" data-rental-order="${esc(order.id)}" ${order.status !== "completed" ? "open" : ""}>
            <summary><div class="rental-incoming-summary"><span class="status">${esc(statusLabels[order.status] || order.status)}</span><strong class="rental-order-code">${esc(order.order_number)}</strong><small>${esc(order.customer_name || "-")} · ${esc(order.phone || "-")}</small><small>${esc(formatRentalDate(order.rental_start))} → ${esc(formatRentalDate(order.rental_end))} · ${Number(order.rental_days || 1)} hari</small></div><strong>${rupiah(order.total)}</strong><span>Lihat ▾</span></summary>
            <div class="rental-incoming-body">
              <div class="rental-order-meta"><div><b>Kode Order</b><strong>${esc(order.order_number)}</strong></div><div><b>Barang</b><strong>${lines.length} jenis / ${lines.reduce((n,l)=>n+Number(l.quantity||0),0)} unit</strong></div><div><b>Lokasi Toko</b><strong>${esc(order.location_name || "Belum dipilih")}</strong></div><div><b>Pembayaran</b><strong>${esc(order.payment_status || "unpaid")}</strong></div></div>
              <section class="rental-inspection-box">
                <div class="admin-editor-heading"><div><span class="badge">CHECKLIST PENGEMBALIAN</span><h4>${order.status === "completed" ? "Pesanan sudah selesai" : "Periksa semua barang sebelum selesai"}</h4></div></div>
                <p class="muted">Semua barang dari checkout tampil otomatis. Isi kondisi <b>semua barang</b>, lalu tekan <b>Simpan Semua Pengembalian</b> sekali. Sistem menyimpan seluruh checklist dalam satu transaksi.</p>
                <div class="rental-check-list">
                  ${lines.map(line=>{
                    const returned=Number(line.returned_quantity||0), total=Number(line.quantity||0), remaining=Math.max(0,total-returned);
                    const last=lastByLine.get(String(line.id)) || lastByLine.get(`item:${line.item_id}`);
                    return `<div class="rental-check-line" data-rental-line="${esc(line.id)}">
                      <div class="rental-check-main"><div><strong>${esc(line.title_snapshot)}${line.variant_name_snapshot?` · ${esc(line.variant_name_snapshot)}`:""}</strong><small>Jumlah: ${total} · Sudah kembali: ${returned} · Sisa: ${remaining}</small>${last?`<small>Pemeriksaan terakhir: <b>${esc(conditionLabel(last.condition))}</b>${last.notes?` · ${esc(last.notes)}`:""}${last.fee?` · Biaya ${rupiah(last.fee)}`:""}</small>`:`<small>Belum diperiksa.</small>`}</div><b>${rupiah(line.line_total)}</b></div>
                      ${canInspect ? `<div class="rental-check-controls"><label class="field"><span>Jumlah kembali</span><input class="input" type="number" min="${remaining}" max="${remaining}" value="${remaining}" data-return-qty="${esc(line.id)}" readonly></label><label class="field"><span>Kondisi *</span><select class="input" data-return-condition="${esc(line.id)}" required><option value="">Pilih kondisi</option><option value="good">Baik</option><option value="dirty">Kotor / perlu dicuci</option><option value="damaged">Rusak</option><option value="lost">Hilang</option></select></label><label class="field rental-note-field"><span>Catatan kondisi</span><input class="input" data-return-note="${esc(line.id)}" placeholder="Contoh: lengkap / resleting rusak"></label><label class="field"><span>Biaya</span><input class="input" type="number" min="0" step="1000" value="0" data-return-fee="${esc(line.id)}"></label></div>` : `<div class="rental-condition-readonly">Kondisi: <b>${esc(conditionLabel(last?.condition || (complete ? order.return_condition : "Belum diperiksa")))}</b></div>`}
                    </div>`;
                  }).join("")}
                </div>
                <div class="rental-complete-bar"><span>${complete?"✅ Semua barang sudah dikembalikan dan tercatat.":"⏳ Semua barang wajib diperiksa sebelum pesanan selesai."}</span>${canInspect?`<button class="btn primary" data-rental-bulk-return="${esc(order.id)}" type="button">Simpan Semua Pengembalian</button>`:""}${order.status === "returned" && complete?`<button class="btn primary small" data-finalize-rental="${esc(order.id)}" type="button">Finalisasi → Selesai</button>`:""}${order.status === "completed"?`<div class="rental-complete-actions"><span class="rental-complete-ok">✓ Selesai & dikembalikan</span><button class="btn danger small" data-delete-rental-order="${esc(order.id)}" type="button">🗑️ Hapus</button></div>`:`<div class="rental-delete-actions"><button class="btn danger small" data-delete-rental-order="${esc(order.id)}" type="button">🗑️ Hapus Pesanan</button></div>`}</div>
              </section>
            </div>
          </details>`;
        };
        return `<section class="card rental-incoming-section"><div class="admin-list-heading"><div><span class="badge">CHECKOUT → SEWA</span><h3>Pesanan Sewa Masuk</h3><p class="muted">${active.length} operasional · ${completed.length} selesai · ${allRentalOrders.length} total.</p></div><button id="refreshRentalOrders" class="btn secondary small" type="button">Muat Ulang</button></div><div class="rental-return-tabs" role="tablist"><button class="btn small ${rentalReturnCategory === "operational" ? "primary" : "secondary"}" data-rental-return-category="operational" type="button">🟡 Operasional (${active.length})</button><button class="btn small ${rentalReturnCategory === "completed" ? "primary" : "secondary"}" data-rental-return-category="completed" type="button">✅ Pesanan Selesai (${completed.length})</button><button class="btn small ${rentalReturnCategory === "all" ? "primary" : "secondary"}" data-rental-return-category="all" type="button">📋 Semua (${allRentalOrders.length})</button></div><div class="rental-workflow-note"><b>Alur:</b> Checkout → Dibayar → Sewa → Barang kembali → <b>Checklist semua barang</b> → Dikembalikan → <b>Selesai</b></div><div class="rental-incoming-list">${rentalOrders.map(card).join("") || '<div class="notice">Tidak ada pesanan pada kategori ini.</div>'}</div></section>`;
      }
      function bindRentalIncomingEvents() {
        const content=document.getElementById("adminContent");
        content.querySelector("#refreshRentalOrders")?.addEventListener("click", refreshOrders);
        content.querySelectorAll("[data-rental-return-category]").forEach(btn => btn.addEventListener("click", () => { rentalReturnCategory = btn.dataset.rentalReturnCategory || "operational"; renderRentalReturnsTab(); }));
        bindStoreCategoryBar(content);
        content.querySelectorAll("[data-rental-bulk-return]").forEach(btn=>btn.addEventListener("click",async()=>{
          const order=orders.find(o=>String(o.id)===String(btn.dataset.rentalBulkReturn));
          if(!order) return;
          const lines=rentalOrderLines(order).filter(line=>Number(line.quantity||0)>Number(line.returned_quantity||0));
          if(!lines.length) return showAdminMessage("Semua barang pada pesanan ini sudah dikembalikan.","warning");
          const inspections=[];
          for(const line of lines){
            const id=line.id;
            const qty=Number(content.querySelector(`[data-return-qty="${id}"]`)?.value||0);
            const condition=content.querySelector(`[data-return-condition="${id}"]`)?.value||"";
            const note=String(content.querySelector(`[data-return-note="${id}"]`)?.value||"").trim()||null;
            const fee=Number(content.querySelector(`[data-return-fee="${id}"]`)?.value||0);
            const remaining=Math.max(0,Number(line.quantity||0)-Number(line.returned_quantity||0));
            if(!condition) return showAdminMessage(`Pilih kondisi untuk ${line.title_snapshot}.`,"error");
            if(!Number.isInteger(qty)||qty!==remaining) return showAdminMessage(`Jumlah kembali ${line.title_snapshot} harus ${remaining}.`,"error");
            if(!Number.isFinite(fee)||fee<0) return showAdminMessage(`Biaya ${line.title_snapshot} tidak valid.`,"error");
            inspections.push({order_item_id:line.id,item_id:line.item_id,quantity:qty,condition,notes:note,fee});
          }
          if(!confirm(`Simpan checklist ${inspections.length} barang sekaligus untuk ${order.order_number}?`)) return;
          btn.disabled=true;btn.textContent="Menyimpan semua...";
          const {error}=await supabase.rpc("secure_admin_bulk_return_inspection",{p_order_id:order.id,p_items:inspections});
          if(error){btn.disabled=false;btn.textContent="Simpan Semua Pengembalian";return showAdminMessage(`${error.message}. Jalankan PATCH-BULK-RETURN-INSPECTION.sql.`,"error");}
          await refreshOrders();showAdminMessage(`${order.order_number}: semua kondisi barang berhasil disimpan dalam satu transaksi dan pesanan dikembalikan.`,"success");
        }));
        content.querySelectorAll("[data-finalize-rental]").forEach(btn=>btn.addEventListener("click",async()=>{const order=orders.find(o=>String(o.id)===String(btn.dataset.finalizeRental));if(!order||order.status!=="returned"||!rentalOrderIsComplete(order))return showAdminMessage("Checklist pengembalian belum lengkap.","error");if(!confirm(`Finalisasi ${order.order_number} menjadi Selesai?`))return;btn.disabled=true;const {data,error}=await supabase.rpc("secure_admin_finalize_rental",{p_order_id:order.id,p_admin_notes:"Semua barang dikembalikan dan diperiksa."});if(error){btn.disabled=false;return showAdminMessage(error.message,"error");}await refreshOrders();showAdminMessage(`${order.order_number} selesai. Denda keterlambatan 100% dihitung server-side dan finalisasi tidak memakai voucher.` ,"success");}));
        content.querySelectorAll("[data-delete-rental-order]").forEach(btn=>btn.addEventListener("click",async()=>{
          const order=orders.find(o=>String(o.id)===String(btn.dataset.deleteRentalOrder));
          if(!order) return showAdminMessage("Pesanan tidak ditemukan.","error");

          const statusText = statusLabels[order.status] || order.status || "-";
          const confirmed = await window.aocReminderConfirm({
            icon: "🗑️",
            title: "Hapus Pesanan Permanen?",
            confirmText: "Hapus Pesanan",
            danger: true,
            message: `
              <div class="aoc-delete-order-summary">
                <div class="aoc-delete-order-row"><span>Kode Order</span><strong>${esc(order.order_number)}</strong></div>
                <div class="aoc-delete-order-row"><span>Customer</span><strong>${esc(order.customer_name || "-")}</strong></div>
                <div class="aoc-delete-order-row"><span>Status</span><b class="aoc-delete-status">${esc(statusText)}</b></div>
              </div>
              <div class="aoc-delete-warning">
                <strong>⚠️ Perhatian</strong>
                <span>Semua data pesanan terkait akan dihapus permanen dan tidak dapat dibatalkan. Stok/kuota yang masih tercatat terpakai akan dikembalikan oleh server.</span>
              </div>
              <div class="aoc-delete-question">Pastikan Anda benar-benar ingin menghapus pesanan ini.</div>
            `
          });
          if(!confirmed) return;

          const oldText=btn.innerHTML;btn.disabled=true;btn.innerHTML="⏳ Menghapus...";
          const {data,error}=await supabase.rpc("admin_delete_order",{p_order_id:order.id});
          if(error){btn.disabled=false;btn.innerHTML=oldText;console.error("admin_delete_rental_order",error);return showAdminMessage(error.message||"Gagal menghapus pesanan.","error");}
          await refreshOrders();
          showAdminMessage(data?.message || `${order.order_number} berhasil dihapus permanen.`,"success");
        }));
      }

      let aocSelectedStoreCategory = "all";

      function getStoreCategories() {
        var map = new Map();
        (orders || []).forEach(function (o) {
          var id = String(o.location_id || "");
          if (!id) return;
          var name = String(o.location_name || "Belum dipilih").trim() || "Belum dipilih";
          if (!map.has(id)) map.set(id, name);
        });
        return Array.from(map.entries()).sort(function (a, b) {
          return a[1].localeCompare(b[1], "id");
        });
      }

      function filterOrdersByStore(list) {
        if (aocSelectedStoreCategory === "all") return list;
        return (list || []).filter(function (o) {
          return String(o.location_id || "") === String(aocSelectedStoreCategory);
        });
      }

      function renderStoreCategoryBar() {
        var categories = getStoreCategories();
        if (!categories.length) return "";
        var html = '<div class="aoc-store-category-wrap">';
        html += '<div class="aoc-store-category-title">🏪 Kategori Toko</div>';
        html += '<div class="aoc-store-category-bar">';
        html += '<button type="button" class="aoc-store-category ' + (aocSelectedStoreCategory === "all" ? "active" : "") + '" data-store-category="all">Semua Toko</button>';
        categories.forEach(function (entry) {
          var id = entry[0];
          var name = entry[1];
          html += '<button type="button" class="aoc-store-category ' + (String(aocSelectedStoreCategory) === String(id) ? "active" : "") + '" data-store-category="' + esc(id) + '">' + esc(name) + '</button>';
        });
        html += '</div></div>';
        return html;
      }

      function bindStoreCategoryBar(root) {
        if (!root) return;
        var buttons = root.querySelectorAll("[data-store-category]");
        buttons.forEach(function (btn) {
          btn.addEventListener("click", function () {
            aocSelectedStoreCategory = btn.getAttribute("data-store-category") || "all";
            if (activeTab === "rental_orders") renderRentalOrdersTab();
            else if (activeTab === "rental_returns") renderRentalReturnsTab();
            else if (activeTab === "rental_reminders") renderRentalRemindersTab();
            else if (activeTab === "orders") renderOrdersTab();
          });
        });
      }

      function renderRentalOrdersTab() {
        const content = document.getElementById("adminContent");
        const rentalOrders = filterOrdersByStore(orders
          .filter(o => o.status !== "cancelled" && rentalOrderLines(o).length && o.status !== "completed"))
          .sort((a,b) => String(b.created_at).localeCompare(String(a.created_at)));
        content.innerHTML = `
          <section class="card rental-incoming-section">
            <div class="admin-list-heading">
              <div><span class="badge">CHECKOUT → SEWA</span><h3>Pesanan Sewa</h3><p class="muted">Order rental yang masih berjalan/menunggu. Pemeriksaan barang tidak dilakukan di menu ini.</p></div>
              <button id="refreshRentalOrdersOnly" class="btn secondary small" type="button">Muat Ulang</button>
            </div>
            <div class="rental-workflow-note"><b>Alur:</b> Checkout → Dibayar → Sewa → Pengembalian Barang → Selesai</div>${renderStoreCategoryBar()}
            <div class="rental-incoming-list">${rentalOrders.map(order => {
              const lines = rentalOrderLines(order);
              return `<details class="card rental-incoming-card" data-rental-order="${esc(order.id)}">
                <summary><div class="rental-incoming-summary"><span class="status">${esc(statusLabels[order.status] || order.status)}</span><strong class="rental-order-code">${esc(order.order_number)}</strong><small>${esc(order.customer_name || "-")} · ${esc(order.phone || "-")}</small><small>${esc(formatRentalDate(order.rental_start))} → ${esc(formatRentalDate(order.rental_end))} · ${Number(order.rental_days || 1)} hari</small></div><strong>${rupiah(order.total)}</strong><span>Lihat ▾</span></summary>
                <div class="rental-incoming-body"><div class="rental-order-meta"><div><b>Kode Order</b><strong>${esc(order.order_number)}</strong></div><div><b>Barang</b><strong>${lines.length} jenis / ${lines.reduce((n,l)=>n+Number(l.quantity||0),0)} unit</strong></div><div><b>Lokasi Toko</b><strong>${esc(order.location_name || "Belum dipilih")}</strong></div><div><b>Pembayaran</b><strong>${esc(order.payment_status || "unpaid")}</strong></div></div><div class="rental-check-list">${lines.map(line => `<div class="rental-check-line"><div class="rental-check-main"><div><strong>${esc(line.title_snapshot)}${line.variant_name_snapshot ? ` · ${esc(line.variant_name_snapshot)}` : ""}</strong><small>Jumlah: ${Number(line.quantity||0)} · Harga: ${rupiah(line.line_total)}</small></div><b>${rupiah(line.line_total)}</b></div></div>`).join("")}</div></div>
              </details>`;
            }).join("") || '<div class="notice">Belum ada pesanan sewa aktif.</div>'}</div>
          </section>`;
        content.querySelector("#refreshRentalOrdersOnly")?.addEventListener("click", refreshOrders);
        bindStoreCategoryBar(content);
      }

      function renderRentalReturnsTab() {
        const content = document.getElementById("adminContent");
        content.innerHTML = renderRentalIncomingOrders();
        bindRentalIncomingEvents();
      }

      const AOC_RENTAL_REMINDER_HIDDEN_KEY = "aoc_rental_reminder_hidden_v1";

      function getHiddenRentalReminderIds() {
        try {
          const raw = localStorage.getItem(AOC_RENTAL_REMINDER_HIDDEN_KEY);
          const parsed = raw ? JSON.parse(raw) : [];
          return new Set(Array.isArray(parsed) ? parsed.map(String) : []);
        } catch (error) {
          console.warn("Gagal membaca daftar pengingat yang dihapus:", error);
          return new Set();
        }
      }

      function saveHiddenRentalReminderIds(ids) {
        try {
          localStorage.setItem(AOC_RENTAL_REMINDER_HIDDEN_KEY, JSON.stringify([...new Set([...ids].map(String))]));
          return true;
        } catch (error) {
          console.warn("Gagal menyimpan daftar pengingat yang dihapus:", error);
          return false;
        }
      }

      function hideRentalReminderPermanently(orderId) {
        const ids = getHiddenRentalReminderIds();
        ids.add(String(orderId));
        return saveHiddenRentalReminderIds(ids);
      }

      function clearRentalRemindersPermanently(orderIds) {
        const ids = getHiddenRentalReminderIds();
        orderIds.forEach(id => ids.add(String(id)));
        return saveHiddenRentalReminderIds(ids);
      }

      function restoreRentalReminders() {
        try {
          localStorage.removeItem(AOC_RENTAL_REMINDER_HIDDEN_KEY);
          return true;
        } catch (error) {
          console.warn("Gagal memulihkan pengingat:", error);
          return false;
        }
      }

      async function renderRentalRemindersTab() {
        const content = document.getElementById("adminContent");
        content.innerHTML = `<section class="card"><div class="admin-list-heading"><div><span class="badge">CUSTOMER REMINDER MONITOR</span><h3>🔔 Pengingat Customer</h3><p class="muted">Semua barang yang di-checkout sebagai rental ditampilkan sebagai monitor waktu. Setiap order menampilkan kode order, seluruh barang, jumlah, batas waktu, countdown, dan tombol pengingat customer.</p></div><button id="refreshRentalReminders" class="btn secondary small" type="button">Muat Ulang</button></div><div class="notice">Memuat monitor rental...</div></section>`;
        try {
          await supabase.rpc("admin_process_rental_reminders");
          const { data: reminderRows, error } = await supabase.rpc("admin_list_rental_reminders");
          if (error) throw error;

          const now = Date.now();
          const reminders = reminderRows || [];
          const reminderByOrder = new Map();
          reminders.forEach(r => {
            const key = String(r.order_id);
            const prev = reminderByOrder.get(key);
            if (!prev || new Date(r.triggered_at || 0).getTime() > new Date(prev.triggered_at || 0).getTime()) reminderByOrder.set(key, r);
          });

          // Monitor berasal dari order checkout, bukan hanya dari tabel reminder,
          // sehingga order yang masih jauh dari H-4 tetap terlihat beserta semua barangnya.
          const hiddenReminderIds = getHiddenRentalReminderIds();
          const rentalOrders = filterOrdersByStore(orders
            .filter(o => !hiddenReminderIds.has(String(o.id)) && o.status !== "cancelled" && o.status !== "completed" && rentalOrderLines(o).length))
            .sort((a,b) => {
              const da = new Date(a.rental_due_at || 0).getTime();
              const db = new Date(b.rental_due_at || 0).getTime();
              return (Number.isFinite(da) ? da : Infinity) - (Number.isFinite(db) ? db : Infinity);
            });

          const dueSoonCount = rentalOrders.filter(o => {
            const due = new Date(o.rental_due_at || 0).getTime();
            return Number.isFinite(due) && due - now > 0 && due - now <= 4 * 3600000;
          }).length;
          const overdueCount = rentalOrders.filter(o => {
            const due = new Date(o.rental_due_at || 0).getTime();
            return Number.isFinite(due) && due <= now;
          }).length;

          const cards = rentalOrders.map(order => {
            const lines = rentalOrderLines(order);
            const days = Math.max(1, Number(order.rental_days || 1));
            let due = new Date(order.rental_due_at || "");
            if (!Number.isFinite(due.getTime()) && order.rental_start) {
              due = new Date(`${order.rental_start}T00:00:00+07:00`);
              due = new Date(due.getTime() + days * 28 * 3600000);
            }
            const dueMs = due.getTime();
            const validDue = Number.isFinite(dueMs);
            const diff = validDue ? dueMs - now : NaN;
            const overdueNow = validDue && diff <= 0;
            const within4h = validDue && diff > 0 && diff <= 4 * 3600000;
            const customerName = order.customer_name || "Customer";
            const phone = order.phone || "";
            const total = Number(order.rental_total ?? order.total ?? order.subtotal ?? 0) || 0;
            const fee = Number(order.late_fee || 0) || (overdueNow ? Math.round(total * 1.00) : 0);
            const digits = String(phone).replace(/\D/g, "").replace(/^0/, "62");
            const msg = overdueNow
              ? `Halo ${customerName}, pengingat pesanan ${order.order_number}. Waktu pengembalian sudah lewat. Mohon segera mengembalikan seluruh barang rental. Denda keterlambatan 100% dari total sewa akan dikenakan.`
              : `Halo ${customerName}, ini pengingat untuk pesanan ${order.order_number}. Waktu sewa akan berakhir ${validDue ? due.toLocaleString("id-ID") : "sesuai jadwal sewa"}. Mohon segera mempersiapkan pengembalian seluruh barang.`;
            let countdown = "Waktu belum tersedia";
            if (overdueNow) {
              const mins = Math.floor(Math.abs(diff) / 60000);
              countdown = `Terlambat ${Math.floor(mins / 60)}j ${mins % 60}m`;
            } else if (validDue) {
              const mins = Math.floor(diff / 60000);
              countdown = `${Math.floor(mins / 60)}j ${mins % 60}m tersisa`;
            }
            const badge = overdueNow ? "🔴 TERLAMBAT" : within4h ? "⚠️ SEGERA KEMBALI" : "🟢 MONITOR";
            const reminderState = reminderByOrder.get(String(order.id));
            const reminderText = reminderState?.reminder_type === "overdue_fee" ? "Denda otomatis 100% aktif" : reminderState?.reminder_type === "4h_before_due" ? "Pengingat H-4 jam aktif" : "Belum masuk H-4 jam";
            const itemRows = lines.map(line => `<div class="rental-reminder-item"><div><strong>${esc(line.title_snapshot || "Item rental")}${line.variant_name_snapshot ? ` · ${esc(line.variant_name_snapshot)}` : ""}</strong><small>Jumlah: <b>${Number(line.quantity || 0)} unit</b> · ${rupiah(line.line_total || 0)}</small></div><span>${Number(line.quantity || 0)}×</span></div>`).join("");
            return `<article class="card rental-reminder-card" data-monitor-order="${esc(order.id)}" data-order-code="${esc(order.order_number || "-")}" data-due-ms="${validDue ? dueMs : ""}"><div class="rental-reminder-head"><div><span class="badge reminder-live-badge">${badge}</span><h3>${esc(order.order_number || "-")}</h3><p><b>${esc(customerName)}</b> · ${esc(phone || "No. HP belum ada")}</p><div class="rental-reminder-location">📍 <span>Lokasi Toko</span> <b>${esc(order.location_name || "Belum dipilih")}</b></div></div><strong>${rupiah(total)}</strong></div><div class="rental-reminder-time"><div><small>BATAS WAKTU</small><b>${validDue ? due.toLocaleString("id-ID") : "Waktu belum tersedia"}</b></div><div><small>WAKTU TERSISA</small><b class="reminder-countdown" data-countdown>${esc(countdown)}</b></div><div><small>STATUS</small><b class="reminder-status">${esc(reminderText)}</b></div></div><div class="rental-reminder-items"><div class="rental-reminder-items-title">📦 Semua barang di-checkout (${lines.length} jenis / ${lines.reduce((n,l)=>n+Number(l.quantity||0),0)} unit)</div>${itemRows}</div><p class="muted">Periode: ${esc(formatRentalDate(order.rental_start))} → ${esc(formatRentalDate(order.rental_end))} · ${days} hari · 1 hari = 28 jam</p><div class="notice error reminder-fee" style="display:${overdueNow ? "block" : "none"}">🔴 Denda keterlambatan 100%: <b>${rupiah(fee || Math.round(total * 1.00))}</b></div><div class="actions">${digits ? `<a class="btn primary small" target="_blank" rel="noopener" href="https://wa.me/${digits}?text=${encodeURIComponent(msg)}">🔔 Ingatkan Customer</a>` : `<span class="muted">Nomor customer belum tersedia</span>`}<button class="btn danger small rental-reminder-delete" type="button">🗑️ Hapus</button></div></article>`;
          }).join("");

          content.innerHTML = `<section class="card"><div class="admin-list-heading rental-reminder-heading"><div><span class="badge">CUSTOMER REMINDER MONITOR</span><h3>🔔 Pengingat Customer</h3><p class="muted">${rentalOrders.length} order rental dipantau · ${dueSoonCount} segera berakhir · ${overdueCount} terlambat.</p></div><div class="rental-reminder-toolbar"><button id="clearRentalReminderArea" class="btn danger small" type="button">🧹 Clear Area</button><button id="restoreRentalReminders" class="btn secondary small" type="button">↺ Pulihkan</button><button id="refreshRentalReminders" class="btn secondary small" type="button">↻ Muat Ulang</button></div></div>${renderStoreCategoryBar()}<div class="rental-reminder-rules"><b>Aturan:</b> 1 hari = 28 jam · pengingat customer mulai H-4 jam · denda keterlambatan = 100% dari seluruh harga sewa.</div><div id="rentalReminderList" class="rental-reminder-list">${cards || '<div class="notice">Belum ada order rental yang bisa dipantau.</div>'}</div></section>`;
          content.querySelector("#refreshRentalReminders")?.addEventListener("click", renderRentalRemindersTab);
          bindStoreCategoryBar(content);
          content.querySelector("#clearRentalReminderArea")?.addEventListener("click", () => {
            const list = content.querySelector("#rentalReminderList");
            if (!list) return;
            const cards = [...list.querySelectorAll(".rental-reminder-card")];
            if (!cards.length) return;
            window.aocReminderConfirm({
              icon: "🧹",
              title: "Clear Area Pengingat?",
              message: "Semua pengingat yang sedang tampil akan disembunyikan dan <b>tetap tersembunyi setelah refresh</b>. Data pesanan/database tidak dihapus.",
              confirmText: "Ya, Clear Permanen",
              danger: true
            }).then((confirmed) => {
              if (!confirmed) return;
              const ids = cards.map(card => card.dataset.monitorOrder).filter(Boolean);
              if (!clearRentalRemindersPermanently(ids)) {
                window.aocReminderConfirm({ icon: "⚠️", title: "Gagal Menyimpan", message: "Browser tidak mengizinkan penyimpanan daftar pengingat. Silakan coba lagi.", confirmText: "OK" });
                return;
              }
              list.innerHTML = '<div class="notice rental-reminder-cleared">🧹 Semua pengingat di area ini sudah disembunyikan secara permanen pada perangkat ini. Gunakan <b>↺ Pulihkan</b> jika ingin menampilkannya kembali.</div>';
              if (window.__aocRentalReminderTimer) { clearInterval(window.__aocRentalReminderTimer); window.__aocRentalReminderTimer = null; }
            });
          });
          content.querySelector("#restoreRentalReminders")?.addEventListener("click", () => {
            window.aocReminderConfirm({
              icon: "↺",
              title: "Pulihkan Pengingat?",
              message: "Semua pengingat yang sebelumnya dihapus/di-clear akan ditampilkan kembali. Data pesanan tidak berubah.",
              confirmText: "Ya, Pulihkan",
              danger: false
            }).then((confirmed) => {
              if (!confirmed) return;
              if (!restoreRentalReminders()) return;
              renderRentalRemindersTab();
            });
          });
          content.querySelectorAll(".rental-reminder-delete")?.forEach(btn => btn.addEventListener("click", () => {
            const card = btn.closest(".rental-reminder-card");
            if (!card) return;
            const code = card.dataset.orderCode || "order ini";
            window.aocReminderConfirm({
              icon: "🗑️",
              title: "Hapus Pengingat?",
              message: `Pengingat <b>${esc(code)}</b> akan disembunyikan <b>secara permanen dari daftar pengingat pada perangkat ini</b>. Data pesanan tetap aman dan tidak akan dihapus.`,
              confirmText: "Ya, Hapus Permanen",
              danger: true
            }).then((confirmed) => {
              if (!confirmed) return;
              if (!hideRentalReminderPermanently(card.dataset.monitorOrder)) {
                window.aocReminderConfirm({ icon: "⚠️", title: "Gagal Menyimpan", message: "Pengingat tidak dapat disimpan sebagai terhapus pada browser ini. Silakan coba lagi.", confirmText: "OK" });
                return;
              }
              card.remove();
              const list = content.querySelector("#rentalReminderList");
              if (list && !list.querySelector(".rental-reminder-card")) list.innerHTML = '<div class="notice rental-reminder-cleared">🗑️ Pengingat sudah dihapus dan tidak akan muncul lagi setelah refresh. Gunakan <b>↺ Pulihkan</b> untuk menampilkannya kembali.</div>';
            });
          }));
          startLiveRentalReminderClock();
        } catch (error) {
          content.innerHTML=`<section class="card"><div class="notice error"><b>Monitor Pengingat Customer belum dapat dimuat.</b><br>${esc(error?.message || "Gagal memuat data.")}<br><small>Pastikan PATCH-RENTAL-REMINDER-28H-4H-FEE100.sql sudah dijalankan di Supabase.</small></div></section>`;
        }
      }

      function startLiveRentalReminderClock() {
        if (window.__aocRentalReminderTimer) clearInterval(window.__aocRentalReminderTimer);
        const tick = () => {
          const cards = document.querySelectorAll("#adminContent .rental-reminder-card[data-due-ms]");
          const now = Date.now();
          cards.forEach(card => {
            const due = Number(card.dataset.dueMs);
            if (!Number.isFinite(due)) return;
            const diff = due - now;
            const countdownEl = card.querySelector("[data-countdown]");
            const badgeEl = card.querySelector(".reminder-live-badge");
            const statusEl = card.querySelector(".reminder-status");
            const feeEl = card.querySelector(".reminder-fee");
            if (diff <= 0) {
              const mins = Math.floor(Math.abs(diff) / 60000);
              if (countdownEl) countdownEl.textContent = `Terlambat ${Math.floor(mins / 60)}j ${mins % 60}m`;
              if (badgeEl) badgeEl.textContent = "🔴 TERLAMBAT";
              if (statusEl) statusEl.textContent = "Denda keterlambatan 100% aktif";
              if (feeEl) feeEl.style.display = "block";
            } else {
              const totalSeconds = Math.floor(diff / 1000);
              const days = Math.floor(totalSeconds / 86400);
              const hours = Math.floor((totalSeconds % 86400) / 3600);
              const minutes = Math.floor((totalSeconds % 3600) / 60);
              const seconds = totalSeconds % 60;
              const text = days > 0 ? `${days}h ${hours}j ${minutes}m ${seconds}d tersisa` : `${hours}j ${minutes}m ${seconds}d tersisa`;
              if (countdownEl) countdownEl.textContent = text;
              if (badgeEl) badgeEl.textContent = diff <= 4 * 3600000 ? "⚠️ SEGERA KEMBALI" : "🟢 MONITOR";
              if (statusEl) statusEl.textContent = diff <= 4 * 3600000 ? "Pengingat H-4 jam aktif" : "Belum masuk H-4 jam";
              if (feeEl) feeEl.style.display = "none";
            }
          });
        };
        tick();
        window.__aocRentalReminderTimer = setInterval(tick, 1000);
      }

      function renderRentalTab() {
        const content = document.getElementById("adminContent");
        const rentals = rentalItems();

        const item = editingItem || {
          title: "",
          slug: "",
          description: "",
          image_url: "",
          price: 0,
          stock: 0,
          deposit: 0,
          sale_price: 0,
          sale_enabled: false,
          rental_enabled: true,
          is_featured: false,
          sort_order: 0,
          requires_guarantee: true,
          guarantee_note: "",
          is_active: true,
        };

        content.innerHTML = `
        <div class="admin-catalog-layout">
          <section class="card admin-editor-card">
            <div class="admin-editor-heading">
              <div>
                <span class="badge">Sewa Item</span>
                <h3>${editingItem ? "Edit Item Sewa" : "Tambah Item Sewa"}</h3>
                <p class="muted">
                  Barang akan muncul di katalog Sewa Item.
                </p>
              </div>

              ${
                editingItem
                  ? `
                <button id="cancelRentalEdit" class="btn secondary small" type="button">
                  Batal
                </button>
              `
                  : ""
              }
            </div>

            <form id="rentalForm" class="form">
              <div class="two">
                <label class="field">
                  <span>Nama item *</span>
                  <input
                    id="rentalTitle"
                    class="input"
                    name="title"
                    value="${esc(item.title || "")}"
                    required
                    maxlength="150"
                    placeholder="Contoh: Tenda Kapasitas 4 Orang"
                  >
                </label>

                <label class="field">
                  <span>Slug URL *</span>
                  <input
                    id="rentalSlug"
                    class="input"
                    name="slug"
                    value="${esc(item.slug || "")}"
                    required
                    maxlength="160"
                    placeholder="tenda-4-orang"
                  >
                </label>
              </div>

              <label class="field">
                <span>Deskripsi *</span>
                <textarea
                  class="input"
                  name="description"
                  required
                  maxlength="3000"
                  placeholder="Spesifikasi, kelengkapan, dan ketentuan penyewaan"
                >${esc(item.description || "")}</textarea>
              </label>

              <div class="two">
                <label class="field">
                  <span>Kategori barang</span>
                  <input class="input" name="category_name" list="catalogCategoryOptions" value="${esc(item.item_categories?.name || "")}" placeholder="Contoh: Tenda">
                  <datalist id="catalogCategoryOptions">${categories.map((category) => `<option value="${esc(category.name)}"></option>`).join("")}</datalist>
                </label>
                <label class="field">
                  <span>Deposit per barang</span>
                  <input class="input" name="deposit" type="number" min="0" step="1000" value="${Number(item.deposit || 0)}">
                </label>
              </div>

              <label class="field catalog-upload-field">
                <span>Upload gambar utama</span>
                <input
                  id="rentalImageUrl"
                  name="image_url"
                  type="hidden"
                  value="${esc(item.image_url || "")}"
                >
                <input
                  id="catalogPrimaryUpload"
                  class="input"
                  type="file"
                  accept="image/jpeg,image/png,image/webp,image/gif"
                >
                <small id="catalogPrimaryUploadStatus" class="muted">${
                  item.image_url
                    ? "Gambar utama tersimpan. Pilih file baru untuk menggantinya."
                    : "Opsional. Pilih JPG, PNG, WEBP, atau GIF. Maksimal 8 MB."
                }</small>
              </label>

              <div
                id="rentalPreviewWrap"
                class="admin-image-preview ${item.image_url ? "" : "hidden"}"
              >
                <img
                  id="rentalPreview"
                  src="${esc(item.image_url || "")}"
                  alt="Preview item sewa"
                >
              </div>

              <details class="admin-advanced-section" open>
                <summary>Galeri, varian, inventaris & harga paket</summary>
                <div class="form admin-advanced-body">
                  <textarea class="hidden" name="gallery_urls" aria-hidden="true">${esc(
                      (item.item_images || [])
                        .filter(
                          (image) =>
                            !image.is_primary &&
                            image.image_url !== item.image_url,
                        )
                        .sort((a, b) => a.sort_order - b.sort_order)
                        .map((image) => image.image_url)
                        .join("\n"),
                    )}</textarea>
                  <label class="field catalog-upload-field">
                    <span>Upload galeri foto tambahan</span>
                    <input id="catalogGalleryUpload" class="input" type="file" accept="image/jpeg,image/png,image/webp,image/gif" multiple>
                    <small id="catalogUploadStatus" class="muted">Pilih beberapa file sekaligus. Maksimal 8 MB per foto.</small>
                  </label>
                  ${renderVariantEditor(item)}
                  ${renderInventoryEditor(item)}
                  ${renderPriceTierEditor(item)}
                </div>
              </details>

              <div class="two">
                <label class="field">
                  <span>Harga sewa per unit / hari *</span>
                  <input
                    class="input"
                    name="price"
                    type="number"
                    min="0"
                    step="1000"
                    value="${Number(item.price || 0)}"
                    required
                  >
                </label>

                <label class="field">
                  <span>Harga jual per unit</span>
                  <input
                    class="input"
                    name="sale_price"
                    type="number"
                    min="0"
                    step="1000"
                    value="${Number(item.sale_price || 0)}"
                  >
                </label>

                <label class="field">
                  <span>Jumlah stok *</span>
                  <input
                    class="input"
                    name="stock"
                    type="number"
                    min="0"
                    step="1"
                    value="${Number(item.stock || 0)}"
                    required
                  >
                </label>
              </div>

              <div class="admin-check-grid">
                <label class="admin-check">
                  <input
                    name="rental_enabled"
                    type="checkbox"
                    ${item.rental_enabled !== false ? "checked" : ""}
                  >
                  <span>Aktifkan sewa</span>
                </label>

                <label class="admin-check">
                  <input
                    name="sale_enabled"
                    type="checkbox"
                    ${item.sale_enabled ? "checked" : ""}
                  >
                  <span>Aktifkan jual</span>
                </label>

                <label class="admin-check">
                  <input
                    name="requires_guarantee"
                    type="checkbox"
                    ${item.requires_guarantee ? "checked" : ""}
                  >
                  <span>Wajib jaminan</span>
                </label>

                <label class="admin-check">
                  <input
                    name="is_active"
                    type="checkbox"
                    ${item.is_active ? "checked" : ""}
                  >
                  <span>Tampilkan di katalog</span>
                </label>

                <label class="admin-check">
                  <input name="is_featured" type="checkbox" ${item.is_featured ? "checked" : ""}>
                  <span>Produk unggulan</span>
                </label>

                <label class="field compact-field">
                  <span>Urutan tampil</span>
                  <input class="input" name="sort_order" type="number" step="1" value="${Number(item.sort_order || 0)}">
                </label>
              </div>

              <label class="field">
                <span>Ketentuan jaminan</span>
                <input
                  class="input"
                  name="guarantee_note"
                  value="${esc(item.guarantee_note || "")}"
                  maxlength="500"
                  placeholder="Contoh: KTP asli atau deposit Rp200.000"
                >
              </label>

              <button id="saveRentalButton" class="btn" type="submit">
                ${editingItem ? "Simpan Perubahan" : "Tambah Item"}
              </button>
            </form>
          </section>

          <section>
            <div class="admin-list-heading">
              <div>
                <h3>Daftar Sewa Item</h3>
                <p class="muted">
                  ${rentals.length} item sewa tersimpan.
                </p>
              </div>

              <div class="actions catalog-tools">
                <button id="downloadCatalogTemplateCsv" class="btn secondary small" type="button">📥 Template CSV</button>
                <button id="downloadCatalogTemplateExcel" class="btn secondary small" type="button">📥 Template Excel</button>
                <button id="exportCatalogCsv" class="btn secondary small" type="button">Ekspor CSV</button>
                <label class="btn secondary small catalog-import-label">Impor CSV<input id="importCatalogCsv" type="file" accept=".csv,text/csv" hidden></label>
                <button id="viewArchivedCatalog" class="btn secondary small" type="button">Arsip</button>
                <button id="refreshRentals" class="btn secondary small" type="button">Muat Ulang</button>
              </div>
            </div>

            <div class="admin-catalog-filter">
              <label class="field">
                <span>Cari item</span>
                <input id="adminCatalogSearch" class="input" type="search" placeholder="Cari nama, kategori, atau deskripsi" autocomplete="off">
              </label>
              <label class="field">
                <span>Filter kategori</span>
                <select id="adminCatalogCategory" class="input">
                  <option value="">Semua kategori</option>
                  ${categories
                    .filter((category) => category.is_active !== false)
                    .sort((a, b) => a.name.localeCompare(b.name, "id"))
                    .map(
                      (category) =>
                        `<option value="${esc(category.slug)}">${esc(category.name)}</option>`,
                    )
                    .join("")}
                </select>
              </label>
              <label class="field">
                <span>Status</span>
                <select id="adminCatalogStatus" class="input">
                  <option value="">Semua status</option>
                  <option value="active">Aktif</option>
                  <option value="inactive">Nonaktif</option>
                  <option value="available">Stok tersedia</option>
                  <option value="empty">Stok kosong</option>
                </select>
              </label>
              <button id="adminCatalogReset" class="btn secondary" type="button">Reset</button>
            </div>
            <p id="adminCatalogResult" class="muted admin-catalog-result" aria-live="polite"></p>

            <div class="admin-catalog-list">
              ${
                rentals.map(renderRentalCard).join("") ||
                `
                <div class="notice">
                  Belum ada item sewa. Tambahkan melalui formulir.
                </div>
              `
              }
            </div>
          </section>
        </div>`;

        bindRentalEvents();
      }

      function renderRentalCard(item) {
        return `
        <article
          class="card admin-rental-card"
          data-catalog-card
          data-search="${esc(`${item.title} ${item.description || ""} ${item.item_categories?.name || ""}`.toLocaleLowerCase("id"))}"
          data-category="${esc(item.item_categories?.slug || "")}"
          data-active="${item.is_active ? "true" : "false"}"
          data-stock="${Number(item.stock || 0)}"
        >
          <img src="${esc(item.image_url)}" alt="${esc(item.title)}">

          <div class="admin-rental-body">
            <div class="row">
              <span class="badge">${esc(item.item_categories?.name || "Sewa Item")}</span>
              <span class="${item.is_active ? "admin-active" : "admin-inactive"}">
                ${item.is_active ? "Aktif" : "Nonaktif"}
              </span>
            </div>

            <h3>${esc(item.title)}</h3>
            ${item.is_featured ? '<span class="catalog-featured-badge">★ Produk unggulan</span>' : ""}
            <p class="muted admin-clamp">${esc(item.description || "")}</p>

            <div class="admin-rental-summary">
              <strong>Sewa ${rupiah(item.price)}</strong>
              <span>${Number(item.stock || 0)} stok</span>
              ${item.sale_enabled ? `<span>Jual ${rupiah(item.sale_price || 0)}</span>` : ""}
            </div>

            <div class="inventory-status-pills">
              <span>Tersedia ${Number((item.inventory_units || []).filter((unit) => unit.status === "available").length || item.stock || 0)}</span>
              <span>Disewa ${Number((item.inventory_units || []).filter((unit) => unit.status === "rented").length)}</span>
              <span>Rusak ${Number((item.inventory_units || []).filter((unit) => unit.status === "damaged").length)}</span>
              <span>Perawatan ${Number((item.inventory_units || []).filter((unit) => unit.status === "maintenance").length)}</span>
            </div>

            ${Number(item.deposit || 0) > 0 ? `<p class="catalog-deposit">Deposit ${rupiah(item.deposit)}</p>` : ""}

            ${
              item.requires_guarantee
                ? `
              <p class="admin-rental-guarantee">
                🔐 ${esc(item.guarantee_note || "Jaminan wajib")}
              </p>
            `
                : ""
            }

            <div class="actions">
              <button
                class="btn secondary small"
                type="button"
                data-edit-rental="${item.id}"
              >
                Edit
              </button>

              <button
                class="btn secondary small"
                type="button"
                data-toggle-rental="${item.id}"
              >
                ${item.is_active ? "Nonaktifkan" : "Aktifkan"}
              </button>

              <button
                class="btn danger small"
                type="button"
                data-delete-rental="${item.id}"
              >
                Arsipkan
              </button>

              <button class="btn secondary small" type="button" data-duplicate-rental="${item.id}">Duplikasi</button>
            </div>
          </div>
        </article>`;
      }

      function bindRentalEvents() {
        const form = document.getElementById("rentalForm");
        const titleInput = document.getElementById("rentalTitle");
        const slugInput = document.getElementById("rentalSlug");
        const imageInput = document.getElementById("rentalImageUrl");
        const previewWrap = document.getElementById("rentalPreviewWrap");
        const preview = document.getElementById("rentalPreview");

        let slugEdited = Boolean(editingItem?.slug);

        titleInput.addEventListener("input", () => {
          if (!slugEdited) slugInput.value = slugify(titleInput.value);
        });

        slugInput.addEventListener("input", () => {
          slugEdited = true;
          slugInput.value = slugify(slugInput.value);
        });

        preview.addEventListener("error", () => {
          previewWrap.classList.add("hidden");
        });

        setupCatalogEntryTables(form);
        form.addEventListener("submit", saveRental);
        document
          .getElementById("catalogPrimaryUpload")
          ?.addEventListener("change", uploadCatalogPrimaryImage);
        document
          .getElementById("catalogGalleryUpload")
          ?.addEventListener("change", uploadCatalogImages);

        document
          .getElementById("cancelRentalEdit")
          ?.addEventListener("click", () => {
            editingItem = null;
            renderRentalTab();
          });

        document
          .getElementById("refreshRentals")
          .addEventListener("click", async () => {
            await refreshItems();
            renderRentalTab();
            showAdminMessage("Daftar item sewa dimuat ulang.", "success");
          });
        document
          .getElementById("downloadCatalogTemplateCsv")
          .addEventListener("click", downloadCatalogTemplateCsv);
        document
          .getElementById("downloadCatalogTemplateExcel")
          .addEventListener("click", downloadCatalogTemplateExcel);
        document
          .getElementById("exportCatalogCsv")
          .addEventListener("click", exportCatalogCsv);
        document
          .getElementById("importCatalogCsv")
          .addEventListener("change", importCatalogCsv);
        document
          .getElementById("viewArchivedCatalog")
          .addEventListener("click", renderArchivedCatalog);

        const catalogSearch = document.getElementById("adminCatalogSearch");
        const catalogCategory = document.getElementById("adminCatalogCategory");
        const catalogStatus = document.getElementById("adminCatalogStatus");
        const applyCatalogFilter = () => {
          const keyword = catalogSearch.value.trim().toLocaleLowerCase("id");
          let visible = 0;
          document.querySelectorAll("[data-catalog-card]").forEach((card) => {
            const statusMatch =
              !catalogStatus.value ||
              (catalogStatus.value === "active" &&
                card.dataset.active === "true") ||
              (catalogStatus.value === "inactive" &&
                card.dataset.active === "false") ||
              (catalogStatus.value === "available" &&
                Number(card.dataset.stock) > 0) ||
              (catalogStatus.value === "empty" &&
                Number(card.dataset.stock) < 1);
            const matches =
              (!keyword || card.dataset.search.includes(keyword)) &&
              (!catalogCategory.value ||
                card.dataset.category === catalogCategory.value) &&
              statusMatch;
            card.classList.toggle("hidden", !matches);
            if (matches) visible += 1;
          });
          document.getElementById("adminCatalogResult").textContent =
            `${visible} dari ${rentalItems().length} item ditampilkan`;
        };
        catalogSearch.addEventListener("input", applyCatalogFilter);
        catalogCategory.addEventListener("change", applyCatalogFilter);
        catalogStatus.addEventListener("change", applyCatalogFilter);
        document
          .getElementById("adminCatalogReset")
          .addEventListener("click", () => {
            catalogSearch.value = "";
            catalogCategory.value = "";
            catalogStatus.value = "";
            applyCatalogFilter();
            catalogSearch.focus();
          });
        applyCatalogFilter();

        document.querySelectorAll("[data-edit-rental]").forEach((button) => {
          button.addEventListener("click", () => {
            editingItem =
              rentalItems().find(
                (item) => item.id === button.dataset.editRental,
              ) || null;

            renderRentalTab();
            window.scrollTo({ top: 0, behavior: "smooth" });
          });
        });

        document.querySelectorAll("[data-toggle-rental]").forEach((button) => {
          button.addEventListener("click", () => {
            toggleItem(button.dataset.toggleRental, "rental");
          });
        });

        document.querySelectorAll("[data-delete-rental]").forEach((button) => {
          button.addEventListener("click", () => {
            deleteItem(button.dataset.deleteRental, "rental");
          });
        });
        document
          .querySelectorAll("[data-duplicate-rental]")
          .forEach((button) => {
            button.addEventListener("click", () =>
              duplicateRental(button.dataset.duplicateRental),
            );
          });
      }

      function csvCell(value) {
        const text = String(value ?? "");
        return /[",\r\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
      }

      function parseCsv(text) {
        const rows = [];
        let row = [],
          cell = "",
          quoted = false;
        for (let index = 0; index < text.length; index += 1) {
          const char = text[index];
          if (quoted && char === '"' && text[index + 1] === '"') {
            cell += '"';
            index += 1;
          } else if (char === '"') quoted = !quoted;
          else if (char === "," && !quoted) {
            row.push(cell);
            cell = "";
          } else if ((char === "\n" || char === "\r") && !quoted) {
            if (char === "\r" && text[index + 1] === "\n") index += 1;
            row.push(cell);
            if (row.some((value) => value !== "")) rows.push(row);
            row = [];
            cell = "";
          } else cell += char;
        }
        row.push(cell);
        if (row.some((value) => value !== "")) rows.push(row);
        const headers = rows.shift()?.map((header) => header.trim()) || [];
        return rows.map((values) =>
          Object.fromEntries(
            headers.map((header, index) => [header, values[index] ?? ""]),
          ),
        );
      }

      function catalogRelationText(item, key) {
        if (key === "gallery_urls")
          return (item.item_images || [])
            .filter((image) => !image.is_primary)
            .map((image) => image.image_url)
            .join(";");
        if (key === "variants")
          return (item.item_variants || [])
            .map(
              (variant) =>
                `${variant.name}|${variant.capacity || ""}|${variant.stock}`,
            )
            .join(";");
        if (key === "inventory_units")
          return (item.inventory_units || [])
            .map(
              (unit) =>
                `${unit.inventory_number}|${unit.condition}|${unit.status}|${unit.notes || ""}`,
            )
            .join(";");
        return (item.item_price_tiers || [])
          .map((tier) => {
            const variant = (item.item_variants || []).find(
              (row) => row.id === tier.variant_id,
            );
            return `${variant?.name || "Semua Varian"}|${tier.label}|${tier.duration_days}|${tier.price}`;
          })
          .join(";");
      }

      function catalogTemplateRows() {
        return [
          [
            "category", "title", "slug", "description", "image_url",
            "gallery_urls", "price", "deposit", "stock", "is_featured",
            "sort_order", "requires_guarantee", "guarantee_note", "is_active",
            "variants", "inventory_units", "price_tiers",
          ],
          [
            "Tenda", "Tenda Dome 2P", "tenda-dome-2p",
            "Tenda kapasitas 2 orang", "", "", "25000", "0", "10",
            "false", "0", "true", "KTP asli atau deposit Rp200.000", "true",
            "", "", "Semua Varian|1 hari|1|25000;Semua Varian|2 hari|2|48000;Semua Varian|1 hari pelajar|1|20000",
          ],
        ];
      }

      function downloadBytes(filename, blob) {
        const url = URL.createObjectURL(blob);
        const link = document.createElement("a");
        link.href = url;
        link.download = filename;
        link.rel = "noopener";
        link.style.display = "none";
        document.body.appendChild(link);
        link.click();
        setTimeout(() => {
          link.remove();
          URL.revokeObjectURL(url);
        }, 1500);
      }

      function templateTimestamp() {
        const d = new Date();
        const pad = (n) => String(n).padStart(2, "0");
        return `${d.getFullYear()}${pad(d.getMonth()+1)}${pad(d.getDate())}-${pad(d.getHours())}${pad(d.getMinutes())}${pad(d.getSeconds())}`;
      }

      function downloadCatalogTemplateCsv() {
        const rows = catalogTemplateRows();
        const guide = [
          ["PETUNJUK: title dan slug wajib diisi."],
          ["variants: Nama Varian|Kapasitas|Stok;Nama Varian|Kapasitas|Stok"],
          ["price_tiers: Nama Varian|Label|Durasi Hari|Harga;..."],
          ["price dapat digunakan sebagai harga jual / harga utama item."],
        ];
        const csv = "\\ufeff" + [...rows, ...guide]
          .map((row) => row.map(csvCell).join(","))
          .join("\\r\\n");
        downloadBytes(
          `template-import-item-aoc-${templateTimestamp()}.csv`,
          new Blob([csv], { type: "text/csv;charset=utf-8" }),
        );
        showAdminMessage("Template CSV berhasil diunduh.", "success");
      }

      function downloadCatalogTemplateExcel() {
        const rows = catalogTemplateRows();
        const escHtml = (value) => String(value ?? "")
          .replace(/&/g, "&amp;")
          .replace(/</g, "&lt;")
          .replace(/>/g, "&gt;")
          .replace(/"/g, "&quot;");
        const table = rows.map((row) =>
          `<tr>${row.map((cell) => `<td>${escHtml(cell)}</td>`).join("")}</tr>`
        ).join("");
        const html = `<!DOCTYPE html><html><head><meta charset="UTF-8"></head><body><table>${table}</table></body></html>`;
        downloadBytes(
          `template-import-item-aoc-${templateTimestamp()}.xls`,
          new Blob([html], { type: "application/vnd.ms-excel;charset=utf-8" }),
        );
        showAdminMessage("Template Excel berhasil diunduh.", "success");
      }

      function exportCatalogCsv() {
        const headers = [
          "category",
          "title",
          "slug",
          "description",
          "image_url",
          "gallery_urls",
          "price",
          "deposit",
          "stock",
          "is_featured",
          "sort_order",
          "requires_guarantee",
          "guarantee_note",
          "is_active",
          "variants",
          "inventory_units",
          "price_tiers",
        ];
        const rows = rentalItems().map((item) => [
          item.item_categories?.name || "",
          item.title,
          item.slug,
          item.description,
          item.image_url,
          catalogRelationText(item, "gallery_urls"),
          item.price,
          item.deposit || 0,
          item.stock,
          item.is_featured,
          item.sort_order || 0,
          item.requires_guarantee,
          item.guarantee_note || "",
          item.is_active,
          catalogRelationText(item, "variants"),
          catalogRelationText(item, "inventory_units"),
          catalogRelationText(item, "price_tiers"),
        ]);
        const csv =
          "\ufeff" +
          [headers, ...rows]
            .map((row) => row.map(csvCell).join(","))
            .join("\r\n");
        const url = URL.createObjectURL(
          new Blob([csv], { type: "text/csv;charset=utf-8" }),
        );
        const link = document.createElement("a");
        link.href = url;
        link.download = `katalog-abidzar-${new Date().toISOString().slice(0, 10)}.csv`;
        link.click();
        URL.revokeObjectURL(url);
      }

      async function importCatalogCsv(event) {
        const file = event.target.files?.[0];
        if (!file) return;
        try {
          const rows = parseCsv(await file.text());
          if (!rows.length) throw new Error("CSV tidak memiliki data.");
          let processed = 0;
          for (const row of rows) {
            const categoryId = await resolveCategoryId(row.category);
            const payload = {
              type: "product",
              title: String(row.title || "").trim(),
              slug: slugify(row.slug || row.title),
              description: row.description || "",
              image_url: row.image_url || "",
              price: Number(row.price || 0),
              deposit: Number(row.deposit || 0),
              stock: Math.max(0, Number(row.stock || 0)),
              category_id: categoryId,
              is_featured: String(row.is_featured).toLowerCase() === "true",
              sort_order: Number(row.sort_order || 0),
              requires_guarantee:
                String(row.requires_guarantee).toLowerCase() === "true",
              guarantee_note: row.guarantee_note || null,
              is_active: String(row.is_active).toLowerCase() !== "false",
              archived_at: null,
            };
            if (!payload.title || !payload.slug)
              throw new Error("Kolom title dan slug wajib diisi.");
            const { data, error } = await supabase
              .from("items")
              .upsert(payload, { onConflict: "slug" })
              .select("id")
              .single();
            if (error) throw error;
            await syncRentalRelations(
              data.id,
              {
                gallery_urls: String(row.gallery_urls || "")
                  .split(";")
                  .join("\n"),
                variants: String(row.variants || "")
                  .split(";")
                  .join("\n"),
                inventory_units: String(row.inventory_units || "")
                  .split(";")
                  .join("\n"),
                price_tiers: String(row.price_tiers || "")
                  .split(";")
                  .join("\n"),
              },
              payload.image_url,
              payload.title,
            );
            processed += 1;
          }
          await refreshItems();
          renderRentalTab();
          showAdminMessage(`${processed} produk berhasil diimpor.`, "success");
        } catch (error) {
          showAdminMessage(`Impor CSV gagal: ${error.message}`, "error");
        } finally {
          event.target.value = "";
        }
      }

      async function duplicateRental(id) {
        const source = rentalItems().find((item) => item.id === id);
        if (!source) return;
        const suffix = Date.now().toString().slice(-6);
        const payload = { ...source };
        [
          "id",
          "created_at",
          "updated_at",
          "item_categories",
          "item_images",
          "item_variants",
          "inventory_units",
          "item_price_tiers",
        ].forEach((key) => delete payload[key]);
        payload.title = `${source.title} (Salinan)`;
        payload.slug = `${source.slug}-copy-${suffix}`;
        payload.is_active = false;
        payload.is_featured = false;
        const { data, error } = await supabase
          .from("items")
          .insert(payload)
          .select("id")
          .single();
        if (error) return showAdminMessage(error.message, "error");
        await syncRentalRelations(
          data.id,
          {
            gallery_urls: catalogRelationText(source, "gallery_urls")
              .split(";")
              .join("\n"),
            variants: catalogRelationText(source, "variants")
              .split(";")
              .join("\n"),
            inventory_units: "",
            price_tiers: catalogRelationText(source, "price_tiers")
              .split(";")
              .join("\n"),
          },
          source.image_url,
          payload.title,
        );
        await refreshItems();
        renderRentalTab();
        showAdminMessage(
          "Produk berhasil diduplikasi dalam status nonaktif. Nomor inventaris tidak disalin.",
          "success",
        );
      }

      async function renderArchivedCatalog() {
        const content = document.getElementById("adminContent");
        content.innerHTML = '<div class="notice">Memuat arsip katalog...</div>';
        const { data, error } = await supabase
          .from("items")
          .select("id,title,slug,image_url,archived_at,type")
          .not("archived_at", "is", null)
          .order("archived_at", { ascending: false });
        if (error) return showAdminMessage(error.message, "error");
        content.innerHTML = `
          <div class="admin-list-heading"><div><h3>Arsip Katalog</h3><p class="muted">Produk tetap tersimpan untuk menjaga riwayat pesanan.</p></div><button id="backFromArchive" class="btn secondary small" type="button">Kembali</button></div>
          <div class="archived-catalog-list">
            ${(data || []).map((item) => `<article class="card archived-catalog-card"><img src="${esc(item.image_url)}" alt="${esc(item.title)}"><div><span class="badge">${item.type === "trip" ? "Trip" : "Sewa"}</span><h3>${esc(item.title)}</h3><small>Diarsipkan ${new Date(item.archived_at).toLocaleString("id-ID")}</small></div><button class="btn small" type="button" data-restore-item="${item.id}">Pulihkan</button></article>`).join("") || '<div class="notice">Arsip masih kosong.</div>'}
          </div>`;
        document
          .getElementById("backFromArchive")
          .addEventListener("click", renderRentalTab);
        document.querySelectorAll("[data-restore-item]").forEach((button) =>
          button.addEventListener("click", async () => {
            const { error: restoreError } = await supabase
              .from("items")
              .update({ archived_at: null, is_active: false })
              .eq("id", button.dataset.restoreItem);
            if (restoreError)
              return showAdminMessage(restoreError.message, "error");
            await refreshItems();
            renderArchivedCatalog();
            showAdminMessage(
              "Produk dipulihkan dalam status nonaktif.",
              "success",
            );
          }),
        );
      }

      function parseCatalogLines(value, expectedParts) {
        return String(value || "")
          .split(/\r?\n/)
          .map((line) => line.trim())
          .filter(Boolean)
          .map((line, index) => {
            const parts = line.split("|").map((part) => part.trim());
            if (parts.length < expectedParts)
              throw new Error(
                `Format baris ${index + 1} tidak lengkap: ${line}`,
              );
            return parts;
          });
      }

      async function uploadCatalogFile(file) {
        if (file.size > 8 * 1024 * 1024)
          throw new Error(`${file.name} lebih besar dari 8 MB.`);
        const allowedTypes = [
          "image/jpeg",
          "image/png",
          "image/webp",
          "image/gif",
        ];
        if (!allowedTypes.includes(file.type))
          throw new Error(`${file.name} bukan format gambar yang didukung.`);
        const extension = file.name.split(".").pop()?.toLowerCase() || "jpg";
        const path = `${new Date().toISOString().slice(0, 10)}/${crypto.randomUUID()}.${extension}`;
        const { error } = await supabase.storage
          .from("catalog")
          .upload(path, file, { cacheControl: "31536000", upsert: false });
        if (error) throw error;
        return supabase.storage.from("catalog").getPublicUrl(path).data
          .publicUrl;
      }

      async function uploadCatalogPrimaryImage(event) {
        const file = event.target.files?.[0];
        if (!file) return;
        const status = document.getElementById("catalogPrimaryUploadStatus");
        const imageInput = document.getElementById("rentalImageUrl");
        const previewWrap = document.getElementById("rentalPreviewWrap");
        const preview = document.getElementById("rentalPreview");
        event.target.disabled = true;
        status.textContent = "Mengupload gambar utama...";
        try {
          const publicUrl = await uploadCatalogFile(file);
          imageInput.value = publicUrl;
          preview.src = publicUrl;
          previewWrap.classList.remove("hidden");
          status.textContent = "Gambar utama berhasil diupload.";
        } catch (error) {
          status.textContent = `Upload gagal: ${error.message}`;
          event.target.value = "";
        } finally {
          event.target.disabled = false;
        }
      }

      async function uploadTripPrimaryImage(event) {
        const file = event.target.files?.[0];
        if (!file) return;
        const status = document.getElementById("tripPrimaryUploadStatus");
        const imageInput = document.getElementById("tripImageUrl");
        const previewWrap = document.getElementById("tripPreviewWrap");
        const preview = document.getElementById("tripPreview");
        event.target.disabled = true;
        status.textContent = "Mengupload gambar utama...";
        try {
          const publicUrl = await uploadCatalogFile(file);
          imageInput.value = publicUrl;
          preview.src = publicUrl;
          previewWrap.classList.remove("hidden");
          status.textContent = "Gambar utama berhasil diupload.";
        } catch (error) {
          status.textContent = `Upload gagal: ${error.message}`;
          event.target.value = "";
        } finally {
          event.target.disabled = false;
        }
      }

      async function uploadCatalogImages(event) {
        const files = [...(event.target.files || [])];
        if (!files.length) return;
        const status = document.getElementById("catalogUploadStatus");
        const textarea = document.querySelector('[name="gallery_urls"]');
        const uploaded = [];
        status.textContent = `Mengupload 0/${files.length} foto...`;
        try {
          for (let index = 0; index < files.length; index += 1) {
            const file = files[index];
            uploaded.push(await uploadCatalogFile(file));
            status.textContent = `Mengupload ${index + 1}/${files.length} foto...`;
          }
          textarea.value = [textarea.value.trim(), ...uploaded]
            .filter(Boolean)
            .join("\n");
          status.textContent = `${uploaded.length} foto berhasil diupload.`;
        } catch (error) {
          status.textContent = `Upload gagal: ${error.message}`;
        } finally {
          event.target.value = "";
        }
      }

      async function resolveCategoryId(name) {
        const categoryName = String(name || "").trim();
        if (!categoryName) return null;
        const existing = categories.find(
          (category) =>
            category.name.toLowerCase() === categoryName.toLowerCase(),
        );
        if (existing) return existing.id;
        const { data, error } = await supabase
          .from("item_categories")
          .insert({ name: categoryName, slug: slugify(categoryName) })
          .select("id")
          .single();
        if (error) throw error;
        categories.push({
          id: data.id,
          name: categoryName,
          slug: slugify(categoryName),
        });
        return data.id;
      }

      async function syncRentalRelations(itemId, values, primaryImage, title) {
        const gallery = String(values.gallery_urls || "")
          .split(/\r?\n/)
          .map((url) => url.trim())
          .filter(Boolean);
        const variants = parseCatalogLines(values.variants, 3);
        const units = parseCatalogLines(values.inventory_units, 3);
        const tiers = parseCatalogLines(values.price_tiers, 4);

        const tables = [
          "item_images",
          "item_variants",
          "inventory_units",
          "item_price_tiers",
        ];
        for (const table of tables) {
          const { error } = await supabase
            .from(table)
            .delete()
            .eq("item_id", itemId);
          if (error) throw error;
        }

        const imageRows = [primaryImage, ...gallery]
          .filter(Boolean)
          .filter((url, index, all) => all.indexOf(url) === index)
          .map((imageUrl, index) => ({
            item_id: itemId,
            image_url: imageUrl,
            alt_text: title,
            is_primary: index === 0,
            sort_order: index,
          }));
        if (imageRows.length) {
          const { error } = await supabase
            .from("item_images")
            .insert(imageRows);
          if (error) throw error;
        }
        let savedVariants = [];
        if (variants.length) {
          const { data, error } = await supabase.from("item_variants").insert(
            variants.map(([name, capacity, stock], index) => ({
              item_id: itemId,
              name,
              capacity: capacity || null,
              price_adjustment: 0,
              stock: Math.max(0, Number(stock || 0)),
              sort_order: index,
            })),
          ).select("id,name");
          if (error) throw error;
          savedVariants = data || [];
        }
        if (units.length) {
          const validConditions = ["new", "good", "fair", "damaged"];
          const validStatuses = [
            "available",
            "rented",
            "damaged",
            "maintenance",
            "retired",
          ];
          const rows = units.map(([number, condition, status, notes]) => {
            if (!validConditions.includes(condition))
              throw new Error(`Kondisi inventaris ${number} tidak valid.`);
            if (!validStatuses.includes(status))
              throw new Error(`Status inventaris ${number} tidak valid.`);
            return {
              item_id: itemId,
              inventory_number: number,
              condition,
              status,
              notes: notes || null,
            };
          });
          const { error } = await supabase.from("inventory_units").insert(rows);
          if (error) throw error;
        }
        if (tiers.length) {
          const { error } = await supabase.from("item_price_tiers").insert(
            tiers.map(([variantName, label, days, price], index) => {
              const variant = savedVariants.find(
                (row) => row.name.toLowerCase() === variantName.toLowerCase(),
              );
              if (!variant && variantName.toLowerCase() !== "semua varian")
                throw new Error(`Varian harga ${variantName} tidak ditemukan.`);
              return {
              item_id: itemId,
              variant_id: variant?.id || null,
              label,
              duration_days: Math.max(1, Number(days)),
              price: Math.max(0, Number(price)),
              sort_order: index,
              };
            }),
          );
          if (error) throw error;
        }
      }

      async function saveRental(event) {
        event.preventDefault();

        const form = event.currentTarget;
        const values = Object.fromEntries(new FormData(form));
        const formData = new FormData(form);
        const button = document.getElementById("saveRentalButton");
        const wasEditing = Boolean(editingItem);

        if (button.disabled) return;

        // Validasi dilakukan sebelum INSERT agar tidak membuat data setengah jadi.
        try {
          parseCatalogLines(values.variants, 3);
          parseCatalogLines(values.inventory_units, 3);
          parseCatalogLines(values.price_tiers, 4);
        } catch (error) {
          showAdminMessage(error.message, "error");
          return;
        }

        let categoryId = null;
        try {
          // Untuk item baru, kategori dibuat di server dalam transaksi yang sama.
          // Ini menghindari kegagalan INSERT hanya karena kategori baru belum ada.
          if (wasEditing) categoryId = await resolveCategoryId(values.category_name);
        } catch (error) {
          showAdminMessage(`Kategori gagal disimpan: ${error.message}`, "error");
          return;
        }

        const payload = {
          title: String(values.title || "").trim(),
          slug: slugify(values.slug || values.title),
          type: "product",
          description: String(values.description || "").trim(),
          image_url: String(values.image_url || "").trim() || null,
          price: Number(values.price || 0),
          sale_price: Number(values.sale_price || 0),
          stock: Number(values.stock || 0),
          sale_enabled: formData.has("sale_enabled"),
          rental_enabled: formData.has("rental_enabled"),
          category_id: categoryId,
          deposit: Number(values.deposit || 0),
          is_featured: formData.has("is_featured"),
          sort_order: Number(values.sort_order || 0),
          location: null,
          trip_date: null,
          quota: null,
          requires_guarantee: formData.has("requires_guarantee"),
          guarantee_note: String(values.guarantee_note || "").trim() || null,
          is_active: formData.has("is_active"),
        };

        if (!payload.title) {
          showAdminMessage("Nama item wajib diisi.", "error");
          return;
        }
        if (!payload.slug) {
          showAdminMessage("Slug item tidak valid.", "error");
          return;
        }
        if (!payload.description) {
          showAdminMessage("Deskripsi wajib diisi.", "error");
          return;
        }
        if (payload.price < 0 || payload.sale_price < 0 || payload.stock < 0 || payload.deposit < 0) {
          showAdminMessage("Harga, stok, dan deposit tidak boleh bernilai negatif.", "error");
          return;
        }

        button.disabled = true;
        button.textContent = wasEditing ? "Menyimpan perubahan..." : "Menambahkan item...";

        try {
          let savedItem;

          if (!wasEditing) {
            // CREATE BARU: gunakan RPC transaksional.
            // Semua tabel item + kategori + varian + inventaris + harga paket
            // disimpan dalam satu transaksi PostgreSQL. Jika satu bagian gagal,
            // seluruh INSERT di-rollback otomatis.
            const variants = parseCatalogLines(values.variants, 3).map(([name, capacity, stock]) => ({
              name,
              capacity: capacity || null,
              stock: Math.max(0, Number(stock || 0)),
            }));
            const inventory = parseCatalogLines(values.inventory_units, 3).map(([number, condition, status, notes]) => ({
              inventory_number: number,
              condition,
              status,
              notes: notes || null,
            }));
            const priceTiers = parseCatalogLines(values.price_tiers, 4).map(([variantName, label, days, price]) => ({
              variant_name: variantName,
              label,
              duration_days: Math.max(1, Number(days || 1)),
              price: Math.max(0, Number(price || 0)),
            }));
            const gallery = String(values.gallery_urls || "")
              .split(/\r?\n/)
              .map((url) => url.trim())
              .filter(Boolean);

            const { data, error } = await supabase.rpc("secure_admin_create_rental_item", {
              p_payload: payload,
              p_category_name: String(values.category_name || "").trim() || null,
              p_gallery_urls: gallery,
              p_variants: variants,
              p_inventory_units: inventory,
              p_price_tiers: priceTiers,
            });

            if (error) throw error;
            const id = data?.id || data?.item_id || data;
            if (!id) throw new Error("Server tidak mengembalikan ID item baru.");
            savedItem = { id };
          } else {
            const { data, error } = await supabase
              .from("items")
              .update(payload)
              .eq("id", editingItem.id)
              .eq("type", "product")
              .select("id")
              .single();
            if (error) throw error;
            savedItem = data;

            await syncRentalRelations(
              savedItem.id,
              values,
              payload.image_url,
              payload.title,
            );
          }

          editingItem = null;
          await refreshItems();
          renderShell();

          showAdminMessage(
            wasEditing
              ? "Item sewa berhasil diperbarui."
              : "Item sewa berhasil ditambahkan dan seluruh data berhasil disimpan.",
            "success",
          );
        } catch (error) {
          console.error("saveRental error:", error);
          const message = error?.message || String(error);
          showAdminMessage(
            message.includes("catalog.manage") || message.includes("Izin")
              ? `Tidak memiliki izin katalog: ${message}`
              : message.includes("23505") || message.toLowerCase().includes("duplicate") || message.toLowerCase().includes("unique")
                ? "Data duplikat. Periksa slug, nomor inventaris, atau kombinasi harga paket."
                : `Gagal menambahkan item: ${message}`,
            "error",
          );
        } finally {
          button.disabled = false;
          button.textContent = wasEditing ? "Simpan Perubahan" : "Tambah Item";
        }
      }

      function renderTripTab() {
        const content = document.getElementById("adminContent");
        const trips = tripItems();

        const item = editingItem || {
          title: "",
          slug: "",
          description: "",
          image_url: "",
          price: 0,
          location: "",
          trip_date: "",
          quota: 0,
          requires_guarantee: false,
          guarantee_note: "",
          is_active: true,
        };
        const detail = Array.isArray(item.trip_details)
          ? item.trip_details[0] || {}
          : item.trip_details || {};
        const localDateTime = (value) => {
          if (!value) return "";
          const date = new Date(value);
          return new Date(date.getTime() - date.getTimezoneOffset() * 60000)
            .toISOString()
            .slice(0, 16);
        };

        content.innerHTML = `
        <div class="admin-catalog-layout">
          <section class="card admin-editor-card">
            <div class="admin-editor-heading">
              <div>
                <span class="badge">Open Trip</span>
                <h3>${editingItem ? "Edit Open Trip" : "Tambah Open Trip"}</h3>
                <p class="muted">
                  Trip akan muncul pada katalog Open Trip.
                </p>
              </div>

              ${
                editingItem
                  ? `
                <button id="cancelTripEdit" class="btn secondary small" type="button">
                  Batal
                </button>
              `
                  : ""
              }
            </div>

            <form id="tripForm" class="form">
              <div class="two">
                <label class="field">
                  <span>Nama trip *</span>
                  <input
                    id="tripTitle"
                    class="input"
                    name="title"
                    value="${esc(item.title || "")}"
                    required
                    maxlength="150"
                    placeholder="Contoh: Open Trip Dieng"
                  >
                </label>

                <label class="field">
                  <span>Slug URL *</span>
                  <input
                    id="tripSlug"
                    class="input"
                    name="slug"
                    value="${esc(item.slug || "")}"
                    required
                    maxlength="160"
                    placeholder="open-trip-dieng"
                  >
                </label>
              </div>

              <div class="trip-admin-section">
                <h3>Jadwal & operasional</h3>
                <div class="notice">Tanggal keberangkatan dipilih oleh peserta saat checkout. Admin cukup mengatur lokasi dan informasi operasional.</div>
                <div class="two">
                  <label class="field"><span>Lokasi meeting point *</span><input class="input" name="meeting_point" required value="${esc(detail.meeting_point || item.location || "")}"></label>
                  <label class="field"><span>Petunjuk waktu meeting</span><input class="input" name="meeting_time" value="${esc(detail.meeting_time || "")}" placeholder="Hadir 30 menit sebelumnya"></label>
                  <label class="field"><span>Status trip *</span><select class="input" name="trip_status">${[
                    ["draft", "Draft"],
                    ["open", "Dibuka"],
                    ["full", "Penuh"],
                    ["running", "Berjalan"],
                    ["completed", "Selesai"],
                    ["cancelled", "Dibatalkan"],
                  ]
                    .map(
                      ([v, l]) =>
                        `<option value="${v}" ${detail.status === v ? "selected" : ""}>${l}</option>`,
                    )
                    .join("")}</select></label>
                  <label class="field"><span>Tingkat kesulitan</span><select class="input" name="difficulty">${[
                    ["easy", "Mudah"],
                    ["moderate", "Sedang"],
                    ["hard", "Sulit"],
                    ["extreme", "Ekstrem"],
                  ]
                    .map(
                      ([v, l]) =>
                        `<option value="${v}" ${(detail.difficulty || "moderate") === v ? "selected" : ""}>${l}</option>`,
                    )
                    .join("")}</select></label>
                  <label class="field"><span>Minimal peserta</span><input class="input" name="min_participants" type="number" min="1" value="${Number(detail.min_participants || 1)}"></label>
                  <label class="field"><span>Usia minimum</span><input class="input" name="min_age" type="number" min="0" value="${detail.min_age ?? ""}"></label>
                  <label class="field"><span>Usia maksimum</span><input class="input" name="max_age" type="number" min="0" value="${detail.max_age ?? ""}"></label>
                </div>
                <label class="field"><span>Itinerary</span><textarea class="input" name="itinerary" placeholder="Hari/jam | kegiatan">${esc(detail.itinerary || "")}</textarea></label>
                <div class="two">
                  <label class="field"><span>Fasilitas termasuk</span><textarea class="input" name="included_facilities">${esc(detail.included_facilities || "")}</textarea></label>
                  <label class="field"><span>Tidak termasuk</span><textarea class="input" name="excluded_facilities">${esc(detail.excluded_facilities || "")}</textarea></label>
                </div>
                <label class="field"><span>Perlengkapan wajib</span><textarea class="input" name="required_equipment">${esc(detail.required_equipment || "")}</textarea></label>
                <label class="field"><span>Informasi perjalanan untuk peserta</span><textarea class="input" name="travel_information" placeholder="Pesan yang akan disalin/dikirim via WhatsApp">${esc(detail.travel_information || "")}</textarea></label>
              </div>

              <label class="field">
                <span>Deskripsi *</span>
                <textarea
                  class="input"
                  name="description"
                  required
                  maxlength="3000"
                  placeholder="Fasilitas, itinerary, titik kumpul, dan ketentuan"
                >${esc(item.description || "")}</textarea>
              </label>

              <label class="field catalog-upload-field">
                <span>Upload gambar utama</span>
                <input id="tripImageUrl" name="image_url" type="hidden" value="${esc(item.image_url || "")}">
                <input id="tripPrimaryUpload" class="input" type="file" accept="image/jpeg,image/png,image/webp,image/gif">
                <small id="tripPrimaryUploadStatus" class="muted">${
                  item.image_url
                    ? "Gambar utama tersimpan. Pilih file baru untuk menggantinya."
                    : "Opsional. Pilih JPG, PNG, WEBP, atau GIF. Maksimal 8 MB."
                }</small>
              </label>
              <div id="tripPreviewWrap" class="admin-image-preview ${item.image_url ? "" : "hidden"}">
                <img id="tripPreview" src="${esc(item.image_url || "")}" alt="Preview open trip">
              </div>

              <div class="two">
                <label class="field">
                  <span>Harga per peserta *</span>
                  <input
                    class="input"
                    name="price"
                    type="number"
                    min="0"
                    step="1000"
                    value="${Number(item.price || 0)}"
                    required
                  >
                </label>

                <label class="field">
                  <span>Kuota peserta *</span>
                  <input
                    class="input"
                    name="quota"
                    type="number"
                    min="0"
                    step="1"
                    value="${Number(item.quota || 0)}"
                    required
                  >
                </label>
              </div>

              <label class="field">
                <span>Lokasi *</span>
                <input
                  class="input"
                  name="location"
                  value="${esc(item.location || "")}"
                  required
                  maxlength="200"
                >
              </label>

              <label class="admin-check">
                <input
                  name="is_active"
                  type="checkbox"
                  ${item.is_active ? "checked" : ""}
                >
                <span>Tampilkan di katalog</span>
              </label>

              <button id="saveTripButton" class="btn" type="submit">
                ${editingItem ? "Simpan Perubahan" : "Tambah Open Trip"}
              </button>
            </form>
          </section>

          <section>
            <div class="admin-list-heading">
              <div>
                <h3>Daftar Open Trip</h3>
                <p class="muted">${trips.length} trip tersimpan.</p>
              </div>
            </div>

            <div class="admin-catalog-list">
              ${
                trips.map(renderTripCard).join("") ||
                `
                <div class="notice">Belum ada open trip.</div>
              `
              }
            </div>
          </section>
        </div>`;

        bindTripEvents();
      }

      function renderTripCard(item) {
        const detail = Array.isArray(item.trip_details)
          ? item.trip_details[0] || {}
          : item.trip_details || {};
        const statusName =
          {
            draft: "Draft",
            open: "Dibuka",
            full: "Penuh",
            running: "Berjalan",
            completed: "Selesai",
            cancelled: "Dibatalkan",
          }[detail.status] || "Belum diatur";
        return `
        <article class="card admin-rental-card">
          <img src="${esc(item.image_url)}" alt="${esc(item.title)}">

          <div class="admin-rental-body">
            <div class="row">
              <span class="badge">Open Trip</span>
              <span class="${item.is_active ? "admin-active" : "admin-inactive"}">
                ${item.is_active ? "Aktif" : "Nonaktif"}
              </span>
            </div>

            <h3>${esc(item.title)}</h3>
            <p class="muted admin-clamp">${esc(item.description || "")}</p>

            <div class="admin-rental-summary">
              <strong>${rupiah(item.price)}</strong>
              <span>${Number(item.quota || 0)} kursi · ${statusName}</span>
            </div>

            <p class="admin-rental-guarantee">📅 Tanggal dipilih peserta saat memesan</p>

            <div class="actions">
              ${can("trip_participants.manage") ? `<button class="btn small" data-trip-participants="${item.id}" type="button">Peserta</button>` : ""}
              <button
                class="btn secondary small"
                data-edit-trip="${item.id}"
                type="button"
              >
                Edit
              </button>

              <button
                class="btn secondary small"
                data-toggle-trip="${item.id}"
                type="button"
              >
                ${item.is_active ? "Nonaktifkan" : "Aktifkan"}
              </button>

              <button
                class="btn danger small"
                data-delete-trip="${item.id}"
                type="button"
              >
                Hapus
              </button>
            </div>
          </div>
        </article>`;
      }

      function bindTripEvents() {
        const form = document.getElementById("tripForm");
        const title = document.getElementById("tripTitle");
        const slug = document.getElementById("tripSlug");
        let slugEdited = Boolean(editingItem?.slug);

        title.addEventListener("input", () => {
          if (!slugEdited) slug.value = slugify(title.value);
        });

        slug.addEventListener("input", () => {
          slugEdited = true;
          slug.value = slugify(slug.value);
        });

        form.addEventListener("submit", saveTrip);
        document
          .getElementById("tripPrimaryUpload")
          ?.addEventListener("change", uploadTripPrimaryImage);

        document
          .getElementById("cancelTripEdit")
          ?.addEventListener("click", () => {
            editingItem = null;
            renderTripTab();
          });

        document.querySelectorAll("[data-edit-trip]").forEach((button) => {
          button.addEventListener("click", () => {
            editingItem =
              tripItems().find((item) => item.id === button.dataset.editTrip) ||
              null;

            renderTripTab();
            window.scrollTo({ top: 0, behavior: "smooth" });
          });
        });

        document.querySelectorAll("[data-toggle-trip]").forEach((button) => {
          button.addEventListener("click", () => {
            toggleItem(button.dataset.toggleTrip, "trip");
          });
        });

        document.querySelectorAll("[data-delete-trip]").forEach((button) => {
          button.addEventListener("click", () => {
            deleteItem(button.dataset.deleteTrip, "trip");
          });
        });
        document
          .querySelectorAll("[data-trip-participants]")
          .forEach((button) => {
            button.addEventListener("click", () =>
              renderTripParticipants(button.dataset.tripParticipants),
            );
          });
      }

      async function renderTripParticipants(itemId) {
        const content = document.getElementById("adminContent");
        const trip = tripItems().find((entry) => entry.id === itemId);
        if (!trip) return;
        content.innerHTML = '<div class="notice">Memuat data peserta...</div>';
        const { data, error } = await supabase
          .from("trip_participants")
          .select("*,orders(order_number,status)")
          .eq("item_id", itemId)
          .order("seat_number");
        if (error) {
          content.innerHTML = `<div class="notice error">${esc(error.message)}<br><small>Jalankan open-trip-management.sql.</small></div>`;
          return;
        }
        const detail = Array.isArray(trip.trip_details)
          ? trip.trip_details[0] || {}
          : trip.trip_details || {};
        const baseMessage = [
          `Informasi perjalanan ${trip.title}`,
          detail.departure_at
            ? `Keberangkatan: ${new Date(detail.departure_at).toLocaleString("id-ID")}`
            : "",
          detail.meeting_point ? `Meeting point: ${detail.meeting_point}` : "",
          detail.meeting_time || "",
          detail.travel_information || "",
        ]
          .filter(Boolean)
          .join("\n");
        content.innerHTML = `
          <div class="admin-list-heading"><div><span class="badge">Peserta Open Trip</span><h2>${esc(trip.title)}</h2><p class="muted">${data.length} peserta terdaftar dari ${Number(trip.quota || 0)} kursi.</p></div><button id="backToTrips" class="btn secondary" type="button">Kembali</button></div>
          <section class="card trip-message-card"><h3>Informasi perjalanan</h3><pre>${esc(baseMessage || "Belum ada informasi perjalanan.")}</pre><button id="copyTripInfo" class="btn secondary small" type="button">Salin Informasi</button></section>
          <div class="trip-participant-grid">${
            data
              .map((participant) => {
                const digits = String(participant.phone || "")
                  .replace(/\D/g, "")
                  .replace(/^0/, "62");
                const messageText = `Halo ${participant.full_name},\n\n${baseMessage}`;
                return `<article class="card trip-participant-card"><div class="row"><strong>Kursi ${participant.seat_number} · ${esc(participant.full_name)}</strong><span class="badge">${esc(participant.status)}</span></div><p>📱 ${esc(participant.phone)} · Usia ${participant.age}</p><p>Kontak darurat: ${esc(participant.emergency_contact_name)} — ${esc(participant.emergency_contact_phone)}</p><p class="muted">Pesanan ${esc(participant.orders?.order_number || "-")} · ${esc(participant.orders?.status || "-")}</p><div class="actions"><select class="input compact-input" data-participant-status="${participant.id}">${[
                  ["registered", "Terdaftar"],
                  ["confirmed", "Dikonfirmasi"],
                  ["attended", "Hadir"],
                  ["cancelled", "Batal"],
                ]
                  .map(
                    ([v, l]) =>
                      `<option value="${v}" ${participant.status === v ? "selected" : ""}>${l}</option>`,
                  )
                  .join(
                    "",
                  )}</select><a class="btn small" target="_blank" rel="noopener" href="https://wa.me/${digits}?text=${encodeURIComponent(messageText)}">WhatsApp</a></div></article>`;
              })
              .join("") || '<div class="notice">Belum ada peserta.</div>'
          }</div>`;
        document.getElementById("backToTrips").onclick = renderTripTab;
        document.getElementById("copyTripInfo").onclick = async () => {
          await navigator.clipboard.writeText(baseMessage);
          showAdminMessage("Informasi perjalanan berhasil disalin.", "success");
        };
        document
          .querySelectorAll("[data-participant-status]")
          .forEach((select) => {
            select.addEventListener("change", async () => {
              const { error: statusError } = await supabase.rpc(
                "secure_admin_update_participant_status",
                { a: select.dataset.participantStatus, b: select.value },
              );
              showAdminMessage(
                statusError
                  ? statusError.message
                  : "Status peserta diperbarui.",
                statusError ? "error" : "success",
              );
            });
          });
      }

      async function saveTrip(event) {
        event.preventDefault();

        const form = event.currentTarget;
        const values = Object.fromEntries(new FormData(form));
        const formData = new FormData(form);
        const button = document.getElementById("saveTripButton");

        const payload = {
          title: String(values.title || "").trim(),
          slug: slugify(values.slug),
          type: "trip",
          description: String(values.description || "").trim(),
          image_url: String(values.image_url || "").trim(),
          price: Number(values.price || 0),
          stock: 0,
          location: String(values.location || "").trim(),
          trip_date: null,
          quota: Number(values.quota || 0),
          requires_guarantee: false,
          guarantee_note: null,
          is_active: formData.has("is_active"),
        };

        if (!payload.image_url) {
          showAdminMessage(
            "Upload gambar utama terlebih dahulu sampai prosesnya berhasil.",
            "error",
          );
          return;
        }

        button.disabled = true;
        button.textContent = "Menyimpan...";

        const query = editingItem
          ? supabase
              .from("items")
              .update(payload)
              .eq("id", editingItem.id)
              .eq("type", "trip")
              .select("id")
              .single()
          : supabase.from("items").insert(payload).select("id").single();

        const { data: savedTrip, error } = await query;

        button.disabled = false;
        button.textContent = editingItem
          ? "Simpan Perubahan"
          : "Tambah Open Trip";

        if (error) {
          showAdminMessage(
            error.code === "23505"
              ? "Slug sudah digunakan. Gunakan slug lain."
              : error.message,
            "error",
          );
          return;
        }

        const nullableNumber = (value) =>
          value === "" || value == null ? null : Number(value);
        const detailsPayload = {
          item_id: savedTrip.id,
          departure_at: null,
          return_at: null,
          meeting_point: String(values.meeting_point || "").trim(),
          meeting_time: String(values.meeting_time || "").trim() || null,
          itinerary: String(values.itinerary || "").trim() || null,
          included_facilities:
            String(values.included_facilities || "").trim() || null,
          excluded_facilities:
            String(values.excluded_facilities || "").trim() || null,
          difficulty: values.difficulty || "moderate",
          min_age: nullableNumber(values.min_age),
          max_age: nullableNumber(values.max_age),
          required_equipment:
            String(values.required_equipment || "").trim() || null,
          min_participants: Math.max(1, Number(values.min_participants || 1)),
          registration_deadline: null,
          status: values.trip_status || "draft",
          travel_information:
            String(values.travel_information || "").trim() || null,
          updated_at: new Date().toISOString(),
        };
        const { error: detailError } = await supabase
          .from("trip_details")
          .upsert(detailsPayload, { onConflict: "item_id" });
        if (detailError) {
          showAdminMessage(
            `Trip tersimpan, tetapi detail gagal: ${detailError.message}. Jalankan open-trip-management.sql.`,
            "error",
          );
          return;
        }

        editingItem = null;
        await refreshItems();
        renderShell();
        showAdminMessage("Open trip berhasil disimpan.", "success");
      }

      async function toggleItem(id, expectedType) {
        const item = items.find((entry) => entry.id === id);
        if (
          !item ||
          item.type !== (expectedType === "rental" ? "product" : "trip")
        ) {
          return;
        }

        const { error } = await supabase
          .from("items")
          .update({ is_active: !item.is_active })
          .eq("id", id);

        if (error) {
          showAdminMessage(error.message, "error");
          return;
        }

        await refreshItems();
        renderActiveTab();
        showAdminMessage(
          `Item berhasil ${item.is_active ? "dinonaktifkan" : "diaktifkan"}.`,
          "success",
        );
      }

      async function deleteItem(id, expectedType) {
        const expectedDatabaseType =
          expectedType === "rental" ? "product" : "trip";

        const item = items.find((entry) => entry.id === id);

        if (!item || item.type !== expectedDatabaseType) return;

        const confirmed = confirm(
          `Arsipkan "${item.title}"?\n\nProduk hilang dari katalog tetapi riwayat pesanan tetap aman.`,
        );

        if (!confirmed) return;

        const { error } = await supabase
          .from("items")
          .update({ archived_at: new Date().toISOString(), is_active: false })
          .eq("id", id)
          .eq("type", expectedDatabaseType);

        if (error) {
          showAdminMessage(error.message, "error");
          return;
        }

        editingItem = null;
        await refreshItems();
        renderActiveTab();
        showAdminMessage(
          "Item berhasil diarsipkan tanpa menghapus riwayat.",
          "success",
        );
      }

      async function refreshItems() {
        itemsLoaded = false;
        categoriesLoaded = false;
        itemsLoadPromise = null;
        await loadItemsData();
      }

      function renderOrdersTab() {
        const content = document.getElementById("adminContent");
        const filteredOrders = filterOrdersByStore(orders.filter((order) => {
          const needle = orderSearch.toLowerCase();
          const matchesSearch =
            !needle ||
            [order.order_number, order.customer_name, order.phone].some(
              (value) =>
                String(value || "")
                  .toLowerCase()
                  .includes(needle),
            );
          const matchesStatus =
            (orderStatusFilter === "all" && order.status !== "cancelled") ||
            orderStatusFilter === "all_with_cancelled" ||
            order.status === orderStatusFilter;
          const date = String(order.created_at || "").slice(0, 10);
          return (
            matchesSearch &&
            matchesStatus &&
            (!orderDateFrom || date >= orderDateFrom) &&
            (!orderDateTo || date <= orderDateTo)
          );
        }));

        content.innerHTML = `
        <div class="admin-list-heading">
          <div>
            <h3>Pesanan Pelanggan</h3>
            <p class="muted">${filteredOrders.length} pesanan ditampilkan · ${orders.filter((order) => order.status === "cancelled").length} dibatalkan disembunyikan dari daftar aktif.</p>
          </div>

          <div class="actions"><button id="exportOrdersCsv" class="btn secondary small" type="button">Ekspor CSV</button><button id="exportOrdersExcel" class="btn secondary small" type="button">Ekspor Excel</button>${can("*") && orders.length ? '<button id="deleteAllOrders" class="btn danger small" type="button">Hapus Semua Pesanan</button>' : ""}<button id="refreshOrders" class="btn secondary small" type="button">Muat Ulang</button></div>
        </div>

        ${renderStoreCategoryBar()}

        <section class="card order-filter-bar"><input id="orderSearch" class="input" value="${esc(orderSearch)}" placeholder="Cari nomor pesanan, nama, atau HP"><select id="orderStatusFilter" class="input"><option value="all">Pesanan aktif</option><option value="all_with_cancelled" ${orderStatusFilter === "all_with_cancelled" ? "selected" : ""}>Semua termasuk dibatalkan</option>${Object.entries(
          statusLabels,
        )
          .map(
            ([value, label]) =>
              `<option value="${value}" ${orderStatusFilter === value ? "selected" : ""}>${label}</option>`,
          )
          .join(
            "",
          )}</select><label class="field"><span>Dari tanggal</span><input id="orderDateFrom" class="input" type="date" value="${orderDateFrom}"></label><label class="field"><span>Sampai tanggal</span><input id="orderDateTo" class="input" type="date" value="${orderDateTo}"></label><button id="resetOrderFilters" class="btn secondary" type="button">Reset</button></section>

        <div class="orders">
          ${
            filteredOrders.map(renderOrder).join("") ||
            `
            <div class="notice">Belum ada pesanan.</div>
          `
          }
        </div>`;

        document
          .getElementById("refreshOrders")
          .addEventListener("click", refreshOrders);
        document
          .getElementById("deleteAllOrders")
          ?.addEventListener("click", deleteAllOrders);

        const applyFilters = () => {
          orderSearch = document.getElementById("orderSearch").value.trim();
          orderStatusFilter =
            document.getElementById("orderStatusFilter").value;
          orderDateFrom = document.getElementById("orderDateFrom").value;
          orderDateTo = document.getElementById("orderDateTo").value;
          renderOrdersTab();
        };
        document
          .getElementById("orderSearch")
          .addEventListener("change", applyFilters);
        ["orderStatusFilter", "orderDateFrom", "orderDateTo"].forEach((id) =>
          document.getElementById(id).addEventListener("change", applyFilters),
        );
        document.getElementById("resetOrderFilters").onclick = () => {
          orderSearch = "";
          orderStatusFilter = "all";
          orderDateFrom = "";
          orderDateTo = "";
          renderOrdersTab();
        };
        document.getElementById("exportOrdersCsv").onclick = () =>
          exportOrders(filteredOrders, "csv");
        document.getElementById("exportOrdersExcel").onclick = () =>
          exportOrders(filteredOrders, "xls");

        document.querySelectorAll("[data-save-order]").forEach((button) => {
          button.addEventListener("click", () => {
            saveOrderStatus(button.dataset.saveOrder);
          });
        });
        document.querySelectorAll("[data-delete-order]").forEach((button) => {
          button.addEventListener("click", () => deleteOrderPermanently(button.dataset.deleteOrder));
        });
        document
          .querySelectorAll("[data-payment-action]")
          .forEach((button) =>
            button.addEventListener("click", () =>
              runAdminPaymentAction(
                button.dataset.paymentAction,
                button.dataset.paymentId,
                button.dataset.orderId,
              ),
            ),
          );
        document
          .querySelectorAll("[data-print-order]")
          .forEach(
            (button) =>
              (button.onclick = () => printInvoice(button.dataset.printOrder)),
          );
        document
          .querySelectorAll("[data-order-operation]")
          .forEach(
            (button) =>
              (button.onclick = () =>
                manageOrderOperation(
                  button.dataset.orderOperation,
                  button.dataset.orderId,
                )),
          );
      }

      function renderOrder(order) {
        const payment = [...(order.payment_transactions || [])].sort((a, b) =>
          String(b.created_at).localeCompare(String(a.created_at)),
        )[0];
        const paymentLabels = {
          unpaid: "Belum Dibayar",
          pending: "Menunggu Pembayaran",
          paid: "Dibayar",
          expired: "Kedaluwarsa",
          cancelled: "Dibatalkan",
          refunded: "Refund",
          failed: "Gagal",
        };
        return `
        <details class="card admin-order-compact" data-order-id="${order.id}">
          <summary>
            <div>
              <span class="status">${statusLabels[order.status] || esc(order.status)}</span>
              <strong>${esc(order.order_number)}</strong>
              <small>${new Date(order.created_at).toLocaleString("id-ID")}</small>
            </div>

            <strong>${rupiah(order.total)}</strong>
            <span>Lihat detail ▾</span>
          </summary>

          <div class="admin-order-details">
            <div class="admin-payment-box">
              <div>
                <b>💳 Pembayaran BTZPay</b><br>
                <span>${paymentLabels[payment?.status || order.payment_status] || esc(payment?.status || order.payment_status || "Belum dibuat")}</span>
                ${payment ? `<small>ID: ${esc(payment.gateway_transaction_id)} · Metode: ${esc(payment.payment_method)} · Tagihan: ${rupiah(payment.total_amount)}</small><small>Dibuat: ${new Date(payment.created_at).toLocaleString("id-ID")}${payment.paid_at ? ` · Dibayar: ${new Date(payment.paid_at).toLocaleString("id-ID")}` : ""}${payment.expires_at ? ` · Batas: ${new Date(payment.expires_at).toLocaleString("id-ID")}` : ""}</small>` : ""}
              </div>
              <div class="actions">
                ${
                  payment?.status === "pending" && can("finance.manage")
                    ? `
                  <button class="btn secondary small" data-payment-action="check" data-payment-id="${payment.id}" data-order-id="${order.id}" type="button">Cek</button>
                  <button class="btn danger small" data-payment-action="cancel" data-payment-id="${payment.id}" data-order-id="${order.id}" type="button">Batalkan</button>
                `
                    : ""
                }
                ${
                  can("finance.manage") &&
                  (!payment ||
                    ["expired", "cancelled", "failed"].includes(payment.status))
                    ? `
                  <button class="btn small" data-payment-action="recreate" data-payment-id="${payment?.id || ""}" data-order-id="${order.id}" type="button">Buat Ulang</button>
                `
                    : ""
                }
                ${
                  payment?.status === "paid" && can("finance.manage")
                    ? `
                  <button class="btn danger small" data-payment-action="refund_mark" data-payment-id="${payment.id}" data-order-id="${order.id}" type="button">Tandai Refund</button>
                `
                    : ""
                }
              </div>
            </div>
            ${
              order.rental_start
                ? `
              <div class="notice rental-order-period">
                <b>📅 Periode sewa</b><br>
                ${esc(formatRentalDate(order.rental_start))} —
                ${esc(formatRentalDate(order.rental_end))}
                (${Number(order.rental_days || 1)} hari)
              </div>
            `
                : ""
            }
            <div class="data-grid">
              <div class="data"><b>Nama</b><br>${esc(order.customer_name)}</div>
              <div class="data"><b>HP</b><br>${esc(order.phone)}</div>
              <div class="data"><b>Alamat</b><br>${esc(order.address)}, ${esc(order.city)}</div>
              <div class="data"><b>Jaminan</b><br>${esc(order.guarantee_type || "-")}</div>
              <div class="data"><b>Subtotal</b><br>${rupiah(order.subtotal)}</div>
              <div class="data"><b>Diskon</b><br>${rupiah(order.discount)}</div>
              <div class="data"><b>Denda</b><br>${rupiah(order.late_fee || 0)}</div>
              <div class="data"><b>Deposit</b><br>${rupiah(order.deposit_amount || 0)} · ${esc(order.deposit_status || "none")}</div>
            </div>

            ${(order.order_items || [])
              .map(
                (line) => `
              <div class="order-line">
                <span>${esc(line.title_snapshot)}${line.variant_name_snapshot ? ` · ${esc(line.variant_name_snapshot)}` : ""} × ${line.quantity}${line.item_type === "product" ? ` · ${line.fulfillment_type === "sale" ? "JUAL" : "SEWA"}${line.fulfillment_type === "rental" ? ` · Kembali ${Number(line.returned_quantity || 0)}/${line.quantity}` : ""}` : ""}${line.item_type === "trip" && line.trip_date_snapshot ? ` · Tanggal peserta: ${new Date(line.trip_date_snapshot + "T00:00:00").toLocaleDateString("id-ID", { dateStyle: "long" })}` : ""}</span>
                <b>${rupiah(line.line_total)}</b>
              </div>
            `,
              )
              .join("")}

            <div class="admin-order-toolbox">
              <a class="btn secondary small" target="_blank" rel="noopener" href="https://wa.me/${String(
                order.phone || "",
              )
                .replace(/\D/g, "")
                .replace(
                  /^0/,
                  "62",
                )}?text=${encodeURIComponent(`Halo ${order.customer_name}, kami menghubungi terkait pesanan ${order.order_number}.`)}">Hubungi Pelanggan</a>
              <button class="btn secondary small" data-print-order="${order.id}" type="button">Cetak Invoice</button>
              <button class="btn secondary small" data-print-order="${order.id}" type="button">Unduh PDF</button>
              ${can("*") ? `<button class="btn danger small" data-delete-order="${order.id}" type="button">🗑️ Hapus</button>` : ""}${can("orders.manage") ? `<button class="btn danger small" data-order-operation="cancel" data-order-id="${order.id}" type="button">Batalkan</button>` : ""}
              ${can("finance.manage") ? `<button class="btn secondary small" data-order-operation="refund" data-order-id="${order.id}" type="button">Refund</button>` : ""}
              ${can("orders.manage") || can("warehouse.manage") ? `<button class="btn secondary small" data-order-operation="late_fee" data-order-id="${order.id}" type="button">Denda</button>` : ""}
              ${can("finance.manage") || can("warehouse.manage") ? `<button class="btn secondary small" data-order-operation="deposit_received" data-order-id="${order.id}" type="button">Deposit Diterima</button><button class="btn secondary small" data-order-operation="deposit_returned" data-order-id="${order.id}" type="button">Deposit Dikembalikan</button>` : ""}
              ${can("warehouse.manage") && order.status === "paid" ? `<button class="btn secondary small" data-order-operation="return" data-order-id="${order.id}" type="button">Periksa Pengembalian</button>` : ""}
            </div>

            ${(order.order_refunds || []).length ? `<section class="order-subsection"><h4>Refund</h4>${order.order_refunds.map((refund) => `<div class="order-line"><span>${esc(refund.refund_type)} · ${esc(refund.reason)}<small>${new Date(refund.created_at).toLocaleString("id-ID")}</small></span><b>${rupiah(refund.amount)}</b></div>`).join("")}</section>` : ""}
            ${(order.order_returns || []).length ? `<section class="order-subsection"><h4>Pemeriksaan Barang</h4>${order.order_returns.map((entry) => `<div class="order-line"><span>${esc(entry.condition)} · ${esc(entry.notes || "Tanpa catatan")}<small>${new Date(entry.inspected_at).toLocaleString("id-ID")}</small></span><b>${entry.fee ? `Biaya ${rupiah(entry.fee)}` : "Lolos"}</b></div>`).join("")}</section>` : ""}
            <section class="order-subsection"><h4>Timeline Status</h4><div class="order-timeline">${
              [...(order.order_status_history || [])]
                .sort((a, b) =>
                  String(b.created_at).localeCompare(String(a.created_at)),
                )
                .map(
                  (history) =>
                    `<div><span></span><p><b>${esc(statusLabels[history.new_status] || history.new_status)}</b><small>${new Date(history.created_at).toLocaleString("id-ID")}${history.note ? ` · ${esc(history.note)}` : ""}</small></p></div>`,
                )
                .join("") ||
              '<p class="muted">Riwayat akan muncul setelah order-management.sql dijalankan.</p>'
            }</div></section>

            <div class="two" style="margin-top:14px">
              <select id="status-${order.id}" class="input">
                ${Object.entries(statusLabels)
                  .map(
                    ([value, label]) => `
                  <option
                    value="${value}"
                    ${order.status === value ? "selected" : ""}
                  >
                    ${label}
                  </option>
                `,
                  )
                  .join("")}
              </select>

              <input
                id="note-${order.id}"
                class="input"
                value="${esc(order.admin_notes || "")}"
                placeholder="Catatan admin"
              >
            </div>

            ${
              can("orders.manage")
                ? `<button
              class="btn"
              data-save-order="${order.id}"
              style="margin-top:10px"
              type="button"
            >
              Simpan Status
            </button>`
                : ""
            }
          </div>
        </details>`;
      }

      async function refreshOrders() {
        ordersLoaded = false;
        ordersLoadPromise = null;
        try {
          await loadOrdersData();
          if (activeTab === "rental") renderRentalTab();
          if (activeTab === "rental_orders") renderRentalOrdersTab();
          if (activeTab === "rental_returns") renderRentalReturnsTab();
          if (activeTab === "rental_reminders") renderRentalRemindersTab();
          if (activeTab === "orders") renderOrdersTab();
          if (activeTab === "schedule") renderRentalScheduleTab();
          showAdminMessage("Daftar pesanan dimuat ulang.", "success");
        } catch (error) {
          showAdminMessage(error?.message || "Gagal memuat pesanan.", "error");
        }
      }

      async function deleteOrderPermanently(orderId) {
        const order = orders.find((entry) => String(entry.id) === String(orderId));
        if (!order) {
          showAdminMessage("Pesanan tidak ditemukan.", "error");
          return;
        }
        if (!can("*")) {
          showAdminMessage("Hanya Super Admin yang dapat menghapus pesanan.", "error");
          return;
        }

        const statusText = statusLabels[order.status] || order.status || "-";
        const confirmed = await window.aocReminderConfirm({
          icon: "🗑️",
          title: "Hapus Pesanan Permanen?",
          confirmText: "Hapus Pesanan",
          danger: true,
          message: `
            <div class="aoc-delete-order-summary">
              <div class="aoc-delete-order-row"><span>Kode Order</span><strong>${esc(order.order_number)}</strong></div>
              <div class="aoc-delete-order-row"><span>Customer</span><strong>${esc(order.customer_name || "-")}</strong></div>
              <div class="aoc-delete-order-row"><span>Status</span><b class="aoc-delete-status">${esc(statusText)}</b></div>
            </div>
            <div class="aoc-delete-warning">
              <strong>⚠️ Perhatian</strong>
              <span>Semua data pesanan terkait akan dihapus permanen dan tidak dapat dibatalkan. Stok/kuota yang masih tercatat terpakai akan dikembalikan oleh server.</span>
            </div>
            <div class="aoc-delete-question">Pastikan Anda benar-benar ingin menghapus pesanan ini.</div>
          `
        });
        if (!confirmed) return;

        const button = document.querySelector(`[data-delete-order="${orderId}"]`) || document.querySelector(`[data-delete-rental-order="${orderId}"]`);
        const oldText = button?.innerHTML;
        if (button) { button.disabled = true; button.innerHTML = "⏳ Menghapus..."; }

        const { data, error } = await supabase.rpc("admin_delete_order", { p_order_id: order.id });
        if (error) {
          if (button) { button.disabled = false; button.innerHTML = oldText || "🗑️ Hapus"; }
          console.error("admin_delete_order", error);
          showAdminMessage(error.message || "Gagal menghapus pesanan.", "error");
          return;
        }

        await refreshOrders();
        showAdminMessage(data?.message || `${order.order_number} berhasil dihapus permanen.`, "success");
      }

      async function deleteAllOrders() {
        const total = orders.length;
        if (!total) {
          showAdminMessage("Tidak ada pesanan untuk dihapus.", "warning");
          return;
        }

        if (
          !confirm(
            `SEMUA ${total} pesanan dari seluruh status akan dihapus permanen beserta transaksi dan riwayatnya. Lanjutkan?`,
          )
        )
          return;

        const verification = prompt(
          `Ketik HAPUS SEMUA ${total} untuk konfirmasi penghapusan permanen:`,
        );
        if (verification !== `HAPUS SEMUA ${total}`) {
          showAdminMessage(
            "Konfirmasi tidak cocok. Penghapusan dibatalkan.",
            "warning",
          );
          return;
        }

        const button = document.getElementById("deleteAllOrders");
        button.disabled = true;
        button.textContent = "Menghapus...";
        const { data, error } = await supabase.rpc("admin_delete_all_orders");
        if (error) {
          button.disabled = false;
          button.textContent = "Hapus Semua Pesanan";
          showAdminMessage(
            `${error.message}. Jalankan order-cleanup.sql terlebih dahulu.`,
            "error",
          );
          return;
        }

        await refreshOrders();
        showAdminMessage(
          `${Number(data || total)} pesanan dari seluruh status berhasil dihapus permanen.`,
          "success",
        );
      }

      async function saveOrderStatus(id) {
        const status = document.getElementById(`status-${id}`).value;
        const notes =
          document.getElementById(`note-${id}`).value.trim() || null;

        const { error } = await supabase.rpc(
          "secure_admin_update_order_status",
          { a: id, b: status, c: notes },
        );

        if (error) {
          showAdminMessage(error.message, "error");
          return;
        }

        await refreshOrders();
        showAdminMessage("Status pesanan berhasil diperbarui.", "success");
      }

      function downloadBlob(content, filename, type) {
        const link = document.createElement("a");
        link.href = URL.createObjectURL(new Blob([content], { type }));
        link.download = filename;
        link.click();
        setTimeout(() => URL.revokeObjectURL(link.href), 1000);
      }

      function exportOrders(rows, format) {
        const data = rows.map((order) => ({
          nomor: order.order_number,
          tanggal: new Date(order.created_at).toLocaleString("id-ID"),
          pelanggan: order.customer_name,
          hp: order.phone,
          status: statusLabels[order.status] || order.status,
          pembayaran: order.payment_status || "unpaid",
          mulai_sewa: order.rental_start || "",
          selesai_sewa: order.rental_end || "",
          subtotal: Number(order.subtotal || 0),
          diskon: Number(order.discount || 0),
          total: Number(order.total || 0),
          denda: Number(order.late_fee || 0),
          deposit: Number(order.deposit_amount || 0),
          status_deposit: order.deposit_status || "none",
        }));
        const headers = Object.keys(data[0] || { nomor: "" });
        if (format === "csv") {
          const csv = [
            headers,
            ...data.map((row) => headers.map((key) => row[key])),
          ]
            .map((row) =>
              row
                .map(
                  (value) => `"${String(value ?? "").replaceAll('"', '""')}"`,
                )
                .join(","),
            )
            .join("\r\n");
          downloadBlob(
            "\ufeff" + csv,
            `laporan-pesanan-${new Date().toISOString().slice(0, 10)}.csv`,
            "text/csv;charset=utf-8",
          );
          return;
        }
        const table = `<table><thead><tr>${headers.map((key) => `<th>${esc(key)}</th>`).join("")}</tr></thead><tbody>${data.map((row) => `<tr>${headers.map((key) => `<td>${esc(row[key])}</td>`).join("")}</tr>`).join("")}</tbody></table>`;
        downloadBlob(
          `\ufeff<html><meta charset="utf-8"><body>${table}</body></html>`,
          `laporan-pesanan-${new Date().toISOString().slice(0, 10)}.xls`,
          "application/vnd.ms-excel",
        );
      }

      function printInvoice(orderId) {
        const order = orders.find((entry) => entry.id === orderId);
        if (!order) return;
        const payment = [...(order.payment_transactions || [])].sort((a, b) =>
          String(b.created_at).localeCompare(String(a.created_at)),
        )[0];
        const popup = window.open("", "_blank", "width=900,height=720");
        popup.document.write(
          `<!doctype html><html><head><title>Invoice ${esc(order.order_number)}</title><style>body{font-family:Arial,sans-serif;color:#17212b;margin:40px}header{display:flex;justify-content:space-between;border-bottom:2px solid #17212b;padding-bottom:18px}.meta,.totals{margin:22px 0;line-height:1.7}table{width:100%;border-collapse:collapse}th,td{padding:10px;border-bottom:1px solid #ddd;text-align:left}th:last-child,td:last-child{text-align:right}.totals{margin-left:auto;width:320px}.totals div{display:flex;justify-content:space-between}.grand{font-size:20px;font-weight:bold;border-top:2px solid;padding-top:8px}@media print{button{display:none}}</style></head><body><header><div><h1>AbidzarOutdoorcamp</h1><p>Invoice Pesanan</p></div><div><b>${esc(order.order_number)}</b><br>${new Date(order.created_at).toLocaleString("id-ID")}</div></header><div class="meta"><b>Pelanggan:</b> ${esc(order.customer_name)}<br><b>HP:</b> ${esc(order.phone)}<br><b>Alamat:</b> ${esc(order.address)}, ${esc(order.city)}${order.rental_start ? `<br><b>Periode sewa:</b> ${esc(formatRentalDate(order.rental_start))} — ${esc(formatRentalDate(order.rental_end))}` : ""}<br><b>Pembayaran:</b> ${esc(payment?.status || order.payment_status || "unpaid")}</div><table><thead><tr><th>Item</th><th>Jumlah</th><th>Harga</th><th>Total</th></tr></thead><tbody>${(order.order_items || []).map((line) => `<tr><td>${esc(line.title_snapshot)}</td><td>${line.quantity}</td><td>${rupiah(line.price_snapshot)}</td><td>${rupiah(line.line_total)}</td></tr>`).join("")}</tbody></table><div class="totals"><div><span>Subtotal</span><b>${rupiah(order.subtotal)}</b></div><div><span>Diskon</span><b>${rupiah(order.discount)}</b></div><div><span>Denda</span><b>${rupiah(order.late_fee || 0)}</b></div><div class="grand"><span>Total</span><b>${rupiah(Number(order.total || 0) + Number(order.late_fee || 0))}</b></div></div><p>Terima kasih telah menggunakan layanan AbidzarOutdoorcamp.</p><button onclick="window.print()">Cetak / Simpan PDF</button></body></html>`,
        );
        popup.document.close();
        popup.focus();
      }

      async function manageOrderOperation(action, orderId) {
        const order = orders.find((entry) => entry.id === orderId);
        if (!order) return;
        let amount = null,
          reason = null,
          condition = null,
          itemId = null,
          quantity = 1;
        if (action === "cancel") reason = prompt("Alasan pembatalan:");
        if (action === "refund") {
          amount = Number(
            prompt(`Nominal refund (maksimal ${order.total}):`) || 0,
          );
          reason = prompt("Alasan refund:") || "Refund admin";
        }
        if (action === "late_fee")
          amount = Number(
            Math.round(Number(order.late_fee_base || order.subtotal || order.total || 0) * 1.00),
          );
        if (action === "deposit_received")
          amount = Number(
            prompt(
              "Nominal deposit yang diterima:",
              order.deposit_amount || 0,
            ) || 0,
          );
        if (
          action === "deposit_returned" &&
          !confirm("Tandai seluruh deposit sudah dikembalikan?")
        )
          return;
        if (action === "return") {
          const rentalLines = (order.order_items || []).filter(
            (line) => line.item_type === "product",
          );
          if (!rentalLines.length)
            return showAdminMessage(
              "Pesanan tidak memiliki barang sewa.",
              "error",
            );
          const selected = prompt(
            `Pilih nomor item:\n${rentalLines.map((line, index) => `${index + 1}. ${line.title_snapshot}`).join("\n")}`,
            "1",
          );
          const line = rentalLines[Number(selected) - 1];
          if (!line) return;
          itemId = line.item_id;
          const remaining = Math.max(
            0,
            Number(line.quantity) - Number(line.returned_quantity || 0),
          );
          if (!remaining)
            return showAdminMessage(
              "Seluruh unit item tersebut sudah dikembalikan.",
              "error",
            );
          quantity = Number(
            prompt(
              `Jumlah yang dikembalikan (maksimal ${remaining}):`,
              remaining,
            ) || 0,
          );
          if (
            !Number.isInteger(quantity) ||
            quantity < 1 ||
            quantity > remaining
          )
            return showAdminMessage(
              `Jumlah pengembalian harus antara 1 sampai ${remaining}.`,
              "error",
            );
          condition = prompt(
            "Kondisi: good, dirty, damaged, atau lost",
            "good",
          );
          reason = prompt("Catatan pemeriksaan:") || null;
          amount = Number(
            prompt("Biaya kerusakan/kebersihan (0 jika tidak ada):", "0") || 0,
          );
        }
        if (action === "cancel" && !reason) return;
        const { error } = await supabase.rpc("secure_admin_manage_order", {
          a: orderId,
          b: action,
          c: amount,
          d: reason,
          e: condition,
          f: itemId,
          g: quantity,
        });
        if (error)
          return showAdminMessage(
            `${error.message}. Jalankan order-management.sql.`,
            "error",
          );
        await refreshOrders();
        showAdminMessage(
          "Data operasional pesanan berhasil disimpan.",
          "success",
        );
      }

      async function runAdminPaymentAction(action, paymentId, orderId) {
        const confirmations = {
          cancel: "Batalkan transaksi pembayaran ini?",
          refund_mark:
            "Tandai pembayaran sebagai refund? Pastikan pengembalian dana sudah dilakukan melalui kanal yang sesuai.",
        };
        if (confirmations[action] && !confirm(confirmations[action])) return;
        const body = { action, payment_id: paymentId, order_id: orderId };
        if (action === "refund_mark")
          body.reason = "Refund dicatat administrator";
        const { data, error } = await supabase.functions.invoke("btzpay", {
          body,
        });
        if (error || !data?.success) {
          showAdminMessage(
            data?.error || error?.message || "Operasi pembayaran gagal.",
            "error",
          );
          return;
        }
        await refreshOrders();
        showAdminMessage("Data pembayaran berhasil diperbarui.", "success");
      }

      async function renderCustomersTab() {
        const content = document.getElementById("adminContent");
        content.innerHTML = '<div class="notice">Memuat pelanggan...</div>';
        const { data, error } = await supabase.rpc("secure_list_customers");
        if (error)
          return (content.innerHTML = `<div class="notice error">${esc(error.message)}<br><small>Jalankan customer-review-notification.sql.</small></div>`);
        customers = data || [];
        content.innerHTML = `<div class="admin-list-heading"><div><h3>Data Pelanggan</h3><p class="muted">${customers.length} pelanggan · pelanggan langganan ditandai dari jumlah transaksi.</p></div></div><div class="customer-admin-grid">${
          customers
            .map((customer) => {
              const history = orders.filter(
                (order) => order.user_id === customer.user_id,
              );
              const loyal =
                Number(customer.total_orders) >= 3 ||
                Number(customer.total_spent) >= 1000000;
              return `<details class="card customer-admin-card"><summary><div><strong>${esc(customer.full_name || customer.email)}</strong><small>${esc(customer.email)} · ${esc(customer.phone || "Belum ada HP")}</small></div><div class="customer-badges">${loyal ? '<span class="badge">Langganan</span>' : ""}${customer.is_verified ? '<span class="admin-active">Terverifikasi</span>' : '<span class="admin-inactive">Belum verifikasi</span>'}${customer.is_blocked ? '<span class="status-danger">Diblokir</span>' : ""}</div></summary><div class="customer-detail"><div class="data-grid"><div class="data"><b>Total pesanan</b><br>${customer.total_orders}</div><div class="data"><b>Total transaksi</b><br>${rupiah(customer.total_spent)}</div><div class="data"><b>Pembatalan</b><br>${customer.cancelled_orders}</div><div class="data"><b>Terakhir transaksi</b><br>${customer.last_order_at ? new Date(customer.last_order_at).toLocaleString("id-ID") : "-"}</div></div><label class="admin-check"><input type="checkbox" data-customer-verified="${customer.user_id}" ${customer.is_verified ? "checked" : ""}><span>Pelanggan terverifikasi</span></label><label class="admin-check"><input type="checkbox" data-customer-blocked="${customer.user_id}" ${customer.is_blocked ? "checked" : ""}><span>Blokir pelanggan</span></label><label class="field"><span>Alasan blokir</span><input class="input" data-customer-reason="${customer.user_id}" value="${esc(customer.blocked_reason || "")}"></label><label class="field"><span>Catatan internal</span><textarea class="input" data-customer-notes="${customer.user_id}">${esc(customer.internal_notes || "")}</textarea></label><button class="btn small" data-save-customer="${customer.user_id}" type="button">Simpan Pelanggan</button><section class="order-subsection"><h4>Riwayat transaksi & pembatalan</h4>${history.map((order) => `<div class="order-line"><span>${esc(order.order_number)} · ${new Date(order.created_at).toLocaleDateString("id-ID")}<small>${esc(statusLabels[order.status] || order.status)}</small></span><b>${rupiah(order.total)}</b></div>`).join("") || '<p class="muted">Belum ada transaksi.</p>'}</section></div></details>`;
            })
            .join("") || '<div class="notice">Belum ada pelanggan.</div>'
        }</div>`;
        document.querySelectorAll("[data-save-customer]").forEach(
          (button) =>
            (button.onclick = async () => {
              const id = button.dataset.saveCustomer;
              const blocked = document.querySelector(
                `[data-customer-blocked="${id}"]`,
              ).checked;
              const reason = document
                .querySelector(`[data-customer-reason="${id}"]`)
                .value.trim();
              if (blocked && !reason)
                return showAdminMessage("Alasan blokir wajib diisi.", "error");
              const { error: saveError } = await supabase.rpc(
                "secure_admin_update_customer",
                {
                  a: id,
                  b: document.querySelector(`[data-customer-verified="${id}"]`)
                    .checked,
                  c: blocked,
                  d:
                    document
                      .querySelector(`[data-customer-notes="${id}"]`)
                      .value.trim() || null,
                  e: reason || null,
                },
              );
              if (saveError)
                return showAdminMessage(saveError.message, "error");
              await renderCustomersTab();
              showAdminMessage("Data pelanggan disimpan.", "success");
            }),
        );
      }

      async function renderReviewsTab() {
        const content = document.getElementById("adminContent");
        content.innerHTML = '<div class="notice">Memuat ulasan...</div>';
        const { data, error } = await supabase.rpc("secure_list_ratings");
        if (error)
          return (content.innerHTML = `<div class="notice error">${esc(error.message)}<br><small>Jalankan customer-review-notification.sql.</small></div>`);
        adminRatings = data || [];
        content.innerHTML = `<div class="admin-list-heading"><div><h3>Moderasi Rating Website</h3><p class="muted">${adminRatings.length} rating tersimpan.</p></div></div><div class="review-admin-grid">${adminRatings.map((rating) => `<article class="card review-admin-card"><div class="row"><strong>${"★".repeat(rating.score)}${"☆".repeat(5 - rating.score)}</strong><span class="${rating.is_hidden ? "admin-inactive" : "admin-active"}">${rating.is_hidden ? "Disembunyikan" : "Tampil"}</span></div><h3>${esc(rating.full_name || rating.email)}</h3><p>${esc(rating.comment || "Tanpa komentar")}</p><small class="muted">${new Date(rating.created_at).toLocaleString("id-ID")}</small><label class="admin-check"><input type="checkbox" data-review-hidden="${rating.id}" ${rating.is_hidden ? "checked" : ""}><span>Sembunyikan ulasan bermasalah</span></label><label class="field"><span>Balasan admin</span><textarea class="input" data-review-reply="${rating.id}">${esc(rating.admin_reply || "")}</textarea></label><button class="btn small" data-save-review="${rating.id}" type="button">Simpan Moderasi</button></article>`).join("") || '<div class="notice">Belum ada rating.</div>'}</div>`;
        document.querySelectorAll("[data-save-review]").forEach(
          (button) =>
            (button.onclick = async () => {
              const id = button.dataset.saveReview;
              const { error: saveError } = await supabase.rpc(
                "secure_admin_moderate_rating",
                {
                  a: id,
                  b: document.querySelector(`[data-review-hidden="${id}"]`)
                    .checked,
                  c:
                    document
                      .querySelector(`[data-review-reply="${id}"]`)
                      .value.trim() || null,
                },
              );
              if (saveError)
                return showAdminMessage(saveError.message, "error");
              await renderReviewsTab();
              showAdminMessage("Moderasi ulasan disimpan.", "success");
            }),
        );
      }

      async function renderNotificationsTab() {
        const content = document.getElementById("adminContent");
        content.innerHTML = '<div class="notice">Memuat notifikasi...</div>';
        const [notificationResult, customerResult] = await Promise.all([
          supabase
            .from("customer_notifications")
            .select("*,orders(order_number)")
            .order("scheduled_for", { ascending: false })
            .limit(200),
          supabase.rpc("secure_list_customers"),
        ]);
        if (notificationResult.error)
          return (content.innerHTML = `<div class="notice error">${esc(notificationResult.error.message)}<br><small>Jalankan customer-review-notification.sql.</small></div>`);
        customerNotifications = notificationResult.data || [];
        customers = customerResult.data || customers;
        const typeLabels = {
          order_created: "Pesanan dibuat",
          payment_paid: "Pembayaran berhasil",
          payment_expired: "Pembayaran kedaluwarsa",
          order_confirmed: "Pesanan dikonfirmasi",
          pickup_reminder: "Pengingat pengambilan",
          return_reminder: "Pengingat pengembalian",
          late_warning: "Peringatan terlambat",
          trip_reminder: "Trip mendekati keberangkatan",
          cancelled: "Pembatalan",
          refund: "Refund",
        };
        content.innerHTML = `<div class="admin-list-heading"><div><h3>Pusat Notifikasi</h3><p class="muted">${customerNotifications.filter((entry) => entry.status === "pending").length} menunggu dikirim.</p></div><button id="generateReminders" class="btn" type="button">Buat Pengingat Otomatis</button></div><div class="notification-admin-list">${
          customerNotifications
            .map((entry) => {
              const customer =
                customers.find((item) => item.user_id === entry.user_id) || {};
              const digits = String(customer.phone || "")
                .replace(/\D/g, "")
                .replace(/^0/, "62");
              return `<article class="card notification-admin-card"><div><span class="badge">${esc(typeLabels[entry.notification_type] || entry.notification_type)}</span><h3>${esc(entry.title)}</h3><p>${esc(entry.message)}</p><small>${esc(customer.full_name || customer.email || "Pelanggan")} · ${esc(entry.orders?.order_number || "-")} · ${new Date(entry.scheduled_for).toLocaleString("id-ID")}</small></div><div class="actions"><span class="${entry.status === "sent" ? "admin-active" : "admin-inactive"}">${esc(entry.status)}</span>${entry.status === "pending" && digits ? `<a class="btn small" data-send-notification="${entry.id}" target="_blank" href="https://wa.me/${digits}?text=${encodeURIComponent(entry.message)}">Kirim WhatsApp</a>` : ""}</div></article>`;
            })
            .join("") || '<div class="notice">Belum ada notifikasi.</div>'
        }</div>`;
        document.getElementById("generateReminders").onclick = async () => {
          const { data, error } = await supabase.rpc(
            "secure_admin_generate_reminders",
          );
          if (error) return showAdminMessage(error.message, "error");
          await renderNotificationsTab();
          showAdminMessage(`${data || 0} pengingat baru dibuat.`, "success");
        };
        document.querySelectorAll("[data-send-notification]").forEach((link) =>
          link.addEventListener("click", async () => {
            await supabase.rpc("secure_admin_mark_notification_sent", {
              a: link.dataset.sendNotification,
            });
            setTimeout(renderNotificationsTab, 700);
          }),
        );
      }

      async function renderAdministratorsTab() {
        const content = document.getElementById("adminContent");

        content.innerHTML = `
    <div class="notice">
      Memuat daftar administrator...
    </div>`;

        const { data, error } = await supabase.rpc("secure_list_staff_users");

        if (error) {
          content.innerHTML = `
      <div class="notice error">
        Fitur pengelolaan admin belum aktif di database.<br><br>
        Jalankan file <b>admin-management.sql</b> melalui
        Supabase SQL Editor, lalu muat ulang halaman.
        <br><small>${esc(error.message)}</small>
      </div>`;
          return;
        }

        administrators = data || [];
        renderAdministratorContent();
      }

      async function renderActivityLogsTab() {
        const content = document.getElementById("adminContent");
        content.innerHTML = '<div class="notice">Memuat log aktivitas...</div>';
        const { data, error } = await supabase
          .from("admin_activity_logs")
          .select("*")
          .order("created_at", { ascending: false })
          .limit(300);
        if (error)
          return (content.innerHTML = `<div class="notice error">${esc(error.message)}<br><small>Jalankan access-security.sql.</small></div>`);
        content.innerHTML = `<div class="admin-list-heading"><div><h3>Log Aktivitas Admin</h3><p class="muted">300 aktivitas terbaru. Log hanya dapat dibaca Super Admin.</p></div></div><div class="activity-log-list">${(data || []).map((entry) => `<article class="card activity-log-card"><div><span class="badge">${esc(entry.admin_role || "system")}</span><strong>${esc(entry.action.toUpperCase())} · ${esc(entry.table_name)}</strong><small>${new Date(entry.created_at).toLocaleString("id-ID")} · ${esc(entry.admin_user_id || "sistem")} · ID ${esc(entry.record_id || "-")}</small></div><details><summary>Lihat perubahan</summary><pre>${esc(JSON.stringify({ sebelum: entry.old_data, sesudah: entry.new_data }, null, 2))}</pre></details></article>`).join("") || '<div class="notice">Belum ada aktivitas admin.</div>'}</div>`;
      }

      function renderAdministratorContent() {
        const content = document.getElementById("adminContent");

        content.innerHTML = `
    <div class="admin-user-layout">
      <section class="card admin-editor-card admin-add-user-card">
        <div class="admin-editor-heading">
          <div>
            <span class="badge">Hak Akses</span>
            <h3>Tambahkan Petugas</h3>
            <p class="muted">
              Pengguna harus mendaftar dan memiliki akun terlebih dahulu.
            </p>
          </div>
        </div>

        <form id="addAdministratorForm" class="form">
          <label class="field">
            <span>Email pengguna *</span>
            <input
              class="input"
              name="email"
              type="email"
              required
              autocomplete="off"
              placeholder="email-admin@gmail.com"
            >
          </label>

          <label class="field"><span>Hak akses *</span><select class="input" name="role" required><option value="order_admin">Admin Pesanan</option><option value="catalog_admin">Admin Katalog</option><option value="finance_admin">Admin Keuangan</option><option value="warehouse_staff">Petugas Gudang</option><option value="super_admin">Super Admin</option></select></label>

          <label class="field">
            <span>Nama tampilan</span>
            <input
              class="input"
              name="full_name"
              maxlength="120"
              autocomplete="off"
              placeholder="Contoh: Admin Toko"
            >
          </label>

          <div class="notice warning admin-access-note">
            Email tersebut harus sudah pernah mendaftar melalui halaman
            Login/Daftar. Fitur ini tidak membuat akun baru dan tidak
            meminta password pengguna.
          </div>

          <button id="addAdministratorButton" class="btn" type="submit">
            Tambahkan Petugas
          </button>
        </form>
      </section>

      <section>
        <div class="admin-list-heading">
          <div>
            <h3>Daftar Petugas & Administrator</h3>
            <p class="muted">
              ${administrators.length} akun memiliki akses operasional.
            </p>
          </div>

          <button
            id="refreshAdministrators"
            class="btn secondary small"
            type="button"
          >
            Muat Ulang
          </button>
        </div>

        <div class="admin-user-list">
          ${
            administrators.map(renderAdministratorCard).join("") ||
            `
            <div class="notice">
              Belum ada administrator yang dapat ditampilkan.
            </div>
          `
          }
        </div>
      </section>
    </div>`;

        document
          .getElementById("addAdministratorForm")
          .addEventListener("submit", addAdministrator);

        document
          .getElementById("refreshAdministrators")
          .addEventListener("click", async () => {
            await reloadAdministrators();
            showAdminMessage("Daftar administrator dimuat ulang.", "success");
          });

        document.querySelectorAll("[data-remove-admin]").forEach((button) => {
          button.addEventListener("click", () => {
            removeAdministrator(button.dataset.removeAdmin);
          });
        });
      }

      function renderAdministratorCard(administrator) {
        const isCurrent =
          String(administrator.user_id) === String(currentAdminUserId);

        const displayName =
          administrator.full_name?.trim() ||
          administrator.email?.split("@")[0] ||
          "Administrator";

        return `
    <article class="card admin-user-card">
      <div class="admin-user-avatar" aria-hidden="true">
        ${esc(displayName.slice(0, 1).toUpperCase())}
      </div>

      <div class="admin-user-info">
        <div class="admin-user-name-row">
          <strong>${esc(displayName)}</strong>
          ${isCurrent ? '<span class="admin-current-badge">Akun Anda</span>' : ""}
        </div>

        <span>${esc(administrator.email || "-")}</span>
        <small>
          ${esc({ super_admin: "Super Admin", order_admin: "Admin Pesanan", catalog_admin: "Admin Katalog", finance_admin: "Admin Keuangan", warehouse_staff: "Petugas Gudang" }[administrator.role] || administrator.role)} · sejak ${new Date(administrator.created_at).toLocaleDateString("id-ID", { dateStyle: "medium" })}
        </small>
      </div>

      <button
        class="btn danger small"
        type="button"
        data-remove-admin="${administrator.user_id}"
        ${isCurrent ? "disabled" : ""}
        title="${
          isCurrent
            ? "Anda tidak dapat mencabut akses akun sendiri"
            : "Cabut akses administrator"
        }"
      >
        Cabut Akses
      </button>
    </article>`;
      }

      async function addAdministrator(event) {
        event.preventDefault();

        const form = event.currentTarget;
        const values = Object.fromEntries(new FormData(form));
        const email = String(values.email || "")
          .trim()
          .toLowerCase();
        const fullName = String(values.full_name || "").trim() || null;
        const role = String(values.role || "order_admin");
        const button = document.getElementById("addAdministratorButton");

        if (!email) {
          showAdminMessage("Masukkan email pengguna.", "error");
          return;
        }

        button.disabled = true;
        button.textContent = "Menambahkan...";

        const { error } = await supabase.rpc("secure_set_staff_role", {
          a: email,
          b: role,
          c: fullName,
        });

        button.disabled = false;
        button.textContent = "Tambahkan Petugas";

        if (error) {
          showAdminMessage(error.message, "error");
          return;
        }

        form.reset();
        await reloadAdministrators();
        showAdminMessage(
          `${email} berhasil mendapatkan akses administrator.`,
          "success",
        );
      }

      async function removeAdministrator(userId) {
        const administrator = administrators.find(
          (entry) => String(entry.user_id) === String(userId),
        );

        if (!administrator) return;

        const confirmed = confirm(
          `Cabut akses admin dari ${administrator.email}?\n\n` +
            "Akun pengguna tidak akan dihapus. Role-nya akan kembali menjadi user.",
        );

        if (!confirmed) return;

        const { error } = await supabase.rpc("secure_remove_staff_role", {
          a: userId,
        });

        if (error) {
          showAdminMessage(error.message, "error");
          return;
        }

        await reloadAdministrators();
        showAdminMessage(
          `Akses admin ${administrator.email} berhasil dicabut.`,
          "success",
        );
      }

      async function reloadAdministrators() {
        const { data, error } = await supabase.rpc("secure_list_staff_users");

        if (error) throw error;

        administrators = data || [];
        renderAdministratorContent();
      }

      function showAdminMessage(text, type = "") {
        const box = document.getElementById("adminMessage");
        if (!box) return;
        message(box, text, type);
        window.scrollTo({ top: 0, behavior: "smooth" });
      }

      window.aocReminderConfirm = function({ icon = "🔔", title = "Konfirmasi", message = "", confirmText = "Lanjutkan", danger = false } = {}) {
        return new Promise((resolve) => {
          const modal = document.getElementById("aocReminderConfirmModal");
          if (!modal) return resolve(window.confirm(String(message).replace(/<[^>]*>/g, "")));
          const iconEl = modal.querySelector("[data-confirm-icon]");
          const labelEl = modal.querySelector("[data-confirm-label]");
          const titleEl = modal.querySelector("[data-confirm-title]");
          const messageEl = modal.querySelector("[data-confirm-message]");
          const okBtn = modal.querySelector("[data-confirm-ok]");
          const cancelBtn = modal.querySelector("[data-confirm-cancel]");
          iconEl.textContent = icon;
          if (labelEl) labelEl.textContent = danger ? "KONFIRMASI PENGHAPUSAN" : "KONFIRMASI";
          titleEl.textContent = title;
          messageEl.innerHTML = message;
          okBtn.textContent = confirmText;
          okBtn.classList.toggle("aoc-confirm-danger", !!danger);
          modal.hidden = false;
          document.body.classList.add("aoc-modal-open");
          requestAnimationFrame(() => modal.classList.add("is-open"));
          const finish = (value) => {
            modal.classList.remove("is-open");
            document.body.classList.remove("aoc-modal-open");
            setTimeout(() => { modal.hidden = true; resolve(value); }, 160);
          };
          okBtn.onclick = () => finish(true);
          cancelBtn.onclick = () => finish(false);
          modal.querySelector("[data-confirm-close]").onclick = () => finish(false);
          modal.onkeydown = (event) => {
            if (event.key === "Escape") finish(false);
            if (event.key === "Enter") finish(true);
          };
          setTimeout(() => cancelBtn.focus(), 30);
        });
      };

      let adminSecurityHeartbeat = null;

      function startAdminSecurityHeartbeat() {
        if (adminSecurityHeartbeat) clearInterval(adminSecurityHeartbeat);
        const check = async () => {
          try {
            const result = await supabase.rpc("admin_security_check");
            if (result?.error || result?.data !== true) {
              clearInterval(adminSecurityHeartbeat);
              adminSecurityHeartbeat = null;
              location.href = "login.html?next=admin.html";
            }
          } catch (_) {
            // Jangan mengeluarkan admin hanya karena jaringan sesaat putus.
          }
        };
        adminSecurityHeartbeat = setInterval(check, 5 * 60 * 1000);
        document.addEventListener("visibilitychange", () => {
          if (document.visibilityState === "visible") check();
        }, { passive: true });
      }

      async function initialize() {
        try {
          const allowed = await verifyAdmin();
          if (!allowed) return;

          if (
            (activeTab === "rental" && !can("catalog.manage")) ||
            (activeTab === "locations" && !can("catalog.manage")) ||
            (activeTab === "trips" && !can("catalog.manage")) ||
            (activeTab === "orders" && !can("orders.view")) ||
            (activeTab === "shop" && !can("coinshop.manage"))
          )
            activeTab = firstAllowedAdminTab();

          // Tampilkan shell admin segera. Data berat dimuat setelah menu dibuka.
          renderShell();
          startAdminSecurityHeartbeat();
        } catch (error) {
          const rawMessage = String(error?.message || "Admin panel gagal dimuat.");
          const needsSaleRentalMigration =
            /rental_enabled|sale_enabled|sale_price/i.test(rawMessage) &&
            /schema cache|column/i.test(rawMessage);

          root.innerHTML = `
          <section class="container section">
            <div class="notice error">
              ${needsSaleRentalMigration
                ? `<b>Database belum menjalankan migrasi JUAL + SEWA V3.</b><br><br>
                   Kolom <code>rental_enabled</code>, <code>sale_enabled</code>, atau <code>sale_price</code> belum tersedia pada tabel <code>items</code>.<br><br>
                   Jalankan file <b>JUAL-SEWA-INVENTORY-FINAL.sql</b> melalui Supabase SQL Editor, lalu refresh halaman Admin. File tersebut juga melakukan reload schema cache Supabase.<br><br>
                   <small>Error asli: ${esc(rawMessage)}</small>`
                : esc(rawMessage)}
            </div>
          </section>`;
        }
      }

      Promise.race([
        initialize(),
        new Promise((_, reject) =>
          setTimeout(() => reject(new Error("Admin Panel timeout. Koneksi/auth Supabase tidak merespons dalam 10 detik.")), 10000),
        ),
      ]).catch((error) => {
        console.error("Admin initialize watchdog:", error);
        const root = document.getElementById("adminRoot");
        if (root && /Memeriksa akses admin/i.test(root.textContent || "")) {
          root.innerHTML = `
            <section class="container section">
              <div class="notice error">
                <b>Admin Panel tidak mendapat respons.</b><br><br>
                Pemeriksaan login/database terlalu lama. Ini biasanya terjadi karena sesi Supabase macet atau koneksi ke database tidak merespons.<br><br>
                <button class="btn primary" type="button" onclick="location.reload()">↻ Coba Lagi</button>
                <a class="btn" href="login.html?next=admin.html">Login Ulang</a>
              </div>
            </section>`;
        }
      });
    
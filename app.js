import { createClient } from "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm";
import { CONFIG } from "./config.js";

export const supabase = createClient(
  CONFIG.SUPABASE_URL,
  CONFIG.SUPABASE_ANON_KEY,
);
export const DEFAULT_SITE_SETTINGS = Object.freeze({
  site_name: CONFIG.SITE_NAME || "AbidzarOutdoorcamp",
  site_logo_url: "",
  whatsapp_number: CONFIG.WHATSAPP_NUMBER || "6289509349428",
  whatsapp_message:
    "Halo CS AbidzarOutdoorcamp, saya ingin bertanya mengenai layanan.",
  admin_1_name: "Admin 1",
  admin_1_whatsapp: "",
  admin_2_name: "Admin 2",
  admin_2_whatsapp: "",
  admin_3_name: "Admin 3",
  admin_3_whatsapp: "",
  address: "",
  business_hours: "",
  google_maps_url: "",
  instagram_url: "",
  tiktok_url: "",
  hero_eyebrow: "Outdoor rental & open trip",
  hero_title: "Siapkan petualangan.",
  hero_subtitle: "Pesan semuanya di satu tempat.",
  hero_description:
    "Cari perlengkapan di katalog Sewa Item atau pilih perjalanan di katalog Open Trip. Keduanya tetap dapat digabungkan dalam satu keranjang dan satu checkout.",
  seo_title: "AbidzarOutdoorcamp — Sewa Outdoor & Open Trip",
  seo_description:
    "Katalog sewa perlengkapan outdoor dan open trip AbidzarOutdoorcamp.",
  rental_min_days: 1,
  rental_max_days: 30,
  payment_enabled: false,
  payment_method: "qrisorkut",
  payment_method_rental: "qrisorkut",
  payment_method_sale: "qrisdana",
  payment_timeout_minutes: 15,
  late_fee_text: "",
  guarantee_policy: "",
  cancellation_policy: "",
  refund_policy: "",
  maintenance_mode: false,
  maintenance_message:
    "Website sedang dalam perawatan. Silakan hubungi kami melalui WhatsApp.",
});

let cachedSiteSettings = null;

export async function loadSiteSettings(force = false) {
  if (cachedSiteSettings && !force) return cachedSiteSettings;

  const { data, error } = await supabase
    .from("site_settings")
    .select("settings")
    .eq("id", "main")
    .maybeSingle();

  // Tabel pengaturan bersifat opsional agar website lama tetap berjalan
  // sebelum site-settings.sql dipasang.
  cachedSiteSettings = {
    ...DEFAULT_SITE_SETTINGS,
    ...(!error && data?.settings && typeof data.settings === "object"
      ? data.settings
      : {}),
  };

  return cachedSiteSettings;
}

export function applySiteSettings(settings) {
  const value = { ...DEFAULT_SITE_SETTINGS, ...(settings || {}) };
  const siteName = String(
    value.site_name || DEFAULT_SITE_SETTINGS.site_name,
  ).trim();
  const whatsapp = String(value.whatsapp_number || "").replace(/\D/g, "");
  const whatsappText = String(value.whatsapp_message || "").trim();

  document.querySelectorAll(".brand").forEach((element) => {
    const logoUrl = String(value.site_logo_url || "").trim();
    const textWrap = document.createElement("span");
    textWrap.className = "brand-text";
    const splitAt = siteName.toLowerCase().indexOf("outdoor");
    if (splitAt > 0) {
      textWrap.append(
        document.createTextNode(siteName.slice(0, splitAt)),
        Object.assign(document.createElement("span"), { textContent: siteName.slice(splitAt) }),
      );
    } else {
      textWrap.textContent = siteName;
    }
    element.replaceChildren();
    element.classList.toggle("has-custom-logo", Boolean(logoUrl));
    if (logoUrl) {
      const img = document.createElement("img");
      img.className = "brand-logo";
      img.src = logoUrl;
      img.alt = siteName;
      img.loading = "eager";
      img.decoding = "async";
      img.referrerPolicy = "no-referrer";
      img.onerror = () => {
        element.classList.remove("has-custom-logo");
        img.remove();
      };
      element.append(img);
    }
    element.append(textWrap);
  });

  if (document.title.includes("AbidzarOutdoorcamp")) {
    document.title = document.title.replace("AbidzarOutdoorcamp", siteName);
  }

  const isHomepage =
    /(?:^|\/)index\.html$/.test(location.pathname) ||
    location.pathname.endsWith("/");

  if (isHomepage) {
    if (value.seo_title) document.title = value.seo_title;
    const meta = document.querySelector('meta[name="description"]');
    if (meta && value.seo_description) meta.content = value.seo_description;
  }

  const content = {
    "site-hero-eyebrow": value.hero_eyebrow,
    "site-hero-title": value.hero_title,
    "site-hero-subtitle": value.hero_subtitle,
    "site-hero-description": value.hero_description,
  };

  Object.entries(content).forEach(([id, text]) => {
    const element = document.getElementById(id);
    if (element && text) element.textContent = text;
  });

  document.querySelectorAll(".customer-service-float").forEach((link) => {
    if (!whatsapp) {
      link.classList.add("hidden");
      return;
    }

    link.href = `https://wa.me/${whatsapp}?text=${encodeURIComponent(whatsappText)}`;
    link.title = `Hubungi CS: +${whatsapp}`;
    link.setAttribute("aria-label", `Hubungi CS ${siteName} melalui WhatsApp`);
  });

  document.documentElement.dataset.maintenance = String(
    Boolean(value.maintenance_mode),
  );
  window.dispatchEvent(
    new CustomEvent("site-settings-ready", { detail: value }),
  );
}

// Dialog UI global AOC: menggantikan alert/confirm/prompt bawaan browser.
let aocDialogPromise = null;
function ensureAocDialogStyles() {
  if (document.getElementById('aocDialogStyles')) return;
  const style = document.createElement('style');
  style.id = 'aocDialogStyles';
  style.textContent = `
    .aoc-dialog-backdrop{position:fixed;inset:0;z-index:99999;display:grid;place-items:end center;padding:18px;background:rgba(2,8,12,.72);backdrop-filter:blur(10px);opacity:0;transition:opacity .18s ease}
    .aoc-dialog-backdrop.is-open{opacity:1}
    .aoc-dialog{width:min(100%,520px);border:1px solid rgba(105,231,174,.2);border-radius:28px;background:linear-gradient(180deg,#111a20,#0a1116);box-shadow:0 24px 70px rgba(0,0,0,.5);transform:translateY(18px);transition:transform .2s ease;overflow:hidden;color:#f4f8f6}
    .aoc-dialog-backdrop.is-open .aoc-dialog{transform:translateY(0)}
    .aoc-dialog-head{display:flex;gap:14px;align-items:center;padding:22px 22px 10px}
    .aoc-dialog-icon{width:46px;height:46px;border-radius:16px;display:grid;place-items:center;background:rgba(91,224,169,.12);font-size:22px}
    .aoc-dialog-kicker{font-size:11px;letter-spacing:.12em;text-transform:uppercase;color:#65e0aa;font-weight:800}
    .aoc-dialog-title{margin:3px 0 0;font-size:20px;font-weight:800}
    .aoc-dialog-body{padding:8px 22px 20px;color:#aebdc4;font-size:14px;line-height:1.6;white-space:pre-wrap}
    .aoc-dialog-input{width:100%;box-sizing:border-box;border:1px solid #263640;border-radius:15px;background:#091116;color:#fff;padding:14px 15px;outline:none;font:inherit;margin-top:8px}
    .aoc-dialog-input:focus{border-color:#5ee1aa;box-shadow:0 0 0 3px rgba(94,225,170,.12)}
    .aoc-dialog-actions{display:flex;gap:10px;padding:0 22px 22px}
    .aoc-dialog-btn{flex:1;min-height:48px;border-radius:15px;border:1px solid #2a3b44;background:#111d24;color:#dce7e8;font-weight:800;font-size:14px}
    .aoc-dialog-btn.primary{background:linear-gradient(135deg,#64e5ad,#3fcf94);border-color:#64e5ad;color:#06110d}
    .aoc-dialog-btn.danger{background:#401a20;border-color:#d85b68;color:#ffd9dd}
    .aoc-dialog-btn:active{transform:scale(.98)}
    body.aoc-dialog-open{overflow:hidden}
    @media(min-width:700px){.aoc-dialog-backdrop{place-items:center}}
  `;
  document.head.appendChild(style);
}
function openAocDialog({mode='confirm',title='Konfirmasi',message='',value='',placeholder='',confirmText='Lanjutkan',cancelText='Batal',danger=false,icon='🔔'}={}) {
  ensureAocDialogStyles();
  if (aocDialogPromise) {
    // Jaga-jaga kalau ada dialog sebelumnya yang macet (tidak sempat ke-resolve),
    // supaya dialog baru tidak diam-diam gagal tampil tanpa pesan apapun.
    document.querySelectorAll('.aoc-dialog-backdrop').forEach((el) => el.remove());
    document.body.classList.remove('aoc-dialog-open');
    aocDialogPromise = null;
  }
  const wrap=document.createElement('div');
  wrap.className='aoc-dialog-backdrop';
  wrap.innerHTML=`<section class="aoc-dialog" role="dialog" aria-modal="true"><div class="aoc-dialog-head"><div class="aoc-dialog-icon">${icon}</div><div><div class="aoc-dialog-kicker">AbidzarOutdoorcamp</div><div class="aoc-dialog-title"></div></div></div><div class="aoc-dialog-body"></div><div class="aoc-dialog-actions"><button type="button" class="aoc-dialog-btn" data-cancel></button><button type="button" class="aoc-dialog-btn primary" data-ok></button></div></section>`;
  document.body.appendChild(wrap);
  const body=wrap.querySelector('.aoc-dialog-body');
  wrap.querySelector('.aoc-dialog-title').textContent=title;
  body.textContent=message;
  const ok=wrap.querySelector('[data-ok]'); const cancel=wrap.querySelector('[data-cancel]');
  cancel.textContent=cancelText; ok.textContent=confirmText; ok.classList.toggle('danger',danger);
  let input=null;
  if(mode==='prompt'){
    input=document.createElement('input'); input.className='aoc-dialog-input'; input.value=value ?? ''; input.placeholder=placeholder || '';
    input.autocomplete='off'; body.appendChild(input);
  }
  const finish=(result)=>{ if(!aocDialogPromise) return; const resolve=wrap._resolve; aocDialogPromise=null; wrap.classList.remove('is-open'); document.body.classList.remove('aoc-dialog-open'); setTimeout(()=>wrap.remove(),180); resolve(result); };
  aocDialogPromise=new Promise(resolve=>{ wrap._resolve=resolve; });
  ok.onclick=()=>finish(mode==='prompt' ? input.value : true);
  cancel.onclick=()=>finish(mode==='prompt' ? null : false);
  wrap.onclick=(e)=>{if(e.target===wrap) finish(mode==='prompt'?null:false)};
  wrap.addEventListener('keydown',(e)=>{if(e.key==='Escape') finish(mode==='prompt'?null:false); if(e.key==='Enter' && mode==='prompt') finish(input.value)});
  requestAnimationFrame(()=>wrap.classList.add('is-open'));
  setTimeout(()=>mode==='prompt' ? input.focus() : cancel.focus(),40);
  return aocDialogPromise;
}
export const aocConfirm = (message, options={}) => openAocDialog({mode:'confirm', message:String(message||''), ...options});
export const aocPrompt = (message, value='', options={}) => openAocDialog({mode:'prompt', message:String(message||''), value, ...options});
export const aocAlert = (message, options={}) => openAocDialog({mode:'alert', message:String(message||''), cancelText:'Tutup', confirmText:'Mengerti', ...options});

const CART_KEY = "tripkita_cart";
const LEGACY_CART_KEYS = [
  "tripkita_cart_v3",
  "tripkita_cart_v2",
  "tripkita_cart_v1",
];

// Penyimpanan cart aman: tetap bekerja jika localStorage dibatasi browser/privacy mode.
const cartMemory = Object.create(null);
export function cartStorageGet(key) {
  try { return window.localStorage.getItem(key); }
  catch { return Object.prototype.hasOwnProperty.call(cartMemory, key) ? cartMemory[key] : null; }
}
export function cartStorageSet(key, value) {
  try { window.localStorage.setItem(key, value); }
  catch { cartMemory[key] = value; }
}
export function cartStorageRemove(key) {
  try { window.localStorage.removeItem(key); } catch {}
  delete cartMemory[key];
}

export const rupiah = (n) =>
  new Intl.NumberFormat("id-ID", {
    style: "currency",
    currency: "IDR",
    maximumFractionDigits: 0,
  }).format(Number(n || 0));

export const esc = (value) =>
  String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");

export function message(el, text, type = "") {
  el.textContent = text;
  el.className = `notice ${type}`.trim();
  el.classList.remove("hidden");
}

export function getCart() {
  // Bila key utama sudah pernah dibuat, termasuk ketika nilainya [],
  // jangan membaca ulang key lama karena dapat menghidupkan kembali item terhapus.
  const currentValue = cartStorageGet(CART_KEY);

  if (currentValue !== null) {
    try {
      const parsed = JSON.parse(currentValue);
      return Array.isArray(parsed) ? parsed : [];
    } catch {
      cartStorageSet(CART_KEY, "[]");
      return [];
    }
  }

  // Migrasi keranjang lama hanya satu kali.
  for (const key of LEGACY_CART_KEYS) {
    try {
      const parsed = JSON.parse(cartStorageGet(key) || "[]");

      if (Array.isArray(parsed) && parsed.length > 0) {
        cartStorageSet(CART_KEY, JSON.stringify(parsed));
        LEGACY_CART_KEYS.forEach((oldKey) => cartStorageRemove(oldKey));
        return parsed;
      }
    } catch {
      cartStorageRemove(key);
    }
  }

  cartStorageSet(CART_KEY, "[]");
  LEGACY_CART_KEYS.forEach((key) => cartStorageRemove(key));
  return [];
}

export function saveCart(cart) {
  const safeCart = Array.isArray(cart) ? cart : [];
  cartStorageSet(CART_KEY, JSON.stringify(safeCart));

  // Bersihkan semua penyimpanan versi lama agar item terhapus tidak muncul kembali.
  LEGACY_CART_KEYS.forEach((key) => cartStorageRemove(key));
  updateCartBadge();
}

export function addCart(
  item,
  qty = 1,
  replace = false,
  selectedVariant = null,
  fulfillmentType = null,
  priceOverride = null,
) {
  const variant = selectedVariant?.id ? selectedVariant : null;
  const mode = fulfillmentType || (item.type === "trip" ? "trip" : "rental");
  const unitPrice =
    priceOverride !== null && Number.isFinite(Number(priceOverride))
      ? Number(priceOverride)
      : mode === "sale"
        ? (Number(item.sale_price) > 0 ? Number(item.sale_price) : Number(item.price || 0))
        : Number(item.price || 0);
  const max = Math.max(
    1,
    Number(item.type === "trip" ? item.quota : variant ? variant.stock : item.stock) || 0,
  );
  const cartKey = `${item.id}:${variant?.id || "default"}:${mode}`;
  const entry = {
    cart_key: cartKey,
    item_id: item.id,
    title: item.title,
    price: unitPrice,
    sale_price: Number(item.sale_price) > 0 ? Number(item.sale_price) : (mode === "sale" ? Number(item.price || 0) : 0),
    rental_price: mode === "rental" ? unitPrice : Number(item.price || 0),
    image_url: item.image_url,
    type: item.type,
    fulfillment_type: mode,
    trip_date: item.trip_date,
    location: item.location,
    quantity: Math.min(max, Math.max(1, Number(qty))),
    max_quantity: max,
    variant_id: variant?.id || null,
    variant_name: variant
      ? [variant.name, variant.capacity].filter(Boolean).join(" · ")
      : "",
    requires_guarantee: Boolean(item.requires_guarantee),
    guarantee_note: item.guarantee_note || "",
    deposit: Number(item.deposit || 0),
    sale_enabled: Boolean(item.sale_enabled),
    rental_enabled: item.rental_enabled !== false,
    variants: item.item_variants || [],
    price_tiers: item.item_price_tiers || [],
  };
  if (replace) return saveCart([entry]);
  const cart = getCart();
  const old = cart.find(
    (x) => (x.cart_key || `${x.item_id}:default`) === cartKey,
  );
  if (old) old.quantity = Math.min(max, Number(old.quantity) + entry.quantity);
  else cart.push(entry);
  saveCart(cart);
}

export function updateCartBadge() {
  const count = getCart().reduce((s, x) => s + Number(x.quantity || 0), 0);
  document.querySelectorAll("[data-cart-count]").forEach((el) => {
    el.textContent = count;
    el.classList.toggle("hidden", count === 0);
  });
}

const MEMBERSHIP_TIER_LABEL = { Bronze: "🥉 Bronze", Silver: "🥈 Silver", Gold: "🥇 Gold", Platinum: "💎 Platinum" };

export async function mountMembershipCard(sectionId = "membershipCardSection") {
  const section = document.getElementById(sectionId);
  if (!section) return;
  try {
    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (!user) return; // section tetap hidden, belum login

    const { data: card, error } = await supabase
      .from("membership_cards")
      .select("*")
      .eq("user_id", user.id)
      .eq("status", "active")
      .maybeSingle();
    if (error || !card) return; // belum punya kartu, section tetap hidden

    const { data: profile } = await supabase
      .from("profiles")
      .select("full_name")
      .eq("id", user.id)
      .single();

    const nameEl = document.getElementById("membershipCardName");
    const numberEl = document.getElementById("membershipCardNumber");
    const tierEl = document.getElementById("membershipCardTier");
    const cardEl = document.getElementById("membershipCard");
    const qrEl = document.getElementById("membershipCardQr");
    if (nameEl) nameEl.textContent = profile?.full_name?.trim() || user.email || "Anggota";
    if (numberEl) numberEl.textContent = card.card_number;
    if (tierEl) tierEl.textContent = MEMBERSHIP_TIER_LABEL[card.tier] || card.tier;
    if (cardEl) cardEl.dataset.membershipTier = card.tier;
    if (qrEl && window.QRCode) {
      qrEl.innerHTML = "";
      new window.QRCode(qrEl, {
        text: card.card_number,
        width: 108,
        height: 108,
        colorDark: "#0b1120",
        colorLight: "#ffffff",
      });
    }
    section.classList.remove("hidden");
  } catch (e) {
    console.warn("Gagal memuat kartu membership:", e);
  }
}

export async function setupNav() {
  updateCartBadge();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  const loginElements = document.querySelectorAll("[data-login]");
  const logoutElements = document.querySelectorAll("[data-logout]");
  const adminElements = document.querySelectorAll("[data-admin]");
  const accountMenus = document.querySelectorAll("[data-account-menu]");
  const notificationElements = document.querySelectorAll("[data-notification]");
  const userNames = document.querySelectorAll("[data-user-name]");
  const userFullNames = document.querySelectorAll("[data-user-full-name]");
  const userEmails = document.querySelectorAll("[data-user-email]");
  const userRoles = document.querySelectorAll("[data-user-role]");
  const userAvatars = document.querySelectorAll("[data-user-avatar]");

  loginElements.forEach((element) =>
    element.classList.toggle("hidden", Boolean(user)),
  );

  logoutElements.forEach((element) =>
    element.classList.toggle("hidden", !user),
  );

  accountMenus.forEach((element) => element.classList.toggle("hidden", !user));

  notificationElements.forEach((element) =>
    element.classList.toggle("hidden", !user),
  );

  let hasAdminAccess = false;

  if (user) {
    const { data: profile } = await supabase
      .from("profiles")
      .select("role,full_name,avatar_url")
      .eq("id", user.id)
      .single();

    const displayName =
      profile?.full_name?.trim() || user.email?.split("@")[0] || "Pengguna";

    const compactName =
      displayName.split(/\s+/).filter(Boolean)[0] || "Pengguna";

    const initial = compactName.slice(0, 1).toUpperCase() || "U";

    const normalizedRole = String(profile?.role || "")
      .trim()
      .toLowerCase();

    hasAdminAccess = ["admin", "super_admin", "superadmin", "order_admin", "catalog_admin", "finance_admin", "warehouse_staff"].includes(normalizedRole);

    if (!hasAdminAccess) {
      const { data: rpcAdmin } = await supabase.rpc("is_admin");
      hasAdminAccess = rpcAdmin === true;
    }

    userNames.forEach((element) => {
      element.textContent = `Halo, ${compactName}`;
      element.title = `Login sebagai ${displayName}`;
    });

    userFullNames.forEach((element) => {
      element.textContent = displayName;
    });

    userEmails.forEach((element) => {
      element.textContent = user.email || "-";
    });

    userRoles.forEach((element) => {
      element.textContent = hasAdminAccess ? "Administrator" : "Pengguna";
    });

    userAvatars.forEach((element) => {
      element.innerHTML = "";
      if (profile?.avatar_url) {
        const image = document.createElement("img");
        image.src = profile.avatar_url;
        image.alt = `Foto profil ${displayName}`;
        element.appendChild(image);
      } else {
        element.textContent = initial;
      }
    });
  }

  adminElements.forEach((element) => {
    element.classList.toggle("hidden", !hasAdminAccess);
    element.setAttribute("aria-hidden", String(!hasAdminAccess));
  });

  logoutElements.forEach((button) => {
    button.onclick = async () => {
      await supabase.auth.signOut();
      location.href = "index.html";
    };
  });

  const accountToggle = document.querySelector("[data-user-menu-toggle]");
  const accountDropdown = document.querySelector("[data-user-dropdown]");

  const closeAccountMenu = () => {
    if (!accountToggle || !accountDropdown) return;

    accountDropdown.classList.remove("is-open");
    accountDropdown.setAttribute("aria-hidden", "true");
    accountToggle.setAttribute("aria-expanded", "false");
  };

  const openAccountMenu = () => {
    if (!accountToggle || !accountDropdown) return;

    accountDropdown.classList.add("is-open");
    accountDropdown.setAttribute("aria-hidden", "false");
    accountToggle.setAttribute("aria-expanded", "true");
  };

  if (
    accountToggle &&
    accountDropdown &&
    accountToggle.dataset.bound !== "true"
  ) {
    accountToggle.dataset.bound = "true";

    accountToggle.addEventListener("click", (event) => {
      event.stopPropagation();

      if (accountDropdown.classList.contains("is-open")) {
        closeAccountMenu();
      } else {
        openAccountMenu();
      }
    });

    accountDropdown.addEventListener("click", (event) => {
      event.stopPropagation();

      if (event.target.closest("a, [data-logout]")) {
        closeAccountMenu();
      }
    });

    document.addEventListener("click", (event) => {
      if (
        !accountDropdown.contains(event.target) &&
        !accountToggle.contains(event.target)
      ) {
        closeAccountMenu();
      }
    });

    document.addEventListener("keydown", (event) => {
      if (event.key === "Escape") {
        closeAccountMenu();
        accountToggle.focus();
      }
    });
  }

  const navToggle = document.querySelector("[data-nav-toggle]");
  const navMenu = document.querySelector("[data-nav-menu]");

  if (navToggle && navMenu && navToggle.dataset.bound !== "true") {
    navToggle.dataset.bound = "true";

    const closeMenu = () => {
      navMenu.classList.remove("is-open");
      navToggle.setAttribute("aria-expanded", "false");
      navToggle.innerHTML = '<span aria-hidden="true">☰</span>';
      closeAccountMenu();
    };

    const openMenu = () => {
      navMenu.classList.add("is-open");
      navToggle.setAttribute("aria-expanded", "true");
      navToggle.innerHTML = '<span aria-hidden="true">✕</span>';
    };

    navToggle.addEventListener("click", (event) => {
      event.stopPropagation();

      if (navMenu.classList.contains("is-open")) closeMenu();
      else openMenu();
    });

    navMenu.querySelectorAll("a, button").forEach((element) => {
      element.addEventListener("click", () => {
        if (
          window.innerWidth <= 1080 &&
          !element.matches("[data-user-menu-toggle]")
        ) {
          closeMenu();
        }
      });
    });

    document.addEventListener("click", (event) => {
      if (
        window.innerWidth <= 1080 &&
        navMenu.classList.contains("is-open") &&
        !navMenu.contains(event.target) &&
        !navToggle.contains(event.target)
      ) {
        closeMenu();
      }
    });

    window.addEventListener("resize", () => {
      if (window.innerWidth > 1080) {
        closeMenu();
      }
    });
  }
}

document.addEventListener("DOMContentLoaded", () => {
  setupNav();
  loadSiteSettings()
    .then(applySiteSettings)
    .catch(() => {
      applySiteSettings(DEFAULT_SITE_SETTINGS);
    });
});

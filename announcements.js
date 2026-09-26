import { supabase } from "./app.js";

const ICONS = { info:"📢", promo:"🔥", warning:"⚠️", event:"🏕️", new:"🆕" };
const LABELS = { info:"Informasi", promo:"Promo", warning:"Penting", event:"Event", new:"Terbaru" };
const esc = (s="") => String(s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[c]));
const safeUrl = (value="") => {
  try { const u = new URL(String(value), window.location.href); return ["http:","https:","mailto:","tel:"].includes(u.protocol) ? u.href : ""; }
  catch { return ""; }
};
const fmt = d => d ? new Date(d).toLocaleString("id-ID",{day:"2-digit",month:"short",year:"numeric",hour:"2-digit",minute:"2-digit"}) : "";
const activeAnnouncementQuery = () => {
  const now = new Date().toISOString();
  return supabase.from("site_announcements").select("*")
    .eq("is_active",true).lte("starts_at",now)
    .or(`ends_at.is.null,ends_at.gt.${now}`)
    .order("sort_order",{ascending:true}).order("created_at",{ascending:false});
};
export async function loadAnnouncements(limit=5){ const {data,error}=await activeAnnouncementQuery().limit(limit); if(error) throw error; return data||[]; }

function announcementMarkup(a){
  const icon=ICONS[a.category]||"📢", label=LABELS[a.category]||"Pengumuman", url=safeUrl(a.action_url);
  return `<div class="announcement-content">
    <div class="announcement-banner-glow"></div>
    <div class="announcement-banner-icon" aria-hidden="true">${icon}</div>
    <div class="announcement-banner-copy">
      <span class="announcement-banner-label"><span class="announcement-live-dot"></span>${esc(label)} · Pengumuman</span>
      <strong>${esc(a.title)}</strong><p>${esc(a.content)}</p>
    </div>
    <div class="announcement-banner-right">
      ${url?`<a class="btn announcement-banner-action" href="${esc(url)}">${esc(a.action_label||"Lihat Selengkapnya")} <span>→</span></a>`:""}
      <small>${fmt(a.starts_at)}</small>
    </div>
  </div>`;
}

function showPopup(a){
  if(!a) return;
  const key=`aoc-announcement-seen-${a.id}`;
  if(sessionStorage.getItem(key)==="1") return;
  document.getElementById("announcementPopup")?.remove();
  const icon=ICONS[a.category]||"📢", label=LABELS[a.category]||"Pengumuman", url=safeUrl(a.action_url), image=safeUrl(a.image_url);
  const modal=document.createElement("div");
  modal.id="announcementPopup"; modal.className="announcement-modal"; modal.setAttribute("role","dialog"); modal.setAttribute("aria-modal","true");
  modal.innerHTML=`<div class="announcement-modal-backdrop" data-announcement-close></div>
    <div class="announcement-modal-card" role="document">
      <div class="announcement-modal-topline"></div>
      <button class="announcement-modal-close" type="button" aria-label="Tutup pengumuman" data-announcement-close>×</button>
      ${image?`<div class="announcement-modal-hero"><img class="announcement-modal-image" src="${esc(image)}" alt=""><div class="announcement-modal-hero-shade"></div><span class="announcement-modal-hero-brand">ABIDZAR OUTDOORCAMP</span></div>`:`<div class="announcement-modal-hero announcement-modal-hero-empty"><div class="announcement-hero-orb orb-a"></div><div class="announcement-hero-orb orb-b"></div><div class="announcement-hero-symbol">${icon}</div><span class="announcement-modal-hero-brand">ABIDZAR OUTDOORCAMP</span></div>`}
      <div class="announcement-modal-body">
        <div class="announcement-modal-kicker"><span class="announcement-live-dot"></span>${icon} ${esc(label)}</div>
        <h2>${esc(a.title)}</h2><p>${esc(a.content)}</p>
        <div class="announcement-modal-footer">
          <span class="announcement-modal-date">${fmt(a.starts_at)}</span>
          ${url?`<a class="btn announcement-modal-action" href="${esc(url)}">${esc(a.action_label||"Lihat Selengkapnya")} <span>→</span></a>`:""}
        </div>
      </div>
    </div>`;
  document.body.appendChild(modal);
  requestAnimationFrame(()=>modal.classList.add("is-open"));
  const close=()=>{ sessionStorage.setItem(key,"1"); modal.classList.remove("is-open"); setTimeout(()=>modal.remove(),260); document.removeEventListener("keydown",onKey); };
  const onKey=e=>{ if(e.key==="Escape") close(); };
  modal.querySelectorAll("[data-announcement-close]").forEach(el=>el.addEventListener("click",close));
  document.addEventListener("keydown",onKey);
}

function renderBanner(rows){
  const box=document.getElementById("announcementBanner"); if(!box||!rows.length) return;
  let index=0;
  const render=()=>{ const a=rows[index%rows.length]; box.innerHTML=announcementMarkup(a); box.classList.remove("hidden");
    if(rows.length>1){ box.querySelector(".announcement-banner-content-extra")?.remove(); }
  };
  render();
  if(rows.length>1){
    let timer=setInterval(()=>{ if(!document.body.contains(box)){clearInterval(timer);return;} index=(index+1)%rows.length; render(); },6500);
  }
}

export async function mountAnnouncements({containerId="announcementList",sectionId="announcements"}={}){
  const box=document.getElementById(containerId), section=document.getElementById(sectionId);
  try{
    const rows=await loadAnnouncements();
    if(!rows.length){ section?.classList.add("hidden"); return; }
    if(box) {
      box.innerHTML=rows.map(a=>{
        const image=safeUrl(a.image_url), url=safeUrl(a.action_url), label=LABELS[a.category]||"Pengumuman";
        return `<article class="announcement-card">
          <div class="announcement-card-shine"></div>
          ${image?`<div class="announcement-card-media"><img src="${esc(image)}" alt="" loading="lazy"><span>${ICONS[a.category]||"📢"} ${esc(label)}</span></div>`:`<div class="announcement-card-media announcement-card-media-empty"><span class="announcement-card-icon">${ICONS[a.category]||"📢"}</span><span>${esc(label)}</span></div>`}
          <div class="announcement-body">
            <div class="announcement-card-kicker"><span class="announcement-live-dot"></span>${esc(label)}<span class="announcement-card-kicker-sep">•</span><span>Info terbaru</span></div>
            <h3>${esc(a.title)}</h3><p>${esc(a.content)}</p>
            <div class="announcement-card-footer"><span class="announcement-meta"><span>◷ ${fmt(a.starts_at)}</span></span>
              ${url?`<a class="announcement-action" href="${esc(url)}">${esc(a.action_label||"Lihat Selengkapnya")} <span>↗</span></a>`:""}
            </div>
          </div></article>`;
      }).join("");
      box.querySelectorAll('.announcement-card-media img').forEach(img=>img.addEventListener('error',()=>{
        const media=img.closest('.announcement-card-media');
        if(!media) return;
        const label=media.querySelector('span')?.textContent || '📢 Pengumuman';
        media.classList.add('announcement-card-media-empty');
        media.innerHTML=`<span class="announcement-card-icon">📢</span><span>${esc(label)}</span>`;
      },{once:true}));
    }
    renderBanner(rows); showPopup(rows[0]);
  }catch(e){ console.error("Announcement load:",e); section?.classList.add("hidden"); }
}

export async function listAllAnnouncements(){
 const {data,error}=await supabase.from("site_announcements").select("*").order("sort_order").order("created_at",{ascending:false});
 if(error) throw error; return data||[];
}
export async function saveAnnouncement(payload,id=null){
 const body={...payload,updated_at:new Date().toISOString()};
 if(id) return supabase.from("site_announcements").update(body).eq("id",id).select().single();
 body.created_by=(await supabase.auth.getUser()).data.user?.id||null;
 return supabase.from("site_announcements").insert(body).select().single();
}
export async function deleteAnnouncement(id){ return supabase.from("site_announcements").delete().eq("id",id); }

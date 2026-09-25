(function () {
  'use strict';
  const SUPABASE_URL = 'https://radrtmyrckylvvmdhgqs.supabase.co';
  const SUPABASE_ANON_KEY = 'sb_publishable_ad-kaXlIwFlCmV3cR3yDpA_Iq2oWMKk';
  let stream = null, running = false, modal = null;

  function esc(v) { return String(v ?? '').replace(/[&<>'"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c])); }
  function rupiah(v) { return new Intl.NumberFormat('id-ID',{style:'currency',currency:'IDR',maximumFractionDigits:0}).format(Number(v)||0); }
  function token() {
    for (let i=0;i<localStorage.length;i++) {
      const k=localStorage.key(i)||'';
      if (!k.includes('auth-token')) continue;
      try { const x=JSON.parse(localStorage.getItem(k)||'{}'); if (x.access_token) return x.access_token; } catch (_) {}
    }
    return '';
  }
  async function api(path, options={}) {
    const t=token();
    if (!t) throw new Error('Session login tidak ditemukan. Login sebagai admin terlebih dahulu.');
    const r=await fetch(SUPABASE_URL + path,{...options,headers:{apikey:SUPABASE_ANON_KEY,Authorization:'Bearer '+t,'Content-Type':'application/json',...(options.headers||{})}});
    const text=await r.text(); let data; try { data=text?JSON.parse(text):null; } catch (_) { data=text; }
    if (!r.ok) throw new Error(data?.message || data?.error_description || data?.hint || `Request gagal (${r.status})`);
    return data;
  }
  function qrValue(raw) {
    let v=String(raw||'').trim();
    try { if (/^https?:\/\//i.test(v)) { const u=new URL(v); v=u.searchParams.get('card')||u.searchParams.get('member')||u.searchParams.get('token')||v; } } catch (_) {}
    return v.replace(/^AOC:(?:MEMBER|MEMBERSHIP):/i,'').trim();
  }
  function styles(){
    if(document.getElementById('aocStandaloneScannerStyle')) return;
    const s=document.createElement('style'); s.id='aocStandaloneScannerStyle'; s.textContent=`
      #aocStandaloneScanBtn{margin:10px 14px;padding:11px 15px;border:0;border-radius:13px;background:#63e6a8;color:#06130d;font-weight:800;cursor:pointer;display:inline-flex;align-items:center;gap:8px}
      #aocStandaloneScanModal{position:fixed;inset:0;z-index:99999;background:rgba(2,6,10,.9);display:flex;align-items:center;justify-content:center;padding:14px}
      .aoc-ss-card{width:min(560px,100%);max-height:94vh;overflow:auto;background:#0c131a;color:#fff;border:1px solid rgba(255,255,255,.14);border-radius:22px;padding:14px;box-shadow:0 25px 90px #000}
      .aoc-ss-head{display:flex;justify-content:space-between;align-items:center;gap:12px}.aoc-ss-close{width:42px;height:42px;border:0;border-radius:12px;background:#ffffff14;color:#fff;font-size:24px}
      .aoc-ss-camera{position:relative;aspect-ratio:1;background:#000;border-radius:18px;overflow:hidden;margin:12px 0}.aoc-ss-camera video{width:100%;height:100%;object-fit:cover}.aoc-ss-frame{position:absolute;inset:18%;border:2px solid #63e6a8;border-radius:18px;box-shadow:0 0 0 999px #0004}.aoc-ss-status{padding:11px;border-radius:12px;background:#ffffff0d;font-size:13px}.aoc-ss-result{margin-top:12px}.aoc-ss-grid{display:grid;grid-template-columns:1fr 1fr;gap:8px}.aoc-ss-stat{background:#ffffff0a;padding:10px;border-radius:12px}.aoc-ss-stat small{display:block;opacity:.65}.aoc-ss-history{display:grid;gap:7px;margin-top:8px}.aoc-ss-row{padding:10px;border-radius:11px;background:#ffffff08;display:flex;justify-content:space-between;gap:10px}@media(max-width:520px){.aoc-ss-grid{grid-template-columns:1fr}}
    `; document.head.appendChild(s);
  }
  function close(){ running=false; if(stream){stream.getTracks().forEach(t=>t.stop());stream=null;} if(modal){modal.remove();modal=null;} }
  async function lookup(raw,status,result){
    const v=qrValue(raw); status.textContent='QR terbaca. Memuat data member...';
    let lookup=null;
    try { lookup=await api('/rest/v1/rpc/aoc_secure_member_lookup',{method:'POST',body:JSON.stringify({p_code:v})}); } catch (e) { status.textContent=e?.message||'Member tidak ditemukan.'; return; }
    const customer=lookup?.member ? {...lookup.member,user_id:lookup.member.user_id,total_spent:lookup.total_spent||0} : null;
    const card=lookup?.card||null;
    const history=Array.isArray(lookup?.history)?lookup.history:[];
    if(!customer){ status.textContent='QR terbaca, tetapi member tidak ditemukan.'; return; }
    status.textContent='Member ditemukan.';
    result.innerHTML=`<div class="aoc-ss-result"><h3 style="margin:8px 0">${esc(customer.full_name||customer.email||'Member')}</h3><p style="opacity:.7;margin:0 0 10px">${esc(card?.card_number||v)} · ${esc(card?.tier||'Member')}</p><div class="aoc-ss-grid"><div class="aoc-ss-stat"><small>WhatsApp</small><b>${esc(customer.phone||'-')}</b></div><div class="aoc-ss-stat"><small>Email</small><b>${esc(customer.email||'-')}</b></div><div class="aoc-ss-stat"><small>Status</small><b>${customer.is_blocked?'🔴 Diblokir':customer.is_verified?'🟢 Aktif':'🟡 Belum verifikasi'}</b></div><div class="aoc-ss-stat"><small>Total transaksi</small><b>${rupiah(customer.total_spent||0)}</b></div></div><h4 style="margin:16px 0 6px">Riwayat Rental</h4><div class="aoc-ss-history">${history.map(o=>`<div class="aoc-ss-row"><span><b>${esc(o.order_number||'-')}</b><br><small>${esc(o.status||'-')} · ${o.created_at?new Date(o.created_at).toLocaleDateString('id-ID'):'-'}</small></span><b>${rupiah(Number(o.total||0)+Number(o.late_fee||0))}</b></div>`).join('')||'<div style="opacity:.65">Belum ada riwayat rental.</div>'}</div></div>`;
    running=false; if(stream){stream.getTracks().forEach(t=>t.stop());stream=null;}
  }
  async function open(){
    styles(); close();
    if(!navigator.mediaDevices?.getUserMedia){alert('Kamera membutuhkan HTTPS atau localhost.');return;}
    if(!window.BarcodeDetector){alert('Browser HP ini belum mendukung QR camera scanner bawaan. Gunakan Chrome terbaru.');return;}
    modal=document.createElement('div'); modal.id='aocStandaloneScanModal'; modal.innerHTML=`<div class="aoc-ss-card"><div class="aoc-ss-head"><div><b>📷 SCAN MEMBER</b><h3 style="margin:5px 0">Scan QR Member</h3><small>Arahkan QR kartu ke kotak.</small></div><button class="aoc-ss-close" type="button">×</button></div><div class="aoc-ss-camera"><video autoplay muted playsinline></video><div class="aoc-ss-frame"></div></div><div class="aoc-ss-status">Menyalakan kamera...</div><div class="aoc-ss-result"></div></div>`;
    document.body.appendChild(modal); modal.querySelector('.aoc-ss-close').onclick=close;
    const video=modal.querySelector('video'), status=modal.querySelector('.aoc-ss-status'), result=modal.querySelector('.aoc-ss-result');
    try{stream=await navigator.mediaDevices.getUserMedia({video:{facingMode:{ideal:'environment'},width:{ideal:1280},height:{ideal:720}},audio:false}); video.srcObject=stream; await video.play(); const detector=new BarcodeDetector({formats:['qr_code']}); running=true; status.textContent='Kamera aktif — arahkan QR ke kotak scan.'; const loop=async()=>{if(!running||!document.body.contains(modal))return;try{if(video.readyState>=2){const codes=await detector.detect(video);if(codes?.length){await lookup(codes[0].rawValue,status,result);return;}}}catch(e){status.textContent='Scanner aktif — arahkan QR dengan jelas.';}if(running)setTimeout(loop,180);}; loop();}catch(e){status.textContent='Kamera gagal dibuka: '+(e?.message||'izin kamera ditolak');}
  }
  function mount(){
    const nav=document.querySelector('nav')||document.querySelector('header'); if(!nav)return;
    if(document.getElementById('aocStandaloneScanBtn'))return;
    const b=document.createElement('button'); b.id='aocStandaloneScanBtn'; b.type='button'; b.innerHTML='📷 Scan Member'; b.onclick=open; nav.appendChild(b);
  }
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',mount);else mount(); setTimeout(mount,1200); setTimeout(mount,3000);
})();

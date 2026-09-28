import { supabase } from './app.js?v=20260928-v36';

const $ = (id) => document.getElementById(id);
const esc = (v) => String(v ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[c]));
const BUCKET = 'community-gallery';
const MAX = 15 * 1024 * 1024;
const ALLOWED = new Set(['image/jpeg','image/png','image/webp','image/gif','video/mp4','video/webm','application/pdf']);
let currentUser = null;
let rows = [];

function msg(text, type='success') {
  const el = $('galleryMsg');
  el.textContent = text;
  el.className = `notice ${type === 'error' ? 'error' : 'success'}`;
  el.classList.remove('hidden');
}
function hideMsg(){ $('galleryMsg').classList.add('hidden'); }
function fmtSize(n){
  if (!n) return '0 B';
  const u=['B','KB','MB','GB']; let i=0, x=Number(n);
  while(x>=1024 && i<u.length-1){x/=1024;i++;}
  return `${x.toFixed(i?1:0)} ${u[i]}`;
}
function safeName(name){ return String(name||'file').replace(/[^a-zA-Z0-9._-]/g,'_').slice(0,120); }
function mediaHtml(row){
  const url = esc(row.file_url);
  const type = String(row.mime_type||'');
  if(type.startsWith('image/')) return `<img class="gallery-media" src="${url}" alt="${esc(row.caption||row.file_name)}" loading="lazy">`;
  if(type.startsWith('video/')) return `<video class="gallery-media" controls preload="metadata"><source src="${url}" type="${esc(type)}"></video>`;
  return `<div class="gallery-file-icon">📄<strong>PDF</strong></div>`;
}

async function loadGallery(){
  const list = $('galleryList');
  list.innerHTML = '<div class="notice">Memuat galeri...</div>';
  const {data,error} = await supabase.from('community_gallery').select('*').order('created_at',{ascending:false}).limit(100);
  if(error){ list.innerHTML = `<div class="notice error">${esc(error.message)}<br><small>Pastikan gallery.sql sudah dijalankan di Supabase.</small></div>`; return; }
  rows = data || [];
  if(!rows.length){ list.innerHTML='<div class="notice">Belum ada file di galeri. Jadilah yang pertama mengunggah.</div>'; return; }
  list.innerHTML = rows.map(r => `
    <article class="gallery-card">
      <a class="gallery-preview" href="${esc(r.file_url)}" target="_blank" rel="noopener noreferrer">${mediaHtml(r)}</a>
      <div class="gallery-card-body">
        <strong>${esc(r.caption || r.file_name)}</strong>
        <small>${esc(r.file_name)} · ${fmtSize(r.file_size)} · ${new Date(r.created_at).toLocaleString('id-ID')}</small>
        ${currentUser && String(currentUser.id)===String(r.user_id) ? `<button class="btn danger small gallery-delete" data-id="${esc(r.id)}" type="button">Hapus file saya</button>` : ''}
      </div>
    </article>`).join('');
}

async function boot(){
  const {data} = await supabase.auth.getSession();
  currentUser = data?.session?.user || null;
  $('loginHint').classList.toggle('hidden', !!currentUser);
  $('uploadBox').classList.toggle('hidden', !currentUser);
  if(currentUser){
    $('uploadForm').addEventListener('submit', upload);
  }
  $('galleryList').addEventListener('click', async (e)=>{
    const btn=e.target.closest('[data-id]'); if(!btn || !currentUser) return;
    if(!confirm('Hapus file ini dari galeri?')) return;
    const row=rows.find(x=>String(x.id)===String(btn.dataset.id));
    if(!row || String(row.user_id)!==String(currentUser.id)) return msg('Anda hanya dapat menghapus file milik sendiri.','error');
    const sr=await supabase.storage.from(BUCKET).remove([row.file_path]);
    if(sr.error) return msg(sr.error.message,'error');
    const dr=await supabase.from('community_gallery').delete().eq('id',row.id).eq('user_id',currentUser.id);
    if(dr.error) return msg(dr.error.message,'error');
    msg('File berhasil dihapus.'); loadGallery();
  });
  loadGallery();
}

async function upload(e){
  e.preventDefault(); hideMsg();
  const input=$('galleryFiles'); const files=[...(input.files||[])];
  if(!files.length) return msg('Pilih minimal 1 file.','error');
  if(files.length>10) return msg('Maksimal 10 file sekali upload.','error');
  for(const file of files){
    if(!ALLOWED.has(file.type)) return msg(`Format ${file.name} tidak didukung. Gunakan JPG, PNG, WEBP, GIF, MP4, WEBM, atau PDF.`,'error');
    if(file.size>MAX) return msg(`${file.name} melebihi batas 15 MB.`,'error');
  }
  const caption=$('galleryCaption').value.trim().slice(0,180);
  $('uploadBtn').disabled=true; $('uploadBtn').textContent='Mengunggah...';
  try{
    for(const file of files){
      const path=`${currentUser.id}/${crypto.randomUUID()}-${safeName(file.name)}`;
      const up=await supabase.storage.from(BUCKET).upload(path,file,{contentType:file.type,upsert:false});
      if(up.error) throw up.error;
      const pub=supabase.storage.from(BUCKET).getPublicUrl(path).data.publicUrl;
      const ins=await supabase.from('community_gallery').insert({user_id:currentUser.id,file_name:file.name,file_path:path,file_url:pub,mime_type:file.type,file_size:file.size,caption:caption||null});
      if(ins.error){ await supabase.storage.from(BUCKET).remove([path]); throw ins.error; }
    }
    $('uploadForm').reset(); msg('File berhasil diunggah ke galeri.'); await loadGallery();
  }catch(err){ msg(err?.message||'Upload gagal.','error'); }
  finally{ $('uploadBtn').disabled=false; $('uploadBtn').textContent='📤 Upload ke Galeri'; }
}

boot();

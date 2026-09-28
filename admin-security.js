const AOC_ADMIN_SECURITY_CONFIG = {
  SUPABASE_URL: "https://radrtmyrckylvvmdhgqs.supabase.co",
  SUPABASE_ANON_KEY: "sb_publishable_ad-kaXlIwFlCmV3cR3yDpA_Iq2oWMKk"
};
const adminSecuritySupabase = window.supabase?.createClient?.(
  AOC_ADMIN_SECURITY_CONFIG.SUPABASE_URL,
  AOC_ADMIN_SECURITY_CONFIG.SUPABASE_ANON_KEY
);
if (!adminSecuritySupabase) throw new Error("Library Supabase gagal dimuat.");

/*
 * AOC ADMIN SECURITY LAYER
 * Front-end mode: no extra SQL/RPC is required for PIN setup.
 * The PIN is stored as a salted SHA-256 digest in this browser and is never
 * stored as plain text. A verified session lasts 10 minutes.
 * IMPORTANT: this is an application/UI gate, not a database authorization layer.
 */
const STORAGE_KEY = "aoc_admin_security_pin_v1";
const SESSION_KEY = "aoc_admin_security_session_v1";
let codePromise = null;
let initialized = false;
let guardInstalled = false;

function el(id){return document.getElementById(id);}
function setStatus(message,type=""){
  const node=el("aocAdminSecurityStatus");
  if(!node)return;
  node.textContent=message||"";
  node.className=`aoc-admin-security-status ${type}`;
}
function showModal(mode="verify"){
  const modal=el("aocAdminSecurityModal");
  const setup=el("aocAdminSecuritySetup");
  const verify=el("aocAdminSecurityVerify");
  if(!modal)return;
  setup?.classList.toggle("hidden",mode!=="setup");
  verify?.classList.toggle("hidden",mode!=="verify");
  modal.classList.remove("hidden");
  modal.setAttribute("aria-hidden","false");
  setTimeout(()=>el(mode==="setup"?"aocAdminSecurityNewCode":"aocAdminSecurityCode")?.focus(),40);
}
function hideModal(){
  const modal=el("aocAdminSecurityModal");
  if(!modal)return;
  modal.classList.add("hidden");
  modal.setAttribute("aria-hidden","true");
  ["aocAdminSecurityCode","aocAdminSecurityNewCode","aocAdminSecurityConfirmCode"].forEach(id=>{const x=el(id);if(x)x.value="";});
}
function bytesToHex(bytes){return Array.from(bytes).map(b=>b.toString(16).padStart(2,"0")).join("");}
function randomSalt(){
  const bytes=new Uint8Array(16);
  crypto.getRandomValues(bytes);
  return bytesToHex(bytes);
}
async function sha256(text){
  const data=new TextEncoder().encode(text);
  const digest=await crypto.subtle.digest("SHA-256",data);
  return bytesToHex(new Uint8Array(digest));
}
async function hashPin(pin,salt){return sha256(`${salt}:${pin}:AOC-ADMIN-PIN`);}
function readPinRecord(){
  try{return JSON.parse(localStorage.getItem(STORAGE_KEY)||"null");}catch{return null;}
}
function writePinRecord(record){localStorage.setItem(STORAGE_KEY,JSON.stringify(record));}
function hasPin(){const r=readPinRecord();return !!(r?.hash&&r?.salt);}
function clearSession(){try{sessionStorage.removeItem(SESSION_KEY);}catch{}}
function sessionValid(){
  try{
    const t=Number(sessionStorage.getItem(SESSION_KEY)||0);
    return Number.isFinite(t)&&t>Date.now();
  }catch{return false;}
}
function startSession(){try{sessionStorage.setItem(SESSION_KEY,String(Date.now()+10*60*1000));}catch{}}

async function verifyCodeInteractive(){
  if(sessionValid())return true;
  if(!hasPin()){
    setStatus("PIN Admin belum dibuat. Buat PIN Admin terlebih dahulu.","error");
    return false;
  }
  if(codePromise)return codePromise;
  codePromise=new Promise((resolve)=>{
    showModal("verify");
    const input=el("aocAdminSecurityCode");
    const btn=el("aocAdminSecurityVerifyBtn");
    const cancel=el("aocAdminSecurityCancelBtn");
    const finish=(ok)=>{resolve(ok);codePromise=null;if(ok)hideModal();};
    if(btn)btn.onclick=async()=>{
      const code=String(input?.value||"").replace(/\D/g,"").slice(0,8);
      if(!/^\d{8}$/.test(code)){setStatus("Masukkan tepat 8 digit kode admin.","error");return;}
      btn.disabled=true;setStatus("Memverifikasi kode admin...");
      try{
        const record=readPinRecord();
        const digest=await hashPin(code,record.salt);
        if(digest===record.hash){startSession();setStatus("Kode benar. Perubahan admin diizinkan.","success");finish(true);}
        else{setStatus("Kode admin salah.","error");btn.disabled=false;}
      }catch(e){setStatus(e?.message||"Verifikasi kode gagal.","error");btn.disabled=false;}
    };
    if(cancel)cancel.onclick=()=>finish(false);
    input?.addEventListener("input",()=>{input.value=input.value.replace(/\D/g,"").slice(0,8);});
  });
  return codePromise;
}

async function setupCodeInteractive(){
  const input=el("aocAdminSecurityNewCode");
  const confirm=el("aocAdminSecurityConfirmCode");
  const btn=el("aocAdminSecuritySetupBtn");
  showModal("setup");
  return new Promise((resolve)=>{
    const finish=(ok)=>{resolve(ok);};
    btn.onclick=async()=>{
      const a=String(input?.value||"").replace(/\D/g,"").slice(0,8);
      const b=String(confirm?.value||"").replace(/\D/g,"").slice(0,8);
      if(!/^\d{8}$/.test(a))return setStatus("Kode admin harus tepat 8 digit.","error");
      if(a!==b)return setStatus("Konfirmasi kode tidak sama.","error");
      btn.disabled=true;setStatus("Menyimpan kode admin...");
      try{
        const salt=randomSalt();
        const hash=await hashPin(a,salt);
        writePinRecord({version:1,salt,hash,updatedAt:new Date().toISOString()});
        setStatus("Kode admin berhasil dibuat.","success");
        setTimeout(()=>{hideModal();finish(true);refreshAdminPinStatus();},350);
      }catch(e){setStatus(e?.message||"Kode gagal disimpan.","error");btn.disabled=false;}
    };
    el("aocAdminSecuritySetupCancelBtn")?.addEventListener("click",()=>{hideModal();finish(false);},{once:true});
    [input,confirm].forEach(x=>x?.addEventListener("input",()=>{x.value=x.value.replace(/\D/g,"").slice(0,8);}));
  });
}

async function getAdminRole(){
  try{
    const {data:userData}=await adminSecuritySupabase.auth.getUser();
    const uid=userData?.user?.id;if(!uid)return "";
    const {data,error}=await adminSecuritySupabase.from("profiles").select("role").eq("id",uid).maybeSingle();
    if(!error&&data?.role)return String(data.role).toLowerCase();
  }catch{}
  return "";
}
async function isSuperAdmin(){const role=await getAdminRole();return role==="super_admin"||role==="superadmin";}
async function ensureAdminCodeExists(){
  if(hasPin())return true;
  if(!(await isSuperAdmin())){setStatus("PIN Admin belum dibuat. Hubungi SUPERADMIN untuk membuat PIN Admin.","error");return false;}
  return setupCodeInteractive();
}
async function ensureAdminMutationAllowed(){
  const {data:userData}=await adminSecuritySupabase.auth.getUser();
  if(!userData?.user)return false;
  if(!(await ensureAdminCodeExists()))return false;
  return verifyCodeInteractive();
}
function installFetchGuard(){if(guardInstalled)return;guardInstalled=true;}
async function initAdminSecurity(){
  if(initialized)return;initialized=true;installFetchGuard();
  const {data:userData}=await adminSecuritySupabase.auth.getUser();
  if(!userData?.user)return;
  const {data:isAdmin}=await adminSecuritySupabase.rpc("is_admin");
  if(isAdmin!==true)return;
}
async function openAdminPinSetup(){
  if(!(await isSuperAdmin())){setStatus("Hanya SUPERADMIN yang dapat membuat atau mengganti PIN Admin.","error");return false;}
  return setupCodeInteractive();
}
async function refreshAdminPinStatus(targetId="aocAdminPinStatus"){
  const node=el(targetId);if(!node)return;
  try{
    const superAdmin=await isSuperAdmin();
    if(!superAdmin){node.textContent="Hanya SUPERADMIN yang dapat mengelola PIN Admin.";return;}
    const exists=hasPin();
    node.textContent=exists?"PIN Admin sudah dibuat di perangkat ini.":"PIN Admin belum dibuat.";
    node.className=`muted ${exists?"success":"warning"}`;
  }catch{node.textContent="Status PIN tidak dapat diperiksa.";}
}
if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",initAdminSecurity,{once:true});else initAdminSecurity();
window.aocAdminSecurity={ensure:ensureAdminMutationAllowed,setup:openAdminPinSetup,verify:verifyCodeInteractive,isSuperAdmin,refreshStatus:refreshAdminPinStatus,clearSession};

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
 * AOC ADMIN SECURITY V39
 * PIN Admin disimpan PER AKUN di database Supabase melalui RPC security-definer.
 * PIN tidak disimpan di localStorage dan tidak pernah disimpan sebagai plaintext.
 *
 * Alur:
 * - Setiap admin membuat PIN Admin milik akunnya sendiri.
 * - Verifikasi selalu memakai auth.uid() akun yang sedang login.
 * - Session unlock hanya berlaku di tab/perangkat saat ini selama 10 menit.
 * - Database menyimpan hash bcrypt + salt internal, bukan PIN asli.
 */
const SESSION_KEY = "aoc_admin_security_session_v2";
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
  ["aocAdminSecurityCode","aocAdminSecurityNewCode","aocAdminSecurityConfirmCode","aocAdminSecurityCurrentCode"].forEach(id=>{
    const x=el(id); if(x)x.value="";
  });
}
function clearSession(){try{sessionStorage.removeItem(SESSION_KEY);}catch{}}
function sessionValid(){
  try{
    const raw=sessionStorage.getItem(SESSION_KEY);
    if(!raw)return false;
    const data=JSON.parse(raw);
    return Number(data?.expiresAt||0)>Date.now();
  }catch{return false;}
}
function startSession(){
  try{
    sessionStorage.setItem(SESSION_KEY,JSON.stringify({
      userId: adminSecuritySupabase.auth.getUser ? null : null,
      expiresAt: Date.now()+10*60*1000
    }));
  }catch{}
}

async function currentUser(){
  const {data,error}=await adminSecuritySupabase.auth.getUser();
  if(error) return null;
  return data?.user||null;
}

async function hasPin(){
  const {data,error}=await adminSecuritySupabase.rpc("has_admin_security_pin");
  if(error) throw error;
  return data===true;
}

async function verifyCodeInteractive(){
  if(sessionValid())return true;

  const exists=await hasPin().catch(error=>{
    setStatus(`Gagal memeriksa PIN Admin: ${error?.message||"RPC belum tersedia."}`,"error");
    return null;
  });
  if(exists===null)return false;
  if(!exists){
    setStatus("PIN Admin akun ini belum dibuat. Buat PIN Admin terlebih dahulu.","error");
    return false;
  }

  if(codePromise)return codePromise;
  codePromise=new Promise((resolve)=>{
    showModal("verify");
    const input=el("aocAdminSecurityCode");
    const btn=el("aocAdminSecurityVerifyBtn");
    const cancel=el("aocAdminSecurityCancelBtn");
    const finish=(ok)=>{
      resolve(ok);
      codePromise=null;
      if(ok)hideModal();
    };

    if(btn)btn.onclick=async()=>{
      const code=String(input?.value||"").replace(/\D/g,"").slice(0,8);
      if(!/^\d{8}$/.test(code)){
        setStatus("Masukkan tepat 8 digit PIN Admin.","error");
        return;
      }
      btn.disabled=true;
      setStatus("Memverifikasi PIN Admin ke server...");
      try{
        const {data,error}=await adminSecuritySupabase.rpc("verify_admin_security_pin",{p_pin:code});
        if(error)throw error;
        if(data?.success){
          startSession();
          setStatus("PIN benar. Perubahan admin diizinkan.","success");
          finish(true);
        }else{
          setStatus(data?.message||"PIN Admin salah.","error");
          btn.disabled=false;
          input?.select();
          if(data?.code==="PIN_LOCKED")btn.disabled=true;
        }
      }catch(e){
        setStatus(e?.message||"Verifikasi PIN gagal.","error");
        btn.disabled=false;
      }
    };

    if(cancel)cancel.onclick=()=>finish(false);
    input?.addEventListener("input",()=>{
      input.value=input.value.replace(/\D/g,"").slice(0,8);
    });
  });
  return codePromise;
}

async function setupCodeInteractive(){
  const input=el("aocAdminSecurityNewCode");
  const confirm=el("aocAdminSecurityConfirmCode");
  const current=el("aocAdminSecurityCurrentCode");
  const btn=el("aocAdminSecuritySetupBtn");
  showModal("setup");

  const existing=await hasPin().catch(error=>{
    setStatus(`Gagal memeriksa PIN akun: ${error?.message||"RPC belum tersedia."}`,"error");
    return null;
  });
  if(existing===null)return false;

  if(current){
    current.classList.toggle("hidden",!existing);
    current.required=Boolean(existing);
  }

  return new Promise((resolve)=>{
    const finish=(ok)=>{resolve(ok);};

    btn.onclick=async()=>{
      const a=String(input?.value||"").replace(/\D/g,"").slice(0,8);
      const b=String(confirm?.value||"").replace(/\D/g,"").slice(0,8);
      const old=String(current?.value||"").replace(/\D/g,"").slice(0,8);

      if(!/^\d{8}$/.test(a))return setStatus("PIN Admin harus tepat 8 digit.","error");
      if(a!==b)return setStatus("Konfirmasi PIN tidak sama.","error");
      if(existing && !/^\d{8}$/.test(old))return setStatus("Masukkan PIN Admin lama untuk menggantinya.","error");
      if(/^([0-9])\1{7}$/.test(a) || ["12345678","87654321","12341234","11223344"].includes(a)){
        return setStatus("PIN terlalu mudah ditebak. Gunakan kombinasi lain.","error");
      }

      btn.disabled=true;
      setStatus("Menyimpan PIN Admin ke database...");
      try{
        const {data,error}=await adminSecuritySupabase.rpc("set_admin_security_pin",{
          p_new_pin:a,
          p_current_pin:existing?old:null
        });
        if(error)throw error;
        if(!data?.success)throw new Error(data?.message||"PIN Admin gagal disimpan.");

        setStatus("PIN Admin akun ini berhasil disimpan ke database.","success");
        setTimeout(()=>{
          hideModal();
          refreshAdminPinStatus();
          finish(true);
        },350);
      }catch(e){
        setStatus(e?.message||"PIN Admin gagal disimpan.","error");
        btn.disabled=false;
      }
    };

    el("aocAdminSecuritySetupCancelBtn")?.addEventListener("click",()=>{
      hideModal();
      finish(false);
    },{once:true});

    [input,confirm,current].forEach(x=>x?.addEventListener("input",()=>{
      x.value=x.value.replace(/\D/g,"").slice(0,8);
    }));
  });
}

async function getAdminRole(){
  try{
    const user=await currentUser();
    const uid=user?.id;
    if(!uid)return "";
    const {data,error}=await adminSecuritySupabase
      .from("profiles")
      .select("role")
      .eq("id",uid)
      .maybeSingle();
    if(!error&&data?.role)return String(data.role).toLowerCase();
  }catch{}
  return "";
}
async function isAdmin(){
  try{
    const {data}=await adminSecuritySupabase.rpc("is_admin");
    if(data===true)return true;
  }catch{}
  const role=await getAdminRole();
  return ["admin","super_admin","superadmin","order_admin","catalog_admin","finance_admin","warehouse_staff"].includes(role);
}
async function ensureAdminCodeExists(){
  const exists=await hasPin().catch(()=>null);
  if(exists===true)return true;
  if(exists===null){
    setStatus("PIN Admin belum dapat diperiksa. Pastikan SQL keamanan admin sudah dipasang.","error");
    return false;
  }
  setStatus("PIN Admin akun ini belum dibuat. Buka Pengaturan → Keamanan untuk membuatnya.","error");
  return false;
}
async function ensureAdminMutationAllowed(){
  const user=await currentUser();
  if(!user)return false;
  if(!(await isAdmin())){
    setStatus("Akun ini bukan akun admin.","error");
    return false;
  }
  if(!(await ensureAdminCodeExists()))return false;
  return verifyCodeInteractive();
}
function installFetchGuard(){if(guardInstalled)return;guardInstalled=true;}

async function initAdminSecurity(){
  if(initialized)return;
  initialized=true;
  installFetchGuard();

  const user=await currentUser();
  if(!user)return;

  const admin=await isAdmin();
  if(!admin)return;

  refreshAdminPinStatus();
}

async function openAdminPinSetup(){
  if(!(await isAdmin())){
    setStatus("Hanya akun admin yang dapat membuat atau mengganti PIN Admin.","error");
    return false;
  }
  return setupCodeInteractive();
}

async function refreshAdminPinStatus(targetId="aocAdminPinStatus"){
  const node=el(targetId);
  if(!node)return;
  try{
    const admin=await isAdmin();
    if(!admin){
      node.textContent="PIN Admin hanya tersedia untuk akun admin.";
      return;
    }
    const exists=await hasPin();
    node.textContent=exists
      ?"PIN Admin akun ini sudah tersimpan di database."
      :"PIN Admin akun ini belum dibuat.";
    node.className=`muted ${exists?"success":"warning"}`;
  }catch(error){
    node.textContent=`Status PIN tidak dapat diperiksa: ${error?.message||"error"}`;
    node.className="muted warning";
  }
}

if(document.readyState==="loading"){
  document.addEventListener("DOMContentLoaded",initAdminSecurity,{once:true});
}else{
  initAdminSecurity();
}

window.aocAdminSecurity={
  ensure:ensureAdminMutationAllowed,
  setup:openAdminPinSetup,
  verify:verifyCodeInteractive,
  isSuperAdmin:isAdmin,
  refreshStatus:refreshAdminPinStatus,
  clearSession
};

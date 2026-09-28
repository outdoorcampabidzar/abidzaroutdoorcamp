import { supabase } from "./app.js";

const form=document.getElementById("homePinForm");
const pin=document.getElementById("homePin");
const confirm=document.getElementById("homePinConfirm");
const status=document.getElementById("pinStatus");
const submit=document.getElementById("saveHomePin");
const params=new URLSearchParams(location.search);
const next=params.get("next")||"index.html";

function safeNext(){try{const u=new URL(next,location.href);if(u.origin!==location.origin)return"index.html";return (u.pathname.split("/").pop()||"index.html")+u.search+u.hash;}catch{return"index.html";}}
function setStatus(msg,type="") { status.textContent=msg; status.className=`pin-status ${type}`; }
function clean(el){el.value=el.value.replace(/\D/g,"").slice(0,6);}
[pin,confirm].forEach(el=>el?.addEventListener("input",()=>clean(el)));

async function init(){
  const {data,error}=await supabase.auth.getUser();
  if(error||!data?.user){location.replace(`login.html?next=${encodeURIComponent("pin.html?next="+safeNext())}`);return;}
  const {data:has,error:hasError}=await supabase.rpc("has_home_security_pin");
  if(!hasError && has===true){
    setStatus("PIN sudah dibuat. Anda akan diarahkan ke Beranda.","pin-success");
    setTimeout(()=>location.replace(safeNext()),250);
  }
}

form?.addEventListener("submit",async e=>{
  e.preventDefault();
  clean(pin);clean(confirm);
  const a=pin.value,b=confirm.value;
  if(!/^\d{6}$/.test(a)){setStatus("PIN harus tepat 6 digit.","pin-error");pin.focus();return;}
  if(a!==b){setStatus("Konfirmasi PIN tidak sama. Tidak disimpan.","pin-error");confirm.focus();return;}
  if(/^([0-9])\1{5}$/.test(a)||["123456","654321","123123","321321","121212","112233"].includes(a)){setStatus("PIN terlalu mudah ditebak. Gunakan kombinasi lain.","pin-error");pin.focus();return;}
  submit.disabled=true;pin.disabled=true;confirm.disabled=true;setStatus("Menyimpan PIN secara aman...");
  try{
    const {data,error}=await supabase.rpc("set_home_security_pin",{p_pin:a});
    if(error)throw error;
    if(!data?.success)throw new Error(data?.message||"PIN gagal disimpan.");
    const verify=await supabase.rpc("verify_home_security_pin",{p_pin:a});
    if(verify.error || !verify.data?.success) throw (verify.error || new Error(verify.data?.message || "PIN gagal diverifikasi."));
    setStatus("PIN berhasil dibuat. Lanjut mengisi identitas...","pin-success");
    setTimeout(()=>location.replace(`identity.html?next=${encodeURIComponent(safeNext())}`),350);
  }catch(err){
    setStatus(err?.message||"PIN gagal disimpan.","pin-error");
    submit.disabled=false;pin.disabled=false;confirm.disabled=false;
  }
});

init();

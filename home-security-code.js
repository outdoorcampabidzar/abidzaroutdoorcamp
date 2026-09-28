import { supabase } from "./app.js";

export function mountHomeSecurityCode(){
 const gate=document.getElementById("homeSecurityGate"),form=document.getElementById("homeSecurityForm"),input=document.getElementById("homeSecurityInput"),status=document.getElementById("homeSecurityStatus"),button=document.getElementById("homeSecuritySubmit");
 if(!gate||!form||!input||!status||!button)return;
 const unlock=()=>{gate.classList.add("hidden");gate.setAttribute("aria-hidden","true");document.documentElement.classList.remove("home-security-locked");document.body.classList.remove("home-security-locked");};
 const lock=()=>{gate.classList.remove("hidden");gate.setAttribute("aria-hidden","false");document.documentElement.classList.add("home-security-locked");document.body.classList.add("home-security-locked");input.disabled=false;button.disabled=false;input.value="";status.textContent="Masukkan PIN keamanan beranda 6 digit.";requestAnimationFrame(()=>input.focus());};
 async function requireAuthAndPin(){
   const {data,error}=await supabase.auth.getUser();
   if(error||!data?.user){location.replace(`login.html?next=${encodeURIComponent("index.html")}`);return false;}
   const {data:has,error:hasError}=await supabase.rpc("has_home_security_pin");
   if(hasError){status.textContent="Sistem PIN belum siap. Jalankan DATABASE-V36-FINAL-PATCH.sql di Supabase.";return false;}
   if(has!==true){location.replace("pin.html?next=index.html");return false;}
   // KONSEP V34: setiap kali beranda dibuka, PIN wajib dimasukkan.
   // Tidak ada lagi sesi unlock 10 menit yang dapat melewati PIN.
   return true;
 }
 lock();
 requireAuthAndPin();
 input.addEventListener("input",()=>{input.value=input.value.replace(/\D/g,"").slice(0,6);status.textContent=input.value.length===6?"PIN siap diverifikasi.":"Masukkan tepat 6 digit PIN keamanan.";});
 form.addEventListener("submit",async e=>{e.preventDefault();const code=input.value.trim();if(!/^\d{6}$/.test(code)){status.textContent="PIN harus tepat 6 digit.";input.focus();return;}button.disabled=true;input.disabled=true;status.textContent="Memverifikasi PIN ke server...";try{const {data,error}=await supabase.rpc("verify_home_security_pin",{p_pin:code});if(error)throw error;if(!data?.success){status.textContent=data?.message||"PIN keamanan salah. Beranda tetap terkunci.";input.disabled=false;button.disabled=false;input.select();if(data?.code==="PIN_LOCKED")button.disabled=true;return;}unlock();}catch(err){status.textContent=err?.message||"Verifikasi PIN gagal. Beranda tetap terkunci.";input.disabled=false;button.disabled=false;input.select();}});
 window.addEventListener("pageshow",e=>{if(e.persisted)lock();});
}

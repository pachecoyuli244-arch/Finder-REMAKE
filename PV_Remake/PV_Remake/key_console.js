"use strict";
const $ = id => document.getElementById(id);
const loginPanel = $("loginPanel"), dashboard = $("dashboard"), notice = $("notice");
let allKeys = [];
const fmtDate = value => value ? new Date(value*1000).toLocaleDateString("es-MX",{day:"2-digit",month:"short",year:"numeric"}) : "Sin vencimiento";

function message(text, error=false){
  notice.textContent = text || "";
  notice.classList.toggle("error",!!error);
}
function view(logged){
  loginPanel.hidden = logged;
  dashboard.hidden = !logged;
  if(!logged){ $("password").value = ""; $("created").hidden=true; $("createdKey").textContent=""; }
}
async function api(path, data){
  const options = {credentials:"same-origin",cache:"no-store",headers:{"Accept":"application/json"}};
  if(data !== undefined){
    options.method="POST";
    options.headers["Content-Type"]="application/json";
    options.headers["X-PV-Request"]="1";
    options.body=JSON.stringify(data);
  }
  let response;
  try {response = await fetch(path,options);}
  catch(e){throw Error("No hay conexión con el servidor");}
  let body = {};
  try{body=await response.json();}catch(e){}
  if(!response.ok){
    if(response.status===401 && path!=="/api/login")view(false);
    throw Error(body.error || "Error " + response.status);
  }
  return body;
}
function add(tag, className, text){
  const e=document.createElement(tag);
  if(className)e.className=className;
  if(text!==undefined)e.textContent=text;
  return e;
}
function renderList(){
  const query=$("search").value.trim().toLowerCase();
  const now=Math.floor(Date.now()/1000);
  const list=$("keyList");
  list.replaceChildren();
  const active=allKeys.filter(k=>!k.revoked_at && (!k.expires_at || k.expires_at>now));
  $("total").textContent=String(allKeys.length);
  $("active").textContent=String(active.length);
  $("revoked").textContent=String(allKeys.filter(k=>k.revoked_at).length);
  const shown=allKeys.filter(k=>String(k.label||"").toLowerCase().includes(query));
  if(!shown.length){list.append(add("p","dim",query?"No hay coincidencias":"Todavía no hay llaves"));return;}
  for(const key of shown){
    const valid=!key.revoked_at && (!key.expires_at || key.expires_at>now);
    const item=add("div","key-item");
    const info=add("div","key-info");
    const head=add("div","key-name",key.label||"Acceso PVFinder");
    const status=add("span","pill"+(valid?"":" off"),valid?"ACTIVA":(key.revoked_at?"REVOCADA":"VENCIDA"));
    head.append(status);
    info.append(head,add("div","key-meta",(key.roblox_user_id?"Cuenta vinculada (llave anterior)":"PVFinder Web y Delta") + " · Hasta: "+fmtDate(key.expires_at)+" · Usos: "+(key.uses||0)));
    item.append(info);
    if(valid){
      const actions=add("div","key-actions");
      const revoke=add("button","danger","Revocar");
      revoke.type="button";
      revoke.addEventListener("click",()=>revokeKey(key));
      actions.append(revoke);
      item.append(actions);
    }
    list.append(item);
  }
}
async function loadKeys(){
  try {
    const result=await api("/api/keys");
    allKeys=[...(result.keys||[]),...(result.web_keys||[])].sort((a,b)=>(b.created_at||0)-(a.created_at||0));
    renderList();
  } catch(e){message(e.message,true);}
}
async function revokeKey(key){
  if(!confirm("¿Revocar el acceso de "+key.label+"? Esta acción no se puede deshacer."))return;
  try{
    await api("/api/keys",{action:"revoke",id:key.id});
    message("Llave revocada; sus sesiones anteriores fueron cerradas");
    await loadKeys();
  }catch(e){message(e.message,true);}
}
$("loginForm").addEventListener("submit",async event=>{
  event.preventDefault();
  const button=event.submitter||$("loginForm").querySelector("button");
  button.disabled=true;
  message("");
  try{
    await api("/api/login",{password:$("password").value});
    view(true);
    message("Sesión de administrador iniciada");
    await loadKeys();
  }catch(e){message(e.message,true);}
  finally{button.disabled=false;$("password").value="";}
});
$("createForm").addEventListener("submit",async event=>{
  event.preventDefault();
  const button=event.submitter||$("createForm").querySelector("button");
  button.disabled=true;
  message("");
  $("created").hidden=true;
  $("createdKey").textContent="";
  try{
    const result=await api("/api/keys",{action:"create",kind:"universal",label:$("label").value.trim(),days:Number($("days").value)});
    $("createdKey").textContent=result.key;
    $("created").hidden=false;
    message("Llave PVFinder válida para web y Delta creada");
    $("createForm").reset();
    await loadKeys();
  }catch(e){message(e.message,true);}
  finally{button.disabled=false;}
});
$("copy").addEventListener("click",async()=>{
  const value=$("createdKey").textContent;
  if(!value)return;
  try{await navigator.clipboard.writeText(value);message("Llave copiada");}
  catch(e){message("Mantén presionado el código para copiarlo",true);}
});
$("refresh").addEventListener("click",loadKeys);
$("search").addEventListener("input",renderList);
$("logout").addEventListener("click",async()=>{
  try{await api("/api/logout",{});}catch(e){}
  view(false);message("Sesión cerrada");allKeys=[];
});
(async()=>{
  try{
    const result=await api("/api/me");
    view(result.authenticated);
    if(result.authenticated)await loadKeys();
  }catch(e){view(false);}
})();

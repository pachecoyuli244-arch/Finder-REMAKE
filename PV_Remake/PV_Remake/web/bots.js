"use strict";
const $ = id => document.getElementById(id);
let snapshot = null;
let selected = "all";
let busy = false;
const nf = new Intl.NumberFormat("es-MX");
const timeFmt = new Intl.DateTimeFormat("es-MX", {hour:"2-digit",minute:"2-digit",hour12:false});
const dateFmt = new Intl.DateTimeFormat("es-MX", {day:"2-digit",month:"short",hour:"2-digit",minute:"2-digit"});
const states = {
  scanning: "Escaneando",
  moving: "Cambiando servidor",
  recent: "Informe reciente",
  paused: "Pausado",
  offline: "Sin señal"
};
const reasons = {
  reading_sources:"Leyendo fuentes",sending_snapshot:"Enviando informe",
  looking_for_server:"Buscando servidor",teleport_requested:"Salto solicitado",
  roblox_flooded:"Roblox saturado",roblox_http_limit:"Límite de Roblox",
  roblox_api_error:"Error API Roblox",teleport_failed:"Fallo de salto",
  no_candidates:"Sin destinos",session_error:"Error de sesión",
  coordinator_error:"Error de coordinación",sources_unavailable:"Fuentes no disponibles",
  snapshot_rejected:"Informe rechazado",snapshot_error:"Error de informe",
  too_many_detections:"Demasiadas detecciones",no_auto_resume:"Sin reanudación automática"
};
const fnum = value => nf.format(Number(value)||0);
function relative(value){
  if(!value) return "Sin reportes";
  const difference = Math.max(0,Math.floor(Date.now()/1000)-Number(value));
  if(difference<60) return "Hace " + difference + " s";
  if(difference<3600) return "Hace " + Math.floor(difference/60) + " min";
  if(difference<86400) return "Hace " + Math.floor(difference/3600) + " h";
  return dateFmt.format(new Date(Number(value)*1000));
}
async function api(path, payload){
  let response;
  try {
    response = await fetch(path,{
      method: payload===undefined ? "GET" : "POST",
      credentials:"same-origin",cache:"no-store",
      headers:payload===undefined ? {"Accept":"application/json"} : {
        "Accept":"application/json","Content-Type":"application/json"
      },
      body:payload===undefined?undefined:JSON.stringify(payload)
    });
  }catch(_){throw new Error("No hay conexión con PVFINDER");}
  const json = await response.json().catch(()=>({error:"Respuesta inválida"}));
  if(!response.ok) {
    const e = new Error(json.error || ("Error " + response.status));
    e.status = response.status;
    throw e;
  }
  return json;
}
function showOwner(isOwner){
  $("login").hidden=isOwner;
  $("dashboard").hidden=!isOwner;
  $("logout").hidden=!isOwner;
  if(!isOwner){
    $("password").value="";
    $("loginError").textContent="";
    snapshot=null;
  }
}
function statusNotice(ok,label){
  $("connectionDot").className="status-dot "+(ok?"online":"problem");
  $("syncState").textContent=label;
}
function put(id,value){$(id).textContent=fnum(value);}
function renderCounts(data){
  const c=data.counts;
  const values={
    activeCount:c.active_estimate,pausedCount:c.paused,offlineCount:c.offline,
    registered:c.registered,available:c.not_revoked,scanning:c.scanning,moving:c.moving,
    serversCycle:c.servers_current_cycle,serversHour:c.servers_with_eggs_hour,
    eggsHour:c.eggs_hour,eggsDay:c.eggs_day,eggsSaved:c.eggs_saved,
    sessions:c.auto_sessions_valid,hopReserved:c.hop_reserved,
    hopAssigned:c.hop_active_recorded,hopDone:c.hop_done,revoked:c.revoked
  };
  for(const [id,value] of Object.entries(values)) put(id,value);
  $("botTotal").textContent=fnum(data.total_count);
  $("windowLabel").textContent="Ciclo: "+timeFmt.format(new Date(data.cycle_start*1000));
}
function renderActivity(data){
  const container=$("bars");
  const fragment=document.createDocumentFragment();
  const peak=Math.max(1,...data.activity.map(x=>x.eggs_updated));
  for(const b of data.activity){
    const slot=document.createElement("div");
    slot.className="bar-slot";
    const count=document.createElement("span");
    count.className="bar-count";
    count.textContent=fnum(b.eggs_updated);
    const fill=document.createElement("div");
    fill.className="bar-fill";
    fill.style.height=Math.max(3,Math.round(b.eggs_updated/peak*123))+"px";
    const label=document.createElement("span");
    label.className="bar-time";
    label.textContent=timeFmt.format(new Date(b.start*1000));
    fill.title=fnum(b.eggs_updated)+" huevos actualizados desde "+label.textContent;
    slot.append(count,fill,label);
    fragment.append(slot);
  }
  container.replaceChildren(fragment);
}
function fieldCell(row,value,cls){
  const td=document.createElement("td");
  if(cls) td.className=cls;
  td.textContent=String(value);
  row.append(td);
  return td;
}
function displayedBots(){
  if(!snapshot)return [];
  const query=$("search").value.trim().toLowerCase();
  return snapshot.bots.filter(bot=>{
    if(query&&!String(bot.label+" "+bot.short_id).toLowerCase().includes(query))return false;
    if(selected==="active") return ["scanning","moving","recent"].includes(bot.state);
    return selected==="all"||bot.state===selected;
  });
}
function renderTable(){
  if(!snapshot)return;
  const shown=displayedBots();
  const fragment=document.createDocumentFragment();
  if(!shown.length){
    const row=document.createElement("tr");
    fieldCell(row,"No hay bots con ese filtro","empty").colSpan=7;
    fragment.append(row);
  }
  for(const bot of shown){
    const row=document.createElement("tr");
    const first=document.createElement("td");
    const name=document.createElement("strong");
    name.textContent=bot.label||"Recolector";
    const ident=document.createElement("span");
    ident.className="id";
    ident.textContent="#"+bot.short_id;
    first.append(name,ident);
    row.append(first);
    const stateTd=document.createElement("td");
    const pill=document.createElement("span");
    pill.className="state-pill "+bot.state;
    pill.textContent=states[bot.state]||bot.state;
    pill.title=reasons[bot.reason]||bot.reason||"";
    stateTd.append(pill);
    if(bot.reason&&bot.state==="paused"){
      const note=document.createElement("div");
      note.className="id";
      note.textContent=reasons[bot.reason]||bot.reason;
      stateTd.append(note);
    }
    row.append(stateTd);
    fieldCell(row,relative(bot.last_signal_at));
    fieldCell(row,relative(bot.last_scan_at));
    fieldCell(row,fnum(bot.eggs_hour));
    fieldCell(row,fnum(bot.servers_with_eggs_hour));
    const last=document.createElement("td");
    if(bot.last_reported_server){
      const job=document.createElement("code");
      job.className="job";
      job.textContent=bot.last_reported_server;
      job.title=bot.last_reported_server;
      last.append(job);
      const at=document.createElement("span");
      at.className="id";
      at.textContent=relative(bot.last_reported_server_at);
      last.append(at);
    }else last.textContent="Sin registro reciente";
    row.append(last);
    fragment.append(row);
  }
  $("botRows").replaceChildren(fragment);
  const extra=snapshot.total_count>snapshot.listed_count?
    " · Se muestran los "+fnum(snapshot.listed_count)+" más recientes de "+fnum(snapshot.total_count):"";
  $("tableInfo").textContent=fnum(shown.length)+" bots en la lista"+extra+
    " · Datos registrados en PVFINDER (no acceso directo al dispositivo)";
}
async function refresh(){
  if(busy)return;
  busy=true;
  $("refresh").disabled=true;
  $("error").hidden=true;
  try{
    const data=await api("/api/admin/bots");
    snapshot=data;
    renderCounts(data);
    renderActivity(data);
    renderTable();
    statusNotice(true,"Datos actualizados");
    $("syncTime").textContent=timeFmt.format(new Date(data.server_time*1000));
  }catch(e){
    if(e.status===401){
      showOwner(false);
      $("loginError").textContent="Sesión expirada. Accede como Owner.";
    }else{
      $("error").hidden=false;
      $("error").textContent=e.message;
      statusNotice(false,"Sin conexión");
    }
  }finally{
    busy=false;
    $("refresh").disabled=false;
  }
}
async function initialize(){
  try{
    const session=await api("/api/me");
    if(session.authenticated&&session.role==="admin"){
      showOwner(true);
      await refresh();
    }else showOwner(false);
  }catch(_){showOwner(false);}
}
$("loginForm").addEventListener("submit",async event=>{
  event.preventDefault();
  const button=$("loginButton");
  button.disabled=true;
  $("loginError").textContent="";
  try{
    const password=$("password").value;
    const result=await api("/api/admin/login",{password});
    if(result.role!=="admin")throw new Error("Solo el propietario puede entrar");
    showOwner(true);
    await refresh();
  }catch(e){
    $("loginError").textContent=e.message;
  }finally{
    button.disabled=false;
    $("password").value="";
  }
});
$("logout").addEventListener("click",async()=>{
  try{await api("/api/logout",{});}catch(_){}
  showOwner(false);
});
$("refresh").addEventListener("click",refresh);
$("search").addEventListener("input",renderTable);
$("filters").addEventListener("click",event=>{
  const button=event.target.closest("button[data-filter]");
  if(!button)return;
  selected=button.dataset.filter;
  for(const b of $("filters").querySelectorAll("button[data-filter]"))
    b.setAttribute("aria-pressed",String(b.dataset.filter===selected));
  renderTable();
});
$("copySummary").addEventListener("click",async()=>{
  if(!snapshot)return;
  const c=snapshot.counts;
  const summary=[
    "PVFINDER OPS · "+dateFmt.format(new Date(snapshot.server_time*1000)),
    "Actividad reciente: "+c.active_estimate,
    "Pausados: "+c.paused+" · Sin señal: "+c.offline,
    "Bots sin revocar: "+c.not_revoked,
    "Servidores escaneados en ciclo: "+c.servers_current_cycle,
    "Servidores con datos en 1 h: "+c.servers_with_eggs_hour,
    "Huevos actualizados en 1 h: "+c.eggs_hour,
    "Huevos actualizados en 24 h: "+c.eggs_day,
    "Activos significa actividad registrada, no confirmación de dispositivo encendido."
  ].join("\n");
  try{
    await navigator.clipboard.writeText(summary);
    $("copySummary").textContent="✓ Resumen copiado";
  }catch(_){
    $("copySummary").textContent="No se pudo copiar";
  }
});
setInterval(()=>{
  if(!$("dashboard").hidden && !document.hidden)refresh();
},20000);
initialize();

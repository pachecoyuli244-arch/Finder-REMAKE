(() => {
'use strict';
const demo=location.pathname.endsWith('/demo.html') || window.PVF_DEMO === true;
const $=id=>document.getElementById(id);
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const categories=['Cosmic','Secret','Eternal','Divine']; // Rarezas que se muestran en el radar.
let role=demo?'admin':null,view='feed',adminView='links',items=[],adminData=null,lastChange='',lastSignature='',tick=null,reloadTick=null;
const AUTO_RELOAD_MS=5*60*1000;
let clockTick=null;
let reloadAt=0;
function updateSessionClock(){
 const dialog=$('pvAccountSheet');
 const text=$('pvSessionTime');
 if(!dialog?.open||!text)return;
 if(sessionPersistent){text.textContent='Sesión sin vencimiento fijo';return;}
 if(!sessionExpiry){text.textContent=demo?'Sesión de demostración':sessionExpiryUnavailable?'Vencimiento no disponible':'Consultando vencimiento…';return;}
 const left=Math.max(0,Math.ceil((sessionExpiry*1000-Date.now()-sessionClockOffset)/60000));
 const duration=[Math.floor(left/1440)?Math.floor(left/1440)+' d':'',Math.floor(left%1440/60)?Math.floor(left%1440/60)+' h':'',left%60+' min'].filter(Boolean).join(' ');
 text.textContent=left?'Te quedan '+duration+' · vence el '+new Date(sessionExpiry*1000).toLocaleString('es-CL'):'La sesión venció.';
}
function updateRadarClock() {
 updateEventBanner();
 updateSessionClock();
 const clock=$('radarReload');
 if (clock) {
  const remaining=Math.max(0,Math.ceil((reloadAt-Date.now())/1000));
  clock.textContent=remaining?Math.floor(remaining/60)+':'+String(remaining%60).padStart(2,'0'):'Reiniciando';
  clock.classList.toggle('pv-ending',remaining<45);
  const progress=$('pvCycleProgress');
  if(progress){
   progress.classList.toggle('pv-ending',remaining<45);
   progress.style.setProperty('--cycle-progress',Math.max(0,100-remaining/3)+'%');
  }
  const scanning=$('pvScanningTime');
  if(scanning)scanning.textContent=clock.textContent;
 }
 for (const timestamp of document.querySelectorAll('[data-received-at]')) {
  timestamp.textContent=elapsedReportTime(Number(timestamp.dataset.receivedAt));
 }
}
function elapsedReportTime(receivedAt) {
 if (!Number.isFinite(receivedAt)||receivedAt<=0) return 'Hora sin dato';
 const seconds=Math.max(0,Math.floor(Date.now()/1000-receivedAt));
 if (seconds<60) return 'hace '+seconds+' s';
 const minutes=Math.floor(seconds/60);
 if (minutes<60) return 'hace '+minutes+' min';
 return 'hace '+Math.floor(minutes/60)+' h';
}
let totalCount=0,nextOffset=0,hasMore=false,loadingMore=false;
const PAGE_LIMIT=250;
let freshSeconds=90;
const demoStamp=Math.floor(Date.now()/1000);
const demoItems=[
 {egg_id:'example-hp-1',server_id:'SERVIDOR-DE-EJEMPLO',egg_name:'Hexed Pumpkin',rarity:'Cosmic',biome:'Halloween',income_per_second:165510000,income_type:'ESTIMADO',weight_kg:null,mutation:null,updated_at:demoStamp-30},
 {egg_id:'example-hs-1',server_id:'SERVIDOR-DE-EJEMPLO',egg_name:'Haunted Scorpio',rarity:'Cosmic',biome:'Halloween',income_per_second:132560000,income_type:'ESTIMADO',weight_kg:null,mutation:null,updated_at:demoStamp-55},
 {egg_id:'example-hp-2',server_id:'SERVIDOR-DE-EJEMPLO',egg_name:'Hexed Pumpkin',rarity:'Cosmic',biome:'Halloween',income_per_second:126760000,income_type:'ESTIMADO',weight_kg:null,mutation:null,updated_at:demoStamp-89}
];
let radarMode='live';
let radarSort='income';
let radarDirection=-1;
const alertedSpecies=new Set();
let lastLiveRender='';
let sessionExpiry=null;
let sessionPersistent=false;
let sessionExpiryUnavailable=false;
let sessionClockOffset=0;
let recentThefts=[];
let scannedServers=null;
let rotationStartedAt=Math.floor(Date.now()/AUTO_RELOAD_MS)*AUTO_RELOAD_MS/1000;
const rarityOrder=new Map(['common','uncommon','rare','epic','legendary','mythic','cosmic','secret','eternal','divine'].map((name,index)=>[name,index]));
let radarModeVersion=0;
let liveRefreshVersion=null;
let livePollAfter=0;
let liveRevision=null,liveSyncCycle=null,liveSyncVersion=null;
const liveReports=new Map();
function feedPath(offset) {
 const liveOnly=view!=='feed'||radarMode==='live';
 const options=new URLSearchParams({detected_only:liveOnly?'1':'0',limit:liveOnly?500:PAGE_LIMIT,offset,alien_min_secret:'1'});
 if(view==='feed'&&radarMode==='live'){
  options.set('radar_cycle','1');
  options.set('sync','1');
  options.set('species',[...radarReportNames].join(','));
  options.set('include_alien','1');
 }
 if(view==='feed'&&radarMode==='history')options.set('sort','recent');
 return '/api/feed?'+options;
}
const radarArt=new Map([["abyssjaw", "abyssjaw"], ["aetheron", "aetheron"], ["ankylosaurus", "ankylosaurus"], ["archangel", "archangel"], ["astral jackalope", "astral-jackalope"], ["aurora stag", "alien-aurora-stag"], ["axolotl", "axolotl"], ["bear", "bear"], ["beluga whale", "beluga-whale"], ["bird", "bird"], ["bladehide", "bladehide"], ["bloodbloom", "bloodbloom"], ["bloomfin", "alien-bloomfin"], ["bloomspire", "bloomspire"], ["bronto", "bronto"], ["brr brr patapim", "brr-brr-patapim"], ["bubblelord", "bubblelord"], ["burrowing owl", "burrowing-owl"], ["camel", "camel"], ["candlefang", "candlefang"], ["catfish", "catfish"], ["celestial sunlion", "celestial-sunlion"], ["centapede", "centapede"], ["centaur", "centaur"], ["cerberus", "cerberus"], ["chicken", "chicken"], ["chillin chilli", "chillin-chilli"], ["chimpanzee", "chimpanzee"], ["cosmic dragon", "cosmic-dragon"], ["cosmic gecko", "cosmic-gecko"], ["cosmic gorilla", "cosmic-gorilla"], ["cosmic skeleton boss", "cosmic-skeleton-boss"], ["crane", "crane"], ["crocodile", "crocodile"], ["crowshade", "crowshade"], ["crustacia", "crustacia"], ["crystal egg", "crystal"], ["demon hound", "demon-hound"], ["dodo", "dodo"], ["dog", "dog"], ["duckling", "duckling"], ["el maja", "el-maja"], ["enchanted bluejay", "enchanted-bluejay"], ["equinox", "equinox"], ["eternal lunar dragon", "eternal-lunar-dragon"], ["fennec", "fennec"], ["flame sprite", "flame-sprite"], ["flaming bull", "flaming-bull"], ["flarefish", "alien-flarefish"], ["fox", "fox"], ["frog", "frog"], ["gargoyle", "gargoyle"], ["ghost reaper", "ghost-reaper"], ["glacigon", "alien-glacigon"], ["gorilla", "gorilla"], ["gorilla king", "gorilla-king"], ["gorillastein", "gorillastein"], ["graveyard brute", "graveyard-brute"], ["halloween dimension", "halloween-dimension"], ["haunted scorpio", "haunted-scorpio"], ["headless horseman", "headless-horseman"], ["hexed pumpkin", "hexed-pumpkin"], ["holy peacock", "holy-peacock"], ["hooded gerbil", "hooded-gerbil"], ["ice dragon", "ice-dragon"], ["imp", "imp"], ["jellynova", "jellynova"], ["jerboa", "jerboa"], ["jesterpop", "jesterpop"], ["king mammoth", "king-mammoth"], ["king snake", "king-snake"], ["kitsune", "kitsune"], ["koi", "koi"], ["kraken", "kraken"], ["la vacca saturno saturnita", "la-vacca-saturno-saturnita"], ["lava dragon", "lava-dragon"], ["lava frog", "lava-frog"], ["lava gecko", "lava-gecko"], ["lava iguana", "lava-iguana"], ["leviathan", "leviathan"], ["light dove", "light-dove"], ["mammoth", "mammoth"], ["mantaris", "mantaris"], ["mimic chest", "mimic-chest"], ["mosasaurus", "mosasaurus"], ["mutant shark", "mutant-shark"], ["nightflame", "nightflame"], ["obsidian rex", "alien-obsidian-rex"], ["oni tiger", "oni-tiger"], ["orangutini ananassini", "orangutini-ananassini"], ["orca", "orca"], ["parrotfish", "parrotfish"], ["patchwork imp", "patchwork-imp"], ["pegasus", "pegasus"], ["penguin", "penguin"], ["petal beetle", "petal-beetle"], ["phoenix", "phoenix"], ["polar bear", "polar-bear"], ["prism gecko", "prism-gecko"], ["prismare", "alien-prismare"], ["pterodactyl", "pterodactyl"], ["pure jellyfish", "pure-jellyfish"], ["raccoon", "raccoon"], ["razorfang", "razorfang"], ["red panda", "red-panda"], ["redmaw", "alien-redmaw"], ["rhinotaur", "rhinotaur"], ["riftbeasts", "riftbeasts"], ["riftborn", "riftborn"], ["ring guard", "ring-guard"], ["ringlord", "ringlord"], ["royal skywhale", "royal-skywhale"], ["royal sphinx", "royal-sphinx"], ["sabertooth tiger", "sabertooth-tiger"], ["sacred moth", "sacred-moth"], ["salamander", "salamander"], ["sand spider", "sand-spider"], ["scorpion", "scorpion"], ["shark", "shark"], ["shattered rift", "shattered-rift"], ["shelltide voyager", "shelltide-voyager"], ["skeleton horse", "skeleton-horse"], ["snake", "snake"], ["snowy owl", "snowy-owl"], ["spider", "spider"], ["spideron", "spideron"], ["spirit knight", "spirit-knight"], ["spirit panda", "spirit-panda"], ["spirit world guardian", "spirit-world-guardian"], ["stag", "stag"], ["starry fox", "starry-fox"], ["swan", "swan"], ["swordfish", "swordfish"], ["t rex", "t-rex"], ["tideler", "alien-tideler"], ["tiger", "tiger"], ["toadstool", "toadstool"], ["tob tobi tob tob", "tob-tobi-tob-tob"], ["toro", "toro"], ["toucan", "toucan"], ["tralaledon", "tralaledon"], ["triceratops", "triceratops"], ["trulimero trulicina", "trulimero-trulicina"], ["turtle", "turtle"], ["unicorn", "unicorn"], ["vexlet", "vexlet"], ["viridian prowler", "alien-viridian-prowler"], ["voidseer pumpkin", "voidseer-pumpkin"], ["walrus", "walrus"], ["werewolf", "werewolf"], ["whale shark", "whale-shark"], ["whiskers", "whiskers"], ["winged lamb", "winged-lamb"], ["world burner", "world-burner"], ["yeti", "yeti"]]);
const radarPets=new Map([["abyssjaw", "alien-abyssjaw"], ["aetheron", "aetheron"], ["ankylosaurus", "ankylosaurus"], ["archangel", "archangel"], ["astral jackalope", "astral-jackalope"], ["aurora stag", "aurora-stag"], ["axolotl", "axolotl"], ["bear", "bear"], ["beluga whale", "beluga-whale"], ["bird", "bird"], ["bladehide", "bladehide"], ["bloodbloom", "bloodbloom"], ["bloomfin", "alien-bloomfin"], ["bloomspire", "bloomspire"], ["bronto", "bronto"], ["brr brr patapim", "brr-brr-patapim"], ["bubblelord", "bubblelord"], ["burrowing owl", "burrowing-owl"], ["camel", "camel"], ["candlefang", "candlefang"], ["catfish", "catfish"], ["celestial sunlion", "celestial-sunlion"], ["centapede", "centapede"], ["centaur", "centaur"], ["cerberus", "cerberus"], ["chicken", "chicken"], ["chillin chilli", "chillin-chilli"], ["chimpanzee", "chimpanzee"], ["cosmic dragon", "cosmic-dragon"], ["cosmic gecko", "cosmic-gecko"], ["cosmic gorilla", "cosmic-gorilla"], ["cosmic skeleton boss", "cosmic-skeleton-boss"], ["crane", "crane"], ["crocodile", "crocodile"], ["crowshade", "crowshade"], ["crustacia", "crustacia"], ["demon hound", "demon-hound"], ["dodo", "dodo"], ["dog", "dog"], ["duckling", "duckling"], ["el maja", "el-maja"], ["enchanted bluejay", "enchanted-bluejay"], ["equinox", "equinox"], ["eternal lunar dragon", "eternal-lunar-dragon"], ["fennec", "fennec"], ["flame sprite", "flame-sprite"], ["flaming bull", "flaming-bull"], ["flarefish", "alien-flarefish"], ["fox", "fox"], ["frog", "frog"], ["gargoyle", "gargoyle"], ["ghost reaper", "ghost-reaper"], ["glacigon", "alien-glacigon"], ["gorilla", "gorilla"], ["gorilla king", "gorilla-king"], ["gorillastein", "gorillastein"], ["graveyard brute", "graveyard-brute"], ["haunted scorpio", "haunted-scorpio"], ["headless horseman", "headless-horseman"], ["hexed pumpkin", "hexed-pumpkin"], ["holy peacock", "holy-peacock"], ["hooded gerbil", "hooded-gerbil"], ["ice dragon", "ice-dragon"], ["imp", "imp"], ["jellynova", "jellynova"], ["jerboa", "jerboa"], ["jesterpop", "jesterpop"], ["king mammoth", "king-mammoth"], ["king snake", "king-snake"], ["kitsune", "kitsune"], ["koi", "koi"], ["kraken", "kraken"], ["la vacca saturno saturnita", "la-vacca-saturno-saturnita"], ["lava dragon", "lava-dragon"], ["lava frog", "lava-frog"], ["lava gecko", "lava-gecko"], ["lava iguana", "lava-iguana"], ["leviathan", "leviathan"], ["light dove", "light-dove"], ["mammoth", "mammoth"], ["mantaris", "mantaris"], ["mimic chest", "mimic-chest"], ["mosasaurus", "mosasaurus"], ["mutant shark", "mutant-shark"], ["nebuloth kraken", "nebuloth-kraken"], ["nightflame", "nightflame"], ["obsidian rex", "alien-obsidian-rex"], ["oni tiger", "oni-tiger"], ["orangutini ananassini", "orangutini-ananassini"], ["orca", "orca"], ["parrotfish", "parrotfish"], ["patchwork imp", "patchwork-imp"], ["pegasus", "pegasus"], ["penguin", "penguin"], ["petal beetle", "petal-beetle"], ["phoenix", "phoenix"], ["polar bear", "polar-bear"], ["prism gecko", "prism-gecko"], ["prismare", "alien-prismare"], ["pterodactyl", "pterodactyl"], ["pure jellyfish", "pure-jellyfish"], ["raccoon", "raccoon"], ["razorfang", "razorfang"], ["red panda", "red-panda"], ["redmaw", "redmaw"], ["rhinotaur", "rhinotaur"], ["ring guard", "ring-guard"], ["ringlord", "ringlord"], ["royal skywhale", "royal-skywhale"], ["royal sphinx", "royal-sphinx"], ["sabertooth tiger", "sabertooth-tiger"], ["sacred moth", "sacred-moth"], ["salamander", "salamander"], ["sand spider", "sand-spider"], ["scorpion", "scorpion"], ["shark", "shark"], ["shelltide voyager", "shelltide-voyager"], ["skeleton horse", "skeleton-horse"], ["snake", "snake"], ["snowy owl", "snowy-owl"], ["spider", "spider"], ["spideron", "spideron"], ["spirit knight", "spirit-knight"], ["spirit panda", "spirit-panda"], ["spirit world guardian", "spirit-world-guardian"], ["sproutling", "sproutling"], ["stag", "stag"], ["starry fox", "starry-fox"], ["swan", "swan"], ["swordfish", "swordfish"], ["t-rex", "t-rex"], ["tideler", "tideler"], ["tiger", "tiger"], ["toadstool", "toadstool"], ["tob tobi tob tob", "tob-tobi-tob-tob"], ["toro", "toro"], ["toucan", "toucan"], ["tralaledon", "tralaledon"], ["triceratops", "triceratops"], ["trulimero trulicina", "trulimero-trulicina"], ["turtle", "turtle"], ["unicorn", "unicorn"], ["vexlet", "vexlet"], ["viridian prowler", "alien-viridian-prowler"], ["voidseer pumpkin", "voidseer-pumpkin"], ["walrus", "walrus"], ["werewolf", "werewolf"], ["whale shark", "whale-shark"], ["whiskers", "whiskers"], ["winged lamb", "winged-lamb"], ["world burner", "world-burner"], ["yeti", "yeti"]]);
// The collector and the catalog can use different names for the same artwork.
const radarArtAliases = new Map([
 ['abomination kong','gorillastein'],
 ['alien skeleton boss','cosmic skeleton boss'],
 ['cave dragon','cosmic dragon'],
 ['godzilla','nightflame'],
 ['king kong','gorilla king'],
 ['jellyfish','pure jellyfish'],
 ['medusa','pure jellyfish'],
]);
const demoAdmin={links:[],collectors:[],counts:{Cosmic:3,Secret:0,Eternal:0,Divine:0},unknown_count:77,events:demoItems};
async function api(path,body,signal){
 if(demo){
  if(path==='/api/me')return {authenticated:true,role:'admin'};
  if(path.startsWith('/api/feed'))return {items:demoItems,count:demoItems.length,total_count:demoItems.length,has_more:false,next_offset:demoItems.length,ttl_seconds:600,fresh_seconds:90};
  if(path==='/api/admin/overview')return demoAdmin;
  if(path==='/api/admin/links'&&body){let id='demo-link-'+Date.now();demoAdmin.links.unshift({id,label:body.label||'Acceso',created_at:demoStamp,expires_at:body.expires_hours?demoStamp+body.expires_hours*3600:null,max_uses:body.max_uses,uses:0});return {ok:true,id,url:'https://ejemplo.invalid/#/acceso/ENLACE_DEMO_NO_FUNCIONAL'};}
  if(path==='/api/admin/collectors'&&body){let id='demo-collector-'+Date.now();demoAdmin.collectors.unshift({id,label:body.label||'Recolector',created_at:demoStamp});return {ok:true,collector_id:id,credential:'CREDENCIAL_DEMO_NO_FUNCIONAL'};}
  if(path.endsWith('/revoke')&&body){let list=path.includes('/links/')?demoAdmin.links:demoAdmin.collectors;let target=list.find(x=>x.id===body.id);if(target)target.revoked_at=demoStamp;return {ok:true};}
  return {ok:true};
 }
 const r=await fetch(path,{method:body===undefined?'GET':'POST',headers:{...(body===undefined?{}:{'Content-Type':'application/json'})},body:body===undefined?undefined:JSON.stringify(body),credentials:'same-origin',cache:'no-store',signal});
 const json=await r.json().catch(()=>({error:'Respuesta inválida'}));
 if(!r.ok)throw Object.assign(Error(json.error||`Error ${r.status}`),{status:r.status});
 return json;
}
let toastTimeout;
function toast(msg){let x=$('toast');x.textContent=msg;x.classList.add('show');clearTimeout(toastTimeout);toastTimeout=setTimeout(()=>x.classList.remove('show'),2900);}
function showAccess(){
 const startup=$('pvStartup');
 if(startup)startup.hidden=true;
 $('gate').classList.remove('hidden');
}
function enter(r,persistent=false){role=r;sessionPersistent=persistent;view='feed';document.body.classList.toggle('viewer-mode',r!=='admin');$('gate').classList.add('hidden');$('app').classList.remove('hidden');$('roleIndicator').textContent=r==='admin'?'Sesión de administrador':'Acceso de solo lectura';document.querySelectorAll('.admin-only').forEach(x=>x.classList.toggle('hidden',r!=='admin'));document.querySelectorAll('.nav').forEach(x=>x.classList.toggle('selected',x.dataset.view==='feed'));$('resultsPanel').classList.remove('hidden');$('adminPanel').classList.add('hidden');$('logsPanel').classList.add('hidden');
 $('connection').textContent=demo?'DEMO · SIN CONEXIÓN':'Acceso autorizado';if(demo)document.querySelector('.live-tag').textContent='◉ MODO DEMO · NO LIVE';
 $('pvStaffAccount')?.classList.toggle('hidden',!canIssueCustomerKeys());
 render();
 const startup=$('pvStartup');
 if(startup)startup.hidden=true;
 refresh();
 if(tick)clearInterval(tick);
 if(reloadTick)clearTimeout(reloadTick);
 if(clockTick)clearInterval(clockTick);
 if(!demo){
  let nextHistoryPoll=0;
  tick=setInterval(()=>{
   const now=Date.now();
   if(radarMode==='live'){if(now>=livePollAfter)refresh();}
   else if(now>=nextHistoryPoll){nextHistoryPoll=now+4000;refresh();}
  },1000);
  // Recargar la página cada 5 minutos. El historial vive en la base de datos.
  reloadAt=(Math.floor(Date.now()/AUTO_RELOAD_MS)+1)*AUTO_RELOAD_MS;
  rotationStartedAt=reloadAt/1000-AUTO_RELOAD_MS/1000;
  updateRadarClock();
  clockTick=setInterval(updateRadarClock,1000);
  refreshRadarEvents();
  const rotate=()=>{
   reloadAt=(Math.floor(Date.now()/AUTO_RELOAD_MS)+1)*AUTO_RELOAD_MS;
   rotationStartedAt=reloadAt/1000-AUTO_RELOAD_MS/1000;
   alertedSpecies.clear();
   lastLiveRender='';
   recentThefts=[];
   scannedServers=null;
   if(view==='feed'&&radarMode==='live'){
    radarModeVersion++;
    items=[];
    render();
   }
   refresh();
   reloadTick=setTimeout(rotate,reloadAt-Date.now());
  };
  reloadTick=setTimeout(rotate,reloadAt-Date.now());
 }
}
function fail(msg){$('gateMessage').textContent=msg;}
function cleanKey(value){return value.replace(/^[\s\u200b]+|[\s\u200b]+$/g,'');}
async function login(){try{let pwd=$('adminPassword').value;if(!pwd)throw Error('Escribe la contraseña o llave de Owner');const key=cleanKey(pwd);if(/^pvfo_[A-Za-z0-9_-]{43}$/.test(key))pwd=key;const r=await api('/api/admin/login',{password:pwd});$('adminPassword').value='';enter(r.role,r.persistent);}catch(e){fail(e.message);}}
async function redeem(token){try{token=cleanKey(token);if(!token)throw Error('Falta el token privado');const ownerKey=/^pvfo_[A-Za-z0-9_-]{43}$/.test(token),coownerKey=/^pvfc_[A-Za-z0-9_-]{43}$/.test(token);if((ownerKey||coownerKey)&&location.hash.startsWith('#/acceso/'))throw Error('Pega la llave directamente en el campo de acceso');const r=ownerKey?await api('/api/admin/login',{password:token}):coownerKey?await api('/api/editor/login',{token}):await api('/api/access/redeem',{token});history.replaceState(null,'','/');$('accessToken').value='';enter(r.role,r.persistent);}catch(e){fail(e.message);}}
function dollars(x){if(x===null||x===undefined||!Number.isFinite(+x))return 'N/D';const n=+x;for(const [v,u] of [[1e15,'Qa'],[1e12,'T'],[1e9,'B'],[1e6,'M'],[1e3,'K']])if(n>=v)return '$'+(n/v).toFixed(2)+u+'/s';return '$'+n.toLocaleString('es-MX')+'/s';}
const reportDateFormat=new Intl.DateTimeFormat('es-MX',{day:'2-digit',month:'2-digit',hour:'2-digit',minute:'2-digit'});
const radarWeightFormat=new Intl.NumberFormat('es-CL',{maximumFractionDigits:2});
function prettyDate(sec){
 const date=new Date(sec*1000);
 return sec&&Number.isFinite(date.getTime())?reportDateFormat.format(date):'N/D';
}
function statusFor(x){
 if(x.data_status==='YA_NO_VISTO')return 'YA NO VISTO';
 if(x.data_status==='HISTORICO')return 'HISTÓRICO';
 if(x.data_status==='VISTO_RECIENTEMENTE')return 'VISTO EN ESCANEO RECIENTE';
 if(x.data_status==='REPORTE_RECIENTE')return 'REPORTE RECIENTE SIN VERIFICAR';
 return 'SIN CONFIRMAR';
}
function viewLabel(v){return ({feed:'Live Feed',top:'Top 5',stats:'Estadísticas',logs:'Logs',admin:'PVFINDER Admin'})[v]||v;}
function viewMode(v){if(role!=='admin'&&v!=='feed')return;if(view!==v){radarModeVersion++;lastLiveRender='';}view=v;document.body.classList.toggle('pv-radar-open',v==='feed');document.querySelectorAll('.nav').forEach(n=>n.classList.toggle('selected',n.dataset.view===v));$('sectionEyebrow').textContent=(v==='admin'?'CONFIGURACIÓN Y ACCESOS':demo?'VISTA DE DEMOSTRACIÓN — NO DATOS EN VIVO':(window.PVF_SITE_CONTENT?.home_live_tag||'MONITOREO EN TIEMPO REAL'));$('sectionTitle').innerHTML=v==='feed'?'Live <span class="grad">Feed</span>':esc(viewLabel(v));$('sectionCaption').textContent=v==='admin'?'Administra accesos, recolectores y diagnósticos.':demo?'Ejemplo visual basado en un escaneo anterior; NO son datos de un servidor en vivo.' :(window.PVF_SITE_CONTENT?.home_live_caption||`Solo reportes recibidos en los últimos ${freshSeconds} segundos; no confirma disponibilidad.`);
 $('resultsPanel').classList.toggle('hidden',v==='admin'||v==='logs');$('adminPanel').classList.toggle('hidden',v!=='admin');$('logsPanel').classList.toggle('hidden',v!=='logs');$('refreshBtn').classList.toggle('hidden',v==='admin');if(v!=='feed'&&$('radarActivity'))$('radarActivity').hidden=true;if(v==='admin')loadAdmin();else if(v==='logs')showLogs();else {render();if(v==='feed')refresh();}}

function mergeFeed(rows){
 const byId=new Map(items.map(x=>[x.server_id+':'+x.egg_id,x]));
 for(const x of rows)byId.set(x.server_id+':'+x.egg_id,x);
 items=[...byId.values()].sort((a,b)=>{
  const ai=a.income_per_second==null?-1:Number(a.income_per_second);
  const bi=b.income_per_second==null?-1:Number(b.income_per_second);
  return bi-ai || Number(b.updated_at)-Number(a.updated_at);
 });
}
function refreshStats(){
 if(role!=='admin')return;
 $('statTotal').textContent=totalCount;
 for(let r of categories){
  let n=items.filter(x=>x.rarity===r).length;
  $('stat'+r)?.replaceChildren(document.createTextNode(n));
  document.querySelectorAll(`[data-count="${r}"]`).forEach(el=>el.textContent=n);
 }
 $('statHigh').textContent=items.filter(x=>x.rarity==='Eternal'||x.rarity==='Divine').length;
}
async function fetchLiveReports(path,firstPage,requestVersion){
 const reports=new Map();
 let page=firstPage;
 let requests=1;
 while(true){
  const rows=Array.isArray(page.items)?page.items:[];
  for(const item of rows){
   const key=JSON.stringify([item.server_id,item.egg_id]);
   const previous=reports.get(key);
   if(!previous||Number(item.updated_at)>=Number(previous.updated_at))reports.set(key,item);
  }
  const cycle=firstPage.cycle_start;
  if(cycle!=null&&page.cycle_start!==cycle)return null;
  if(cycle!=null){
   if(!page.next_cursor)break;
   if(path.searchParams.get('after')===page.next_cursor)throw Error('La lista de servidores quedó incompleta');
   path.searchParams.set('after',page.next_cursor);
   if(Number.isSafeInteger(firstPage.sync_revision)){
    path.searchParams.set('through',firstPage.sync_revision);
    path.searchParams.set('sync_cycle',cycle);
    if(!firstPage.delta)path.searchParams.delete('since');
    path.searchParams.delete('wait');
   }
  }else{
   const offset=Number(page.next_offset);
   if(!page.has_more&&!(offset<Number(page.total_count)))break;
   const lastOffset=Number(path.searchParams.get('offset')||0);
   if(!Number.isInteger(offset)||offset<=lastOffset)throw Error('La lista de servidores quedó incompleta');
   path.searchParams.set('offset',offset);
  }
  if(requestVersion!==radarModeVersion)return null;
  // Respect the service's limit of 60 requests/minute even for large scans.
  if(requests>=3)await new Promise(resolve=>setTimeout(resolve,1250));
  if(requestVersion!==radarModeVersion)return null;
  page=await api(path.pathname+path.search);
  requests++;
 }
 livePollAfter=Date.now()+requests*1350;
 return [...reports.values()];
}
let radarEvents=[],nextEventRefresh=0;
function updateEventBanner(){
 const box=$('pvEventBanners');
 if(!box)return;
 const list=$('pvEventList');
 const now=Math.floor(Date.now()/1000);
 if(nextEventRefresh&&Date.now()>=nextEventRefresh)refreshRadarEvents();
 const lines=radarEvents.filter(event=>event.end>now).map(event=>{
  const active=event.start<=now;
  const seconds=(active?event.end:event.start)-now;
  const remaining=seconds>=86400
   ?Math.floor(seconds/86400)+' d '+Math.floor(seconds%86400/3600)+' h'
   :seconds<3600
   ?Math.floor(seconds/60)+':'+String(seconds%60).padStart(2,'0')
   :Math.floor(seconds/3600)+' h '+Math.floor(seconds%3600/60)+' min';
  return `<div><strong>${esc(event.title)}</strong> <small> · Evento oficial de Roblox · ${active?'Termina en':'Empieza en'} ${remaining}</small></div>`;
 }).join('');
 if(list.innerHTML!==lines)list.innerHTML=lines;
 box.hidden=!lines;
}
async function refreshRadarEvents(){
 if(demo||!$('pvEventBanners')||Date.now()<nextEventRefresh)return;
 nextEventRefresh=Date.now()+60000;
 try{
  const data=await api('/api/radar/events');
  if(Array.isArray(data.events))radarEvents=data.events;
  updateEventBanner();
 }catch{}
}
async function refresh(){
 const requestVersion=radarModeVersion;
 const isLive=view==='feed'&&radarMode==='live';
 if(isLive&&liveRefreshVersion===requestVersion)return;
 if(isLive)liveRefreshVersion=requestVersion;
 try{
  const path=new URL(feedPath(0),location.origin);
  if(isLive&&liveSyncVersion===requestVersion&&liveRevision>0){
   path.searchParams.set('since',liveRevision);
   path.searchParams.set('sync_cycle',liveSyncCycle);
   path.searchParams.set('wait','1');
  }
  const feed=await api(path.pathname+path.search);
  if(requestVersion!==radarModeVersion)return;
  const rows=isLive?await fetchLiveReports(path,feed,requestVersion):feed.items;
  if(requestVersion!==radarModeVersion||!rows)return;
  let reports=Array.isArray(rows)?rows:[];
  const sync=isLive&&Number.isSafeInteger(feed.sync_revision);
  if(isLive){
   scannedServers=Number.isInteger(feed.scanned_servers)?feed.scanned_servers:null;
   updateRadarScanCount();
  }
  if(sync){
   const emptyDelta=feed.delta&&liveSyncVersion===requestVersion
    &&feed.cycle_start===liveSyncCycle&&!reports.length;
   if(emptyDelta){
    liveRevision=feed.sync_revision;
    $('connection').textContent='REPORTES RECIBIDOS';
    return;
   }
   if(!feed.delta||liveSyncVersion!==requestVersion||feed.cycle_start!==liveSyncCycle)liveReports.clear();
   for(const item of reports)liveReports.set(JSON.stringify([item.server_id,item.egg_id]),item);
   liveSyncVersion=requestVersion;
   liveSyncCycle=feed.cycle_start;
   liveRevision=feed.sync_revision;
   reports=[...liveReports.values()];
  }
  if(isLive){
   recentThefts=reports.filter(item=>item.data_status==='YA_NO_VISTO');
   items=reports.filter(item=>item.data_status!=='YA_NO_VISTO');
  }else items=reports;
  nextOffset=Number(feed.next_offset??items.length);
  totalCount=isLive?items.length:Number(feed.total_count??feed.count??items.length);
  freshSeconds=Number(feed.fresh_seconds??90);
  hasMore=!isLive&&nextOffset<totalCount;
  $('connection').textContent=demo?'DEMO · SIN CONEXIÓN':'REPORTES RECIBIDOS';
  refreshStats();
  const sig=items.map(x=>x.server_id+':'+x.egg_id).join('|');
  if(sig!==lastSignature){lastChange=prettyDate(Math.floor(Date.now()/1000));lastSignature=sig;}
  if(view!=='admin'&&view!=='logs'){
   const fingerprint=isLive?(sync?`${liveSyncCycle}:${liveRevision}`:JSON.stringify([scannedServers,reports])):null;
   if(!isLive||fingerprint!==lastLiveRender){
    if(isLive)lastLiveRender=fingerprint;
    render();
   }
  }
  if(view==='logs')showLogs();
 }catch(e){
  if(requestVersion!==radarModeVersion)return;
  if(isLive){
   if(e.status===409){liveSyncVersion=null;livePollAfter=Date.now()+1350;return;}
   livePollAfter=Date.now()+8000;
  }
  $('connection').textContent='SIN CONEXIÓN';
  if(e.message==='Acceso no autorizado'){
   if(tick)clearInterval(tick);
   if(reloadTick)clearTimeout(reloadTick);
 if(clockTick)clearInterval(clockTick);
   document.body.classList.remove('pv-radar-open');
   $('app').classList.add('hidden');showAccess();
   fail('Sesión vencida o enlace revocado');
  }else toast('Conexión: '+e.message);
 }finally{
  if(isLive&&liveRefreshVersion===requestVersion)liveRefreshVersion=null;
 }
}
async function loadMore(){
 if(loadingMore||!hasMore)return;
 loadingMore=true;$('loadMoreBtn').disabled=true;
 try{
  const requestVersion=radarModeVersion;
  const feed=await api(feedPath(nextOffset));
  if(requestVersion!==radarModeVersion)return;
  mergeFeed(Array.isArray(feed.items)?feed.items:[]);
  nextOffset=Number(feed.next_offset??nextOffset);
  totalCount=Number(feed.total_count??totalCount);
  hasMore=nextOffset<totalCount;
  refreshStats();render();
 }catch(e){toast('No se pudieron cargar más detecciones: '+e.message);}
 finally{loadingMore=false;$('loadMoreBtn').disabled=false;}
}
// Mostrar todas las detecciones, incluidas rarezas normales, recibidas por el Finder.
 // El filtro minimo es opcional; sin umbral no ocultar huevos sin ingresos.
function shown(source=items){
 const minIncome = Number($('minIncomeFilter').value || 0);
 let list=source.filter(x=>minIncome<=0 || (
   x.income_per_second != null &&
   Number.isFinite(Number(x.income_per_second)) &&
   Number(x.income_per_second) >= minIncome
 ));
 if(categories.includes(view))list=list.filter(x=>x.rarity===view);
 if(view==='top')list=list.slice().sort((a,b)=>
   Number(b.income_per_second)-Number(a.income_per_second)).slice(0,5);
 if(view==='feed')list=list.filter(item=>(isAlienZone(item.biome)?premiumAlien(item):radarReportNames.has(keyOf(item.egg_name)))&&!filterKeys(item).some(key=>hiddenRadar.has(key)));
 const rarity=$('radarRarity')?.value;
 const biome=$('radarBiome')?.value;
 if(view==='feed'&&rarity)list=list.filter(item=>item.rarity===rarity);
 if(view==='feed'&&biome)list=list.filter(item=>item.biome===biome);
 const incomeType=$('radarIncomeType')?.value;
 if(view==='feed'&&incomeType)list=list.filter(item=>{
  const kind=String(item.income_type||'').toUpperCase();
  return incomeType==='DESCONOCIDO'?kind!=='DIRECTO'&&kind!=='ESTIMADO':kind===incomeType;
 });
 const query=$('radarSearch')?.value.trim().toLocaleLowerCase();
 if(query)list=list.filter(item=>speciesKey(item.egg_name)===speciesKey(query)
  ||[item.egg_name,item.biome,item.rarity].some(
  value=>String(value??'').toLocaleLowerCase().includes(query)
 ));
 if(view==='feed')list.sort(compareRadar);
 return list;
}
function radarSortValue(item){
 if(radarSort==='rarity')return rarityOrder.get(keyOf(item.rarity))??null;
 const field=({recent:'updated_at',weight:'weight_kg',income:'income_per_second',multiplier:'multiplier'})[radarSort];
 const value=item[field];
 return value==null||!Number.isFinite(Number(value))?null:Number(value);
}
function compareRadar(a,b){
 const left=radarSortValue(a);
 const right=radarSortValue(b);
 if(left===null||right===null)return Number(left===null)-Number(right===null)||compareIncome(a,b);
 return (radarSort==='income'?-1:radarDirection)*(left-right)||compareIncome(a,b);
}
function formatMultiplier(value){
 return value==null||!Number.isFinite(Number(value))||Number(value)<=0
  ? '× —'
  : '×'+Number(value).toFixed(2);
}
function compareIncome(a,b){
 return Number(b.income_per_second??-1)-Number(a.income_per_second??-1)
  || Number(b.updated_at)-Number(a.updated_at);
}
function joinControl(x){
  // Generar el enlace desde los IDs del propio reporte, no depender de
  // join_url: clientes anteriores no siempre lo recibian.
  const place=x.place_id==null?'':String(x.place_id).trim();
  const job=x.server_id==null?'':String(x.server_id).trim();
  const validPlace=/^[1-9]\d{0,15}$/.test(place);
  const validJob=/^[a-f\d]{8}-(?:[a-f\d]{4}-){3}[a-f\d]{12}$/i.test(job);
  if(!demo&&validPlace&&validJob){
    // Abrir la aplicacion nativa en el JobId exacto (no un server aleatorio).
    const target=`roblox://placeId=${place}&gameInstanceId=${job.toLowerCase()}`;
    return `<a class="join-button" href="${esc(target)}" title="Abrir este JobId en Roblox; puede haber cerrado o estar lleno">▸ JOIN</a>`;
  }
  const reason=!validPlace?'No se reportó un PlaceId válido':'El JobId del reporte no es válido';
  return `<button class="join-button join-disabled" disabled title="${demo?'Demostración sin servidor real':reason}">JOIN</button>`;
}

function renderTable(){
 const v=shown();
 $('resultsHeading').textContent=view==='top'?'TOP 5 — INGRESOS REPORTADOS':categories.includes(view)?view.toUpperCase()+' — HUEVOS REPORTADOS':'HUEVOS REPORTADOS RECIENTEMENTE';
 $('resultsCount').textContent=v.length;
 $('panelFoot').textContent=demo?'DATOS DE EJEMPLO — NO ESTÁ CONECTADO A ROBLOX':`Reportes recibidos en ${freshSeconds}s · ${items.length} de ${totalCount} · no confirma disponibilidad`;
 $('loadMoreBtn').classList.toggle('hidden',!hasMore||view==='top');
 $('feedRows').innerHTML=v.length?v.map(x=>{
  const kind=String(x.income_type||'DESCONOCIDO').toUpperCase();
  let incomeType=x.income_per_second==null?'unknown':kind==='ESTIMADO'?'estimated':kind==='DIRECTO'?'':'unknown';
  let mark=x.income_per_second==null?'SIN DATO':kind==='ESTIMADO'?'ESTIMADO':kind==='DIRECTO'?'DIRECTO DECLARADO':'ORIGEN NO VERIFICADO';
  let status=statusFor(x);
  let checked='';
  return `<div class="feed-row"><div class="egg"><div class="egg-icon">${x.rarity==='Divine'?'◇':x.rarity==='Eternal'?'◆':'◈'}</div><div class="egg-text"><strong title="${esc(x.egg_id)}">${esc(x.egg_name)}</strong><small><span class="rarity-tag ${esc(x.rarity)}">${esc(x.rarity||'SIN RAREZA')}</span></small></div></div><div class="meta"><strong>${esc(x.biome||'Bioma N/D')}</strong><small title="${esc(x.server_id)}">${esc(x.server_id)}</small></div><div><div class="income ${incomeType}">${esc(dollars(x.income_per_second))}</div><div class="note">${esc(mark)}</div></div><div class="mass">${x.weight_kg==null?'N/D':esc((+x.weight_kg).toLocaleString('es-MX',{maximumFractionDigits:2}))+' kg'}</div><div class="date" title="Hora de recepción en PVFinder, no disponibilidad confirmada">${esc(prettyDate(x.updated_at))}<small>${esc(status+checked)}</small></div><div class="join-cell">${joinControl(x)}</div></div>`;
 }).join(''):'<div class="empty">Sin detecciones recientes. Se mostrarán los huevos cuando llegue un nuevo escaneo.</div>';
}
function updateRadarSelect(id,field) {
 const select=$(id);
 if(!select)return;
 const selected=select.value;
 const options=radarMode==='live'
  ? items.filter(item=>categories.includes(item.rarity))
  : items;
 const values=new Set((radarMode==='live'&&field==='rarity'?categories:options.map(item=>item[field])).filter(Boolean));
 if(selected)values.add(selected);
 const choices=[...values].sort((a,b)=>a.localeCompare(b));
 if(JSON.stringify(choices)===select.dataset.choices)return;
 select.replaceChildren(select.options[0],...choices.map(value=>new Option(value,value)));
 select.value=selected;
 select.dataset.choices=JSON.stringify(choices);
}
const REFERENCE_RADAR_CSS=`
#pvEventBanners{margin:.35rem 0}
#pvEventBanners summary{width:fit-content;cursor:pointer;color:#bde8b6;font-size:.875rem}
#pvEventList div{margin:.35rem 0;padding:.6rem .85rem;border:1px solid #86d47b;border-radius:12px;background:#12271f;color:#eaffdf;overflow-wrap:anywhere}
#pvEventBanners small{color:#bde8b6}
.pv-radar-open .radar-toolbar.pv-history-mode .pv-radar-actions,.pv-radar-open .radar-toolbar.pv-history-mode .radar-sort-row,.pv-radar-open .radar-toolbar.pv-history-mode .radar-random{display:none}
body.pv-radar-open{background:#0e182c}
.pv-radar-open::before{content:"";position:fixed;inset:0;pointer-events:none;background:
 linear-gradient(#0b152a2e,#08122465),
 var(--pv-full-cover) center / contain no-repeat,
 linear-gradient(#0a1529d9,#0a1529ed),
 var(--pv-full-cover) center / cover no-repeat}
.pv-radar-open #app>.main-content{min-height:100dvh;background:none;border-radius:0}
.pv-radar-open #resultsPanel .panel-foot:not(:has(button:not(.hidden))){display:none}
.pv-radar-open #panelFoot,.pv-radar-open.viewer-mode #resultsPanel .panel-foot{display:none}
.pv-radar-open #shell{max-width:none;width:100%;margin:0}
.pv-radar-open #shell>.header,.pv-radar-open #app>.sidebar,.pv-radar-open #app .section-top,.pv-radar-open #privateStats,.pv-radar-open .footer-note{display:none}
.pv-radar-open #app.workspace{display:block;min-height:100dvh}
.pv-radar-open #app>.main-content{max-width:none;width:100%;padding:0}
.pv-radar-open .radar-toolbar{position:relative}
.pv-radar-open .pv-quick-brand{display:flex;align-items:center;gap:8px;flex-wrap:wrap;width:100%}
.pv-radar-open .pv-logo{display:flex;align-items:center;gap:9px;color:#eaf4ff;font-size:clamp(16px,2.2vw,22px);font-weight:950;letter-spacing:.09em}
.pv-radar-open .pv-logo :is(img,svg){flex:none;width:44px;height:44px;object-fit:contain;filter:drop-shadow(0 2px 6px #080d19b0)}
.pv-radar-open .pv-logo span{background:linear-gradient(102deg,#ecf7ff 4%,#8fe3ff 37%,#c1abff 70%,#ffe196 100%);background-clip:text;-webkit-background-clip:text;color:transparent}
.pv-radar-open .pv-quick-brand .live-tag{margin-left:auto;min-height:0;padding:4px 7px;font-size:11px;background:#111d32;border-color:#53698b}
.pv-radar-open .pv-quick-brand .live-tag .pulse{display:none}
.pv-radar-open .pv-quick-brand .live-tag time{font-weight:900;margin-left:4px}
.pv-radar-open .pv-quick-brand .radar-logout,.pv-radar-open .pv-quick-brand .radar-discord{display:inline-flex;align-items:center;min-height:0;padding:4px 8px;border-radius:999px;font-size:11px}

.pv-radar-open .section-actions{width:100%;margin:0;justify-content:flex-end;gap:8px}
.pv-radar-open .section-actions .live-tag{order:-1;margin-right:auto;display:grid;gap:2px;line-height:1.1;color:#a1afc8;background:none;border:0;padding:0;letter-spacing:.08em;text-transform:uppercase}
.pv-radar-open .live-tag .pulse{display:none}
.pv-radar-open .live-tag time{font-size:1.3rem;color:white;letter-spacing:0;font-weight:950}
.pv-radar-open .live-tag time.pv-ending{color:#ff7579}
.pv-radar-open .radar-discord,.pv-radar-open .radar-logout{background:#18243a;color:#f5f8ff;border:1px solid #334057;border-radius:16px;padding:9px 12px;font-weight:750}
.pv-radar-open .pv-progress{height:3px;background:#ffd245;border:0;position:absolute;bottom:0;left:0;width:var(--cycle-progress,0%)}
.pv-radar-open .pv-progress.pv-ending{background:#ff7579}
.pv-radar-open #resultsPanel{background:transparent;border:0;box-shadow:none}
.pv-radar-open .radar-toolbar{display:grid;grid-template-columns:minmax(0,1fr);justify-items:start;align-items:start;background:transparent;border:0;gap:9px;padding:13px 14px}
.pv-radar-open .radar-toolbar [role=group],.pv-radar-open .pv-radar-actions{display:flex;gap:7px;flex-wrap:wrap}
.pv-radar-open .radar-toolbar button{border-radius:999px;background:#132140e8;border:1px solid #90a6c05e;color:#e7f0ff;font-size:12px;font-weight:750;padding:4px 9px;min-height:26px}
.pv-radar-open .radar-toolbar #pvFilterOpen{background:#18294a;border-color:#7693c0}
.pv-radar-open .radar-toolbar #pvSortDirection{min-width:27px;padding-inline:6px}
.pv-radar-open .radar-toolbar #radarSearch{width:clamp(120px,24vw,190px);min-height:26px;padding:4px 9px;border-radius:999px;border-color:#657fa8;background:#132140ed;color:#fff;font-size:12px}
.pv-radar-open .radar-toolbar #radarSearch::placeholder{color:#c1d1e7}
.pv-radar-open .radar-toolbar button:focus-visible,.pv-sheet button:focus-visible{outline:2px solid #ffd04e;outline-offset:2px}
.pv-radar-open .radar-toolbar button[aria-pressed=true]{background:#285e91e8;color:#fff}
.pv-radar-open .radar-toolbar .radar-random{background:#ffcb2c;border:0;color:#171220}
.pv-radar-open .pv-radar-actions button:not(#pvFilterOpen){color:#ffd04e;border-color:#ffd04e88}
.pv-radar-open .radar-sort-row{border:0;padding-top:0}
.pv-scan-count{color:#ecf5ff;background:#132140ed;border:1px solid #5d769e;border-radius:999px;font-size:12px;font-weight:750;padding:4px 9px}
.pv-scan-count[hidden]{display:none}
.pv-radar-open .radar-results-label{display:none}
.pv-radar-open #feedRows.radar-grid{max-width:none;margin:0;padding:4px 6px 8px;gap:8px;grid-template-columns:repeat(2,minmax(0,1fr))}
.pv-radar-open #feedRows.radar-grid:has(>.radar-card:only-child){grid-template-columns:minmax(0,1fr)}
.pv-radar-open .radar-card,.pv-history-tile{--zone:#69cff0;border:1px solid #344c72;border-top:3px solid var(--zone);border-radius:15px;background:linear-gradient(160deg,#192940,#111a30 65%);box-shadow:0 8px 24px #050c1b50;padding:12px;min-width:0}
.pv-radar-open .radar-zone{color:var(--zone);font-size:11px;font-weight:950;letter-spacing:.15em}
.pv-radar-open .radar-title{gap:11px;margin:9px 0 11px;grid-template-columns:58px minmax(0,1fr) auto}
.pv-radar-open .radar-title h2,.pv-history-tile h3{font-weight:1000;color:var(--rarity,#dae4f4);font-size:clamp(15px,2.15vw,25px);letter-spacing:-.02em;text-transform:uppercase}
.pv-radar-open .radar-best strong{color:#ffd237}
.pv-radar-open .pv-variants{display:grid;gap:5px;min-width:0}
.pv-radar-open .radar-report{min-height:49px;margin:0;padding:6px 8px;border:1px solid transparent;border-radius:13px;background:linear-gradient(90deg,color-mix(in srgb,var(--zone) 18%,#1a2845) var(--rank,0%),#1a2845 var(--rank,0%))}
.pv-radar-open .radar-report.pv-leader .radar-value>strong{color:#ffdb4a}
.pv-radar-open .radar-report.radar-report-absent{border-color:#9a556b}
.pv-radar-open .radar-report .radar-value{display:flex;flex-wrap:wrap;gap:4px 6px;align-items:center;font-size:.74rem}
.pv-radar-open .radar-value>strong{color:#edf4ff;font-size:1.05rem}
.pv-radar-open .pv-income,.pv-mutation,.pv-stolen{border:1px solid #8292ac55;border-radius:6px;padding:1px 4px;color:#c3d1e5;white-space:nowrap;font-size:.67rem}
.pv-radar-open .pv-mutation{color:#11182b;background:#dce6f7;font-weight:850}.pv-radar-open .pv-mutation[data-mut=golden]{background:#ffc758}.pv-radar-open .pv-mutation[data-mut=rainbow]{background:#d5a1ff}
.pv-radar-open .pv-no-multiplier{opacity:.64}
.pv-radar-open .radar-best .pv-max-weight{font-size:11px}
.pv-radar-open .pv-stolen{color:#ff9aa7;border-color:#bc5c7388;font-weight:850;letter-spacing:.05em}
.pv-radar-open .radar-report time{color:#82ec92;font-weight:800}.pv-radar-open .radar-report-absent time{color:#e5b0a2}
.pv-radar-open .radar-report .join-button:not(.join-disabled){background:linear-gradient(135deg,#ffc327,#ff9121);color:#151017;border-radius:15px;font-weight:1000;letter-spacing:.08em}
.pv-radar-open .pv-sheet{position:fixed;inset:0 0 0 auto;margin:0;height:100dvh;max-height:none;width:min(95vw,470px);max-width:none;border:0;border-left:1px solid #34415b;padding:0;background:#121d34;color:#f0f5ff;z-index:20;overflow:auto}
.pv-sheet::backdrop{background:#0308199c}
.pv-sheet button[hidden]{display:none}
.pv-radar-open #pvFilterSheet{width:min(82vw,278px);background:#101b31}
#pvFilterSheet .pv-sheet-head{padding:8px 11px}
#pvFilterSheet .pv-sheet-head h2{font-size:.94rem}
#pvFilterSheet .pv-sheet-body{padding:7px 11px 14px}
#pvFilterSheet .pv-sheet-body h3{margin:11px 0 5px;font-size:.69rem}
#pvFilterSheet .pv-sheet-body p{font-size:.72rem;line-height:1.35;margin:8px 0}
#pvFilterSheet .pv-chipset{gap:4px}
#pvFilterSheet button{padding:3px 7px;border-radius:999px;min-height:24px;font-size:.7rem}
#pvFilterSheet button[data-pv-filter]{color:var(--chip-color,#e4edff);background:#19263e;border-color:#394b68}
#pvFilterSheet button[data-pv-filter]:hover{background:#263755;border-color:#8299bf}
#pvFilterSheet button[data-pv-filter][aria-pressed=false]{background:#111b2d;border-style:dashed}

.pv-sheet-head{position:sticky;top:0;background:#121d34;z-index:1;display:flex;align-items:center;justify-content:space-between;border-bottom:1px solid #34415b;padding:12px 16px}
.pv-sheet-head h2{margin:0;text-transform:uppercase;font-size:1.15rem;font-weight:950}
.pv-sheet-body{padding:12px 16px 22px}
.pv-sheet-body h3,.pv-history-label{margin:15px 0 8px;color:#b6c8e4;font-weight:900;font-size:.78rem;letter-spacing:.13em;text-transform:uppercase}
.pv-sheet-body p,.pv-history-tile p{color:#a8bad7;font-size:.88rem}
.pv-chipset{display:flex;flex-wrap:wrap;gap:6px}
.pv-sheet button{background:#1c2941;border:1px solid #3a4962;color:#edf4ff;border-radius:14px;padding:8px 10px;min-height:35px;font:inherit;font-size:.84rem;cursor:pointer}
.pv-sheet button[aria-pressed=false]{opacity:.57;text-decoration:line-through}
.pv-sheet button[aria-pressed=true]{border-color:#718cb7}
.pv-sheet .pv-chip-icon,.pv-cycle-pill .pv-chip-icon,.pv-history-tile .pv-chip-icon{background-position:center;background-size:contain;background-repeat:no-repeat;display:inline-block;vertical-align:middle;width:24px;height:24px;margin-right:4px}
.pv-sheet #radarSearch{width:100%;border:1px solid #465977;border-radius:10px;background:#0e182b;color:#fff;padding:9px}
.pv-radar-open #feedRows.pv-history-grid{grid-template-columns:repeat(auto-fit,minmax(min(140px,46%),1fr))}
.pv-history-label,.pv-cycle-list,.pv-scanning{grid-column:1/-1}
.pv-history-tile{text-align:center}.pv-history-tile h3{font-size:14px;margin:6px 0}.pv-history-tile .pv-chip-icon{width:48px;height:48px;margin:0}
.pv-history-tile p{margin:6px 0}.pv-cycle-row{display:flex;align-items:center;gap:8px;padding:7px;background:#121e34;border:1px solid #2d3b57;border-radius:12px;margin:4px 0}
.pv-cycle-row time{font-variant-numeric:tabular-nums;color:#b9cae3;min-width:3.3em}.pv-cycle-row>div{display:flex;gap:4px;flex-wrap:wrap}
.pv-cycle-pill{background:#202c43;border-radius:12px;padding:3px 6px;color:#d9e4f6;font-size:.8rem}
.pv-scanning{min-height:220px;display:grid;place-content:center;text-align:center;background:#101c39a8;border-radius:18px}
.pv-scanning strong{font-size:1.45rem}.pv-scanning time{font-size:2.6rem;font-weight:950}
@media(max-width:720px){.pv-radar-open #feedRows.radar-grid{grid-template-columns:minmax(0,1fr)}.pv-radar-open #feedRows.pv-history-grid{grid-template-columns:repeat(2,minmax(0,1fr))}.pv-radar-open .section-actions{justify-content:flex-start}.pv-radar-open .radar-toolbar{padding-top:9px}}
`;
const zoneColors = new Map([
 ['abandoned manor','#ff8753'],['haunted swamp','#ffab68'],['enchanted forest','#65d5f5'],
 ['light dark','#f2da90'],['titan temple','#ffba56'],['cherry blossom','#f685b7'],
 ['cosmic','#ae94ff'],['prehistoric','#73df9f'],['alien','#98ea69']
]);
const rarityColors = new Map([['divine','#ffec49'],['eternal','#ff4be7'],['secret','#d9e0ec'],['cosmic','#b9a6ff']]);
const zoneColor=name=>zoneColors.get(String(name??'').toLowerCase())||'#69cff0';
const rarityColor=name=>rarityColors.get(String(name??'').toLowerCase())||'#d9e4f6';
const keyOf=name=>String(name??'').trim().toLowerCase();
const speciesKey=name=>{
 const key=keyOf(name);
 return radarArtAliases.get(key)??key;
};
function storedRadarSetting(key,fallback){
 try{return JSON.parse(localStorage.getItem('pv-radar-'+key))??fallback;}catch{return fallback;}
}
function saveRadarSetting(key,value){
 try{localStorage.setItem('pv-radar-'+key,JSON.stringify(value));}catch{}
}
const hiddenRadar = new Set(storedRadarSetting('hidden',[]).map(key=>
 key.startsWith('egg:')?'egg:'+speciesKey(key.slice(4)):key));
let radarAlerts = storedRadarSetting('alerts',false);
let radarAudio;
function unlockRadarAudio(){
 const AudioContext=window.AudioContext||window.webkitAudioContext;
 if(!AudioContext||!radarAlerts||demo)return;
 try{
  radarAudio??=new AudioContext();
  radarAudio.resume().catch(()=>{});
 }catch{}
}
function playRadarAlert(){
 if(radarAudio?.state!=='running'||document.hidden)return;
 const start=radarAudio.currentTime;
 const tone=radarAudio.createOscillator();
 const gain=radarAudio.createGain();
 tone.frequency.setValueAtTime(660,start);
 tone.frequency.setValueAtTime(880,start+0.12);
 gain.gain.setValueAtTime(0.055,start);
 gain.gain.exponentialRampToValueAtTime(0.001,start+0.25);
 tone.connect(gain);
 gain.connect(radarAudio.destination);
 tone.start(start);
 tone.stop(start+0.25);
}
const filterCatalog = new Map([
 ['Abandoned Manor',['Voidseer Pumpkin','Abomination Kong','Werewolf']],
 ['Cherry Blossom',['Kitsune','Oni Tiger','Stag']],
 ['Cosmic',['Unicorn','Eternal Lunar Dragon','Alien Skeleton Boss','Cave Dragon']],
 ['Enchanted Forest',['Royal Skywhale','Celestial Sunlion','Starry Fox']],
 ['Haunted Swamp',['Shelltide Voyager']],
 ['Light Dark',['World Burner','ArchAngel','Skeleton Horse','Pegasus','RazorFang','Centaur','Gargoyle']],
 ['Prehistoric',['Mosasaurus']],
 ['Titan Temple',['Godzilla','King Kong','Shark']],
 ['Medusa',['Medusa','Jellyfish','Pure Jellyfish']],
 ['Alien',['Aurora Stag','Tideler','Viridian Prowler']]
].map(([zone,names])=>[zone,new Map(names.map(name=>[keyOf(name),name]))]));
const isAlienZone=name=>['alien','alien zone','zona alien'].includes(keyOf(name));
const premiumAlien=item=>isAlienZone(item.biome)
 && (rarityOrder.get(keyOf(item.rarity))??-1)>=rarityOrder.get('secret');
const jellyfishNames=new Set(filterCatalog.get('Medusa').keys());
const curatedSpecies=new Set([...filterCatalog].filter(([zone])=>zone!=='Alien').flatMap(([,names])=>[...names.keys()]));
const radarReportNames=new Set([...curatedSpecies,...[...curatedSpecies].map(speciesKey)]);
function filterKeys(item){
 const name=speciesKey(item.egg_name);
 const zone=isAlienZone(item.biome)?'alien':jellyfishNames.has(name)?'medusa':keyOf(item.biome);
 return ['zone:'+zone,'rarity:'+keyOf(item.rarity),'egg:'+name];
}
function collectAlienNames(){
 const names=filterCatalog.get('Alien');
 for(const item of [...items,...recentThefts]){
  if(premiumAlien(item)&&item.egg_name&&!names.has(keyOf(item.egg_name)))names.set(keyOf(item.egg_name),item.egg_name);
 }
}
function radarIcon(name){
 const key=speciesKey(name);
 const pet=radarPets.get(key), egg=radarArt.get(key);
 const art=pet?'radar-pet-'+pet:egg?'radar-art-'+egg:'';
 return art?'<span class="pv-chip-icon '+art+'" aria-hidden="true"></span>':'';
}
function drawRadarFilters(){
 const chip=(name,key,color='')=>`<button type="button" data-pv-filter="${esc(key)}" aria-pressed="${!hiddenRadar.has(key)}"${color?` style="--chip-color:${color}"`:''}>${esc(name)}</button>`;
 const groups=[...filterCatalog.entries()].sort(([a],[b])=>a.localeCompare(b));
 $('pvFilterChips').innerHTML=`<h3>Zonas</h3><div class="pv-chipset">${groups.map(([zone])=>chip(zone,'zone:'+keyOf(zone),zoneColor(zone))).join('')}</div>
 <h3>Rarezas</h3><div class="pv-chipset">${[...categories].reverse().map(name=>chip(name,'rarity:'+keyOf(name),rarityColor(name))).join('')}</div>
 <p>Toca una zona, rareza o huevo para ocultarlo o volver a verlo. Lo oculto no aparece ni avisa.</p>
 ${groups.map(([zone,names])=>`<h3 style="color:${zoneColor(zone)}">${esc(zone)}</h3><div class="pv-chipset">${[...names].map(([key,name])=>chip(name,'egg:'+speciesKey(key))).join('')}</div>`).join('')}`;
}
function canIssueCustomerKeys(){return !demo&&(role==='admin'||role==='coowner');}
function bindCustomerKeys(){
 const sheet=$('pvKeysSheet'), form=$('pvKeyForm'), status=$('pvKeyStatus'), list=$('pvKeyList'),
  result=$('pvKeyResult'), code=$('pvKeyCode'), create=$('pvKeyCreate'),
  unit=$('pvKeyUnit'), amount=$('pvKeyAmount');
 const date=sec=>new Intl.DateTimeFormat('es-CL',{dateStyle:'medium',timeStyle:'short',timeZone:'America/Santiago'}).format(sec*1000);
 const syncFields=()=>{
  amount.max=unit.value==='hours'?87600:3650;
 };
 const wipe=()=>{code.value='';result.classList.remove('show');};
 const listKeys=async()=>{
  try{
   const data=await api('/api/editor/keys');
   const records=[...(data.keys||[]),...(data.web_keys||[])].sort((a,b)=>b.created_at-a.created_at).slice(0,30);
   list.innerHTML=records.length?records.map(k=>{
    const state=k.revoked_at?'Revocada':k.expires_at&&k.expires_at<=Date.now()/1000?'Vencida':'Activa';
    const mode=k.roblox_user_id?'Cuenta vinculada (llave anterior)':'PVFinder web y Delta';
    const expiry=k.expires_at?' · vence '+esc(date(k.expires_at)):'';
    return `<div class="admin-record"><div><strong>${esc(k.label)}</strong><small>${mode} · ${state}${expiry}</small></div>${state==='Activa'?`<button type="button" class="secondary" data-revoke-key="${esc(k.id)}">Revocar</button>`:''}</div>`;
   }).join(''):'<p>Aún no hay llaves.</p>';
  }catch(e){list.textContent=e.message;}
 };
 $('pvKeysOpen').onclick=()=>{
  if(!canIssueCustomerKeys())return;
  $('pvAccountSheet').close();wipe();status.textContent='';
  sheet.showModal();list.textContent='Cargando llaves…';listKeys();
 };
 sheet.addEventListener('close',()=>{wipe();list.replaceChildren();status.textContent='';});
 unit.onchange=syncFields;syncFields();
 form.onsubmit=async event=>{
  event.preventDefault();
  if(create.disabled||!canIssueCustomerKeys()||!form.reportValidity())return;
  const n=Number(amount.value), hours=unit.value==='days'?n*24:n;
  if(!Number.isSafeInteger(hours)||hours<1||hours>87600)return;
  create.disabled=true;wipe();status.textContent='Generando…';
  try{
   const r=await api('/api/editor/keys',{action:'create',kind:'universal',label:$('pvKeyLabel').value.trim(),hours});
   if(!sheet.open)return;
   code.value=r.key;
   $('pvKeyExpiry').textContent='Vence el '+date(r.expires_at)+' (hora de Chile).';
   $('pvKeyCopyLink').classList.remove('hidden');
   status.textContent='Llave creada.';
   result.classList.add('show');
   listKeys();
  }catch(e){status.textContent=e.message;}finally{create.disabled=false;}
 };
 async function copyKey(link){
  if(!code.value)return;
  const value=link?location.origin+'/#/acceso/'+code.value:code.value;
  try{await navigator.clipboard.writeText(value);status.textContent=link?'Enlace copiado.':'Llave copiada.';}
  catch{code.focus();code.select();status.textContent='Copia la llave seleccionada manualmente.';}
 }
 $('pvKeyCopy').onclick=()=>copyKey(false);
 $('pvKeyCopyLink').onclick=()=>copyKey(true);
 list.onclick=async event=>{
  const button=event.target.closest('[data-revoke-key]');
  if(!button||button.disabled||!canIssueCustomerKeys()||!confirm('¿Revocar esta llave y cerrar las sesiones que abrió?'))return;
  button.disabled=true;
  try{
   await api('/api/editor/keys',{action:'revoke',id:button.dataset.revokeKey});
   wipe();status.textContent='Llave revocada.';await listKeys();
  }catch(e){status.textContent=e.message;button.disabled=false;}
 };
}

function setUpRadarReference(){
 const toolbar=document.querySelector('.radar-toolbar'), menu=toolbar?.querySelector('#pvRadarFilterState, .radar-filter-menu');
 if(!menu)return;
 const style=document.createElement('style');
 style.textContent=REFERENCE_RADAR_CSS;
 document.head.append(style);
 if(!$('pvEventBanners')){
  const eventBanners=document.createElement('details');
  eventBanners.id='pvEventBanners';
  eventBanners.innerHTML='<summary>Eventos oficiales</summary><div id="pvEventList"></div>';
  eventBanners.hidden=true;
  toolbar.before(eventBanners);
 }
 let actions=toolbar.querySelector('.pv-radar-actions');
 if(!actions){
  actions=document.createElement('div');
  actions.className='pv-radar-actions';
  actions.innerHTML='<button type="button" id="pvFilterOpen">Filtros</button><button type="button" id="pvAlertOpen">Alertas</button><button type="button" id="pvCatalogOpen">Catálogo</button><button type="button" id="pvStaffAccount" class="hidden">Mi cuenta</button>';
  menu.before(actions);
 }
 $('radarAbsent')?.remove();
 menu.hidden=true;
 const sheets=document.createElement('div');
 sheets.innerHTML=`<dialog id="pvFilterSheet" class="pv-sheet" aria-labelledby="pvFilterTitle">
 <div class="pv-sheet-head"><h2 id="pvFilterTitle">Filtros</h2><form method="dialog"><button aria-label="Cerrar filtros">✕</button></form></div>
 <div class="pv-sheet-body" id="pvFilterChips"></div></dialog>
 <dialog id="pvCatalogSheet" class="pv-sheet" aria-labelledby="pvCatalogTitle">
 <div class="pv-sheet-head"><h2 id="pvCatalogTitle">Catálogo de huevos y mascotas</h2><form method="dialog"><button aria-label="Cerrar catálogo">✕</button></form></div>
 <div class="pv-sheet-body" id="pvCatalogGroups"></div></dialog>
 <dialog id="pvAccountSheet" class="pv-sheet" aria-labelledby="pvAccountTitle">
 <div class="pv-sheet-head"><h2 id="pvAccountTitle">Mi cuenta</h2><form method="dialog"><button aria-label="Cerrar cuenta">✕</button></form></div>
 <div class="pv-sheet-body"><h3>Tu acceso</h3><p id="pvAccountStatus"></p><p id="pvSessionTime"></p><button type="button" id="pvKeysOpen" class="primary hidden">Generar llaves</button><button type="button" id="pvAdminOpen" hidden>Administrar radar</button><button type="button" id="pvAccountExit">Salir</button></div></dialog>
 <dialog id="pvKeysSheet" class="pv-sheet" aria-labelledby="pvKeysTitle">
 <div class="pv-sheet-head"><h2 id="pvKeysTitle">Llaves para clientes</h2><form method="dialog"><button aria-label="Cerrar llaves">✕</button></form></div>
 <div class="pv-sheet-body">
 <p>Genera una llave de visitante para PVFinder web y Delta, sin nombre ni ID de Roblox.</p>
 <form id="pvKeyForm" class="gate-form">
 <label for="pvKeyLabel">Nombre o referencia del cliente (opcional)</label><input id="pvKeyLabel" maxlength="60" autocomplete="off" placeholder="Ej. Pedido 104">
 <div class="field-row"><div class="field"><label for="pvKeyAmount">Duración</label><input id="pvKeyAmount" type="number" min="1" max="3650" step="1" value="7" required></div>
 <div class="field"><label for="pvKeyUnit">Unidad</label><select id="pvKeyUnit"><option value="days">Días</option><option value="hours">Horas</option></select></div></div>
 <button type="submit" class="primary" id="pvKeyCreate">Generar llave</button>
 </form>
 <p id="pvKeyStatus" role="status" aria-live="polite"></p>
 <div id="pvKeyResult" class="admin-result">
 <label for="pvKeyCode">Llave del cliente</label><input id="pvKeyCode" readonly autocomplete="off">
 <p id="pvKeyExpiry"></p>
 <button type="button" class="secondary" id="pvKeyCopy">Copiar llave</button>
 <button type="button" class="secondary" id="pvKeyCopyLink">Copiar enlace de acceso</button>
 <p>Cópiala ahora: el código no se vuelve a mostrar.</p></div>
 <h3>Llaves recientes</h3><div id="pvKeyList" class="admin-list"></div>
 </div></dialog>`;
 document.body.append(sheets);
 bindCustomerKeys();
 const catalogSheet=$('pvCatalogSheet');
 $('pvCatalogOpen').onclick=()=>{
  collectAlienNames();
  $('pvCatalogGroups').innerHTML='<p>Incluye los huevos que sigue el radar aunque no hayan salido en este ciclo.</p>'
   +[...filterCatalog].map(([zone,names])=>
    `<h3 style="color:${zoneColor(zone)}">${esc(zone)}</h3><div class="pv-chipset">${[...names.values()].map(name=>
     `<button type="button" data-catalog-name="${esc(name)}">${radarIcon(name)}${esc(name)}</button>`).join('')}</div>`).join('');
  catalogSheet.showModal();
 };
 $('pvCatalogGroups').onclick=event=>{
  const button=event.target.closest('button[data-catalog-name]');
  const input=$('radarSearch');
  if(!button||!input)return;
  input.value=button.dataset.catalogName;
  catalogSheet.close();
  if(radarMode==='live')render();else $('radarLive').click();
 };
 const search=$('radarSearch');
 if(search&&!actions.contains(search)){
  search.setAttribute('aria-label','Buscar mascota o huevo');
  search.placeholder='Buscar mascota…';
  actions.append(search);
 }
 if(!$('pvScanCount')){
  const scanCount=document.createElement('output');
  scanCount.id='pvScanCount';
  scanCount.className='pv-scan-count';
  actions.after(scanCount);
 }
 const random=$('radarRandom');
 if(random)random.textContent='Servidor aleatorio';
 $('pvFilterOpen').onclick=()=>{collectAlienNames();drawRadarFilters();$('pvFilterSheet').showModal();};
 $('pvFilterChips').onclick=event=>{
  const button=event.target.closest('button[data-pv-filter]');
  if(!button)return;
  const key=button.dataset.pvFilter;
  if(hiddenRadar.has(key))hiddenRadar.delete(key);else hiddenRadar.add(key);
  button.setAttribute('aria-pressed',String(!hiddenRadar.has(key)));
  saveRadarSetting('hidden',[...hiddenRadar]);
  renderRadar();
 };
 const alert=$('pvAlertOpen');
 alert.setAttribute('aria-pressed',String(radarAlerts));
 if(radarAlerts)document.addEventListener('click',unlockRadarAudio,{once:true});
 alert.onclick=()=>{
  radarAlerts=!radarAlerts;
  saveRadarSetting('alerts',radarAlerts);
  alert.setAttribute('aria-pressed',String(radarAlerts));
  if(radarAlerts)unlockRadarAudio();
  toast(radarAlerts?'Alertas del radar activadas en esta pestaña':'Alertas del radar desactivadas');
 };
 const account=$('radarLogout');
 if(account){
  account.textContent='Mi cuenta';
  const staffAccount=$('pvStaffAccount');
  if(staffAccount)staffAccount.onclick=()=>account.click();
  account.onclick=async()=>{
   $('pvAccountStatus').textContent=role==='admin'?'Sesión de administrador':role==='coowner'?'Sesión de coadministración':'Sesión de visitante';
   $('pvAdminOpen').hidden=role!=='admin';
   $('pvKeysOpen').classList.toggle('hidden',!canIssueCustomerKeys());
   $('pvAccountSheet').showModal();
   updateSessionClock();
   if(!demo){
    try{
     const me=await api('/api/me');
     sessionPersistent=me.persistent===true;
     sessionExpiry=me.expires_at??null;
     sessionExpiryUnavailable=!sessionExpiry;
     sessionClockOffset=Number.isFinite(me.server_time)?me.server_time*1000-Date.now():0;
    }catch{sessionExpiry=null;sessionExpiryUnavailable=true;}
    updateSessionClock();
   }
  };
 }
 $('pvAccountExit').onclick=()=>$('logoutBtn').click();
 $('pvAdminOpen').onclick=()=>{$('pvAccountSheet').close();viewMode('admin');};
 const header=document.querySelector('.section-top');
 if(header&&!toolbar.querySelector('.pv-quick-brand')){
  const bar=document.createElement('div');
  bar.className='pv-quick-brand';
  const mark=`<svg xmlns="http://www.w3.org/2000/svg" width="192" height="192" viewBox="0 0 64 64">
   <defs>
    <linearGradient id="rim" x2="1" y2="1"><stop stop-color="#79e1ff"/><stop offset=".62" stop-color="#a888ff"/><stop offset="1" stop-color="#ffd67d"/></linearGradient>
    <linearGradient id="egg" x2="1" y2="1"><stop stop-color="#67cfff"/><stop offset="1" stop-color="#6b53db"/></linearGradient>
   </defs>
   <rect x="2" y="2" width="60" height="60" rx="17" fill="#090f20" stroke="url(#rim)" stroke-width="1.4"/>
   <path d="M32 10c-7 0-17 15-17 25a17 17 0 0 0 34 0c0-10-10-25-17-25Z" fill="url(#egg)" fill-opacity=".33" stroke="url(#rim)" stroke-width="2.1"/>
   <circle cx="32" cy="33" r="9" fill="none" stroke="#ffe096" stroke-width="1.7"/>
   <path d="M32 20v6m0 14v6M19 33h6m14 0h6" fill="none" stroke="#a6e5ff" stroke-width="1.6" stroke-linecap="round"/>
   <path d="m32 28 4 5-4 5-4-5z" fill="#ffe096"/>
   <path d="m49 11 1.5 3.5L54 16l-3.5 1.5L49 21l-1.5-3.5L44 16l3.5-1.5z" fill="#ffdb85"/>
  </svg>`;
  const markUrl='data:image/svg+xml,'+encodeURIComponent(mark);
  bar.innerHTML='<span class="pv-logo"><img width="44" height="44" alt=""><span>PVFINDER</span></span>';
  bar.querySelector('img').src=markUrl;
  toolbar.prepend(bar);
  for(const selector of ['.live-tag','.radar-discord','.radar-logout']){
   const control=header.querySelector(selector);
   if(control)bar.append(control);
  }
  const resetLabel=bar.querySelector('.live-tag>span:nth-child(2)');
  if(resetLabel)resetLabel.textContent='Reset';
  const discord=bar.querySelector('.radar-discord');
  if(discord)discord.textContent='Discord';
  for(const rel of ['icon','apple-touch-icon']){
   const link=document.createElement('link');
   link.rel=rel;
   link.href=markUrl;
   document.head.append(link);
  }
 }
 const sortRow=toolbar.querySelector('.radar-sort-row');
 if(sortRow){
  const direction=document.createElement('button');
  direction.type='button';
  direction.id='pvSortDirection';
  const sync=()=>{
   direction.hidden=radarSort==='income';
   direction.textContent=radarDirection<0?'↓':'↑';
   direction.title=radarDirection<0?'De mayor a menor':'De menor a mayor';
   direction.setAttribute('aria-label',direction.title+' · invertir orden');
  };
  direction.onclick=()=>{radarDirection*=-1;sync();render();};
  sortRow.addEventListener('click',sync);
  sync();
  sortRow.append(direction);
 }
}
function renderRadarHistory(detections){
 const results=$('feedRows');
 results.classList.add('pv-history-grid');
 const species=new Map(), cycles=new Map();
 const cycleAt=timestamp=>{
  const time=Math.floor(Number(timestamp)/300)*300;
  if(!time)return null;
  if(!cycles.has(time))cycles.set(time,{reports:new Map(),thefts:[]});
  return cycles.get(time);
 };
 for(const item of detections){
  const name=keyOf(item.egg_name);
  const stats=species.get(name);
  const multiplier=Number(item.multiplier??0);
  if(!stats)species.set(name,{latest:item,multiplier});
  else {
   if(Number(item.updated_at)>Number(stats.latest.updated_at))stats.latest=item;
   stats.multiplier=Math.max(stats.multiplier,multiplier);
  }
  const cycle=cycleAt(item.updated_at);
  if(cycle&&(!cycle.reports.has(name)||compareIncome(item,cycle.reports.get(name))<0)){
   cycle.reports.set(name,item);
  }
  if(item.data_status==='YA_NO_VISTO')cycleAt(item.checked_at)?.thefts.push(item);
 }
 if(!species.size){results.innerHTML='<div class="empty">Sin reportes para estos filtros.</div>';return;}
 const tiles=[...species.values()].sort((a,b)=>{
  const rank=item=>rarityOrder.get(keyOf(item.latest.rarity))??-1;
  return rank(b)-rank(a)||Number(b.latest.updated_at)-Number(a.latest.updated_at);
 }).map(({latest:item,multiplier})=>`<article class="pv-history-tile" style="--zone:${zoneColor(item.biome)};--rarity:${rarityColor(item.rarity)}">
 ${radarIcon(item.egg_name)}<h3>${esc(item.egg_name)}</h3><p>${esc(item.biome||'Bioma sin dato')}</p>
 <strong><time data-received-at="${Number(item.updated_at)}">${elapsedReportTime(Number(item.updated_at))}</time></strong>
 <p>Mayor ${multiplier>0?'×'+esc(multiplier):esc(dollars(item.income_per_second))}</p></article>`).join('');
 const timeline=[...cycles].sort(([a],[b])=>b-a).map(([time,cycle])=>{
  const reports=[...cycle.reports.values()].sort(compareIncome).slice(0,2).map(item=>
   `<span class="pv-cycle-pill">${radarIcon(item.egg_name)}${esc(item.egg_name)} ${item.multiplier==null?'':'×'+esc(item.multiplier)}</span>`
  );
  const thefts=cycle.thefts.sort((a,b)=>Number(b.checked_at)-Number(a.checked_at)).map(item=>{
   const checkedAt=Number(item.checked_at);
   return `<span class="pv-cycle-pill">${radarIcon(item.egg_name)}${esc(item.egg_name)}
    <span class="pv-stolen">ROBADO</span>
    <time data-received-at="${checkedAt}" title="${esc(prettyDate(checkedAt))}">${elapsedReportTime(checkedAt)}</time></span>`;
  });
  return `<div class="pv-cycle-row">
   <time title="${esc(prettyDate(time))}">${esc(new Date(time*1000).toLocaleTimeString('es-CL',{hour:'2-digit',minute:'2-digit'}))}</time>
   <div>${thefts.concat(reports).join('')}</div></div>`;
 }).join('');
 results.innerHTML=`<h2 class="pv-history-label">Cuánto llevan sin salir</h2>${tiles}<section class="pv-cycle-list"><h2 class="pv-history-label">Qué salió en cada ciclo</h2>${timeline}</section>`;
}

function renderRadarActivity(showRadar) {
 const activity=$('radarActivity');
 if(!activity)return;
 activity.hidden=!showRadar||!items.length||radarMode!=='live';
 if(activity.hidden)return;
 const latest=[...items].sort((a,b)=>Number(b.updated_at)-Number(a.updated_at)).slice(0,4);
 $('radarActivityList').innerHTML=latest.map(item=>{
  const time=Number(item.updated_at);
  return `<li><span aria-hidden="true">◈</span> <strong>${esc(item.egg_name)}</strong> <time data-received-at="${time}">${elapsedReportTime(time)}</time></li>`;
 }).join('');
}
function render() {
 const showRadar = view === 'feed';
 const toolbar=document.querySelector('.radar-toolbar');
 if(!toolbar){renderTable();return;}
 toolbar.hidden = !showRadar;
 document.querySelector('#resultsPanel .table-head').hidden = showRadar;
 $('feedRows').classList.toggle('radar-grid', showRadar);
 document.body.classList.toggle('pv-radar-open',showRadar&&!$('app').classList.contains('hidden'));
 if (showRadar) {
  renderRadar();
 }
 else renderTable();
}
function updateRadarScanCount(){
 const scanCount=$('pvScanCount');
 if(!scanCount)return;
 scanCount.hidden=radarMode!=='live'||scannedServers===null;
 if(scanCount.hidden)return;
 const label=`${scannedServers.toLocaleString('es-CL')} ${scannedServers===1?'servidor escaneado':'servidores escaneados'} en este ciclo`;
 if(scanCount.textContent!==label)scanCount.textContent=label;
}
function renderRadar(){
 const detections=shown();
 const toolbar=document.querySelector('.radar-toolbar');
 toolbar.classList.toggle('pv-history-mode',radarMode==='history');
 const feedRows=$('feedRows');
 updateRadarScanCount();
 feedRows.classList.toggle('pv-history-grid',radarMode==='history');
 if(radarMode==='history'){
  $('loadMoreBtn').classList.toggle('hidden',!hasMore);
  $('panelFoot').textContent='Historial de reportes cargados · horarios del radar';
  renderRadarHistory(detections);
  return;
 }
 const live=radarMode==='live';
 const searching=live&&Boolean($('radarSearch')?.value.trim());
 const speciesOf=item=>speciesKey(item.egg_name);
 const groups=new Map();
 for(const detection of detections){
  const key=live?speciesOf(detection):JSON.stringify([detection.egg_name,detection.biome,detection.rarity]);
  if(!groups.has(key))groups.set(key,[]);
  groups.get(key).push(detection);
 }

 let cards=[...groups];
 if(live){
  const bySort=cards.map(([key,rows])=>[key,[...rows].sort(compareRadar)])
   .sort(([,a],[,b])=>compareRadar(a[0],b[0]));
  const matchingThefts=shown(recentThefts);
  if(!searching){
   const newSpecies=bySort.filter(([key])=>!alertedSpecies.has(key));
   if(radarAlerts&&!demo&&newSpecies.length){
    toast('¡Huevo nuevo! '+newSpecies[0][1][0].egg_name);
    playRadarAlert();
   }
   for(const [key] of newSpecies)alertedSpecies.add(key);
  }
  const reported=new Set(detections.map(item=>JSON.stringify([item.server_id,item.egg_id])));
  for(const item of matchingThefts){
   const key=speciesOf(item);
   if(reported.has(JSON.stringify([item.server_id,item.egg_id])))continue;
   if(!groups.has(key))groups.set(key,[]);
   groups.get(key).push(item);
  }
  const rankedKeys=bySort.map(([key])=>key);
  cards=[...new Set([...rankedKeys,...groups.keys()])].map(key=>[key,groups.get(key)]);
 }
 $('resultsHeading').textContent='HUEVOS DETECTADOS';
 $('resultsCount').textContent=live?cards.length:detections.length;
 if($('radarRandom'))$('radarRandom').hidden=!live;
 $('panelFoot').textContent=demo?'DEMOSTRACIÓN · DATOS DE EJEMPLO':live
  ? searching
   ? 'Resultados de búsqueda · todos sus servidores reportados'
   : 'Todas las especies admitidas · todos sus servidores reportados'
  : `Mostrando ${items.length} de ${totalCount} reportes · registro del radar`;
 $('loadMoreBtn').classList.toggle('hidden',!hasMore||view==='top');
 $('feedRows').classList.add('radar-grid');
 const expanded=new Set([...$('feedRows').querySelectorAll('details[open]')].map(el=>el.dataset.group));
 $('feedRows').innerHTML=cards.length?cards.map(([key,entries])=>{
  if(live)entries.sort(compareIncome);
  const first=entries.find(item=>item.data_status!=='YA_NO_VISTO')||entries[0];
  const rowEntries=live?[...entries].sort(compareRadar):entries;
  const species=speciesOf(first);
  const art=radarArt.get(species);
  const pet=radarPets.get(species);
  const thumb=art?`<span class="radar-art radar-art-${art}" aria-hidden="true"></span>`:'<svg class="radar-egg-icon" width="37" height="37" viewBox="0 0 36 36" aria-hidden="true"><path d="M18 3C12 3 6 14 6 22a12 12 0 0 0 24 0C30 14 24 3 18 3Z" fill="none" stroke="currentColor" stroke-width="2"/><path d="m8 21 7-4 5 4 7-5" fill="none" stroke="currentColor" stroke-width="2"/></svg>';
  const petThumb=pet?`<span class="radar-pet-art radar-pet-${pet}" role="img" aria-label="Mascota ${esc(first.egg_name)}"></span>`:thumb;
  const eggBadge=pet&&art?`<span class="radar-egg-badge radar-art-${art}" role="img" aria-label="Huevo de ${esc(first.egg_name)}" title="Huevo de ${esc(first.egg_name)}"></span>`:'';
  const serverCount=new Set(entries.map(item=>item.server_id).filter(Boolean)).size;
  const bestIncome=entries.reduce((best,item)=>item.income_per_second!=null&&Number(item.income_per_second)>best?Number(item.income_per_second):best,-1);
  const bestWeight=rowEntries.reduce((best,item)=>item.data_status==='YA_NO_VISTO'||item.weight_kg==null?best:Math.max(best,Number(item.weight_kg)),0);
  const availableRows=entries.filter(item=>item.data_status!=='YA_NO_VISTO');
  const summaryRows=availableRows.length?availableRows:entries;
  const bestMultiplier=summaryRows.reduce((best,item)=>item.multiplier!=null&&Number(item.multiplier)>best?Number(item.multiplier):best,null);
  const rows=rowEntries.map(item=>{
   const known=item.income_per_second!=null;
   const kind=String(item.income_type||'').toUpperCase();
   const incomeLabel=!known?'Sin dato':kind==='DIRECTO'?'Directo declarado':kind==='ESTIMADO'?'Estimado':'Origen no verificado';
   const absent=item.data_status==='YA_NO_VISTO';
   const receivedAt=Number(absent?item.checked_at:item.updated_at);
   const time=receivedAt>0?`<time data-received-at="${receivedAt}" title="${esc(prettyDate(receivedAt))}">${elapsedReportTime(receivedAt)}</time>`:'Hora sin dato';
   const weight=item.weight_kg==null?'':` · ${esc(radarWeightFormat.format(item.weight_kg))} kg`;
   const mutation=keyOf(item.mutation);
   const mutationTag=({golden:'GLD',gold:'GLD',silver:'SLV',rainbow:'RBW'})[mutation];
   const multiplier=formatMultiplier(item.multiplier);
   const rowMultiplier=`<strong${multiplier==='× —'?' class="pv-no-multiplier" title="El escáner aún no reportó el multiplicador"':' title="Multiplicador de tamaño"'}>${esc(multiplier)}</strong>`;
   const percent=Math.max(0,Math.min(100,100*Number(item.income_per_second)/Math.max(bestIncome,1)));
   return `<div class="radar-report${absent?' radar-report-absent':''}${item===first?' pv-leader':''}" style="--rank:${percent}%" title="${esc(statusFor(item))}">
    <div><div class="radar-value">${rowMultiplier}<span class="pv-income">${esc(dollars(item.income_per_second))}</span>
    ${mutationTag?`<span class="pv-mutation" data-mut="${esc(mutation)}">${mutationTag}</span>`:''}
    ${absent?'<span class="pv-stolen" title="Reportado ausente por el escáner">ROBADO</span>':''}</div>
    <small>◷ ${absent?'Detectado como robado ':''}${time} · ${esc(incomeLabel)}${weight}</small></div>
    ${absent?'<span class="radar-old">Ya no está en el servidor</span>':joinControl(item)}</div>`;
  });
  const more=!live&&rows.length>2?`<details data-group="${esc(key)}" ${expanded.has(key)?'open':''}><summary>Ver ${rows.length-2} reportes más</summary>${rows.slice(2).join('')}</details>`:'';
  return `<article class="radar-card" style="--zone:${zoneColor(first.biome)};--rarity:${rarityColor(first.rarity)}">
   <div class="radar-zone">● ${esc(first.biome||'Bioma sin dato')}</div>
   <div class="radar-title">
    <div class="radar-thumb">${petThumb}${eggBadge}</div>
    <div><h2>${esc(first.egg_name)}</h2><p class="radar-count"><span class="rarity-tag ${esc(first.rarity)}">${esc(first.rarity||'Rareza sin dato')}</span> · ${serverCount} ${serverCount===1?'servidor':'servidores'}${live?' con detección':''}</p></div>
    <div class="radar-best">
     <small>Mayor multiplicador</small><strong title="Multiplicador de tamaño">${esc(formatMultiplier(bestMultiplier))}</strong>
     ${bestWeight>0?`<span class="pv-max-weight">Mayor peso · ${esc(radarWeightFormat.format(bestWeight))} kg</span>`:''}
     ${bestIncome>=0?`<span>Mayor generación · ${esc(dollars(bestIncome))}</span>`:''}
    </div>
   </div>${live?`<div class="pv-variants" data-group="${esc(key)}" aria-label="Variantes de ${esc(first.egg_name)}">${rows.join('')}</div>`:rows.slice(0,2).join('')+more}
  </article>`;
 }).join(''):live&&!searching?`<div class="pv-scanning"><strong>Buscando huevos…</strong><time id="pvScanningTime">${esc($('radarReload').textContent)}</time><small>hasta el próximo reset</small></div>`:'<div class="empty">No hay coincidencias en los reportes cargados.</div>';
}
function showLogs(){let lines=['[PVFINDER] '+new Date().toLocaleString('es-MX'),demo?'[DEMO] NO conectado al servidor real.':'[OK] Sesión autorizada.','[INFO] Huevos detectados recientemente: '+items.length,'[INFO] Cosmic: '+items.filter(x=>x.rarity==='Cosmic').length,'[INFO] Secret: '+items.filter(x=>x.rarity==='Secret').length,'[INFO] Eternal: '+items.filter(x=>x.rarity==='Eternal').length,'[INFO] Divine: '+items.filter(x=>x.rarity==='Divine').length,'[INFO] Última actualización: '+(lastChange||'N/D'),'','--- EJEMPLARES ---'];for(let i of items)lines.push(`${i.egg_name} | ${i.rarity} | ${i.biome||'N/D'} | ${dollars(i.income_per_second)} | ${i.income_type} | PlaceId ${i.place_id??'N/D'} | JobId ${i.server_id} | ${i.egg_id} | ESTADO ${statusFor(i)} | RECIBIDO EN PVFINDER ${prettyDate(i.updated_at)}`);$('logOutput').textContent=lines.join('\n');}
function copy(txt){navigator.clipboard?.writeText(txt).then(()=>toast('Copiado al portapapeles')).catch(()=>manualCopy(txt))||manualCopy(txt);}
function manualCopy(txt){let t=document.createElement('textarea');t.value=txt;t.style.cssText='position:fixed;left:-9999px';document.body.append(t);t.select();let ok=document.execCommand('copy');t.remove();toast(ok?'Copiado':'Selecciona el texto manualmente');}
async function loadAdmin(){if(role!=='admin'){viewMode('feed');return;}try{adminData=await api('/api/admin/overview');drawAdmin();}catch(e){toast(e.message);}}
function drawAdmin(){if(!adminData)return;document.querySelectorAll('[data-admin]').forEach(x=>x.classList.toggle('active',x.dataset.admin===adminView));const body=$('adminBody');if(adminView==='links'){
 body.innerHTML=`<p class="admin-help">Genera enlaces privados. El token aparece solamente una vez. Revocar un enlace también invalida las sesiones que creó.</p><div class="field-row"><div class="field"><label>Nombre del acceso</label><input id="linkLabel" placeholder="Cliente 01" maxlength="60"></div><div class="field"><label>Vencimiento</label><select id="linkHours"><option value="24">24 horas</option><option value="1">1 hora</option><option value="168">7 días</option><option value="720">30 días</option><option value="0">Sin vencimiento</option></select></div><div class="field"><label>Máximo de usos</label><input id="linkUses" type="number" min="1" max="100000" placeholder="Sin límite"></div><button class="primary" id="createLink">+ GENERAR URL</button></div><div class="admin-result" id="linkResult"></div><div class="admin-list">${adminData.links.length?adminData.links.map(l=>`<div class="admin-record"><div><strong>${esc(l.label)}</strong><small>${l.revoked_at?'REVO CADO':l.expires_at&&l.expires_at<Date.now()/1000?'VENCIDO':'ACTIVO'} · Usos: ${l.uses}${l.max_uses?'/'+l.max_uses:''} · ${esc(prettyDate(l.created_at))}</small></div>${l.revoked_at?'':'<button class="danger" data-revlink="'+esc(l.id)+'">REVOCAR</button>'}</div>`).join(''):'<div class="empty">Todavía no hay enlaces generados.</div>'}</div>`;
 $('createLink').onclick=async()=>{try{let h=Number($('linkHours').value);let use=$('linkUses').value;const r=await api('/api/admin/links',{label:$('linkLabel').value,expires_hours:h===0?null:h,max_uses:use?Number(use):null});await loadAdmin();let out=$('linkResult');if(out){out.classList.add('show');out.innerHTML=`<small>ENLACE GENERADO · COPIA AHORA</small><code>${esc(r.url)}</code><button class="secondary" id="copyNewLink">⧉ COPIAR URL</button>${demo?'<p class="admin-help">Este enlace es de ejemplo y no concede acceso real.</p>':''}`;$('copyNewLink').onclick=()=>copy(r.url);}}catch(e){toast(e.message);}};
 body.querySelectorAll('[data-revlink]').forEach(btn=>btn.onclick=async()=>{if(!confirm('¿Revocar acceso y sus sesiones?'))return;try{await api('/api/admin/links/revoke',{id:btn.dataset.revlink});toast('Enlace revocado');await loadAdmin();}catch(e){toast(e.message);}});
 }else if(adminView==='collectors'){
 body.innerHTML=`<p class="admin-help">Cada recolector recibe una credencial individual para enviar datos a la API. Una credencial no permite ver el panel privado.</p><div class="field-row"><div class="field"><label>Nombre del recolector</label><input id="collectorLabel" maxlength="60" placeholder="iPhone 01"></div><button class="primary" id="createCollector">+ CREAR RECOLECTOR</button></div><div class="admin-result" id="collectorResult"></div><div class="admin-list">${adminData.collectors.length?adminData.collectors.map(c=>`<div class="admin-record"><div><strong>${esc(c.label)}</strong><small>${c.revoked_at?'REVOCADO':'ACTIVO'} · Última señal: ${esc(prettyDate(c.last_seen))}</small></div>${c.revoked_at?'':`<button class="danger" data-revcollector="${esc(c.id)}">REVOCAR</button>`}</div>`).join(''):'<div class="empty">No hay recolectores activos.</div>'}</div>`;
 $('createCollector').onclick=async()=>{try{let r=await api('/api/admin/collectors',{label:$('collectorLabel').value});await loadAdmin();let out=$('collectorResult');if(out){out.classList.add('show');out.innerHTML=`<small>CREDENCIAL GENERADA · NO SE VOLVERÁ A MOSTRAR</small><code>${esc(r.credential)}</code><button class="secondary" id="copyNewCollector">⧉ COPIAR CREDENCIAL</button>${demo?'<p class="admin-help">Esta credencial es solo un ejemplo.</p>':''}`;$('copyNewCollector').onclick=()=>copy(r.credential);}}catch(e){toast(e.message);}};
 body.querySelectorAll('[data-revcollector]').forEach(btn=>btn.onclick=async()=>{if(!confirm('¿Desactivar este recolector?'))return;try{await api('/api/admin/collectors/revoke',{id:btn.dataset.revcollector});toast('Recolector revocado');await loadAdmin();}catch(e){toast(e.message);}});
 }else{
 body.innerHTML=`<p class="admin-help">Las detecciones sin rareza identificada se contabilizan por separado; los huevos con rareza conocida aparecen en el Live Feed.</p><div class="stats-grid"><div class="stat"><span>HUEVOS SIN CLASIFICAR</span><strong>${esc(adminData.unknown_count||0)}</strong><small>Datos recibidos recientemente</small></div><div class="stat"><span>RECOLECTORES</span><strong>${adminData.collectors.filter(x=>!x.revoked_at).length}</strong><small>Credenciales activas</small></div></div><pre class="diagnostic-pre">${esc((adminData.events||[]).map(e=>`${prettyDate(e.updated_at)} | ${e.egg_name} | ${e.rarity||'RAR_N/D'} | ${e.biome||'N/D'} | ${e.income_type} | ${e.server_id}`).join('\n')||'No hay detecciones registradas.')}</pre><button class="secondary" id="copyDiag">⧉ COPIAR RESULTADOS</button>`;
 $('copyDiag').onclick=()=>copy((adminData.events||[]).map(e=>JSON.stringify(e)).join('\n'));
 }}
async function init(){ setUpRadarReference(); $('redeemBtn').onclick=()=>redeem($('accessToken').value.trim());$('adminLoginBtn').onclick=login;$('adminPassword').onkeydown=e=>{if(e.key==='Enter')login();};$('accessToken').onkeydown=e=>{if(e.key==='Enter')redeem($('accessToken').value.trim());};
 document.querySelectorAll('[data-view]').forEach(n=>n.onclick=()=>viewMode(n.dataset.view));document.querySelectorAll('[data-admin]').forEach(n=>n.onclick=()=>{adminView=n.dataset.admin;drawAdmin();});$('refreshBtn').onclick=refresh;$('loadMoreBtn').onclick=loadMore;$('minIncomeFilter').onchange=render;
 $('logoutBtn').onclick=async()=>{await api('/api/logout',{});if(tick)clearInterval(tick);if(reloadTick)clearTimeout(reloadTick);
 if(clockTick)clearInterval(clockTick);location.href='/';};
 $('copyResultsBtn').onclick=()=>copy(shown().map(x=>`${x.egg_name} | ${x.rarity} | ${x.biome||'N/D'} | PlaceId ${x.place_id??'N/D'} | JobId ${x.server_id} | ${x.egg_id} | ${dollars(x.income_per_second)} | ${x.income_type} | ${x.weight_kg??'N/D'} kg | ${statusFor(x)} | Último reporte ${prettyDate(x.updated_at)}`).join('\n')||'Sin resultados');$('copyLogsBtn').onclick=()=>copy($('logOutput').textContent);
 function selectRadarMode(mode) {
  if(mode===radarMode)return;
  radarMode=mode;
  radarModeVersion++;
  lastLiveRender='';
  items=[];
  totalCount=0;
  nextOffset=0;
  hasMore=false;
  for(const [id,value] of [['radarLive','live'],['radarHistory','history']]){
   $(id).setAttribute('aria-pressed',String(mode===value));
  }
  render();
  $('feedRows').innerHTML='<div class="empty">Consultando reportes…</div>';
  refresh();
 }
 $('radarLive')?.addEventListener('click',()=>selectRadarMode('live'));
 $('radarHistory')?.addEventListener('click',()=>selectRadarMode('history'));
 $('radarSearch')?.addEventListener('input',render);
 const sortButtons=[...document.querySelectorAll('[data-radar-sort]')];
 for(const button of sortButtons)button.addEventListener('click',()=>{
  radarSort=button.dataset.radarSort;
  radarDirection=-1;
  for(const choice of sortButtons)choice.setAttribute('aria-pressed',String(choice===button));
  render();
 });
 $('radarRandom')?.addEventListener('click',()=>{
  const links=[...new Set([...$('feedRows').querySelectorAll('a.join-button')].map(link=>link.href))];
  if(!links.length){toast('No hay servidores disponibles en los reportes filtrados.');return;}
  window.open(links[Math.floor(Math.random()*links.length)],'_blank','noopener,noreferrer');
 });
 $('radarIncomeType')?.addEventListener('change',render);
 $('radarRarity')?.addEventListener('change',render);
 $('radarBiome')?.addEventListener('change',render);
 if(demo){enter('admin');return;}
 const hash=location.hash.match(/^#\/acceso\/([a-zA-Z0-9_\-]{32,})$/);
 if(hash){
  try{await redeem(hash[1]);}
  finally{
   history.replaceState(null,'','/');
   if(!role)showAccess();
  }
  return;
 }
 try{
  const session=await api('/api/me',undefined,AbortSignal.timeout?.(8000));
  if(session.authenticated)enter(session.role,session.persistent);
  else showAccess();
 }catch{
  showAccess();
  fail('No se pudo comprobar la sesión. Intenta entrar de nuevo.');
 }
}
init();
})();

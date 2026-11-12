/* Visual co-owner content editor. Uses allowlisted backend fields only. */
(() => {
'use strict';
const $ = id => document.getElementById(id);
const GROUPS = [
  ['🎨 Marca y colores', [
    ['brand_name','Nombre visible','text',42],
    ['site_announcement','Aviso destacado (aparece en ambas páginas)','textarea',180],
    ['theme_primary','Color principal','color'],
    ['theme_secondary','Color secundario','color'],
    ['theme_background','Fondo de Live Feed','color'],
    ['theme_sales_background','Fondo de ventas','color']
  ]],
  ['🏠 Portada y acceso', [
    ['home_access_tag','Etiqueta de acceso','text',55],
    ['home_title_first','Título: primera línea','text',85],
    ['home_title_second','Título: segunda línea','text',85],
    ['home_description','Descripción','textarea',320],
    ['home_access_button','Texto del botón de acceso','text',65],
    ['home_side_tag','Etiqueta de portada derecha','text',65],
    ['home_side_first','Portada: línea 1','text',70],
    ['home_side_second','Portada: línea 2','text',70],
    ['home_side_third','Portada: línea 3','text',70],
    ['home_side_description','Descripción derecha','textarea',320],
    ['home_side_status','Estado de portada','text',100],
    ['home_live_tag','Etiqueta del feed','text',90],
    ['home_live_caption','Descripción del feed','textarea',240],
    ['home_footer_text','Pie de la página principal','text',90]
  ]],
  ['🛒 Página de ventas', [
    ['sales_page_tag','Etiqueta de la página de ventas','text',85],
    ['sales_eyebrow','Texto encima del título','text',110],
    ['sales_title_first','Título de ventas: primera parte','text',100],
    ['sales_title_second','Título destacado','text',100],
    ['sales_intro','Introducción','textarea',700],
    ['sales_feature_one','Beneficio 1','text',90],
    ['sales_feature_two','Beneficio 2','text',90],
    ['sales_feature_three','Beneficio 3','text',90],
    ['sales_feature_four','Beneficio 4','text',90],
    ['sales_plans_title','Título de planes','text',100],
    ['sales_plans_hint','Descripción de planes','textarea',280],
    ['sales_button_label','Texto del botón de compra','text',65],
    ['sales_featured_tag','Etiqueta del plan destacado','text',38],
    ['sales_contact_title','Título de contacto','text',140],
    ['sales_contact_text','Descripción de contacto','textarea',450],
    ['sales_contact_button','Botón de Discord','text',65],
    ['sales_discord_link','Enlace de Discord','url',250],
    ['sales_footer_text','Pie de página de ventas','text',180],
    ['sales_extra_title','Sección adicional: título (opcional)','text',140],
    ['sales_extra_text','Sección adicional: contenido (opcional)','textarea',700]
  ]],
  ['💲 Planes y precios en USD', [
    ['plan_three_name','Plan de 3 días: nombre','text',60],
    ['plan_three_description','Plan de 3 días: descripción','textarea',250],
    ['plan_three_price','Plan de 3 días: precio','number'],
    ['plan_weekly_name','Plan semanal: nombre','text',60],
    ['plan_weekly_description','Plan semanal: descripción','textarea',250],
    ['plan_weekly_price','Plan semanal: precio','number'],
    ['plan_biweekly_name','Plan de 2 semanas: nombre','text',60],
    ['plan_biweekly_description','Plan de 2 semanas: descripción','textarea',250],
    ['plan_biweekly_price','Plan de 2 semanas: precio','number'],
    ['plan_monthly_name','Plan mensual: nombre','text',60],
    ['plan_monthly_description','Plan mensual: descripción','textarea',250],
    ['plan_monthly_price','Plan mensual: precio','number']
  ]]
];
const inputs = Object.create(null);
let initial = Object.create(null);
let currentRole = 'coowner';
let loading = false;
async function call(path, body) {
  const r = await fetch(path, {
    method:body?'POST':'GET', credentials:'same-origin', cache:'no-store',
    headers:body?{'Content-Type':'application/json'}:{},
    body:body?JSON.stringify(body):undefined
  });
  const json = await r.json().catch(()=>({error:'Respuesta inválida'}));
  if (!r.ok) throw new Error(json.error || 'HTTP ' + r.status);
  return json;
}
function state(t,err=false) {
  const el=$('siteStatus');
  if (el) {el.textContent=t;el.style.color=err?'#ffc2c2':'#9cefcf';}
}
function changes() {
  const patch={};
  for (const [key,input] of Object.entries(inputs)) {
    const original=initial[key];
    let value=input.value;
    if (input.type==='number') value=value.trim()?Number(value):NaN;
    if (value !== original) patch[key]=value;
  }
  return patch;
}
function changedMessage() {
  if (loading) return;
  const count=Object.keys(changes()).length;
  state(count?'⚠️ '+count+' cambio(s) sin guardar':'Sin cambios pendientes.');
}
function draw() {
  const root=$('siteFields');
  if (!root || root.childElementCount) return;
  for (const [heading, fields] of GROUPS) {
    const group=document.createElement('details');
    group.className='site-group';
    group.open = heading.startsWith('🎨');
    const summary=document.createElement('summary');
    summary.textContent=heading;
    group.appendChild(summary);
    const grid=document.createElement('div');
    grid.className='grid site-fields-grid';
    for (const [key,label,kind,max] of fields) {
      const wrap=document.createElement('div');
      wrap.className=kind==='textarea'?'site-field site-wide':'site-field';
      const labelEl=document.createElement('label');
      labelEl.textContent=label;
      labelEl.htmlFor='site_'+key;
      let input;
      if (kind==='textarea') {
        input=document.createElement('textarea');
        input.rows=3;
      } else {
        input=document.createElement('input');
        input.type=kind;
      }
      input.id='site_'+key;
      if (max) input.maxLength=max;
      if (kind==='number') {input.min='1';input.max='999.99';input.step='0.01';}
      if (kind==='url') input.placeholder='https://discord.com/...';
      input.addEventListener('input',changedMessage);
      inputs[key]=input;
      wrap.append(labelEl,input);
      grid.append(wrap);
    }
    group.append(grid);
    root.append(group);
  }
}
function fill(data) {
  initial=data.values || {};
  loading=true;
  for (const [key,input] of Object.entries(inputs)) {
    if (initial[key] !== undefined) input.value=String(initial[key]);
  }
  loading=false;
  state('Ajustes cargados. Edita y pulsa Guardar cambios.');
}
async function load() {
  try {fill(await call('/api/editor/site'));}
  catch(e) {state('No se pudieron cargar los ajustes: '+e.message,true);}
}
async function save() {
  const patch=changes();
  if (!Object.keys(patch).length) return state('No hay cambios para guardar.');
  const btn=$('saveSite');
  btn.disabled=true;
  state('Guardando cambios...');
  try {
    const fresh=await call('/api/editor/site',{action:'save',values:patch});
    fill(fresh);
    state('✅ Cambios publicados en la página.');
    if (currentRole==='admin') history();
  } catch(e) {state('No se pudo guardar: '+e.message,true);}
  finally {btn.disabled=false;}
}
async function restore() {
  if (!confirm('¿Restaurar todos los textos, colores y precios originales? Las imágenes y llaves NO se borrarán.'))return;
  try {
    const fresh=await call('/api/editor/site',{action:'reset'});
    fill(fresh);
    state('✅ Página restaurada a sus valores originales.');
    history();
  } catch(e) {state('Error: '+e.message,true);}
}
async function history() {
  try {
    const data=await call('/api/editor/site/history');
    const root=$('siteHistory');
    if (!root) return;
    root.replaceChildren();
    for (const item of (data.edits||[]).slice(0,15)) {
      const p=document.createElement('p');
      p.className='site-edit-history';
      p.textContent=new Date(item.updated_at*1000).toLocaleString('es-MX')+' · '+item.actor+' · '+item.changed_keys;
      root.append(p);
    }
    if (!root.childElementCount) root.textContent='Sin cambios registrados.';
  } catch (_) {}
}
window.loadSiteEditor=function(role) {
  currentRole=role;
  draw();
  const tools=$('siteOwnerTools');
  if (tools) tools.classList.toggle('hidden',role!=='admin');
  load();
  if (role==='admin') history();
};
$('saveSite')?.addEventListener('click',save);
$('restoreSite')?.addEventListener('click',restore);
$('reloadSite')?.addEventListener('click',()=>{
  if (Object.keys(changes()).length && !confirm('¿Descartar cambios sin guardar?'))return;
  load();
});
window.addEventListener('beforeunload',e=>{
  if (Object.keys(changes()).length) {e.preventDefault();e.returnValue='';}
});
})();

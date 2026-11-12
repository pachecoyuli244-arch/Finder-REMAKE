(() => {
'use strict';
fetch('/api/branding/meta',{cache:'no-store'}).then(r=>r.ok?r.json():null).then(data=>{
if(!data||!data.images)return;
const useOriginalLogo=String(data.images.logo)==='1794124830';
const useOriginalCover=String(data.images.hero)==='1794124830';
const img=(name,css)=>{let i=document.createElement('img');i.alt=name==='hero'?'Portada PVFINDER':'PVFINDER';i.src='/api/branding/'+name+'?v='+data.images[name];i.style.cssText=css;return i};
if(data.images.logo){
 const emblem=document.querySelector('.brandicon')||document.querySelector('header .brand span:first-child');
 if(emblem){emblem.textContent='';emblem.classList.toggle('pv-clean-brand',useOriginalLogo&&!!document.querySelector('.access-entry'));emblem.append(img('logo','display:block;width:100%;height:100%;object-fit:contain;border-radius:23%'))}
}
if(data.images.hero){
 const gate=document.querySelector('.access-entry');
 if(gate){
  if(!useOriginalCover)gate.style.setProperty('--access-cover','url("/api/branding/hero?v='+encodeURIComponent(data.images.hero)+'")');
  const symbol=gate.querySelector('.gate-symbol');
  if(symbol&&data.images.logo){symbol.classList.toggle('pv-clean-brand',useOriginalLogo);symbol.replaceChildren(img('logo','width:100%;height:100%;object-fit:contain'));}
  return;
 }
 const orbit=document.querySelector('.gate-side .orbit');
 if(orbit){orbit.replaceWith(img('hero','display:block;max-width:100%;width:470px;max-height:270px;object-fit:cover;border-radius:14px;margin-bottom:25px;border:1px solid #545786'))}
 else {const main=document.querySelector('main');if(main){const banner=img('hero','display:block;width:100%;max-height:300px;object-fit:cover;border-radius:14px;margin:8px 0 22px;border:1px solid #545786');main.prepend(banner)}}
}
}).catch(()=>{});
})();
'use strict';
// A separate web shell over the same authenticated application and data layer.
const generalWeb=!!document.body?.classList.contains('general-web');
const previewNavigation=navigation,previewRender=render;
const portalPages=[['dashboard','Resumen','dashboard'],['stations','Sucursales','stations'],['managers','Gerentes','managers'],['reports','Análisis de rendimiento','reports'],['fill','Llenar tanques','inventory'],['personnel','Personal','managers'],['workshifts','Turnos y horarios','cuts'],['products','Inventario comercial','inventory'],['pos','Punto de venta','money'],['services','Servicios','check'],['database','Conexión','stations'],['profile','Mi cuenta','profile']];
const portalGroups=[
 {id:'overview',label:'Panorama general',symbol:'dashboard',pages:['dashboard','reports']},
 {id:'administration',label:'Administración',symbol:'managers',pages:['stations','managers','personnel','workshifts']},
 {id:'operations',label:'Operación y ventas',symbol:'inventory',pages:['fill','products','pos','services']},
 {id:'account',label:'Cuenta y conexión',symbol:'profile',pages:['profile','database']}
];
let portalOpenGroup='overview',portalLastPage=null;
function portalSelected(page){return state.page===page||(page==='stations'&&state.page==='detail')||(page==='workshifts'&&['shiftEditor','shiftDetail'].includes(state.page));}
navigation=function(){
 if(!generalWeb)return previewNavigation();
 if(user()?.role!=='general')return '';
 const activeGroup=portalGroups.find(group=>group.pages.some(portalSelected));
 if(portalLastPage!==state.page){portalOpenGroup=activeGroup?.id||'overview';portalLastPage=state.page;}
 return `<div class="portal-nav"><p class="portal-nav-label">Gerente general</p>${portalGroups.map(group=>`<details class="portal-nav-group ${activeGroup?.id===group.id?'has-active-page':''}" name="portal-sidebar" data-portal-group="${group.id}" ${portalOpenGroup===group.id?'open':''}><summary>${icon(group.symbol)}<span>${group.label}</span><span class="portal-group-chevron" aria-hidden="true">›</span></summary><div class="portal-group-items">${group.pages.map(id=>portalPages.find(([page])=>page===id)).map(([page,label,symbol])=>`<button data-action="navigate" data-page="${page}" class="${portalSelected(page)?'active':''}" ${portalSelected(page)?'aria-current="page"':''}>${icon(symbol)}<span>${label}</span></button>`).join('')}</div></details>`).join('')}<button class="portal-logout" data-action="logout">${icon('back')}<span>Cerrar sesión</span></button></div>`;
};
render=function(keepScroll=false){
 if(!generalWeb){previewRender(keepScroll);return;}
 const rejected=user()&&user().role!=='general';
 if(rejected){state.userId=null;state.draft=null;state.page='dashboard';clearRemoteSession();}
 previewRender(keepScroll);
 const signedIn=user()?.role==='general';
 document.body.classList.toggle('portal-authenticated',signedIn);
 document.body.classList.remove('portal-menu-open');
 const menu=document.querySelector('#portal-menu');menu.hidden=!signedIn;menu.setAttribute('aria-expanded','false');
 document.querySelector('#app').dataset.portalPage=signedIn?state.page:'login';
 document.querySelector('#portal-account').innerHTML=signedIn?`<span>${esc(user().name)}</span><small>Gerente general</small>`:'<span>Acceso de gerente general</span>';
 if(!keepScroll&&typeof window.scrollTo==='function')window.scrollTo(0,0);
 if(rejected){const error=document.querySelector('#login-error');if(error)error.textContent='Esta página es exclusiva del gerente general. Para una cuenta de sucursal, utiliza la vista previa móvil.';}
};
document.addEventListener('click',event=>{
 if(!generalWeb||!event.target.closest('[data-portal-menu]'))return;
 const open=!document.body.classList.contains('portal-menu-open');document.body.classList.toggle('portal-menu-open',open);document.querySelector('#portal-menu').setAttribute('aria-expanded',String(open));
});
document.addEventListener('keydown',event=>{if(generalWeb&&event.key==='Escape'){document.body.classList.remove('portal-menu-open');document.querySelector('#portal-menu').setAttribute('aria-expanded','false');}});
// Native details/summary provides keyboard and screen-reader behavior.
// Capture toggle because it does not bubble; keep the chosen group across data refreshes.
document.addEventListener('toggle',event=>{
 const group=event.target;if(!generalWeb||!group.dataset?.portalGroup)return;
 if(group.open){portalOpenGroup=group.dataset.portalGroup;for(const other of document.querySelectorAll('[data-portal-group]'))if(other!==group)other.open=false;}
 else if(portalOpenGroup===group.dataset.portalGroup)portalOpenGroup=null;
},true);
render();

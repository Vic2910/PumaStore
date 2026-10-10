(function(root, factory) { if (typeof module === 'object' && module.exports) module.exports = factory(require('./domain.js')); else root.Operations = factory(root.Puma); })(typeof window !== 'undefined' ? window : this, function(P) {
'use strict';
const empty = () => ({employees:[],shifts:[],products:[],sales:[],services:[],records:[],receipts:[]});
const assert = (ok, message) => { if (!ok) throw Error(message); };
const stamp = () => new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');
const uuid = value => String(value).toLowerCase();
const total = sale => Math.round(sale.lines.reduce((n,l) => n+l.price*l.quantity,0)*100)/100;
function normalize(data) {
 const next=P.clone(data); next.operations={...empty(),...next.operations};
 // Upgrade known legacy capacities once; never clamp inventory silently.
 if(!next.tankCapacityMigrated){for(const s of next.stations)for(const t of s.tanks){assert(t.current<=10000,'Una existencia supera 10,000. Revisa la migración antes de cambiar capacidad.');t.capacity=10000;}next.tankCapacityMigrated=true;}
 return next;
}
function save(data,kind,item){
 const next=normalize(data), list=next.operations[kind];assert(list,'Módulo inexistente.');assert(next.stations.some(s=>uuid(s.id)===uuid(item.stationID)),'Sucursal inexistente.');
 item=P.clone(item);item.id=item.id||P.id();
 if(kind==='employees'){
  assert(item.name.trim()&&item.document.trim()&&item.phone.trim()&&item.position.trim(),'Completa nombre, documento, teléfono y cargo.');
  assert(!list.some(e=>e.id!==item.id&&e.document===item.document),'El documento ya existe.');
 }
 if(kind==='products'){
  assert(item.name.trim()&&item.sku.trim()&&Number.isFinite(item.price)&&item.price>=0&&Number.isFinite(item.cost)&&item.cost>=0&&Number.isInteger(item.stock)&&item.stock>=0&&Number.isInteger(item.minimum)&&item.minimum>=0,'Verifica identificación, precios y stock.');
  assert(!list.some(p=>p.id!==item.id&&p.stationID===item.stationID&&p.sku.toLowerCase()===item.sku.toLowerCase()),'SKU duplicado.');
 }
 if(kind==='services')assert(item.name.trim()&&Number.isFinite(item.price)&&item.price>=0,'Verifica nombre y precio.');
 if(kind==='shifts'){
  const previous=list.find(s=>s.id===item.id),changed=!previous||['employeeID','stationID','start','end'].some(k=>previous[k]!==item[k]);
  if(changed&&Number.isFinite(Date.parse(item.start)))assert(P.day(new Date(item.start))>=P.day(),'No puedes asignar turnos en una fecha pasada.');
  const existing=list.find(s=>s.id===item.id);assert(!existing||shiftStatus(existing)==='Programado','Solo puedes editar un turno Programado.');
  assert(next.operations.employees.some(e=>e.id===item.employeeID&&e.stationID===item.stationID&&e.active),'Selecciona un empleado activo de esta sucursal.');
  assert(Number.isFinite(Date.parse(item.start))&&Date.parse(item.end)>Date.parse(item.start),'El fin debe ser posterior al inicio.');
  const conflict=list.find(s=>s.id!==item.id&&!s.cancelled&&s.employeeID===item.employeeID&&Date.parse(s.start)<Date.parse(item.end)&&Date.parse(s.end)>Date.parse(item.start));
  assert(!conflict,'Conflicto de horarios'+(conflict?`: TUR-${conflict.id.slice(0,8)} · ${conflict.start} → ${conflict.end}. Cambia el horario o el empleado.`:'.'));
 }
 const index=list.findIndex(e=>e.id===item.id);if(index<0)list.push(item);else list[index]=item;return next;
}
function shiftStatus(shift){return shift.cancelled?'Cancelado':shift.clockOut?'Completado':shift.clockIn?'En curso':'Programado';}
function cancelShift(data,id){const next=normalize(data),s=next.operations.shifts.find(s=>s.id===id);assert(s&&shiftStatus(s)==='Programado','Solo puedes cancelar un turno Programado.');s.cancelled=true;return next;}
function clock(data,id){const next=normalize(data),s=next.operations.shifts.find(s=>s.id===id);assert(s&&!s.clockOut&&!s.cancelled,'Turno cerrado.');assert(next.operations.employees.some(e=>e.id===s.employeeID&&e.active),'Empleado inactivo.');if(!s.clockIn)s.clockIn=stamp();else s.clockOut=stamp();return next;}
function sell(data,stationID,cart,cashier,payment,received){
 const next=normalize(data);assert(Object.keys(cart).length,'Agrega productos.');const lines=[];
 for(const [id,quantity] of Object.entries(cart)){const p=next.operations.products.find(p=>p.id===id&&p.stationID===stationID&&p.active);assert(p&&Number.isInteger(quantity)&&quantity>0&&p.stock>=quantity,'Existencias insuficientes.');lines.push({productID:id,name:p.name,sku:p.sku,price:p.price,quantity});p.stock-=quantity;}
 const sale={id:P.id(),stationID,date:stamp(),cashier,lines,payment,received};assert(Number.isFinite(received)&&received>=total(sale),'Pago insuficiente.');next.operations.sales.push(sale);return next;
}
function record(data,fields){const next=normalize(data),s=next.operations.services.find(s=>s.id===fields.serviceID&&s.stationID===fields.stationID&&s.available);assert(s,'Servicio no disponible.');assert(next.operations.employees.some(e=>e.id===fields.employeeID&&e.stationID===fields.stationID&&e.active),'Empleado inactivo.');next.operations.records.push({...fields,id:P.id(),name:s.name,price:s.price,date:stamp(),status:'Pendiente'});return next;}
function transition(data,id,status){const next=normalize(data),r=next.operations.records.find(r=>r.id===id);assert(r&&['Pendiente','En proceso'].includes(r.status)&&['En proceso','Completado','Cancelado'].includes(status),'El servicio ya terminó.');r.status=status;return next;}
function fill(data,stationID,fuel,volume,cost,supplier){const next=normalize(data),s=next.stations.find(s=>s.id===stationID),t=s?.tanks.find(t=>t.fuel===fuel);assert(t&&Number.isFinite(volume)&&volume>0&&Number.isFinite(cost)&&cost>=0&&supplier.trim()&&t.current+volume<=t.capacity,'Verifica cantidad, proveedor y capacidad.');t.current+=volume;s.receipts=s.receipts||[];s.receipts.push({id:P.id(),stationID,date:stamp(),fuel,volume,cost,supplier});return next;}
function manager(data,id,active){let next=P.assign(data,id,null);const u=next.users.find(u=>u.id===id&&u.role==='branch');assert(u,'Gerente inexistente.');u.active=active;return next;}
function deleteManager(data,id){assert(data.users.some(u=>u.id===id&&u.role==='branch'),'Solo puedes eliminar gerentes de sucursal.');const next=P.assign(data,id,null);next.users=next.users.filter(u=>u.id!==id);return next;}
function performance(data,stations,days,category='all',endDay=P.day()){
 assert(Number.isInteger(days)&&days>0&&days<=365,'Período inválido.');
 assert(['all','fuel','products','services'].includes(category),'Actividad inválida.');
 const ids=new Set(stations.map(s=>uuid(s.id))),ops={...empty(),...data.operations};
 const end=new Date(endDay+'T12:00:00Z'),points=[];
 for(let offset=days-1;offset>=0;offset--){const date=new Date(end);date.setUTCDate(date.getUTCDate()-offset);points.push({date:date.toISOString().slice(0,10),fuel:0,products:0,services:0,volume:0,losses:0,units:0,completed:0,pending:0,cancelled:0});}
 const byDay=new Map(points.map(p=>[p.date,p])),fuelSales=Object.fromEntries(P.fuels.map(f=>[f,0])),productSales=new Map(),serviceSales=new Map();
 const pointFor=iso=>{const date=new Date(iso);return Number.isFinite(date.getTime())?byDay.get(P.day(date)):undefined;};
 for(const s of stations)for(const c of s.cuts||[]){const p=byDay.get(c.date);if(!p||!c.closed)continue;const t=P.totals(c);p.fuel+=t.sales;p.volume+=t.volume;p.losses+=t.losses;for(const pump of c.pumps)fuelSales[pump.fuel]=(fuelSales[pump.fuel]||0)+pump.amount;}
 for(const sale of ops.sales){if(!ids.has(uuid(sale.stationID)))continue;const p=pointFor(sale.date);if(!p)continue;p.products+=total(sale);for(const l of sale.lines){p.units+=l.quantity;const key=uuid(l.productID),row=productSales.get(key)||{id:key,name:l.name,units:0,revenue:0};row.units+=l.quantity;row.revenue+=l.price*l.quantity;productSales.set(key,row);}}
 for(const r of ops.records){if(!ids.has(uuid(r.stationID)))continue;const p=pointFor(r.date);if(!p)continue;if(r.status==='Completado'){p.services+=r.price;p.completed++;const key=uuid(r.serviceID),row=serviceSales.get(key)||{id:key,name:r.name,count:0,revenue:0};row.count++;row.revenue+=r.price;serviceSales.set(key,row);}else if(r.status==='Pendiente'||r.status==='En proceso')p.pending++;else if(r.status==='Cancelado')p.cancelled++;}
 const round=n=>Math.round((n+Number.EPSILON)*100)/100;
 for(const p of points){for(const key of ['fuel','products','services'])p[key]=round(p[key]);p.total=round(p.fuel+p.products+p.services);p.sales=category==='all'?p.total:p[category];}
 const summary=Object.fromEntries(['fuel','products','services','total','sales','volume','losses','units','completed','pending','cancelled'].map(k=>[k,round(points.reduce((n,p)=>n+p[k],0))]));
 return {points,summary,fuelSales,products:[...productSales.values()].sort((a,b)=>b.revenue-a.revenue),services:[...serviceSales.values()].sort((a,b)=>b.revenue-a.revenue)};
}
function performanceCSV(report){return 'Fecha,Combustible USD,Productos USD,Servicios completados USD,Ingresos totales USD,Ingresos actividad seleccionada USD,Galones vendidos,Perdidas gal,Unidades productos,Servicios completados,Servicios pendientes,Servicios cancelados\n'+report.points.map(p=>[p.date,p.fuel.toFixed(2),p.products.toFixed(2),p.services.toFixed(2),p.total.toFixed(2),p.sales.toFixed(2),p.volume,p.losses,p.units,p.completed,p.pending,p.cancelled].join(',')).join('\n');}
return {empty,normalize,save,clock,sell,record,transition,fill,manager,deleteManager,total,stamp,shiftStatus,cancelShift,performance,performanceCSV};
});

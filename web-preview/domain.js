(function(root,factory){if(typeof module==='object'&&module.exports)module.exports=factory();else root.Puma=factory();})(typeof window!=='undefined'?window:this,function(){
'use strict';
const fuels=['Súper','Regular','Diésel'];
const shifts=['matutino','vespertino'];
const prices={'Súper':4.10,'Regular':3.95,'Diésel':3.75};
const clone=o=>JSON.parse(JSON.stringify(o));
const id=()=>typeof crypto!=='undefined'&&crypto.randomUUID?crypto.randomUUID():`id-${Date.now()}-${Math.random().toString(36).slice(2)}`;
const day=(date=new Date())=>new Intl.DateTimeFormat('en-CA',{timeZone:'America/El_Salvador',year:'numeric',month:'2-digit',day:'2-digit'}).format(date);
const fuelFor=n=>n<=2?fuels[0]:n<=4?fuels[1]:fuels[2];
const blankCut=(shift,date=day())=>({id:id(),date,shift,pumps:Array.from({length:6},(_,i)=>({number:i+1,fuel:fuelFor(i+1),volume:0,amount:0,complete:false})),purchases:[],losses:[],closed:false});
const sum=(items,key)=>items.reduce((total,item)=>total+item[key],0);
const totals=cut=>({sales:sum(cut.pumps,'amount'),volume:sum(cut.pumps,'volume'),purchases:sum(cut.purchases,'cost'),losses:sum(cut.losses,'volume')});
const level=tank=>tank.capacity>0?Math.max(0,Math.min(1,tank.current/tank.capacity)):0;
const status=tank=>level(tank)<.25?'Crítico':level(tank)<.6?'Medio':'Óptimo';
const statusClass=tank=>level(tank)<.25?'critical':level(tank)<.6?'medium':'optimal';
function seed(){
 const morning=()=>{const cut=blankCut('matutino');cut.pumps.forEach(p=>{p.volume=80+p.number*17;p.amount=p.volume*prices[p.fuel];p.complete=true;});cut.closed=true;return cut;};
 const santa=morning();santa.purchases=[{id:id(),fuel:'Diésel',volume:1000,cost:3950,supplier:'RECOPE'}];santa.losses=[{id:id(),fuel:'Regular',volume:5,reason:'Derrame menor en manguera'}];
 return {version:1,stations:[
 {id:'santa',name:'PUMA Santa Ana Centro',city:'Santa Ana',address:'Av. Independencia Sur',manager:'Abigail Rivera',tanks:fuels.map((fuel,i)=>({fuel,capacity:10000,current:[7200,4500,1800][i]})),cuts:[santa,blankCut('vespertino')]},
 {id:'salvador',name:'PUMA San Salvador Norte',city:'San Salvador',address:'Bulevar Constitución',manager:'Ana Rivas',tanks:fuels.map((fuel,i)=>({fuel,capacity:10000,current:[9000,7800,6600][i]})),cuts:[morning()]},
 {id:'sonsonate',name:'PUMA Sonsonate Km 65',city:'Sonsonate',address:'Carretera CA-8',manager:'José Portillo',tanks:fuels.map((fuel,i)=>({fuel,capacity:10000,current:[2000,4700,4500][i]})),cuts:[blankCut('matutino')]}
 ],users:[
 {id:'general',name:'Gabriela Díaz',username:'gerente.general',password:'1234',role:'general',stationId:null},
 {id:'abigail',name:'Abigail Rivera',username:'santa.ana',password:'1234',role:'branch',stationId:'santa'},
 {id:'ana',name:'Ana Rivas',username:'san.salvador',password:'1234',role:'branch',stationId:'salvador'},
 {id:'jose',name:'José Portillo',username:'sonsonate',password:'1234',role:'branch',stationId:'sonsonate'}]};
}
function assert(condition,message){if(!condition)throw new Error(message);}
function validNumber(value,positive=false){return typeof value==='number'&&Number.isFinite(value)&&(positive?value>0:value>=0);}
function validateCut(cut){
 assert(shifts.includes(cut.shift),'Turno inválido.');
 assert(/^\d{4}-\d{2}-\d{2}$/.test(cut.date),'Fecha inválida.');
 assert([3,6].includes(cut.pumps.length)&&new Set(cut.pumps.map(p=>p.number)).size===cut.pumps.length&&cut.pumps.every(p=>Number.isInteger(p.number)&&p.number>=1&&p.number<=cut.pumps.length),'El corte requiere tres controles o seis registros históricos, sin duplicados.');
 assert(cut.pumps.every(p=>p.fuel===(cut.pumps.length===3?fuels[p.number-1]:fuelFor(p.number))&&validNumber(p.volume)&&validNumber(p.amount)),'Verifica los valores y el combustible de los registros.');
 assert(cut.purchases.every(p=>fuels.includes(p.fuel)&&validNumber(p.volume,true)&&validNumber(p.cost)&&p.supplier.trim()),'Las compras requieren cantidad positiva, costo válido y proveedor.');
 assert(cut.losses.every(p=>fuels.includes(p.fuel)&&validNumber(p.volume,true)&&p.reason.trim()),'Las pérdidas requieren cantidad positiva y motivo.');
 if(cut.closed)assert(cut.pumps.every(p=>p.complete),'Debes registrar las seis bombas antes de cerrar el corte.');
}
function saveCut(data,stationId,draft,close=false){
 const next=clone(data);const station=next.stations.find(s=>s.id===stationId);assert(station,'Sucursal inexistente.');
 const cut=clone(draft);cut.closed=close;
 const existing=station.cuts.find(c=>c.id===cut.id);assert(!existing||!existing.closed,'Este corte ya está cerrado y no puede modificarse.');
 assert(!station.cuts.some(c=>c.id!==cut.id&&c.date===cut.date&&c.shift===cut.shift),'Ya existe este turno para la fecha seleccionada.');
 validateCut(cut);
 if(close)for(const fuel of fuels){
  const tank=station.tanks.find(t=>t.fuel===fuel);assert(tank,'Falta un tanque de combustible.');
  const remaining=tank.current+sum(cut.purchases.filter(p=>p.fuel===fuel),'volume')-sum(cut.pumps.filter(p=>p.fuel===fuel),'volume')-sum(cut.losses.filter(p=>p.fuel===fuel),'volume');
  assert(validNumber(remaining)&&remaining<=tank.capacity,`El movimiento de ${fuel} excede el inventario o la capacidad del tanque.`);tank.current=remaining;
 }
 const index=station.cuts.findIndex(c=>c.id===cut.id);if(index<0)station.cuts.push(cut);else station.cuts[index]=cut;
 return next;
}
function aggregate(stations,date=day()){
 const cuts=stations.flatMap(s=>s.cuts).filter(c=>c.closed&&(!date||c.date===date));
 const values=cuts.map(totals),receipts=stations.flatMap(s=>s.receipts||[]).filter(r=>!date||day(new Date(r.date))===date);return {sales:sum(values,'sales'),volume:sum(values,'volume'),purchases:sum(values,'purchases')+sum(receipts,'cost'),losses:sum(values,'losses')};
}
function globalTanks(stations){return fuels.map(fuel=>({fuel,current:sum(stations.flatMap(s=>s.tanks).filter(t=>t.fuel===fuel),'current'),capacity:sum(stations.flatMap(s=>s.tanks).filter(t=>t.fuel===fuel),'capacity')}));}
function assign(data,userId,stationId){
 const next=clone(data),user=next.users.find(u=>u.id===userId&&u.role==='branch');assert(user,'Gerente inexistente.');
 assert(!stationId||next.stations.some(s=>s.id===stationId),'Sucursal inexistente.');
 const previous=next.stations.find(s=>s.id===user.stationId);if(previous)previous.manager='Sin asignar';
 if(stationId){next.users.forEach(u=>{if(u.id!==userId&&u.stationId===stationId)u.stationId=null;});next.stations.find(s=>s.id===stationId).manager=user.name;}
 user.stationId=stationId||null;return next;
}
function addStation(data,fields){
 assert(fields.name.trim()&&fields.city.trim()&&fields.address.trim(),'Completa nombre, dirección y ciudad.');
 const next=clone(data);next.stations.push({id:id(),name:fields.name.trim(),city:fields.city.trim(),address:fields.address.trim(),manager:'Sin asignar',tanks:fuels.map(fuel=>({fuel,capacity:10000,current:0})),cuts:[]});return next;
}
function addManager(data,fields){
 assert(fields.name.trim()&&fields.username.trim()&&fields.password.length>=4,'Completa los datos y una contraseña de al menos 4 caracteres.');
 assert(!data.users.some(u=>u.username.toLowerCase()===fields.username.trim().toLowerCase()),'Este usuario ya existe.');
 const next=clone(data),user={id:id(),name:fields.name.trim(),username:fields.username.trim(),password:fields.password,role:'branch',stationId:null};next.users.push(user);
 return assign(next,user.id,fields.stationId);
}
function report(stations,days){
 const today=day();const end=new Date(today+'T12:00:00Z');const points=[];
 for(let i=days-1;i>=0;i--){const date=new Date(end);date.setUTCDate(date.getUTCDate()-i);const stamp=date.toISOString().slice(0,10);points.push({date:stamp,...aggregate(stations,stamp)});}
 return points;
}
return {fuels,shifts,prices,clone,id,day,fuelFor,blankCut,totals,level,status,statusClass,seed,validateCut,saveCut,aggregate,globalTanks,assign,addStation,addManager,report};
});

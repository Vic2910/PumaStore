'use strict';
const test=require('node:test'),assert=require('node:assert/strict');
const P=require('./domain.js'),O=require('./operations.js');
function fixture(){return O.normalize(P.seed());}
test('ventas de despacho en vivo no se duplican al generar el corte de tres controles',()=>{
 const d=fixture(),station=d.stations[0];station.cuts=[];d.operations=O.empty();
 d.registerSales=[{station_id:station.id,work_day:'2026-10-09',fuel:P.fuels[0],fuel_total:40,gallons:10}];
 let r=O.performance(d,[station],1,'all','2026-10-09');assert.equal(r.summary.fuel,40);assert.equal(r.summary.volume,10);
 station.cuts=[{...P.blankCut('matutino','2026-10-09'),registerSource:true,closed:true,pumps:P.fuels.map((fuel,i)=>({number:i+1,fuel,amount:i===0?40:0,volume:i===0?10:0,complete:true}))}];
 r=O.performance(d,[station],1,'all','2026-10-09');assert.equal(r.summary.fuel,40);assert.equal(r.summary.volume,10);assert.equal(r.fuelSales[P.fuels[0]],40);
});
test('rechaza dos turnos separados del mismo empleado en un día y admite el siguiente día',()=>{
 let d=fixture();const employee={id:'daily',stationID:'santa',name:'Daily',document:'DAILY',phone:'555',position:'Vendedor',active:true};d=O.save(d,'employees',employee);
 const tomorrow=new Date();tomorrow.setDate(tomorrow.getDate()+1);const day=P.day(tomorrow),start=day+'T06:00:00-06:00';
 d=O.save(d,'shifts',{id:'first',stationID:'santa',employeeID:'daily',start,end:day+'T14:00:00-06:00',operationalTurn:1});
 assert.throws(()=>O.save(d,'shifts',{id:'second',stationID:'santa',employeeID:'daily',start:day+'T14:00:00-06:00',end:day+'T22:00:00-06:00',operationalTurn:2}),/un turno por día/);
 tomorrow.setDate(tomorrow.getDate()+1);const next=P.day(tomorrow);assert.equal(O.save(d,'shifts',{id:'next',stationID:'santa',employeeID:'daily',start:next+'T06:00:00-06:00',end:next+'T14:00:00-06:00'}).operations.shifts.length,2);
});
function reportFixture(){
 const cut=(closed,amount,date='2026-10-07')=>({...P.blankCut('matutino',date),closed,pumps:[{fuel:P.fuels[0],amount,volume:10}],losses:[{volume:2}]});
 const stations=[{id:'a',cuts:[cut(true,100),cut(false,999)]},{id:'b',cuts:[cut(true,500)]}];
 const sale=(stationID,date,price,quantity=1)=>({stationID,date,lines:[{productID:'oil',name:'Aceite',price,quantity}]});
 const record=status=>({stationID:'a',date:'2026-10-08T12:00:00Z',serviceID:'wash',name:'Lavado',price:30,status});
 return {stations,operations:{...O.empty(),products:[{id:'oil',price:999}],sales:[sale('a','2026-10-07T06:00:00Z',10,2),sale('a','2026-10-07T05:59:59Z',7),sale('a','2026-10-10T05:59:59Z',5),sale('a','2026-10-10T06:00:00Z',999),sale('b','2026-10-08T12:00:00Z',50)],records:['Completado','Pendiente','En proceso','Cancelado'].map(record)}};
}
test('rendimiento suma ingresos históricos y excluye borradores, servicios pendientes y otras sucursales',()=>{
 const d=reportFixture(),before=JSON.stringify(d),r=O.performance(d,[d.stations[0]],3,'all','2026-10-09');
 assert.equal(r.summary.fuel,100);assert.equal(r.summary.products,25);assert.equal(r.summary.services,30);assert.equal(r.summary.total,155);assert.equal(r.summary.sales,155);
 assert.equal(r.summary.volume,10);assert.equal(r.summary.losses,2);assert.equal(r.summary.units,3);assert.equal(r.summary.completed,1);assert.equal(r.summary.pending,2);assert.equal(r.summary.cancelled,1);
 assert.deepEqual(r.points.map(p=>p.date),['2026-10-07','2026-10-08','2026-10-09']);assert.deepEqual(r.points.map(p=>p.sales),[120,30,5]);assert.equal(r.products[0].revenue,25);assert.equal(r.services[0].revenue,30);assert.equal(JSON.stringify(d),before);
 assert.equal(O.performance(d,d.stations,3,'all','2026-10-09').summary.total,705);
});
test('filtros, días vacíos y CSV conservan el desglose y usan el calendario de El Salvador',()=>{
 const d=reportFixture(),r=O.performance(d,[d.stations[0]],3,'products','2026-10-09');assert.equal(r.summary.sales,25);assert.equal(r.summary.total,155);assert.deepEqual(r.points.map(p=>p.sales),[20,0,5]);
 assert.equal(O.performance(d,[d.stations[0]],3,'products','2026-10-06').summary.sales,7);
 const csv=O.performanceCSV(r),rows=csv.split('\n');assert.equal(rows.length,4);assert.equal(rows[1].split(',').length,12);assert.equal(rows[1].split(',')[4],'120.00');assert.equal(rows[1].split(',')[5],'20.00');
 assert.equal(O.performance(d,[],7,'services','2026-10-09').summary.sales,0);assert.throws(()=>O.performance(d,d.stations,0),/Período/);
});
function employee(data,active=true){return O.save(data,'employees',{id:'emp',stationID:'santa',name:'Carlos',document:'DOC1',phone:'555',email:'',position:'Cajero',hireDate:'2026-10-01T00:00:00Z',active});}
test('asignación rechaza ayer y permite hoy; el historial previo no bloquea notas ni cancelación',()=>{
 const d=employee(fixture()),today=P.day(),date=new Date(today+'T12:00:00Z');date.setUTCDate(date.getUTCDate()-1);const yesterday=date.toISOString().slice(0,10),s={id:'past',stationID:'santa',employeeID:'emp',start:yesterday+'T10:00:00-06:00',end:yesterday+'T18:00:00-06:00'};
 assert.throws(()=>O.save(d,'shifts',s),/fecha pasada/);assert.equal(d.operations.shifts.length,0);
 assert.equal(O.save(d,'shifts',{...s,start:today+'T10:00:00-06:00',end:today+'T18:00:00-06:00'}).operations.shifts.length,1);
 d.operations.shifts.push(s);assert.equal(O.save(d,'shifts',{...s,notes:'Observación histórica'}).operations.shifts[0].notes,'Observación histórica');assert.equal(O.cancelShift(d,'past').operations.shifts[0].cancelled,true);
 assert.throws(()=>O.save(d,'shifts',{...s,end:yesterday+'T19:00:00-06:00'}),/fecha pasada/);
});
test('eliminar gerente libera sucursal y elimina acceso sin borrar registros ni aceptar generales',()=>{
 const d=fixture(),m=d.users.find(u=>u.role==='branch'),branch=d.stations.find(s=>s.id===m.stationId),history=JSON.stringify(branch.cuts),n=O.deleteManager(d,m.id);
 assert.equal(n.users.some(u=>u.id===m.id),false);assert.equal(n.stations.find(s=>s.id===branch.id).manager,'Sin asignar');assert.equal(JSON.stringify(n.stations.find(s=>s.id===branch.id).cuts),history);assert.equal(d.users.some(u=>u.id===m.id),true);
 assert.throws(()=>O.deleteManager(d,d.users.find(u=>u.role==='general').id),/sucursal/);m.active=false;assert.equal(O.deleteManager(d,m.id).users.some(u=>u.id===m.id),false);
});
function product(data){return O.save(data,'products',{id:'prod',stationID:'santa',name:'Aceite',sku:'LUB1',category:'Lubricantes',price:10,cost:5,stock:5,minimum:2,active:true});}
test('todos los tanques iniciales y nuevas sucursales tienen 10000',()=>{assert.ok(P.seed().stations.every(s=>s.tanks.every(t=>t.capacity===10000)));assert.ok(P.addStation(P.seed(),{name:'Nueva',city:'Ciudad',address:'Calle'}).stations.at(-1).tanks.every(t=>t.capacity===10000));});
test('llenado actualiza una vez y rechaza exceso sin mutar',()=>{const d=fixture(),n=O.fill(d,'santa','Súper',100,10,'Proveedor');assert.equal(n.stations[0].tanks[0].current,7300);assert.equal(n.stations[0].receipts.length,1);assert.equal(d.stations[0].tanks[0].current,7200);assert.throws(()=>O.fill(d,'santa','Súper',3000,10,'P'),/capacidad/);});
test('documentos únicos y baja lógica preservan personal',()=>{const d=employee(fixture());assert.throws(()=>O.save(d,'employees',{...d.operations.employees[0],id:'otro'}),/documento/);const n=employee(d,false);assert.equal(n.operations.employees.length,1);assert.equal(n.operations.employees[0].active,false);});
test('turnos nocturnos permitidos; superpuestos e inactivos rechazados',()=>{const d=employee(fixture()),s={id:'shift',stationID:'santa',employeeID:'emp',start:P.day(new Date(Date.now()+86400000))+'T22:00:00Z',end:P.day(new Date(Date.now()+172800000))+'T06:00:00Z'},n=O.save(d,'shifts',s);assert.throws(()=>O.save(n,'shifts',{...s,id:'other'}),/Conflicto/);assert.throws(()=>O.save(employee(d,false),'shifts',s),/activo/);const clocked=O.clock(O.clock(n,'shift'),'shift');assert.ok(clocked.operations.shifts[0].clockOut);assert.throws(()=>O.clock(clocked,'shift'),/cerrado/);});
test('venta atómica conserva precio histórico y calcula cambio',()=>{const d=product(fixture()),n=O.sell(d,'santa',{prod:2},'Carlos','Efectivo',25);assert.equal(n.operations.products[0].stock,3);assert.equal(O.total(n.operations.sales[0]),20);assert.equal(n.operations.sales[0].received-O.total(n.operations.sales[0]),5);const updated=O.save(n,'products',{...n.operations.products[0],price:99});assert.equal(O.total(updated.operations.sales[0]),20);assert.throws(()=>O.sell(d,'santa',{prod:6},'C','Efectivo',100),/Existencias/);assert.throws(()=>O.sell(d,'santa',{prod:2},'C','Efectivo',10),/Pago/);assert.equal(d.operations.products[0].stock,5);});
test('servicios flexibles y estados terminales inmutables',()=>{const d=O.save(employee(fixture()),'services',{id:'srv',stationID:'santa',name:'Lavado',price:35,available:true}),n=O.record(d,{stationID:'santa',serviceID:'srv',employeeID:'emp',vehicle:'Sedán',notes:'Exterior'}),id=n.operations.records[0].id,done=O.transition(n,id,'Completado');assert.equal(done.operations.records[0].price,35);assert.throws(()=>O.transition(done,id,'Cancelado'),/terminó/);});
test('desactivar gerente libera asignación y preserva historial',()=>{const d=fixture(),n=O.manager(d,'abigail',false);assert.equal(n.users.find(u=>u.id==='abigail').active,false);assert.equal(n.users.find(u=>u.id==='abigail').stationId,null);assert.equal(n.stations[0].manager,'Sin asignar');assert.deepEqual(n.stations[0].cuts,d.stations[0].cuts);});
test('compras del día incluyen llenados independientes sin duplicarlos en cortes',()=>{const d=fixture(),before=P.aggregate(d.stations).purchases,n=O.fill(d,'santa','Súper',100,300,'P');assert.equal(P.aggregate(n.stations).purchases,before+300);assert.deepEqual(n.stations[0].cuts,d.stations[0].cuts);});
test('cancelación conserva historial y libera el horario para otra asignación',()=>{let d=employee(fixture()),s={id:'s1',stationID:'santa',employeeID:'emp',start:'2026-10-12T22:00:00Z',end:'2026-10-13T06:00:00Z',type:'Noche',notes:'Cobertura'};d=O.save(d,'shifts',s);d=O.cancelShift(d,'s1');assert.equal(O.shiftStatus(d.operations.shifts[0]),'Cancelado');d=O.save(d,'shifts',{...s,id:'s2'});assert.equal(d.operations.shifts.length,2);assert.throws(()=>O.clock(d,'s1'),/cerrado/);assert.throws(()=>O.save(d,'shifts',s),/Programado/);});
test('turno iniciado impide edición y cancelación; salida lo completa',()=>{let d=employee(fixture()),s={id:'s1',stationID:'santa',employeeID:'emp',start:'2026-10-12T22:00:00Z',end:'2026-10-13T06:00:00Z'};d=O.clock(O.save(d,'shifts',s),'s1');assert.equal(O.shiftStatus(d.operations.shifts[0]),'En curso');assert.throws(()=>O.cancelShift(d,'s1'),/Programado/);assert.throws(()=>O.save(d,'shifts',s),/Programado/);d=O.clock(d,'s1');assert.equal(O.shiftStatus(d.operations.shifts[0]),'Completado');});

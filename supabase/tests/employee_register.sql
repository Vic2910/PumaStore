-- Execute in SQL Editor AFTER migrations 001–004. All fixtures roll back.
begin;
insert into auth.users(id,email) values
 ('91000000-0000-0000-0000-000000000001','register-manager@example.invalid'),
 ('91000000-0000-0000-0000-000000000002','register-seller@example.invalid'),
 ('91000000-0000-0000-0000-000000000003','register-dispatcher@example.invalid'),
 ('91000000-0000-0000-0000-000000000004','register-seller-two@example.invalid');
insert into profiles(id,name,role,station_id) values('91000000-0000-0000-0000-000000000001','Manager','branch','91000000-0000-0000-0000-000000000010');
insert into station_documents(id,document) values('91000000-0000-0000-0000-000000000010',jsonb_build_object(
 'station',jsonb_build_object('id','91000000-0000-0000-0000-000000000010','nombre','QA','cuts','[]'::jsonb,'tanks',jsonb_build_array(
 jsonb_build_object('id',gen_random_uuid(),'fuelType','Súper','capacityGallons',10000,'currentGallons',1000),
 jsonb_build_object('id',gen_random_uuid(),'fuelType','Regular','capacityGallons',10000,'currentGallons',1000),
 jsonb_build_object('id',gen_random_uuid(),'fuelType','Diésel','capacityGallons',10000,'currentGallons',1000))),
 'operations',jsonb_build_object('employees',jsonb_build_array(
 jsonb_build_object('id','91000000-0000-0000-0000-000000000020','stationID','91000000-0000-0000-0000-000000000010','name','Seller','position','Vendedor','active',true),
 jsonb_build_object('id','91000000-0000-0000-0000-000000000021','stationID','91000000-0000-0000-0000-000000000010','name','Dispatcher','position','Despachador','active',true),
 jsonb_build_object('id','91000000-0000-0000-0000-000000000022','stationID','91000000-0000-0000-0000-000000000010','name','Seller two','position','Vendedor','active',true)),
 'shifts',jsonb_build_array(
 jsonb_build_object('id','91000000-0000-0000-0000-000000000030','stationID','91000000-0000-0000-0000-000000000010','employeeID','91000000-0000-0000-0000-000000000020','start',now()-interval '1 hour','end',now()+interval '1 hour','operationalTurn',1),
 jsonb_build_object('id','91000000-0000-0000-0000-000000000031','stationID','91000000-0000-0000-0000-000000000010','employeeID','91000000-0000-0000-0000-000000000021','start',now()-interval '1 hour','end',now()+interval '1 hour','operationalTurn',1),
 jsonb_build_object('id','91000000-0000-0000-0000-000000000032','stationID','91000000-0000-0000-0000-000000000010','employeeID','91000000-0000-0000-0000-000000000022','start',now()-interval '1 hour','end',now()+interval '1 hour','operationalTurn',2)),
 'products',jsonb_build_array(jsonb_build_object('id','91000000-0000-0000-0000-000000000040','stationID','91000000-0000-0000-0000-000000000010','name','Oil','sku','OIL','price',10,'stock',5,'active',true)),
 'services',jsonb_build_array(jsonb_build_object('id','91000000-0000-0000-0000-000000000050','stationID','91000000-0000-0000-0000-000000000010','name','Air','price',3,'available',true)),
 'sales','[]'::jsonb,'records','[]'::jsonb,'receipts','[]'::jsonb)));
set local role authenticated;
select set_config('request.jwt.claim.sub','91000000-0000-0000-0000-000000000001',true);
select provision_employee('91000000-0000-0000-0000-000000000002','91000000-0000-0000-0000-000000000010','91000000-0000-0000-0000-000000000020','seller');
select provision_employee('91000000-0000-0000-0000-000000000003','91000000-0000-0000-0000-000000000010','91000000-0000-0000-0000-000000000021','dispatcher');
select provision_employee('91000000-0000-0000-0000-000000000004','91000000-0000-0000-0000-000000000010','91000000-0000-0000-0000-000000000022','seller');
select set_fuel_price('91000000-0000-0000-0000-000000000010','Súper',4);
select set_config('request.jwt.claim.sub','91000000-0000-0000-0000-000000000002',true);
do $$ declare s employee_sessions; again employee_sessions; v register_sales; begin
 if exists(select 1 from station_documents) then raise exception 'FAIL: worker reads full documents'; end if;
 if public.can_access_station('91000000-0000-0000-0000-000000000010') then raise exception 'FAIL: worker has document-write permission'; end if;
 begin
   perform public.save_stations('[{"id":"91000000-0000-0000-0000-000000000010","revision":1,"document":{}}]');
   raise exception 'FAIL: worker can edit catalog';
 exception when others then if sqlerrm<>'Acceso denegado' then raise; end if; end;
 s=begin_employee_shift('91000000-0000-0000-0000-000000000030');
 again=begin_employee_shift('91000000-0000-0000-0000-000000000030');
 if s.id<>again.id then raise exception 'FAIL: duplicate entry'; end if;
 v=register_employee_sale('91000000-0000-0000-0000-000000000060',s.id,'[{"productID":"91000000-0000-0000-0000-000000000040","quantity":2}]',null,0,null,'Efectivo',25);
 if v.total<>20 or v.change<>5 then raise exception 'FAIL: product total or change'; end if;
 perform register_employee_sale(v.id,s.id,'[{"productID":"91000000-0000-0000-0000-000000000040","quantity":2}]',null,0,null,'Efectivo',25);
 if (worker_context()->'products'->0->>'stock')::int<>3 then raise exception 'FAIL: duplicate product deduction'; end if;
 begin
   perform register_employee_sale(gen_random_uuid(),s.id,'[]','Súper',2,null,'Efectivo',20);
   raise exception 'FAIL: seller sells fuel';
 exception when others then if sqlerrm<>'PRODUCTS' then raise; end if; end;
 begin
   perform register_employee_sale(gen_random_uuid(),s.id,'[{"productID":"91000000-0000-0000-0000-000000000040","quantity":2}]',null,0,null,'Efectivo',1);
   raise exception 'FAIL: insufficient payment accepted';
 exception when others then if sqlerrm<>'PAYMENT' then raise; end if; end;
 if (worker_context()->'products'->0->>'stock')::int<>3 then raise exception 'FAIL: failed sale changed inventory'; end if;
 s=end_employee_shift(s.id); again=end_employee_shift(s.id);
 if s.exited_at<>again.exited_at or (s.summary->>'total')::numeric<>20 then raise exception 'FAIL: repeated exit'; end if;
 again=begin_employee_shift('91000000-0000-0000-0000-000000000030');
 if again.exited_at is null then raise exception 'FAIL: ended day reopened'; end if;
 begin
   perform register_employee_sale(gen_random_uuid(),s.id,'[{"productID":"91000000-0000-0000-0000-000000000040","quantity":1}]',null,0,null,'Efectivo',20);
   raise exception 'FAIL: sale after exit';
 exception when others then if sqlerrm<>'SHIFT_CLOSED' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','91000000-0000-0000-0000-000000000003',true);
do $$ declare s employee_sessions; v register_sales; begin
 s=begin_employee_shift('91000000-0000-0000-0000-000000000031');
 if exists(select 1 from register_sales where employee_id<>'91000000-0000-0000-0000-000000000021') then raise exception 'FAIL: dispatcher reads another employee'; end if;
 v=register_employee_sale('91000000-0000-0000-0000-000000000061',s.id,'[]','Súper',10,'91000000-0000-0000-0000-000000000050','Efectivo',50);
 if v.fuel_total<>40 or v.service_total<>3 or v.total<>43 or v.change<>7 then raise exception 'FAIL: fuel/service breakdown'; end if;
 perform register_employee_sale(v.id,s.id,'[]','Súper',10,'91000000-0000-0000-0000-000000000050','Efectivo',50);
 perform end_employee_shift(s.id);
end $$;
select set_config('request.jwt.claim.sub','91000000-0000-0000-0000-000000000001',true);
do $$ declare c operational_closures; again operational_closures; doc jsonb; day date; begin
 select work_day into day from employee_sessions where employee_id='91000000-0000-0000-0000-000000000021';
 c=close_operational_turn('91000000-0000-0000-0000-000000000010',day,1);
 again=close_operational_turn('91000000-0000-0000-0000-000000000010',day,1);
 if c.id<>again.id or (c.snapshot->>'fuel')::numeric<>40 or (c.snapshot->>'products')::numeric<>20 or (c.snapshot->>'services')::numeric<>3 or (c.snapshot->>'total')::numeric<>63 then raise exception 'FAIL: cut summary or idempotency'; end if;
 select document into doc from station_documents where id=c.station_id;
 if (doc->'station'->'tanks'->0->>'currentGallons')::numeric<>990 then raise exception 'FAIL: cut deducted inventory twice'; end if;
 if jsonb_array_length(doc->'station'->'cuts'->0->'pumps')<>3 then raise exception 'FAIL: expected three controls'; end if;
 if jsonb_array_length(doc->'operations'->'sales')<>1 or jsonb_array_length(doc->'operations'->'records')<>1 then raise exception 'FAIL: duplicate report projection'; end if;
end $$;
select set_config('request.jwt.claim.sub','91000000-0000-0000-0000-000000000004',true);
do $$ declare s employee_sessions; begin
 s=begin_employee_shift('91000000-0000-0000-0000-000000000032');
 perform register_employee_sale('91000000-0000-0000-0000-000000000062',s.id,'[{"productID":"91000000-0000-0000-0000-000000000040","quantity":1}]',null,0,null,'Tarjeta',10);
 perform end_employee_shift(s.id);
end $$;
select set_config('request.jwt.claim.sub','91000000-0000-0000-0000-000000000001',true);
do $$ declare c operational_closures; first operational_closures; day date; begin
 select work_day into day from employee_sessions where employee_id='91000000-0000-0000-0000-000000000022';
 c=close_operational_turn('91000000-0000-0000-0000-000000000010',day,2);
 select * into first from operational_closures where station_id=c.station_id and work_day=day and turn=1;
 if (c.snapshot->>'total')::numeric<>10 or (c.snapshot->>'products')::numeric<>10 or (c.snapshot->>'dayTotal')::numeric<>73 then raise exception 'FAIL: second cut includes first turn or incorrect day total'; end if;
 if (first.snapshot->>'total')::numeric<>63 or (first.snapshot->>'dayTotal')::numeric<>63 then raise exception 'FAIL: first snapshot changed'; end if;
end $$;
rollback;

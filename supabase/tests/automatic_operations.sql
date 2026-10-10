-- Run in SQL Editor AFTER both migrations. Everything rolls back.
begin;
insert into auth.users(id,email) values
 ('90000000-0000-0000-0000-000000000001','qa-general@example.invalid'),
 ('90000000-0000-0000-0000-000000000002','qa-branch@example.invalid');
insert into public.profiles(id,name,role,station_id) values
 ('90000000-0000-0000-0000-000000000001','QA General','general',null),
 ('90000000-0000-0000-0000-000000000002','QA Branch','branch','90000000-0000-0000-0000-000000000010');
create temp table qa_document(document jsonb);
insert into qa_document select jsonb_build_object(
 'station',jsonb_build_object('id','90000000-0000-0000-0000-000000000010','nombre','QA','direccion','QA','ciudad','QA','gerenteNombre','QA','cuts','[]'::jsonb,'tanks',jsonb_build_array(
 jsonb_build_object('id',gen_random_uuid(),'fuelType','Súper','capacityGallons',10000,'currentGallons',0),
 jsonb_build_object('id',gen_random_uuid(),'fuelType','Regular','capacityGallons',10000,'currentGallons',0),
 jsonb_build_object('id',gen_random_uuid(),'fuelType','Diésel','capacityGallons',10000,'currentGallons',0))),
 'operations',jsonb_build_object('employees',jsonb_build_array(jsonb_build_object('id','90000000-0000-0000-0000-000000000020','stationID','90000000-0000-0000-0000-000000000010','name','QA','active',true)),
 'shifts','[]'::jsonb,'products','[]'::jsonb,'sales','[]'::jsonb,'services','[]'::jsonb,'records','[]'::jsonb,'receipts','[]'::jsonb));
grant select on qa_document to authenticated;
set local role authenticated;
select set_config('request.jwt.claim.sub','90000000-0000-0000-0000-000000000001',true);
select public.save_stations(jsonb_build_array(jsonb_build_object('id','90000000-0000-0000-0000-000000000010','revision',0,'document',document))) from qa_document;
do $$ declare doc jsonb; begin
 select document into doc from qa_document;
 begin
   perform public.save_stations(jsonb_build_array(jsonb_build_object('id','90000000-0000-0000-0000-000000000010','revision',0,'document',doc)));
   raise exception 'FAIL: stale revision accepted';
 exception when others then if position('Conflicto de versión' in sqlerrm)=0 then raise; end if; end;
 doc=jsonb_set(doc,'{operations,shifts}',jsonb_build_array(
  jsonb_build_object('id','90000000-0000-0000-0000-000000000030','stationID','90000000-0000-0000-0000-000000000010','employeeID','90000000-0000-0000-0000-000000000020','start','2026-10-12T22:00:00Z','end','2026-10-13T06:00:00Z'),
  jsonb_build_object('id','90000000-0000-0000-0000-000000000031','stationID','90000000-0000-0000-0000-000000000010','employeeID','90000000-0000-0000-0000-000000000020','start','2026-10-12T23:00:00Z','end','2026-10-13T07:00:00Z')));
 begin
   perform public.save_stations(jsonb_build_array(jsonb_build_object('id','90000000-0000-0000-0000-000000000010','revision',1,'document',doc)));
   raise exception 'FAIL: overlapping shifts accepted';
 exception when others then if position('Conflicto de horarios' in sqlerrm)=0 then raise; end if; end;
 if (select revision from public.station_documents where id='90000000-0000-0000-0000-000000000010')<>1 then raise exception 'FAIL: rejected operation mutated inventory'; end if;
end $$;
select set_config('request.jwt.claim.sub','90000000-0000-0000-0000-000000000002',true);
do $$ begin
 if (select count(*) from public.station_documents where id='90000000-0000-0000-0000-000000000010')<>1 then raise exception 'FAIL: branch cannot read its own station'; end if;
 if exists(select 1 from public.station_documents where id<>'90000000-0000-0000-0000-000000000010') then raise exception 'FAIL: branch sees another station'; end if;
 begin
   perform public.set_manager_active('90000000-0000-0000-0000-000000000002',false);
   raise exception 'FAIL: branch can administer managers';
 exception when others then if position('Acceso denegado' in sqlerrm)=0 then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','90000000-0000-0000-0000-000000000001',true);
select public.set_manager_active('90000000-0000-0000-0000-000000000002',false);
select set_config('request.jwt.claim.sub','90000000-0000-0000-0000-000000000002',true);
do $$ begin if exists(select 1 from public.station_documents) then raise exception 'FAIL: inactive branch can read'; end if; end $$;
reset role;
do $$ begin
 if has_function_privilege('anon','public.save_stations(jsonb)','EXECUTE') then raise exception 'FAIL: anonymous RPC access was not revoked'; end if;
end $$;
rollback;
-- PASS if no FAIL exception appeared. No QA accounts or data remain.

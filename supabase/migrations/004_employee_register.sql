-- Run after 003. Transactions, prices, inventory and permissions are authoritative here.
begin;
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles add constraint profiles_role_check check(role in ('general','branch','seller','dispatcher'));
alter table public.profiles add column if not exists employee_id uuid;
create unique index if not exists profile_employee on profiles(employee_id) where employee_id is not null;
create or replace function public.can_access_station(p_id uuid) returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from profiles where id=auth.uid() and active and (role='general' or (role='branch' and station_id=p_id)));
$$;
create table if not exists public.employee_sessions (
 id uuid primary key default gen_random_uuid(), profile_id uuid not null references auth.users(id), employee_id uuid not null,
 station_id uuid not null references station_documents(id), shift_id uuid not null, work_day date not null,
 turn integer not null check(turn in (1,2)), entered_at timestamptz not null default now(), exited_at timestamptz,
 summary jsonb, unique(employee_id,work_day)
);
create unique index if not exists employee_open_session on employee_sessions(employee_id) where exited_at is null;
create table if not exists public.register_sales (
 id uuid primary key, session_id uuid not null references employee_sessions(id), profile_id uuid not null references auth.users(id),
 employee_id uuid not null, employee_name text not null, station_id uuid not null references station_documents(id),
 work_day date not null, turn integer not null check(turn in(1,2)), sold_at timestamptz not null default now(),
 fuel text, service_id uuid, gallons numeric not null default 0 check(gallons>=0), fuel_total numeric not null default 0,
 product_total numeric not null default 0, service_total numeric not null default 0, lines jsonb not null default '[]',
 payment text not null, received numeric not null, total numeric not null, change numeric not null,
 check(total=fuel_total+product_total+service_total and change=received-total and change>=0)
);
alter table public.register_sales add column if not exists service_id uuid;
create table if not exists public.operational_closures (
 id uuid primary key default gen_random_uuid(), station_id uuid not null references station_documents(id), work_day date not null,
 turn integer not null check(turn in(1,2)), closed_at timestamptz not null default now(), actor uuid not null references auth.users(id),
 snapshot jsonb not null, unique(station_id,work_day,turn)
);
create table if not exists public.fuel_prices (
 station_id uuid not null references station_documents(id), fuel text not null check(fuel in('Súper','Regular','Diésel')),
 price numeric not null check(price>0), primary key(station_id,fuel)
);
alter table employee_sessions enable row level security;
alter table register_sales enable row level security;
alter table operational_closures enable row level security;
alter table fuel_prices enable row level security;
drop policy if exists session_read on employee_sessions;
create policy session_read on employee_sessions for select to authenticated using(can_access_station(station_id) or (profile_id=auth.uid() and exists(select 1 from profiles where id=auth.uid() and active)));
drop policy if exists sale_read on register_sales;
create policy sale_read on register_sales for select to authenticated using(can_access_station(station_id) or (profile_id=auth.uid() and exists(select 1 from profiles where id=auth.uid() and active)));
drop policy if exists closure_read on operational_closures;
create policy closure_read on operational_closures for select to authenticated using(can_access_station(station_id));
drop policy if exists price_read on fuel_prices;
create policy price_read on fuel_prices for select to authenticated using(can_access_station(station_id) or exists(select 1 from profiles where id=auth.uid() and active and station_id=fuel_prices.station_id));
revoke all on employee_sessions,register_sales,operational_closures,fuel_prices from anon,authenticated;
grant select on employee_sessions,register_sales,operational_closures,fuel_prices to authenticated;
-- A scalar JSON response avoids the REST row cap and uses one consistent read snapshot.
create or replace function public.register_context() returns jsonb language sql stable security invoker set search_path=public as $$
 select jsonb_build_object(
 'sessions',coalesce((select jsonb_agg(s order by entered_at desc,id) from employee_sessions s),'[]'::jsonb),
 'sales',coalesce((select jsonb_agg(s order by sold_at desc,id) from register_sales s),'[]'::jsonb),
 'prices',coalesce((select jsonb_agg(p) from fuel_prices p),'[]'::jsonb),
 'closures',coalesce((select jsonb_agg(c order by work_day desc,turn) from operational_closures c),'[]'::jsonb));
$$;
revoke all on function public.register_context() from public,anon,authenticated;
grant execute on function public.register_context() to authenticated;

create or replace function public.provision_employee(p_id uuid,p_station uuid,p_employee uuid,p_role text) returns void
language plpgsql security definer set search_path=public as $$
declare e jsonb;
begin
 if not can_access_station(p_station) or p_role not in('seller','dispatcher') then raise exception 'ACCESS'; end if;
 select value into e from station_documents d,jsonb_array_elements(d.document->'operations'->'employees') where d.id=p_station and (value->>'id')::uuid=p_employee and (value->>'active')::boolean;
 if e is null or not exists(select 1 from auth.users where id=p_id) or exists(select 1 from profiles where id=p_id) then raise exception 'EMPLOYEE'; end if;
 if lower(e->>'position')<>(case when p_role='seller' then 'vendedor' else 'despachador' end) then raise exception 'POSITION'; end if;
 insert into profiles(id,name,role,station_id,employee_id,active) values(p_id,e->>'name',p_role,p_station,p_employee,true);
end; $$;

create or replace function public.worker_context() returns jsonb language plpgsql security definer set search_path=public as $$
declare p profiles; d jsonb; e jsonb;
begin
 select * into p from profiles where id=auth.uid() and active and role in('seller','dispatcher');
 if p.id is null then raise exception 'ACCESS'; end if;
 select document into d from station_documents where id=p.station_id;
 select value into e from jsonb_array_elements(d->'operations'->'employees') where (value->>'id')::uuid=p.employee_id and (value->>'active')::boolean;
 if e is null then raise exception 'EMPLOYEE'; end if;
 if lower(e->>'position')<>(case when p.role='seller' then 'vendedor' else 'despachador' end) then raise exception 'POSITION'; end if;
 return jsonb_build_object('name',d->'station'->>'nombre','products',coalesce((select jsonb_agg(value) from jsonb_array_elements(d->'operations'->'products') where (value->>'active')::boolean),'[]'),
 'services',coalesce((select jsonb_agg(value) from jsonb_array_elements(d->'operations'->'services') where (value->>'available')::boolean),'[]'),
 'shifts',coalesce((select jsonb_agg(value) from jsonb_array_elements(d->'operations'->'shifts') where (value->>'employeeID')::uuid=p.employee_id),'[]'));
end; $$;

-- All register mutations take the same station lock as the document store.
create or replace function public.begin_employee_shift(p_shift uuid) returns employee_sessions language plpgsql security definer set search_path=public as $$
declare p profiles; d jsonb; s jsonb; day date; result employee_sessions; n integer;
begin
 perform worker_context(); select * into p from profiles where id=auth.uid();
 perform pg_advisory_xact_lock(hashtextextended(p.station_id::text,0));
 select document into d from station_documents where id=p.station_id for update;
 select value into s from jsonb_array_elements(d->'operations'->'shifts') where (value->>'id')::uuid=p_shift and (value->>'employeeID')::uuid=p.employee_id and not coalesce((value->>'cancelled')::boolean,false);
 if s is null then raise exception 'SHIFT'; end if;
 day=((s->>'start')::timestamptz at time zone 'America/El_Salvador')::date;
 select * into result from employee_sessions where employee_id=p.employee_id and work_day=day;
 if result.id is not null then return result; end if;
 if now() < (s->>'start')::timestamptz or now() >= (s->>'end')::timestamptz or s->>'clockOut' is not null or s->>'clockIn' is not null then raise exception 'SHIFT_TIME'; end if;
 n=coalesce((s->>'operationalTurn')::integer,case when s->>'type'='Mañana' then 1 else 2 end);
 if exists(select 1 from operational_closures where station_id=p.station_id and work_day=day and turn=n) then raise exception 'TURN_CLOSED'; end if;
 if exists(select 1 from jsonb_array_elements(d->'station'->'cuts') where (to_timestamp((value->>'fecha')::double precision+978307200) at time zone 'America/El_Salvador')::date=day and not coalesce((value->>'registerSource')::boolean,false)) then raise exception 'LEGACY_CUT'; end if;
 if exists(select 1 from employee_sessions where employee_id=p.employee_id and exited_at is null) then raise exception 'OPEN_SHIFT'; end if;
 insert into employee_sessions(profile_id,employee_id,station_id,shift_id,work_day,turn) values(p.id,p.employee_id,p.station_id,p_shift,day,n) returning * into result;
 s=jsonb_set(s,'{clockIn}',to_jsonb(now()));
 d=jsonb_set(d,'{operations,shifts}',(select jsonb_agg(case when (value->>'id')::uuid=p_shift then s else value end) from jsonb_array_elements(d->'operations'->'shifts')));
 update station_documents set document=d,revision=revision+1,updated_at=now(),updated_by=p.id where id=p.station_id;
 insert into station_audit(station_id,revision,actor,document) select id,revision,p.id,document from station_documents where id=p.station_id;
 return result;
end; $$;

create or replace function public.end_employee_shift(p_session uuid) returns employee_sessions language plpgsql security definer set search_path=public as $$
declare r employee_sessions; d jsonb;
begin
 select * into r from employee_sessions where id=p_session;
 if r.id is null or not (can_access_station(r.station_id) or (r.profile_id=auth.uid() and exists(select 1 from profiles where id=auth.uid() and active))) then raise exception 'ACCESS'; end if;
 perform pg_advisory_xact_lock(hashtextextended(r.station_id::text,0));
 select * into r from employee_sessions where id=p_session for update;
 if r.exited_at is not null then return r; end if;
 update employee_sessions set exited_at=now(),summary=(select jsonb_build_object('sales',count(*),'fuel',coalesce(sum(fuel_total),0),'products',coalesce(sum(product_total),0),'services',coalesce(sum(service_total),0),'total',coalesce(sum(total),0),'cash',coalesce(sum(total) filter(where payment='Efectivo'),0),'card',coalesce(sum(total) filter(where payment='Tarjeta'),0),'units',coalesce((select sum((l->>'quantity')::integer) from register_sales x,jsonb_array_elements(x.lines) l where x.session_id=p_session and l->>'productID' is not null),0)) from register_sales where session_id=p_session) where id=p_session returning * into r;
 select document into d from station_documents where id=r.station_id for update;
 d=jsonb_set(d,'{operations,shifts}',(select jsonb_agg(case when (value->>'id')::uuid=r.shift_id then jsonb_set(value,'{clockOut}',to_jsonb(r.exited_at)) else value end) from jsonb_array_elements(d->'operations'->'shifts')));
 update station_documents set document=d,revision=revision+1,updated_at=now(),updated_by=auth.uid() where id=r.station_id;
 insert into station_audit(station_id,revision,actor,document) select id,revision,auth.uid(),document from station_documents where id=r.station_id;
 return r;
end; $$;

create or replace function public.register_employee_sale(p_id uuid,p_session uuid,p_items jsonb,p_fuel text,p_gallons numeric,p_service uuid,p_payment text,p_received numeric) returns register_sales
language plpgsql security definer set search_path=public as $$
declare p profiles; r employee_sessions; existing register_sales; d jsonb; item jsonb; product jsonb; service jsonb; lines jsonb='[]'; products numeric=0; fuel_amount numeric=0; service_amount numeric=0; unit_price numeric; qty integer; total_amount numeric;
begin
 perform worker_context(); select * into p from profiles where id=auth.uid();
 perform pg_advisory_xact_lock(hashtextextended(p.station_id::text,0));
 select * into existing from register_sales where id=p_id;
 if existing.id is not null then if existing.profile_id<>p.id or existing.session_id<>p_session then raise exception 'ACCESS'; end if; return existing; end if;
 select * into r from employee_sessions where id=p_session and profile_id=p.id for update;
 if r.id is null or r.exited_at is not null then raise exception 'SHIFT_CLOSED'; end if;
 if exists(select 1 from operational_closures where station_id=r.station_id and work_day=r.work_day and turn=r.turn) then raise exception 'TURN_CLOSED'; end if;
 if p_payment not in('Efectivo','Tarjeta') or p_received is null or p_received<0 or p_received::text in('NaN','Infinity','-Infinity') then raise exception 'PAYMENT'; end if;
 select document into d from station_documents where id=r.station_id for update;
 if p.role='seller' then
   if p_fuel is not null or coalesce(p_gallons,0)<>0 or p_service is not null or jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items)=0 or jsonb_array_length(p_items)>100 then raise exception 'PRODUCTS'; end if;
   for item in select value from jsonb_array_elements(p_items) loop
     qty=(item->>'quantity')::integer;
     select value into product from jsonb_array_elements(d->'operations'->'products') where (value->>'id')::uuid=(item->>'productID')::uuid and (value->>'active')::boolean;
     if product is null or qty is null or qty<=0 or (product->>'stock')::integer<qty then raise exception 'STOCK'; end if;
     lines=lines||jsonb_build_array(jsonb_build_object('productID',product->>'id','name',product->>'name','sku',product->>'sku','quantity',qty,'price',(product->>'price')::numeric));
     products=products+round((product->>'price')::numeric*qty,2);
     product=jsonb_set(product,'{stock}',to_jsonb((product->>'stock')::integer-qty));
     d=jsonb_set(d,'{operations,products}',(select jsonb_agg(case when (value->>'id')::uuid=(product->>'id')::uuid then product else value end) from jsonb_array_elements(d->'operations'->'products')));
   end loop;
 else
   if coalesce(jsonb_array_length(p_items),0)<>0 or p_gallons is null or p_gallons<=0 or p_gallons::text in('NaN','Infinity','-Infinity') then raise exception 'FUEL'; end if;
   select price into unit_price from fuel_prices where station_id=r.station_id and fuel=p_fuel;
   if unit_price is null then raise exception 'FUEL_PRICE'; end if;
   select value into product from jsonb_array_elements(d->'station'->'tanks') where value->>'fuelType'=p_fuel;
   if product is null or (product->>'currentGallons')::numeric<p_gallons then raise exception 'STOCK'; end if;
   fuel_amount=round(unit_price*p_gallons,2);
   product=jsonb_set(product,'{currentGallons}',to_jsonb((product->>'currentGallons')::numeric-p_gallons));
   d=jsonb_set(d,'{station,tanks}',(select jsonb_agg(case when value->>'fuelType'=p_fuel then product else value end) from jsonb_array_elements(d->'station'->'tanks')));
   if p_service is not null then
     select value into service from jsonb_array_elements(d->'operations'->'services') where (value->>'id')::uuid=p_service and (value->>'available')::boolean;
     if service is null then raise exception 'SERVICE'; end if;
     service_amount=round((service->>'price')::numeric,2);
     d=jsonb_set(d,'{operations,records}',(d->'operations'->'records')||jsonb_build_array(jsonb_build_object('id',upper(p_id::text),'stationID',upper(r.station_id::text),'serviceID',upper(p_service::text),'employeeID',upper(r.employee_id::text),'sessionID',upper(r.id::text),'workDay',r.work_day,'name',service->>'name','date',now(),'price',service_amount,'vehicle','','notes','Venta de despacho','status','Completado')));
   end if;
 end if;
 total_amount=fuel_amount+products+service_amount;
 if p_received<total_amount or (p_payment='Tarjeta' and p_received<>total_amount) then raise exception 'PAYMENT'; end if;
 insert into register_sales(id,session_id,profile_id,employee_id,employee_name,station_id,work_day,turn,fuel,service_id,gallons,fuel_total,product_total,service_total,lines,payment,received,total,change) values(p_id,r.id,p.id,r.employee_id,p.name,r.station_id,r.work_day,r.turn,p_fuel,p_service,coalesce(p_gallons,0),fuel_amount,products,service_amount,lines,p_payment,p_received,total_amount,p_received-total_amount) returning * into existing;
 if p.role='seller' then
   d=jsonb_set(d,'{operations,sales}',(d->'operations'->'sales')||jsonb_build_array(jsonb_build_object('id',upper(p_id::text),'stationID',upper(r.station_id::text),'employeeID',upper(r.employee_id::text),'sessionID',upper(r.id::text),'workDay',r.work_day,'date',now(),'cashier',p.name,'lines',lines,'payment',p_payment,'received',p_received)));
 end if;
 update station_documents set document=d,revision=revision+1,updated_at=now(),updated_by=p.id where id=r.station_id;
 insert into station_audit(station_id,revision,actor,document) select id,revision,p.id,document from station_documents where id=r.station_id;
 return existing;
end; $$;

create or replace function public.set_fuel_price(p_station uuid,p_fuel text,p_price numeric) returns void language plpgsql security definer set search_path=public as $$
begin
 if not can_access_station(p_station) then raise exception 'ACCESS'; end if;
 if p_price is null or p_price<=0 or p_price::text in('NaN','Infinity','-Infinity') then raise exception 'PRICE'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_station::text,0));
 insert into fuel_prices values(p_station,p_fuel,round(p_price,4)) on conflict(station_id,fuel) do update set price=excluded.price;
end; $$;

create or replace function public.close_operational_turn(p_station uuid,p_day date,p_turn integer) returns operational_closures language plpgsql security definer set search_path=public as $$
declare r operational_closures; d jsonb; snap jsonb; controls jsonb; cut jsonb;
begin
 if not can_access_station(p_station) or p_turn not in(1,2) or p_day>(now() at time zone 'America/El_Salvador')::date then raise exception 'ACCESS'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_station::text,0));
 select * into r from operational_closures where station_id=p_station and work_day=p_day and turn=p_turn;
 if r.id is not null then return r; end if;
 if p_turn=2 and not exists(select 1 from operational_closures where station_id=p_station and work_day=p_day and turn=1) then raise exception 'FIRST_CUT'; end if;
 if exists(select 1 from employee_sessions where station_id=p_station and work_day=p_day and turn=p_turn and exited_at is null) then raise exception 'OPEN_SHIFT'; end if;
 if not exists(select 1 from employee_sessions where station_id=p_station and work_day=p_day and turn=p_turn) then raise exception 'NO_SHIFT'; end if;
 select document into d from station_documents where id=p_station for update;
 if exists(select 1 from jsonb_array_elements(d->'station'->'cuts') where (to_timestamp((value->>'fecha')::double precision+978307200) at time zone 'America/El_Salvador')::date=p_day and value->>'shift'=(case when p_turn=1 then 'Corte Matutino' else 'Corte Vespertino/Nocturno' end)) then raise exception 'LEGACY_CUT'; end if;
 select jsonb_build_object('fuel',coalesce(sum(fuel_total),0),'products',coalesce(sum(product_total),0),'services',coalesce(sum(service_total),0),'total',coalesce(sum(total),0),'sales',count(*),'dayFuel',coalesce((select sum(fuel_total) from register_sales where station_id=p_station and work_day=p_day),0),'dayProducts',coalesce((select sum(product_total) from register_sales where station_id=p_station and work_day=p_day),0),'dayServices',coalesce((select sum(service_total) from register_sales where station_id=p_station and work_day=p_day),0),'dayTotal',coalesce((select sum(total) from register_sales where station_id=p_station and work_day=p_day),0)) into snap from register_sales where station_id=p_station and work_day=p_day and turn=p_turn;
 select jsonb_agg(jsonb_build_object('id',upper(gen_random_uuid()::text),'pumpNumber',n,'fuelType',f,'ventasGalones',coalesce((select sum(gallons) from register_sales where station_id=p_station and work_day=p_day and turn=p_turn and fuel=f),0),'ventasMonto',coalesce((select sum(fuel_total) from register_sales where station_id=p_station and work_day=p_day and turn=p_turn and fuel=f),0),'completado',true) order by n) into controls from (values(1,'Súper'),(2,'Regular'),(3,'Diésel')) fuels(n,f);
 insert into operational_closures(station_id,work_day,turn,actor,snapshot) values(p_station,p_day,p_turn,auth.uid(),snap) returning * into r;
 cut=jsonb_build_object('id',upper(r.id::text),'fecha',extract(epoch from (p_day::timestamp at time zone 'America/El_Salvador'))-978307200,'shift',case when p_turn=1 then 'Corte Matutino' else 'Corte Vespertino/Nocturno' end,'pumps',controls,'purchases','[]'::jsonb,'losses','[]'::jsonb,'cerrado',true,'registerSource',true);
 d=jsonb_set(d,'{station,cuts}',(d->'station'->'cuts')||jsonb_build_array(cut));
 update station_documents set document=d,revision=revision+1,updated_at=now(),updated_by=auth.uid() where id=p_station;
 insert into station_audit(station_id,revision,actor,document) select id,revision,auth.uid(),document from station_documents where id=p_station;
 return r;
end; $$;

-- Keep existing validation and add daily uniqueness, protecting register records against document edits.
do $$ begin if to_regprocedure('public.validate_station_document_v3(uuid,jsonb)') is null then alter function public.validate_station_document(uuid,jsonb) rename to validate_station_document_v3; end if; end $$;
create or replace function public.validate_station_document(p_id uuid,p_document jsonb) returns void language plpgsql security definer set search_path=public as $$
declare s jsonb; old jsonb; x register_sales;
begin
 perform validate_station_document_v3(p_id,p_document);
 select document into old from station_documents where id=p_id;
 for s in select value from jsonb_array_elements(p_document->'operations'->'shifts') loop
   if not coalesce((s->>'cancelled')::boolean,false) and not exists(select 1 from jsonb_array_elements(coalesce(old->'operations'->'shifts','[]')) where value=s) then
     if coalesce((s->>'operationalTurn')::integer,1) not in(1,2) then raise exception 'TURN'; end if;
     if exists(select 1 from jsonb_array_elements(p_document->'operations'->'shifts') o where (o->>'id')::uuid<>(s->>'id')::uuid and (o->>'employeeID')::uuid=(s->>'employeeID')::uuid and not coalesce((o->>'cancelled')::boolean,false) and ((o->>'start')::timestamptz at time zone 'America/El_Salvador')::date=((s->>'start')::timestamptz at time zone 'America/El_Salvador')::date) then raise exception 'ONE_SHIFT'; end if;
   end if;
   if exists(select 1 from employee_sessions where shift_id=(s->>'id')::uuid) and not exists(select 1 from jsonb_array_elements(old->'operations'->'shifts') where value=s) then raise exception 'REGISTER_SHIFT_IMMUTABLE'; end if;
 end loop;
 for x in select * from register_sales where station_id=p_id and service_id is not null loop
   if not exists(select 1 from jsonb_array_elements(p_document->'operations'->'records') n join jsonb_array_elements(old->'operations'->'records') o on n=o where (n->>'id')::uuid=x.id) then raise exception 'REGISTER_SALE_IMMUTABLE'; end if;
 end loop;
 for s in select value from jsonb_array_elements(p_document->'station'->'cuts') loop
   if not exists(select 1 from jsonb_array_elements(coalesce(old->'station'->'cuts','[]')) where (value->>'id')::uuid=(s->>'id')::uuid) then
     if coalesce((s->>'registerSource')::boolean,false) or jsonb_array_length(s->'pumps')<>3 then raise exception 'CUT_CONTROLS'; end if;
     if (select count(distinct value->>'fuelType') from jsonb_array_elements(s->'pumps') where value->>'fuelType' in('Súper','Regular','Diésel'))<>3 then raise exception 'CUT_CONTROLS'; end if;
   end if;
   if not exists(select 1 from jsonb_array_elements(coalesce(old->'station'->'cuts','[]')) where value=s) and exists(select 1 from employee_sessions where station_id=p_id and work_day=(to_timestamp((s->>'fecha')::double precision+978307200) at time zone 'America/El_Salvador')::date) then raise exception 'USE_REGISTER_CUT'; end if;
 end loop;
end; $$;
revoke all on function public.validate_station_document(uuid,jsonb),public.validate_station_document_v3(uuid,jsonb) from public,anon,authenticated;
revoke all on function public.provision_employee(uuid,uuid,uuid,text),public.worker_context(),public.begin_employee_shift(uuid),public.end_employee_shift(uuid),public.register_employee_sale(uuid,uuid,jsonb,text,numeric,uuid,text,numeric),public.set_fuel_price(uuid,text,numeric),public.close_operational_turn(uuid,date,integer) from public,anon,authenticated;
grant execute on function public.provision_employee(uuid,uuid,uuid,text),public.worker_context(),public.begin_employee_shift(uuid),public.end_employee_shift(uuid),public.register_employee_sale(uuid,uuid,jsonb,text,numeric,uuid,text,numeric),public.set_fuel_price(uuid,text,numeric),public.close_operational_turn(uuid,date,integer) to authenticated;
notify pgrst,'reload schema';
commit;

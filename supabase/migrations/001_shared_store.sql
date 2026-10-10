-- Run once in the Supabase SQL editor. No service-role key belongs in clients.
create table public.profiles (
  id uuid primary key references auth.users(id),
  name text not null,
  role text not null check (role in ('general','branch')),
  station_id uuid,
  active boolean not null default true
);
create table public.station_documents (
  id uuid primary key,
  revision integer not null default 1,
  document jsonb not null,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id)
);
create table public.station_audit (
  id bigint generated always as identity primary key,
  station_id uuid not null,
  revision integer not null,
  actor uuid not null,
  created_at timestamptz not null default now(),
  document jsonb not null
);
create function public.can_access_station(p_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from profiles where id=auth.uid() and active and (role='general' or station_id=p_id));
$$;
create function public.is_general() returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from profiles where id=auth.uid() and active and role='general');
$$;
alter table profiles enable row level security;
alter table station_documents enable row level security;
alter table station_audit enable row level security;
create policy read_profiles on profiles for select to authenticated using ((id=auth.uid() and active) or public.is_general());
create policy read_stations on station_documents for select to authenticated using (public.can_access_station(id));
create policy read_audit on station_audit for select to authenticated using (public.is_general());
revoke all on profiles, station_documents, station_audit from anon, authenticated;
grant select on profiles, station_documents, station_audit to authenticated;

-- A whole station is one transaction. Revisions prevent silent last-writer wins.
create function public.save_station(p_id uuid, p_revision integer, p_document jsonb) returns integer
language plpgsql security definer set search_path = public as $$
declare old_revision integer; next_revision integer; item jsonb; collection text; tank jsonb; old_document jsonb; previous jsonb;
begin
  if not public.can_access_station(p_id) then raise exception 'Acceso denegado'; end if;
  if (p_document->'station'->>'id')::uuid is distinct from p_id then raise exception 'Sucursal inválida'; end if;
  if jsonb_typeof(p_document->'station'->'tanks') is distinct from 'array' or jsonb_typeof(p_document->'station'->'cuts') is distinct from 'array' then raise exception 'Tanques y cortes deben ser listas'; end if;
  if jsonb_typeof(p_document->'operations') is distinct from 'object' or jsonb_array_length(p_document->'station'->'tanks') <> 3 then raise exception 'Documento inválido'; end if;
  for tank in select value from jsonb_array_elements(p_document->'station'->'tanks') loop
    if jsonb_typeof(tank->'capacityGallons') is distinct from 'number' or jsonb_typeof(tank->'currentGallons') is distinct from 'number' then raise exception 'Cantidades de tanque inválidas'; end if;
    if (tank->>'capacityGallons')::numeric <= 0 or (tank->>'currentGallons')::numeric < 0 or (tank->>'currentGallons')::numeric > (tank->>'capacityGallons')::numeric then raise exception 'Inventario fuera de capacidad'; end if;
  end loop;
  foreach collection in array array['employees','shifts','products','sales','services','records','receipts'] loop
    if jsonb_typeof(p_document->'operations'->collection) is distinct from 'array' then raise exception 'Colección inválida: %', collection; end if;
    for item in select value from jsonb_array_elements(p_document->'operations'->collection) loop
      if (item->>'stationID')::uuid is distinct from p_id then raise exception 'Registro de otra sucursal'; end if;
      if item->>'id' is null then raise exception 'Registro sin identificador'; end if;
      if collection='products' and ((item->>'stock')::integer < 0 or (item->>'price')::numeric < 0 or (item->>'cost')::numeric < 0) then raise exception 'Producto inválido'; end if;
      if collection='services' and (item->>'price')::numeric < 0 then raise exception 'Precio inválido'; end if;
    end loop;
  end loop;
  -- Serialize creation as well as updates, including absent rows.
  perform pg_advisory_xact_lock(hashtextextended(p_id::text, 0));
  select revision,document into old_revision,old_document from station_documents where id=p_id for update;
  if old_revision is null then
    if not public.is_general() or p_revision <> 0 then raise exception 'Solo el gerente general crea sucursales'; end if;
    next_revision := 1;
    insert into station_documents(id,revision,document,updated_by) values(p_id,next_revision,p_document,auth.uid());
  else
    if old_revision <> p_revision then raise exception 'Conflicto de versión: descarga y concilia los cambios'; end if;
    for previous in select value from jsonb_array_elements(old_document->'station'->'cuts') where (value->>'cerrado')::boolean loop
      if not exists(select 1 from jsonb_array_elements(p_document->'station'->'cuts') where value=previous) then raise exception 'Corte cerrado inmutable'; end if;
    end loop;
    foreach collection in array array['sales'] loop
      for previous in select value from jsonb_array_elements(old_document->'operations'->collection) loop
        if not exists(select 1 from jsonb_array_elements(p_document->'operations'->collection) where value=previous) then raise exception 'Venta confirmada inmutable'; end if;
      end loop;
    end loop;
    next_revision := old_revision + 1;
    update station_documents set document=p_document,revision=next_revision,updated_at=now(),updated_by=auth.uid() where id=p_id;
  end if;
  insert into station_audit(station_id,revision,actor,document) values(p_id,next_revision,auth.uid(),p_document);
  return next_revision;
end;
$$;
create function public.set_manager_active(p_id uuid, p_active boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_general() then raise exception 'Acceso denegado'; end if;
  update profiles set active=p_active, station_id=case when p_active then station_id else null end where id=p_id and role='branch';
  if not found then raise exception 'Gerente inexistente'; end if;
end;
$$;
revoke all on function public.can_access_station(uuid), public.is_general(), public.save_station(uuid,integer,jsonb), public.set_manager_active(uuid,boolean) from public;
grant execute on function public.can_access_station(uuid), public.is_general(), public.save_station(uuid,integer,jsonb), public.set_manager_active(uuid,boolean) to authenticated;

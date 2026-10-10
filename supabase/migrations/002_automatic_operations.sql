-- Execute after 001_shared_store.sql. Safe to execute again.
-- Do not grant anon SELECT: Auth and profiles determine access.
create or replace function public.validate_station_document(p_id uuid, p_document jsonb) returns void
language plpgsql security definer set search_path=public as $$
declare item jsonb; employee jsonb; other jsonb; old_document jsonb; previous jsonb;
begin
  select document into old_document from station_documents where id=p_id;
  for item in select value from jsonb_array_elements(p_document->'operations'->'shifts') loop
    if jsonb_typeof(item->'start') is distinct from 'string' or jsonb_typeof(item->'end') is distinct from 'string' or item->>'employeeID' is null then raise exception 'Horario o empleado incompleto'; end if;
    if (item->>'stationID')::uuid is distinct from p_id or (item->>'end')::timestamptz <= (item->>'start')::timestamptz then raise exception 'Horario inválido'; end if;
    select value into employee from jsonb_array_elements(p_document->'operations'->'employees') where (value->>'id')::uuid=(item->>'employeeID')::uuid;
    if employee is null then raise exception 'Empleado inexistente'; end if;
    select value into previous from jsonb_array_elements(coalesce(old_document->'operations'->'shifts','[]')) where (value->>'id')::uuid=(item->>'id')::uuid;
    if previous is not null and previous is distinct from item and (coalesce((previous->>'cancelled')::boolean,false) or previous->>'clockOut' is not null) then raise exception 'Turno terminado inmutable'; end if;
    if previous is not null and previous->>'clockIn' is not null and (previous->>'start' is distinct from item->>'start' or previous->>'end' is distinct from item->>'end' or previous->>'employeeID' is distinct from item->>'employeeID' or coalesce((item->>'cancelled')::boolean,false)) then raise exception 'Solo puedes editar o cancelar un turno Programado'; end if;
    if previous is distinct from item and not coalesce((item->>'cancelled')::boolean,false) and not coalesce((employee->>'active')::boolean,false) then raise exception 'Selecciona un empleado activo'; end if;
    if not coalesce((item->>'cancelled')::boolean,false) then
      for other in select value from jsonb_array_elements(p_document->'operations'->'shifts') loop
        if (other->>'id')::uuid<>(item->>'id')::uuid and (other->>'employeeID')::uuid=(item->>'employeeID')::uuid and not coalesce((other->>'cancelled')::boolean,false) and (other->>'start')::timestamptz < (item->>'end')::timestamptz and (other->>'end')::timestamptz > (item->>'start')::timestamptz then raise exception 'Conflicto de horarios: %', other->>'id'; end if;
      end loop;
    end if;
    if item->>'clockOut' is not null and (item->>'clockIn' is null or (item->>'clockOut')::timestamptz < (item->>'clockIn')::timestamptz) then raise exception 'Marcaciones inválidas'; end if;
  end loop;
  for previous in select value from jsonb_array_elements(coalesce(old_document->'operations'->'shifts','[]')) loop
    if not exists(select 1 from jsonb_array_elements(p_document->'operations'->'shifts') where (value->>'id')::uuid=(previous->>'id')::uuid) then raise exception 'No se puede borrar el historial de turnos'; end if;
  end loop;
end;
$$;

create or replace function public.save_stations(p_changes jsonb) returns jsonb
language plpgsql security definer set search_path=public as $$
declare item jsonb; result jsonb='[]'; version integer;
begin
  if jsonb_typeof(p_changes) is distinct from 'array' or jsonb_array_length(p_changes)>100 then raise exception 'Solicitud inválida'; end if;
  for item in select value from jsonb_array_elements(p_changes) order by value->>'id' loop
    if not public.can_access_station((item->>'id')::uuid) then raise exception 'Acceso denegado'; end if;
    perform pg_advisory_xact_lock(hashtextextended(item->>'id',0));
    perform public.validate_station_document((item->>'id')::uuid,item->'document');
    version=public.save_station((item->>'id')::uuid,(item->>'revision')::integer,item->'document');
    result=result||jsonb_build_array(jsonb_build_object('id',item->>'id','revision',version));
  end loop;
  return result;
end;
$$;

create or replace function public.assign_manager(p_id uuid,p_station uuid) returns void
language plpgsql security definer set search_path=public as $$
declare previous uuid; manager_name text; branch uuid;
begin
  if not public.is_general() then raise exception 'Acceso denegado'; end if;
  select station_id,name into previous,manager_name from profiles where id=p_id and role='branch' and active for update;
  if not found then raise exception 'Gerente inexistente o inactivo'; end if;
  if p_station is not null and not exists(select 1 from station_documents where id=p_station) then raise exception 'Sucursal inexistente'; end if;
  update profiles set station_id=null where role='branch' and station_id=p_station and id<>p_id;
  update profiles set station_id=p_station where id=p_id;
  for branch in select distinct id from station_documents where id=previous or id=p_station order by id loop
    perform pg_advisory_xact_lock(hashtextextended(branch::text,0));
    update station_documents set document=jsonb_set(document,'{station,gerenteNombre}',to_jsonb(case when id=p_station then manager_name else 'Sin asignar' end)),revision=revision+1,updated_at=now(),updated_by=auth.uid() where id=branch;
    insert into station_audit(station_id,revision,actor,document) select id,revision,auth.uid(),document from station_documents where id=branch;
  end loop;
end;
$$;

create or replace function public.provision_manager(p_id uuid,p_name text,p_station uuid) returns void
language plpgsql security definer set search_path=public as $$
begin
  if not public.is_general() then raise exception 'Acceso denegado'; end if;
  if trim(p_name)='' or not exists(select 1 from auth.users where id=p_id) or exists(select 1 from profiles where id=p_id and role='general') then raise exception 'Cuenta inválida'; end if;
  insert into profiles(id,name,role,active) values(p_id,p_name,'branch',true) on conflict(id) do update set name=p_name,active=true;
  perform public.assign_manager(p_id,p_station);
end;
$$;

create or replace function public.set_manager_active(p_id uuid,p_active boolean) returns void
language plpgsql security definer set search_path=public as $$
begin
  if not public.is_general() then raise exception 'Acceso denegado'; end if;
  if not p_active then perform public.assign_manager(p_id,null); end if;
  update profiles set active=p_active where id=p_id and role='branch';
  if not found then raise exception 'Gerente inexistente'; end if;
end;
$$;
revoke all on function public.validate_station_document(uuid,jsonb),public.save_stations(jsonb),public.assign_manager(uuid,uuid),public.provision_manager(uuid,text,uuid),public.set_manager_active(uuid,boolean) from public,anon,authenticated;
grant execute on function public.save_stations(jsonb),public.assign_manager(uuid,uuid),public.provision_manager(uuid,text,uuid),public.set_manager_active(uuid,boolean) to authenticated;
-- Clients use only the validated batch endpoint.
revoke execute on function public.save_station(uuid,integer,jsonb) from authenticated;
revoke all on function public.save_station(uuid,integer,jsonb) from anon;
notify pgrst,'reload schema';

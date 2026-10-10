-- Execute after 001 and 002. Safe to run again.
begin;
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
    if (previous is null or previous->>'employeeID' is distinct from item->>'employeeID' or previous->>'stationID' is distinct from item->>'stationID' or previous->>'start' is distinct from item->>'start' or previous->>'end' is distinct from item->>'end')
       and ((item->>'start')::timestamptz at time zone 'America/El_Salvador')::date < (now() at time zone 'America/El_Salvador')::date then
      raise exception 'No puedes asignar turnos en una fecha pasada';
    end if;
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

-- Remove application access, retaining Auth identities referenced by historical records.
create or replace function public.delete_manager(p_id uuid) returns void
language plpgsql security definer set search_path=public as $$
declare branch uuid;
begin
  if not public.is_general() then raise exception 'Acceso denegado'; end if;
  select station_id into branch from profiles where id=p_id and role='branch' for update;
  if not found then raise exception 'Solo puedes eliminar gerentes de sucursal'; end if;
  if branch is not null then
    perform pg_advisory_xact_lock(hashtextextended(branch::text,0));
    update station_documents set document=jsonb_set(document,'{station,gerenteNombre}',to_jsonb('Sin asignar'::text)),revision=revision+1,updated_at=now(),updated_by=auth.uid() where id=branch;
    insert into station_audit(station_id,revision,actor,document) select id,revision,auth.uid(),document from station_documents where id=branch;
  end if;
  delete from profiles where id=p_id and role='branch';
end;
$$;
revoke all on function public.delete_manager(uuid),public.validate_station_document(uuid,jsonb) from public,anon,authenticated;
grant execute on function public.delete_manager(uuid) to authenticated;
notify pgrst,'reload schema';
commit;


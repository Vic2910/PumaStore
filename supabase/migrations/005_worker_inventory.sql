-- Apply after 004. Read-only inventory for the employee assigned to this station.
begin;
create or replace function public.worker_context() returns jsonb language plpgsql security definer set search_path=public as $$
declare p profiles; d jsonb; e jsonb;
begin
 select * into p from profiles where id=auth.uid() and active and role in('seller','dispatcher');
 if p.id is null then raise exception 'ACCESS'; end if;
 select document into d from station_documents where id=p.station_id;
 select value into e from jsonb_array_elements(d->'operations'->'employees') where (value->>'id')::uuid=p.employee_id and (value->>'active')::boolean;
 if e is null then raise exception 'EMPLOYEE'; end if;
 if lower(e->>'position')<>(case when p.role='seller' then 'vendedor' else 'despachador' end) then raise exception 'POSITION'; end if;
 return jsonb_build_object('name',d->'station'->>'nombre','tanks',coalesce(d->'station'->'tanks','[]'::jsonb),'products',coalesce((select jsonb_agg(value) from jsonb_array_elements(d->'operations'->'products') where (value->>'active')::boolean),'[]'),
 'services',coalesce((select jsonb_agg(value) from jsonb_array_elements(d->'operations'->'services') where (value->>'available')::boolean),'[]'),
 'shifts',coalesce((select jsonb_agg(value) from jsonb_array_elements(d->'operations'->'shifts') where (value->>'employeeID')::uuid=p.employee_id),'[]'));
end; $$;

revoke all on function public.worker_context() from public,anon;
grant execute on function public.worker_context() to authenticated;
commit;

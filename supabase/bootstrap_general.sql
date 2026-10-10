-- 1. Authentication > Users > Add user > Create new user.
--    Enter YOUR real email/password and enable Auto Confirm User.
-- 2. Replace the email below with exactly that email; execute in SQL Editor.
do $$
declare account uuid;
begin
  select id into account from auth.users where lower(email)=lower('REEMPLAZAR_CON_TU_CORREO');
  if account is null then raise exception 'Primero crea la cuenta en Authentication > Users y reemplaza el correo en este script'; end if;
  insert into public.profiles(id,name,role,active)
  values(account,'Gerente general','general',true)
  on conflict(id) do update set role='general',active=true;
end;
$$;

-- شغّل هذا الملف كاملًا مرة واحدة في Supabase: SQL Editor
-- قبل التشغيل: أنشئ حساب المسؤول يدويًا من Authentication > Users > Add user (بالبريد وكلمة مرور قوية جديدة)

create table if not exists public.tests (
  id bigint generated always as identity primary key,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  rid text not null,
  player text not null,
  data jsonb not null,
  created_at timestamptz not null default now(),
  unique (user_id, rid)
);
create table if not exists public.admins (user_id uuid primary key references auth.users(id) on delete cascade);
create table if not exists public.roster (
  id bigint generated always as identity primary key,
  player text not null unique,
  nid_hash text not null unique,
  code text not null,
  attempts int not null default 0,
  user_id uuid unique references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
alter table public.tests enable row level security;
alter table public.admins enable row level security;
alter table public.roster enable row level security;

create or replace function public.is_admin() returns boolean language sql stable security definer set search_path = public as
$$ select exists (select 1 from public.admins where user_id = auth.uid()) $$;
create or replace function public.my_player() returns text language sql stable security definer set search_path = public as
$$ select player from public.roster where user_id = auth.uid() $$;
create or replace function public.my_role() returns json language sql stable security definer set search_path = public as
$$ select case when public.is_admin() then json_build_object('role','admin')
   else (select json_build_object('role','player','player',player) from public.roster where user_id = auth.uid()) end $$;

create or replace function public.add_player(p_name text, p_nid text) returns text language plpgsql security definer set search_path = public as $$
declare c text := upper(substr(replace(gen_random_uuid()::text,'-',''),1,8));
begin
  if not public.is_admin() then raise exception 'not allowed'; end if;
  if p_nid !~ '^[0-9]{14}$' then raise exception 'bad national id'; end if;
  insert into public.roster(player, nid_hash, code)
  values (p_name, encode(sha256(convert_to(p_nid,'UTF8')),'hex'), c);
  return c;
end $$;

create or replace function public.claim_player(p_nid text, p_code text) returns text language plpgsql security definer set search_path = public as $$
declare r public.roster%rowtype;
begin
  if auth.uid() is null then return null; end if;
  select * into r from public.roster
   where nid_hash = encode(sha256(convert_to(p_nid,'UTF8')),'hex') and user_id is null for update;
  if not found or r.attempts >= 5 then return null; end if;
  if r.code <> p_code then
    update public.roster set attempts = attempts + 1 where id = r.id;
    return null;
  end if;
  update public.roster set user_id = auth.uid() where id = r.id;
  return r.player;
end $$;

revoke all on function public.is_admin(), public.my_player(), public.my_role(),
  public.add_player(text,text), public.claim_player(text,text) from public, anon;
grant execute on function public.is_admin(), public.my_player(), public.my_role(),
  public.add_player(text,text), public.claim_player(text,text) to authenticated;

drop policy if exists "own rows only" on public.tests;
drop policy if exists "admin all tests" on public.tests;
drop policy if exists "player reads own" on public.tests;
drop policy if exists "admin all roster" on public.roster;
create policy "admin all tests" on public.tests for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy "player reads own" on public.tests for select to authenticated
  using (player = public.my_player());
create policy "admin all roster" on public.roster for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- تعيين المسؤول الرئيسي (يجب أن يكون الحساب قد أُنشئ في Authentication أولًا)
insert into public.admins(user_id)
select id from auth.users where email = 'ah.sharshar@phed.usc.edu.eg'
on conflict do nothing;

-- Estrutura aplicada ao projeto Supabase MeuKM (sa-east-1).
-- A migration remota correspondente é 20260904225539_create_meukm_user_data.

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create or replace function private.set_meukm_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

revoke all on function private.set_meukm_updated_at() from public, anon, authenticated;

create table public.meukm_user_data (
  user_id uuid primary key references auth.users(id) on delete cascade,
  data jsonb not null default '{}'::jsonb
    check (jsonb_typeof(data) = 'object'),
  updated_at timestamptz not null default now()
);

alter table public.meukm_user_data enable row level security;
alter table public.meukm_user_data force row level security;

revoke all on table public.meukm_user_data from anon;
grant select, insert, update, delete on table public.meukm_user_data to authenticated;

create policy "users_select_own_meukm_data"
on public.meukm_user_data
for select
to authenticated
using ((select auth.uid()) = user_id);

create policy "users_insert_own_meukm_data"
on public.meukm_user_data
for insert
to authenticated
with check ((select auth.uid()) = user_id);

create policy "users_update_own_meukm_data"
on public.meukm_user_data
for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

create policy "users_delete_own_meukm_data"
on public.meukm_user_data
for delete
to authenticated
using ((select auth.uid()) = user_id);

create trigger set_meukm_user_data_updated_at
before update on public.meukm_user_data
for each row
execute function private.set_meukm_updated_at();

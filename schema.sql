-- =====================================================================
-- Malhan Trading Company — database schema for Supabase
-- Run once: Supabase dashboard → SQL Editor → New query → paste → Run.
--
-- Design
--   • One shop per project. The first person to sign up creates it and
--     becomes the owner; everyone else joins with the shop's join code.
--   • Business records live in one sync-friendly table (records). Each
--     sale, purchase, payment, etc. is one row holding a JSON document.
--     Devices sync by pulling rows changed since their last sync.
--   • Row-level security: people only ever see their own shop's data.
--   • Nothing is hard-deleted; deletes are soft so every device learns
--     about them. Every change is written to audit_log (who, when, what).
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------- Tables ----------------------------------------------------

create table if not exists public.shops (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  join_code   text not null unique default upper(substr(encode(gen_random_bytes(6), 'hex'), 1, 8)),
  created_at  timestamptz not null default now()
);

create table if not exists public.members (
  shop_id       uuid not null references public.shops(id) on delete cascade,
  user_id       uuid not null references auth.users(id) on delete cascade,
  role          text not null check (role in ('owner', 'manager', 'staff')),
  display_name  text not null,
  email         text,
  active        boolean not null default true,
  joined_at     timestamptz not null default now(),
  primary key (shop_id, user_id)
);
create index if not exists members_user on public.members (user_id);

create table if not exists public.records (
  shop_id     uuid not null references public.shops(id) on delete cascade,
  id          text not null,
  collection  text not null check (collection in
                ('products','suppliers','purchases','sales','customers','payments','expenses','adjustments')),
  data        jsonb not null,
  deleted     boolean not null default false,
  created_by  uuid references auth.users(id),
  updated_by  uuid references auth.users(id),
  created_at  timestamptz not null default clock_timestamp(),
  updated_at  timestamptz not null default clock_timestamp(),
  primary key (shop_id, id)
);
create index if not exists records_sync on public.records (shop_id, updated_at);
create index if not exists records_collection on public.records (shop_id, collection);

create table if not exists public.audit_log (
  id          bigint generated always as identity primary key,
  shop_id     uuid not null references public.shops(id) on delete cascade,
  record_id   text not null,
  collection  text not null,
  action      text not null check (action in ('create', 'update', 'delete', 'restore')),
  actor       uuid,
  at          timestamptz not null default clock_timestamp(),
  old_data    jsonb,
  new_data    jsonb
);
create index if not exists audit_shop_at on public.audit_log (shop_id, at desc);

-- ---------- Helpers ---------------------------------------------------

create or replace function public.my_role(s uuid)
returns text language sql stable security definer set search_path = public as $$
  select role from public.members where shop_id = s and user_id = auth.uid() and active
$$;

-- Server owns timestamps and authorship; clients cannot forge them.
create or replace function public.records_stamp()
returns trigger language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    new.created_at := clock_timestamp();
    new.created_by := auth.uid();
  else
    new.shop_id    := old.shop_id;
    new.created_at := old.created_at;
    new.created_by := old.created_by;
  end if;
  new.updated_at := clock_timestamp();
  new.updated_by := auth.uid();
  return new;
end $$;

drop trigger if exists records_stamp on public.records;
create trigger records_stamp before insert or update on public.records
  for each row execute function public.records_stamp();

create or replace function public.records_audit()
returns trigger language plpgsql security definer set search_path = public as $$
declare act text;
begin
  if tg_op = 'INSERT' then act := case when new.deleted then 'delete' else 'create' end;
  elsif new.deleted and not old.deleted then act := 'delete';
  elsif old.deleted and not new.deleted then act := 'restore';
  elsif new.data = old.data then return new;      -- nothing changed
  else act := 'update';
  end if;
  insert into public.audit_log (shop_id, record_id, collection, action, actor, old_data, new_data)
  values (new.shop_id, new.id, new.collection, act, auth.uid(),
          case when tg_op = 'UPDATE' then old.data end, new.data);
  return new;
end $$;

drop trigger if exists records_audit on public.records;
create trigger records_audit after insert or update on public.records
  for each row execute function public.records_audit();

-- ---------- Row-level security ----------------------------------------

alter table public.shops     enable row level security;
alter table public.members   enable row level security;
alter table public.records   enable row level security;
alter table public.audit_log enable row level security;

drop policy if exists shops_read on public.shops;
create policy shops_read on public.shops for select
  using (public.my_role(id) is not null);

drop policy if exists members_read on public.members;
create policy members_read on public.members for select
  using (public.my_role(shop_id) is not null);

drop policy if exists members_owner_update on public.members;
create policy members_owner_update on public.members for update
  using (public.my_role(shop_id) = 'owner' and user_id <> auth.uid())
  with check (public.my_role(shop_id) = 'owner' and role in ('manager', 'staff'));

drop policy if exists records_read on public.records;
create policy records_read on public.records for select
  using (public.my_role(shop_id) is not null);

drop policy if exists records_insert on public.records;
create policy records_insert on public.records for insert
  with check (public.my_role(shop_id) is not null);

-- Owners and managers can change anything. Staff can change or delete
-- only their own entries, and only within 24 hours of creating them.
drop policy if exists records_update on public.records;
create policy records_update on public.records for update
  using (
    public.my_role(shop_id) in ('owner', 'manager')
    or (public.my_role(shop_id) = 'staff'
        and created_by = auth.uid()
        and created_at > now() - interval '24 hours')
  )
  with check (public.my_role(shop_id) is not null);

drop policy if exists audit_read on public.audit_log;
create policy audit_read on public.audit_log for select
  using (public.my_role(shop_id) in ('owner', 'manager'));

-- No delete policies: rows are soft-deleted (deleted = true).

-- ---------- Functions the app calls -----------------------------------

create or replace function public.create_shop(shop_name text, owner_name text)
returns uuid language plpgsql security definer set search_path = public as $$
declare sid uuid;
begin
  if auth.uid() is null then raise exception 'Please sign in first'; end if;
  if exists (select 1 from public.shops) then
    raise exception 'This shop is already set up. Ask the owner for the join code.';
  end if;
  insert into public.shops (name) values (trim(shop_name)) returning id into sid;
  insert into public.members (shop_id, user_id, role, display_name, email)
  values (sid, auth.uid(), 'owner', trim(owner_name), auth.jwt() ->> 'email');
  return sid;
end $$;

create or replace function public.join_shop(code text, member_name text)
returns uuid language plpgsql security definer set search_path = public as $$
declare sid uuid;
begin
  if auth.uid() is null then raise exception 'Please sign in first'; end if;
  select id into sid from public.shops where join_code = upper(trim(code));
  if sid is null then raise exception 'That join code is not correct'; end if;
  if exists (select 1 from public.members where shop_id = sid and user_id = auth.uid() and not active) then
    raise exception 'Your access was removed. Please contact the owner.';
  end if;
  insert into public.members (shop_id, user_id, role, display_name, email)
  values (sid, auth.uid(), 'staff', trim(member_name), auth.jwt() ->> 'email')
  on conflict (shop_id, user_id) do nothing;
  return sid;
end $$;

create or replace function public.rotate_join_code()
returns text language plpgsql security definer set search_path = public as $$
declare sid uuid; newcode text;
begin
  select shop_id into sid from public.members where user_id = auth.uid() and role = 'owner' and active;
  if sid is null then raise exception 'Only the owner can change the join code'; end if;
  newcode := upper(substr(encode(gen_random_bytes(6), 'hex'), 1, 8));
  update public.shops set join_code = newcode where id = sid;
  return newcode;
end $$;

revoke all on function public.create_shop(text, text) from public, anon;
revoke all on function public.join_shop(text, text) from public, anon;
revoke all on function public.rotate_join_code() from public, anon;
grant execute on function public.create_shop(text, text) to authenticated;
grant execute on function public.join_shop(text, text) to authenticated;
grant execute on function public.rotate_join_code() to authenticated;

-- ---------- Reporting view (for SQL / spreadsheets) -------------------

create or replace view public.sale_lines with (security_invoker = true) as
select r.shop_id,
       r.id                          as sale_id,
       (r.data ->> 'date')::date     as sale_date,
       r.data ->> 'customerId'       as customer_id,
       i ->> 'productId'             as product_id,
       (i ->> 'qty')::numeric        as bags,
       (i ->> 'rate')::numeric       as rate,
       (i ->> 'cost')::numeric       as cost_per_bag,
       ((i ->> 'qty')::numeric * ((i ->> 'rate')::numeric - coalesce((i ->> 'cost')::numeric, 0))) as profit,
       r.created_by
from public.records r
cross join lateral jsonb_array_elements(r.data -> 'items') i
where r.collection = 'sales' and not r.deleted;

-- ---------- Realtime --------------------------------------------------

do $$ begin
  alter publication supabase_realtime add table public.records;
exception when duplicate_object then null; when undefined_object then null;
end $$;

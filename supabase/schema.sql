-- CardioLife — структура базы данных (Supabase / PostgreSQL)
--
-- КАК ПРИМЕНИТЬ:
-- 1. Откройте свой проект на supabase.com
-- 2. Слева: SQL Editor → New query
-- 3. Вставьте сюда весь этот файл целиком → Run
--
-- Это создаёт таблицы пользователей и анализов и настраивает безопасный
-- доступ (Row Level Security): каждый пациент видит только свои данные,
-- а врач (роль 'doctor') видит всё.

-- ========================================================================
-- ПРОФИЛИ ПОЛЬЗОВАТЕЛЕЙ
-- ========================================================================
create table if not exists public.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  full_name  text,
  phone      text,
  role       text not null default 'patient',   -- 'patient' | 'doctor'
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

-- Проверка «текущий пользователь — врач?».
-- SECURITY DEFINER читает таблицу в обход RLS, чтобы не было рекурсии в политиках.
create or replace function public.is_doctor()
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'doctor'
  );
$$;

drop policy if exists "profiles_select" on public.profiles;
create policy "profiles_select" on public.profiles
  for select using (auth.uid() = id or public.is_doctor());

drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own" on public.profiles
  for insert with check (auth.uid() = id);

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own" on public.profiles
  for update using (auth.uid() = id);

-- Автоматически создавать профиль при регистрации.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, phone)
  values (
    new.id,
    new.raw_user_meta_data ->> 'full_name',
    new.raw_user_meta_data ->> 'phone'
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ========================================================================
-- АНАЛИЗЫ (ЭКГ / ЭхоКГ / кровь)
-- ========================================================================
create table if not exists public.analyses (
  id             uuid primary key default gen_random_uuid(),
  patient_id     uuid not null references auth.users(id) on delete cascade,
  type           text not null,                   -- 'ecg' | 'echo' | 'blood'
  input          jsonb,                            -- данные, введённые пациентом
  ai_result      jsonb,                            -- черновик заключения от ИИ
  status         text not null default 'pending',  -- 'pending' | 'reviewed' | 'sent'
  doctor_comment text,
  created_at     timestamptz not null default now(),
  reviewed_at    timestamptz
);

alter table public.analyses enable row level security;

drop policy if exists "analyses_select" on public.analyses;
create policy "analyses_select" on public.analyses
  for select using (auth.uid() = patient_id or public.is_doctor());

drop policy if exists "analyses_insert_own" on public.analyses;
create policy "analyses_insert_own" on public.analyses
  for insert with check (auth.uid() = patient_id);

drop policy if exists "analyses_doctor_update" on public.analyses;
create policy "analyses_doctor_update" on public.analyses
  for update using (public.is_doctor());

-- ========================================================================
-- НАЗНАЧИТЬ ВРАЧА
-- После того как Dr. Севара зарегистрируется обычным образом, выполните
-- (подставив её email вместо примера), чтобы дать ей роль врача:
--
--   update public.profiles set role = 'doctor'
--   where id = (select id from auth.users where email = 'sevara@cardiolife.kz');
-- ========================================================================

-- CardioLife — структура базы данных (Supabase / PostgreSQL)
-- БЕЗОПАСНО для общего / существующего проекта: все объекты с префиксом cardio_,
-- ничего чужого не трогаем и не удаляем.
--
-- КАК ПРИМЕНИТЬ:
-- 1. Откройте нужный проект на supabase.com
-- 2. Слева: SQL Editor → New query
-- 3. Вставьте этот файл целиком → Run (должно написать Success)

-- ========================================================================
-- ПРОФИЛИ ПОЛЬЗОВАТЕЛЕЙ CardioLife
-- ========================================================================
create table if not exists public.cardio_profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  full_name  text,
  phone      text,
  role       text not null default 'patient',   -- 'patient' | 'doctor'
  created_at timestamptz not null default now()
);

alter table public.cardio_profiles enable row level security;

-- «Текущий пользователь — врач?» (security definer — без рекурсии в политиках)
create or replace function public.cardio_is_doctor()
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.cardio_profiles
    where id = auth.uid() and role = 'doctor'
  );
$$;

drop policy if exists "cardio_profiles_select" on public.cardio_profiles;
create policy "cardio_profiles_select" on public.cardio_profiles
  for select using (auth.uid() = id or public.cardio_is_doctor());

drop policy if exists "cardio_profiles_insert_own" on public.cardio_profiles;
create policy "cardio_profiles_insert_own" on public.cardio_profiles
  for insert with check (auth.uid() = id);

drop policy if exists "cardio_profiles_update_own" on public.cardio_profiles;
create policy "cardio_profiles_update_own" on public.cardio_profiles
  for update using (auth.uid() = id);

-- Автосоздание профиля при регистрации (уникальное имя триггера — чужие не трогаем)
create or replace function public.cardio_handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.cardio_profiles (id, full_name, phone)
  values (
    new.id,
    new.raw_user_meta_data ->> 'full_name',
    new.raw_user_meta_data ->> 'phone'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_cardio on auth.users;
create trigger on_auth_user_created_cardio
  after insert on auth.users
  for each row execute function public.cardio_handle_new_user();

-- ========================================================================
-- АНАЛИЗЫ (ЭКГ / ЭхоКГ / кровь)
-- ========================================================================
create table if not exists public.cardio_analyses (
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

alter table public.cardio_analyses enable row level security;

drop policy if exists "cardio_analyses_select" on public.cardio_analyses;
create policy "cardio_analyses_select" on public.cardio_analyses
  for select using (auth.uid() = patient_id or public.cardio_is_doctor());

drop policy if exists "cardio_analyses_insert_own" on public.cardio_analyses;
create policy "cardio_analyses_insert_own" on public.cardio_analyses
  for insert with check (auth.uid() = patient_id);

drop policy if exists "cardio_analyses_doctor_update" on public.cardio_analyses;
create policy "cardio_analyses_doctor_update" on public.cardio_analyses
  for update using (public.cardio_is_doctor());

-- ========================================================================
-- НАЗНАЧИТЬ ВРАЧА
-- После того как Dr. Севара зарегистрируется в приложении, выполните
-- (подставив её email), чтобы дать ей роль врача:
--
--   update public.cardio_profiles set role = 'doctor'
--   where id = (select id from auth.users where email = 'sevara@cardiolife.kz');
-- ========================================================================

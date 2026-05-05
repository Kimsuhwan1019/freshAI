-- FreshAI Supabase Schema
-- Supabase SQL Editor에서 실행하세요

-- 식재료 테이블 생성
create table if not exists public.ingredients (
  id          uuid default gen_random_uuid() primary key,
  user_id     uuid references auth.users(id) on delete cascade not null,
  name        text not null,
  quantity    numeric,
  unit        text,
  category    text check (category in ('채소','과일','육류','어류','유제품','곡류','조미료','음료','기타')),
  expiry_date date,
  created_at  timestamptz default now() not null,
  updated_at  timestamptz default now() not null
);

-- Row Level Security 활성화
alter table public.ingredients enable row level security;

-- RLS 정책: 본인 데이터만 접근 가능
create policy "select_own" on public.ingredients
  for select using (auth.uid() = user_id);

create policy "insert_own" on public.ingredients
  for insert with check (auth.uid() = user_id);

create policy "update_own" on public.ingredients
  for update using (auth.uid() = user_id);

create policy "delete_own" on public.ingredients
  for delete using (auth.uid() = user_id);

-- updated_at 자동 업데이트 트리거
create or replace function public.handle_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger ingredients_updated_at
  before update on public.ingredients
  for each row execute function public.handle_updated_at();

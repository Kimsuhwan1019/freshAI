-- Supabase 대시보드 > SQL Editor 에서 이 파일 전체를 실행하세요.

-- 1. 테이블 생성
create table if not exists public.keep_alive (
  id         int8        generated always as identity primary key,
  last_ping  timestamptz not null default now()
);

-- 2. RLS 활성화
alter table public.keep_alive enable row level security;

-- 3. anon 역할 SELECT 허용
create policy "anon can select keep_alive"
  on public.keep_alive
  for select
  to anon
  using (true);

-- 4. 초기 행 삽입 (없을 때만)
insert into public.keep_alive (last_ping)
select now()
where not exists (select 1 from public.keep_alive);

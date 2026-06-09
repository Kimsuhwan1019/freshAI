# FreshAI

스마트 냉장고 식재료 관리 앱 (Flutter · Supabase · GPT-4o)

## GitHub Secrets 등록

**GitHub 시크릿 등록**: 저장소 → Settings → Secrets and variables → Actions → New repository secret → `SUPABASE_ANON_KEY` 에 Supabase 프로젝트의 anon public key 값 입력.

## Supabase Keep-Alive 설정

무료 플랜 7일 자동 일시정지 방지용 테이블 초기 설정:

1. [Supabase 대시보드](https://app.supabase.com) → SQL Editor
2. `supabase/keep_alive.sql` 내용 실행

이후 GitHub Actions가 2일마다 자동으로 ping을 보냅니다.

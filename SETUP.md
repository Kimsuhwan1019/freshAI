# FreshAI 설정 가이드

## 1. 환경 변수 설정

`.env.example` 파일을 복사해서 `.env` 파일을 만들고 실제 API 키를 입력하세요.

```bash
cp .env.example .env
```

`.env` 파일 내용:
```
UNSPLASH_ACCESS_KEY=your_unsplash_access_key_here
OPENAI_API_KEY=your_openai_api_key_here
```

- **Unsplash API 키** (무료): https://unsplash.com/developers 에서 발급
- **OpenAI API 키**: https://platform.openai.com/api-keys 에서 발급

> ⚠️ `.env` 파일은 `.gitignore`에 등록되어 있어 GitHub에 업로드되지 않습니다.

---

## 2. Supabase 데이터베이스 설정

Supabase 콘솔(https://supabase.com/dashboard)에 접속하여:
1. 프로젝트 선택 → SQL Editor 열기
2. `supabase/schema.sql` 파일 내용을 복사하여 실행

---

## 3. 앱 빌드 및 실행

```bash
# 패키지 설치
flutter pub get

# Android / Galaxy Tab 실행
flutter run

# APK 빌드
flutter build apk --debug
```

---

## 4. 주요 기능

| 기능 | 설명 |
|------|------|
| 📸 냉장고 촬영 | GPT-4o Vision으로 식재료 자동 인식 |
| 🥕 식재료 관리 | 추가 / 수정 / 삭제, 카테고리 · 수량 · 유통기한 관리 |
| ⏰ 유통기한 알림 | 앱 실행 시 3일 이내 만료 식재료 알림 |
| 🍳 AI 레시피 추천 | 보유 식재료 선택 → GPT-4o 맞춤 레시피 생성 |
| ❤️ 즐겨찾기 | 마음에 드는 레시피 저장 (로컬 영구 보관) |
| 📋 히스토리 | 이전 추천 레시피 최대 5개 기록 |
| 🖼️ 음식 이미지 | Unsplash API로 식재료·레시피 이미지 자동 표시 |

---

## 5. 프로젝트 구조

```
lib/
  main.dart                          # 앱 진입점 · 다크 테마 · dotenv 로드
  config.dart                        # 환경 변수 접근 (AppConfig)
  models/
    ingredient.dart                  # 식재료 데이터 모델
  services/
    auth_service.dart                # 인증 서비스
    ingredient_service.dart          # 식재료 CRUD (Supabase)
    openai_service.dart              # GPT-4o Vision · 레시피 추천
    unsplash_service.dart            # 식재료·레시피 이미지 검색
  utils/
    expiry_utils.dart                # D-day 계산 · 유통기한 색상
  screens/
    auth/
      login_screen.dart              # 로그인
      signup_screen.dart             # 회원가입
    home_screen.dart                 # 하단 탭 · 유통기한 알림
    ingredients/
      ingredients_screen.dart        # 식재료 그리드 (Unsplash 이미지)
      ingredient_form_screen.dart    # 추가 / 수정 폼 · D-day 미리보기
    camera/
      camera_screen.dart             # 카메라 촬영 · AI 인식
    recipes/
      recipe_screen.dart             # 레시피 추천 · 즐겨찾기 · 히스토리
    settings/
      settings_screen.dart           # 프로필 · 로그아웃
supabase/
  schema.sql                         # DB 테이블 생성 SQL
.env.example                         # 환경 변수 템플릿
```

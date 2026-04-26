# Fitness Tracker — ДЗ №3 (Вариант 14)

Приложение для отслеживания тренировок, аналог [MyFitnessPal](https://www.myfitnesspal.com/).  
Стек: **FastAPI** + **asyncpg** + **PostgreSQL 16**

---

## Схема базы данных

```
┌─────────────┐       ┌──────────────────┐       ┌────────────────────┐
│    users    │       │    workouts      │       │ workout_exercises  │
│─────────────│       │──────────────────│       │────────────────────│
│ id (PK)     │──┐    │ id (PK)          │──┐    │ id (PK)            │
│ login       │  └──▶ │ user_id (FK)     │  └──▶ │ workout_id (FK)    │
│ first_name  │       │ title            │       │ exercise_id (FK)   │
│ last_name   │       │ notes            │       │ sets               │
│ email       │       │ started_at       │       │ reps               │
│ password_   │       │ ended_at         │       │ weight_kg          │
│   hash      │       │ created_at       │       │ duration_s         │
│ created_at  │       └──────────────────┘       │ distance_m         │
└─────────────┘                                  │ order_index        │
                                                 └────────────────────┘
                                                         │
                                                         ▼
                                                 ┌──────────────────┐
                                                 │    exercises     │
                                                 │──────────────────│
                                                 │ id (PK)          │
                                                 │ name             │
                                                 │ description      │
                                                 │ muscle_group     │
                                                 │ equipment        │
                                                 │ created_at       │
                                                 └──────────────────┘
```

### Таблицы

| Таблица | Описание |
|---------|----------|
| `users` | Пользователи системы |
| `exercises` | Справочник упражнений |
| `workouts` | Тренировки пользователей |
| `workout_exercises` | Упражнения, выполненные в тренировке |

---

## Запуск

### Через Docker Compose (рекомендуется)

```bash
# 1. Клонировать репозиторий
git clone <repo_url> && cd fitness-tracker

# 2. Запустить всё
docker compose up --build -d

# 3. API доступен по адресу
open http://localhost:8000/docs
```

PostgreSQL при первом запуске автоматически выполнит `schema.sql` и `data.sql`.

### Локальный запуск (без Docker)

```bash
# 1. Создать БД PostgreSQL
createdb fitness_db
psql fitness_db < schema.sql
psql fitness_db < data.sql

# 2. Установить зависимости
cd api
pip install -r requirements.txt

# 3. Запустить API
DATABASE_URL=postgresql://user:pass@localhost/fitness_db uvicorn main:app --reload
```

---

## API Endpoints

| Метод | URL | Описание |
|-------|-----|---------|
| `POST` | `/users/` | Создание пользователя |
| `GET` | `/users/by-login/{login}` | Поиск по логину |
| `GET` | `/users/search?q=Иван` | Поиск по маске имени/фамилии |
| `POST` | `/exercises/` | Создание упражнения |
| `GET` | `/exercises/` | Список упражнений |
| `GET` | `/exercises/?muscle_group=back` | Фильтрация по группе мышц |
| `POST` | `/workouts/` | Создание тренировки |
| `POST` | `/workouts/{id}/exercises` | Добавить упражнение в тренировку |
| `GET` | `/workouts/users/{user_id}/history` | История тренировок |
| `GET` | `/workouts/users/{user_id}/stats?from_date=...&to_date=...` | Статистика за период |

Интерактивная документация: **http://localhost:8000/docs**

---

## Файлы проекта

```
fitness-tracker/
├── schema.sql          # DDL: таблицы + индексы
├── data.sql            # Тестовые данные (12+ пользователей, 15 упражнений, 12 тренировок)
├── queries.sql         # SQL-запросы для всех API-операций
├── optimization.md     # Анализ EXPLAIN, описание индексов
├── docker-compose.yaml # PostgreSQL + API
├── README.md           # Этот файл
├── Dockerfile
├── requirements.txt
├── main.py          # FastAPI приложение
└── routers/
    ├── users.py     # POST /users, GET /users/by-login, GET /users/search
    ├── exercises.py # POST /exercises, GET /exercises
    └── workouts.py  # POST /workouts, POST /workouts/:id/exercises,
                      # GET /workouts/users/:id/history,
                      # GET /workouts/users/:id/stats
```

---

## Примеры запросов

```bash
# Создать пользователя
curl -X POST http://localhost:8000/users/ \
  -H "Content-Type: application/json" \
  -d '{"login":"kasem",
"first_name":"kasem",
"last_name":"alkhalaf",
"email":"kasem@gmail.com",
"password":"secret"}'
![Создать пользователя](images/create_user.png)

# Найти по логину
curl http://localhost:8000/users/by-login/kasem
![Найти по логину](images/get_user_login.png)

# Поиск по имени
curl "http://localhost:8000/users/search?q=Иван"
![Поиск по имени](images/get_user_by_name.png)

# Статистика за декабрь 2024
curl "http://localhost:8000/workouts/users/53654566-31a1-44fe-98e6-168dca4380ca/stats?from_date=2024-12-01T00:00:00&to_date=2025-01-01T00:00:00"
![Статистика](images/get_status.png)
```

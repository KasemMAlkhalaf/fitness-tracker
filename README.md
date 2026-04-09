# Fitness Tracker — Домашнее задание 03

Вариант 14: Фитнес-трекер (аналог MyFitnessPal)

---

## Схема базы данных

### Сущности

```
users ──────────< workouts >──── workout_exercises >── exercises
                                     (связующая)
```

| Таблица | Назначение |
|---|---|
| `users` | Пользователи приложения |
| `exercises` | Справочник упражнений |
| `workouts` | Тренировочные сессии |
| `workout_exercises` | Упражнения внутри тренировки (M:M) |

### Ключевые решения

- `workouts.duration_sec` — вычисляемая колонка (`GENERATED ALWAYS AS`), не требует ручного обновления
- `pg_trgm` + GIN-индексы — для поиска по маске имени/фамилии (`ILIKE '%...%'`)
- Составной индекс `(user_id, started_at DESC)` — покрывает оба типа запросов: история и статистика за период
- Частичный индекс на `exercises.is_public WHERE TRUE` — меньше размер, выше скорость

---

## Запуск

### Быстрый старт (Docker Compose)

```bash
git clone <your-repo>
cd fitness-tracker
docker-compose up --build
```

API доступен на `http://localhost:8080`
PostgreSQL доступен на `localhost:5432` (user: fitness, password: fitness, db: fitness)

### Только база данных (без Docker)

```bash
psql -U postgres -c "CREATE DATABASE fitness;"
psql -U postgres -d fitness -f schema.sql
psql -U postgres -d fitness -f data.sql
```

---

## API Endpoints

| Метод | URL | Описание |
|---|---|---|
| POST | `/users` | Создание пользователя |
| GET | `/users/by-login/{login}` | Поиск по логину |
| GET | `/users/search?first_name=Ив&last_name=Пет` | Поиск по маске имени |
| POST | `/exercises` | Создание упражнения |
| GET | `/exercises?category=strength&page=1` | Список упражнений |
| POST | `/workouts` | Создание тренировки |
| POST | `/workouts/{id}/exercises` | Добавление упражнения в тренировку |
| GET | `/users/{id}/workouts?page=1` | История тренировок |
| GET | `/users/{id}/workouts/stats?from=2024-01-01&to=2024-01-31` | Статистика за период |

### Примеры запросов

```bash
# Создать пользователя
curl -X POST http://localhost:8080/users \
  -H "Content-Type: application/json" \
  -d '{"login":"test_user","first_name":"Тест","last_name":"Пользователь","email":"test@example.com","password_hash":"hash123"}'

# Поиск по логину
curl http://localhost:8080/users/by-login/ivan_petrov

# Поиск по маске фамилии
curl "http://localhost:8080/users/search?last_name=Пет"

# Создать упражнение
curl -X POST http://localhost:8080/exercises \
  -H "Content-Type: application/json" \
  -d '{"name":"Тяга блока","category":"strength","muscle_group":"Спина","is_public":true,"created_by":1}'

# Создать тренировку
curl -X POST http://localhost:8080/workouts \
  -H "Content-Type: application/json" \
  -d '{"user_id":1,"title":"Силовая тренировка","started_at":"2024-01-20T09:00:00Z","finished_at":"2024-01-20T10:15:00Z","calories_burned":500}'

# Добавить упражнение в тренировку
curl -X POST http://localhost:8080/workouts/1/exercises \
  -H "Content-Type: application/json" \
  -d '{"exercise_id":1,"sets":4,"reps":10,"weight_kg":100}'

# История тренировок
curl "http://localhost:8080/users/1/workouts?page=1&page_size=10"

# Статистика за январь 2024
curl "http://localhost:8080/users/1/workouts/stats?from=2024-01-01&to=2024-01-31"
```

---

## Структура файлов

```
fitness-tracker/
├── schema.sql          # DDL: CREATE TABLE + индексы
├── data.sql            # Тестовые данные (12+ записей в каждой таблице)
├── queries.sql         # SQL запросы для всех операций API
├── optimization.md     # Оптимизации + EXPLAIN планы
├── docker-compose.yaml # Запуск API + PostgreSQL
├── README.md           # Этот файл
└── main.go             #  Go API (gorilla/mux +  libpq)
└── go.mod 
└── go.sum        
└── Dockerfile
```

---

## Технологии

- **PostgreSQL 16** — СУБД
- **Go 1.21** — язык API
- **gorilla/mux** — HTTP роутер
- **lib/pq** — PostgreSQL драйвер для Go
- **pg_trgm** — расширение PostgreSQL для trigram-поиска
- **Docker + Docker Compose** — контейнеризация

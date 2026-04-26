# 🏋️ Fitness Tracker — ДЗ №3 (Вариант 14)

![Python](https://img.shields.io/badge/Python-3.12+-blue.svg)
![FastAPI](https://img.shields.io/badge/FastAPI-Async-green)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-blue)
![Docker](https://img.shields.io/badge/Docker-Enabled-2496ED)
![License](https://img.shields.io/badge/License-Educational-lightgrey)
![Status](https://img.shields.io/badge/Status-Active-success)

Современное API-приложение для отслеживания тренировок пользователей (аналог MyFitnessPal), построенное на асинхронном стеке.

---

## 🚀 Возможности

* 👤 Управление пользователями
* 💪 Каталог упражнений
* 🏋️ Создание тренировок
* 📊 История и статистика
* ⚡ Высокая производительность (async + PostgreSQL)

---

## 🛠️ Технологии

* **FastAPI** — современный async backend
* **asyncpg** — быстрый PostgreSQL драйвер
* **PostgreSQL 16** — база данных
* **Docker** — контейнеризация

---

## 📊 Схема базы данных

```text
┌─────────────┐       ┌──────────────────┐       ┌────────────────────┐
│    users    │       │    workouts      │       │ workout_exercises  │
│─────────────│       │──────────────────│       │────────────────────│
│ id (PK)     │──┐    │ id (PK)          │──┐    │ id (PK)            │
│ login       │  └──▶ │ user_id (FK)     │  └──▶│ workout_id (FK)    │
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

---

## 🧩 Структура проекта

```bash
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

## ⚡ Быстрый старт

### 🐳 Docker (рекомендуется)

```bash
git clone <repo_url>
cd fitness-tracker
docker compose up --build -d
```

👉 API:

```
http://localhost:8000/docs
```

---

### 💻 Локальный запуск

```bash
createdb fitness_db
psql fitness_db < schema.sql
psql fitness_db < data.sql

pip install -r requirements.txt

DATABASE_URL=postgresql://user:pass@localhost/fitness_db uvicorn main:app --reload
```

---

## 🔗 API Endpoints

| Метод | Endpoint                            | Описание              |
| ----- | ----------------------------------- | --------------------- |
| POST  | `/users/`                           | Создание пользователя |
| GET   | `/users/by-login/{login}`           | Поиск по логину       |
| GET   | `/users/search?q=...`               | Поиск по имени        |
| POST  | `/exercises/`                       | Создать упражнение    |
| GET   | `/exercises/`                       | Список упражнений     |
| GET   | `/exercises/?muscle_group=...`      | Фильтр                |
| POST  | `/workouts/`                        | Создать тренировку    |
| POST  | `/workouts/{id}/exercises`          | Добавить упражнение   |
| GET   | `/workouts/users/{user_id}/history` | История               |
| GET   | `/workouts/users/{user_id}/stats`   | Статистика            |

📘 Swagger:

```
http://localhost:8000/docs
```

---

## 🧪 Примеры использования

### ➤ Создание пользователя

```bash
curl -X POST http://localhost:8000/users/ \
  -H "Content-Type: application/json" \
  -d '{"login":"kasem","first_name":"kasem","last_name":"alkhalaf","email":"kasem@gmail.com","password":"secret"}'
```
![Создать пользователя](images/create_user.png)

### ➤ Поиск по логину

```bash
curl http://localhost:8000/users/by-login/kasem
```
![Найти по логину](images/get_user_login.png)

### ➤ Статистика

```bash
curl "http://localhost:8000/workouts/users/{user_id}/stats?from_date=2024-12-01T00:00:00&to_date=2025-01-01T00:00:00"
```
![Поиск по имени](images/get_user_by_name.png)
---

## 📈 Производительность

* Используются индексы для ускорения запросов
* Анализ выполнен через `EXPLAIN` (см. `optimization.md`)
* Асинхронная обработка соединений

---
![Статистика](images/get_status.png)

## 📌 Дополнительно

* 📄 `queries.sql` — SQL логика
* 🧪 `data.sql` — тестовые данные
* 📊 `optimization.md` — оптимизация

---

## 👨‍💻 Автор

**Альхалаф Касем**

---

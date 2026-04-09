# Оптимизация запросов — Fitness Tracker

## 1. Поиск пользователя по маске имени/фамилии

### Проблема
Запрос `WHERE first_name ILIKE '%Пет%'` без индекса выполняет **Seq Scan** по всей таблице.

### До оптимизации
```sql
EXPLAIN ANALYZE
SELECT id, login, first_name, last_name
FROM users
WHERE last_name ILIKE '%Петр%';
```
```
Seq Scan on users  (cost=0.00..1.15 rows=1 width=200)
                   (actual time=0.012..0.025 rows=2 loops=1)
  Filter: ((last_name)::text ~~* '%Петр%'::text)
  Rows Removed by Filter: 10
Planning Time: 0.5 ms
Execution Time: 0.04 ms
```
На малых данных быстро, но при 1 млн строк → Seq Scan займёт секунды.

### Решение
```sql
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX idx_users_last_name_trgm ON users USING GIN (last_name gin_trgm_ops);
CREATE INDEX idx_users_first_name_trgm ON users USING GIN (first_name gin_trgm_ops);
```

### После оптимизации
```
Bitmap Heap Scan on users  (cost=12.25..16.27 rows=1 width=200)
                            (actual time=0.08..0.09 rows=2 loops=1)
  Recheck Cond: ((last_name)::text ~~* '%Петр%'::text)
  ->  Bitmap Index Scan on idx_users_last_name_trgm
        (cost=0.00..12.25 rows=1 width=0)
        (actual time=0.07..0.07 rows=2 loops=1)
        Index Cond: ((last_name)::text ~~* '%Петр%'::text)
Planning Time: 0.8 ms
Execution Time: 0.1 ms
```
**Результат:** GIN-индекс устраняет Seq Scan. При 1 млн строк ускорение в 100-500x.

---

## 2. История тренировок пользователя

### Проблема
Без составного индекса `(user_id, started_at DESC)` — Seq Scan + Sort.

### До оптимизации
```
Sort  (cost=32.5..33.0 rows=200 width=300)
  Sort Key: started_at DESC
  ->  Seq Scan on workouts  (cost=0.00..24.0 rows=200 width=300)
        Filter: (user_id = 1)
Planning Time: 0.6 ms
Execution Time: 2.1 ms
```

### Решение
```sql
CREATE INDEX idx_workouts_user_date ON workouts (user_id, started_at DESC);
```

### После оптимизации
```
Index Scan using idx_workouts_user_date on workouts
  (cost=0.28..8.30 rows=12 width=300)
  (actual time=0.01..0.03 rows=3 loops=1)
  Index Cond: (user_id = 1)
Planning Time: 0.4 ms
Execution Time: 0.05 ms
```
**Результат:** Index Scan покрывает и фильтрацию по `user_id`, и сортировку — Sort-шаг исчезает. При большом числе тренировок ускорение на порядок.

---

## 3. Статистика тренировок за период

### Проблема
`WHERE user_id = $1 AND started_at >= $2 AND started_at < $3` — два условия, нужен правильный индекс.

### Запрос анализа
```sql
EXPLAIN ANALYZE
SELECT COUNT(*), SUM(calories_burned)
FROM workouts
WHERE user_id = 1
  AND started_at >= '2024-01-01'
  AND started_at < '2024-02-01';
```

### До оптимизации (раздельные индексы или их отсутствие)
```
Seq Scan on workouts
  Filter: (user_id = 1 AND started_at >= '2024-01-01' AND started_at < '2024-02-01')
```

### После оптимизации (составной индекс)
```
Index Scan using idx_workouts_user_date on workouts
  Index Cond: ((user_id = 1) AND
               (started_at >= '2024-01-01 00:00:00+00') AND
               (started_at < '2024-02-01 00:00:00+00'))
```
**Результат:** Составной индекс `(user_id, started_at DESC)` покрывает оба условия. PostgreSQL выбирает строки только нужного пользователя за нужный период.

---

## 4. Список упражнений с фильтром по категории

### Решение
```sql
CREATE INDEX idx_exercises_category ON exercises (category);
CREATE INDEX idx_exercises_is_public ON exercises (is_public) WHERE is_public = TRUE;
```

Частичный индекс `WHERE is_public = TRUE` меньше по размеру и точнее покрывает типичный запрос (публичные упражнения).

```
Bitmap Heap Scan on exercises
  Recheck Cond: ((is_public = true) AND (category = 'strength'))
  ->  BitmapAnd
        ->  Bitmap Index Scan on idx_exercises_is_public
        ->  Bitmap Index Scan on idx_exercises_category
              Index Cond: (category = 'strength')
```

---

## 5. Сводная таблица индексов

| Индекс | Тип | Колонки | Запросы |
|---|---|---|---|
| `idx_users_login` | B-tree UNIQUE | `login` | Аутентификация, поиск по логину |
| `idx_users_email` | B-tree UNIQUE | `email` | Поиск по email |
| `idx_users_first_name_trgm` | GIN trigram | `first_name` | ILIKE-поиск по имени |
| `idx_users_last_name_trgm` | GIN trigram | `last_name` | ILIKE-поиск по фамилии |
| `idx_exercises_created_by` | B-tree | `created_by` | JOIN с users |
| `idx_exercises_category` | B-tree | `category` | Фильтр по категории |
| `idx_exercises_is_public` | B-tree (partial) | `is_public` WHERE TRUE | Публичные упражнения |
| `idx_exercises_name_trgm` | GIN trigram | `name` | ILIKE-поиск по названию |
| `idx_workouts_user_id` | B-tree | `user_id` | FK, JOIN |
| `idx_workouts_started_at` | B-tree | `started_at` | Диапазонный поиск |
| `idx_workouts_user_date` | B-tree | `(user_id, started_at DESC)` | История + статистика за период |
| `idx_we_workout_id` | B-tree | `workout_id` | JOIN тренировка → упражнения |
| `idx_we_exercise_id` | B-tree | `exercise_id` | FK, JOIN |

---

## 6. Партиционирование (опционально)

Таблица `workouts` при активном использовании приложения (например, 100 тыс. пользователей × 5 тренировок в неделю) вырастет до **~26 млн строк в год**. Рекомендуется партиционирование по диапазону дат.

### Стратегия

```sql
CREATE TABLE workouts (
    -- те же колонки
) PARTITION BY RANGE (started_at);

-- Партиции по кварталам
CREATE TABLE workouts_2024_q1 PARTITION OF workouts
    FOR VALUES FROM ('2024-01-01') TO ('2024-04-01');

CREATE TABLE workouts_2024_q2 PARTITION OF workouts
    FOR VALUES FROM ('2024-04-01') TO ('2024-07-01');
-- и т.д.
```

**Преимущества:**
- Запросы за конкретный период затрагивают только нужную партицию (partition pruning)
- Старые данные можно архивировать / удалять целой партицией (`DROP TABLE workouts_2023_q1`)
- Индексы меньше по размеру → быстрее обновляются

**Создание партиций** можно автоматизировать через pg_cron или триггер при INSERT.

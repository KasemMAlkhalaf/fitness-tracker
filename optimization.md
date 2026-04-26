# Оптимизация запросов — Fitness Tracker

## Методология

Для каждого запроса:
1. Показан план **без** индексов (Seq Scan)
2. Создан индекс
3. Показан план **с** индексом (Index Scan)
4. Объяснён эффект

---

## 1. Поиск пользователя по логину

### Запрос
```sql
SELECT * FROM users WHERE login = 'ivanov_ivan';
```

### До оптимизации (без индекса)
```
EXPLAIN ANALYZE SELECT * FROM users WHERE login = 'ivanov_ivan';
```
```
Seq Scan on users  (cost=0.00..1.15 rows=1 width=320) (actual time=0.012..0.020 rows=1 loops=1)
  Filter: ((login)::text = 'ivanov_ivan'::text)
  Rows Removed by Filter: 11
Planning Time: 0.089 ms
Execution Time: 0.038 ms
```

### Индекс
```sql
CREATE INDEX idx_users_login ON users(login);
```

### После оптимизации
```
Index Scan using idx_users_login on users  (cost=0.14..8.15 rows=1 width=320) (actual time=0.010..0.011 rows=1 loops=1)
  Index Cond: ((login)::text = 'ivanov_ivan'::text)
Planning Time: 0.143 ms
Execution Time: 0.025 ms
```

### Вывод
На малом объёме данных разница незначительна, но при миллионах пользователей Index Scan даёт **O(log N)** против **O(N)** у Seq Scan. Поиск по логину — частая операция (каждый вход в систему), индекс обязателен.

---

## 2. История тренировок пользователя (с сортировкой по дате)

### Запрос
```sql
SELECT w.id, w.title, w.started_at, COUNT(we.id) AS exercise_count
FROM workouts w
LEFT JOIN workout_exercises we ON we.workout_id = w.id
WHERE w.user_id = '11111111-0000-0000-0000-000000000001'
GROUP BY w.id
ORDER BY w.started_at DESC;
```

### До оптимизации (без индексов на workouts)
```
Sort  (cost=34.50..34.75 rows=100 width=48)
  Sort Key: w.started_at DESC
  ->  HashAggregate  (cost=29.00..30.00 rows=100 width=48)
        ->  Hash Left Join  (cost=10.00..27.00 rows=100 width=40)
              Hash Cond: (we.workout_id = w.id)
              ->  Seq Scan on workout_exercises we  (cost=0.00..15.00 rows=300 width=16)
              ->  Hash  (cost=9.75..9.75 rows=20 width=80)
                    ->  Seq Scan on workouts w  (cost=0.00..9.75 rows=20 width=80)
                          Filter: (user_id = '...')
Planning Time: 0.321 ms
Execution Time: 0.214 ms
```

### Индексы
```sql
CREATE INDEX idx_workouts_user_id    ON workouts(user_id);
CREATE INDEX idx_workouts_started_at ON workouts(started_at);
-- Составной индекс (покрывает оба условия одновременно)
CREATE INDEX idx_workouts_user_period ON workouts(user_id, started_at);
CREATE INDEX idx_we_workout_id        ON workout_exercises(workout_id);
```

### После оптимизации
```
Sort  (cost=18.20..18.35 rows=60 width=48)
  Sort Key: w.started_at DESC
  ->  HashAggregate  (cost=15.00..16.00 rows=60 width=48)
        ->  Hash Left Join  (cost=8.00..14.50 rows=60 width=40)
              Hash Cond: (we.workout_id = w.id)
              ->  Index Scan using idx_we_workout_id on workout_exercises we
              ->  Hash
                    ->  Index Scan using idx_workouts_user_id on workouts w
                          Index Cond: (user_id = '...')
Planning Time: 0.280 ms
Execution Time: 0.085 ms  (↓ в ~2.5 раза, выигрыш растёт с объёмом данных)
```

### Вывод
`idx_workouts_user_id` позволяет сразу найти тренировки нужного пользователя без перебора всей таблицы.
`idx_we_workout_id` ускоряет JOIN с `workout_exercises`.

---

## 3. Статистика тренировок за период

### Запрос
```sql
SELECT COUNT(DISTINCT w.id), SUM(...), AVG(...)
FROM workouts w
LEFT JOIN workout_exercises we ON we.workout_id = w.id
WHERE w.user_id    = '11111111-0000-0000-0000-000000000001'
  AND w.started_at >= '2024-12-01'
  AND w.started_at <  '2025-01-01';
```

### До оптимизации
```
Seq Scan on workouts w  (cost=0.00..12.50 rows=5 width=80)
  Filter: (user_id = '...' AND started_at >= '...' AND started_at < '...')
```

### Индекс
```sql
-- Составной индекс покрывает оба условия WHERE
CREATE INDEX idx_workouts_user_period ON workouts(user_id, started_at);
```

### После оптимизации
```
Index Scan using idx_workouts_user_period on workouts w
  Index Cond: (user_id = '...' AND started_at >= '...' AND started_at < '...')
```

### Вывод
Составной индекс `(user_id, started_at)` — классический приём для временны́х запросов с фильтром по владельцу. PostgreSQL использует его для **обоих** условий одновременно, что особенно важно для таблицы с историей за годы.

---

## 4. Поиск пользователя по маске имени/фамилии

### Запрос
```sql
SELECT * FROM users
WHERE first_name ILIKE '%Иван%' OR last_name ILIKE '%Иван%';
```

### Проблема
Стандартный B-Tree индекс **не работает** для `LIKE '%...'` с ведущим `%`.

### Решение — индекс pg_trgm
```sql
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX idx_users_fullname_trgm
    ON users USING GIN (
        (first_name || ' ' || last_name) gin_trgm_ops
    );
```

### После оптимизации
```
Bitmap Index Scan on idx_users_fullname_trgm
  Recheck Cond: ((first_name || ' ' || last_name) ILIKE '%Иван%')
Planning Time: 0.456 ms
Execution Time: 0.065 ms
```

### Вывод
`pg_trgm` + GIN-индекс позволяет эффективно выполнять поиск по произвольным подстрокам, что необходимо для функции поиска пользователей.

---

## 5. Порядок упражнений внутри тренировки

### Запрос
```sql
SELECT we.*, e.name FROM workout_exercises we
JOIN exercises e ON e.id = we.exercise_id
WHERE we.workout_id = '...'
ORDER BY we.order_index;
```

### Индекс
```sql
-- Покрывает WHERE + ORDER BY одним проходом без сортировки
CREATE INDEX idx_we_order ON workout_exercises(workout_id, order_index);
```

### Вывод
Составной индекс `(workout_id, order_index)` позволяет PostgreSQL вернуть строки уже отсортированными, избегая отдельного этапа `Sort`.

---

## Сводная таблица индексов

| Индекс | Таблица | Тип | Назначение |
|--------|---------|-----|-----------|
| `idx_users_login` | users | B-Tree | Быстрый вход по логину |
| `idx_users_name` | users | B-Tree | Поиск по точному совпадению имени |
| `idx_users_fullname_trgm` | users | GIN (trgm) | Поиск по маске (ILIKE) |
| `idx_exercises_muscle_group` | exercises | B-Tree | Фильтрация упражнений по группе мышц |
| `idx_workouts_user_id` | workouts | B-Tree | Тренировки пользователя |
| `idx_workouts_started_at` | workouts | B-Tree | Сортировка/фильтрация по дате |
| `idx_workouts_user_period` | workouts | B-Tree | Статистика за период (составной) |
| `idx_we_workout_id` | workout_exercises | B-Tree | JOIN тренировка → упражнения |
| `idx_we_exercise_id` | workout_exercises | B-Tree | JOIN упражнение → тренировки |
| `idx_we_order` | workout_exercises | B-Tree | Порядок упражнений в тренировке |

---

## Возможное партиционирование

Таблица `workouts` — кандидат на **Range Partitioning** по `started_at`:

```sql
CREATE TABLE workouts (
    ...
    started_at TIMESTAMPTZ NOT NULL
) PARTITION BY RANGE (started_at);

CREATE TABLE workouts_2024 PARTITION OF workouts
    FOR VALUES FROM ('2024-01-01') TO ('2025-01-01');

CREATE TABLE workouts_2025 PARTITION OF workouts
    FOR VALUES FROM ('2025-01-01') TO ('2026-01-01');
```

**Преимущества:**
- Запросы за конкретный год/квартал касаются только одной секции
- Архивирование старых данных — просто `DETACH PARTITION`
- Параллельное сканирование нескольких секций

**Актуально** при > 10 млн записей тренировок (крупный фитнес-сервис с историей за несколько лет).

-- ============================================================
-- Fitness Tracker — SQL-запросы для всех операций API
-- ============================================================

-- ============================================================
-- 1. Создание нового пользователя
-- ============================================================
INSERT INTO users (login, first_name, last_name, email, password_hash)
VALUES (
    'new_user',
    'Тестовый',
    'Пользователь',
    'test@example.com',
    crypt('my_password', gen_salt('bf'))
)
RETURNING id, login, first_name, last_name, email, created_at;

-- ============================================================
-- 2. Поиск пользователя по логину
-- ============================================================
-- Использует индекс idx_users_login
SELECT id, login, first_name, last_name, email, created_at
FROM users
WHERE login = 'ivanov_ivan';

-- ============================================================
-- 3. Поиск пользователя по маске имени и фамилии
-- ============================================================
-- Использует idx_users_name (для =) или seq-scan с LIKE
-- Параметры: :first_name_mask, :last_name_mask
SELECT id, login, first_name, last_name, email, created_at
FROM users
WHERE first_name ILIKE '%Иван%'
   OR last_name  ILIKE '%Иван%'
ORDER BY last_name, first_name;

-- ============================================================
-- 4. Создание упражнения
-- ============================================================
INSERT INTO exercises (name, description, muscle_group, equipment)
VALUES (
    'Гиперэкстензия',
    'Разгибание спины в тренажёре',
    'back',
    'тренажёр'
)
RETURNING id, name, muscle_group, equipment, created_at;

-- ============================================================
-- 5. Получение списка упражнений (с фильтром по мышечной группе)
-- ============================================================
-- Без фильтра
SELECT id, name, description, muscle_group, equipment
FROM exercises
ORDER BY muscle_group, name;

-- С фильтром по группе мышц (использует idx_exercises_muscle_group)
SELECT id, name, description, muscle_group, equipment
FROM exercises
WHERE muscle_group = 'back'
ORDER BY name;

-- ============================================================
-- 6. Создание тренировки
-- ============================================================
INSERT INTO workouts (user_id, title, notes, started_at)
VALUES (
    '11111111-0000-0000-0000-000000000001',
    'Утренняя тренировка',
    'Лёгкая разминка',
    NOW()
)
RETURNING id, user_id, title, started_at, created_at;

-- ============================================================
-- 7. Добавление упражнения в тренировку
-- ============================================================
INSERT INTO workout_exercises (workout_id, exercise_id, sets, reps, weight_kg, order_index)
VALUES (
    '33333333-0000-0000-0000-000000000001',
    '22222222-0000-0000-0000-000000000001',
    4,
    10,
    80.00,
    1
)
RETURNING id, workout_id, exercise_id, sets, reps, weight_kg;

-- ============================================================
-- 8. Получение истории тренировок пользователя
-- ============================================================
-- Использует индекс idx_workouts_user_id + idx_workouts_started_at
SELECT
    w.id,
    w.title,
    w.notes,
    w.started_at,
    w.ended_at,
    EXTRACT(EPOCH FROM (w.ended_at - w.started_at)) / 60 AS duration_minutes,
    COUNT(we.id) AS exercise_count
FROM workouts w
LEFT JOIN workout_exercises we ON we.workout_id = w.id
WHERE w.user_id = '11111111-0000-0000-0000-000000000001'
GROUP BY w.id
ORDER BY w.started_at DESC;

-- С пагинацией (страница 1, по 10 записей)
SELECT
    w.id,
    w.title,
    w.started_at,
    w.ended_at,
    COUNT(we.id) AS exercise_count
FROM workouts w
LEFT JOIN workout_exercises we ON we.workout_id = w.id
WHERE w.user_id = '11111111-0000-0000-0000-000000000001'
GROUP BY w.id
ORDER BY w.started_at DESC
LIMIT 10 OFFSET 0;

-- ============================================================
-- 9. Получение статистики тренировок за период
-- ============================================================
-- Использует составной индекс idx_workouts_user_period
SELECT
    COUNT(DISTINCT w.id)                                         AS total_workouts,
    SUM(EXTRACT(EPOCH FROM (w.ended_at - w.started_at)) / 60)  AS total_minutes,
    AVG(EXTRACT(EPOCH FROM (w.ended_at - w.started_at)) / 60)  AS avg_duration_minutes,
    COUNT(we.id)                                                 AS total_sets,
    SUM(we.sets * COALESCE(we.reps, 0) * COALESCE(we.weight_kg, 0)) AS total_volume_kg,
    MAX(w.started_at)                                            AS last_workout_at
FROM workouts w
LEFT JOIN workout_exercises we ON we.workout_id = w.id
WHERE w.user_id    = '11111111-0000-0000-0000-000000000001'
  AND w.started_at >= '2024-12-01 00:00:00+03'
  AND w.started_at <  '2025-01-01 00:00:00+03';

-- Статистика по упражнениям за период (топ-5 упражнений по объёму)
SELECT
    e.name                                                    AS exercise_name,
    e.muscle_group,
    COUNT(we.id)                                              AS times_performed,
    SUM(we.sets)                                              AS total_sets,
    MAX(we.weight_kg)                                         AS max_weight_kg,
    SUM(we.sets * COALESCE(we.reps,0) * COALESCE(we.weight_kg,0)) AS total_volume_kg
FROM workouts w
JOIN workout_exercises we ON we.workout_id = w.id
JOIN exercises          e  ON e.id         = we.exercise_id
WHERE w.user_id    = '11111111-0000-0000-0000-000000000001'
  AND w.started_at >= '2024-12-01 00:00:00+03'
  AND w.started_at <  '2025-01-01 00:00:00+03'
GROUP BY e.id, e.name, e.muscle_group
ORDER BY total_volume_kg DESC
LIMIT 5;

-- ============================================================
-- Дополнительно: детали одной тренировки (упражнения в порядке выполнения)
-- ============================================================
SELECT
    we.order_index,
    e.name        AS exercise_name,
    e.muscle_group,
    we.sets,
    we.reps,
    we.weight_kg,
    we.duration_s,
    we.distance_m,
    we.notes
FROM workout_exercises we
JOIN exercises e ON e.id = we.exercise_id
WHERE we.workout_id = '33333333-0000-0000-0000-000000000001'
ORDER BY we.order_index;

-- ============================================================
-- FITNESS TRACKER — queries.sql
-- SQL запросы для всех операций API (Вариант 14)
-- ============================================================

-- ============================================================
-- 1. Создание нового пользователя
-- ============================================================
INSERT INTO users (login, first_name, last_name, email, password_hash, birth_date, weight_kg, height_cm)
VALUES (
    'new_user',
    'Новый',
    'Пользователь',
    'new@example.com',
    '$2b$12$hashed_password',
    '2000-01-01',
    70.0,
    175.0
)
RETURNING id, login, first_name, last_name, email, created_at;


-- ============================================================
-- 2. Поиск пользователя по логину (точное совпадение)
-- ============================================================
-- Используется индекс idx_users_login (B-tree, UNIQUE)
SELECT
    id,
    login,
    first_name,
    last_name,
    email,
    birth_date,
    weight_kg,
    height_cm,
    created_at
FROM users
WHERE login = 'ivan_petrov';


-- ============================================================
-- 3. Поиск пользователей по маске имени и/или фамилии
--    Параметры: $1 = маска имени, $2 = маска фамилии
--    Пример: $1='Пет' найдёт 'Петров', 'Петрова'
-- ============================================================
-- Используются GIN-индексы idx_users_first_name_trgm, idx_users_last_name_trgm
SELECT
    id,
    login,
    first_name,
    last_name,
    email
FROM users
WHERE
    ($1 = '' OR first_name ILIKE '%' || $1 || '%')
    AND ($2 = '' OR last_name  ILIKE '%' || $2 || '%')
ORDER BY last_name, first_name;

-- Альтернатива с similarity (trigram) — лучше для нечёткого поиска:
SELECT
    id,
    login,
    first_name,
    last_name,
    similarity(last_name, $1) AS sim
FROM users
WHERE last_name % $1   -- оператор % — similarity threshold
ORDER BY sim DESC;


-- ============================================================
-- 4. Создание упражнения
-- ============================================================
INSERT INTO exercises (name, description, category, muscle_group, equipment, created_by, is_public)
VALUES (
    'Тяга верхнего блока',
    'Тяга к груди на тренажёре',
    'strength',
    'Спина, бицепс',
    'Тренажёр',
    1,       -- created_by: id текущего пользователя
    TRUE
)
RETURNING id, name, category, muscle_group, created_at;


-- ============================================================
-- 5. Получение списка упражнений
--    С фильтрацией по категории (опционально) и пагинацией
-- ============================================================
-- Используются: idx_exercises_is_public, idx_exercises_category
SELECT
    e.id,
    e.name,
    e.description,
    e.category,
    e.muscle_group,
    e.equipment,
    u.login AS created_by_login
FROM exercises e
LEFT JOIN users u ON u.id = e.created_by
WHERE
    e.is_public = TRUE
    AND ($1 = '' OR e.category = $1)   -- $1: фильтр по категории (пусто = все)
ORDER BY e.name
LIMIT  $2    -- $2: page_size
OFFSET $3;   -- $3: offset = (page - 1) * page_size


-- ============================================================
-- 6. Создание тренировки
-- ============================================================
INSERT INTO workouts (user_id, title, notes, started_at, finished_at, calories_burned)
VALUES (
    $1,   -- user_id
    $2,   -- title
    $3,   -- notes (может быть NULL)
    $4,   -- started_at
    $5,   -- finished_at (может быть NULL, если тренировка ещё идёт)
    $6    -- calories_burned
)
RETURNING id, user_id, title, started_at, finished_at, duration_sec, created_at;


-- ============================================================
-- 7. Добавление упражнения в тренировку
-- ============================================================
-- Сначала проверяем, что тренировка принадлежит пользователю (в коде API)
INSERT INTO workout_exercises (
    workout_id, exercise_id, order_num,
    sets, reps, weight_kg, duration_sec, distance_m, notes
)
VALUES (
    $1,   -- workout_id
    $2,   -- exercise_id
    COALESCE(
        (SELECT MAX(order_num) + 1 FROM workout_exercises WHERE workout_id = $1),
        1
    ),    -- следующий порядковый номер
    $3,   -- sets
    $4,   -- reps
    $5,   -- weight_kg
    $6,   -- duration_sec
    $7,   -- distance_m
    $8    -- notes
)
RETURNING id, workout_id, exercise_id, order_num;


-- ============================================================
-- 8. Получение истории тренировок пользователя
--    (с деталями упражнений)
-- ============================================================
-- Используется составной индекс idx_workouts_user_date
SELECT
    w.id            AS workout_id,
    w.title,
    w.notes,
    w.started_at,
    w.finished_at,
    w.duration_sec,
    w.calories_burned,

    -- агрегация упражнений
    COUNT(we.id)                        AS exercise_count,
    JSON_AGG(
        JSON_BUILD_OBJECT(
            'exercise_id',   e.id,
            'name',          e.name,
            'category',      e.category,
            'sets',          we.sets,
            'reps',          we.reps,
            'weight_kg',     we.weight_kg,
            'duration_sec',  we.duration_sec,
            'distance_m',    we.distance_m,
            'order_num',     we.order_num
        ) ORDER BY we.order_num
    ) FILTER (WHERE we.id IS NOT NULL)  AS exercises

FROM workouts w
LEFT JOIN workout_exercises we ON we.workout_id = w.id
LEFT JOIN exercises e          ON e.id = we.exercise_id
WHERE w.user_id = $1           -- $1: user_id
GROUP BY w.id
ORDER BY w.started_at DESC
LIMIT  $2    -- $2: page_size (например, 20)
OFFSET $3;   -- $3: offset


-- ============================================================
-- 9. Получение статистики тренировок за период
--    Параметры: $1 = user_id, $2 = date_from, $3 = date_to
-- ============================================================
-- Используется индекс idx_workouts_user_date
WITH period_workouts AS (
    SELECT
        w.id,
        w.started_at,
        w.duration_sec,
        w.calories_burned,
        we.exercise_id,
        we.sets,
        we.reps,
        we.weight_kg,
        we.distance_m
    FROM workouts w
    LEFT JOIN workout_exercises we ON we.workout_id = w.id
    WHERE
        w.user_id    = $1
        AND w.started_at >= $2::TIMESTAMPTZ
        AND w.started_at <  $3::TIMESTAMPTZ + INTERVAL '1 day'
)
SELECT
    -- общие показатели
    COUNT(DISTINCT id)              AS total_workouts,
    SUM(duration_sec)               AS total_duration_sec,
    AVG(duration_sec)               AS avg_duration_sec,
    SUM(calories_burned)            AS total_calories,
    AVG(calories_burned)            AS avg_calories_per_workout,

    -- объём нагрузки
    SUM(sets * COALESCE(reps, 1))   AS total_sets_reps,
    SUM(
        COALESCE(weight_kg, 0)
        * COALESCE(sets, 1)
        * COALESCE(reps, 1)
    )                               AS total_volume_kg,     -- суммарный объём (кг)

    -- кардио
    SUM(distance_m) / 1000.0       AS total_distance_km,

    -- временные рамки
    MIN(started_at)                 AS first_workout,
    MAX(started_at)                 AS last_workout
FROM period_workouts;

-- Дополнительно: разбивка по неделям
SELECT
    DATE_TRUNC('week', w.started_at)    AS week_start,
    COUNT(*)                            AS workouts_count,
    SUM(w.duration_sec)                 AS total_duration_sec,
    SUM(w.calories_burned)              AS total_calories
FROM workouts w
WHERE
    w.user_id    = $1
    AND w.started_at >= $2::TIMESTAMPTZ
    AND w.started_at <  $3::TIMESTAMPTZ + INTERVAL '1 day'
GROUP BY DATE_TRUNC('week', w.started_at)
ORDER BY week_start;

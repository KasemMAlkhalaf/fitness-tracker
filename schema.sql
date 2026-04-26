-- ============================================================
-- Fitness Tracker — Schema (Вариант 14)
-- ============================================================

-- Расширения
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- 1. Пользователи
-- ============================================================
CREATE TABLE users (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    login       VARCHAR(64) NOT NULL UNIQUE,
    first_name  VARCHAR(128) NOT NULL,
    last_name   VARCHAR(128) NOT NULL,
    email       VARCHAR(255) NOT NULL UNIQUE,
    password_hash TEXT       NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_login_length  CHECK (char_length(login) >= 3),
    CONSTRAINT chk_email_format  CHECK (email LIKE '%@%')
);

-- ============================================================
-- 2. Упражнения (справочник)
-- ============================================================
CREATE TABLE exercises (
    id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    name         VARCHAR(256) NOT NULL UNIQUE,
    description  TEXT,
    muscle_group VARCHAR(128),               -- грудь, спина, ноги, …
    equipment    VARCHAR(128),               -- штанга, гантели, TRX, …
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_muscle_group CHECK (
        muscle_group IN ('chest','back','legs','shoulders','arms','core','cardio','full_body', NULL)
    )
);

-- ============================================================
-- 3. Тренировки
-- ============================================================
CREATE TABLE workouts (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title       VARCHAR(256),
    notes       TEXT,
    started_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ended_at    TIMESTAMPTZ,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chk_dates CHECK (ended_at IS NULL OR ended_at >= started_at)
);

-- ============================================================
-- 4. Упражнения в тренировке (связующая таблица)
-- ============================================================
CREATE TABLE workout_exercises (
    id          UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
    workout_id  UUID    NOT NULL REFERENCES workouts(id)  ON DELETE CASCADE,
    exercise_id UUID    NOT NULL REFERENCES exercises(id) ON DELETE RESTRICT,
    sets        SMALLINT NOT NULL DEFAULT 1,
    reps        SMALLINT,                     -- NULL для кардио
    weight_kg   NUMERIC(6,2),                 -- NULL если упражнение без веса
    duration_s  INT,                          -- длительность в секундах (кардио)
    distance_m  NUMERIC(8,2),                 -- дистанция (бег/велосипед)
    order_index SMALLINT NOT NULL DEFAULT 1,  -- порядок внутри тренировки
    notes       TEXT,

    CONSTRAINT chk_sets       CHECK (sets > 0),
    CONSTRAINT chk_reps       CHECK (reps IS NULL OR reps > 0),
    CONSTRAINT chk_weight     CHECK (weight_kg IS NULL OR weight_kg >= 0),
    CONSTRAINT chk_duration   CHECK (duration_s IS NULL OR duration_s > 0),
    CONSTRAINT chk_distance   CHECK (distance_m IS NULL OR distance_m > 0)
);

-- ============================================================
-- ИНДЕКСЫ
-- ============================================================

-- users
CREATE INDEX idx_users_login      ON users(login);          -- поиск по логину
CREATE INDEX idx_users_name       ON users(first_name, last_name); -- поиск по маске имени
CREATE INDEX idx_users_created_at ON users(created_at);

-- exercises
CREATE INDEX idx_exercises_name         ON exercises(name);
CREATE INDEX idx_exercises_muscle_group ON exercises(muscle_group);

-- workouts
CREATE INDEX idx_workouts_user_id    ON workouts(user_id);          -- история пользователя
CREATE INDEX idx_workouts_started_at ON workouts(started_at);       -- фильтрация по периоду
CREATE INDEX idx_workouts_user_period ON workouts(user_id, started_at); -- статистика за период

-- workout_exercises
CREATE INDEX idx_we_workout_id  ON workout_exercises(workout_id);   -- упражнения тренировки
CREATE INDEX idx_we_exercise_id ON workout_exercises(exercise_id);  -- какие тренировки содержат упражнение
CREATE INDEX idx_we_order       ON workout_exercises(workout_id, order_index); -- сортировка внутри тренировки

-- ============================================================
-- FITNESS TRACKER — schema.sql
-- Вариант 14: PostgreSQL схема базы данных
-- ============================================================

-- Расширения
CREATE EXTENSION IF NOT EXISTS pg_trgm;  -- для поиска по маске имени

-- ============================================================
-- ТАБЛИЦЫ
-- ============================================================

-- Пользователи
CREATE TABLE users (
    id          BIGSERIAL       PRIMARY KEY,
    login       VARCHAR(64)     NOT NULL UNIQUE,
    first_name  VARCHAR(100)    NOT NULL,
    last_name   VARCHAR(100)    NOT NULL,
    email       VARCHAR(255)    NOT NULL UNIQUE,
    password_hash VARCHAR(255)  NOT NULL,
    birth_date  DATE,
    weight_kg   NUMERIC(5,2)    CHECK (weight_kg > 0 AND weight_kg < 500),
    height_cm   NUMERIC(5,1)    CHECK (height_cm > 0 AND height_cm < 300),
    created_at  TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    CONSTRAINT users_login_format CHECK (login ~ '^[a-zA-Z0-9_]{3,64}$')
);

-- Упражнения (справочник)
CREATE TABLE exercises (
    id              BIGSERIAL       PRIMARY KEY,
    name            VARCHAR(200)    NOT NULL UNIQUE,
    description     TEXT,
    category        VARCHAR(50)     NOT NULL
                        CHECK (category IN (
                            'strength', 'cardio', 'flexibility',
                            'balance', 'plyometrics', 'other'
                        )),
    muscle_group    VARCHAR(100),
    equipment       VARCHAR(100),
    created_by      BIGINT          REFERENCES users(id) ON DELETE SET NULL,
    is_public       BOOLEAN         NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

-- Тренировки
CREATE TABLE workouts (
    id              BIGSERIAL       PRIMARY KEY,
    user_id         BIGINT          NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title           VARCHAR(200)    NOT NULL,
    notes           TEXT,
    started_at      TIMESTAMPTZ     NOT NULL,
    finished_at     TIMESTAMPTZ,
    duration_sec    INT             GENERATED ALWAYS AS (
                        EXTRACT(EPOCH FROM (finished_at - started_at))::INT
                    ) STORED,
    calories_burned INT             CHECK (calories_burned >= 0),
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),

    CONSTRAINT workouts_dates_order CHECK (finished_at IS NULL OR finished_at > started_at)
);

-- Упражнения в тренировке (связующая таблица)
CREATE TABLE workout_exercises (
    id              BIGSERIAL       PRIMARY KEY,
    workout_id      BIGINT          NOT NULL REFERENCES workouts(id) ON DELETE CASCADE,
    exercise_id     BIGINT          NOT NULL REFERENCES exercises(id) ON DELETE RESTRICT,
    order_num       SMALLINT        NOT NULL DEFAULT 1 CHECK (order_num > 0),
    sets            SMALLINT        CHECK (sets > 0 AND sets <= 100),
    reps            SMALLINT        CHECK (reps > 0 AND reps <= 10000),
    weight_kg       NUMERIC(6,2)    CHECK (weight_kg >= 0),
    duration_sec    INT             CHECK (duration_sec > 0),
    distance_m      NUMERIC(10,2)   CHECK (distance_m > 0),
    notes           TEXT,

    CONSTRAINT workout_exercises_unique UNIQUE (workout_id, exercise_id, order_num)
);

-- ============================================================
-- ИНДЕКСЫ
-- ============================================================

-- users: поиск по логину (точный, часто используется при аутентификации)
CREATE UNIQUE INDEX idx_users_login       ON users (login);

-- users: поиск по email
CREATE UNIQUE INDEX idx_users_email       ON users (email);

-- users: поиск по маске имени/фамилии (trigram для ILIKE)
CREATE INDEX idx_users_first_name_trgm   ON users USING GIN (first_name gin_trgm_ops);
CREATE INDEX idx_users_last_name_trgm    ON users USING GIN (last_name  gin_trgm_ops);

-- exercises: FK на создателя + фильтрация публичных
CREATE INDEX idx_exercises_created_by    ON exercises (created_by);
CREATE INDEX idx_exercises_category      ON exercises (category);
CREATE INDEX idx_exercises_is_public     ON exercises (is_public) WHERE is_public = TRUE;
-- trigram для поиска упражнений по названию
CREATE INDEX idx_exercises_name_trgm     ON exercises USING GIN (name gin_trgm_ops);

-- workouts: FK + диапазонный поиск по дате (история, статистика за период)
CREATE INDEX idx_workouts_user_id        ON workouts (user_id);
CREATE INDEX idx_workouts_started_at     ON workouts (started_at);
-- составной индекс: история конкретного пользователя, отсортированная по дате
CREATE INDEX idx_workouts_user_date      ON workouts (user_id, started_at DESC);

-- workout_exercises: FK индексы
CREATE INDEX idx_we_workout_id           ON workout_exercises (workout_id);
CREATE INDEX idx_we_exercise_id          ON workout_exercises (exercise_id);

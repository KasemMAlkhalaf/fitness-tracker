"""
Workouts API:
- POST  /workouts/                          — создание тренировки
- POST  /workouts/{workout_id}/exercises    — добавление упражнения
- GET   /workouts/users/{user_id}/history   — история тренировок
- GET   /workouts/users/{user_id}/stats     — статистика за период
"""

from fastapi import APIRouter, HTTPException, Request, Query
from pydantic import BaseModel
from typing import Optional
from datetime import datetime

router = APIRouter()


# ── Schemas ──────────────────────────────────────────────────

class WorkoutCreate(BaseModel):
    user_id: str
    title: Optional[str] = None
    notes: Optional[str] = None
    started_at: Optional[datetime] = None


class WorkoutExerciseAdd(BaseModel):
    exercise_id: str
    sets: int = 1
    reps: Optional[int] = None
    weight_kg: Optional[float] = None
    duration_s: Optional[int] = None
    distance_m: Optional[float] = None
    order_index: int = 1
    notes: Optional[str] = None


class WorkoutOut(BaseModel):
    id: str
    user_id: str
    title: Optional[str]
    notes: Optional[str]
    started_at: str
    ended_at: Optional[str]
    created_at: str


class WorkoutHistoryItem(BaseModel):
    id: str
    title: Optional[str]
    started_at: str
    ended_at: Optional[str]
    duration_minutes: Optional[float]
    exercise_count: int


class WorkoutExerciseOut(BaseModel):
    id: str
    workout_id: str
    exercise_id: str
    sets: int
    reps: Optional[int]
    weight_kg: Optional[float]
    order_index: int


class StatsOut(BaseModel):
    total_workouts: int
    total_minutes: Optional[float]
    avg_duration_minutes: Optional[float]
    total_sets: int
    total_volume_kg: Optional[float]
    last_workout_at: Optional[str]


# ── Helpers ──────────────────────────────────────────────────

def _fmt(dt) -> Optional[str]:
    return dt.isoformat() if dt else None


# ── Endpoints ─────────────────────────────────────────────────

@router.post("/", response_model=WorkoutOut, status_code=201)
async def create_workout(body: WorkoutCreate, request: Request):
    """Создание новой тренировки."""
    pool = request.app.state.pool
    started_at = body.started_at or datetime.utcnow()
    try:
        row = await pool.fetchrow(
            """
            INSERT INTO workouts (user_id, title, notes, started_at)
            VALUES ($1::uuid, $2, $3, $4)
            RETURNING id, user_id, title, notes, started_at, ended_at, created_at
            """,
            body.user_id, body.title, body.notes, started_at,
        )
    except Exception as e:
        if "foreign key" in str(e).lower():
            raise HTTPException(404, "user not found")
        raise HTTPException(500, str(e))
    return WorkoutOut(
        id=str(row["id"]),
        user_id=str(row["user_id"]),
        title=row["title"],
        notes=row["notes"],
        started_at=_fmt(row["started_at"]),
        ended_at=_fmt(row["ended_at"]),
        created_at=_fmt(row["created_at"]),
    )


@router.post("/{workout_id}/exercises", response_model=WorkoutExerciseOut, status_code=201)
async def add_exercise_to_workout(
    workout_id: str,
    body: WorkoutExerciseAdd,
    request: Request,
):
    """Добавление упражнения в тренировку."""
    pool = request.app.state.pool
    try:
        row = await pool.fetchrow(
            """
            INSERT INTO workout_exercises
                (workout_id, exercise_id, sets, reps, weight_kg,
                 duration_s, distance_m, order_index, notes)
            VALUES ($1::uuid, $2::uuid, $3, $4, $5, $6, $7, $8, $9)
            RETURNING id, workout_id, exercise_id, sets, reps, weight_kg, order_index
            """,
            workout_id, body.exercise_id,
            body.sets, body.reps, body.weight_kg,
            body.duration_s, body.distance_m, body.order_index, body.notes,
        )
    except Exception as e:
        err = str(e).lower()
        if "foreign key" in err:
            raise HTTPException(404, "workout or exercise not found")
        raise HTTPException(500, str(e))
    return WorkoutExerciseOut(
        id=str(row["id"]),
        workout_id=str(row["workout_id"]),
        exercise_id=str(row["exercise_id"]),
        sets=row["sets"],
        reps=row["reps"],
        weight_kg=float(row["weight_kg"]) if row["weight_kg"] is not None else None,
        order_index=row["order_index"],
    )


@router.get("/users/{user_id}/history", response_model=list[WorkoutHistoryItem])
async def get_workout_history(
    user_id: str,
    request: Request,
    limit: int = Query(20, ge=1, le=100),
    offset: int = Query(0, ge=0),
):
    """
    История тренировок пользователя.
    Использует индексы idx_workouts_user_id, idx_we_workout_id.
    """
    pool = request.app.state.pool
    rows = await pool.fetch(
        """
        SELECT
            w.id,
            w.title,
            w.started_at,
            w.ended_at,
            EXTRACT(EPOCH FROM (w.ended_at - w.started_at)) / 60 AS duration_minutes,
            COUNT(we.id)::int AS exercise_count
        FROM workouts w
        LEFT JOIN workout_exercises we ON we.workout_id = w.id
        WHERE w.user_id = $1::uuid
        GROUP BY w.id
        ORDER BY w.started_at DESC
        LIMIT $2 OFFSET $3
        """,
        user_id, limit, offset,
    )
    return [
        WorkoutHistoryItem(
            id=str(r["id"]),
            title=r["title"],
            started_at=_fmt(r["started_at"]),
            ended_at=_fmt(r["ended_at"]),
            duration_minutes=float(r["duration_minutes"]) if r["duration_minutes"] else None,
            exercise_count=r["exercise_count"],
        )
        for r in rows
    ]


@router.get("/users/{user_id}/stats", response_model=StatsOut)
async def get_workout_stats(
    user_id: str,
    request: Request,
    from_date: datetime = Query(..., description="Начало периода (ISO 8601)"),
    to_date: datetime = Query(..., description="Конец периода (ISO 8601)"),
):
    """
    Статистика тренировок пользователя за период.
    Использует составной индекс idx_workouts_user_period.
    """
    pool = request.app.state.pool
    row = await pool.fetchrow(
        """
        SELECT
            COUNT(DISTINCT w.id)::int                                          AS total_workouts,
            SUM(EXTRACT(EPOCH FROM (w.ended_at - w.started_at)) / 60)        AS total_minutes,
            AVG(EXTRACT(EPOCH FROM (w.ended_at - w.started_at)) / 60)        AS avg_duration_minutes,
            COUNT(we.id)::int                                                  AS total_sets,
            SUM(we.sets * COALESCE(we.reps, 0) * COALESCE(we.weight_kg, 0)) AS total_volume_kg,
            MAX(w.started_at)                                                  AS last_workout_at
        FROM workouts w
        LEFT JOIN workout_exercises we ON we.workout_id = w.id
        WHERE w.user_id    = $1::uuid
          AND w.started_at >= $2
          AND w.started_at <  $3
        """,
        user_id, from_date, to_date,
    )
    return StatsOut(
        total_workouts=row["total_workouts"] or 0,
        total_minutes=float(row["total_minutes"]) if row["total_minutes"] else None,
        avg_duration_minutes=float(row["avg_duration_minutes"]) if row["avg_duration_minutes"] else None,
        total_sets=row["total_sets"] or 0,
        total_volume_kg=float(row["total_volume_kg"]) if row["total_volume_kg"] else None,
        last_workout_at=_fmt(row["last_workout_at"]),
    )

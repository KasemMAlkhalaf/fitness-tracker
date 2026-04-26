"""
Exercises API:
- POST  /exercises/         — создание упражнения
- GET   /exercises/         — список упражнений (с опциональным фильтром)
"""

from fastapi import APIRouter, Request, Query
from pydantic import BaseModel
from typing import Optional

router = APIRouter()

VALID_MUSCLE_GROUPS = {
    "chest", "back", "legs", "shoulders", "arms", "core", "cardio", "full_body"
}


# ── Schemas ──────────────────────────────────────────────────

class ExerciseCreate(BaseModel):
    name: str
    description: Optional[str] = None
    muscle_group: Optional[str] = None
    equipment: Optional[str] = None


class ExerciseOut(BaseModel):
    id: str
    name: str
    description: Optional[str]
    muscle_group: Optional[str]
    equipment: Optional[str]
    created_at: str


def _row_to_exercise(row) -> ExerciseOut:
    return ExerciseOut(
        id=str(row["id"]),
        name=row["name"],
        description=row["description"],
        muscle_group=row["muscle_group"],
        equipment=row["equipment"],
        created_at=row["created_at"].isoformat(),
    )


# ── Endpoints ─────────────────────────────────────────────────

@router.post("/", response_model=ExerciseOut, status_code=201)
async def create_exercise(body: ExerciseCreate, request: Request):
    """Создание нового упражнения."""
    pool = request.app.state.pool
    from fastapi import HTTPException
    if body.muscle_group and body.muscle_group not in VALID_MUSCLE_GROUPS:
        raise HTTPException(422, f"muscle_group must be one of {VALID_MUSCLE_GROUPS}")
    try:
        row = await pool.fetchrow(
            """
            INSERT INTO exercises (name, description, muscle_group, equipment)
            VALUES ($1, $2, $3, $4)
            RETURNING id, name, description, muscle_group, equipment, created_at
            """,
            body.name, body.description, body.muscle_group, body.equipment,
        )
    except Exception as e:
        if "unique" in str(e).lower():
            from fastapi import HTTPException
            raise HTTPException(409, "exercise with this name already exists")
        raise
    return _row_to_exercise(row)


@router.get("/", response_model=list[ExerciseOut])
async def list_exercises(
    request: Request,
    muscle_group: Optional[str] = Query(None, description="Фильтр по группе мышц"),
):
    """
    Список всех упражнений.
    Опционально фильтруется по muscle_group.
    Использует idx_exercises_muscle_group.
    """
    pool = request.app.state.pool
    if muscle_group:
        rows = await pool.fetch(
            """
            SELECT id, name, description, muscle_group, equipment, created_at
            FROM exercises
            WHERE muscle_group = $1
            ORDER BY name
            """,
            muscle_group,
        )
    else:
        rows = await pool.fetch(
            """
            SELECT id, name, description, muscle_group, equipment, created_at
            FROM exercises
            ORDER BY muscle_group, name
            """
        )
    return [_row_to_exercise(r) for r in rows]

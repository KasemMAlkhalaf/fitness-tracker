"""
Users API:
- POST   /users/           — создание пользователя
- GET    /users/by-login/{login} — поиск по логину
- GET    /users/search?q=  — поиск по маске имени/фамилии
"""

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, EmailStr, field_validator
import hashlib

router = APIRouter()


# ── Schemas ──────────────────────────────────────────────────

class UserCreate(BaseModel):
    login: str
    first_name: str
    last_name: str
    email: EmailStr
    password: str

    @field_validator("login")
    @classmethod
    def login_min_length(cls, v: str) -> str:
        if len(v) < 3:
            raise ValueError("login must be at least 3 characters")
        return v


class UserOut(BaseModel):
    id: str
    login: str
    first_name: str
    last_name: str
    email: str
    created_at: str


def _hash_password(password: str) -> str:
    """Simple SHA-256 hash (в продакшне использовать bcrypt через DB crypt())"""
    return hashlib.sha256(password.encode()).hexdigest()


def _row_to_user(row) -> UserOut:
    return UserOut(
        id=str(row["id"]),
        login=row["login"],
        first_name=row["first_name"],
        last_name=row["last_name"],
        email=row["email"],
        created_at=row["created_at"].isoformat(),
    )


# ── Endpoints ─────────────────────────────────────────────────

@router.post("/", response_model=UserOut, status_code=201)
async def create_user(body: UserCreate, request: Request):
    """Создание нового пользователя."""
    pool = request.app.state.pool
    try:
        row = await pool.fetchrow(
            """
            INSERT INTO users (login, first_name, last_name, email, password_hash)
            VALUES ($1, $2, $3, $4, crypt($5, gen_salt('bf')))
            RETURNING id, login, first_name, last_name, email, created_at
            """,
            body.login, body.first_name, body.last_name,
            body.email, body.password,
        )
    except Exception as e:
        if "unique" in str(e).lower():
            raise HTTPException(409, "login or email already exists")
        raise HTTPException(500, str(e))
    return _row_to_user(row)


@router.get("/by-login/{login}", response_model=UserOut)
async def get_user_by_login(login: str, request: Request):
    """Поиск пользователя по логину. Использует индекс idx_users_login."""
    pool = request.app.state.pool
    row = await pool.fetchrow(
        """
        SELECT id, login, first_name, last_name, email, created_at
        FROM users
        WHERE login = $1
        """,
        login,
    )
    if not row:
        raise HTTPException(404, "user not found")
    return _row_to_user(row)


@router.get("/search", response_model=list[UserOut])
async def search_users(q: str, request: Request):
    """
    Поиск по маске имени и фамилии (ILIKE).
    При наличии расширения pg_trgm использует GIN-индекс.
    """
    pool = request.app.state.pool
    mask = f"%{q}%"
    rows = await pool.fetch(
        """
        SELECT id, login, first_name, last_name, email, created_at
        FROM users
        WHERE first_name ILIKE $1
           OR last_name  ILIKE $1
        ORDER BY last_name, first_name
        LIMIT 50
        """,
        mask,
    )
    return [_row_to_user(r) for r in rows]

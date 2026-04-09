package main

import (
	"database/sql"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"strconv"
	"time"

	"github.com/gorilla/mux"
	_ "github.com/lib/pq"
)

// ─── Models ─────────────────────────────────────────────────

type User struct {
	ID           int64      `json:"id"`
	Login        string     `json:"login"`
	FirstName    string     `json:"first_name"`
	LastName     string     `json:"last_name"`
	Email        string     `json:"email"`
	PasswordHash string     `json:"-"`
	BirthDate    *time.Time `json:"birth_date,omitempty"`
	WeightKg     *float64   `json:"weight_kg,omitempty"`
	HeightCm     *float64   `json:"height_cm,omitempty"`
	CreatedAt    time.Time  `json:"created_at"`
}

type Exercise struct {
	ID          int64     `json:"id"`
	Name        string    `json:"name"`
	Description *string   `json:"description,omitempty"`
	Category    string    `json:"category"`
	MuscleGroup *string   `json:"muscle_group,omitempty"`
	Equipment   *string   `json:"equipment,omitempty"`
	CreatedBy   *int64    `json:"created_by,omitempty"`
	IsPublic    bool      `json:"is_public"`
	CreatedAt   time.Time `json:"created_at"`
}

type Workout struct {
	ID             int64      `json:"id"`
	UserID         int64      `json:"user_id"`
	Title          string     `json:"title"`
	Notes          *string    `json:"notes,omitempty"`
	StartedAt      time.Time  `json:"started_at"`
	FinishedAt     *time.Time `json:"finished_at,omitempty"`
	DurationSec    *int       `json:"duration_sec,omitempty"`
	CaloriesBurned *int       `json:"calories_burned,omitempty"`
	CreatedAt      time.Time  `json:"created_at"`
}

type WorkoutExercise struct {
	ID          int64    `json:"id"`
	WorkoutID   int64    `json:"workout_id"`
	ExerciseID  int64    `json:"exercise_id"`
	OrderNum    int      `json:"order_num"`
	Sets        *int     `json:"sets,omitempty"`
	Reps        *int     `json:"reps,omitempty"`
	WeightKg    *float64 `json:"weight_kg,omitempty"`
	DurationSec *int     `json:"duration_sec,omitempty"`
	DistanceM   *float64 `json:"distance_m,omitempty"`
	Notes       *string  `json:"notes,omitempty"`
}

type WorkoutStats struct {
	TotalWorkouts        int      `json:"total_workouts"`
	TotalDurationSec     *int     `json:"total_duration_sec,omitempty"`
	AvgDurationSec       *float64 `json:"avg_duration_sec,omitempty"`
	TotalCalories        *int     `json:"total_calories,omitempty"`
	AvgCaloriesPerWkt    *float64 `json:"avg_calories_per_workout,omitempty"`
	TotalVolumeKg        *float64 `json:"total_volume_kg,omitempty"`
	TotalDistanceKm      *float64 `json:"total_distance_km,omitempty"`
	FirstWorkout         *time.Time `json:"first_workout,omitempty"`
	LastWorkout          *time.Time `json:"last_workout,omitempty"`
}

// ─── App ─────────────────────────────────────────────────────

type App struct {
	DB     *sql.DB
	Router *mux.Router
}

func NewApp(dsn string) (*App, error) {
	db, err := sql.Open("postgres", dsn)
	if err != nil {
		return nil, err
	}
	if err = db.Ping(); err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(25)
	db.SetMaxIdleConns(5)
	db.SetConnMaxLifetime(5 * time.Minute)

	app := &App{DB: db, Router: mux.NewRouter()}
	app.registerRoutes()
	return app, nil
}

func (a *App) registerRoutes() {
	r := a.Router
	r.HandleFunc("/users",                         a.createUser).Methods("POST")
	r.HandleFunc("/users/by-login/{login}",        a.getUserByLogin).Methods("GET")
	r.HandleFunc("/users/search",                  a.searchUsers).Methods("GET")
	r.HandleFunc("/exercises",                     a.createExercise).Methods("POST")
	r.HandleFunc("/exercises",                     a.listExercises).Methods("GET")
	r.HandleFunc("/workouts",                      a.createWorkout).Methods("POST")
	r.HandleFunc("/workouts/{id}/exercises",       a.addExerciseToWorkout).Methods("POST")
	r.HandleFunc("/users/{id}/workouts",           a.getUserWorkoutHistory).Methods("GET")
	r.HandleFunc("/users/{id}/workouts/stats",     a.getWorkoutStats).Methods("GET")
}

// ─── Helpers ─────────────────────────────────────────────────

func respond(w http.ResponseWriter, code int, data any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	json.NewEncoder(w).Encode(data)
}

func errResp(w http.ResponseWriter, code int, msg string) {
	respond(w, code, map[string]string{"error": msg})
}

func decode(r *http.Request, dst any) error {
	return json.NewDecoder(r.Body).Decode(dst)
}

// ─── Handlers ────────────────────────────────────────────────

// POST /users — создание пользователя
func (a *App) createUser(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Login        string   `json:"login"`
		FirstName    string   `json:"first_name"`
		LastName     string   `json:"last_name"`
		Email        string   `json:"email"`
		PasswordHash string   `json:"password_hash"`
		BirthDate    *string  `json:"birth_date"`
		WeightKg     *float64 `json:"weight_kg"`
		HeightCm     *float64 `json:"height_cm"`
	}
	if err := decode(r, &req); err != nil {
		errResp(w, http.StatusBadRequest, "invalid JSON")
		return
	}
	if req.Login == "" || req.Email == "" || req.PasswordHash == "" {
		errResp(w, http.StatusBadRequest, "login, email and password_hash are required")
		return
	}

	var user User
	err := a.DB.QueryRowContext(r.Context(), `
		INSERT INTO users (login, first_name, last_name, email, password_hash, weight_kg, height_cm)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
		RETURNING id, login, first_name, last_name, email, weight_kg, height_cm, created_at`,
		req.Login, req.FirstName, req.LastName, req.Email, req.PasswordHash, req.WeightKg, req.HeightCm,
	).Scan(&user.ID, &user.Login, &user.FirstName, &user.LastName, &user.Email,
		&user.WeightKg, &user.HeightCm, &user.CreatedAt)

	if err != nil {
		errResp(w, http.StatusConflict, err.Error())
		return
	}
	respond(w, http.StatusCreated, user)
}

// GET /users/by-login/{login} — поиск по логину
func (a *App) getUserByLogin(w http.ResponseWriter, r *http.Request) {
	login := mux.Vars(r)["login"]
	var user User
	err := a.DB.QueryRowContext(r.Context(), `
		SELECT id, login, first_name, last_name, email, weight_kg, height_cm, created_at
		FROM users WHERE login = $1`, login,
	).Scan(&user.ID, &user.Login, &user.FirstName, &user.LastName, &user.Email,
		&user.WeightKg, &user.HeightCm, &user.CreatedAt)

	if err == sql.ErrNoRows {
		errResp(w, http.StatusNotFound, "user not found")
		return
	}
	if err != nil {
		errResp(w, http.StatusInternalServerError, err.Error())
		return
	}
	respond(w, http.StatusOK, user)
}

// GET /users/search?first_name=Ив&last_name=Пет — поиск по маске
func (a *App) searchUsers(w http.ResponseWriter, r *http.Request) {
	fn := r.URL.Query().Get("first_name")
	ln := r.URL.Query().Get("last_name")

	rows, err := a.DB.QueryContext(r.Context(), `
		SELECT id, login, first_name, last_name, email, created_at
		FROM users
		WHERE ($1 = '' OR first_name ILIKE '%' || $1 || '%')
		  AND ($2 = '' OR last_name  ILIKE '%' || $2 || '%')
		ORDER BY last_name, first_name
		LIMIT 50`, fn, ln,
	)
	if err != nil {
		errResp(w, http.StatusInternalServerError, err.Error())
		return
	}
	defer rows.Close()

	var users []User
	for rows.Next() {
		var u User
		if err := rows.Scan(&u.ID, &u.Login, &u.FirstName, &u.LastName, &u.Email, &u.CreatedAt); err != nil {
			continue
		}
		users = append(users, u)
	}
	respond(w, http.StatusOK, users)
}

// POST /exercises — создание упражнения
func (a *App) createExercise(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Name        string  `json:"name"`
		Description *string `json:"description"`
		Category    string  `json:"category"`
		MuscleGroup *string `json:"muscle_group"`
		Equipment   *string `json:"equipment"`
		CreatedBy   *int64  `json:"created_by"`
		IsPublic    bool    `json:"is_public"`
	}
	if err := decode(r, &req); err != nil {
		errResp(w, http.StatusBadRequest, "invalid JSON")
		return
	}

	var ex Exercise
	err := a.DB.QueryRowContext(r.Context(), `
		INSERT INTO exercises (name, description, category, muscle_group, equipment, created_by, is_public)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
		RETURNING id, name, description, category, muscle_group, equipment, created_by, is_public, created_at`,
		req.Name, req.Description, req.Category, req.MuscleGroup, req.Equipment, req.CreatedBy, req.IsPublic,
	).Scan(&ex.ID, &ex.Name, &ex.Description, &ex.Category, &ex.MuscleGroup,
		&ex.Equipment, &ex.CreatedBy, &ex.IsPublic, &ex.CreatedAt)

	if err != nil {
		errResp(w, http.StatusConflict, err.Error())
		return
	}
	respond(w, http.StatusCreated, ex)
}

// GET /exercises?category=strength&page=1&page_size=20 — список упражнений
func (a *App) listExercises(w http.ResponseWriter, r *http.Request) {
	category := r.URL.Query().Get("category")
	page, _     := strconv.Atoi(r.URL.Query().Get("page"))
	pageSize, _ := strconv.Atoi(r.URL.Query().Get("page_size"))
	if page < 1      { page = 1 }
	if pageSize < 1  { pageSize = 20 }
	offset := (page - 1) * pageSize

	rows, err := a.DB.QueryContext(r.Context(), `
		SELECT e.id, e.name, e.description, e.category, e.muscle_group, e.equipment,
		       e.created_by, e.is_public, e.created_at
		FROM exercises e
		WHERE e.is_public = TRUE
		  AND ($1 = '' OR e.category = $1)
		ORDER BY e.name
		LIMIT $2 OFFSET $3`, category, pageSize, offset,
	)
	if err != nil {
		errResp(w, http.StatusInternalServerError, err.Error())
		return
	}
	defer rows.Close()

	var exercises []Exercise
	for rows.Next() {
		var ex Exercise
		if err := rows.Scan(&ex.ID, &ex.Name, &ex.Description, &ex.Category,
			&ex.MuscleGroup, &ex.Equipment, &ex.CreatedBy, &ex.IsPublic, &ex.CreatedAt); err != nil {
			continue
		}
		exercises = append(exercises, ex)
	}
	respond(w, http.StatusOK, exercises)
}

// POST /workouts — создание тренировки
func (a *App) createWorkout(w http.ResponseWriter, r *http.Request) {
	var req struct {
		UserID         int64      `json:"user_id"`
		Title          string     `json:"title"`
		Notes          *string    `json:"notes"`
		StartedAt      time.Time  `json:"started_at"`
		FinishedAt     *time.Time `json:"finished_at"`
		CaloriesBurned *int       `json:"calories_burned"`
	}
	if err := decode(r, &req); err != nil {
		errResp(w, http.StatusBadRequest, "invalid JSON")
		return
	}

	var wkt Workout
	err := a.DB.QueryRowContext(r.Context(), `
		INSERT INTO workouts (user_id, title, notes, started_at, finished_at, calories_burned)
		VALUES ($1, $2, $3, $4, $5, $6)
		RETURNING id, user_id, title, notes, started_at, finished_at, duration_sec, calories_burned, created_at`,
		req.UserID, req.Title, req.Notes, req.StartedAt, req.FinishedAt, req.CaloriesBurned,
	).Scan(&wkt.ID, &wkt.UserID, &wkt.Title, &wkt.Notes, &wkt.StartedAt,
		&wkt.FinishedAt, &wkt.DurationSec, &wkt.CaloriesBurned, &wkt.CreatedAt)

	if err != nil {
		errResp(w, http.StatusInternalServerError, err.Error())
		return
	}
	respond(w, http.StatusCreated, wkt)
}

// POST /workouts/{id}/exercises — добавление упражнения в тренировку
func (a *App) addExerciseToWorkout(w http.ResponseWriter, r *http.Request) {
	wktID, err := strconv.ParseInt(mux.Vars(r)["id"], 10, 64)
	if err != nil {
		errResp(w, http.StatusBadRequest, "invalid workout id")
		return
	}

	var req struct {
		ExerciseID  int64    `json:"exercise_id"`
		Sets        *int     `json:"sets"`
		Reps        *int     `json:"reps"`
		WeightKg    *float64 `json:"weight_kg"`
		DurationSec *int     `json:"duration_sec"`
		DistanceM   *float64 `json:"distance_m"`
		Notes       *string  `json:"notes"`
	}
	if err := decode(r, &req); err != nil {
		errResp(w, http.StatusBadRequest, "invalid JSON")
		return
	}

	var we WorkoutExercise
	err = a.DB.QueryRowContext(r.Context(), `
		INSERT INTO workout_exercises
		  (workout_id, exercise_id, order_num, sets, reps, weight_kg, duration_sec, distance_m, notes)
		VALUES (
		  $1, $2,
		  COALESCE((SELECT MAX(order_num)+1 FROM workout_exercises WHERE workout_id=$1), 1),
		  $3, $4, $5, $6, $7, $8
		)
		RETURNING id, workout_id, exercise_id, order_num`,
		wktID, req.ExerciseID, req.Sets, req.Reps, req.WeightKg, req.DurationSec, req.DistanceM, req.Notes,
	).Scan(&we.ID, &we.WorkoutID, &we.ExerciseID, &we.OrderNum)

	if err != nil {
		errResp(w, http.StatusInternalServerError, err.Error())
		return
	}
	respond(w, http.StatusCreated, we)
}

// GET /users/{id}/workouts?page=1&page_size=20 — история тренировок
func (a *App) getUserWorkoutHistory(w http.ResponseWriter, r *http.Request) {
	userID, err := strconv.ParseInt(mux.Vars(r)["id"], 10, 64)
	if err != nil {
		errResp(w, http.StatusBadRequest, "invalid user id")
		return
	}
	page, _     := strconv.Atoi(r.URL.Query().Get("page"))
	pageSize, _ := strconv.Atoi(r.URL.Query().Get("page_size"))
	if page < 1     { page = 1 }
	if pageSize < 1 { pageSize = 20 }
	offset := (page - 1) * pageSize

	rows, err := a.DB.QueryContext(r.Context(), `
		SELECT w.id, w.title, w.notes, w.started_at, w.finished_at, w.duration_sec, w.calories_burned,
		       w.created_at
		FROM workouts w
		WHERE w.user_id = $1
		ORDER BY w.started_at DESC
		LIMIT $2 OFFSET $3`, userID, pageSize, offset,
	)
	if err != nil {
		errResp(w, http.StatusInternalServerError, err.Error())
		return
	}
	defer rows.Close()

	var workouts []Workout
	for rows.Next() {
		var wkt Workout
		wkt.UserID = userID
		if err := rows.Scan(&wkt.ID, &wkt.Title, &wkt.Notes, &wkt.StartedAt,
			&wkt.FinishedAt, &wkt.DurationSec, &wkt.CaloriesBurned, &wkt.CreatedAt); err != nil {
			continue
		}
		workouts = append(workouts, wkt)
	}
	respond(w, http.StatusOK, workouts)
}

// GET /users/{id}/workouts/stats?from=2024-01-01&to=2024-01-31 — статистика
func (a *App) getWorkoutStats(w http.ResponseWriter, r *http.Request) {
	userID, err := strconv.ParseInt(mux.Vars(r)["id"], 10, 64)
	if err != nil {
		errResp(w, http.StatusBadRequest, "invalid user id")
		return
	}
	from := r.URL.Query().Get("from")
	to   := r.URL.Query().Get("to")
	if from == "" { from = "1970-01-01" }
	if to   == "" { to   = "9999-12-31" }

	var stats WorkoutStats
	err = a.DB.QueryRowContext(r.Context(), `
		SELECT
		    COUNT(DISTINCT w.id),
		    SUM(w.duration_sec),
		    AVG(w.duration_sec),
		    SUM(w.calories_burned),
		    AVG(w.calories_burned),
		    SUM(COALESCE(we.weight_kg,0)*COALESCE(we.sets,1)*COALESCE(we.reps,1)),
		    SUM(we.distance_m)/1000.0,
		    MIN(w.started_at),
		    MAX(w.started_at)
		FROM workouts w
		LEFT JOIN workout_exercises we ON we.workout_id = w.id
		WHERE w.user_id   = $1
		  AND w.started_at >= $2::TIMESTAMPTZ
		  AND w.started_at <  $3::TIMESTAMPTZ + INTERVAL '1 day'`,
		userID, from, to,
	).Scan(
		&stats.TotalWorkouts,
		&stats.TotalDurationSec,
		&stats.AvgDurationSec,
		&stats.TotalCalories,
		&stats.AvgCaloriesPerWkt,
		&stats.TotalVolumeKg,
		&stats.TotalDistanceKm,
		&stats.FirstWorkout,
		&stats.LastWorkout,
	)
	if err != nil {
		errResp(w, http.StatusInternalServerError, err.Error())
		return
	}
	respond(w, http.StatusOK, stats)
}

// ─── Main ─────────────────────────────────────────────────────

func main() {
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		dsn = "postgresql://postgres:postgres@localhost:5432/fitness?sslmode=disable"
	}

	app, err := NewApp(dsn)
	if err != nil {
		log.Fatalf("failed to connect to database: %v", err)
	}
	defer app.DB.Close()

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	log.Printf("Fitness Tracker API listening on :%s", port)
	log.Fatal(http.ListenAndServe(":"+port, app.Router))
}

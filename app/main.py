import logging
import time

from fastapi import Depends, FastAPI, HTTPException, Query, Request, Response, status
from fastapi.responses import JSONResponse
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from .config import get_settings
from .database import get_db
from .models import Task
from .schemas import HealthRead, TaskCreate, TaskRead, TaskUpdate, VersionRead

settings = get_settings()

TASK_NOT_FOUND = "Task not found"

logging.basicConfig(
    level=settings.log_level.upper(),
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
logger = logging.getLogger("app")

app = FastAPI(
    title=settings.app_name,
    version=settings.app_version,
    description="Application KPS Tasks API, deployee via CI/CD sur VPS.",
)


@app.middleware("http")
async def log_requests(request: Request, call_next):
    started_at = time.perf_counter()
    response = await call_next(request)
    duration_ms = (time.perf_counter() - started_at) * 1000
    logger.info(
        "%s %s -> %s %.2fms",
        request.method,
        request.url.path,
        response.status_code,
        duration_ms,
    )
    return response


@app.get("/", tags=["meta"])
def root() -> VersionRead:
    return VersionRead(
        name=settings.app_name,
        version=settings.app_version,
        environment=settings.app_env,
    )


@app.get("/version", tags=["meta"])
def version() -> VersionRead:
    return VersionRead(
        name=settings.app_name,
        version=settings.app_version,
        environment=settings.app_env,
    )


@app.get("/health", response_model=HealthRead, tags=["meta"])
def health(db: Session = Depends(get_db)):
    try:
        db.execute(text("SELECT 1"))
    except SQLAlchemyError as exc:
        logger.exception("Database healthcheck failed")
        payload = HealthRead(
            status="degraded",
            database="error",
            version=settings.app_version,
            details=str(exc.__class__.__name__),
        )
        return JSONResponse(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            content=payload.model_dump(),
        )

    return HealthRead(status="ok", database="ok", version=settings.app_version)


@app.get("/tasks", response_model=list[TaskRead], tags=["tasks"])
def list_tasks(
    db: Session = Depends(get_db),
    limit: int = Query(default=50, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
):
    return db.query(Task).order_by(Task.id.asc()).offset(offset).limit(limit).all()


@app.post(
    "/tasks",
    response_model=TaskRead,
    status_code=status.HTTP_201_CREATED,
    tags=["tasks"],
)
def create_task(payload: TaskCreate, db: Session = Depends(get_db)):
    task = Task(**payload.model_dump())
    db.add(task)
    db.commit()
    db.refresh(task)
    logger.info("Task created id=%s title=%s", task.id, task.title)
    return task


@app.get("/tasks/{task_id}", response_model=TaskRead, tags=["tasks"])
def get_task(task_id: int, db: Session = Depends(get_db)):
    task = db.get(Task, task_id)
    if task is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail=TASK_NOT_FOUND
        )
    return task


@app.patch("/tasks/{task_id}", response_model=TaskRead, tags=["tasks"])
def update_task(task_id: int, payload: TaskUpdate, db: Session = Depends(get_db)):
    task = db.get(Task, task_id)
    if task is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail=TASK_NOT_FOUND
        )

    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(task, field, value)

    db.commit()
    db.refresh(task)
    logger.info("Task updated id=%s", task.id)
    return task


@app.delete("/tasks/{task_id}", status_code=status.HTTP_204_NO_CONTENT, tags=["tasks"])
def delete_task(task_id: int, db: Session = Depends(get_db)):
    task = db.get(Task, task_id)
    if task is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail=TASK_NOT_FOUND
        )

    db.delete(task)
    db.commit()
    logger.info("Task deleted id=%s", task_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)

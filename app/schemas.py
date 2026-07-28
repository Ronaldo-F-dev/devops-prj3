from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field

from .models import TaskStatus


class VersionRead(BaseModel):
    name: str
    version: str
    environment: str


class HealthRead(BaseModel):
    status: str
    database: str
    version: str
    details: str | None = None


class TaskBase(BaseModel):
    title: str = Field(min_length=1, max_length=160)
    description: str | None = Field(default=None, max_length=2000)
    status: TaskStatus = TaskStatus.todo


class TaskCreate(TaskBase):
    pass


class TaskUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=160)
    description: str | None = Field(default=None, max_length=2000)
    status: TaskStatus | None = None


class TaskRead(TaskBase):
    model_config = ConfigDict(from_attributes=True)

    id: int
    created_at: datetime
    updated_at: datetime
from .database import Base, engine
from .models import Task  # noqa: F401 - imported so SQLAlchemy registers the model


def main() -> None:
    Base.metadata.create_all(bind=engine)
    print("Database schema initialized.")


if __name__ == "__main__":
    main()

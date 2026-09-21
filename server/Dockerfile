FROM python:3.12-slim
WORKDIR /app
COPY pyproject.toml .
COPY maboy ./maboy
RUN pip install --no-cache-dir .
CMD ["uvicorn", "maboy.app:app", "--host", "0.0.0.0", "--port", "8000"]
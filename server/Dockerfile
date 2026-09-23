FROM node:24-bookworm-slim AS node_runtime

FROM python:3.12-slim
WORKDIR /app
COPY --from=node_runtime /usr/local/bin/node /usr/local/bin/node
RUN apt-get update \
    && apt-get install -y --no-install-recommends ffmpeg \
    && rm -rf /var/lib/apt/lists/*
COPY pyproject.toml .
COPY maboy ./maboy
RUN pip install --no-cache-dir .
CMD ["uvicorn", "maboy.app:app", "--host", "0.0.0.0", "--port", "8000"]

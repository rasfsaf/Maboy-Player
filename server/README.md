# Maboy API — первый этап

Серверная основа по `../target.md`: учетные записи, изоляция данных по пользователям,
идемпотентные операции и инкрементальная синхронизация библиотеки, плейлистов и очереди.
Это **не** готовый плеер: Flutter-клиент, загрузка медиа, OAuth, offline-хранилище
и конфликты при одновременном редактировании с разных устройств — следующие этапы.

## Локально

Из каталога `server`:

```powershell
uv run --extra test pytest -q
uv run uvicorn maboy.app:app --reload
```

По умолчанию используется SQLite-файл `maboy.db`. API-документация: `/docs`.
Для PostgreSQL задайте `DATABASE_URL=postgresql+psycopg://...`.

## Docker Compose (VPS)

Создайте `server/.env` с `POSTGRES_PASSWORD=` (случайный сильный пароль),
затем в каталоге `server` выполните `docker compose up -d --build`.
Порт API слушает только `127.0.0.1:18181`: перед публикацией подключите HTTPS
через reverse proxy. Не запускайте публичный HTTP с bearer-токенами.
Развёрнуто отдельно на `happ-germany` в `/opt/maboy/server` (`maboy-db-1`,
`maboy-api-1`). Внешний HTTPS-маршрут ещё не настроен; существующие сервисы
и прокси-конфигурации не менялись. Локальный healthcheck:
`curl http://127.0.0.1:18181/health`.

## Протокол

`POST /auth/register`, `POST /auth/login` возвращают bearer token.
`POST /sync/operations` принимает `operation_id` (UUID), `kind` и `payload`.
`GET /sync/operations?after=0&limit=100` возвращает операции и курсор.
Поддерживаемые виды операций: `track.upsert`, `playlist.upsert`,
`playlist.set_tracks`, `queue.set`. Последние две операции заменяют полный
упорядоченный список. Повтор с тем же `operation_id` возвращает прежнюю версию,
а повтор с иным содержимым отвергается. При реконструкции клиент применяет
операции по `version` и хранит собственный курсор локально.

В текущем прототипе нет snapshot/compaction, удаления треков и плейлистов,
refresh/revoke токенов, миграций схемы, rate limiting и разрешения конкурентных
правок: до запуска с реальными пользователями они обязательны.
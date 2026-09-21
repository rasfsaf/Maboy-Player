# Maboy — Target

## 1. Цель проекта

**Maboy** — музыкальный плеер и небольшой персональный музыкальный сервис для **Windows и Android**.

Главная идея:

* пользователь добавляет музыку из YouTube;
* музыка скачивается локально;
* библиотека и плейлисты синхронизируются между устройствами через VPS;
* пользователь полностью контролирует порядок треков;
* shuffle создаёт редактируемую очередь, а не скрытую магию;
* приложение остаётся удобным и функциональным без интернета;
* интерфейс минималистичный, преимущественно чёрный;
* Maboy поддерживает несколько независимых пользователей.

Maboy не пытается стать полноценной заменой YouTube или Spotify.

Основная цель — сделать простой, быстрый и приятный музыкальный сервис для небольшой группы пользователей.

---

# 2. Целевые платформы

## Windows

* Windows 10/11 x64.
* Полноценное desktop-приложение.
* Поддержка системных media keys.
* Drag & drop.
* Горячие клавиши.
* Persistent mini player.
* Вставка YouTube URL через clipboard.
* Работа в фоне.

## Android

* Android 7+.
* Background playback.
* Media notification.
* Lock screen controls.
* Bluetooth/headset controls.
* Работа при выключенном экране.
* Android Share Target:

  * YouTube → Поделиться → Maboy.
* Возможность скачать трек непосредственно через Share.

---

# 3. Основной стек

## Client

**Flutter / Dart**

Одна основная кодовая база для:

* Windows;
* Android.

---

## State management

**Riverpod**

Использовать для:

* auth;
* текущего пользователя;
* player state;
* library;
* playlists;
* queue;
* downloads;
* sync;
* settings;
* devices.

---

## Local database

**SQLite + Drift**

Локальная БД является основным источником данных клиента.

Приложение должно продолжать работать без VPS.

---

## Audio

**just_audio**

Для Android:

**audio_service**

Используется для:

* background playback;
* Android Media Session;
* notification;
* lock screen controls;
* Bluetooth controls.

Playback backend должен находиться за отдельным интерфейсом.

---

# 4. Backend

## Stack

* Python
* FastAPI
* PostgreSQL
* WebSocket
* HTTPS
* Caddy или Nginx

Redis в MVP не требуется.

---

# 5. Пользователи

Maboy является многопользовательским приложением.

Каждый пользователь имеет собственные:

* библиотеку;
* плейлисты;
* порядок плейлистов;
* favorites;
* историю;
* очередь;
* playback state;
* устройства;
* настройки;
* состояние синхронизации.

Данные пользователей не должны смешиваться.

---

# 6. Авторизация

Использовать простую систему:

```text
email
password
```

Поддержать:

* Register
* Login
* Logout
* автоматическое восстановление сессии

На сервере:

```text
User
├── id
├── email
├── password_hash
├── created_at
└── updated_at
```

Email уникален.

Пароли никогда не хранятся в plaintext.

Использовать нормальное password hashing:

```text
Argon2
```

или аналогичный современный алгоритм.

---

# 7. Auth tokens

После входа сервер выдаёт токен.

Предпочтительно:

```text
access token
refresh token
```

Клиент автоматически обновляет авторизацию.

Пользователь не должен постоянно вводить пароль.

Защита аккаунтов не является главным направлением разработки, но базовые правила безопасности должны соблюдаться.

---

# 8. Устройства

Один аккаунт может использоваться на нескольких устройствах.

Например:

```text
Арка

├── Desktop
├── Laptop
└── Phone
```

Каждое устройство получает:

```text
device_id
device_name
platform
last_seen
```

Пользователь может изменить имя устройства.

---

# 9. YouTube / Download

Для получения аудио использовать:

**yt-dlp**

Архитектурно:

```text
DownloadProvider
    └── YouTubeDownloadProvider
            └── yt-dlp
```

Остальной код Maboy не должен напрямую зависеть от конкретной реализации yt-dlp.

---

# 10. Windows yt-dlp

Использовать bundled `yt-dlp` executable.

Обновление yt-dlp должно быть возможно без обновления всего приложения.

---

# 11. Android yt-dlp

Использовать Android-compatible интеграцию yt-dlp.

Она должна быть спрятана за Flutter Platform Channel / adapter.

Конкретная wrapper-библиотека должна быть заменяемой.

---

# 12. Добавление трека

Пользователь может вставить:

```text
https://youtube.com/watch?v=...
```

или:

```text
https://youtu.be/...
```

После этого Maboy:

1. Распознаёт URL.
2. Получает metadata.
3. Определяет provider.
4. Получает provider source ID.
5. Проверяет наличие трека.
6. Получает:

   * title;
   * channel/uploader;
   * duration;
   * thumbnail;
   * original URL.
7. Создаёт Track.
8. Начинает локальную загрузку.
9. Сохраняет metadata.
10. Синхронизирует Track через VPS.

---

# 13. Формат аудио

Предпочитать лучший подходящий audio-only поток.

Не выполнять лишнее перекодирование.

Не конвертировать Opus → MP3 просто ради расширения файла.

Хранить максимально близкий к исходному аудиопоток.

---

# 14. Android Share

Maboy должен быть доступен в меню:

```text
YouTube
   ↓
Поделиться
   ↓
Maboy
```

После получения URL:

```text
Maboy
↓
metadata
↓
download
↓
library
↓
sync
```

В настройках:

```text
Share action:

[x] Automatically download
[x] Add to library
[ ] Ask for playlist
```

Если включена автоматическая загрузка, дополнительные подтверждения не нужны.

---

# 15. Библиотека

Основные разделы:

```text
Home
Search
Tracks
Playlists
Favorites
Downloads
History
```

Дополнительно:

* Recently played
* Recently added

---

# 16. Поиск

Поиск должен работать локально и быстро.

Искать по:

* title;
* artist/uploader;
* album, если известен;
* source title.

---

# 17. Track

Пример модели:

```text
Track

id
user_id

provider
source_id
source_url

title
artist
album

duration_ms

thumbnail_url

created_at
updated_at
```

---

# 18. Локальное наличие трека

Файл не является частью основной сущности Track.

Использовать:

```text
DeviceTrack

device_id
track_id

local_path
download_status
file_size

created_at
updated_at
```

Таким образом один Track может существовать:

```text
Server:
Track ABC

Windows:
ABC downloaded

Android:
ABC downloaded

Laptop:
ABC not downloaded
```

---

# 19. Duplicate detection

Для YouTube:

```text
provider = youtube
source_id = VIDEO_ID
```

Для одного пользователя сочетание:

```text
user_id
provider
source_id
```

должно быть уникальным.

Один и тот же YouTube ролик не должен создавать бесконечные копии Track.

---

# 20. Плейлисты

Пользователь может:

* создать плейлист;
* переименовать;
* удалить;
* добавить трек;
* удалить трек;
* добавить несколько треков;
* выбрать несколько треков;
* воспроизвести плейлист;
* включить shuffle;
* добавить плейлист в queue;
* изменить порядок треков;
* изменить порядок самих плейлистов.

---

# 21. Порядок треков внутри Playlist

Это критическая функция.

Пример:

```text
Playlist: Main

1. Deftones
2. Korn
3. Linkin Park
4. Limp Bizkit
```

Пользователь перетаскивает Korn:

```text
1. Korn
2. Deftones
3. Linkin Park
4. Limp Bizkit
```

Новый порядок:

* сохраняется локально;
* синхронизируется с сервером;
* появляется на остальных устройствах.

---

# 22. Порядок самих плейлистов

Пользователь должен иметь возможность вручную менять порядок плейлистов.

Например:

```text
Liked
Gym
Night
Random
Driving
```

Пользователь делает:

```text
Driving
Night
Liked
Gym
Random
```

Этот порядок должен использоваться:

* в Sidebar на Windows;
* в разделе Playlists;
* в Library;
* на Android.

Он должен синхронизироваться между устройствами.

---

# 23. Playlist model

```text
Playlist

id
user_id

name
sort_key

created_at
updated_at
```

Треки:

```text
PlaylistTrack

playlist_id
track_id

sort_key

added_at
```

Не полагаться на порядок строк SQL.

---

# 24. Reorder

Для порядка:

* Playlist;
* PlaylistTrack;
* QueueTrack;

предпочтительно использовать `sort_key`.

Drag & drop не должен требовать переписывания позиций у тысячи элементов при каждом перемещении.

---

# 25. Playback Queue

Queue и Playlist — разные сущности.

Это фундаментальное правило Maboy.

Пример:

```text
Playlist:

A
B
C
D
E
```

При запуске создаётся:

```text
Queue:

A ← playing
B
C
D
E
```

Изменение Queue не должно менять Playlist.

---

# 26. Редактирование Queue

Пользователь может:

* менять порядок drag & drop;
* удалить трек;
* Play next;
* Add to queue;
* очистить queue;
* сохранить queue как playlist;
* shuffle remaining;
* добавлять целый playlist.

---

# 27. Shuffle / Mix

Ключевое требование Maboy.

Shuffle не является скрытым алгоритмом выбора следующего трека.

При нажатии Shuffle создаётся конкретный порядок Queue.

Например:

```text
Playlist:

A
B
C
D
E
F
```

Shuffle:

```text
Current:
D

Up next:

B
F
A
E
C
```

Теперь:

```text
B
F
A
E
C
```

— обычная Queue.

Пользователь может переставить:

```text
F
C
B
A
E
```

После этого Maboy должен воспроизводить:

```text
F → C → B → A → E
```

без повторного скрытого shuffle.

---

# 28. Правило ручного порядка

Приоритет:

```text
Manual order > Shuffle
```

Если пользователь изменил Queue вручную, Maboy обязан уважать новый порядок.

Shuffle не может самопроизвольно менять его.

---

# 29. Reshuffle

Должна быть отдельная команда:

```text
Shuffle remaining
```

Она перемешивает только будущие элементы очереди.

Текущий трек остаётся текущим.

---

# 30. Repeat

Поддержать:

```text
Repeat off
Repeat queue
Repeat one
```

---

# 31. Player

Полный экран Player:

* cover;
* title;
* artist;
* current position;
* duration;
* progress bar;
* previous;
* play/pause;
* next;
* shuffle;
* repeat;
* favorite;
* volume;
* Queue button.

Seek должен ощущаться мгновенным.

---

# 32. Mini Player

На основных экранах доступен persistent mini player.

Windows:

```text
[cover] Track — Artist    ━━━━━━━━━   ⏮ ▶ ⏭    🔊
```

Android:

```text
[cover] Track
Artist            ▶   ⏭
```

Tap открывает полный Player.

---

# 33. Базовые Spotify-like удобства

Maboy должен иметь привычные функции музыкального приложения:

* [ ] Favorites;
* [ ] Recently played;
* [ ] Recently added;
* [ ] History;
* [ ] Play next;
* [x] Add to queue;
* [x] editable queue (reorder + remove);
* [~] editable playlists (добавление треков есть, переименования/удаления пока нет);
* [ ] reorder playlists;
* [ ] shuffle;
* [ ] repeat;
* [x] resume session;
* [x] восстановление Queue (сохраняется в локальном кэше);
* [ ] восстановление current track;
* [ ] восстановление position;
* [ ] search;
* [ ] covers;
* [ ] media controls;
* [ ] sorting;
* [ ] контекстное меню.

---

# 34. Контекстное меню Track

Пример:

```text
Play now
Play next
Add to queue

Add to playlist
Add to favorites

Download
Remove local download

Open source

Remove from library
```

Windows:

* right click.

Android:

* long press / menu.

---

# 35. Download Manager

Состояния:

```text
queued
fetching_metadata
downloading
processing
completed
failed
cancelled
```

Показывать:

* track;
* progress;
* скорость;
* status;
* error;
* retry;
* cancel.

---

# 36. Параллельные загрузки

Maboy должен поддерживать очередь загрузок.

Настройка:

```text
Concurrent downloads:

1
2
3
4
```

Ошибка одного трека не блокирует остальные.

---

# 37. Offline-first

Без интернета пользователь должен иметь возможность:

* открыть приложение;
* войти через сохранённую сессию;
* видеть библиотеку;
* слушать скачанные треки;
* открывать playlists;
* менять порядок playlists;
* менять порядок tracks;
* редактировать queue;
* ставить favorite;
* использовать search.

Изменения сохраняются локально.

После восстановления сети выполняется sync.

---

# 38. Synchronization

Синхронизируются:

```text
Tracks
Playlists
Playlist order
Playlist tracks
Playlist track order
Favorites
History
Queue
Queue order
Playback state
Devices
Settings
```

---

# 39. Sync model

Изменение сначала применяется локально.

Пример:

```text
User moves Track A
↓
SQLite updated
↓
UI immediately updated
↓
sync operation created
↓
VPS receives operation
↓
other clients updated
```

UI не должен ждать ответа VPS для обычных локальных действий.

---

# 40. Realtime

Использовать WebSocket для событий:

```text
track_added
track_updated
track_removed

playlist_added
playlist_updated
playlist_removed
playlist_order_updated

queue_updated

favorite_updated

download_available

playback_updated

device_updated
```

WebSocket не является обязательным для работы приложения.

---

# 41. Automatic download synchronization

Сценарий:

```text
Windows:
пользователь добавил Track A
↓
Windows скачал A
↓
VPS знает о Track A
↓
Android sync
↓
Android видит новый Track A
↓
если Auto Download enabled:
Android скачивает A
```

---

# 42. Download preferences

Настройки:

```text
Auto-download synced music: ON/OFF

Wi-Fi only: ON/OFF
```

Можно сделать отдельно по устройствам.

---

# 43. VPS и аудиофайлы

По умолчанию VPS не хранит музыку.

Он хранит:

```text
source
metadata
user data
sync state
```

Файлы скачиваются непосредственно устройствами.

---

# 44. Возможный fallback

После MVP можно добавить временный media relay:

```text
Windows
↓
VPS
↓
Android
```

например, если исходный YouTube ролик больше недоступен.

Это не является MVP-функцией.

---

# 45. Playback Sync

Сервер может хранить:

```text
user_id
track_id
position_ms
queue_id
queue_index
device_id
updated_at
```

Отправлять position:

* при pause;
* при смене track;
* при seek;
* при закрытии;
* периодически.

Не отправлять update каждую секунду.

---

# 46. Continue listening

Home показывает:

```text
Continue listening
```

Пользователь может продолжить последний Track.

При наличии нескольких устройств Maboy использует последнее актуальное PlaybackState.

---

# 47. History

Хранить:

```text
track_id
started_at
completed
device_id
```

Не создавать новую запись истории каждую секунду воспроизведения.

---

# 48. Основные server entities

```text
User

Device

Track
DeviceTrack

Playlist
PlaylistTrack

Favorite

Queue
QueueTrack

PlaybackState

PlayHistory

SyncOperation
```

---

# 49. UI Design

Основная тема:

**Black / Dark**

Главный фон должен быть практически чёрным.

Не использовать дефолтный серый Material UI.

Направление:

```text
Background       almost black
Surface          slightly brighter
Card             subtle contrast
Border           barely visible

Text primary     white
Text secondary   muted

Accent           one main accent
```

---

# 50. Визуальный стиль

* минимализм;
* крупные covers;
* хороший whitespace;
* чёткая typography;
* никаких лишних рамок;
* короткие animations;
* responsive hover;
* responsive press;
* умеренные rounded corners;
* минимум визуального шума.

Не использовать glassmorphism просто потому что можно.

---

# 51. Covers

Album / video cover является главным визуальным элементом интерфейса.

Можно позже добавить:

```text
Dynamic Accent
```

где accent извлекается из текущей cover.

---

# 52. Windows Layout

Sidebar:

```text
Maboy

Home
Search

Library
├── Tracks
├── Favorites
├── Downloads
└── History

Playlists
├── Driving
├── Night
├── Gym
└── Random

Settings
```

Список Playlists в sidebar должен поддерживать drag & drop reorder.

---

# 53. Android Navigation

Bottom navigation:

```text
Home
Search
Library
```

Mini Player находится над navigation bar.

Full Player открывается tap/swipe.

---

# 54. Playlists screen

Экран должен позволять:

* открыть playlist;
* создать;
* удалить;
* переименовать;
* drag & drop playlists;
* поиск playlists.

Ручной порядок playlists является главным порядком по умолчанию.

---

# 55. Home

Показывать только полезное:

```text
Continue listening

Recently played

Recently added

Favorite playlists
```

Никаких рекламных блоков.

---

# 56. Login Screen

Минималистичный экран:

```text
           Maboy

Email
[________________]

Password
[________________]

      Log in

Create account
```

Без лишней onboarding-параши.

---

# 57. Register

```text
Email
Password
Confirm password
```

После успешной регистрации:

```text
Login automatically
```

---

# 58. Windows shortcuts

```text
Space       Play/Pause

Ctrl + F    Search

Ctrl + L    Search

Ctrl + V    Detect YouTube URL

Ctrl + N    Add URL
```

Поддержать system media keys.

---

# 59. Android conveniences

* Bluetooth controls;
* lock screen;
* notification;
* background playback;
* YouTube Share;
* long press menus;
* swipe actions только там, где они действительно удобны.

---

# 60. Settings

## Account

* email;
* logout.

## Playback

* resume session;
* gapless playback;
* default repeat.

## Downloads

* download directory;
* mobile data;
* parallel downloads;
* auto-download synced tracks;
* Wi-Fi only.

## Sync

* sync enabled;
* playback sync;
* device name.

## Appearance

* accent;
* animations;
* dynamic accent.

---

# 61. MVP

Первая реально используемая версия Maboy должна поддерживать:

### Account

* [x] **register** — **Выполнено** (бэкенд `/auth/register` со scrypt-хешированием паролей, клиент `signIn(register: true)`);
* [x] **login** — **Выполнено** (бэкенд `/auth/login` с выдачей bearer-токена, клиент `signIn`);
* [x] **saved session** — **Выполнено** (токен сохраняется в `FlutterSecureStorage`, состояние в `SharedPreferences`, автовосстановление при старте);
* [x] **logout** — **Выполнено** (удаление токена из защищённого хранилища и сброс локального состояния).

### Platforms

* [~] **Windows** — **Частично** (собран `maboy.exe`, но нет медиа-клавиш, глобальных шорткатов и сайдбара);
* [~] **Android** — **Частично** (собран `maboy.apk`, но нет фоновой службы воспроизведения, медиа-нотификации и Share Target).

### Audio

* [ ] **playback** — **Не выполнено** (аудио-движок `just_audio` отсутствует, воспроизведение не реализовано);
* [ ] **background playback** — **Не выполнено** (`audio_service` и фоновый сервис отсутствуют);
* [ ] **media controls** — **Не выполнено** (системные медиа-контролы не подключены).

### YouTube

* [~] **URL → download** — **Частично** (распознавание YouTube URL и сохранение трека в БД работают; `yt-dlp` и фактическое скачивание аудиофайлов отсутствуют);
* [ ] **Android Share → download** — **Не выполнено** (нет Intent Filter `SEND` и обработчика шаринга).

### Library

* [x] **tracks** — **Выполнено** (сохранение метаданных треков, дедупликация по `provider + source_id`, отображение списка);
* [ ] **search** — **Не выполнено** (локальный поиск не реализован);
* [ ] **favorites** — **Не выполнено** (избранное не реализовано);
* [ ] **history** — **Не выполнено** (история воспроизведения не реализована).

### Playlists

* [x] **create** — **Выполнено** (создание плейлистов локально и через мутацию `playlist.upsert`);
* [ ] **rename** — **Не выполнено** (переименование в интерфейсе отсутствует);
* [ ] **delete** — **Не выполнено** (удаление плейлистов не реализовано);
* [~] **add/remove tracks** — **Частично** (добавление трека через `playlist.set_tracks` работает; удаление трека из плейлиста в UI отсутствует);
* [ ] **reorder tracks** — **Не выполнено** (ручной drag & drop порядок треков внутри плейлиста отсутствует в UI);
* [ ] **reorder playlists** — **Не выполнено** (в модели есть `sort_key`, но в UI нет drag & drop сортировки плейлистов).

### Queue

* [ ] **Play next** — **Не выполнено**;
* [x] **Add to queue** — **Выполнено** (добавление трека в очередь через `queue.set`);
* [x] **reorder** — **Выполнено** (ручной drag-and-drop порядок очереди через `ReorderableListView`);
* [x] **remove** — **Выполнено** (удаление трека из очереди);
* [ ] **clear** — **Не выполнено** (очистка всей очереди отсутствует);
* [ ] **editable shuffle** — **Не выполнено** (создание перемешанной очереди отсутствует).

### Sync

* [x] **multi-device** — **Выполнено** (архитектура синхронизации изолирована по `user_id` и рассчитана на несколько устройств);
* [~] **VPS** — **Частично** (FastAPI сервер и PostgreSQL/SQLite развернуты в docker compose на порту `18181`, но внешний HTTPS роут `https://maboy.dofic.site` пока не настроен);
* [x] **offline-first** — **Выполнено** (локальное сохранение состояния, буфер `pending` мутаций и автоматическая досылка при наличии сети);
* [ ] **realtime updates** — **Не выполнено** (WebSocket-уведомлений об обновлениях нет, только HTTP push/pull).

### UI

* [~] **polished black/dark design** — **Частично** (задана тёмная тема с фоном `#0d0d0f`, но интерфейс является черновым прототипом без Persistent Mini Player, обложек и кастомного стиля).

Если эти вещи не работают стабильно, MVP не считается законченным.

---

# 62. После MVP

Можно добавить:

* lyrics;
* equalizer;
* waveform;
* Discord Rich Presence;
* Android Auto;
* statistics;
* smart playlists;
* playlist import;
* recommendations;
* automatic metadata cleanup;
* dynamic themes;
* temporary VPS file relay.

---

# 63. Non-goals MVP

Не делать на старте:

* платные подписки;
* billing;
* социальную сеть;
* followers;
* comments;
* public profiles;
* web player;
* iOS;
* ML recommendations;
* полноценный YouTube frontend;
* video player;
* сложную enterprise security;
* DRM.

---

# 64. Главный сценарий Maboy

```text
1. Пользователь скачивает Maboy.

2. Создаёт аккаунт:
   email + password.

3. Входит на Windows.

4. Вставляет YouTube URL.

5. Maboy получает metadata.

6. Трек скачивается.

7. Трек появляется в Library.

8. Пользователь создаёт Playlist.

9. Добавляет Tracks.

10. Переставляет Tracks внутри Playlist.

11. Переставляет сам Playlist среди остальных Playlists.

12. Все изменения сохраняются.

13. Пользователь входит с тем же аккаунтом на Android.

14. Library синхронизируется.

15. Playlists появляются в том же порядке.

16. Tracks внутри них находятся в том же порядке.

17. Android при необходимости скачивает музыку.

18. Пользователь запускает Playlist.

19. Включает Shuffle.

20. Maboy создаёт конкретную shuffled Queue.

21. Пользователь вручную меняет порядок Queue.

22. Maboy воспроизводит её строго в установленном порядке.

23. Пользователь отправляет новый трек:
    YouTube → Share → Maboy.

24. Maboy скачивает Track.

25. Через sync он появляется на Windows.

26. Интернет пропадает.

27. Уже скачанная музыка, Playlists и Queue продолжают работать.
```

---

# 65. Главные продуктовые правила

## Rule 1

**User order always wins.**

Если пользователь поставил Track или Playlist в конкретное место — Maboy не должен самостоятельно менять этот порядок.

## Rule 2

**Playlist != Queue.**

Изменение одного не должно неожиданно менять другое.

## Rule 3

**Offline is normal state.**

Отсутствие VPS не должно превращать Maboy в кирпич.

## Rule 4

**Server synchronizes. Client plays.**

VPS не должен без необходимости находиться между пользователем и аудиофайлом.

## Rule 5

**Simple beats universal.**

Если функция не улучшает основной музыкальный сценарий, она не нужна в MVP.

## Rule 6

**Maboy should feel intentional.**

Интерфейс не должен выглядеть как набор стандартных Flutter widgets.

Каждый основной экран должен быть спроектирован как часть одного цельного продукта.

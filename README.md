# ru-files-mcp

Удалённый MCP-сервер на **Cloudflare Workers** для российских файловых хранилищ. Подключается в Claude как
кастомный коннектор по одному URL — без локальных процессов.

[![Deploy to Cloudflare](https://deploy.workers.cloudflare.com/button)](https://deploy.workers.cloudflare.com/?url=https://github.com/qmurzik/qmods-client/tree/claude/ru-files-mcp)

| Сервис | Префикс | Что нужно |
|---|---|---|
| Яндекс Диск (официальный REST API) | `yadisk_*` | `YANDEX_DISK_TOKEN` |
| Публичные ссылки Яндекс Диска | `yadisk_public_*` | ничего |
| Облако Mail.ru (**неофициальный** API, как в rclone) | `mailru_*` | `MAILRU_EMAIL`, `MAILRU_APP_PASSWORD` |
| Публичные ссылки Облака Mail.ru | `mailru_public_*` | ничего |
| S3: Yandex Object Storage, Selectel, VK Cloud, Cloud.ru, любой S3 | `s3_*` | `S3_PROVIDER`, `S3_ACCESS_KEY`, `S3_SECRET_KEY` (+ опц. `S3_ENDPOINT`, `S3_REGION`) |

Если секреты сервиса не заданы, его инструменты просто не регистрируются — сервер работает с остальными.

## Как это устроено

- MCP по Streamable HTTP, stateless: `createMcpHandler` из `agents/mcp/server` + `@modelcontextprotocol/server` (MCP SDK v2).
- Авторизация — секретный путь: `https://<worker>.<subdomain>.workers.dev/<ACCESS_KEY>/mcp`.
  Неверный ключ или любой другой путь → `404`. OAuth не используется.
- Большие файлы через воркер не идут: скачивание — прямые ссылки (`*_download_link`, `s3_presigned_url`),
  загрузка больших — `yadisk_upload_from_url` или `s3_presigned_url` c `method=PUT`.
  Текстовые чтение/запись ограничены **1 МБ**.
- Ошибки внешних API возвращаются в результате инструмента понятным текстом (`isError: true`), а не исключением.

## Инструменты

**Яндекс Диск** (`YANDEX_DISK_TOKEN`): `yadisk_disk_info`, `yadisk_list` (limit/offset), `yadisk_recent`,
`yadisk_search` (подстрока в имени/пути по плоскому списку файлов), `yadisk_metadata`, `yadisk_get_download_link`,
`yadisk_read_text` (≤1 МБ), `yadisk_upload_text` (≤1 МБ), `yadisk_upload_from_url`, `yadisk_operation_status`,
`yadisk_mkdir`, `yadisk_copy`, `yadisk_move`, `yadisk_delete` (в корзину; `permanently=true` — насовсем),
`yadisk_publish`, `yadisk_unpublish`, `yadisk_list_trash`, `yadisk_restore`.

**Публичные ссылки Яндекс Диска** (без токена): `yadisk_public_info` (метаданные + содержимое папки),
`yadisk_public_download_link`. Принимают `https://disk.yandex.ru/d/...`, `https://yadi.sk/...` или `public_key`.

**Облако Mail.ru** (неофициальный API): `mailru_list`, `mailru_metadata`, `mailru_download_link`, `mailru_mkdir`,
`mailru_move`, `mailru_delete`, `mailru_publish`.
Авторизация и эндпоинты взяты из [rclone backend/mailru](https://github.com/rclone/rclone/tree/master/backend/mailru):
OAuth password grant на `o2.mail.ru/token` (`client_id=cloud-win`), JSON `/api/m1/*`, бинарный протокол meta-сервера
(mkdir/move) и диспетчер `dispatcher.cloud.mail.ru`. Mail.ru может сломать это в любой момент.
⚠️ Ссылка из `mailru_download_link` содержит временный токен доступа к аккаунту — не публикуйте её.

**Публичные ссылки Облака Mail.ru** (без авторизации): `mailru_public_list` (содержимое + прямые ссылки на файлы),
`mailru_public_download_link`.

**S3**: `s3_list_buckets`, `s3_list_objects` (prefix/delimiter/continuation_token), `s3_get_object` (текст ≤1 МБ),
`s3_put_object` (текст ≤1 МБ), `s3_delete_object`, `s3_presigned_url` (GET/PUT).

Пресеты `S3_PROVIDER`:

| `S3_PROVIDER` | Endpoint | Регион |
|---|---|---|
| `yandex` | `https://storage.yandexcloud.net` | `ru-central1` |
| `selectel` | `https://s3.ru-1.storage.selcloud.ru` | `ru-1` |
| `vk` | `https://hb.ru-msk.vkcloud-storage.ru` | `ru-msk` |
| `cloudru` | `https://s3.cloud.ru` | `ru-central-1` |

Для другого провайдера или региона задайте `S3_ENDPOINT` и `S3_REGION` (они перекрывают пресет). Используется path-style адресация.

## Как получить токены

### Яндекс Диск
1. Откройте <https://oauth.yandex.ru/client/new>, создайте приложение (платформа «Веб-сервисы»).
2. Redirect URI: `https://oauth.yandex.ru/verification_code`.
3. Права доступа (Яндекс Диск REST API): `cloud_api:disk.read`, `cloud_api:disk.write`, `cloud_api:disk.info`,
   `cloud_api:disk.app_folder`.
4. Скопируйте ClientID и откройте в браузере
   `https://oauth.yandex.ru/authorize?response_type=token&client_id=<ClientID>` — после подтверждения
   вы получите OAuth-токен. Это и есть `YANDEX_DISK_TOKEN` (передаётся как `Authorization: OAuth <token>`).

### Облако Mail.ru
Обычный пароль не подойдёт. Создайте **пароль для внешнего приложения**: id.mail.ru → «Безопасность» →
«Пароли для внешних приложений» → «Добавить» (доступ к Облаку / полный доступ). `MAILRU_EMAIL` — ваш адрес
(`user@mail.ru`, `@bk.ru`, `@inbox.ru`, `@list.ru`), `MAILRU_APP_PASSWORD` — сгенерированный пароль.

### S3
Ключи выдаются в консоли провайдера:
- **Yandex Cloud**: сервисный аккаунт с ролью `storage.editor` → «Создать статический ключ доступа».
- **Selectel**: Панель → «Сервисные пользователи» → пользователь с ролью на Object Storage → S3-ключи.
- **VK Cloud**: Объектное хранилище → «Аккаунты» → добавить аккаунт → Access Key / Secret Key.
- **Cloud.ru (Evolution)**: «Управление профилем» → «Ключи доступа» → создать; Access Key имеет вид `<tenant_id>:<key_id>`.

## Деплой

### Кнопкой
Нажмите «Deploy to Cloudflare» выше, затем задайте секреты в дашборде Workers → Settings → Variables and Secrets.

### Вручную
```bash
npm install
npx wrangler login              # или export CLOUDFLARE_API_TOKEN=...
npx wrangler deploy

openssl rand -hex 24 | npx wrangler secret put ACCESS_KEY
npx wrangler secret put YANDEX_DISK_TOKEN
npx wrangler secret put MAILRU_EMAIL
npx wrangler secret put MAILRU_APP_PASSWORD
npx wrangler secret put S3_PROVIDER     # yandex | selectel | vk | cloudru
npx wrangler secret put S3_ACCESS_KEY
npx wrangler secret put S3_SECRET_KEY
```
Секреты нельзя класть в код или `wrangler.jsonc`. Для локальной разработки скопируйте `.dev.vars.example` в `.dev.vars`
(он в `.gitignore`) и запустите `npm run dev`.

### Подключение в Claude
Settings → Connectors → «Add custom connector» → URL `https://ru-files-mcp.<subdomain>.workers.dev/<ACCESS_KEY>/mcp`.
URL содержит ключ — относитесь к нему как к паролю. Сменить ключ: `npx wrangler secret put ACCESS_KEY`.

### Проверка
```bash
URL=https://ru-files-mcp.<subdomain>.workers.dev/<ACCESS_KEY>/mcp
H='-H Content-Type:application/json -H Accept:application/json,text/event-stream'
curl -s $H -X POST $URL -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"curl","version":"1"}}}'
curl -s $H -H 'MCP-Protocol-Version: 2025-06-18' -X POST $URL -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
# или: npx @modelcontextprotocol/inspector
```

## Что не добавлено и почему

Добавлялись только сервисы со стабильным HTTP-API без браузерной капчи. На момент разработки ни у одного из этих
сервисов публичного API нет:

| Сервис | Причина |
|---|---|
| DropMeFiles | Нет публичного/документированного API — только веб-интерфейс для анонимных загрузок; работать можно лишь эмулируя браузер. |
| WDfiles | Не найдено ни документации API, ни описания протокола. |
| СберДиск | Не найдено публичного API или WebDAV — только официальные приложения и веб-интерфейс. |
| МТС «Вторая память» | Не найдено публичного API или WebDAV; вход через МТС ID (номер телефона + SMS). |
| Облако Билайн | Не найдено публичного API или WebDAV; сервис для абонентов, вход по номеру телефона. |

Реверс-инжиниринг их приватных API был бы ненадёжным, а вход по SMS требует интерактивной авторизации,
которую удалённый stateless-сервер выполнить не может. Если у сервиса появится API — модуль легко добавить в `src/services/`.

## Лицензия
MIT

# DoomPB — подробный план разработки

> **Проект:** DoomPB — нативный порт оригинального Doom на PureBasic 6.41
> **Статус документа:** план / roadmap (не отчёт о выполненной работе)
> **Редакция:** 1.0 · 14 ноября 2026
> **Лицензия кода:** GPL-2.0-only
> **Целевая игра для первого релиза:** The Ultimate Doom (1995), IWAD 1.9ud
> **Основной референс:** [id-Software/DOOM, `linuxdoom-1.10`](https://github.com/id-Software/DOOM/tree/master/linuxdoom-1.10)
> **Вспомогательный референс:** [Chocolate Doom](https://github.com/chocolate-doom/chocolate-doom)

## 1. Цель проекта

Создать самостоятельный исходный порт Doom, написанный на **PureBasic 6.41**, с сохранением поведения оригинального движка, его программного рендеринга, структуры ресурсов и игровой логики. Это **не** обёртка над DLL/EXE оригинального Doom, не новый движок «по мотивам» и не запуск C-кода под видом PureBasic.

**Первая цель:** корректно открыть приобретённый `DOOM.WAD`, прочитать каталог ресурсов, декодировать `PLAYPAL` и `TITLEPIC` и вывести титульный экран в окне PureBasic.

**Цель 1.0:** пройти все четыре эпизода The Ultimate Doom с оригинальными механиками, отрисовкой, управлением, звуком, музыкой, меню и сохранениями. Основной приоритет — корректность, а не графические улучшения.

### 1.1. Зафиксированные решения

| Область | Решение |
|---|---|
| Репозиторий | `DoomPB` (публичный GitHub-репозиторий после создания владельцем) |
| Язык | PureBasic **6.41**, полная версия |
| Платформы | Windows x64 — основная платформа первого цикла; Linux x64 — обязательная до 1.0 |
| Источник алгоритмов | Linux Doom 1.10; Chocolate Doom — для проверки поведения/портируемости |
| Графика мира | Классический программный renderer, индексированный буфер 320×200 |
| Вывод/ввод | Встроенные средства PureBasic; без обязательной SDL и без C-движка |
| Игровая логика | 35 tics/с; фиксированная игровая арифметика и оригинальная последовательность обновления |
| Система контроля версий | Git, небольшие проверяемые PR/коммиты |
| AI-агент | OpenCode Desktop + DeepSeek V4.1 Flash 1017; VS Code + Kilo Code — дополнительная среда |
| Ресурсы | Коммерческие IWAD не распространять и не коммитить |
| Лицензия | GPL-2.0-only, с сохранением соответствующих авторских уведомлений |

> **Уточнение:** «без внешнего движка» не означает, что сама библиотека отображения PureBasic не использует системные графические API. Рендеринг Doom остаётся программным; способ вывода готового кадра на экран — отдельный платформенный слой.

### 1.2. Известный тестовый IWAD

| Поле | Значение |
|---|---|
| Игра | The Ultimate Doom, версия 1.9ud |
| Имя файла у владельца | `DOOM.WAD` (имя само по себе не определяет версию) |
| Тип | `IWAD` |
| Размер | 12 408 292 байта |
| Ресурсов (lumps) | 2306 |
| MD5 | `c4fe9fd920207691a9f493668e0a2083` |
| SHA-1 | `9b07b02ab3c275a6a7570c3f73cc20d63a0e3833` |
| Карты | 4 эпизода, 36 карт, включая секретные |

MD5 нужен для распознавания *известной* сборки и регрессионных тестов. Загрузчик не должен требовать только этот хеш: в дальнейшем понадобятся другие легальные IWAD, а также PWAD-оверлеи.

## 2. Область работ и границы релиза

### Включено в 1.0

- Бинарный WAD-формат (`IWAD`, `PWAD`), проверка целостности и приоритет загрузки ресурсов.
- PLAYPAL, COLORMAP, patch-графика, flats, составные wall textures, спрайты, шрифты и элементы меню.
- Четыре эпизода Ultimate Doom; загрузка карт и всех необходимых стандартных структур.
- Программный BSP-рендерер: стены, полы, потолки, небо, прозрачные/маскированные текстуры, спрайты, освещение.
- Оригинальная физика, перемещение, коллизии, игрок, монстры, оружие, предметы, триггеры и специальные секторы.
- Оригинальные 35 игровых тиков/с, генератор случайных чисел и детерминированный порядок обновления.
- HUD, automap, меню, пауза, экран между уровнями, финалы, чит-коды.
- Звуковые эффекты и музыка с сохранением смысла оригинальных ресурсов и поведения.
- Сохранение/загрузка игр; одиночная игра, настройки и базовая поддержка демозаписей/воспроизведения при достаточной совместимости.
- Сборки под Windows x64 и Linux x64, документация и пакеты без коммерческих WAD.

### Не является обязательным для 1.0

- Doom II / Final Doom, Boom/MBF/GZDoom-расширения и современные map formats.
- Сетевой multiplayer; выделить в отдельный этап после стабилизации single-player.
- OpenGL/Vulkan-renderer, 3D-акселерация геометрии, HDR, динамические тени.
- 60/120 FPS логики, interpolation и повышенные разрешения рендеринга.
- Порт на macOS, ARM, мобильные платформы и консоли.
- Точные до байта файлы сохранений всех DOS-версий — оценивать отдельно.

## 3. Организация исходников

```text
DoomPB/
├── .github/
│   ├── ISSUE_TEMPLATE/
│   └── workflows/                # После настройки доступной среды сборки
├── docs/
│   ├── DEVELOPMENT_PLAN.md       # Этот документ
│   ├── ARCHITECTURE.md
│   ├── PORTING_NOTES.md
│   ├── TESTING.md
│   └── COMPATIBILITY.md
├── src/
│   ├── DoomPB.pb                 # Точка входа и порядок инициализации
│   ├── Core/
│   │   ├── Types.pbi
│   │   ├── Fixed.pbi
│   │   ├── Endian.pbi
│   │   ├── Memory.pbi
│   │   ├── Random.pbi
│   │   ├── Timer.pbi
│   │   └── Log.pbi
│   ├── WAD/
│   │   ├── WAD.pbi
│   │   ├── LumpCache.pbi
│   │   └── IWADInfo.pbi
│   ├── Graphics/
│   │   ├── Palette.pbi
│   │   ├── Patch.pbi
│   │   ├── Texture.pbi
│   │   ├── FrameBuffer.pbi
│   │   └── Video.pbi
│   ├── Map/
│   │   ├── MapTypes.pbi
│   │   ├── MapLoader.pbi
│   │   └── MapValidate.pbi
│   ├── Renderer/
│   │   ├── Geometry.pbi
│   │   ├── BSP.pbi
│   │   ├── Segs.pbi
│   │   ├── Planes.pbi
│   │   ├── Sprites.pbi
│   │   ├── Draw.pbi
│   │   └── RenderMain.pbi
│   ├── Game/
│   │   ├── Game.pbi
│   │   ├── Player.pbi
│   │   ├── Physics.pbi
│   │   ├── Thinker.pbi
│   │   ├── Objects.pbi
│   │   ├── Enemy.pbi
│   │   ├── Weapons.pbi
│   │   ├── Specials.pbi
│   │   ├── SaveGame.pbi
│   │   └── Demo.pbi
│   ├── UI/
│   │   ├── HUD.pbi
│   │   ├── Menu.pbi
│   │   ├── Automap.pbi
│   │   └── Intermission.pbi
│   ├── Audio/
│   │   ├── Sound.pbi
│   │   ├── Music.pbi
│   │   └── MUS.pbi
│   └── Platform/
│       ├── Input.pbi
│       ├── Display.pbi
│       ├── Timing.pbi
│       └── Config.pbi
├── tests/
│   ├── unit/                    # Генераторы синтетических WAD и тесты без IWAD
│   ├── integration/             # Локальные проверки с пользовательским IWAD
│   ├── golden/                  # Только производные метрики, без лиценз. ресурсов
│   └── fixtures/                # Авторские минимальные тестовые бинарники
├── scripts/
│   ├── build.ps1
│   ├── build.sh
│   ├── test.ps1
│   └── test.sh
├── local-data/                  # Игровые ресурсы только на компьютере пользователя
│   └── DOOM.WAD                 # НЕ КОММИТИТЬ
├── build/                       # НЕ КОММИТИТЬ
├── .gitignore
├── .gitattributes
├── AGENTS.md
├── README.md
├── LICENSE
└── CHANGELOG.md
```

Структура ориентировочная: не нужно создавать десятки пустых файлов заранее. Добавлять модули по мере реализации, избегать циклических `XIncludeFile` и скрытых глобальных зависимостей. Оригинальные C-исходники держать **рядом** с рабочим репозиторием (например, `../doom-original/`); зафиксировать используемый upstream commit в документации. Не смешивать лицензированный код и локальные коммерческие WAD.

### 3.1. Сопоставление с оригинальным C-кодом

| Original Linux Doom | Зона DoomPB | Основная задача |
|---|---|---|
| `w_wad.c`, `z_zone.c` | `WAD/`, `Core/Memory.pbi` | Каталог ресурсов, кэш, время жизни объектов |
| `m_fixed.c`, `m_random.c`, `tables.c` | `Core/` и `Renderer/` | Численные операции, RNG, таблицы углов |
| `v_video.c`, `i_video.c` | `Graphics/`, `Platform/Display.pbi` | Patch draw, framebuffer, представление кадра |
| `r_data.c` | `Graphics/Texture.pbi` | Текстуры, flats, light tables |
| `p_setup.c` | `Map/MapLoader.pbi` | Создание геометрии/объектов уровня |
| `r_main.c`, `r_geom.c` | `Renderer/RenderMain.pbi`, `Geometry.pbi` | Параметры камеры и геометрия |
| `r_bsp.c`, `r_segs.c` | `Renderer/BSP.pbi`, `Segs.pbi` | BSP, occlusion, стены |
| `r_plane.c`, `r_draw.c` | `Renderer/Planes.pbi`, `Draw.pbi` | Visplanes, колонки, spans |
| `r_things.c` | `Renderer/Sprites.pbi` | Видимые и маскированные спрайты |
| `p_tick.c`, `p_map.c`, `p_maputl.c` | `Game/Thinker.pbi`, `Physics.pbi` | Tics, collisions, blockmap |
| `p_mobj.c`, `p_enemy.c`, `p_inter.c` | `Game/Objects.pbi`, `Enemy.pbi` | Состояния, AI, взаимодействия |
| `p_pspr.c`, `p_user.c` | `Game/Weapons.pbi`, `Player.pbi` | Оружие, игрок |
| `p_spec.c`, `p_doors.c` и смежные | `Game/Specials.pbi` | Сектора, двери, лифты, телепорты |
| `g_game.c`, `p_saveg.c` | `Game/Game.pbi`, `SaveGame.pbi`, `Demo.pbi` | Состояние игры, сохранения, демо |
| `m_menu.c`, `st_stuff.c`, `am_map.c` | `UI/` | Меню, HUD, автомапа |
| `s_sound.c`, `i_sound.c` | `Audio/` | Звук, музыка, platform backend |

Не переносить по одному C-файлу механически: границы модулей адаптировать к PureBasic, сохраняя последовательность вычислений и семантику алгоритмов.

## 4. Технические правила совместимости

1. **Бинарные данные:** WAD хранит целые в little-endian. Для файла использовать явное чтение `u8/u16/u32`, проверки смещения и размера; нельзя зависеть от выравнивания структур или порядка полей в памяти.
2. **Числа и указатели:** исходные 32-битные `int`/`fixed_t` сопоставлять с 32-битными типами PureBasic (`.l`), адреса — с pointer-sized `.i`/указателями, широкие промежуточные значения — с `.q`. Проверять signedness, переполнение и сдвиги.
3. **Fixed-point:** сохранять формат 16.16 (`FRACBITS = 16`, `FRACUNIT = 65536`) и отдельные функции умножения/деления с явными правилами переполнения и округления; не подменять операции плавающей точкой.
4. **Детерминизм:** RNG, порядок thinker-обновлений, обработка событий, привязка ввода и 35 tics/с должны быть повторяемы. Отрисовка не должна изменять игровую симуляцию.
5. **Память:** чётко определить владельцев буферов WAD, кэша текстур, карты и временных структур, правила выделения/освобождения и ошибки при нехватке памяти.
6. **WAD-оверлеи:** сохранить порядок загрузки и правило разрешения повторяющихся имён (приоритет более поздней записи), включая zero-sized marker lumps.
7. **Графика:** исходный render target — 320×200, 8-bit palette indices. На экран выводить масштабированный 32-bit RGB/RGBA буфер с ближайшей фильтрацией и правильным aspect ratio в отдельном слое.
8. **Платформы:** для платформенных отличий использовать ограниченные модули `Platform/`, а не разбросанные условные директивы по gameplay.
9. **Синтаксис:** при добавлении PureBasic API сверяться с документацией именно PureBasic 6.41 и сразу запускать компилятор. Не предполагать существование функций по аналогии с C/другими Basic.
10. **Ошибочные файлы:** WAD parser — поверхность обработки недоверенных данных. Никаких чтений за концом файла, умножений без контроля переполнения, неконтролируемой рекурсии в BSP или allocations по недостоверным размерам.

### 4.1. Важная особенность вывода на Linux

В документации PureBasic отмечено, что рисование через `StartDrawing(ScreenOutput())` на Linux может работать медленно из-за копирования экранного буфера. Поэтому нужен отдельный 320×200 буфер в RAM и адаптер вывода кадров; в раннем прототипе можно выбрать простой путь, но перед рендерером протестировать **два способа presentation** и зафиксировать более быстрый. Мир и игровой цикл не должны зависеть от выбранного метода вывода.

## 5. Дорожная карта (milestones)

Порядок ниже важнее условных версий. Выполнение milestone подтверждается **работающей сборкой и тестами**, а не количеством написанных файлов.

### M0 — Основа репозитория и воспроизводимая сборка (`v0.0.x`)

**Зависимости:** отсутствуют.

- [ ] Создать публичный GitHub-репозиторий `DoomPB`.
- [ ] Добавить `LICENSE` (полный текст GPL-2.0), `README.md`, `.gitignore`, `AGENTS.md`, план и архитектурный журнал.
- [ ] Клонировать оригинал id Software в соседний каталог; записать URL и commit SHA.
- [ ] Создать `src/DoomPB.pb` с `EnableExplicit`, логированием и корректным кодом завершения.
- [ ] Проверить `pbcompiler --version`, `--check`, обычную сборку в `build/`.
- [ ] Добавить `scripts/build.ps1` для Windows и `scripts/build.sh` для Linux; пути компилятора настраиваемые, без жёстких абсолютных путей в репозитории.
- [ ] Создать тестовый runner и соглашение о кодах возврата.
- [ ] Убедиться, что `DOOM.WAD`, executable и временные файлы исключены из Git.

**Критерий готовности:** checkout проекта компилируется в чистый исполняемый файл, выводит версию и завершается без ошибок; при отсутствии IWAD нет аварийного завершения.

### M1 — WAD Loader + TITLEPIC (`v0.1.0`) — **первая контрольная точка**

**Основные модули:** `WAD.pbi`, `IWADInfo.pbi`, `Endian.pbi`, `Palette.pbi`, `Patch.pbi`, `FrameBuffer.pbi`, `Video.pbi`.

- [ ] Реализовать чтение заголовка WAD: signature (`IWAD`/`PWAD`), число lumps, offset каталога.
- [ ] Проверять границы заголовка, каталога и каждого lump на базе 64-битных промежуточных значений.
- [ ] Считывать записи каталога (offset, length, 8-байтное имя); имена — ASCII, нормализация без предположений о null-termination.
- [ ] Реализовать поиск по имени, поиск по индексу, чтение байтов, повторяющиеся имена, маркеры нулевой длины.
- [ ] Поддержать несколько WAD в будущем без изменения публичного API загрузчика.
- [ ] Распознать тестовый Ultimate Doom 1.9ud по размеру/хешу; вывести информацию о файле и `2306` lumps.
- [ ] Загрузить первую палитру `PLAYPAL` (256 RGB-троек; всего в ресурсе обычно 14 палитр).
- [ ] Декодировать Doom patch-изображения: width/height, offsets, column offsets, posts, прозрачность, end-of-column marker.
- [ ] Загрузить `TITLEPIC`; вывести его с корректной палитрой, пропорциями и без искажений.
- [ ] Реализовать явные сообщения об ошибках и безопасное завершение при плохом WAD.
- [ ] Создать синтетические тестовые IWAD/PWAD: пустой каталог, invalid offsets, duplicate names, truncated patch, oversized column.

**Критерий готовности:** на Windows появляется **оригинальный титульный экран**, полученный непосредственно из `DOOM.WAD`; дамп 2306 элементов совпадает с ожидаемой структурой; некорректные WAD не приводят к краху. На этой стадии игры ещё нет.

### M2 — Ресурсы, текстуры и загрузка карты (`v0.2.0`)

**Основные модули:** `LumpCache.pbi`, `Texture.pbi`, `MapTypes.pbi`, `MapLoader.pbi`, `MapValidate.pbi`.

- [x] Прочитать `COLORMAP`, `PNAMES`, `TEXTURE1` и при наличии `TEXTURE2`.
- [x] Реализовать сборку wall textures из patches, прозрачность, origin offsets.
- [x] Реализовать flats 64×64, ресурсную таблицу sprites, правила выбора lump по namespace/marker.
- [x] Разобрать карту `E1M1`: `THINGS`, `LINEDEFS`, `SIDEDEFS`, `VERTEXES`, `SEGS`, `SSECTORS`, `NODES`, `SECTORS`, `REJECT`, `BLOCKMAP`.
- [x] Правильно преобразовывать файловые индексы в собственные массивы и ссылки; не хранить указатели в файле.
- [x] Проверить количество структур и перекрёстные ссылки, связанные sectors/subsectors/lines.
- [x] Вывести технический отчёт E1M1: размер, количество геометрических элементов, список обнаруженных текстур.
- [x] Обработать повреждённые ссылки и truncated map lumps без доступа за пределы памяти.
- [x] Покрыть минимум E1M1, E1M2, E4M1 структурными тестами.

**Критерий готовности:** карты загружаются в память без ошибок, ссылки между объектами проверены, текстуры и flats декодируются корректно. Рендеринга мира пока нет.

**Статус (16 ноября 2026):** M2 выполнен на Windows x64 (PureBasic 6.41), версия
`0.2.0` подготовлена в рабочем дереве. Синтетические наборы M1/M2-01…M2-07
проходят полностью; реальный Ultimate Doom 1.9ud проверен read-only: 287/287
wall textures собраны, `MapLevelValidateResources` подтвердил flats и textures
для E1M1, E1M2 и E4M1. `LumpCache.pbi` и оригинальный renderer-side column
cache сознательно отложены: для текущей single-IWAD загрузки они не требуются.
Linux x64 — **NOT RUN**. Коммит/тег `v0.2.0` создаёт владелец.

### M3 — Геометрия и первые стены (`v0.3.0`)

**Основные модули:** `Fixed.pbi`, `Geometry.pbi`, `BSP.pbi`, `WallVisibility.pbi`, `WallView.pbi`, `WallProject.pbi`, `WallDraw.pbi`, `RenderMain.pbi`, `WallTextureMapping.pbi`, `WallTextureCache.pbi`, `WallLighting.pbi`, `TexturedWallDraw.pbi`, `TexturedRenderMain.pbi`.

- [x] Перенести fixed-point операции и необходимые lookup/trigonometry tables (M3-01/M3-02, Windows x64).
- [x] Реализовать точную экранную горизонтальную проекцию и FOV-углы: `R_InitTextureMapping`, `viewangletox`/`xtoviewangle`/`clipangle` M3-04 для канонического 320-column viewport; полная вертикальная wall projection теперь реализована M3-05.
- [x] Создать камеру с заданной позицией и направлением (M3-03 `BspCamera`,
      signed 16.16 X/Y и raw unsigned BAM heading).
- [x] Перенести обход BSP дерева с правильным порядком near-to-far (M3-03 cull-free
      trace; M3-04 добавляет real `R_CheckBBox` occlusion и online culling без
      изменения старого trace behavior).
- [x] Реализовать headless solid/pass wall clipping с inclusive интервалами,
      owned solidsegs-эквивалентом и реальным occlusion state (M3-04).
- [x] Реализовать вертикальную wall projection `R_StoreWallRange`/`R_ScaleFromGlobalAngle` и отрисовку одноцветных middle/upper/lower колонок с точным clip по экрану (M3-05, Windows x64; debug palette indices 0/176/252/96). Полный vanilla `drawseg_t` records всё ещё отложен: кадр использует caller-owned `WallSpanPlan` numeric metadata.
- [x] M3-06 textured wall-column/COLORMAP lighting: upper/lower/middle wall textures с точным `rw_offset`/width-mask texturecolumn, unsigned `dc_iscale`, pegged `dc_texturemid`, owned used-texture cache и vanilla `scalelight[16][48]` COLORMAP lighting (Windows x64). Masked two-sided middle textures detected/deferred, не рисуются opaque; masked midtexture clipping по экрану остаётся за M3-06 scope (back-to-front drawseg/sprite-style M4).
- [ ] Сравнивать результирующие textured frame hashes / изображения с эталонной сборкой при одинаковых позициях камеры (M3-06 synthetic TI01/TI02 full frames/samples/plans/hashes сверены с независимым Python oracle и остались неизменными в M3-07; owner RI04 independent raw-PATCH composition сравнил 6/6/4 bounded textures для E1M1/E1M2/E4M1 с 0 pixel/mask/opaque/width-mask mismatch, raw owner `COLORMAP` exhaustively identical, bounded first-span column/row sample matched для E1M2/E4M1, а E1M1 frame-pixel oracle — `NOT RUN` reason 3; owner hashes `183BA53FCECECBC8`/`835A0339A38B190E`/`03B5C8CFA517FC7E` остаются **NOT LOCKED**; полное same-camera original-C wall-only image comparison — **REFERENCE UNAVAILABLE**).
- [x] Замерять время CPU на кадр и отсутствие лишних аллокаций внутри горячего цикла (M3-07 BEN01, Windows PB 6.41 x64 verified kernel32 QPC 10 MHz/1 мкс: cold end-to-end 2 warmup + 11 measured, warm textured 20 + 100, warm debug 10 + 100; независимые от хоста min/median/p95/mean µs фактически печатаются, это wall-only synthetic preview, не FPS claim; allocations pre-column 13 = cache 8 + five frame resources; draw path source audit 0 `AllocateMemory(`/`TextureCompose(`/`WADReadLump(`)).

**Критерий готовности:** из фиксированной камеры в E1M1 видны **правильно расположенные и текстурированные стены** без заметных геометрических артефактов; можно воспроизвести один и тот же кадр.

**Статус (27 ноября 2026):** M3-07 завершил Windows x64 интеграцию M3-01…M3-06
как явно ограниченный **wall-only textured preview** release scope; версия
`0.3.0` подготовлена после обязательных gates, но owner commit/tag ещё pending,
и полный M3 не объявляется завершённым: эталонная C-сравнение кадров остаётся
официально незакрытым. M3-01 fixed-point, M3-02 BAM углы/точные trig-tables/
geometry primitives, M3-03 детерминированный обход BSP дерева из fixed camera с
owned `SUBSECTOR`/`SEG` trace, M3-04 точная 320-column проекция, headless solid/
pass interval clipping, source-faithful `R_AddLine` SOLID/PASS screen spans, полный
`R_CheckBBox` и online near-first occlusion walk, M3-05 checked `WallView` и
`R_StoreWallRange`/`R_ScaleFromGlobalAngle` projection/12-bit plans/debug tiers, и
M3-06 exact `rw_offset`/`rw_centerangle` texturecolumn/vanilla width mask/unsigned
`dc_iscale`/pegged `dc_texturemid`/owned used-texture cache/static
`scalelight[16][48]` `COLORMAP` lighting сохранены на Windows x64 PB 6.41.
M3-04 публикует owned числовые экранные интервалы/счётчики; M3-05 рисует debug
palette indices 0/176/252/96 и canonical FNV-1a64; M3-06 рисует те же
middle/upper/lower tiers textured/COLORMAP-lit. `<128` height rows bounded/
documented/fallback-counted, uncovered mask0 routed through composed index-0/
mask-0 policy/counted, masked two-sided middles detected/deferred (never opaque).
Floors/ceilings/sky/sprites/masked back-to-front overlays остаются M4+.
Actual M3-07 tests на owner Windows: synthetic MR01–MR36 + RI01–RI03
**39/444/0, exit 0**; optional owner RI04 E1M1/E1M2/E4M1 **1/149/0, exit 0**
(no path: **0/0, NOT RUN**); BEN01 **1/67/0, exit 0** (QPC 10 MHz/1 мкс; cold
2+11, warm textured 20+100, warm debug 10+100; observed per-frame min/median/
p95/mean мкс representative post-bump runs cold `7910/8136/8297/8126` и
`8461/8528/8682/8547`, warm textured `5899/6103/6287/6168` и
`6422/6628/6758/6634`, warm debug `369/390/399/389` и `370/389/405/390` on the
observed host, varying per run; wall-only metric, not FPS; allocations 13 =
cache8+5, composed 3 unique; hot
draw path has zero allocation/compose/WAD-read tokens). Existing WT01–WT60/
TI01–TI03/TI04, M2 owner mode 36/240 and old M1/M2/M3 regressions remained green.
Synthetic full-pipeline TI01/TI02 fixtures `119A71B79384D465`/
`F05D55B8FE8C07EB` и M3-04 span fingerprints `3EE9969A4FF10052`/
`2FAA660491199243` unchanged; legacy M3-05 debug hashes `4A923E4D357C7BD1`/
`0C9627E5C2FD8D35`/`9AEB8BDD16834359` and M3-04 fingerprint pairs preserved.
Owner textured hashes `183BA53FCECECBC8`/`835A0339A38B190E`/`03B5C8CFA517FC7E`
repeat and pass independent full-plane re-FNV, raw compose/COLORMAP/bounded sample
evidence, но остаются **NOT LOCKED**; полное same-camera C wall-only image
comparison недоступно (E1M1 bounded frame-pixel oracle `NOT RUN` reason 3).
Windows GUI TITLEPIC/debug/textured для E1M1/E1M2/E4M1 открыты/закрыты в exact
960×600 client, nonblank captures, normal `WM_CLOSE`, exit 0; captures ignored,
raw-vs-3x layers различаются. Post-bump full regression после version/script/doc
edits: owner `scripts/test.ps1` **239/239 checks exit 0**; synthetic-only
**175/175 checks exit 0**. Executable-level aggregate actual: synthetic **732
cases / 6,106 assertions / 0 failures**; owner mode **740 / 6,913 / 0** (M2 owner
36/240 заменяет synthetic 35/221; optional harnesses counted only when executed,
без double count). Linux x64 **NOT RUN**: Windows `bash.exe` is a WSL stub
failing `/bin/bash`, but actual Git Bash `5.2.37(1)-release (x86_64-pc-msys)`
`bash -n scripts/build.sh` и `test.sh` exit 0 (синтаксис only); Linux PB 6.41
build/runtime genuinely не выполнялся.
Owner IWAD unchanged 12,408,292 bytes/MD5
`c4fe9fd920207691a9f493668e0a2083`. Owner commit/tag pending.

### M4 — Полный программный рендерер (`v0.4.0`)

**Основные модули:** `Planes.pbi`, `Sprites.pbi`, расширение `Draw.pbi` и `RenderMain.pbi`.

**Текущий статус:** M4-01 PARTIAL development slice accepted in the working tree;
full M4 remains open. Version stays `0.3.0`; do not start M4-02 in the M4-01 task.

Actual Windows verification: PL01-PL60 60 cases/211 assertions/0 failures;
PI01-PI03 3/76/0; owner PI04 1/150/0; full scripts no-IWAD **211/211** and
owner-IWAD **291/291** checks, both exit 0; real GUI E1M1/E1M2/E4M1 previews at
960x600, clean exit 0 and visually inspected.

- [ ] Visplanes, полы, потолки, flats и небо: M4-01 PARTIAL — online
  `R_FindPlane`/`R_CheckPlane`, pre-clip marks, real 64x64 `FlatLoad` floors/
  ceilings after walls, `F_SKY1` detected/normalized/deferred with counts. Real
  sky pixel texture and full outdoor rendering are not implemented.
- [ ] `COLORMAP` и оригинальные правила освещения/расстояния: PARTIAL — plane
  `zlight[16][128]`/`COLORMAP` remap implemented and independently checked;
  dynamic extralight/light animation remain deferred (M4-02+).
- [ ] masked midtextures, sprite clipping и порядок перекрытия objects: not
  implemented (M4-02+); masked midtexture back-to-front is explicitly out of scope.
- [ ] анимация текстур и flats: not implemented.
- [ ] Оружие как overlay (PSprite rendering): not implemented (M5+).
- [ ] Сверить кадры типовых rooms/doors/lifts/outdoor/sprites: PARTIAL synthetic
  PI01/PI02 full-frame oracle byte/hash comparisons and owner PI04 counters/
  coverage; new owner combined hashes `B6C3BD9880758292`, `D32BD22FF01A9BBB`,
  `0AFA2E970F9C08C8` are NOT LOCKED pending independent same-camera source
  comparison. Sky pixels/sprites/outdoor-match remain not verified.
- [ ] Режим записи контрольного кадра и диагностических counters: PARTIAL —
  `--show-planes <ExMy>` opt-in preview plus bounded plane span trace, counters,
  coverage and hashes; no full M4-02 diagnostic capture mode yet.
- [ ] Корректное масштабирование window/fullscreen: PARTIAL — 3x nearest-
  neighbour window wired for `--show-planes`; human plane/sky visual review RUN
  via real 960x600 preview captures of E1M1/E1M2/E4M1 (exit 0); fullscreen not
  implemented.

**Критерий готовности:** статический кадр E1M1 выглядит как Doom (стены, полы,
потолки, свет, спрайты); нет систематических артефактов прозрачности/сортировки.
M4-01 does not meet this full criterion: no sky pixel texture, sprites, masked
midtexture overlay, animation or independent C same-camera comparison yet.

### M5 — Игровой цикл, ввод, движение (`v0.5.0`)

**Основные модули:** `Timer.pbi`, `Input.pbi`, `Game.pbi`, `Player.pbi`, `Physics.pbi`, `Thinker.pbi`.

- [ ] Реализовать главный цикл: независимый системный frame timing и ровно 35 logic tics/с.
- [ ] Добавить клавиатуру, мышь, поворот, движение, бег и действие Use.
- [ ] Перенести `ticcmd_t`, управление игроком и обработку событий в согласованном порядке.
- [ ] Реализовать столкновения со стенами, slides, высоту пола, лестницы и блокировки проходов.
- [ ] Реализовать пространственные структуры `BLOCKMAP`, позиционирование в subsector, line-of-sight primitives.
- [ ] Реализовать открытие простых дверей, кнопок и базовую систему special thinkers.
- [ ] Проверить движение и коллизии на E1M1/E1M2; тесты фиксированных последовательностей input tics.
- [ ] Добавить паузу, выход из игры, ограничение числа steps при кратковременном зависании окна.

**Критерий готовности:** игрок свободно перемещается по E1M1, не проходит сквозь стены, взаимодействует с дверями и сохраняет стабильную скорость независимо от FPS.

### M6 — Игровые объекты, боёвка и прогресс (`v0.6.0`)

**Основные модули:** `Objects.pbi`, `Enemy.pbi`, `Weapons.pbi`, `Specials.pbi`, расширение `Thinker.pbi`.

- [ ] Перенести таблицы состояний, `mobjinfo`, спавн и обновление thinkers.
- [ ] Реализовать предметы, броню, здоровье, боеприпасы, ключи, pickup interactions.
- [ ] Реализовать все виды оружия Doom, стрельбу, попадания, projectiles и взрывы.
- [ ] Реализовать AI монстров: поиск, повороты, атаки, реакции на звук/урон, line-of-sight.
- [ ] Реализовать повреждения, смерть, telefrag, взаимодействия с объектами.
- [ ] Реализовать все необходимые linedef/sector specials для Ultimate Doom: doors, lifts, floors, ceilings, crushers, lighting, teleporters, exits.
- [ ] Добавить навыки сложности, параметры эпизода/уровня, секретные уровни и переходы.
- [ ] Прогнать сценарии E1M1 → E1M2 и эпизодные/секретные переходы.

**Критерий готовности:** E1M1 можно пройти от старта до выхода с реальными противниками и оружием; механики воспроизводимы и не зависят от способа вывода.

### M7 — Интерфейс, звук и музыка (`v0.7.0`)

**Основные модули:** `HUD.pbi`, `Menu.pbi`, `Automap.pbi`, `Intermission.pbi`, `Sound.pbi`, `Music.pbi`, `MUS.pbi`.

- [ ] Внедрить HUD/status bar, face states, индикацию здоровья, брони, патронов и ключей.
- [ ] Внедрить меню New Game, Options, Load/Save (само сохранение — M8), Quit, Help.
- [ ] Внедрить automap, overlay/полноэкранное отображение, карту, маркеры, масштаб.
- [ ] Реализовать intermission, счётчики kills/items/secrets, экран завершения эпизода.
- [ ] Разобрать формат звуковых lump и корректно воспроизводить звуковые эффекты.
- [ ] Разобрать MUS и определить архитектуру музыкального backend: преобразование в события/MIDI и/или собственный программный синтез; проверить законность и кроссплатформенность выбранного решения.
- [ ] Добавить уровни громкости, отключение музыки/звука и обработку отсутствующего аудиоустройства.
- [ ] Проверить синхронизацию звуков событий, отсутствие зависаний/утечек и воспроизведение нескольких эффектов.

**Критерий готовности:** игра имеет полноценный HUD, меню, автомапу, рабочие звуки и музыку на обеих целевых ОС. **Музыка — отдельный технический риск**: она не должна блокировать тесты симуляции, но обязательна для принятия 1.0.

### M8 — Сохранения, демо и пользовательские настройки (`v0.8.0`)

**Основные модули:** `SaveGame.pbi`, `Demo.pbi`, `Config.pbi`.

- [ ] Определить формат сохранений DoomPB (версионирование, контроль целостности, совместимость между версиями).
- [ ] Сохранять и восстанавливать игровое состояние: players, thinkers, sectors, line/special state, RNG/timing.
- [ ] Добавить quicksave/quickload, слоты, обработку испорченных файлов.
- [ ] Разобрать оригинальные demo lump и формат ввода; внедрить воспроизведение/запись там, где симуляция достаточно совместима.
- [ ] Сравнивать контрольные суммы состояния после выбранных game tics с эталоном.
- [ ] Реализовать конфигурацию клавиш, мыши, окна, звука, путей IWAD.
- [ ] Проверить смену версии бинарника без уничтожения сохранений и загрузку после рестарта.

**Критерий готовности:** пользователь может сохраняться, выходить и продолжать игру, а воспроизводимые сценарии дают одинаковые состояния. Совместимость оригинальных демо — желательная дополнительная проверка с явным отчётом о расхождениях.

### M9 — Совместимость, тестирование и Linux (`v0.9.0`)

- [ ] Сборка/запуск проекта на Windows x64 и Linux x64 с PureBasic 6.41.
- [ ] Исправление различий файловых путей, регистра имён, звука, клавиатуры и экранного backend.
- [ ] Прогон всех 36 карт Ultimate Doom, включая E4 и секретные выходы.
- [ ] Прогон скрипта smoke-test уровней: загрузка, первые кадры, предметы, AI, переходы.
- [ ] Проверка IWAD + нескольких PWAD-оверлеев (поддерживаемый vanilla Doom subset).
- [ ] Сравнение пиксельных хешей статичных кадров и снимков состояния симуляции с эталоном, с задокументированными допустимыми расхождениями.
- [ ] Проверки повреждённых WAD, нехватки памяти, многократного открытия/закрытия уровней, альт-таба/изменения размера окна.
- [ ] Замер CPU/RAM/FPS без искусственного требования «N FPS на любом железе»; установить базовый целевой профиль после измерений.
- [ ] Проверка лицензий, отсутствия коммерческих ресурсов и приватных ключей в истории Git.
- [ ] Подготовить руководство установки/сборки/указания пути к легальному IWAD.

**Критерий готовности:** игра проходима на Windows и Linux, известные регрессии задокументированы и нет блокирующих ошибок в критических путях.

### M10 — Публичный выпуск (`v1.0.0`)

- [ ] Закрыть обязательные пункты M0–M9 или зафиксировать осознанные исключения до релиза.
- [ ] Обновить README, скриншоты (только если права на публикацию соблюдены), `CHANGELOG.md`, `COMPATIBILITY.md`.
- [ ] Проверить SPDX headers, `LICENSE`, upstream attribution.
- [ ] Собрать релизные бинарники Windows/Linux **без IWAD**.
- [ ] Добавить контрольные суммы релизных архивов и инструкции запуска.
- [ ] Создать тег `v1.0.0` и GitHub Release после ручной проверки.

**Критерий готовности:** новый пользователь с лицензированным Ultimate Doom может скачать бинарник, указать собственный `DOOM.WAD`, запустить игру и пройти кампанию.

### После 1.0 (backlog, не блокирует релиз)

- [ ] Doom II / Final Doom и дополнительные версии IWAD.
- [ ] Сетевой multiplayer, совместимый режим для исходной модели тиков.
- [ ] High-resolution, widescreen, interpolation для 60/120 FPS *только в renderer*.
- [ ] Gamepad, расширенная клавиатурная раскладка, accessibility.
- [ ] Более гибкий PWAD support и модификации с документированными пределами vanilla.
- [ ] Дополнительные архитектуры и платформы.

## 6. Тестовая стратегия

### 6.1. Уровни проверки

| Уровень | Проверки | Условие запуска |
|---|---|---|
| Syntax | `pbcompiler --check` | После каждой правки кода |
| Unit | Endian, fixed math, patch decoding, WAD parser, lookup | При каждом изменении модуля |
| Integration | Реальный WAD, карты E1M1/E1M2/E4M1, загрузка/декодирование | Локально у разработчика |
| Golden | Одни и те же входы → checksum, pixel hashes, selected state snapshots | После завершения подсистемы |
| Regression | Старые баги, memory leaks, malformed WAD, transitions | Перед каждым milestone |
| Cross-platform | Собрать и запустить Windows + Linux | До принятия M9/M10 |

### 6.2. Что тестировать с первого дня

- Маленькие **собственные** тестовые WAD, создаваемые тестовым кодом: не включать в репозиторий части коммерческого IWAD.
- Пустой WAD, неверная сигнатура, truncation, каталог за концом файла, отрицательные/переполняющиеся размеры, нулевой lump, повторяющееся имя.
- Patch с прозрачными промежутками, несколькими posts, неверными смещениями и отсутствующим terminator.
- `FixedMul`, `FixedDiv`, trig/angle tables: сравнение с эталонными результатами C-версии на наборе крайних значений.
- Загрузка карт: нулевые и слишком большие индексы, сектора без соседей, некорректные BSP nodes.
- Детерминированная симуляция: seed + последовательность `ticcmd` → повторяемые checksum состояния.
- Возможность вывести диагностические логи и checksum **без** копирования игровых ресурсов.

### 6.3. Критерии для pull request / merge

1. Объяснена исходная C-функция/структура и семантика переноса.
2. `--check` проходит для соответствующей целевой платформы.
3. Сборка проходит; проведён локальный smoke-test изменённой подсистемы.
4. Новые или изменённые edge cases покрыты тестами.
5. Не добавлены коммерческие WAD, временные данные, бинарные артефакты.
6. Изменения ограничены областью задачи; review diff выполнен человеком.
7. Обновлены `PORTING_NOTES.md` и/или `COMPATIBILITY.md` при значимом изменении поведения.

> **CI-нюанс:** не считать, что лицензированный PureBasic можно свободно распространять как часть публичного runner image. Для автоматической сборки допустим контролируемый runner с законно установленным компилятором; пока он не настроен, локальная сборка обязательна, а GitHub Actions может проверять текстовые/ресурсные ограничения.

## 7. Работа с AI-агентом

### 7.1. Роли инструментов

- **OpenCode Desktop** — основной агент для изучения референса, узких изменений, запуска компилятора, тестов и git diff.
- **DeepSeek V4.1 Flash 1017** — основная модель через настроенный OpenRouter API; не полагаться на заявленный огромный контекст вместо точного подбора файлов.
- **VS Code + Kilo Code** — независимый review, ручная отладка и редактор; избегать одновременного редактирования одного дерева двумя агентами.
- **Hermes Desktop / Zoo Code** — запасные варианты для исследований или альтернативного решения отдельной проблемы, без переключений в середине незавершённого изменения.

### 7.2. Политика задач для агента

- Одна задача = один ограниченный набор модулей + один наблюдаемый критерий принятия.
- **Plan → Implement → Compile → Test → Diff → Commit**; переход к следующей задаче только после проверки предыдущей.
- Перед изменением кода агент перечисляет задействованные C-функции, типы и взаимосвязи.
- Нельзя предлагать «примерную альтернативу» оригинальному алгоритму без явного согласования и записи в `PORTING_NOTES.md`.
- Нельзя изобретать PureBasic API; при сомнениях использовать официальную документацию и маленький компилируемый repro.
- Не разрешать агенту удалять/перезаписывать чужие файлы, пушить/форс-пушить, менять лицензии или публиковать бинарники без согласования.
- Коммиты делать после успешной компиляции; желательно по одному смысловому изменению, с указанием исходного C-модуля в commit message.
- Если агент зашёл в тупик: уменьшить контекст, выделить минимальный воспроизводимый пример, сверить с оригинальным C и документацией, затем исправлять.

### 7.3. Шаблон задания для OpenCode

```text
Проект: DoomPB (PureBasic 6.41, GPL-2.0-only).
Задача: [одна конкретная функция или небольшой модуль].
Референс: ../doom-original/linuxdoom-1.10/[файл].
Изучить: [нужные функции и структуры].
Реализовать: [список входов/выходов, ограничения].
Критерий готовности: [измеримый тест].
Ограничения: не добавлять C/SDL wrapper; не менять другие модули;
не включать WAD в Git; сохранить семантику оригинала.
Проверка: запустить pbcompiler --check, затем сборку и тесты.
Отчёт: какие файлы изменены, какие тесты прошли,
какие отличия от оригинального Doom остались.
```

### 7.4. Первые 6 задач для агента

1. `M0-01`: каркас репозитория, `.gitignore`, `LICENSE`, минимальный `DoomPB.pb`, проверка компилятора.
2. `M0-02`: PowerShell/Bash build/test scripts, конфигурация пути к компилятору.
3. `M1-01`: endian-safe чтение WAD header/directory, тесты на повреждённые входы.
4. `M1-02`: поиск lumps и загрузка bytes, тест дубликатов и zero-length markers.
5. `M1-03`: декодер Doom patch + `PLAYPAL`, собственные fixtures.
6. `M1-04`: показ `TITLEPIC` в окне, smoke test с Ultimate Doom, релиз `v0.1.0`.

## 8. Команды сборки и диагностические соглашения

Компилятор располагается в подкаталоге `Compilers` установленного PureBasic. Примеры ниже предполагают добавление его в `PATH` или вызов через переменную окружения `PB_COMPILER`. Они **не** являются проверенным готовым скриптом конкретного компьютера — эту задачу выполняет M0-02.

### Windows / PowerShell

```powershell
$env:PB_COMPILER = 'C:\Program Files\PureBasic\Compilers\pbcompiler.exe' # заменить при необходимости
& $env:PB_COMPILER --version
& $env:PB_COMPILER src\DoomPB.pb --check
New-Item -ItemType Directory -Force build | Out-Null
& $env:PB_COMPILER src\DoomPB.pb --output build\DoomPB.exe
```

### Linux / Bash

```bash
export PB_COMPILER="${PB_COMPILER:-pbcompiler}"
"$PB_COMPILER" --version
"$PB_COMPILER" src/DoomPB.pb --check
mkdir -p build
"$PB_COMPILER" src/DoomPB.pb --output build/DoomPB
```

**Необходимые соглашения CLI для самой игры:**

```text
DoomPB --help
DoomPB --version
DoomPB --iwad /path/to/DOOM.WAD
DoomPB --iwad /path/to/DOOM.WAD --file mod.wad
DoomPB --iwad /path/to/DOOM.WAD --list-lumps
DoomPB --iwad /path/to/DOOM.WAD --dump-info
```

Это **планируемые**, а не уже реализованные параметры; они должны быть единообразными в CLI и GUI. Для автоматических тестов добавить `--headless` и команды диагностики отдельным изменением.

## 9. Git, лицензия и защита ресурсов

### 9.1. Минимальный `.gitignore`

```gitignore
# Commercial and user-provided game data
*.wad
*.WAD
*.iwad
*.IWAD
*.pk3
local-data/
data/

# Binary outputs, caches and logs
build/
dist/
*.exe
*.dll
*.so
*.log
*.tmp
*.bak
*.pbf

# Personal IDE/OS files
.vscode/
.idea/
.DS_Store
Thumbs.db
```

Если решим хранить **собственные** маленькие тестовые `.wad`, придётся точно разрешить только их: `!tests/fixtures/*.wad`; прежде проверить, что они сгенерированы нами и не содержат коммерческие данные. Для IDE-конфигурации отдельные исключения можно позднее ослабить.

### 9.2. Работа с лицензией

- В корне должен находиться полный текст **GNU GPL version 2**; SPDX идентификатор `GPL-2.0-only`.
- Сохранять/атрибутировать исходные уведомления id Software при переносе соответствующего кода.
- README должен прямо указывать: DoomPB — неофициальный порт, ресурсы Doom не включены, требуется собственный легально полученный IWAD или совместимый свободный набор данных.
- Не публиковать `DOOM.WAD`, извлечённые оригинальные графику/звуки, бинарные дампы lumps и автоматически созданные из них assets. Даже golden-тесты должны хранить только не восстанавливающие ресурсы контрольные суммы/статистики.
- При использовании кода из других проектов проверять совместимость лицензий и атрибуцию отдельно (особенно для сторонних модулей аудио).

### 9.3. Предлагаемые Git-ветки и релизы

- `main` — собираемое, проверенное состояние.
- `feat/m1-wad-directory`, `feat/m1-patch-decoder`, `feat/m3-bsp` — короткие рабочие ветки.
- Conventional-style commits (по желанию): `feat(wad): ...`, `test(patch): ...`, `fix(renderer): ...`, `docs: ...`.
- Теги milestone: `v0.1.0` … `v1.0.0`; релиз возможен только при выполнении DoD.

## 10. Риски и решения

| Риск | Влияние | Как снижаем |
|---|---|---|
| Скрытые C-зависимости и глобальное состояние | Высокое | Список зависимостей до переноса, небольшие блоки, таблица соответствия |
| Переполнения/знаки/bit shifts в fixed math | Высокое | `.l`/`.q`, эталонные тесты и строгий порядок операций |
| Выравнивание структур и 64-bit pointers | Высокое | Декодирование файлов по байтам, не `memcpy` в native structs |
| Неполный или ошибочный Doom patch decoder | Среднее | Синтетические fixtures, отдельные посты/прозрачность |
| Артефакты BSP, visplanes и masked textures | Высокое | Кадровые эталоны и поэтапное подключение рендеринга |
| Десинхронизация игровой логики и DEMO | Высокое | 35 tics, таблицы RNG, state hashes и deterministic input replay |
| Звук и особенно MUS/music backend на двух ОС | Высокое | Исследовать формат и backend рано, не откладывать до релиза |
| Медленный вывод кадров на Linux | Среднее | Профилировать разные PB presentation paths при M1/M3 |
| Галлюцинации AI в малоизвестном языке | Высокое | Компиляция каждого шага, примеры документации, узкие задачи |
| Случайная публикация IWAD | Высокое | `.gitignore`, проверка `git status`, pre-commit scan, ревью бинарников |
| Отсутствие лицензированного PB в публичном CI | Среднее | Локальный build gate / законный частный runner |
| Scope creep (high-res, новый renderer, Doom II) | Высокое | `1.0 = Ultimate Doom classic`; backlog после релиза |

## 11. Метрики прогресса

Для каждого milestone в `CHANGELOG.md` или GitHub Projects фиксировать:

- **Functional:** какие сценарии уже выполняются от начала до конца, а не сколько файлов перенесено.
- **Compatibility:** какие тесты/кадры/уровни совпадают с оригиналом; какие расхождения сознательно оставлены.
- **Reliability:** процент повторно проходящих тестов, число крашей на invalid WAD.
- **Performance:** CPU ms/frame, memory high-water mark, средняя скорость на целевой платформе; измерять на одинаковых сценариях.
- **Maintainability:** размер PR, покрытые edge cases, задокументированные расхождения.

Выполнение этапа оценивается по условиям **Definition of Done** и тестам, не по проценту «переведённых строк C». Приоритет — постоянно собирать и запускать проект.

## 12. Рекомендуемый порядок ближайших действий

1. Создать GitHub-репозиторий с GPL-2.0 и локально клонировать его.
2. Добавить этот файл как **`docs/DEVELOPMENT_PLAN.md`** и создать корневой `AGENTS.md`.
3. Подготовить соседний `doom-original` и зафиксировать исходную ревизию.
4. Установить/проверить PowerShell и Bash build scripts под PureBasic 6.41.
5. Выполнить `M1-01` и `M1-02`: WAD directory + lump lookup с тестами.
6. Выполнить `M1-03`: `PLAYPAL` + decoder Doom patch.
7. Выполнить `M1-04`: показать `TITLEPIC` из легального Ultimate Doom.
8. Сохранить скриншот **только локально**, проверить правильность палитры, зафиксировать тег `v0.1.0`.
9. Только затем переходить к `M2` (map/resource pipeline).

---

## 13. Источники и технические ссылки

- [Оригинальный исходный код Doom — id Software](https://github.com/id-Software/DOOM) — основной источник кода и GPL-2.0.
- [Linux Doom 1.10](https://github.com/id-Software/DOOM/tree/master/linuxdoom-1.10) — исходники для последовательного переноса.
- [Chocolate Doom](https://github.com/chocolate-doom/chocolate-doom) — исторически близкая реализация и практические решения портирования.
- [PureBasic: использование командного компилятора](https://www.purebasic.com/documentation/reference/cli_compiler.html) — `--check`, `--output`, debugger, optimizer.
- [PureBasic: ScreenOutput](https://www.purebasic.com/documentation/screen/screenoutput.html) — замечание о производительности рисования на Linux.
- [Doom Wiki: DOOM.WAD](https://doom.fandom.com/wiki/DOOM.WAD) — параметры Ultimate Doom IWAD 1.9ud.
- [Doom picture format](https://doom.fandom.com/wiki/Picture_format) — patch columns/posts.
- [Doom WAD format overview](https://reverseengineering.wiki/index.php/Format%3AWAD_%28Doom_engine%29) — заголовки, lump directory, palettes и patches.

> Документ описывает целевую архитектуру и порядок разработки. Он не означает, что перечисленные модули или тесты уже существуют. Изменять план по результатам первых прототипов допустимо, но обязательные требования совместимости и лицензирования должны сохраняться.

# Spun → macOS Migration: Resume Prompt

## Контекст

Мы мигрируем проект **Spun** (Qt6/QML музыкальный плеер, автор yappologistic) с Linux на macOS. За 4 build-сессии приложение **запускается и работает** на macOS 14+ arm64 — UI грузится, окно создаётся, процесс живёт стабильно. Цель сессии — завершить публикацию (README, Homebrew formula, CI).

## Что сделано (коммиты на ветке `feature/macos-port`)

```
73bee37  MIGRATION_NOTES: capture Day 4 verification log
d01fa6d  macOS: lazy-load FileDialogs to dodge Qt 6.11 QFileDialogOptions quirk
352198d  Add MIGRATION_NOTES.md handoff for future agents
b7ea2ea  macOS: package Qt frameworks into Spun.app for standalone launch
bc992a2  macOS: produce a real .app bundle with Info.plist and icon
0f69401  macOS: add build script and patch linker flags
```

## Ключевые файлы

- `MIGRATION_NOTES.md` — **ГЛАВНЫЙ ДОКУМЕНТ**. Прочитай его **первым делом** в новой сессии. Содержит:
  - Полное описание всех 4 дней работы
  - Что работает, что нет
  - Все open questions и решения пользователя
  - Команды для воспроизведения сборки
  - Verification log визуального теста
- `scripts/build-macos.sh` — обёртка над cmake для Homebrew Qt
- `scripts/sign-macos-bundle.sh` — pipeline: macdeployqt + rpath/code-sign fixup
- `resources/Info.plist.in`, `resources/spun-icon.icns`, `resources/spun.entitlements`
- `CMakeLists.txt` — патчи: `dead_strip`, `strip -x`, `MACOSX_BUNDLE`, post-build шаги
- `qml/Main.qml`, `qml/Tx6Controls.qml` — FileDialog/FolderDialog обёрнуты в `Loader { active: false }` (Qt 6.11 QFileDialogOptions quirk)
- `.gitignore` — разрешает `MIGRATION_NOTES.md` и `resources/`

## Что работает СЕЙЧАС

```bash
cd ~/Documents/_PERSONAL/repos/Spun
./scripts/build-macos.sh -DBUILD_TESTING=OFF   # ~3 мин
xattr -dr com.apple.quarantine build/Spun.app  # обход Gatekeeper
open build/Spun.app                              # запуск через LaunchServices
```

Подтверждено: PID живёт 25 threads, 187 MB RSS, появляется в System Events как "Spun", AppleScript находит bundle ID `com.yappologistic.spun`. Bundle ~230 MB, всё Qt внутри.

## Что осталось (День 5)

Приоритеты по MIGRATION_NOTES.md (раздел 5):

1. **README.md** — добавить секцию "Install on macOS":
   - Команда `brew install --cask spun` (или ссылка на tarball)
   - Секция "Build on macOS" с предупреждением про duplicate class warnings на dev-машинах с Homebrew Qt
2. **Homebrew formula** (`Formula/spun.rb` или cask):
   - Cask formula для `homebrew-cask`
   - Качает tar.gz с GitHub Releases
   - Устанавливает `Spun.app` в `/Applications`
3. **CI** (`.github/workflows/`):
   - macOS runner
   - Устанавливает Qt через `jurplel/install-qt-action`
   - Запускает `./scripts/build-macos.sh -DBUILD_TESTING=ON`
   - Запускает `ctest` (исключая `spun-desktop-media` который требует D-Bus)
4. **`--self-test` регресс**:
   - `src/main.cpp:1544` делает `findChild<QObject *>("musicDialog")`
   - FileDialog теперь в Loader с `active: false`
   - Нужно либо подняться вверх по Loader, либо вызвать `openMusicDialog()` в тесте

## Решения пользователя (НЕ менять без подтверждения)

- Минимальная адаптация `#ifdef Q_OS_MACOS`, не рефакторить абстракции
- Только Cider (без нативного MusicKit)
- Homebrew formula (без подписи Developer ID, без нотаризации)
- macOS 14+ minimum
- Apple Silicon arm64 (Universal binary не нужен)

## Известные ограничения (НЕ чинить без запроса)

- `open build/Spun.app` работает ТОЛЬКО после `xattr -dr com.apple.quarantine` (на dev-машине) или на чистой user-машине без Homebrew Qt
- 5 objc warnings "Class X is implemented in both" появляются на dev-машинах с Homebrew Qt — безвредны, но шумные
- LaunchServices через `open` отклоняет bundle без Developer ID (Gatekeeper); прямое выполнение `Contents/MacOS/Spun` всегда работает
- macdeployqt's `-qmldir` падает с `qmlimportscanner output error` на Qt 6.11 — поэтому скрипт копирует .qmldir вручную (см. MIGRATION_NOTES.md раздел 3.2)

## Первые шаги в новой сессии

1. Прочитать `MIGRATION_NOTES.md` полностью
2. Проверить `git status` и `git log` на ветке `feature/macos-port`
3. Убедиться что сборка всё ещё работает: `./scripts/build-macos.sh -DBUILD_TESTING=OFF`
4. Спросить пользователя с чего начать День 5 (README, формула, CI, или self-test fix)

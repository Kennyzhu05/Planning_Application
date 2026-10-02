# Planning_Application
A modern, high-performance C++20 and Qt Quick (QML) daily planning desktop and mobile application built on a **Visual Focus Budgeting** paradigm. Designed for seamless productivity, dark-mode ergonomics, and real-time SQLite persistence.

---

## Key Features & UX Highlights

* **Visual Time Budgeting:** Treats focus time as a finite budget rather than an infinite checklist. Features a dynamic capacity bar that smoothly transitions from **Indigo (`#6366F1`)** to **Amber (`#F59E0B`)** when scheduled tasks exceed daily target hours.
* **One-Tap Task Creation:** Ergonomic duration preset chips (`15m`, `30m`, `45m`, `1h`, `2h`) and category tags for rapid, frictionless input.
* **Active Focus Mode:** Integrated Pomodoro-style countdown timer with custom-rendered canvas progress ring.
* **SQLite Persistence:** Native C++ model (`TaskManager` deriving from `QAbstractListModel`) providing fast SQLite data storage and instant state synchronization.

---

## Technical Stack

* **Framework:** Qt 6.5+ (Qt Quick, QML, QuickControls2, C++20)
* **Build System:** CMake 3.16+
* **Database:** SQLite (`QSqlDatabase`)
* **Architecture:** C++ backend data model exposed directly to reactive QML frontend context views.

---

## Quick Start

### Prerequisites
* Qt 6.5+ with Quick, QuickControls2, and Sql components installed.
* CMake 3.16 or higher.
* C++17 or C++20 compatible compiler (MSVC 2019+, GCC 11+, or Clang 12+).

### Building & Running

```bash
# Configure with CMake
cmake -B build -S .

# Build executable
cmake --build build

# Run application
./build/appDailyPlanner
```'

### Daily Git Commands

```bash
# 1. Pull latest updates from remote main branch using rebase
git pull 

# 2. Stage modified and new files
git add .

# 3. Commit changes following conventional commits standard
git commit -m "[Name of your commit]"

# 4. Push local changes to GitHub
git push
```

## AI task breakdown (private desktop prototype)

Open a dashboard task to view its details and nested subtasks. Click **Break down the task**, edit the suggested titles and durations, then **Save subtasks**. Completing all subtasks completes their parent. The focus budget uses the subtask total instead of double-counting the parent estimate.

The service uses Groq's `openai/gpt-oss-20b` model and strict JSON-schema output. Set `GROQ_API_KEY` in Qt Creator under **Projects > Run Settings > Environment** for the application's desktop run configuration, then restart the app. Enter the key privately; never put it in QML, source code, or Git. The key is read only by the C++ network service.

Each request sends the selected task's title, description, category, and original estimate. There is one request at a time, a 45-second timeout, and cancellation when the card closes. Suggestions are saved only after review. Regenerating requires confirmation before replacing saved subtasks and completion progress.

The existing `planner.db` working-directory location is retained. An additive `subtasks` table preserves existing tasks and settings. Keep the same run working directory to continue using your existing planner database.

This direct provider connection is for private desktop development. Before distributing the mobile application, put the provider key on an authenticated backend. Timeline scheduling and recursive subtasks are outside this version.

### Optional tests

Configure CMake with `-DDAILYPLANNER_BUILD_TESTS=ON`, build, then run `ctest --test-dir build --output-on-failure`. Qt Test must be installed for the selected kit. Tests use isolated databases and a loopback HTTP server. The live Groq smoke test skips when no `GROQ_API_KEY` is configured; with a key it sends three sample tasks and consumes API quota. Ensure the Qt and MinGW runtime DLL directories are on PATH.

See [Groq setup](https://console.groq.com/docs/quickstart) and [structured outputs](https://console.groq.com/docs/structured-outputs).

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
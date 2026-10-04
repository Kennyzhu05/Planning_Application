# Planning_Application
A modern, high-performance C++20 and Qt Quick (QML) daily planning desktop and mobile application built on a **Visual Focus Budgeting** paradigm. Designed for seamless productivity, dark-mode ergonomics, and real-time SQLite persistence.

---

## Key Features & UX Highlights

* **Visual Time Budgeting:** Treats focus time as a finite budget rather than an infinite checklist. Features a dynamic capacity bar that smoothly transitions from **Indigo (`#6366F1`)** to **Amber (`#F59E0B`)** when scheduled tasks exceed daily target hours.
* **One-Tap Task Creation:** Ergonomic duration preset chips (`15m`, `30m`, `45m`, `1h`, `2h`) and category tags for rapid, frictionless input.
* **Active Focus Mode:** Timed or open-ended Android focus monitoring, with screen-use reminders at one and five minutes and a matching in-app warning. Desktop retains simulated screen monitoring.
* **SQLite Persistence:** Native C++ model (`TaskManager` deriving from `QAbstractListModel`) providing fast SQLite data storage and instant state synchronization.
* **Calendar month/year picker:** Click the month heading to choose a month and year (1900–9999), then select a day to view its tasks and goal deadlines. Browsing months does not change the selected day until a day is clicked.
* **Editable breakdowns:** Task and goal AI previews support titles, guidance, durations, adding/removing steps, and moving steps up/down. Task cards also offer **Edit subtasks** and **Create subtasks manually**, with Save/Cancel and discard confirmation. Ordinary edits preserve retained subtask IDs and completion; new steps start incomplete. AI regeneration remains an explicit replacement that resets progress after confirmation. Keep 1–12 steps with 1–120 minutes each. All accepted edits are transactional and refresh the parent, focus budget, and progress displays.
* **Auto task configure placeholder:** A dashboard button between Focus Budget and the task list opens a **Coming soon** message. It does not schedule tasks or make an AI request.
* **Consistent forms:** Task creation/editing and goal creation/editing share `qml/components/FormDrawer.qml`, with a fixed header/footer and scrolling fields. `CategorySelector.qml` displays all category choices as readable chips. The floating add button overlays the lists, with trailing scroll space instead of a reserved full-width row. Goal deadline selection displays **Select a deadline** until a date is chosen; **No deadline** is the separate clear action.

The calendar/editor interface update requires reconfiguring CMake and rebuilding the Qt app because new QML components are registered in the module. No Cloudflare redeployment is required. No build, automated tests, or live AI requests were run for this interface update; runtime and visual checks are left to the user.

---

## Project folders

```text
DailyPlanner/
  CMakeLists.txt          Build entry point (open this in Qt Creator)
  README.md              Project setup and feature notes
  cmake/                 Public configuration header template
  src/
    main.cpp             Application entry point
    models/              Tasks, goals, SQLite storage, breakdown validation
    services/            AI backend client and account authentication
    focus/               Focus timer engine and controller
  qml/
    Main.qml             Application shell and dashboard
    pages/               Calendar, goals, and legacy focus screen
    dialogs/             Task/goal editors, sign-in, and focus setup
    components/          Reusable controls, calendar, cards, and step editor
    utils/               Shared date helpers
  backend/               Cloudflare Worker source, settings, and deployment guide
  android/               Native focus service, private IPC, manifest, and notifications
  tests/                 Existing C++ test sources
  importedcontent/       Reserved for imported design files
  build/                 Generated build files (ignored by Git)
```

After the folder reorganization, open the root `CMakeLists.txt` and run CMake
again in your existing build configuration before rebuilding. Keep your current
run environment and working directory so the same local `planner.db` is used.
QML resource aliases preserve the existing module entry point and relative
JavaScript imports; source files remain grouped in the folders above. Both
application and optional test targets use the updated source/include paths.
The Groq/Cloudflare backend configuration is unchanged and needs no redeployment.
No builds or tests were run for this source-file reorganization.

## Technical Stack

* **Framework:** Qt 6.5+ (Qt Quick, QML, QuickControls2, C++20)
* **Build System:** CMake 3.16+
* **Database:** SQLite (`QSqlDatabase`)
* **Architecture:** C++ backend data model exposed directly to reactive QML frontend context views.

---

## Quick Start

### Prerequisites
* Qt 6.5+ with Quick, QuickControls2, Sql, and Network components installed.
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

## AI breakdown and account sign-in

Open a task to view its details and nested subtasks. Click **Break down the task**, edit the suggested titles and durations, then **Save subtasks**. Completing all subtasks completes their parent. The focus budget counts today's scheduled tasks and uses the subtask total instead of double-counting the parent estimate. AI estimates may exceed your original estimate; the preview flags the difference before saving.

Open **Menu > Sign in / Create account** to use AI breakdown. The Qt app signs in with Supabase Auth, including email-code verification and password recovery. On Windows, refresh credentials are stored in Credential Manager; passwords are never saved. Other platforms currently keep sessions in memory until the app closes. Local planning works while signed out.

The TypeScript backend in `backend/` runs on Cloudflare Workers and uses Groq's `openai/gpt-oss-20b` model with strict JSON-schema output. `GROQ_API_KEY` now belongs exclusively in a Cloudflare Worker secret. Remove the old key from the Qt run environment: there is no direct-provider fallback. Only the selected context is transmitted for a breakdown; planner data stays in local SQLite.

Configure `DAILYPLANNER_API_URL`, `DAILYPLANNER_SUPABASE_URL` and `DAILYPLANNER_SUPABASE_PUBLISHABLE_KEY` in Qt Creator's run environment, or embed those public values in CMake settings for a shared build. The full guide covers custom SMTP, email templates, JWT signing keys, account access, quotas, local development and deployment: **[backend setup guide](backend/README.md)**. Supabase and Cloudflare setup/deployment have not been performed.

Each request sends the selected task's title, description, category, and original estimate. There is one request at a time, a 45-second timeout, and cancellation when the card closes. Suggestions are saved only after review. Regenerating requires confirmation before replacing saved subtasks and completion progress.

The existing `planner.db` working-directory location is retained. Schema upgrades preserve existing tasks, subtasks, and settings in a transaction. When planned dates are first introduced, existing tasks receive the upgrade day's local date. Unscheduled goal tasks remain unscheduled on later launches. Keep the same run working directory to continue using your existing planner database.

The backend authenticates requests, validates input/output, enforces per-account limits and shared daily/monthly request caps, and returns readable errors. The trial uses an explicit account allowlist. Sign-in controls AI access; changing accounts does not create a separate local planner or synchronize data. Timed events, recurring tasks, automatic scheduling, and recursive subtasks are outside this version.

## Android focus sessions

Focus supports timed and open-ended sessions on Android. During an active session,
an awake screen for one continuous minute triggers a gentle notification; five
minutes triggers a stronger warning that repeats every further five minutes.
Reminders work in other apps, with a matching banner inside DailyPlanner. Screen-off
clears warnings and resets the screen-use streak while overall focus time continues.
The native foreground service owns session state; desktop keeps its simulation.

Reconfigure CMake, rebuild the Android APK, and allow notifications on the phone.
No Cloudflare deployment is needed. See [Android focus setup and implementation](android/README.md)
for permissions, background/battery settings, changed files, platform limitations,
and manual checks. No build or phone tests were run for this change.

## Calendar and long-term goals

**Calendar** displays a month above the selected day's tasks and goal deadlines. Browse months, use **Today**, or select a date. Dots mark dates with saved work or deadlines. **+ Task** opens task creation with the selected date. Dashboard shows today's tasks; completing or editing a task updates its shared record in all views. Use **Edit** in a task card to change its title, description, estimate, category, or planned date. Nested subtasks follow their parent's date.

Use the round **+** button on **Long-term goal** to create a goal. Add its title, description, success criteria, and optional target date. **More details** includes category, starting point, and weekly availability; zero hours means unspecified. Goal deadlines appear on Calendar but do not consume the daily Focus Budget.

Open a goal and choose **Break down this goal**. AI suggests 1–8 ordered milestone titles and 1–12 actionable tasks for the first milestone, each estimated at 1–120 minutes. Review the milestone titles and task titles, guidance, and durations; remove tasks or assign dates before saving. Undated tasks stay in the goal backlog. Scheduled goal tasks appear on Calendar and on Dashboard when scheduled for today. Open a saved goal task to edit its date or use the regular AI subtask breakdown.

**Regenerate goal breakdown** creates a replacement preview. Saving requires confirmation because it replaces that goal's linked tasks, dates, nested subtasks, and completion progress. An unsuccessful save preserves the existing plan. Closing an unsaved preview asks before discarding it; closing during generation cancels the request. Task and goal request identities are distinct, even when their database IDs match.

Goal progress reports completed planned tasks. **Mark goal achieved** is a manual decision based on its success criteria, so finishing the first milestone does not automatically complete the whole goal. Later milestones are stored as a roadmap; expanding later milestones is a future feature.

### Optional tests

No tests or builds were run for this backend/sign-in change, as requested. The existing optional suite (`DAILYPLANNER_BUILD_TESTS`, off by default) includes direct-Groq API fixtures from the earlier prototype. Those API/UI fixtures need migration to the authenticated backend contract before they can validate the new flow. Do not use the old live-Groq test as backend verification. Manual verification and setup steps are in `backend/README.md`.

See [Groq setup](https://console.groq.com/docs/quickstart) and [structured outputs](https://console.groq.com/docs/structured-outputs).

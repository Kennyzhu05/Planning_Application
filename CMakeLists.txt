cmake_minimum_required(VERSION 3.16)

project(DailyPlanner VERSION 0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Find required Qt packages.
# Public defaults can be embedded when distributing a build to friends.
# The Groq key and all Supabase admin keys belong exclusively on the server.
set(DAILYPLANNER_API_URL "" CACHE STRING "HTTPS backend /v1/breakdown endpoint")
set(DAILYPLANNER_SUPABASE_URL "" CACHE STRING "Public Supabase project URL")
set(DAILYPLANNER_SUPABASE_PUBLISHABLE_KEY "" CACHE STRING "Public sb_publishable_ key")
if(DAILYPLANNER_SUPABASE_PUBLISHABLE_KEY AND NOT DAILYPLANNER_SUPABASE_PUBLISHABLE_KEY MATCHES "^sb_publishable_[A-Za-z0-9_-]+$")
    message(FATAL_ERROR "Use a public sb_publishable_ key. Groq and Supabase admin keys must never be compiled into the app.")
endif()
configure_file(dailyplannerconfig.h.in dailyplannerconfig.h @ONLY)

# 1. Find required Qt6 packages
find_package(Qt6 REQUIRED COMPONENTS Quick QuickControls2 Sql Network)

qt_standard_project_setup(REQUIRES 6.5)

# Application sources.
qt_add_executable(appDailyPlanner
    main.cpp
    taskmanager.h taskmanager.cpp
    goaloperations.cpp
    aiservice.h aiservice.cpp
    authservice.h authservice.cpp
    task.h breakdownvalidation.h
    focusengine.h focusengine.cpp
    focuscontroller.h focuscontroller.cpp
)

# Application QML files.
qt_add_qml_module(appDailyPlanner
    URI DailyPlanner
    VERSION 1.0
    QML_FILES
        Main.qml
        FocusSetupDialog.qml
        TaskModal.qml
        TargetSetupModal.qml
        TaskDetailsModal.qml
        BottomNavigation.qml
        NavigationIcon.qml
        DateUtils.js
        AppButton.qml
        CalendarWidget.qml
        DateField.qml
        TaskListCard.qml
        CalendarPage.qml
        GoalListCard.qml
        GoalsPage.qml
        PlannerField.qml
        PlannerArea.qml
        GoalForm.qml
        TaskEditModal.qml
        GoalDetailsModal.qml
        AuthModal.qml
)

target_link_libraries(appDailyPlanner
    PRIVATE
        Qt6::Quick
        Qt6::QuickControls2
        Qt6::Sql
        Qt6::Network
)
target_include_directories(appDailyPlanner PRIVATE ${CMAKE_CURRENT_BINARY_DIR})
if(WIN32)
    target_link_libraries(appDailyPlanner PRIVATE advapi32)
endif()

set_target_properties(appDailyPlanner PROPERTIES
    MACOSX_BUNDLE_GUI_IDENTIFIER my.dailyplanner.app
    MACOSX_BUNDLE TRUE
    WIN32_EXECUTABLE TRUE
)

# Focus engine rule tests.
include(CTest)

if(BUILD_TESTING AND NOT ANDROID)
    add_executable(focusengine_tests
        tests/focusengine_test.cpp
        focusengine.h
        focusengine.cpp
    )

    target_include_directories(focusengine_tests PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}"
    )

    set_target_properties(focusengine_tests PROPERTIES
        AUTOMOC OFF
        AUTOUIC OFF
        AUTORCC OFF
    )

    add_test(NAME FocusEngineRules COMMAND focusengine_tests)
endif()

# Existing application tests.
option(DAILYPLANNER_BUILD_TESTS
    "Build isolated storage, API and task-card tests" OFF
)

if(DAILYPLANNER_BUILD_TESTS)
    enable_testing()
    find_package(Qt6 REQUIRED COMPONENTS Test QuickTest)

    qt_add_executable(dailyplanner_tests
        tests/test_dailyplanner.cpp
        taskmanager.cpp taskmanager.h task.h
        goaloperations.cpp
        aiservice.cpp aiservice.h breakdownvalidation.h
        focusengine.cpp focusengine.h
        focuscontroller.cpp focuscontroller.h
        authservice.cpp authservice.h
    )

    target_include_directories(dailyplanner_tests PRIVATE
        "${CMAKE_CURRENT_SOURCE_DIR}"
        "${CMAKE_CURRENT_BINARY_DIR}"
    )

    target_link_libraries(dailyplanner_tests PRIVATE
        Qt6::Test
        Qt6::QuickTest
        Qt6::Quick
        Qt6::QuickControls2
        Qt6::Sql
        Qt6::Network
    )

    if(WIN32)
    target_link_libraries(dailyplanner_tests PRIVATE advapi32)
endif()

    qt_add_qml_module(dailyplanner_tests
        URI DailyPlannerTest
        VERSION 1.0
        QML_FILES
            Main.qml
            TaskModal.qml
            TargetSetupModal.qml
            FocusSetupDialog.qml
            TaskDetailsModal.qml
            BottomNavigation.qml
            NavigationIcon.qml
            DateUtils.js
            AppButton.qml
            CalendarWidget.qml
            DateField.qml
            TaskListCard.qml
            CalendarPage.qml
            GoalListCard.qml
            GoalsPage.qml
            PlannerField.qml
            PlannerArea.qml
            GoalForm.qml
            TaskEditModal.qml
            GoalDetailsModal.qml
            AuthModal.qml
    )

    add_test(NAME dailyplanner_tests COMMAND dailyplanner_tests)

    set_tests_properties(dailyplanner_tests PROPERTIES
        ENVIRONMENT "QT_QPA_PLATFORM=offscreen"
    )
endif()

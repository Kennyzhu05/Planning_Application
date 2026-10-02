cmake_minimum_required(VERSION 3.16)

project(DailyPlanner VERSION 0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# 1. Find required Qt6 packages
find_package(Qt6 REQUIRED COMPONENTS Quick QuickControls2 Sql Network)

qt_standard_project_setup(REQUIRES 6.5)

# 2. Define the app executable and C++ source files
qt_add_executable(appDailyPlanner
    main.cpp
    taskmanager.h taskmanager.cpp
    aiservice.h aiservice.cpp
    task.h breakdownvalidation.h
)

# 3. Register QML Module and QML UI files
qt_add_qml_module(appDailyPlanner
    URI DailyPlanner
    VERSION 1.0
    QML_FILES
        Main.qml
        FocusPage.qml
        TaskModal.qml
        TargetSetupModal.qml
        TaskDetailsModal.qml
        BottomNavigation.qml
        NavigationIcon.qml
)

# 4. Link C++ backend & Qt framework libraries
target_link_libraries(appDailyPlanner
    PRIVATE
        Qt6::Quick
        Qt6::QuickControls2
        Qt6::Sql
        Qt6::Network
)

# Set application window icon & properties
set_target_properties(appDailyPlanner PROPERTIES
    MACOSX_BUNDLE_GUI_IDENTIFIER my.dailyplanner.app
    MACOSX_BUNDLE TRUE
    WIN32_EXECUTABLE TRUE
)

option(DAILYPLANNER_BUILD_TESTS "Build isolated storage, API and task-card tests" OFF)
if(DAILYPLANNER_BUILD_TESTS)
    enable_testing()
    find_package(Qt6 REQUIRED COMPONENTS Test)
    qt_add_executable(dailyplanner_tests
        tests/test_dailyplanner.cpp taskmanager.cpp taskmanager.h task.h
        aiservice.cpp aiservice.h breakdownvalidation.h)
    target_include_directories(dailyplanner_tests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
    target_link_libraries(dailyplanner_tests PRIVATE Qt6::Test Qt6::Quick Qt6::QuickControls2 Qt6::Sql Qt6::Network)
    qt_add_qml_module(dailyplanner_tests
        URI DailyPlannerTest VERSION 1.0
        QML_FILES Main.qml TaskModal.qml TargetSetupModal.qml FocusPage.qml TaskDetailsModal.qml
            BottomNavigation.qml NavigationIcon.qml)
    add_test(NAME dailyplanner_tests COMMAND dailyplanner_tests)
    set_tests_properties(dailyplanner_tests PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
endif()

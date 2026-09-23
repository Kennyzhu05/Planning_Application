cmake_minimum_required(VERSION 3.16)

project(DailyPlanner VERSION 0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# 1. ADD QuickControls2 HERE
find_package(Qt6 REQUIRED COMPONENTS Quick QuickControls2 Sql)

qt_standard_project_setup(REQUIRES 6.5)

qt_add_executable(appDailyPlanner
    main.cpp
    taskmanager.h taskmanager.cpp
    aiservice.h aiservice.cpp
)

qt_add_qml_module(appDailyPlanner
    URI DailyPlanner
    VERSION 1.0
    QML_FILES
        Main.qml
        TaskModal.qml
        TargetSetupModal.qml
)

# 2. LINK Qt6::QuickControls2 HERE
target_link_libraries(appDailyPlanner
    PRIVATE
        Qt6::Quick
        Qt6::QuickControls2
        Qt6::Sql
)
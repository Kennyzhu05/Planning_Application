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
    focusengine.h focusengine.cpp
    focuscontroller.h focuscontroller.cpp
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
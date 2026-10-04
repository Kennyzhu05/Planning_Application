cmake_minimum_required(VERSION 3.16)

project(DailyPlanner VERSION 0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Public defaults can be embedded when distributing a build to friends.
# Groq and Supabase admin keys belong exclusively on the server.
set(DAILYPLANNER_API_URL "" CACHE STRING "HTTPS backend /v1/breakdown endpoint")
set(DAILYPLANNER_SUPABASE_URL "" CACHE STRING "Public Supabase project URL")
set(DAILYPLANNER_SUPABASE_PUBLISHABLE_KEY "" CACHE STRING "Public sb_publishable_ key")
if(DAILYPLANNER_SUPABASE_PUBLISHABLE_KEY AND NOT DAILYPLANNER_SUPABASE_PUBLISHABLE_KEY MATCHES "^sb_publishable_[A-Za-z0-9_-]+$")
    message(FATAL_ERROR "Use a public sb_publishable_ key. Groq and Supabase admin keys must never be compiled into the app.")
endif()
configure_file(cmake/dailyplannerconfig.h.in dailyplannerconfig.h @ONLY)

find_package(Qt6 REQUIRED COMPONENTS Quick QuickControls2 Sql Network)
qt_standard_project_setup(REQUIRES 6.5)

if(Qt6_VERSION VERSION_GREATER_EQUAL 6.6)
    qt_policy(SET QTP0002 NEW)
endif()

# Shared sources and include directories are reused by the application and
# optional tests, so both targets follow the same folder layout.
set(DAILYPLANNER_CORE_SOURCES
    src/models/task.h
    src/models/taskmanager.h
    src/models/taskmanager.cpp
    src/models/goaloperations.cpp
    src/models/breakdownvalidation.h
    src/services/aiservice.h
    src/services/aiservice.cpp
    src/services/authservice.h
    src/services/authservice.cpp
    src/focus/focusengine.h
    src/focus/focusengine.cpp
    src/focus/focuscontroller.h
    src/focus/focuscontroller.cpp
)

set(DAILYPLANNER_INCLUDE_DIRS
    "${CMAKE_CURRENT_SOURCE_DIR}/src/models"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/services"
    "${CMAKE_CURRENT_SOURCE_DIR}/src/focus"
    "${CMAKE_CURRENT_BINARY_DIR}"
)

set(DAILYPLANNER_QML_FILES
    qml/Main.qml
    qml/pages/CalendarPage.qml
    qml/pages/GoalsPage.qml
    qml/dialogs/AuthModal.qml
    qml/dialogs/FocusSetupDialog.qml
    qml/dialogs/GoalDetailsModal.qml
    qml/dialogs/GoalForm.qml
    qml/dialogs/TargetSetupModal.qml
    qml/dialogs/TaskDetailsModal.qml
    qml/dialogs/TaskEditModal.qml
    qml/dialogs/TaskModal.qml
    qml/components/AppButton.qml
    qml/components/BottomNavigation.qml
    qml/components/CalendarWidget.qml
    qml/components/CategorySelector.qml
    qml/components/DateField.qml
    qml/components/DurationSpinBox.qml
    qml/components/FormDrawer.qml
    qml/components/GoalListCard.qml
    qml/components/InfoBadge.qml
    qml/components/NavigationIcon.qml
    qml/components/PlannerArea.qml
    qml/components/PlannerCheckBox.qml
    qml/components/PlannerField.qml
    qml/components/StepsEditor.qml
    qml/components/TaskListCard.qml
    qml/utils/DateUtils.js
)

# Physical folders organize the sources; resource aliases keep the existing
# module URLs, component names, and relative DateUtils.js imports unchanged.
# Set these before adding either QML module (including the optional test one).
foreach(qml_file IN LISTS DAILYPLANNER_QML_FILES)
    get_filename_component(qml_name "${qml_file}" NAME)
    set_source_files_properties("${qml_file}" PROPERTIES QT_RESOURCE_ALIAS "${qml_name}")
endforeach()

qt_add_executable(appDailyPlanner src/main.cpp ${DAILYPLANNER_CORE_SOURCES})
qt_add_qml_module(appDailyPlanner
    URI DailyPlanner
    VERSION 1.0
    QML_FILES ${DAILYPLANNER_QML_FILES}
)

target_link_libraries(appDailyPlanner PRIVATE
    Qt6::Quick Qt6::QuickControls2 Qt6::Sql Qt6::Network
)
if(ANDROID)
    # Keep native service sources/resources in the APK, using Qt's Gradle template.
    set_property(TARGET appDailyPlanner PROPERTY QT_ANDROID_PACKAGE_SOURCE_DIR
        "${CMAKE_CURRENT_SOURCE_DIR}/android")
    # Match the already-installed APK so the upgrade keeps its local database.
    set_property(TARGET appDailyPlanner PROPERTY QT_ANDROID_PACKAGE_NAME
        "org.qtproject.example.appDailyPlanner")
    set_property(TARGET appDailyPlanner PROPERTY QT_ANDROID_TARGET_SDK_VERSION 36)
    include("${ANDROID_SDK_ROOT}/android_openssl/android_openssl.cmake")
    add_android_openssl_libraries(appDailyPlanner)
endif()
target_include_directories(appDailyPlanner PRIVATE ${DAILYPLANNER_INCLUDE_DIRS})
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
        src/focus/focusengine.h
        src/focus/focusengine.cpp
    )
    target_include_directories(focusengine_tests PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src/focus")
    set_target_properties(focusengine_tests PROPERTIES
        AUTOMOC OFF
        AUTOUIC OFF
        AUTORCC OFF
    )
    add_test(NAME FocusEngineRules COMMAND focusengine_tests)
endif()

# Existing application tests (not run as part of this reorganization).
option(DAILYPLANNER_BUILD_TESTS "Build isolated storage, API and task-card tests" OFF)
if(DAILYPLANNER_BUILD_TESTS)
    enable_testing()
    find_package(Qt6 REQUIRED COMPONENTS Test QuickTest)
    qt_add_executable(dailyplanner_tests
        tests/test_dailyplanner.cpp
        ${DAILYPLANNER_CORE_SOURCES}
    )
    target_include_directories(dailyplanner_tests PRIVATE ${DAILYPLANNER_INCLUDE_DIRS})
    target_link_libraries(dailyplanner_tests PRIVATE
        Qt6::Test Qt6::QuickTest Qt6::Quick Qt6::QuickControls2 Qt6::Sql Qt6::Network
    )
    if(WIN32)
        target_link_libraries(dailyplanner_tests PRIVATE advapi32)
    endif()
    qt_add_qml_module(dailyplanner_tests
        URI DailyPlannerTest
        VERSION 1.0
        QML_FILES ${DAILYPLANNER_QML_FILES}
    )
    add_test(NAME dailyplanner_tests COMMAND dailyplanner_tests)
    set_tests_properties(dailyplanner_tests PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
endif()

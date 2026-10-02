#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>

#include "taskmanager.h"
#include "aiservice.h"
#include "focuscontroller.h"

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);

    QQuickStyle::setStyle("Basic");

    // Context objects must outlive the QML engine.
    TaskManager taskManager;
    AIService aiService;
    FocusController focusController;

    QQmlApplicationEngine engine;

    engine.rootContext()->setContextProperty(
        "taskManager", &taskManager);

    engine.rootContext()->setContextProperty(
        "aiService", &aiService);

    engine.rootContext()->setContextProperty(
        "focusController", &focusController);

    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreationFailed,
        &app,
        []() { QCoreApplication::exit(-1); },
        Qt::QueuedConnection);

    engine.loadFromModule("DailyPlanner", "Main");

    return app.exec();
}
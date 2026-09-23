#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include "taskmanager.h"
#include "aiservice.h"

int main(int argc, char *argv[]) {
    QGuiApplication app(argc, argv);

    // Forces "Basic" style to enable dark-mode QML customization across desktop & mobile
    QQuickStyle::setStyle("Basic");

    QQmlApplicationEngine engine;

    TaskManager taskManager;
    AIService aiService;

    // Register objects into QML context
    engine.rootContext()->setContextProperty("taskManager", &taskManager);
    engine.rootContext()->setContextProperty("aiService", &aiService);

    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreationFailed,
        &app,
        []() { QCoreApplication::exit(-1); },
        Qt::QueuedConnection);

    engine.loadFromModule("DailyPlanner", "Main");

    return app.exec();
}
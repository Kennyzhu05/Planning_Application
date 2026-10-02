#include <QtTest>
#include <QDir>
#include <QUuid>
#include <QTcpServer>
#include <QTcpSocket>
#include <QPointer>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QSqlQuery>
#include <QSqlError>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>
#include <QQuickItem>
#include <QQuickStyle>
#include <QFontDatabase>
#include <QQmlProperty>
#include <QWheelEvent>
#include "taskmanager.h"
#include "aiservice.h"
#include "focuscontroller.h"

static QVariantList sampleSteps() {
    return {QVariantMap{{"name", "Outline the main message"}, {"description", "Write three main points."}, {"minutes", 10}},
        QVariantMap{{"name", "Draft the slides"}, {"description", "Make one slide for each point."}, {"minutes", 35}}};
}

static QString databaseError(const QString &path) {
    for (const auto &connection : QSqlDatabase::connectionNames()) {
        const auto db = QSqlDatabase::database(connection, false);
        if (db.databaseName() == path && !db.isOpen()) return db.lastError().text();
    }
    return {};
}

// QTemporaryDir installs a private Windows ACL that excludes restricted test
// process tokens. Inherit the approved build directory's ACL instead.
class TestDirectory {
    QString base = QDir::current().absolutePath();
    QString path = base + "/dailyplanner-test-" + QUuid::createUuid().toString(QUuid::WithoutBraces);
    bool valid = QDir().mkpath(path);
public:
    ~TestDirectory() {
        const QString absolute = QDir(path).absolutePath();
        if (absolute.startsWith(base + "/dailyplanner-test-")) QDir(absolute).removeRecursively();
    }
    bool isValid() const { return valid; }
    QString filePath(const QString &name) const { return QDir(path).filePath(name); }
};

static QByteArray completion(const QVariantList &steps, const QString &reason = "stop") {
    const auto content = QJsonDocument(QJsonObject{{"subtasks", QJsonArray::fromVariantList(steps)}}).toJson(QJsonDocument::Compact);
    return QJsonDocument(QJsonObject{{"choices", QJsonArray{QJsonObject{{"finish_reason", reason},
        {"message", QJsonObject{{"content", QString::fromUtf8(content)}}}}}}}).toJson(QJsonDocument::Compact);
}

// Real HTTP transport exercised against loopback only; no production key or task data.
class MockGroq : public QTcpServer {
public:
    struct Response { int status; QByteArray body; int delayMs = 0; };
    QList<Response> responses;
    QList<QJsonObject> requests;
    explicit MockGroq(QObject *parent = nullptr) : QTcpServer(parent) {
        listen(QHostAddress::LocalHost);
        connect(this, &QTcpServer::newConnection, this, [this]() {
            while (hasPendingConnections()) {
                auto socket = nextPendingConnection();
                connect(socket, &QTcpSocket::disconnected, socket, &QObject::deleteLater);
                connect(socket, &QTcpSocket::readyRead, this, [this, socket]() {
                    QByteArray buffer = socket->property("buffer").toByteArray() + socket->readAll();
                    socket->setProperty("buffer", buffer);
                    if (socket->property("handled").toBool()) return;
                    const int end = buffer.indexOf("\r\n\r\n");
                    if (end < 0) return;
                    int length = 0;
                    for (const auto &line : buffer.left(end).split('\n'))
                        if (line.toLower().startsWith("content-length:")) length = line.mid(15).trimmed().toInt();
                    if (buffer.size() < end + 4 + length) return;
                    socket->setProperty("handled", true);
                    requests.append(QJsonDocument::fromJson(buffer.mid(end + 4, length)).object());
                    const Response response = responses.isEmpty() ? Response{500, "{}"} : responses.takeFirst();
                    QPointer<QTcpSocket> guarded(socket);
                    QTimer::singleShot(response.delayMs, this, [guarded, response]() {
                        if (!guarded || guarded->state() != QAbstractSocket::ConnectedState) return;
                        const QByteArray reply = "HTTP/1.1 " + QByteArray::number(response.status)
                            + " Mock\r\nContent-Type: application/json\r\nConnection: close\r\n"
                              "Retry-After: 1\r\nContent-Length: " + QByteArray::number(response.body.size())
                            + "\r\n\r\n" + response.body;
                        guarded->write(reply);
                        guarded->disconnectFromHost();
                    });
                });
            }
        });
    }
    QUrl endpoint() const { return QUrl(QString("http://127.0.0.1:%1/chat/completions").arg(serverPort())); }
};

static QQuickItem *findItem(QQuickItem *root, const QString &name) {
    if (root->objectName() == name) return root;
    for (auto child : root->childItems()) if (auto found = findItem(child, name)) return found;
    return nullptr;
}

class DailyPlannerTests : public QObject {
    Q_OBJECT
    QByteArray previousKey;
    bool hadKey = false;
private slots:
    void init() {
        hadKey = qEnvironmentVariableIsSet("GROQ_API_KEY");
        previousKey = qgetenv("GROQ_API_KEY");
        qputenv("GROQ_API_KEY", "mock-key-not-a-secret");
    }
    void cleanup() {
        if (hadKey) qputenv("GROQ_API_KEY", previousKey);
        else qunsetenv("GROQ_API_KEY");
    }

    void storagePersistenceAndProgress() {
        TestDirectory directory;
        QVERIFY(directory.isValid());
        const auto path = directory.filePath("planner.db");
        int id = 0;
        {
            TaskManager manager(nullptr, path);
            QVERIFY2(databaseError(path).isEmpty(), qPrintable(databaseError(path)));
            QVERIFY(manager.addTask("Presentation", 120, "Work", "A ten-minute talk."));
            id = manager.data(manager.index(0), TaskManager::IdRole).toInt();
            QVERIFY(manager.addTask("Walk", 30, "Health"));
            QCOMPARE(manager.totalPlannedHours(), 2.5);
            QVERIFY(manager.saveSubtasks(id, sampleSteps()));
            QCOMPARE(manager.rowCount(), 2); // Subtasks never become dashboard rows.
            QCOMPARE(manager.totalPlannedHours(), 1.25); // 45 + 30, not 120 + 45 + 30.
            QCOMPARE(manager.getTask(id)["minutes"].toInt(), 120);
            auto steps = manager.getSubtasks(id);
            QVERIFY(manager.toggleSubtask(id, steps[0].toMap()["subtaskId"].toInt()));
            QVERIFY(!manager.getTask(id)["isCompleted"].toBool());
            QVERIFY(manager.toggleSubtask(id, steps[1].toMap()["subtaskId"].toInt()));
            QVERIFY(manager.getTask(id)["isCompleted"].toBool());
            QCOMPARE(manager.totalPlannedHours(), 1.25);
            QVERIFY(manager.toggleSubtask(id, steps[0].toMap()["subtaskId"].toInt()));
            QVERIFY(!manager.getTask(id)["isCompleted"].toBool());
            QVERIFY(manager.toggleTaskById(id));
            QCOMPARE(manager.getTask(id)["completedSubtaskCount"].toInt(), 2);
            QVERIFY(manager.toggleTaskById(id));
            QCOMPARE(manager.getTask(id)["completedSubtaskCount"].toInt(), 0);
            QVERIFY(manager.toggleSubtask(id, steps[0].toMap()["subtaskId"].toInt()));
        }
        {
            TaskManager manager(nullptr, path);
            QCOMPARE(manager.getSubtasks(id).size(), 2);
            QCOMPARE(manager.getTask(id)["completedSubtaskCount"].toInt(), 1);
            QCOMPARE(manager.getTask(id)["description"].toString(), QString("A ten-minute talk."));
            QVERIFY(manager.saveSubtasks(id, sampleSteps()));
            QCOMPARE(manager.getTask(id)["completedSubtaskCount"].toInt(), 0);
            manager.deleteTask(0);
            QVERIFY(manager.getSubtasks(id).isEmpty());
            QCOMPARE(manager.totalPlannedHours(), 0.5);
        }
        TaskManager reopened(nullptr, path);
        QCOMPARE(reopened.rowCount(), 1);
        QVERIFY(reopened.getTask(id).isEmpty());
    }

    void legacyDatabaseUpgrade() {
        TestDirectory directory;
        QVERIFY(directory.isValid());
        const auto path = directory.filePath("legacy.db");
        {
            auto db = QSqlDatabase::addDatabase("QSQLITE", "legacy-fixture");
            db.setDatabaseName(path);
            QVERIFY2(db.open(), qPrintable(db.lastError().text()));
            QSqlQuery query(db);
            QVERIFY(query.exec("CREATE TABLE tasks (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, category TEXT, "
                               "minutes INTEGER, description TEXT, completed INTEGER)"));
            QVERIFY(query.exec("INSERT INTO tasks VALUES (7, 'Existing task', 'Personal', 60, '', 1)"));
            QVERIFY(query.exec("CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT)"));
            QVERIFY(query.exec("INSERT INTO settings VALUES ('targetHours', '6')"));
        }
        QSqlDatabase::removeDatabase("legacy-fixture");
        TaskManager manager(nullptr, path);
        QVERIFY2(databaseError(path).isEmpty(), qPrintable(databaseError(path)));
        QCOMPARE(manager.targetHours(), 6.0);
        QCOMPARE(manager.rowCount(), 1);
        QVERIFY(manager.getTask(7)["isCompleted"].toBool());
        QVERIFY(manager.saveSubtasks(7, sampleSteps()));
        QCOMPARE(manager.getTask(7)["name"].toString(), QString("Existing task"));
    }

    void invalidBreakdown_data() {
        QTest::addColumn<QVariantList>("steps");
        QTest::newRow("empty") << QVariantList{};
        auto emptyName = sampleSteps();
        auto step = emptyName[0].toMap();
        step["name"] = "  ";
        emptyName[0] = step;
        QTest::newRow("blank-title") << emptyName;
        for (const auto &value : QVariantList{0, 121, 3.5, QString("10")}) {
            auto steps = sampleSteps();
            auto bad = steps[0].toMap();
            bad["minutes"] = value;
            steps[0] = bad;
            QTest::newRow(qPrintable("duration-" + value.toString())) << steps;
        }
        QVariantList tooMany;
        for (int i = 0; i < 13; ++i) tooMany.append(sampleSteps().first());
        QTest::newRow("too-many") << tooMany;
    }
    void invalidBreakdown() {
        QFETCH(QVariantList, steps);
        TaskManager manager(nullptr, ":memory:");
        QVERIFY(manager.addTask("Task", 60, "Work"));
        const int id = manager.getTask(1)["taskId"].toInt();
        QVERIFY(manager.saveSubtasks(id, sampleSteps()));
        const auto before = manager.getSubtasks(id);
        QVERIFY(!manager.saveSubtasks(id, steps));
        QCOMPARE(manager.getSubtasks(id), before);
    }

    void transactionRollback() {
        TestDirectory directory;
        QVERIFY(directory.isValid());
        const auto path = directory.filePath("rollback.db");
        TaskManager manager(nullptr, path);
        QVERIFY(manager.addTask("Task", 60, "Work"));
        QVERIFY(manager.saveSubtasks(1, sampleSteps()));
        const auto before = manager.getSubtasks(1);
        {
            auto db = QSqlDatabase::addDatabase("QSQLITE", "failure-fixture");
            db.setDatabaseName(path);
            QVERIFY(db.open());
            QSqlQuery query(db);
            QVERIFY(query.exec("CREATE TRIGGER reject_insert BEFORE INSERT ON subtasks "
                               "BEGIN SELECT RAISE(ABORT, 'simulated failure'); END"));
            QVERIFY(!manager.saveSubtasks(1, sampleSteps()));
            QCOMPARE(manager.getSubtasks(1), before);
            TaskManager reopened(nullptr, path);
            QCOMPARE(reopened.getSubtasks(1), before);
            QVERIFY(query.exec("DROP TRIGGER reject_insert"));
            QVERIFY(query.exec("CREATE TRIGGER reject_update BEFORE UPDATE ON tasks "
                               "BEGIN SELECT RAISE(ABORT, 'simulated failure'); END"));
            QVERIFY(!manager.toggleSubtask(1, before.first().toMap()["subtaskId"].toInt()));
            QCOMPARE(manager.getSubtasks(1), before);
            TaskManager afterFailedToggle(nullptr, path);
            QCOMPARE(afterFailedToggle.getSubtasks(1), before);
            QVERIFY(!manager.toggleTaskById(1));
            QVERIFY(query.exec("DROP TRIGGER reject_update"));
            QVERIFY(query.exec("CREATE TRIGGER reject_delete BEFORE DELETE ON tasks "
                               "BEGIN SELECT RAISE(ABORT, 'simulated failure'); END"));
            manager.deleteTask(0);
            QCOMPARE(manager.rowCount(), 1);
            TaskManager afterFailedDelete(nullptr, path);
            QCOMPARE(afterFailedDelete.getSubtasks(1), before);
        }
        QSqlDatabase::removeDatabase("failure-fixture");
    }

    void apiRequestAndValidation() {
        MockGroq server;
        server.responses.append({200, completion(sampleSteps())});
        AIService service(nullptr, server.endpoint());
        QSignalSpy complete(&service, &AIService::breakdownComplete);
        QSignalSpy errors(&service, &AIService::errorOccurred);
        const QVariantMap task{{"taskId", 42}, {"name", "Presentation"}, {"description", "Talk about solar power."},
                               {"category", "Work"}, {"minutes", 120}};
        service.breakdownTask(42, task);
        QVERIFY(service.busy());
        service.breakdownTask(99, task); // Prevent overlapping requests.
        QTRY_COMPARE(complete.count(), 1);
        QCOMPARE(errors.count(), 0);
        QVERIFY(!service.busy());
        QCOMPARE(complete.first()[0].toInt(), 42);
        QCOMPARE(complete.first()[1].toList(), sampleSteps());
        QCOMPARE(server.requests.size(), 1);
        const auto request = server.requests.first();
        QCOMPARE(request["model"].toString(), QString("openai/gpt-oss-20b"));
        QVERIFY(request["response_format"].toObject()["json_schema"].toObject()["strict"].toBool());
        const auto messages = request["messages"].toArray();
        const auto context = QJsonDocument::fromJson(messages[1].toObject()["content"].toString().toUtf8()).object();
        QCOMPARE(context["description"].toString(), QString("Talk about solar power."));
        QVERIFY(!QJsonDocument(request).toJson().contains("mock-key-not-a-secret"));
    }

    void apiFailures_data() {
        QTest::addColumn<int>("status");
        QTest::addColumn<QByteArray>("body");
        QTest::addColumn<QString>("expected");
        QTest::newRow("authentication") << 401 << QByteArray("{\"error\":\"sensitive provider response\"}") << QString("key");
        QTest::newRow("forbidden") << 403 << QByteArray("{}") << QString("permissions");
        QTest::newRow("rate-limit") << 429 << QByteArray("{}") << QString("Retry in 1 seconds");
        QTest::newRow("server") << 503 << QByteArray("{}") << QString("unavailable");
        QTest::newRow("bad-json") << 200 << QByteArray("not-json") << QString("invalid");
        QTest::newRow("truncated") << 200 << completion(sampleSteps(), "length") << QString("incomplete");
        auto invalid = sampleSteps();
        auto step = invalid[0].toMap();
        step["minutes"] = 121;
        invalid[0] = step;
        QTest::newRow("invalid-duration") << 200 << completion(invalid) << QString("invalid");
        QTest::newRow("empty-steps") << 200 << completion({}) << QString("invalid");
    }
    void apiFailures() {
        QFETCH(int, status);
        QFETCH(QByteArray, body);
        QFETCH(QString, expected);
        MockGroq server;
        server.responses.append({status, body});
        AIService service(nullptr, server.endpoint());
        QSignalSpy complete(&service, &AIService::breakdownComplete);
        QSignalSpy errors(&service, &AIService::errorOccurred);
        service.breakdownTask(1, {{"taskId", 1}, {"name", "Task"}});
        QTRY_COMPARE(errors.count(), 1);
        QVERIFY(errors.first()[1].toString().contains(expected));
        QVERIFY(!errors.first()[1].toString().contains("sensitive provider response"));
        QCOMPARE(complete.count(), 0);
        QVERIFY(!service.busy());
    }

    void missingKeyAndNetworkFailure() {
        qunsetenv("GROQ_API_KEY");
        AIService service(nullptr, QUrl("http://127.0.0.1:1"));
        QSignalSpy errors(&service, &AIService::errorOccurred);
        service.breakdownTask(1, {{"taskId", 1}, {"name", "Task"}});
        QCOMPARE(errors.count(), 1);
        QVERIFY(errors.first()[1].toString().contains("GROQ_API_KEY"));
        qputenv("GROQ_API_KEY", "mock-key-not-a-secret");
        errors.clear();
        service.breakdownTask(1, {{"taskId", 1}, {"name", "Task"}});
        QTRY_COMPARE(errors.count(), 1);
        QVERIFY(errors.first()[1].toString().contains("connection"));
    }

    void cancellationAndTimeout() {
        MockGroq server;
        server.responses.append({200, completion(sampleSteps()), 200});
        server.responses.append({200, completion(sampleSteps())});
        AIService service(nullptr, server.endpoint());
        QSignalSpy complete(&service, &AIService::breakdownComplete);
        QSignalSpy errors(&service, &AIService::errorOccurred);
        service.breakdownTask(1, {{"taskId", 1}, {"name", "Old task"}});
        QTRY_COMPARE(server.requests.size(), 1);
        service.cancel();
        QVERIFY(!service.busy());
        service.breakdownTask(2, {{"taskId", 2}, {"name", "New task"}});
        QTRY_COMPARE(complete.count(), 1);
        QCOMPARE(complete.first()[0].toInt(), 2);
        QTest::qWait(250);
        QCOMPARE(complete.count(), 1);
        QCOMPARE(errors.count(), 0);

        server.responses.append({200, completion(sampleSteps()), 200});
        AIService shortTimeout(nullptr, server.endpoint(), 50);
        QSignalSpy timedOut(&shortTimeout, &AIService::errorOccurred);
        QSignalSpy timedComplete(&shortTimeout, &AIService::breakdownComplete);
        shortTimeout.breakdownTask(3, {{"taskId", 3}, {"name", "Slow task"}});
        QTRY_COMPARE(timedOut.count(), 1);
        QVERIFY(timedOut.first()[1].toString().contains("timed out"));
        QVERIFY(!shortTimeout.busy());
        QTest::qWait(250);
        QCOMPARE(timedComplete.count(), 0);
    }

    void taskCardFlow() {
        TestDirectory directory;
        QVERIFY(directory.isValid());
        TaskManager manager(nullptr, directory.filePath("ui.db"));
        QVERIFY(manager.addTask("Prepare a presentation", 120, "Work", "A ten-minute talk about renewable energy."));
        QVERIFY(manager.addTask("Go for a walk", 30, "Health"));
        MockGroq server;
        server.responses.append({200, completion(sampleSteps()), 100});
        AIService service(nullptr, server.endpoint());
        FocusController focusController;

        QQmlApplicationEngine engine;
        engine.rootContext()->setContextProperty("taskManager", &manager);
        engine.rootContext()->setContextProperty("aiService", &service);
        engine.rootContext()->setContextProperty(
            "focusController", &focusController);
        QSignalSpy warnings(&engine, &QQmlEngine::warnings);
        engine.loadFromModule("DailyPlannerTest", "Main");
        QVERIFY(!engine.rootObjects().isEmpty());
        auto window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
        QVERIFY(window);
        auto target = window->findChild<QObject *>("targetModal");
        QVERIFY(target);
        target->setProperty("visible", false);
        QVERIFY(QTest::qWaitForWindowExposed(window));
        auto item = [&](const QString &name) { return findItem(window->contentItem(), name); };
        auto click = [&](QQuickItem *control) {
            QVERIFY(control);
            QTest::mouseClick(window, Qt::LeftButton, Qt::NoModifier,
                control->mapToScene(QPointF(control->width()/2, control->height()/2)).toPoint());
        };
        QTRY_VERIFY(item("taskRow1"));
        auto card = item("taskDetailsModal");
        QVERIFY(card);
        click(item("taskCheckbox1"));
        QVERIFY(manager.getTask(1)["isCompleted"].toBool());
        QVERIFY(!card->isVisible());
        click(item("taskRow1"));
        QTRY_VERIFY(card->isVisible());
        QVERIFY(!item("dashboardContent")->isEnabled());
        QVERIFY(item("dashboardContent")->property("layer").isValid());
        QCOMPARE(card->property("selectedTaskId").toInt(), 1);
        QVERIFY(item("detailsCard")->width() <= window->width());
        click(item("breakdownAction"));
        QVERIFY(service.busy());
        QTRY_VERIFY(card->property("hasPreview").toBool());
        QCOMPARE(card->property("suggestedMinutes").toInt(), 45);

        QTRY_VERIFY(item("suggestedTitle0"));
        auto title = item("suggestedTitle0");
        click(title);
        QTest::keyClick(window, Qt::Key_A, Qt::ControlModifier);
        for (const char character : QByteArray("Write the outline"))
            QTest::keyClick(window, character);
        // Duration edits and removal must update the preview's planned total.
        click(item("suggestedMinutes0"));
        QTest::keyClick(window, Qt::Key_Up);
        QTest::keyClick(window, Qt::Key_Tab);
        QTRY_COMPARE(card->property("suggestedMinutes").toInt(), 46);
        click(item("breakdownAction"));
        QTRY_VERIFY(!card->property("hasPreview").toBool());
        QCOMPARE(manager.getSubtasks(1).first().toMap()["name"].toString(), QString("Write the outline"));
        QCOMPARE(manager.getSubtasks(1).first().toMap()["minutes"].toInt(), 11);
        QCOMPARE(manager.getTask(1)["subtaskCount"].toInt(), 2);
        QCOMPARE(manager.rowCount(), 2);
        QTRY_VERIFY(item("subtaskCheck0"));
        click(item("subtaskCheck0"));
        QCOMPARE(manager.getTask(1)["completedSubtaskCount"].toInt(), 1);
        if (!qEnvironmentVariableIsEmpty("DAILYPLANNER_TEST_SCREENSHOT"))
            QTest::qWait(100);
        if (!qEnvironmentVariableIsEmpty("DAILYPLANNER_TEST_SCREENSHOT"))
            QVERIFY(window->grabWindow().save(qEnvironmentVariable("DAILYPLANNER_TEST_SCREENSHOT")));
        QTest::keyClick(window, Qt::Key_Escape);
        QTRY_VERIFY(!card->isVisible());
        click(item("taskRow1"));
        QTRY_VERIFY(card->isVisible());
        QCOMPARE(server.requests.size(), 1); // Reopening loads SQLite, not another request.

        server.responses.append({200, completion(sampleSteps())});
        click(item("breakdownAction"));
        QTRY_VERIFY(card->property("hasPreview").toBool());
        QTest::keyClick(window, Qt::Key_Escape);
        QCOMPARE(card->property("confirmation").toString(), QString("discard"));
        QTest::keyClick(window, Qt::Key_Escape);
        QCOMPARE(card->property("confirmation").toString(), QString());
        // A failed save preserves both the saved checklist and the preview.
        const auto beforeReplacement = manager.getSubtasks(1);
        {
            auto db = QSqlDatabase::addDatabase("QSQLITE", "ui-save-failure");
            db.setDatabaseName(directory.filePath("ui.db"));
            QVERIFY(db.open());
            QSqlQuery query(db);
            QVERIFY(query.exec("CREATE TRIGGER reject_ui_insert BEFORE INSERT ON subtasks "
                               "BEGIN SELECT RAISE(ABORT, 'simulated failure'); END"));
            click(item("breakdownAction"));
            click(item("confirmBreakdownAction"));
            QVERIFY(card->property("hasPreview").toBool());
            QVERIFY(!card->property("errorMessage").toString().isEmpty());
            QCOMPARE(manager.getSubtasks(1), beforeReplacement);
            QVERIFY(query.exec("DROP TRIGGER reject_ui_insert"));
        }
        QSqlDatabase::removeDatabase("ui-save-failure");
        click(item("removeSuggestion1"));
        QTRY_COMPARE(card->property("suggestedMinutes").toInt(), 10);
        click(item("breakdownAction"));
        QCOMPARE(card->property("confirmation").toString(), QString("replace"));
        click(item("confirmBreakdownAction"));
        QCOMPARE(manager.getTask(1)["completedSubtaskCount"].toInt(), 0);
        QCOMPARE(manager.getSubtasks(1).size(), 1);

        server.responses.append({200, completion(sampleSteps())});
        click(item("breakdownAction"));
        QTRY_VERIFY(card->property("hasPreview").toBool());
        QTest::keyClick(window, Qt::Key_Escape);
        click(item("confirmBreakdownAction"));
        QTRY_VERIFY(!card->isVisible());
        QCOMPARE(manager.getSubtasks(1).size(), 1);

        click(item("taskRow1"));
        window->resize(320, 568);
        QTest::qWait(100);
        QVERIFY(item("detailsCard")->height() <= window->height());
        QVERIFY(item("detailsCard")->width() <= window->width());
        window->resize(390, 844);
        QTest::keyClick(window, Qt::Key_Escape);
        QTRY_VERIFY(!card->isVisible());

        // Closing a pending request and opening another task never shows old suggestions.
        click(item("taskRow1"));
        server.responses.append({200, completion(sampleSteps()), 200});
        click(item("breakdownAction"));
        QTRY_VERIFY(service.busy());
        QTest::keyClick(window, Qt::Key_Escape);
        QVERIFY(!service.busy());
        click(item("taskRow2"));
        QCOMPARE(card->property("selectedTaskId").toInt(), 2);
        QTest::qWait(250);
        QVERIFY(!card->property("hasPreview").toBool());

        qunsetenv("GROQ_API_KEY");
        click(item("breakdownAction"));
        QVERIFY(card->property("errorMessage").toString().contains("GROQ_API_KEY"));
        QVERIFY(card->isVisible());
        qputenv("GROQ_API_KEY", "mock-key-not-a-secret");
        QTest::keyClick(window, Qt::Key_Escape);
        QTRY_VERIFY(!card->isVisible());
        // A real swipe exposes deletion without opening the details card.
        auto row = item("taskRow1");
        const auto start = row->mapToScene(QPointF(row->width() - 30, row->height()/2)).toPoint();
        const auto end = row->mapToScene(QPointF(30, row->height()/2)).toPoint();
        QTest::mousePress(window, Qt::LeftButton, Qt::NoModifier, start);
        QTest::mouseMove(window, end, 100);
        QTest::mouseRelease(window, Qt::LeftButton, Qt::NoModifier, end);
        QTRY_COMPARE(QQmlProperty(row, "swipe.position").read().toDouble(), -1.0);
        QTest::qWait(50);
        QVERIFY(!card->isVisible());
        click(item("deleteTask1"));
        QTRY_VERIFY(manager.getTask(1).isEmpty());
        QVERIFY(manager.getSubtasks(1).isEmpty());
        QCOMPARE(warnings.count(), 0);
    }

    void focusControlFlow() {
        TestDirectory directory;
        QVERIFY(directory.isValid());
        TaskManager manager(nullptr, directory.filePath("focus-ui.db"));
        manager.setTargetHours(8);
        AIService service;
        FocusController focusController;
        QQmlApplicationEngine engine;
        engine.rootContext()->setContextProperty("taskManager", &manager);
        engine.rootContext()->setContextProperty("aiService", &service);
        engine.rootContext()->setContextProperty("focusController", &focusController);
        QSignalSpy warnings(&engine, &QQmlEngine::warnings);
        engine.loadFromModule("DailyPlannerTest", "Main");
        QVERIFY(!engine.rootObjects().isEmpty());
        auto window = qobject_cast<QQuickWindow *>(engine.rootObjects().first());
        QVERIFY(window);
        QVERIFY(QTest::qWaitForWindowExposed(window));
        auto item = [&](const QString &name) { return findItem(window->contentItem(), name); };
        auto click = [&](const QString &name) {
            auto control = item(name);
            if (!control || !control->isVisible() || control->width() <= 0 || control->height() <= 0)
                return false;
            QTest::mouseClick(window, Qt::LeftButton, Qt::NoModifier,
                control->mapToScene(QPointF(control->width()/2, control->height()/2)).toPoint());
            return true;
        };
        auto capture = [&](const QString &name) {
            const QString output = qEnvironmentVariable("FOCUS_UI_SCREENSHOT_DIR");
            if (output.isEmpty()) return true;
            QTest::qWait(240);
            return window->grabWindow().save(output + "/" + name + ".png");
        };
        auto dialog = window->findChild<QObject *>("focusSetupDialog");
        QVERIFY(dialog);
        QTRY_VERIFY(item("focusControl"));
        auto control = item("focusControl");
        auto title = item("dashboardTitle");
        auto date = item("dashboardDate");
        QVERIFY(title && date);
        QCOMPARE(title->property("font").value<QFont>().pixelSize(), 24);
        QCOMPARE(date->property("font").value<QFont>().pixelSize(), 13);
        QCOMPARE(control->property("text").toString(), QString("Start Focus"));
        QVERIFY(control->width() < 120);
        QVERIFY(capture("focus-idle"));

        // The header remains readable at the standard and narrow phone widths.
        for (int width : {390, 320}) {
            window->resize(width, 844);
            QTest::qWait(100);
            const QRectF buttonRect(control->mapToScene(QPointF()), control->size());
            const QRectF titleRect(title->mapToScene(QPointF()), title->size());
            const QRectF dateRect(date->mapToScene(QPointF()), date->size());
            QVERIFY(!buttonRect.intersects(titleRect));
            QVERIFY(!buttonRect.intersects(dateRect));
            QVERIFY(buttonRect.right() <= width - 19);
            QCOMPARE(title->property("font").value<QFont>().pixelSize(), 24);
            QCOMPARE(date->property("font").value<QFont>().pixelSize(), 13);
        }
        QVERIFY(capture("focus-narrow"));
        window->resize(390, 844);
        QTest::qWait(100);

        QVERIFY(click("focusControl"));
        QTRY_VERIFY(dialog->property("opened").toBool());
        QCOMPARE(window->property("currentPage").toInt(), 0);
        QVERIFY(item("dashboardContent")->isVisible());
        QVERIFY(capture("focus-mode-popup"));
        QVERIFY(!item("focusSetupCancel"));
        QTest::mouseClick(window, Qt::LeftButton, Qt::NoModifier, QPoint(10, 10));
        QTRY_VERIFY(!dialog->property("visible").toBool());
        QVERIFY(!focusController.running());

        // Outside clicks also cancel the duration stage without starting focus.
        QVERIFY(click("focusControl"));
        QTRY_VERIFY(dialog->property("opened").toBool());
        QVERIFY(click("focusTimedOption"));
        QTRY_VERIFY(item("focusMinutesInput")->isVisible());
        QTest::mouseClick(window, Qt::LeftButton, Qt::NoModifier, QPoint(10, 10));
        QTRY_VERIFY(!dialog->property("visible").toBool());
        QVERIFY(!focusController.running());
        QVERIFY(click("focusControl"));
        QTRY_VERIFY(dialog->property("opened").toBool());
        QVERIFY(click("focusTimedOption"));
        QTRY_VERIFY(item("focusChooseMode")->isVisible());
        QVERIFY(click("focusChooseMode"));
        QTRY_VERIFY(!dialog->property("editingDuration").toBool());
        QVERIFY(item("focusOpenEndedOption")->isVisible());
        QTest::keyClick(window, Qt::Key_Escape);
        QTRY_VERIFY(!dialog->property("visible").toBool());
        QVERIFY(!focusController.running());

        // Choosing Open-ended starts immediately without a second confirmation.
        QVERIFY(click("focusControl"));
        QTRY_VERIFY(dialog->property("opened").toBool());
        QVERIFY(click("focusOpenEndedOption"));
        QTRY_VERIFY(focusController.running());
        QVERIFY(!focusController.timed());
        QTRY_VERIFY(!dialog->property("visible").toBool());
        QTRY_COMPARE(item("focusControlBackground")->property("color").value<QColor>(), QColor("#C2410C"));
        QVERIFY(item("focusStopSquare")->isVisible());
        QTRY_VERIFY(focusController.elapsedSeconds() >= 1);
        const auto elapsedSeconds = focusController.elapsedSeconds();
        QCOMPARE(control->property("text").toString(), QString("%1:%2")
            .arg(elapsedSeconds / 60, 2, 10, QLatin1Char('0'))
            .arg(elapsedSeconds % 60, 2, 10, QLatin1Char('0')));
        QVERIFY(capture("focus-open-ended"));
        window->setProperty("currentPage", 3);
        QTest::qWait(1100);
        QVERIFY(focusController.running());
        window->setProperty("currentPage", 0);
        QTest::qWait(100);
        QTest::mouseClick(window, Qt::LeftButton, Qt::NoModifier,
            item("focusStopSquare")->mapToScene(QPointF(5, 5)).toPoint());
        QCOMPARE(focusController.status(), QString("Stopped"));
        QVERIFY(!focusController.running());
        QCOMPARE(control->property("text").toString(), QString("Start Focus"));

        // Timed focus uses wheel selection and still rejects zero duration.
        QVERIFY(click("focusControl"));
        QTRY_VERIFY(dialog->property("opened").toBool());
        QVERIFY(click("focusTimedOption"));
        QTRY_VERIFY(item("focusMinutesInput")->isVisible());
        auto hours = item("focusHoursInput");
        auto minutes = item("focusMinutesInput");
        QVERIFY(hours && minutes);
        QVERIFY(capture("focus-duration-popup"));
        hours->setProperty("currentIndex", 0);
        minutes->setProperty("currentIndex", 0);
        QVERIFY(click("focusTimedStart"));
        QVERIFY(!focusController.running());
        QVERIFY(dialog->property("visible").toBool());
        QVERIFY(!item("focusStartError")->property("text").toString().isEmpty());

        // Send real wheel events through the window, not directly to the model.
        const auto minutePoint = minutes->mapToScene(QPointF(minutes->width()/2, minutes->height()/2));
        QWheelEvent wheelEvent(minutePoint, window->mapToGlobal(minutePoint.toPoint()),
            QPoint(), QPoint(0, -120), Qt::NoButton, Qt::NoModifier, Qt::NoScrollPhase, false);
        QCoreApplication::sendEvent(window, &wheelEvent);
        QTRY_VERIFY(minutes->property("currentIndex").toInt() > 0);
        QTRY_VERIFY(!minutes->property("moving").toBool());
        QVERIFY(item("focusStartError")->property("text").toString().isEmpty());

        // Drag the hour wheel, including in the narrow phone-sized window.
        window->resize(320, 568);
        QTest::qWait(100);
        const auto hourStart = hours->mapToScene(QPointF(hours->width()/2, hours->height()/2 + 40)).toPoint();
        QTest::mousePress(window, Qt::LeftButton, Qt::NoModifier, hourStart);
        for (int step = 1; step <= 8; ++step)
            QTest::mouseMove(window, hourStart - QPoint(0, step * 10), 30);
        QTest::mouseRelease(window, Qt::LeftButton, Qt::NoModifier, hourStart - QPoint(0, 80));
        QTRY_VERIFY(hours->property("currentIndex").toInt() > 0);
        QTRY_VERIFY(!hours->property("moving").toBool());
        QVERIFY(dialog->property("visible").toBool());
        QVERIFY(!focusController.running());
        window->resize(390, 844);
        QTest::qWait(100);
        hours->setProperty("currentIndex", 0);
        minutes->setProperty("currentIndex", 25);
        QVERIFY(capture("focus-duration-popup"));
        QVERIFY(click("focusTimedStart"));
        QTRY_VERIFY(focusController.running());
        QVERIFY(focusController.timed());
        QCOMPARE(focusController.plannedSeconds(), 1500);
        QCOMPARE(control->property("text").toString(), QString("25:00"));
        QTRY_VERIFY(!dialog->property("visible").toBool());
        QVERIFY(capture("focus-timed"));
        QVERIFY(click("focusControl"));
        QCOMPARE(focusController.status(), QString("Stopped"));

        // The 24-hour limit cannot keep a nonzero minute field.
        QVERIFY(click("focusControl"));
        QTRY_VERIFY(dialog->property("opened").toBool());
        QVERIFY(click("focusTimedOption"));
        hours->setProperty("currentIndex", 24);
        QTRY_COMPARE(minutes->property("currentIndex").toInt(), 0);
        QVERIFY(!minutes->isEnabled());
        QVERIFY(click("focusTimedStart"));
        QTRY_VERIFY(focusController.running());
        QCOMPARE(focusController.plannedSeconds(), 86400);
        QCOMPARE(control->property("text").toString(), QString("24:00:00"));
        QTRY_VERIFY(!dialog->property("visible").toBool());
        QVERIFY(capture("focus-24-hours"));
        QVERIFY(click("focusControl"));

        // Actual timer completion returns the compact control to its idle state.
        QVERIFY(click("focusControl"));
        QTRY_VERIFY(dialog->property("opened").toBool());
        QVERIFY(click("focusTimedOption"));
        hours->setProperty("currentIndex", 0);
        minutes->setProperty("currentIndex", 1);
        QVERIFY(click("focusTimedStart"));
        QTRY_VERIFY(focusController.running());
        QTRY_VERIFY(!dialog->property("visible").toBool());
        QTRY_VERIFY(focusController.remainingSeconds() < 60);
        QTRY_COMPARE_WITH_TIMEOUT(focusController.status(), QString("Completed"), 65000);
        QCOMPARE(control->property("text").toString(), QString("Start Focus"));
        QVERIFY(!item("focusStopSquare")->isVisible());
        QCOMPARE(warnings.count(), 0);
    }

    void liveGroqSmokeTest() {
        if (previousKey.trimmed().isEmpty())
            QSKIP("No locally configured GROQ_API_KEY; live provider smoke test is pending.");
        qputenv("GROQ_API_KEY", previousKey);
        AIService service;
        QSignalSpy complete(&service, &AIService::breakdownComplete);
        QSignalSpy errors(&service, &AIService::errorOccurred);
        const QStringList titles{"Prepare a renewable-energy presentation", "Improve my workspace", "Send a meeting reminder"};
        for (int i = 0; i < titles.size(); ++i) {
            complete.clear();
            errors.clear();
            service.breakdownTask(i + 1, {{"taskId", i + 1}, {"name", titles[i]},
                {"description", "Sample task for development testing."}, {"category", "Work"}, {"minutes", 60}});
            QTRY_VERIFY_WITH_TIMEOUT(!complete.isEmpty() || !errors.isEmpty(), 50000);
            QVERIFY2(errors.isEmpty(), errors.isEmpty() ? "" : qPrintable(errors.first()[1].toString()));
            QVERIFY(!complete.first()[1].toList().isEmpty());
        }
    }
};

int main(int argc, char **argv) {
    QGuiApplication app(argc, argv);
#ifdef Q_OS_WIN
    // The offscreen platform does not enumerate Windows system fonts.
    const int fontId = QFontDatabase::addApplicationFont(qEnvironmentVariable("WINDIR") + "/Fonts/segoeui.ttf");
    if (fontId >= 0) QGuiApplication::setFont(QFont(QFontDatabase::applicationFontFamilies(fontId).first()));
#endif
    QQuickStyle::setStyle("Basic");
    DailyPlannerTests tests;
    return QTest::qExec(&tests, argc, argv);
}

#include "test_dailyplanner.moc"

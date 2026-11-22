# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.27.0

/**
 * White-box tests for telegram: jennifer test src/telegram_test.j
 *
 * Form encoding, response parsing, keyboards and uploads are tested directly.
 * The API calls go to an `httpd` server on a loopback port (through `botWith`),
 * which answers one request with a canned Bot API reply and hands back what it
 * received.
 */
use encoding;
use httpd;
use os;
use task;
use testing;

def const TOKEN as string init "123456:TESTTOKEN";

/** One request as the fake server saw it. */
def struct Seen {
    method as string,
    path as string,
    contentType as string,
    body as bytes
};

/**
 * Answer one request with `reply` and status 200.
 *
 * @param srv {httpd.Server} the listening server
 * @param reply {string} the JSON body to answer with
 * @return {Seen} the request
 */
func answerOne(srv as httpd.Server, reply as string) {
    def req as httpd.Request init httpd.accept($srv);
    def seen as Seen init Seen{
        method: httpd.method($req),
        path: httpd.path($req),
        contentType: httpd.header($req, "Content-Type"),
        body: httpd.body($req)
    };
    httpd.respond($req, 200, $reply);
    return $seen;
}

/**
 * The form fields of a seen request.
 *
 * @param seen {Seen} the request
 * @return {map of string to string} the decoded form
 */
func formOf(seen as Seen) {
    return uri.parseQuery(encoding.decode("utf-8", $seen.body));
}

/**
 * A bot pointed at a loopback server.
 *
 * @param srv {httpd.Server} the listening server
 * @return {Bot} the bot
 */
func localBot(srv as httpd.Server) {
    return botWith(TOKEN, "http://" + httpd.address($srv));
}

func testFormEncode() {
    def p as map of string to string init {};
    $p["chat_id"] = "12345";
    $p["text"] = "hi there & <ok>";
    testing.assertEqual(formEncode($p), "chat_id=12345&text=hi+there+%26+%3Cok%3E");
}

func testCheckResponseThrowsOnError() {
    def node as json.Value init json.decode('{"ok":false,"error_code":401,' +
        '"description":"Unauthorized"}');
    def threw as bool init false;
    try {
        checkResponse($node, 401);
    } catch (e) {
        $threw = true;
        testing.assertEqual($e.kind, "telegram");
        testing.assertEqual($e.errorCode, 401);
        testing.assertEqual($e.status, 401);
        testing.assertEqual($e.retryAfter, 0);
        testing.assertEqual($e.message, "telegram: Unauthorized");
    }
    testing.assertTrue($threw);
}

# Flood control and a migrated group carry their parameters into the error.
func testApiErrorsCarryTheirParameters() {
    try {
        checkResponse(
            json.decode('{"ok":false,"error_code":429,"description":"Too Many Requests: retry after 35",' +
                '"parameters":{"retry_after":35}}'),
            429);
        throw Error{kind: "missed", message: "a 429"};
    } catch (e) {
        testing.assertEqual($e.errorCode, 429);
        testing.assertEqual($e.retryAfter, 35);
    }
    try {
        checkResponse(
            json.decode('{"ok":false,"error_code":400,"description":"Bad Request: group chat was upgraded",' +
                '"parameters":{"migrate_to_chat_id":-1001234567890}}'),
            400);
        throw Error{kind: "missed", message: "a migrated group"};
    } catch (e) {
        testing.assertEqual($e.migrateToChatId, -1001234567890);
    }
    try {
        fail("local");
    } catch (e) {
        testing.assertEqual($e.errorCode, 0);
        testing.assertEqual($e.status, 0);
    }
}

func testCheckResponseOkPasses() {
    checkResponse(json.decode('{"ok":true,"result":{}}'), 200);
    testing.assertTrue(true);
}

func testParseMessage() {
    def node as json.Value init json.decode('{"result":{"message_id":42,"chat":{"id":-1001,' +
        '"type":"group"},"date":1700000000,"text":"hello"}}');
    def m as Message init parseMessage($node, "/result");
    testing.assertEqual($m.messageId, 42);
    testing.assertEqual($m.chatId, -1001);
    testing.assertEqual($m.text, "hello");
    testing.assertEqual($m.date, 1700000000);
}

func testParseUser() {
    def node as json.Value init json.decode('{"result":{"id":777,"is_bot":true,' +
        '"first_name":"Botty","username":"botty_bot"}}');
    def u as User init parseUser($node, "/result");
    testing.assertEqual($u.id, 777);
    testing.assertTrue($u.isBot);
    testing.assertEqual($u.firstName, "Botty");
    testing.assertEqual($u.username, "botty_bot");
}

func testParseUpdates() {
    def body as string init '{"ok":true,"result":[' +
        '{"update_id":100,"message":{"message_id":1,"chat":{"id":5},"date":1,"text":"first"}},' +
        '{"update_id":101,"edited_message":{"message_id":2}}]}';
    def us as list of Update init parseUpdates(json.decode($body));
    testing.assertEqual(len($us), 2);
    testing.assertEqual($us[0].updateId, 100);
    testing.assertTrue($us[0].hasMessage);
    testing.assertEqual($us[0].message.text, "first");
    testing.assertEqual($us[1].updateId, 101);
    testing.assertTrue(not $us[1].hasMessage);
}

func testParseUpdatesEmpty() {
    def us as list of Update init parseUpdates(json.decode('{"ok":true,"result":[]}'));
    testing.assertEqual(len($us), 0);
}

func testRenderInlineKeyboard() {
    def rows as list of list of Button init [
        [urlButton("Open", "https://example.org"), inlineButton("Ping", "ping")],
        [inlineButton("Close", "close")]
    ];
    testing.assertEqual(
        renderInlineKeyboard($rows),
        '{"inline_keyboard":[[{"text":"Open","url":"https://example.org"},' +
            '{"text":"Ping","callback_data":"ping"}],' +
            '[{"text":"Close","callback_data":"close"}]]}');
}

func testRenderInlineKeyboardEmpty() {
    def rows as list of list of Button init [];
    testing.assertEqual(renderInlineKeyboard($rows), '{"inline_keyboard":[]}');
}

func testParseCallbackQuery() {
    def body as string init '{"update_id":200,"callback_query":{' +
        "\"id\":\"cbq-99\"," +
        '"from":{"id":42,"is_bot":false,"first_name":"Ada","username":"ada"},' +
        '"message":{"message_id":7,"chat":{"id":5},"date":1,"text":"pick"},' +
        '"data":"ping"}}';
    def cq as CallbackQuery init parseCallbackQuery(json.decode($body));
    testing.assertEqual($cq.id, "cbq-99");
    testing.assertEqual($cq.data, "ping");
    testing.assertEqual($cq.from.id, 42);
    testing.assertEqual($cq.from.username, "ada");
    testing.assertEqual($cq.messageId, 7);
}

func testParseCallbackQueryAbsent() {
    def cq as CallbackQuery init parseCallbackQuery(json.decode('{"update_id":201}'));
    testing.assertEqual($cq.id, "");
    testing.assertEqual($cq.data, "");
    testing.assertEqual($cq.messageId, 0);
}

func testBuildUpload() {
    def data as bytes init encoding.encode("utf-8", "PNGDATA");
    def form as multipart.Built init buildUpload("photo", -1001, "pic.png", "image/png", $data);
    testing.assertTrue(strings.contains($form.contentType, "multipart/form-data; boundary="));
    # Round-trip the built body back through multipart.parse to assert its shape.
    def parts as list of multipart.Part init multipart.parse($form.contentType, $form.body);
    testing.assertEqual(len($parts), 2);
    testing.assertEqual($parts[0].name, "chat_id");
    testing.assertEqual(multipart.text($parts[0]), "-1001");
    testing.assertEqual($parts[1].name, "photo");
    testing.assertEqual($parts[1].filename, "pic.png");
    testing.assertEqual($parts[1].contentType, "image/png");
    testing.assertEqual(multipart.text($parts[1]), "PNGDATA");
}

func testRedactToken() {
    def token as string init "123456:ABC-secretpart";
    def msg as string init "http: POST https://api.telegram.org/bot" + $token +
        "/sendMessage read timed out";
    def red as string init redactToken($msg, $token);
    testing.assertTrue(not strings.contains($red, $token));
    testing.assertTrue(not strings.contains($red, "secretpart"));
    testing.assertTrue(strings.contains($red, "bot<redacted>"));
}

func testGetMe() {
    def srv as httpd.Server init httpd.listen("127.0.0.1:0");
    defer httpd.shutdown($srv);
    def t as task of Seen init spawn {
        return answerOne(
            $srv,
            '{"ok":true,"result":{"id":1,"is_bot":true,"first_name":"Bot","username":"testbot"}}');
    };
    def me as User init getMe(localBot($srv));
    def seen as Seen init task.wait($t);
    testing.assertEqual($seen.method, "POST");
    testing.assertEqual($seen.path, "/bot" + TOKEN + "/getMe");
    testing.assertEqual($me.username, "testbot");
    testing.assertTrue($me.isBot);
}

func testSendMessagePostsTheForm() {
    def srv as httpd.Server init httpd.listen("127.0.0.1:0");
    defer httpd.shutdown($srv);
    def t as task of Seen init spawn {
        return answerOne(
            $srv,
            '{"ok":true,"result":{"message_id":10,"chat":{"id":555},' +
                '"date":1700000000,"text":"hello world"}}');
    };
    def m as Message init sendMessage(localBot($srv), 555, "hello world");
    def seen as Seen init task.wait($t);
    testing.assertEqual($seen.path, "/bot" + TOKEN + "/sendMessage");
    testing.assertEqual($seen.contentType, "application/x-www-form-urlencoded");
    def form as map of string to string init formOf($seen);
    testing.assertEqual($form["chat_id"], "555");
    testing.assertEqual($form["text"], "hello world");
    testing.assertEqual($m.messageId, 10);
    testing.assertEqual($m.chatId, 555);
}

func testSendMessageWithSetsTheParseMode() {
    def srv as httpd.Server init httpd.listen("127.0.0.1:0");
    defer httpd.shutdown($srv);
    def t as task of Seen init spawn {
        return answerOne(
            $srv,
            '{"ok":true,"result":{"message_id":11,"chat":{"id":5},"date":1,"text":"b"}}');
    };
    sendMessageWith(localBot($srv), 5, "*b*", "MarkdownV2");
    def seen as Seen init task.wait($t);
    testing.assertEqual(formOf($seen)["parse_mode"], "MarkdownV2");
}

func testSendMessageWithKeyboardAttachesTheMarkup() {
    def srv as httpd.Server init httpd.listen("127.0.0.1:0");
    defer httpd.shutdown($srv);
    def t as task of Seen init spawn {
        return answerOne(
            $srv,
            '{"ok":true,"result":{"message_id":12,"chat":{"id":5},"date":1,"text":"pick"}}');
    };
    def rows as list of list of Button init [[inlineButton("Ping", "ping")]];
    sendMessageWithKeyboard(localBot($srv), 5, "pick", $rows);
    def seen as Seen init task.wait($t);
    testing.assertEqual(formOf($seen)["reply_markup"], renderInlineKeyboard($rows));
}

func testSendPhotoAndChatAction() {
    def srv as httpd.Server init httpd.listen("127.0.0.1:0");
    defer httpd.shutdown($srv);
    def t as task of Seen init spawn {
        return answerOne($srv, '{"ok":true,"result":{"message_id":13,"chat":{"id":5},"date":1}}');
    };
    sendPhoto(localBot($srv), 5, "https://example.org/a.png", "a cat");
    def seen as Seen init task.wait($t);
    testing.assertEqual(formOf($seen)["photo"], "https://example.org/a.png");
    testing.assertEqual(formOf($seen)["caption"], "a cat");

    def srv2 as httpd.Server init httpd.listen("127.0.0.1:0");
    defer httpd.shutdown($srv2);
    def t2 as task of Seen init spawn {
        return answerOne($srv2, '{"ok":true,"result":true}');
    };
    testing.assertTrue(sendChatAction(localBot($srv2), 5, "typing"));
    def seen2 as Seen init task.wait($t2);
    testing.assertEqual(formOf($seen2)["action"], "typing");
}

func testAnswerCallbackQuery() {
    def srv as httpd.Server init httpd.listen("127.0.0.1:0");
    defer httpd.shutdown($srv);
    def t as task of Seen init spawn {
        return answerOne($srv, '{"ok":true,"result":true}');
    };
    testing.assertTrue(answerCallbackQuery(localBot($srv), "cbq-99", "done"));
    def seen as Seen init task.wait($t);
    testing.assertEqual(formOf($seen)["callback_query_id"], "cbq-99");
    testing.assertEqual(formOf($seen)["text"], "done");
}

func testGetUpdatesParsesTheResult() {
    def srv as httpd.Server init httpd.listen("127.0.0.1:0");
    defer httpd.shutdown($srv);
    def t as task of Seen init spawn {
        return answerOne(
            $srv,
            '{"ok":true,"result":[{"update_id":100,"message":{"message_id":1,' +
                '"chat":{"id":5},"date":1,"text":"ping"}}]}');
    };
    def us as list of Update init getUpdates(localBot($srv), 7, 0);
    def seen as Seen init task.wait($t);
    testing.assertEqual(formOf($seen)["offset"], "7");
    testing.assertEqual(len($us), 1);
    testing.assertEqual($us[0].updateId, 100);
    testing.assertEqual($us[0].message.text, "ping");
}

func testApiErrorThrows() {
    def srv as httpd.Server init httpd.listen("127.0.0.1:0");
    defer httpd.shutdown($srv);
    def t as task of Seen init spawn {
        return answerOne(
            $srv,
            '{"ok":false,"error_code":400,"description":"Bad Request: chat not found"}');
    };
    def threw as bool init false;
    try {
        sendMessage(localBot($srv), 999, "x");
    } catch (e) {
        $threw = true;
        testing.assertEqual($e.kind, "telegram");
        testing.assertContains($e.message, "chat not found");
    }
    task.wait($t);
    testing.assertTrue($threw);
}

func testNonJsonReplyThrows() {
    def srv as httpd.Server init httpd.listen("127.0.0.1:0");
    defer httpd.shutdown($srv);
    def t as task of Seen init spawn {
        return answerOne($srv, "<html>bad gateway</html>");
    };
    def threw as bool init false;
    try {
        getMe(localBot($srv));
    } catch (e) {
        $threw = true;
        testing.assertEqual($e.kind, "telegram");
        testing.assertContains($e.message, "non-JSON");
    }
    task.wait($t);
    testing.assertTrue($threw);
}

# A refused connection is http's net.NetError (kind "net"), passed on with its
# fields readable and no token in its message.
func testARefusedConnectionIsANetError() {
    # Nothing listens once the server is shut down, so the POST fails in http.
    def srv as httpd.Server init httpd.listen("127.0.0.1:0");
    def b as Bot init localBot($srv);
    httpd.shutdown($srv);
    def threw as bool init false;
    try {
        getMe($b);
    } catch (e) {
        $threw = true;
        testing.assertEqual($e.kind, "net");
        testing.assertEqual($e.reason, "refused");
        testing.assertEqual($e.op, "connect");
        testing.assertFalse($e.sent);
        testing.assertTrue(not strings.contains($e.message, "TESTTOKEN"));
    }
    testing.assertTrue($threw);
}

# netFailed keeps a NetError's kind and fields and redacts the token from its
# message, should one ever carry it.
func testANetErrorNeverCarriesTheToken() {
    def srv as httpd.Server init httpd.listen("127.0.0.1:0");
    def addr as string init httpd.address($srv);
    httpd.shutdown($srv);
    try {
        http.get("http://" + $addr + "/bot" + TOKEN + "/getMe", {});
        throw Error{kind: "missed", message: "a refused connection"};
    } catch (e) {
        testing.assertEqual($e.kind, "net");
        try {
            netFailed($e, TOKEN);
            throw Error{kind: "missed", message: "netFailed returned"};
        } catch (f) {
            testing.assertEqual($f.kind, "net");
            testing.assertEqual($f.reason, $e.reason);
            testing.assertEqual($f.op, $e.op);
            testing.assertTrue(not strings.contains($f.message, "TESTTOKEN"));
        }
    }
}

# A reply past json's nesting cap is kind "limit", not a TelegramError.
func testADecodingCapIsALimit() {
    def srv as httpd.Server init httpd.listen("127.0.0.1:0");
    defer httpd.shutdown($srv);
    def t as task of Seen init spawn {
        return answerOne($srv, strings.replicate("[", 1001));
    };
    try {
        getMe(localBot($srv));
        throw Error{kind: "missed", message: "a decoding cap"};
    } catch (e) {
        testing.assertEqual($e.kind, "limit");
    }
    task.wait($t);
}

func testFileUploadsSendMultipart() {
    def dir as string init fs.makeTempDir(os.tempDir(), "telegram-test");
    def file as string init $dir + "/report.txt";
    fs.writeBytes($file, encoding.encode("utf-8", "REPORT"));
    def srv as httpd.Server init httpd.listen("127.0.0.1:0");
    defer httpd.shutdown($srv);
    def t as task of Seen init spawn {
        return answerOne($srv, '{"ok":true,"result":{"message_id":14,"chat":{"id":5},"date":1}}');
    };
    def m as Message init sendDocumentFile(localBot($srv), 5, $file, "text/plain");
    def seen as Seen init task.wait($t);
    testing.assertEqual($seen.path, "/bot" + TOKEN + "/sendDocument");
    def parts as list of multipart.Part init multipart.parse($seen.contentType, $seen.body);
    testing.assertEqual(multipart.text($parts[0]), "5");
    testing.assertEqual($parts[1].name, "document");
    testing.assertEqual($parts[1].filename, "report.txt");
    testing.assertEqual(multipart.text($parts[1]), "REPORT");
    testing.assertEqual($m.messageId, 14);

    def srv2 as httpd.Server init httpd.listen("127.0.0.1:0");
    defer httpd.shutdown($srv2);
    def t2 as task of Seen init spawn {
        return answerOne($srv2, '{"ok":true,"result":{"message_id":15,"chat":{"id":5},"date":1}}');
    };
    sendPhotoFile(localBot($srv2), 5, $file, "");
    def seen2 as Seen init task.wait($t2);
    fs.removeAll($dir);
    testing.assertEqual($seen2.path, "/bot" + TOKEN + "/sendPhoto");
    testing.assertEqual(multipart.parse($seen2.contentType, $seen2.body)[1].name, "photo");
}

func testBotUsesThePublicApi() {
    testing.assertEqual(bot("t").baseUrl, "https://api.telegram.org");
}

func testParseUpdate() {
    def u as Update init parseUpdate(json.decode('{"update_id":300,' +
        '"message":{"message_id":1,"chat":{"id":5},"date":1,"text":"hi"}}'));
    testing.assertEqual($u.updateId, 300);
    testing.assertTrue($u.hasMessage);
    testing.assertEqual($u.message.text, "hi");
    def press as Update init parseUpdate(json.decode('{"update_id":301,' +
        '"callback_query":{"id":"cbq-1","data":"ping"}}'));
    testing.assertEqual($press.updateId, 301);
    testing.assertTrue(not $press.hasMessage);
}

func testGetUpdatesRawKeepsButtonPresses() {
    def srv as httpd.Server init httpd.listen("127.0.0.1:0");
    defer httpd.shutdown($srv);
    def t as task of Seen init spawn {
        return answerOne(
            $srv,
            '{"ok":true,"result":[{"update_id":100,"message":{"message_id":1,' +
                '"chat":{"id":5},"date":1,"text":"ping"}},' +
                '{"update_id":101,"callback_query":{"id":"cbq-7","data":"close",' +
                '"from":{"id":42,"first_name":"Ada"}}}]}');
    };
    def raw as list of json.Value init getUpdatesRaw(localBot($srv), 7, 0);
    def seen as Seen init task.wait($t);
    testing.assertEqual($seen.path, "/bot" + TOKEN + "/getUpdates");
    testing.assertEqual(formOf($seen)["offset"], "7");
    testing.assertEqual(len($raw), 2);
    testing.assertEqual(parseUpdate($raw[0]).message.text, "ping");
    testing.assertEqual(parseUpdate($raw[1]).updateId, 101);
    def cq as CallbackQuery init parseCallbackQuery($raw[1]);
    testing.assertEqual($cq.id, "cbq-7");
    testing.assertEqual($cq.data, "close");
    testing.assertEqual($cq.from.firstName, "Ada");
}

func badUserId() {
    parseUser(json.decode('{"result":{"id":"seven"}}'), "/result");
}

func badMessageText() {
    parseMessage(json.decode('{"result":{"message_id":1,"text":5}}'), "/result");
}

func updateWithoutId() {
    parseUpdate(json.decode('{"message":{"message_id":1}}'));
}

func resultNotAList() {
    parseUpdates(json.decode('{"ok":true,"result":5}'));
}

func okNotABool() {
    checkResponse(json.decode('{"ok":"yes"}'), 200);
}

func resultNotABool() {
    resultBool(json.decode('{"ok":true,"result":"yes"}'));
}

func testMalformedRepliesThrowTelegramErrors() {
    for (def name in [
        "badUserId",
        "badMessageText",
        "updateWithoutId",
        "resultNotAList",
        "okNotABool",
        "resultNotABool"
    ]) {
        testing.assertThrows($name, "telegram");
    }
}

func testCallbackQueryBadSenderIsOneTelegramError() {
    def threw as bool init false;
    try {
        parseCallbackQuery(json.decode('{"callback_query":{"id":"c","from":{"id":"x"}}}'));
    } catch (e) {
        $threw = true;
        testing.assertEqual($e.kind, "telegram");
        testing.assertEqual(len(strings.split($e.message, "telegram:")), 2);
    }
    testing.assertTrue($threw);
}

func testRedactTokenPercentEncoded() {
    def token as string init "123456:ABC-secretpart";
    for (def colon in ["%3A", "%3a"]) {
        def red as string init redactToken(
            "GET /bot123456" + $colon + "ABC-secretpart/getMe",
            $token);
        testing.assertEqual($red, "GET /bot<redacted>/getMe");
    }
}

# cutShort answers one request with half a status line and closes.
func cutShort(listener as net.Listener) {
    def c as net.Conn init net.accept($listener);
    net.readBytes($c, 65536);
    net.writeBytes($c, encoding.encode("utf-8", "HTTP/1.1 200 OK\r\nContent-Le"));
    net.close($c);
}

# stall reads one request and never answers; it returns when the client
# gives up and closes.
func stall(listener as net.Listener) {
    def c as net.Conn init net.accept($listener);
    net.readBytes($c, 65536);
    try {
        net.readBytes($c, 1);
    } catch (e) { # lint-disable: L103
        # the client closed: the stall is over
    }
    net.close($c);
}

# A connection closed mid-answer is kind "closed" and a deadline kind
# "timeout", not a TelegramError; the token stays out of both messages.
func testClosedAndTimeoutKeepTheirKinds() {
    def listener as net.Listener init net.listen("127.0.0.1:0");
    def b as Bot init botWith(TOKEN, "http://" + net.address($listener));
    def cut as task of null init spawn {
        cutShort($listener);
    };
    try {
        call($b, "getMe", {}, 2000);
        throw Error{kind: "missed", message: "a cut answer"};
    } catch (e) {
        testing.assertEqual($e.kind, "closed");
        testing.assertTrue(not strings.contains($e.message, "TESTTOKEN"));
    }
    task.wait($cut);
    def slow as task of null init spawn {
        stall($listener);
    };
    try {
        call($b, "getMe", {}, 300);
        throw Error{kind: "missed", message: "a deadline"};
    } catch (e) {
        testing.assertEqual($e.kind, "timeout");
        testing.assertTrue(not strings.contains($e.message, "TESTTOKEN"));
    }
    task.wait($slow);
    net.close($listener);
}

# transportFailed keeps a generic kind and redacts the token from its message.
func testTransportFailedRedactsAGenericKind() {
    try {
        transportFailed(
            Error{kind: "timeout", message: "GET /bot" + TOKEN + "/getMe timed out"},
            TOKEN);
        throw Error{kind: "missed", message: "transportFailed returned"};
    } catch (e) {
        testing.assertEqual($e.kind, "timeout");
        testing.assertEqual($e.message, "telegram: GET /bot<redacted>/getMe timed out");
    }
}

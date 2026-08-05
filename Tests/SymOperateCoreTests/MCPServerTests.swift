import XCTest
@testable import SymOperateMCP
@testable import SymOperateCore

final class MCPServerTests: XCTestCase {
    private var server: MCPServer!

    override func setUp() {
        super.setUp()
        server = MCPServer()
    }

    func testInitializeReturnsProtocolVersion() async throws {
        let result = try await server.dispatch(method: "initialize", params: ["protocolVersion": "2024-11-05"])
        XCTAssertEqual(result["protocolVersion"] as? String, "2024-11-05")
        let capabilities = result["capabilities"] as? [String: Any]
        XCTAssertNotNil(capabilities?["tools"])
    }

    func testPingReturnsEmptyResult() async throws {
        let result = try await server.dispatch(method: "ping", params: [:])
        XCTAssertEqual(result.count, 0)
    }

    func testToolsListReturnsAllTools() async throws {
        let result = try await server.dispatch(method: "tools/list", params: [:])
        let tools = result["tools"] as? [[String: Any]]
        XCTAssertEqual(tools?.count, 20)
        let names = tools?.compactMap { $0["name"] as? String }
        XCTAssertTrue(names?.contains("snapshot") ?? false)
        XCTAssertTrue(names?.contains("click") ?? false)
        XCTAssertTrue(names?.contains("list_displays") ?? false)
        XCTAssertTrue(names?.contains("wait_for") ?? false)
    }

    func testUnknownMethodThrows() async {
        do {
            _ = try await server.dispatch(method: "invalid/method", params: [:])
            XCTFail("Expected error to be thrown")
        } catch let error as AutomationError {
            let message = error.localizedDescription
            XCTAssertTrue(message.contains("Method not found"))
        } catch {
            XCTFail("Unexpected error type: \(type(of: error))")
        }
    }

    func testQueryUISchemaHasMaxDepthAndMaxNodes() async throws {
        let result = try await server.dispatch(method: "tools/list", params: [:])
        let tools = result["tools"] as? [[String: Any]]
        let queryUI = tools?.first { $0["name"] as? String == "query_ui" }
        XCTAssertNotNil(queryUI)
        let schema = queryUI?["inputSchema"] as? [String: Any]
        let properties = schema?["properties"] as? [String: Any]
        XCTAssertNotNil(properties?["max_depth"])
        XCTAssertNotNil(properties?["max_nodes"])
        XCTAssertEqual(schema?["type"] as? String, "object")
    }

    func testClickSchemaHasCorrectFields() async throws {
        let result = try await server.dispatch(method: "tools/list", params: [:])
        let tools = result["tools"] as? [[String: Any]]
        let click = tools?.first { $0["name"] as? String == "click" }
        let schema = click?["inputSchema"] as? [String: Any]
        let properties = schema?["properties"] as? [String: Any]
        XCTAssertNotNil(properties?["snapshot_id"])
        XCTAssertNotNil(properties?["element_id"])
        XCTAssertNotNil(properties?["x"])
        XCTAssertNotNil(properties?["y"])
        XCTAssertNotNil(properties?["button"])
        XCTAssertNotNil(properties?["double_click"])
        // Verify oneOf constraint for mutually exclusive parameter groups
        let oneOf = schema?["oneOf"] as? [[String: Any]]
        XCTAssertEqual(oneOf?.count, 2)
        let coordRequired = oneOf?[0]["required"] as? [String]
        XCTAssertEqual(coordRequired?.sorted(), ["x", "y"])
        let elemRequired = oneOf?[1]["required"] as? [String]
        XCTAssertEqual(elemRequired?.sorted(), ["element_id", "snapshot_id"])
    }

    func testTypeTextToolRequiresTextArgument() async throws {
        let result = try await server.dispatch(method: "tools/list", params: [:])
        let tools = result["tools"] as? [[String: Any]]
        let typeText = tools?.first { $0["name"] as? String == "type_text" }
        let schema = typeText?["inputSchema"] as? [String: Any]
        let required = schema?["required"] as? [String]
        XCTAssertEqual(required, ["text"])
    }

    func testToolsCallSnapshotReturnsContent() async throws {
        let result = try await server.dispatch(method: "tools/call", params: ["name": "snapshot", "arguments": [:]])
        let content = result["content"] as? [[String: Any]]
        XCTAssertNotNil(content)
        XCTAssertEqual(content?.first?["type"] as? String, "text")
        XCTAssertNotNil(result["structuredContent"])
        XCTAssertEqual(result["isError"] as? Bool, false)
    }

    func testToolsCallWithMissingNameThrows() async {
        do {
            _ = try await server.dispatch(method: "tools/call", params: ["arguments": [:]])
            XCTFail("Expected error to be thrown")
        } catch let error as AutomationError {
            let message = error.localizedDescription
            XCTAssertTrue(message.contains("tool name") || message.contains("requires"))
        } catch {
            XCTFail("Unexpected error type: \(type(of: error))")
        }
    }

    func testToolsCallWithInvalidToolNameThrows() async {
        do {
            _ = try await server.dispatch(method: "tools/call", params: ["name": "nonexistent_tool", "arguments": [:]])
            XCTFail("Expected error to be thrown")
        } catch let error as AutomationError {
            let message = error.localizedDescription
            XCTAssertTrue(message.contains("Unknown tool"))
        } catch {
            XCTFail("Unexpected error type: \(type(of: error))")
        }
    }

    func testListDisplaysReturnsDisplays() async throws {
        let result = try await server.dispatch(method: "tools/call", params: ["name": "list_displays", "arguments": [:]])
        let content = result["content"] as? [[String: Any]]
        XCTAssertNotNil(content)
        let text = content?.first?["text"] as? String ?? ""
        XCTAssertTrue(text.contains("displayID"), "Expected displayID in list_displays output")
    }

    func testListWindowsReturnsWindows() async throws {
        let result = try await server.dispatch(method: "tools/call", params: ["name": "list_windows", "arguments": [:]])
        let content = result["content"] as? [[String: Any]]
        XCTAssertNotNil(content)
        XCTAssertEqual(result["isError"] as? Bool, false)
    }

    func testDragSchemaHasOneOfConstraint() async throws {
        let result = try await server.dispatch(method: "tools/list", params: [:])
        let tools = result["tools"] as? [[String: Any]]
        let drag = tools?.first { $0["name"] as? String == "drag" }
        let schema = drag?["inputSchema"] as? [String: Any]
        let properties = schema?["properties"] as? [String: Any]
        XCTAssertNotNil(properties?["snapshot_id"])
        XCTAssertNotNil(properties?["from_element_id"])
        XCTAssertNotNil(properties?["to_element_id"])
        XCTAssertNotNil(properties?["from_x"])
        XCTAssertNotNil(properties?["from_y"])
        XCTAssertNotNil(properties?["to_x"])
        XCTAssertNotNil(properties?["to_y"])
        let oneOf = schema?["oneOf"] as? [[String: Any]]
        XCTAssertEqual(oneOf?.count, 2)
        let coordRequired = oneOf?[0]["required"] as? [String]
        XCTAssertEqual(coordRequired?.sorted(), ["from_x", "from_y", "to_x", "to_y"])
        let elemRequired = oneOf?[1]["required"] as? [String]
        XCTAssertEqual(elemRequired?.sorted(), ["from_element_id", "snapshot_id", "to_element_id"])
    }

    func testLaunchAppSchemaHasAnyOfConstraint() async throws {
        let result = try await server.dispatch(method: "tools/list", params: [:])
        let tools = result["tools"] as? [[String: Any]]
        let launchApp = tools?.first { $0["name"] as? String == "launch_app" }
        let schema = launchApp?["inputSchema"] as? [String: Any]
        let properties = schema?["properties"] as? [String: Any]
        XCTAssertNotNil(properties?["bundle_id"])
        XCTAssertNotNil(properties?["app_name"])
        let anyOf = schema?["anyOf"] as? [[String: Any]]
        XCTAssertEqual(anyOf?.count, 2)
        let bundleRequired = anyOf?[0]["required"] as? [String]
        XCTAssertEqual(bundleRequired, ["bundle_id"])
        let appRequired = anyOf?[1]["required"] as? [String]
        XCTAssertEqual(appRequired, ["app_name"])
    }

    func testFocusWindowSchemaHasAnyOfConstraint() async throws {
        let result = try await server.dispatch(method: "tools/list", params: [:])
        let tools = result["tools"] as? [[String: Any]]
        let focusWindow = tools?.first { $0["name"] as? String == "focus_window" }
        let schema = focusWindow?["inputSchema"] as? [String: Any]
        let properties = schema?["properties"] as? [String: Any]
        XCTAssertNotNil(properties?["bundle_id"])
        XCTAssertNotNil(properties?["app_name"])
        XCTAssertNotNil(properties?["title"])
        let anyOf = schema?["anyOf"] as? [[String: Any]]
        XCTAssertEqual(anyOf?.count, 2)
        let bundleRequired = anyOf?[0]["required"] as? [String]
        XCTAssertEqual(bundleRequired, ["bundle_id"])
        let appRequired = anyOf?[1]["required"] as? [String]
        XCTAssertEqual(appRequired, ["app_name"])
    }

    func testSnapshotSchemaHasNoRequiredParams() async throws {
        let result = try await server.dispatch(method: "tools/list", params: [:])
        let tools = result["tools"] as? [[String: Any]]
        let snapshot = tools?.first { $0["name"] as? String == "snapshot" }
        let schema = snapshot?["inputSchema"] as? [String: Any]
        let properties = schema?["properties"] as? [String: Any]
        XCTAssertNotNil(properties?["display_id"])
        XCTAssertNotNil(properties?["window_id"])
        let required = schema?["required"] as? [String]
        XCTAssertNil(required, "snapshot should have no required parameters")
        let description = snapshot?["description"] as? String ?? ""
        XCTAssertTrue(description.contains("optional"), "snapshot description should note both parameters are optional")
    }
}
extension MCPServerTests {
    // MARK: - Buffered stdin transport tests (Issue #86)

    /// Writes `data` into a pipe and returns the read end (EOF after the data).
    private func makeReadHandle(_ data: Data) -> FileHandle {
        let pipe = Pipe()
        pipe.fileHandleForWriting.write(data)
        pipe.fileHandleForWriting.closeFile()
        return pipe.fileHandleForReading
    }

    /// A stream of several newline-delimited messages must be parsed one line
    /// per message, with the remainder of each buffered chunk carried over.
    func testReadMessageParsesMultipleNewlineDelimitedMessages() throws {
        var buffer = MCPStreamBuffer()
        let handle = makeReadHandle(Data("""
        {"jsonrpc":"2.0","id":1,"method":"ping"}
        {"jsonrpc":"2.0","id":2,"method":"ping"}
        {"jsonrpc":"2.0","id":3,"method":"ping"}
        """.utf8))
        defer { try? handle.close() }

        XCTAssertEqual(
            try buffer.readMessage(from: handle),
            Data("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}".utf8)
        )
        XCTAssertEqual(
            try buffer.readMessage(from: handle),
            Data("{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"ping\"}".utf8)
        )
        XCTAssertEqual(
            try buffer.readMessage(from: handle),
            Data("{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"ping\"}".utf8)
        )
        XCTAssertNil(try buffer.readMessage(from: handle))
    }

    /// A message larger than one 4096-byte read chunk must be assembled from
    /// multiple chunks, and the next message must start exactly after it.
    func testReadMessageLargerThanReadChunkCarriesOverRemainder() throws {
        var buffer = MCPStreamBuffer()
        let bigPayload = String(repeating: "x", count: MCPStreamBuffer.readChunkSize * 3)
        let big = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\",\"params\":{\"text\":\"\(bigPayload)\"}}"
        let small = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"ping\"}"
        let handle = makeReadHandle(Data((big + "\n" + small + "\n").utf8))
        defer { try? handle.close() }

        XCTAssertGreaterThan(big.utf8.count, MCPStreamBuffer.readChunkSize)
        XCTAssertEqual(try buffer.readMessage(from: handle), Data(big.utf8))
        XCTAssertEqual(try buffer.readMessage(from: handle), Data(small.utf8))
        XCTAssertNil(try buffer.readMessage(from: handle))
    }

    /// A final line without a trailing newline must still be delivered, and a
    /// subsequent read at EOF (with an empty buffer) must return nil.
    func testReadMessageDeliversFinalLineWithoutTrailingNewline() throws {
        var buffer = MCPStreamBuffer()
        let line = "{\"jsonrpc\":\"2.0\",\"id\":9,\"method\":\"ping\"}"
        let handle = makeReadHandle(Data(line.utf8))
        defer { try? handle.close() }

        XCTAssertEqual(try buffer.readMessage(from: handle), Data(line.utf8))
        XCTAssertNil(try buffer.readMessage(from: handle))
    }

    /// Legacy LSP Content-Length framing (header + blank line + body) must
    /// still work through the shared buffer, including a following
    /// newline-delimited message that starts in the same buffered chunk.
    func testReadMessageContentLengthFraming() throws {
        var buffer = MCPStreamBuffer()
        let body = "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"ping\"}"
        let header = "Content-Length: \(body.utf8.count)\r\n\r\n"
        let next = "{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"ping\"}\n"
        let handle = makeReadHandle(Data((header + body + next).utf8))
        defer { try? handle.close() }

        XCTAssertEqual(try buffer.readMessage(from: handle), Data(body.utf8))
        XCTAssertEqual(
            try buffer.readMessage(from: handle),
            Data("{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"ping\"}".utf8)
        )
        XCTAssertNil(try buffer.readMessage(from: handle))
    }

    /// The 50 MB size guard must still reject an oversized NDJSON line.
    func testReadMessageRejectsOversizedNewlineDelimitedLine() throws {
        var buffer = MCPStreamBuffer(maxLineSize: 1024)
        let oversized = String(repeating: "a", count: 2048)
        let handle = makeReadHandle(Data((oversized + "\n").utf8))
        defer { try? handle.close() }

        XCTAssertThrowsError(try buffer.readMessage(from: handle)) { error in
            guard case AutomationError.operationFailed(let message) = error else {
                return XCTFail("Expected operationFailed, got \(error)")
            }
            XCTAssertTrue(
                message.contains("exceeds maximum allowed size"),
                "Guard message missing size hint: \(message)"
            )
        }
        // The production guard is 50 MB; the injected limit above only shrinks it.
        XCTAssertEqual(MCPStreamBuffer.maxMessageSize, 50 * 1024 * 1024)
    }
}

extension MCPServerTests {
    // MARK: - Permission Gate Tests (Issue #85)

    func testSetPolicyGrantedPermissionsRestrictsAndGetPolicyRoundTrips() async throws {
        let setResult = try await server.dispatch(method: "tools/call", params: [
            "name": "set_policy",
            "arguments": ["granted_permissions": ["capture", "input"]],
        ])
        XCTAssertEqual(setResult["isError"] as? Bool, false)

        let getResult = try await server.dispatch(method: "tools/call", params: ["name": "get_policy", "arguments": [:]])
        let policy = getResult["structuredContent"] as? [String: Any]
        XCTAssertEqual(policy?["granted_permissions"] as? [String], ["capture", "input"])
    }

    func testSetPolicyGrantedPermissionsReplacesNotUnions() async throws {
        _ = try await server.dispatch(method: "tools/call", params: [
            "name": "set_policy", "arguments": ["granted_permissions": ["capture", "policy_modify"]],
        ])
        _ = try await server.dispatch(method: "tools/call", params: [
            "name": "set_policy", "arguments": ["granted_permissions": ["input", "policy_modify"]],
        ])
        let getResult = try await server.dispatch(method: "tools/call", params: ["name": "get_policy", "arguments": [:]])
        let policy = getResult["structuredContent"] as? [String: Any]
        // REPLACE semantics: the earlier "capture" must be gone, not unioned in.
        XCTAssertEqual(policy?["granted_permissions"] as? [String], ["input", "policy_modify"])
    }

    func testRestrictedAgentReceivesPermissionDeniedForSnapshot() async throws {
        _ = try await server.dispatch(method: "tools/call", params: [
            "name": "set_policy", "arguments": ["granted_permissions": ["input"]],
        ])
        do {
            _ = try await server.dispatch(method: "tools/call", params: ["name": "snapshot", "arguments": [:]])
            XCTFail("Expected permissionDenied for snapshot without capture permission")
        } catch let error as AutomationError {
            if case .permissionDenied(let message) = error {
                XCTAssertTrue(message.contains("capture"), "Expected message naming 'capture', got: \(message)")
            } else {
                XCTFail("Expected permissionDenied, got \(error)")
            }
        }
    }

    func testSetPolicyRequiresPolicyModifyPermission() async throws {
        _ = try await server.dispatch(method: "tools/call", params: [
            "name": "set_policy", "arguments": ["granted_permissions": ["capture"]],
        ])
        do {
            _ = try await server.dispatch(method: "tools/call", params: [
                "name": "set_policy", "arguments": ["allow_keywords": ["save"]],
            ])
            XCTFail("Expected permissionDenied for set_policy without policy_modify permission")
        } catch let error as AutomationError {
            if case .permissionDenied(let message) = error {
                XCTAssertTrue(message.contains("policy_modify"), "Expected message naming 'policy_modify', got: \(message)")
            } else {
                XCTFail("Expected permissionDenied, got \(error)")
            }
        }
        // The refused mutation must not have changed the policy.
        let getResult = try await server.dispatch(method: "tools/call", params: ["name": "get_policy", "arguments": [:]])
        let policy = getResult["structuredContent"] as? [String: Any]
        XCTAssertEqual(policy?["granted_permissions"] as? [String], ["capture"])
        XCTAssertEqual(policy?["allowedKeywords"] as? [String], [], "Refused allow_keywords must not be applied")
    }

    func testPermissionDeniedRefusalPayloadCarriesStableCode() {
        let message = "Permission denied: the 'capture' permission is required for snapshot."
        let payload = MCPServer.refusalPayload(
            code: AutomationError.permissionDenied(message).code,
            message: message
        )
        XCTAssertEqual(payload["isError"] as? Bool, false)
        let structured = payload["structuredContent"] as? [String: Any]
        XCTAssertEqual(structured?["status"] as? String, "refused")
        let refusal = structured?["refusal"] as? [String: Any]
        XCTAssertEqual(refusal?["code"] as? String, "destructive_control_refused")
        XCTAssertEqual(refusal?["message"] as? String, message)
    }
}

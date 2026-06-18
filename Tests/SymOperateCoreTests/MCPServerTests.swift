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
}

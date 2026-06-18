import XCTest
@testable import SymOperateMCP
@testable import SymOperateCore

final class MCPServerTests: XCTestCase {
    private var server: MCPServer!

    override func setUp() {
        super.setUp()
        server = MCPServer()
    }

    func testInitializeReturnsProtocolVersion() throws {
        let result = try server.dispatch(method: "initialize", params: ["protocolVersion": "2024-11-05"])
        XCTAssertEqual(result["protocolVersion"] as? String, "2024-11-05")
        let capabilities = result["capabilities"] as? [String: Any]
        XCTAssertNotNil(capabilities?["tools"])
    }

    func testPingReturnsEmptyResult() throws {
        let result = try server.dispatch(method: "ping", params: [:])
        XCTAssertEqual(result.count, 0)
    }

    func testToolsListReturnsAllTools() throws {
        let result = try server.dispatch(method: "tools/list", params: [:])
        let tools = result["tools"] as? [[String: Any]]
        XCTAssertEqual(tools?.count, 14)
        let names = tools?.compactMap { $0["name"] as? String }
        XCTAssertTrue(names?.contains("snapshot") ?? false)
        XCTAssertTrue(names?.contains("click") ?? false)
        XCTAssertTrue(names?.contains("wait_for") ?? false)
    }

    func testUnknownMethodThrows() {
        XCTAssertThrowsError(try server.dispatch(method: "invalid/method", params: [:])) { error in
            let message = (error as? AutomationError)?.localizedDescription ?? ""
            XCTAssertTrue(message.contains("Method not found"))
        }
    }

    func testQueryUISchemaHasMaxDepthAndMaxNodes() throws {
        let result = try server.dispatch(method: "tools/list", params: [:])
        let tools = result["tools"] as? [[String: Any]]
        let queryUI = tools?.first { $0["name"] as? String == "query_ui" }
        XCTAssertNotNil(queryUI)
        let schema = queryUI?["inputSchema"] as? [String: Any]
        let properties = schema?["properties"] as? [String: Any]
        XCTAssertNotNil(properties?["max_depth"])
        XCTAssertNotNil(properties?["max_nodes"])
        XCTAssertEqual(schema?["type"] as? String, "object")
    }

    func testClickSchemaHasCorrectFields() throws {
        let result = try server.dispatch(method: "tools/list", params: [:])
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

    func testTypeTextToolRequiresTextArgument() throws {
        let result = try server.dispatch(method: "tools/list", params: [:])
        let tools = result["tools"] as? [[String: Any]]
        let typeText = tools?.first { $0["name"] as? String == "type_text" }
        let schema = typeText?["inputSchema"] as? [String: Any]
        let required = schema?["required"] as? [String]
        XCTAssertEqual(required, ["text"])
    }

    func testToolsCallSnapshotReturnsContent() throws {
        let result = try server.dispatch(method: "tools/call", params: ["name": "snapshot", "arguments": [:]])
        let content = result["content"] as? [[String: Any]]
        XCTAssertNotNil(content)
        XCTAssertEqual(content?.first?["type"] as? String, "text")
        XCTAssertNotNil(result["structuredContent"])
        XCTAssertEqual(result["isError"] as? Bool, false)
    }

    func testToolsCallWithMissingNameThrows() {
        XCTAssertThrowsError(try server.dispatch(method: "tools/call", params: ["arguments": [:]])) { error in
            let message = (error as? AutomationError)?.localizedDescription ?? ""
            XCTAssertTrue(message.contains("tool name") || message.contains("requires"))
        }
    }

    func testToolsCallWithInvalidToolNameThrows() {
        XCTAssertThrowsError(try server.dispatch(method: "tools/call", params: ["name": "nonexistent_tool", "arguments": [:]])) { error in
            let message = (error as? AutomationError)?.localizedDescription ?? ""
            XCTAssertTrue(message.contains("Unknown tool"))
        }
    }
}
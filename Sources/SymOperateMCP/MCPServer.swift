import Foundation
import SymOperateCore

public final class MCPServer {
    private let controller: AutomationController
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    /// Maximum allowed MCP message size (50 MB) to prevent unbounded memory allocation.
    private static let maxMessageSize = 50 * 1024 * 1024

    public init(controller: AutomationController = AutomationController()) {
        self.controller = controller
        encoder.outputFormatting = [.sortedKeys]
    }

    public func run() async throws {
        let stdin = FileHandle.standardInput
        while let message = try readMessage(from: stdin) {
            guard
                let object = try JSONSerialization.jsonObject(with: message) as? [String: Any],
                let method = object["method"] as? String
            else {
                continue
            }

            let id = object["id"]
            let params = object["params"] as? [String: Any] ?? [:]

            do {
                let result = try await dispatch(method: method, params: params)
                try sendResponse(id: id, result: result)
            } catch let error as AutomationError {
                if case .permissionDenied = error {
                    // Deliberate safety refusals are NOT JSON-RPC errors — the call
                    // executed correctly and the outcome is the refusal.
                    try sendRefusal(id: id, code: error.code, message: error.localizedDescription)
                } else {
                    // Genuine faults carry the code in error.data for machine-readable
                    // classification on the error path.
                    try sendError(id: id, code: -32000, message: error.localizedDescription, data: ["code": error.code])
                }
            } catch {
                try sendError(id: id, code: -32000, message: error.localizedDescription)
            }
        }
    }

    public func dispatch(method: String, params: [String: Any]) async throws -> [String: Any] {
        switch method {
        case "initialize":
            return initializeResult(requestedProtocol: params["protocolVersion"] as? String)
        case "notifications/initialized":
            return [:]
        case "ping":
            return [:]
        case "tools/list":
            return ["tools": tools()]
        case "tools/call":
            return try await callTool(params: params)
        default:
            throw AutomationError.invalidArgument("Method not found: \(method)")
        }
    }

    private func initializeResult(requestedProtocol: String?) -> [String: Any] {
        [
            "protocolVersion": requestedProtocol ?? "2024-11-05",
            "capabilities": [
                "tools": [
                    "listChanged": false,
                ],
            ],
            "serverInfo": [
                "name": "symoperate",
                "version": SymOperateVersion.current,
            ],
        ]
    }

    private func tools() -> [[String: Any]] {
        [
            tool("list_apps", description: "List currently running GUI apps on macOS.", input: [:]),
            tool("list_windows", description: "List currently visible windows.", input: [:]),
            tool("list_displays", description: "List all connected displays with bounds and IDs.", input: [:]),
            tool("snapshot", description: "Capture a display or window as PNG plus coordinate transform metadata. Both parameters are optional: omit both for the main display, provide display_id for a specific display, or provide window_id for a specific window. When window_id is provided, display_id is ignored.", input: [
                "type": "object",
                "properties": [
                    "display_id": ["type": "integer", "description": "Display ID to capture. Omit for main display."],
                    "window_id": ["type": "integer", "description": "Window ID to capture. When provided, display_id is ignored."],
                ],
            ]),
            tool("query_ui", description: "Capture a screenshot and accessible UI tree for the frontmost app.", input: [
                "type": "object",
                "properties": [
                    "max_depth": ["type": "integer", "default": 4],
                    "max_nodes": ["type": "integer", "default": 200],
                    "display_id": ["type": "integer", "description": "Display ID to capture. Omit for main display."],
                    "window_id": ["type": "integer", "description": "Window ID to capture. When provided, display_id is ignored."],
                ],
            ]),
            tool("query_ui_ocr", description: "Like query_ui but falls back to Vision OCR when the Accessibility tree is weak. Returns OCR text regions with coordinates.", input: [
                "type": "object",
                "properties": [
                    "max_depth": ["type": "integer", "default": 4],
                    "max_nodes": ["type": "integer", "default": 200],
                    "display_id": ["type": "integer", "description": "Display ID to capture. Omit for main display."],
                    "window_id": ["type": "integer", "description": "Window ID to capture. When provided, display_id is ignored."],
                ],
            ]),
            tool("find_ui", description: "Search the UI tree by role, title, label, value, subrole, or actions. Supports regex patterns (wrap in /slashes/). When snapshot_id is provided and the snapshot is still cached, reuses the existing snapshot instead of taking a fresh one.", input: [
                "type": "object",
                "properties": [
                    "role": ["type": "string"],
                    "title": ["type": "string"],
                    "label": ["type": "string"],
                    "value": ["type": "string"],
                    "subrole": ["type": "string"],
                    "actions": ["type": "array", "items": ["type": "string"]],
                    "snapshot_id": ["type": "string", "description": "Reuse an existing snapshot. If omitted, takes a fresh one."],
                ],
            ]),
            tool("click", description: "Click by x/y coordinates or by snapshot_id + element_id. Requires exactly one of two groups: (x, y) for coordinate-based clicking, or (snapshot_id, element_id) for element-based clicking. Raw coordinates require a prior query_ui snapshot so the target element can be identified and safety-checked; destructive controls and secure text fields are always blocked. Optional: button (default \"left\"), double_click.", input: [
                "type": "object",
                "properties": [
                    "snapshot_id": ["type": "string"],
                    "element_id": ["type": "string"],
                    "x": ["type": "number"],
                    "y": ["type": "number"],
                    "button": ["type": "string", "enum": ["left", "right"]],
                    "double_click": ["type": "boolean"],
                ],
                "oneOf": [
                    ["required": ["x", "y"]],
                    ["required": ["snapshot_id", "element_id"]],
                ],
            ]),
            tool("type_text", description: "Type raw unicode text into the current focused control.", input: [
                "type": "object",
                "properties": ["text": ["type": "string"]],
                "required": ["text"],
            ]),
            tool("press_keys", description: "Press a keyboard shortcut like [\"cmd\", \"s\"] or [\"return\"].", input: [
                "type": "object",
                "properties": ["keys": ["type": "array", "items": ["type": "string"]]],
                "required": ["keys"],
            ]),
            tool("scroll", description: "Scroll by pixel deltas.", input: [
                "type": "object",
                "properties": [
                    "delta_x": ["type": "number", "default": 0],
                    "delta_y": ["type": "number"],
                ],
                "required": ["delta_y"],
            ]),
            tool("drag", description: "Drag from one coordinate or element to another. Requires exactly one of two groups: (from_x, from_y, to_x, to_y) for coordinate-based dragging, or (snapshot_id, from_element_id, to_element_id) for element-based dragging. Raw coordinates require a prior query_ui snapshot so the target element can be identified and safety-checked; destructive controls and secure text fields are always blocked.", input: [
                "type": "object",
                "properties": [
                    "snapshot_id": ["type": "string"],
                    "from_element_id": ["type": "string"],
                    "to_element_id": ["type": "string"],
                    "from_x": ["type": "number"],
                    "from_y": ["type": "number"],
                    "to_x": ["type": "number"],
                    "to_y": ["type": "number"],
                ],
                "oneOf": [
                    ["required": ["from_x", "from_y", "to_x", "to_y"]],
                    ["required": ["snapshot_id", "from_element_id", "to_element_id"]],
                ],
            ]),
            tool("launch_app", description: "Launch an app by bundle_id or app_name. At least one of bundle_id or app_name is required.", input: [
                "type": "object",
                "properties": [
                    "bundle_id": ["type": "string"],
                    "app_name": ["type": "string"],
                ],
                "anyOf": [
                    ["required": ["bundle_id"]],
                    ["required": ["app_name"]],
                ],
            ]),
            tool("focus_window", description: "Activate an app and optionally raise a matching window title. At least one of bundle_id or app_name is required.", input: [
                "type": "object",
                "properties": [
                    "bundle_id": ["type": "string"],
                    "app_name": ["type": "string"],
                    "title": ["type": "string"],
                ],
                "anyOf": [
                    ["required": ["bundle_id"]],
                    ["required": ["app_name"]],
                ],
            ]),
            tool("menu_action", description: "Trigger a frontmost-app menu path like [\"File\", \"Save\"].", input: [
                "type": "object",
                "properties": [
                    "path": ["type": "array", "items": ["type": "string"]],
                ],
                "required": ["path"],
            ]),
            tool("wait_for", description: "Wait until text appears in the frontmost UI or an app becomes available.", input: [
                "type": "object",
                "properties": [
                    "text": ["type": "string"],
                    "app": ["type": "string"],
                    "timeout_seconds": ["type": "number", "default": 10],
                ],
            ]),
            tool("permissions_status", description: "Report screen recording and accessibility permission status.", input: [:]),
            tool("get_policy", description: "Get the current action policy (deny/allow keywords, allowed bundle IDs).", input: [:]),
            tool("set_policy", description: "Update the action policy. Extends defaults; cannot weaken the built-in safety guard.", input: [
                "type": "object",
                "properties": [
                    "extra_deny_keywords": ["type": "array", "items": ["type": "string"], "description": "Additional keywords to block."],
                    "allow_keywords": ["type": "array", "items": ["type": "string"], "description": "Keywords to allow (overrides deny)."],
                    "allow_bundle_ids": ["type": "array", "items": ["type": "string"], "description": "Bundle IDs to exempt from destructive checks."],
                ],
            ]),
            tool("version", description: "Print current version and check for updates from GitHub releases.", input: [:]),
        ]
    }

    private func tool(_ name: String, description: String, input: [String: Any]) -> [String: Any] {
        [
            "name": name,
            "description": description,
            "inputSchema": input.isEmpty ? ["type": "object", "properties": [:]] : input,
        ]
    }

    private func callTool(params: [String: Any]) async throws -> [String: Any] {
        guard let name = params["name"] as? String else {
            throw AutomationError.invalidArgument("tools/call requires a tool name.")
        }
        let arguments = params["arguments"] as? [String: Any] ?? [:]

        let payload: Encodable
        switch name {
        case "snapshot":
            payload = try controller.snapshot(
                displayID: uint32(arguments["display_id"]),
                windowID: intOptional(arguments["window_id"])
            )
        case "list_apps":
            payload = controller.listApps()
        case "list_windows":
            payload = controller.listWindows()
        case "list_displays":
            payload = controller.listDisplays()
        case "query_ui":
            payload = try controller.queryUI(
                maxDepth: int(arguments["max_depth"], default: 4),
                maxNodes: int(arguments["max_nodes"], default: 200),
                displayID: uint32(arguments["display_id"]),
                windowID: intOptional(arguments["window_id"])
            )
        case "query_ui_ocr":
            payload = try controller.queryUIWithOCR(
                maxDepth: int(arguments["max_depth"], default: 4),
                maxNodes: int(arguments["max_nodes"], default: 200),
                displayID: uint32(arguments["display_id"]),
                windowID: intOptional(arguments["window_id"])
            )
        case "click":
            payload = try controller.click(
                snapshotID: string(arguments["snapshot_id"]),
                elementID: string(arguments["element_id"]),
                x: double(arguments["x"]),
                y: double(arguments["y"]),
                button: string(arguments["button"]) ?? "left",
                doubleClick: bool(arguments["double_click"], default: false)
            )
        case "type_text":
            payload = try controller.typeText(requireString(arguments["text"], name: "text"))
        case "press_keys":
            payload = try controller.pressKeys(requireStringArray(arguments["keys"], name: "keys"))
        case "scroll":
            payload = try controller.scroll(
                deltaX: double(arguments["delta_x"]) ?? 0,
                deltaY: requireDouble(arguments["delta_y"], name: "delta_y")
            )
        case "drag":
            payload = try controller.drag(
                snapshotID: string(arguments["snapshot_id"]),
                fromElementID: string(arguments["from_element_id"]),
                toElementID: string(arguments["to_element_id"]),
                fromX: double(arguments["from_x"]),
                fromY: double(arguments["from_y"]),
                toX: double(arguments["to_x"]),
                toY: double(arguments["to_y"])
            )
        case "launch_app":
            payload = try controller.launchApp(
                bundleID: string(arguments["bundle_id"]),
                appName: string(arguments["app_name"])
            )
        case "focus_window":
            payload = try controller.focusWindow(
                bundleID: string(arguments["bundle_id"]),
                appName: string(arguments["app_name"]),
                title: string(arguments["title"])
            )
        case "menu_action":
            payload = try controller.menuAction(path: requireStringArray(arguments["path"], name: "path"))
        case "wait_for":
            payload = try await controller.waitFor(
                text: string(arguments["text"]),
                app: string(arguments["app"]),
                timeoutSeconds: double(arguments["timeout_seconds"]) ?? 10
            )
        case "permissions_status":
            payload = controller.permissionsStatus()
        case "get_policy":
            payload = controller.actionPolicy
        case "set_policy":
            if let extraDeny = arguments["extra_deny_keywords"] as? [String] {
                for kw in extraDeny { controller.actionPolicy.addDenyKeyword(kw) }
            }
            if let allowKw = arguments["allow_keywords"] as? [String] {
                for kw in allowKw { controller.actionPolicy.allowKeyword(kw) }
            }
            if let allowBundle = arguments["allow_bundle_ids"] as? [String] {
                for bid in allowBundle { controller.actionPolicy.allowBundleID(bid) }
            }
            payload = controller.actionPolicy
        case "find_ui":
            let predicate = UIElementPredicate(
                role: string(arguments["role"]),
                title: string(arguments["title"]),
                label: string(arguments["label"]),
                value: string(arguments["value"]),
                subrole: string(arguments["subrole"]),
                actions: arguments["actions"] as? [String]
            )
            payload = try controller.findUI(
                predicate: predicate,
                snapshotID: string(arguments["snapshot_id"]),
                maxDepth: int(arguments["max_depth"], default: 4),
                maxNodes: int(arguments["max_nodes"], default: 200),
                displayID: uint32(arguments["display_id"]),
                windowID: intOptional(arguments["window_id"])
            )
        case "version":
            let checker = UpdateChecker()
            payload = await checker.checkForUpdate()
        default:
            throw AutomationError.notFound("Unknown tool '\(name)'.")
        }

        let structured = try encodeToJSONObject(payload)
        let summary = textSummary(for: name, payload: structured)
        return [
            "content": [
                ["type": "text", "text": summary],
            ],
            "structuredContent": structured,
            "isError": false,
        ]
    }

    private func encodeToJSONObject(_ value: Encodable) throws -> Any {
        let boxed = AnyEncodable(value)
        let data = try encoder.encode(boxed)
        return try JSONSerialization.jsonObject(with: data)
    }

    private func textSummary(for tool: String, payload: Any) -> String {
        guard
            let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
            let text = String(data: data, encoding: .utf8)
        else {
            return "\(tool) completed."
        }
        // For snapshot responses, skip the text field to avoid double base64 serialization
        if tool == "snapshot" || tool == "query_ui" || tool == "query_ui_ocr" || tool == "find_ui" {
            if let dict = payload as? [String: Any],
               dict["imageBase64PNG"] != nil {
                return "\(tool) completed. See structuredContent for full result."
            }
        }
        return text
    }
}

// MARK: - Send helpers

extension MCPServer {
    private func sendResponse(id: Any?, result: [String: Any]) throws {
        var message: [String: Any] = [
            "jsonrpc": "2.0",
            "result": result,
        ]
        if let id { message["id"] = id }
        try send(message)
    }

    private func sendRefusal(id: Any?, code: String, message: String) throws {
        var payload: [String: Any] = [
            "jsonrpc": "2.0",
            "result": [
                "isError": false,
                "content": [
                    ["type": "text", "text": message],
                ],
                "structuredContent": [
                    "status": "refused",
                    "refusal": [
                        "code": code,
                        "message": message,
                    ],
                ],
            ],
        ]
        if let id { payload["id"] = id }
        try send(payload)
    }

    private func sendError(id: Any?, code: Int, message: String, data: [String: Any]? = nil) throws {
        var errorPayload: [String: Any] = [
            "code": code,
            "message": message,
        ]
        if let data { errorPayload["data"] = data }
        var payload: [String: Any] = [
            "jsonrpc": "2.0",
            "error": errorPayload,
        ]
        if let id { payload["id"] = id }
        try send(payload)
    }

    /// Emit a single newline-delimited JSON-RPC frame on stdout.
    private func send(_ payload: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0A])) // newline
    }
}

// MARK: - Read helpers

extension MCPServer {
    /// Read one MCP message from stdin.
    ///
    /// Accepts both standard MCP newline-delimited framing (one JSON object per
    /// line) and legacy LSP Content-Length framing for backward compatibility
    /// with hosts that cannot be reconfigured.
    private func readMessage(from handle: FileHandle) throws -> Data? {
        let data = try readLine(from: handle)
        guard let data else { return nil }
        guard !data.isEmpty else { return nil }

        // Detect Content-Length framing by peeking for the header prefix.
        if data.count >= 15,
           let prefix = String(data: data[0..<15], encoding: .utf8),
           prefix.lowercased().hasPrefix("content-length:") {
            return try readContentLengthMessage(from: handle, headerLine: data)
        }

        // Newline-delimited: the entire line is the JSON message.
        guard data.count <= Self.maxMessageSize else {
            throw AutomationError.operationFailed("MCP message size \(data.count) exceeds maximum allowed size of \(Self.maxMessageSize) bytes.")
        }
        return data
    }

    /// Read one line (until newline) from the file handle.
    private func readLine(from handle: FileHandle) throws -> Data? {
        var data = Data()
        while true {
            guard let chunk = try handle.read(upToCount: 1), !chunk.isEmpty else {
                return data.isEmpty ? nil : data
            }
            if chunk[0] == 0x0A { // newline
                return data
            }
            data.append(chunk)
        }
    }

    /// Parse a Content-Length-framed message and return its body.
    /// The header line has already been read into `headerLine`.
    private func readContentLengthMessage(from handle: FileHandle, headerLine: Data) throws -> Data? {
        guard let headerString = String(data: headerLine, encoding: .utf8) else {
            throw AutomationError.operationFailed("Failed to decode MCP header.")
        }
        let headerTrimmed = headerString.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = headerTrimmed.components(separatedBy: ":")
        guard parts.count >= 2, parts[0].lowercased() == "content-length" else {
            throw AutomationError.operationFailed("Missing Content-Length header.")
        }
        let value = parts[1..<parts.count].joined(separator: ":").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let length = Int(value) else {
            throw AutomationError.operationFailed("Invalid Content-Length header.")
        }
        guard length <= Self.maxMessageSize else {
            throw AutomationError.operationFailed("MCP message size \(length) exceeds maximum allowed size of \(Self.maxMessageSize) bytes.")
        }
        // Consume the blank line after the header
        _ = try? handle.read(upToCount: 2) // \r\n
        return try readBytes(from: handle, count: length)
    }

    private func readBytes(from handle: FileHandle, count: Int) throws -> Data {
        var data = Data()
        while data.count < count {
            let remaining = count - data.count
            guard let chunk = try handle.read(upToCount: remaining), !chunk.isEmpty else {
                throw AutomationError.operationFailed("Unexpected end of input while reading MCP payload.")
            }
            data.append(chunk)
        }
        return data
    }

}

private extension MCPServer {
    func string(_ value: Any?) -> String? { value as? String }

    func double(_ value: Any?) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        return (value as? String).flatMap(Double.init)
    }

    func uint32(_ value: Any?) -> UInt32? {
        if let n = value as? NSNumber { return n.uint32Value }
        return (value as? String).flatMap(UInt32.init)
    }

    func intOptional(_ value: Any?) -> Int? {
        if let n = value as? NSNumber { return n.intValue }
        return (value as? String).flatMap(Int.init)
    }

    func int(_ value: Any?, default defaultValue: Int) -> Int {
        intOptional(value) ?? defaultValue
    }

    func bool(_ value: Any?, default defaultValue: Bool) -> Bool {
        if let b = value as? Bool { return b }
        return (value as? NSNumber)?.boolValue ?? defaultValue
    }

    func requireString(_ value: Any?, name: String) throws -> String {
        guard let string = value as? String, !string.isEmpty else {
            throw AutomationError.invalidArgument("Missing required string argument '\(name)'.")
        }
        return string
    }

    func requireDouble(_ value: Any?, name: String) throws -> Double {
        guard let double = double(value) else {
            throw AutomationError.invalidArgument("Missing required numeric argument '\(name)'.")
        }
        return double
    }

    func requireStringArray(_ value: Any?, name: String) throws -> [String] {
        guard let array = value as? [String], !array.isEmpty else {
            throw AutomationError.invalidArgument("Missing required string array argument '\(name)'.")
        }
        return array
    }
}

private struct AnyEncodable: Encodable {
    private let encodeImpl: (Encoder) throws -> Void

    init(_ wrapped: Encodable) {
        self.encodeImpl = wrapped.encode(to:)
    }

    func encode(to encoder: Encoder) throws {
        try encodeImpl(encoder)
    }
}

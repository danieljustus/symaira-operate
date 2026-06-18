import Foundation
import SymOperateCore
import SymOperateMCP

enum Command: String {
    case serve
    case doctor
    case permissions
}

let controller = AutomationController()

func printUsage() {
    let usage = """
    symoperate

    Commands:
      serve                          Run the MCP server over stdio.
      doctor                         Print permission status and environment checks (JSON).
      permissions status             Print the current macOS permissions.
      permissions grant accessibility  Trigger the Accessibility permission prompt.
      permissions grant screen         Trigger the Screen Recording permission prompt.
    """
    FileHandle.standardOutput.write(Data((usage + "\n").utf8))
}

func printJSON<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
    let data = try encoder.encode(value)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}

func exitCode(for error: AutomationError) -> ExitCode {
    switch error {
    case .permissionDenied: return .permissionDenied
    case .notFound: return .notFound
    case .invalidArgument: return .invalidArgument
    case .operationFailed: return .operationFailed
    case .staleReference: return .staleReference
    case .unavailable: return .unavailable
    }
}

do {
    let args = Array(CommandLine.arguments.dropFirst())
    guard let first = args.first else {
        printUsage()
        exit(ExitCode.ok.rawValue)
    }

    switch first {
    case Command.serve.rawValue:
        try MCPServer(controller: controller).run()
    case Command.doctor.rawValue:
        let permissions = controller.permissionsStatus()
        let apps = controller.listApps()
        let displays = controller.listDisplays()

        let screenshotProbe: ProbeResult
        if permissions.screenRecordingGranted {
            do {
                _ = try controller.snapshot()
                screenshotProbe = ProbeResult(ok: true, message: "Screenshot capture works.")
            } catch let error as AutomationError {
                screenshotProbe = ProbeResult(ok: false, message: error.localizedDescription)
            } catch {
                screenshotProbe = ProbeResult(ok: false, message: error.localizedDescription)
            }
        } else {
            screenshotProbe = ProbeResult(ok: false, message: "Screen Recording permission denied.")
        }

        let accessibilityProbe: ProbeResult
        if permissions.accessibilityGranted {
            do {
                let ax = AccessibilityService()
                _ = try ax.queryFrontmostUI(snapshotID: "doctor-probe", maxDepth: 1, maxNodes: 10)
                accessibilityProbe = ProbeResult(ok: true, message: "Accessibility query works.")
            } catch let error as AutomationError {
                accessibilityProbe = ProbeResult(ok: false, message: error.localizedDescription)
            } catch {
                accessibilityProbe = ProbeResult(ok: false, message: error.localizedDescription)
            }
        } else {
            accessibilityProbe = ProbeResult(ok: false, message: "Accessibility permission denied.")
        }

        let platform = ProcessInfo.processInfo.operatingSystemVersion
        let macOSVersion = "\(platform.majorVersion).\(platform.minorVersion).\(platform.patchVersion)"
        let swiftVer = ProcessInfo.processInfo.environment["SWIFT_VERSION"] ?? "unknown"

        let environment = EnvironmentReport(
            platform: "macOS",
            macOSVersion: macOSVersion,
            swiftVersion: swiftVer,
            appsCount: apps.count,
            displaysCount: displays.count
        )

        let capabilities: [String: Bool] = [
            "screenshot": permissions.screenRecordingGranted,
            "accessibility": permissions.accessibilityGranted,
            "multi_display": displays.count > 1,
            "ocr": true,
        ]

        var recommendations: [String] = []
        if !screenshotProbe.ok { recommendations.append(screenshotProbe.message) }
        if !accessibilityProbe.ok { recommendations.append(accessibilityProbe.message) }
        if recommendations.isEmpty { recommendations.append("Environment ready.") }

        let ok = screenshotProbe.ok && accessibilityProbe.ok
        try printJSON(DoctorReport(
            ok: ok,
            version: "0.1.0",
            permissions: permissions,
            capabilities: capabilities,
            environment: environment,
            recommendations: recommendations
        ))
        exit(ok ? ExitCode.ok.rawValue : ExitCode.permissionDenied.rawValue)
    case Command.permissions.rawValue:
        let rest = Array(args.dropFirst())
        guard let subcommand = rest.first else {
            printUsage()
            exit(ExitCode.invalidArgument.rawValue)
        }

        switch subcommand {
        case "status":
            try printJSON(controller.permissionsStatus())
        case "grant":
            guard let target = rest.dropFirst().first else {
                throw AutomationError.invalidArgument("permissions grant requires 'accessibility' or 'screen'.")
            }
            let success: Bool
            switch target {
            case "accessibility":
                success = controller.requestAccessibilityPermission()
            case "screen":
                success = controller.requestScreenRecordingPermission()
            default:
                throw AutomationError.invalidArgument("Unknown permission target '\(target)'.")
            }
            FileHandle.standardOutput.write(Data("prompt_result=\(success)\n".utf8))
        default:
            throw AutomationError.invalidArgument("Unknown permissions subcommand '\(subcommand)'.")
        }
    default:
        printUsage()
        exit(ExitCode.invalidArgument.rawValue)
    }
} catch let error as AutomationError {
    FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
    exit(exitCode(for: error).rawValue)
} catch {
    FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
    exit(ExitCode.generalError.rawValue)
}

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
      doctor                         Print permission status and environment checks.
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

do {
    let args = Array(CommandLine.arguments.dropFirst())
    guard let first = args.first else {
        printUsage()
        exit(0)
    }

    switch first {
    case Command.serve.rawValue:
        try MCPServer(controller: controller).run()
    case Command.doctor.rawValue:
        struct ProbeResult: Encodable {
            let ok: Bool
            let message: String
        }

        struct DoctorReport: Encodable {
            let permissions: PermissionSnapshot
            let appsCount: Int
            let frontmostApp: AppInfo?
            let screenshotProbe: ProbeResult
            let accessibilityProbe: ProbeResult
            let recommendations: [String]
        }

        let permissions = controller.permissionsStatus()

        let screenshotProbe: ProbeResult
        if permissions.screenRecordingGranted {
            do {
                _ = try controller.snapshot()
                screenshotProbe = ProbeResult(ok: true, message: "Screenshot capture works.")
            } catch let error as AutomationError {
                if case let .permissionDenied(msg) = error {
                    screenshotProbe = ProbeResult(
                        ok: false,
                        message: "Permission denied: \(msg). Enable it in System Settings > Privacy & Security > Screen Recording."
                    )
                } else {
                    screenshotProbe = ProbeResult(ok: false, message: "Screenshot failed: \(error.localizedDescription)")
                }
            } catch {
                screenshotProbe = ProbeResult(ok: false, message: "Screenshot failed: \(error.localizedDescription)")
            }
        } else {
            screenshotProbe = ProbeResult(
                ok: false,
                message: "Screen Recording permission denied. Enable it in System Settings > Privacy & Security > Screen Recording."
            )
        }

        let accessibilityProbe: ProbeResult
        if permissions.accessibilityGranted {
            do {
                let ax = AccessibilityService()
                _ = try ax.queryFrontmostUI(snapshotID: "doctor-probe", maxDepth: 1, maxNodes: 10)
                accessibilityProbe = ProbeResult(ok: true, message: "Accessibility query works.")
            } catch let error as AutomationError {
                if case let .permissionDenied(msg) = error {
                    accessibilityProbe = ProbeResult(
                        ok: false,
                        message: "Accessibility permission denied: \(msg). Enable it in System Settings > Privacy & Security > Accessibility."
                    )
                } else {
                    accessibilityProbe = ProbeResult(ok: false, message: "Accessibility query failed: \(error.localizedDescription)")
                }
            } catch {
                accessibilityProbe = ProbeResult(ok: false, message: "Accessibility query failed: \(error.localizedDescription)")
            }
        } else {
            accessibilityProbe = ProbeResult(
                ok: false,
                message: "Accessibility permission denied. Enable it in System Settings > Privacy & Security > Accessibility."
            )
        }

        var recommendations: [String] = []
        if !screenshotProbe.ok {
            recommendations.append(screenshotProbe.message)
        }
        if !accessibilityProbe.ok {
            recommendations.append(accessibilityProbe.message)
        }
        if recommendations.isEmpty {
            recommendations.append("Environment looks ready for local OpenCode MCP usage.")
        }

        try printJSON(DoctorReport(
            permissions: permissions,
            appsCount: controller.listApps().count,
            frontmostApp: AppService().frontmostApp(),
            screenshotProbe: screenshotProbe,
            accessibilityProbe: accessibilityProbe,
            recommendations: recommendations
        ))
    case Command.permissions.rawValue:
        let rest = Array(args.dropFirst())
        guard let subcommand = rest.first else {
            printUsage()
            exit(1)
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
        exit(1)
    }
} catch {
    FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
    exit(1)
}

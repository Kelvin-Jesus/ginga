import CGVirtualDisplayShim
import Foundation
import ShimFakes
import Testing

/// Maps the private class names onto test doubles.
func fakeResolver(overriding overrides: [String: AnyClass?] = [:]) -> GingaClassResolver {
    var classes: [String: AnyClass?] = [
        "CGVirtualDisplayDescriptor": GingaFakeVirtualDisplayDescriptor.self,
        "CGVirtualDisplayMode": GingaFakeVirtualDisplayMode.self,
        "CGVirtualDisplaySettings": GingaFakeVirtualDisplaySettings.self,
        "CGVirtualDisplay": GingaFakeVirtualDisplay.self,
    ]
    for (name, cls): (String, AnyClass?) in overrides { classes[name] = cls }
    return { name in classes[name] ?? nil }
}

@Suite("PrivateAPIChecker")
struct PrivateAPICheckerTests {
    /// Canary: fails loudly if a macOS update changes the private interface we rely on.
    @Test func privateAPIIsUsableOnThisMac() {
        let report = GingaPrivateAPIChecker.checkRuntime()
        #expect(report.isUsable, "private CGVirtualDisplay problems: \(report.problems)")
        #expect(report.missingOptional.isEmpty, "optional features missing: \(report.missingOptional)")
    }

    @Test func fakesSatisfyEveryRequirement() {
        let report = GingaPrivateAPIChecker.check(classResolver: fakeResolver())
        #expect(report.isUsable, "\(report.problems)")
        #expect(report.checks.allSatisfy { $0.hasPrefix("✓") })
    }

    @Test func missingClassMakesTheAPIUnusable() {
        let report = GingaPrivateAPIChecker.check(classResolver: fakeResolver(overriding: ["CGVirtualDisplay": nil]))
        #expect(!report.isUsable)
        #expect(report.problems == ["class CGVirtualDisplay not found"])
    }

    @Test func missingSelectorIsReported() {
        let report = GingaPrivateAPIChecker.check(classResolver: fakeResolver(overriding: ["CGVirtualDisplay": GingaFakeVirtualDisplayWithoutApply.self]))
        #expect(!report.isUsable)
        #expect(report.problems.contains("missing -[CGVirtualDisplay applySettings:]"))
    }

    @Test func changedSignatureIsReportedAsIncompatible() {
        let report = GingaPrivateAPIChecker.check(classResolver: fakeResolver(overriding: ["CGVirtualDisplayMode": GingaFakeVirtualDisplayModeWrongTypes.self]))
        #expect(!report.isUsable)
        let problem = report.problems.first ?? ""
        #expect(problem.contains("initWithWidth:height:refreshRate:"))
        #expect(problem.contains("expected @@:IId"))
        #expect(problem.contains("found @@:QQd"))
    }

    @Test func legacySelectorNamesAreAcceptedAndOptionalFeaturesAreNotFatal() {
        let report = GingaPrivateAPIChecker.check(classResolver: fakeResolver(overriding: ["CGVirtualDisplayDescriptor": GingaFakeLegacyDescriptor.self]))
        #expect(report.isUsable, "\(report.problems)")
        #expect(report.missingOptional.count == 4)  // red/green/blue primaries + white point
    }

    @Test func normalizesTypeEncodings() {
        #expect(GingaPrivateAPIChecker.normalizedTypeEncoding("B24@0:8@16") == "B@:@")
        #expect(GingaPrivateAPIChecker.normalizedTypeEncoding("v32@0:8{CGSize=dd}16") == "v@:{CGSize=dd}")
        #expect(GingaPrivateAPIChecker.normalizedTypeEncoding("@32@0:8I16I20d24") == "@@:IId")
    }

    @Test func runtimeDumpDescribesThePrivateClasses() {
        let dump = GingaPrivateAPIChecker.runtimeInterfaceDump()
        #expect(dump.contains { $0.hasPrefix("CGVirtualDisplay (") })
        #expect(dump.contains { $0.contains("-applySettings:") })
    }
}

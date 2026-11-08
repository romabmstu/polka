import Foundation
import Security

/// Checks code signatures with the Security framework.
public enum CodeSignature {
    public enum Failure: Error, Equatable {
        /// The bundle's signature is missing, broken or doesn't cover every file.
        case invalid(OSStatus)
        /// Validly signed, but not by the same certificate as the running app.
        case differentSigner
    }

    /// Verifies `app` the way `codesign --verify --deep --strict` does and,
    /// when `requirement` is given, that it satisfies it.
    public static func verify(_ app: URL, requirement: SecRequirement? = nil) throws {
        var code: SecStaticCode?
        let created = SecStaticCodeCreateWithPath(app as CFURL, [], &code)
        guard created == errSecSuccess, let code else { throw Failure.invalid(created) }
        let flags = SecCSFlags(
            rawValue: UInt32(kSecCSCheckAllArchitectures) | UInt32(kSecCSCheckNestedCode) | UInt32(kSecCSStrictValidate))
        let status = SecStaticCodeCheckValidity(code, flags, requirement)
        switch status {
        case errSecSuccess: return
        case errSecCSReqFailed: throw Failure.differentSigner
        default: throw Failure.invalid(status)
        }
    }

    /// What a replacement must satisfy to count as the same app: the running
    /// app's designated requirement (its bundle ID and signing certificate).
    /// `nil` for an ad-hoc signed development build, which has no certificate
    /// to pin; release builds are always signed with the project certificate.
    public static func designatedRequirementOfRunningApp() -> SecRequirement? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: UInt32(kSecCSSigningInformation)), &info) == errSecSuccess,
            let info = info as? [String: Any],
            let certificates = info[kSecCodeInfoCertificates as String] as? [SecCertificate],
            !certificates.isEmpty
        else { return nil }
        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess else { return nil }
        return requirement
    }
}

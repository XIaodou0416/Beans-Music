import Foundation
import Combine

nonisolated enum LoginCredentialKind: String, Codable, Sendable {
    case unknown
    case web
    case appQRCodeTV
    case appSMS
}

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var sessdata: String?
    @Published private(set) var accessKey: String?
    @Published private(set) var loginCredentialKind: LoginCredentialKind
    @Published private(set) var user: NavUserInfo?

    // Kept as the main-account revision for compatibility with existing views.
    @Published private(set) var playbackCredentialVersion = 0
    @Published private(set) var playbackAccountCredentialVersion = 0
    @Published private(set) var dynamicFeedAccountCredentialVersion = 0
    @Published private(set) var interactionAccountCredentialVersion = 0
    @Published private(set) var historyAccountCredentialVersion = 0
    @Published private(set) var accountConfigurationVersion = 0

    @Published private(set) var accounts: [BiliAccountSummary]
    @Published private(set) var mainAccountMID: Int?
    @Published private(set) var playbackAccountMID: Int?
    @Published private(set) var dynamicFeedAccountMID: Int?
    @Published private(set) var interactionAccountMID: Int?
    @Published private(set) var historyAccountPolicy: WatchHistoryAccountPolicy

    private let keychain: KeychainStore
    private let sessdataKey = "SESSDATA"
    private let accessKeyKey = "ACCESS_KEY"
    private let loginCookieHeaderKey = "LOGIN_COOKIE_HEADER"
    private let loginCredentialKindKey = "LOGIN_CREDENTIAL_KIND"
    private let accountRegistryKey = "MULTI_ACCOUNT_REGISTRY_V1"
    private let buvidKey = "buvid3"
    private var loginCookieHeader: String?
    private var credentialsByMID: [Int: StoredBiliAccountCredentials]

    init(keychain: KeychainStore? = nil) {
        let keychain = keychain ?? KeychainStore()
        self.keychain = keychain

        let storedRegistry = Self.loadRegistry(from: keychain, key: accountRegistryKey)
        var loadedCredentials = [Int: StoredBiliAccountCredentials]()
        var loadedAccounts = storedRegistry?.accounts ?? []

        for account in loadedAccounts {
            guard let credentials = Self.loadCredentials(
                for: account.mid,
                from: keychain
            ) else { continue }
            loadedCredentials[account.mid] = credentials
        }
        loadedAccounts.removeAll { loadedCredentials[$0.mid] == nil }

        let legacyHeader = try? keychain.read(loginCookieHeaderKey)
        let legacySESSDATA = (try? keychain.read(sessdataKey))
            ?? Self.cookieValue(named: "SESSDATA", in: legacyHeader)
        let legacyAccessKey = try? keychain.read(accessKeyKey)
        let legacyKind = Self.loadCredentialKind(from: keychain, key: loginCredentialKindKey)
        var didMigrateLegacyAccount = false

        if loadedAccounts.isEmpty,
           let legacySESSDATA,
           !legacySESSDATA.isEmpty,
           let legacyMID = Self.cookieValue(named: "DedeUserID", in: legacyHeader).flatMap(Int.init),
           legacyMID > 0 {
            var values = Self.cookieValues(in: legacyHeader)
            values["SESSDATA"] = legacySESSDATA
            if values["buvid3"]?.isEmpty != false {
                values["buvid3"] = Self.generatedBuvid3()
            }
            let credentials = StoredBiliAccountCredentials(
                cookieHeader: Self.cookieHeader(from: values),
                accessKey: legacyAccessKey,
                credentialKind: legacyKind
            )
            loadedCredentials[legacyMID] = credentials
            loadedAccounts = [
                BiliAccountSummary(
                    mid: legacyMID,
                    name: nil,
                    face: nil,
                    credentialKind: legacyKind
                )
            ]
            didMigrateLegacyAccount = true
        }

        let validMIDs = Set(loadedAccounts.map(\.mid))
        let resolvedMainMID = storedRegistry?.mainAccountMID.flatMap { validMIDs.contains($0) ? $0 : nil }
            ?? loadedAccounts.first?.mid
        let resolvedPlaybackMID = storedRegistry?.playbackAccountMID.flatMap { validMIDs.contains($0) ? $0 : nil }
            ?? resolvedMainMID
        let resolvedDynamicFeedMID = storedRegistry?.dynamicFeedAccountMID.flatMap { validMIDs.contains($0) ? $0 : nil }
            ?? resolvedMainMID
        let resolvedInteractionMID = storedRegistry?.interactionAccountMID.flatMap { validMIDs.contains($0) ? $0 : nil }
            ?? resolvedMainMID
        let resolvedHistoryPolicy = storedRegistry?.historyPolicy ?? .main
        let mainCredentials = resolvedMainMID.flatMap { loadedCredentials[$0] }
        let mainSummary = resolvedMainMID.flatMap { mid in loadedAccounts.first(where: { $0.mid == mid }) }

        self.accounts = loadedAccounts
        self.mainAccountMID = resolvedMainMID
        self.playbackAccountMID = resolvedPlaybackMID
        self.dynamicFeedAccountMID = resolvedDynamicFeedMID
        self.interactionAccountMID = resolvedInteractionMID
        self.historyAccountPolicy = resolvedHistoryPolicy
        self.credentialsByMID = loadedCredentials
        self.loginCookieHeader = mainCredentials?.cookieHeader
        self.sessdata = Self.cookieValue(named: "SESSDATA", in: mainCredentials?.cookieHeader)
        self.accessKey = mainCredentials?.accessKey
        self.loginCredentialKind = mainCredentials?.credentialKind ?? .unknown
        self.user = mainSummary.map(Self.navUserInfo)

        if didMigrateLegacyAccount, let resolvedMainMID, let credentials = loadedCredentials[resolvedMainMID] {
            try? persistAccountCredentials(credentials, for: resolvedMainMID)
            try? persistRegistry()
        } else if storedRegistry != nil,
                  storedRegistry?.mainAccountMID != resolvedMainMID
                    || storedRegistry?.playbackAccountMID != resolvedPlaybackMID
                    || storedRegistry?.dynamicFeedAccountMID != resolvedDynamicFeedMID
                    || storedRegistry?.interactionAccountMID != resolvedInteractionMID
                    || storedRegistry?.accounts != loadedAccounts {
            try? persistRegistry()
        }
    }

    var isLoggedIn: Bool {
        sessdata?.isEmpty == false
    }

    var mainAccount: BiliAccountSummary? {
        accountSummary(mid: mainAccountMID)
    }

    var playbackAccount: BiliAccountSummary? {
        accountSummary(mid: playbackAccountMID ?? mainAccountMID)
    }

    var dynamicFeedAccount: BiliAccountSummary? {
        accountSummary(mid: dynamicFeedAccountMID ?? mainAccountMID)
    }

    var interactionAccount: BiliAccountSummary? {
        accountSummary(mid: interactionAccountMID ?? mainAccountMID)
    }

    func accountSummary(mid: Int?) -> BiliAccountSummary? {
        guard let mid else { return nil }
        return accounts.first(where: { $0.mid == mid })
    }

    func cookieHeader() -> String {
        resolvedCookieHeader(from: loginCookieHeader, fallbackSESSDATA: sessdata)
    }

    func anonymousCookieHeader() -> String {
        let values = Self.cookieValues(in: cookieHeader())
        return "buvid3=\(values["buvid3"] ?? buvid3())"
    }

    func appAccessKey() -> String? {
        Self.nonEmpty(accessKey)
    }

    func recommendCacheIdentityKey(guestModeEnabled: Bool) -> String {
        if guestModeEnabled {
            return "guest-\(buvid3())"
        }
        let credentialSuffix = "login-\(loginCredentialKind.rawValue)"
        if let mid = Self.cookieValue(named: "DedeUserID", in: cookieHeader()) {
            return "mid-\(mid)|\(credentialSuffix)"
        }
        if isLoggedIn {
            return "auth-cookie|\(credentialSuffix)"
        }
        return "anon-\(buvid3())"
    }

    func credentialSnapshot(
        for purpose: BiliAccountPurpose,
        multiAccountEnabled: Bool
    ) -> BiliAccountCredentialSnapshot {
        let resolvedPurpose = multiAccountEnabled ? purpose : .main
        let resolution = accountResolution(for: resolvedPurpose)
        guard resolution.isEnabled,
              let mid = resolution.mid,
              let credentials = credentialsByMID[mid]
        else {
            return disabledCredentialSnapshot(version: resolution.version)
        }
        return credentialSnapshot(
            mid: mid,
            credentials: credentials,
            version: resolution.version,
            isPurposeEnabled: true
        )
    }

    func credentialSnapshot(forAccountMID mid: Int) -> BiliAccountCredentialSnapshot? {
        guard let credentials = credentialsByMID[mid] else { return nil }
        return credentialSnapshot(
            mid: mid,
            credentials: credentials,
            version: accountConfigurationVersion,
            isPurposeEnabled: true
        )
    }

    func accountCacheIdentityKey(
        for purpose: BiliAccountPurpose,
        multiAccountEnabled: Bool
    ) -> String {
        let snapshot = credentialSnapshot(
            for: purpose,
            multiAccountEnabled: multiAccountEnabled
        )
        return [
            purpose.rawValue,
            "mid-\(snapshot.accountMID ?? 0)",
            "credential-\(snapshot.version)",
            "enabled-\(snapshot.isPurposeEnabled)"
        ].joined(separator: "|")
    }

    func csrfToken() -> String? {
        Self.csrfToken(in: cookieHeader())
    }

    func saveBuvid3(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        UserDefaults.standard.set(trimmed, forKey: buvidKey)
    }

    func saveSESSDATA(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try logout()
            return
        }
        guard let mainAccountMID else {
            throw MultiAccountSessionError.missingUserID
        }
        _ = try upsertAccount(
            cookies: [
                "SESSDATA": trimmed,
                "DedeUserID": String(mainAccountMID)
            ],
            credentialKind: loginCredentialKind,
            makeMain: true
        )
    }

    func saveLoginCookies(_ cookies: [HTTPCookie], credentialKind: LoginCredentialKind? = nil) throws {
        let values = cookies.reduce(into: [String: String]()) { result, cookie in
            result[cookie.name] = cookie.value
        }
        try saveLoginCookies(values, credentialKind: credentialKind)
    }

    func saveLoginCookies(_ cookies: [String: String], credentialKind: LoginCredentialKind? = nil) throws {
        _ = try upsertAccount(
            cookies: cookies,
            credentialKind: credentialKind ?? loginCredentialKind,
            makeMain: true
        )
    }

    @discardableResult
    func saveAdditionalAccount(
        _ cookies: [HTTPCookie],
        credentialKind: LoginCredentialKind = .web
    ) throws -> BiliAccountSummary {
        let values = cookies.reduce(into: [String: String]()) { result, cookie in
            result[cookie.name] = cookie.value
        }
        return try upsertAccount(
            cookies: values,
            credentialKind: credentialKind,
            makeMain: accounts.isEmpty
        )
    }

    func updateUser(_ user: NavUserInfo?) {
        guard let mainAccountMID else {
            self.user = user
            return
        }
        updateAccountUser(mid: mainAccountMID, user: user)
    }

    func updateAccountUser(mid: Int, user: NavUserInfo?) {
        guard let index = accounts.firstIndex(where: { $0.mid == mid }) else { return }
        if let user {
            accounts[index].name = user.uname
            accounts[index].face = user.face
        }
        if mainAccountMID == mid {
            self.user = user ?? Self.navUserInfo(from: accounts[index])
        }
        accountConfigurationVersion &+= 1
        try? persistRegistry()
    }

    func selectMainAccount(mid: Int) throws {
        guard credentialsByMID[mid] != nil else {
            throw MultiAccountSessionError.accountNotFound
        }
        guard mainAccountMID != mid else { return }
        mainAccountMID = mid
        if playbackAccountMID == nil {
            playbackAccountMID = mid
            playbackAccountCredentialVersion &+= 1
        }
        if dynamicFeedAccountMID == nil {
            dynamicFeedAccountMID = mid
            dynamicFeedAccountCredentialVersion &+= 1
        }
        if interactionAccountMID == nil {
            interactionAccountMID = mid
            interactionAccountCredentialVersion &+= 1
        }
        syncPublishedMainAccount()
        accountConfigurationVersion &+= 1
        playbackCredentialVersion &+= 1
        historyAccountCredentialVersion &+= 1
        try persistRegistry()
        try mirrorMainCredentialsToLegacyKeys()
    }

    func selectPlaybackAccount(mid: Int) throws {
        guard credentialsByMID[mid] != nil else {
            throw MultiAccountSessionError.accountNotFound
        }
        guard playbackAccountMID != mid else { return }
        playbackAccountMID = mid
        playbackAccountCredentialVersion &+= 1
        historyAccountCredentialVersion &+= 1
        accountConfigurationVersion &+= 1
        try persistRegistry()
    }

    func selectDynamicFeedAccount(mid: Int) throws {
        guard credentialsByMID[mid] != nil else {
            throw MultiAccountSessionError.accountNotFound
        }
        guard dynamicFeedAccountMID != mid else { return }
        dynamicFeedAccountMID = mid
        dynamicFeedAccountCredentialVersion &+= 1
        accountConfigurationVersion &+= 1
        try persistRegistry()
    }

    func selectInteractionAccount(mid: Int) throws {
        guard credentialsByMID[mid] != nil else {
            throw MultiAccountSessionError.accountNotFound
        }
        guard interactionAccountMID != mid else { return }
        interactionAccountMID = mid
        interactionAccountCredentialVersion &+= 1
        accountConfigurationVersion &+= 1
        try persistRegistry()
    }

    func setHistoryAccountPolicy(_ policy: WatchHistoryAccountPolicy) throws {
        guard historyAccountPolicy != policy else { return }
        historyAccountPolicy = policy
        historyAccountCredentialVersion &+= 1
        accountConfigurationVersion &+= 1
        try persistRegistry()
    }

    func removeAccount(mid: Int) throws {
        guard credentialsByMID[mid] != nil else {
            throw MultiAccountSessionError.accountNotFound
        }
        guard mainAccountMID != mid else {
            throw MultiAccountSessionError.cannotRemoveMainAccount
        }
        credentialsByMID[mid] = nil
        accounts.removeAll { $0.mid == mid }
        try deleteAccountCredentials(for: mid)
        if playbackAccountMID == mid {
            playbackAccountMID = mainAccountMID
            playbackAccountCredentialVersion &+= 1
        }
        if dynamicFeedAccountMID == mid {
            dynamicFeedAccountMID = mainAccountMID
            dynamicFeedAccountCredentialVersion &+= 1
        }
        if interactionAccountMID == mid {
            interactionAccountMID = mainAccountMID
            interactionAccountCredentialVersion &+= 1
        }
        historyAccountCredentialVersion &+= 1
        accountConfigurationVersion &+= 1
        try persistRegistry()
    }

    func logout() throws {
        for mid in credentialsByMID.keys {
            try deleteAccountCredentials(for: mid)
        }
        try keychain.delete(accountRegistryKey)
        try keychain.delete(sessdataKey)
        try keychain.delete(accessKeyKey)
        try keychain.delete(loginCookieHeaderKey)
        try keychain.delete(loginCredentialKindKey)
        credentialsByMID = [:]
        accounts = []
        mainAccountMID = nil
        playbackAccountMID = nil
        dynamicFeedAccountMID = nil
        interactionAccountMID = nil
        historyAccountPolicy = .main
        sessdata = nil
        accessKey = nil
        loginCookieHeader = nil
        loginCredentialKind = .unknown
        user = nil
        playbackCredentialVersion &+= 1
        playbackAccountCredentialVersion &+= 1
        dynamicFeedAccountCredentialVersion &+= 1
        interactionAccountCredentialVersion &+= 1
        historyAccountCredentialVersion &+= 1
        accountConfigurationVersion &+= 1
    }

    func buvid3() -> String {
        if let existing = UserDefaults.standard.string(forKey: buvidKey), !existing.isEmpty {
            return existing
        }
        let newValue = Self.generatedBuvid3()
        UserDefaults.standard.set(newValue, forKey: buvidKey)
        return newValue
    }

    private func upsertAccount(
        cookies: [String: String],
        credentialKind: LoginCredentialKind,
        makeMain: Bool
    ) throws -> BiliAccountSummary {
        let incomingMID = Self.nonEmpty(cookies["DedeUserID"]).flatMap(Int.init)
            ?? mainAccountMID
        guard let mid = incomingMID, mid > 0 else {
            throw MultiAccountSessionError.missingUserID
        }
        let existing = credentialsByMID[mid]
        let incomingSESSDATA = Self.nonEmpty(cookies["SESSDATA"])
        let existingSESSDATA = Self.cookieValue(named: "SESSDATA", in: existing?.cookieHeader)
        let replacesSession = incomingSESSDATA.map { $0 != existingSESSDATA } ?? false
        var mergedCookies = Self.cookieValues(in: existing?.cookieHeader)
        if replacesSession {
            Self.accountBoundCookieNames.forEach { mergedCookies[$0] = nil }
        }
        for name in Self.loginCookieNames {
            guard let value = Self.nonEmpty(cookies[name]) else { continue }
            mergedCookies[name] = value
        }
        if let incomingSESSDATA {
            mergedCookies["SESSDATA"] = incomingSESSDATA
        }
        guard Self.nonEmpty(mergedCookies["SESSDATA"]) != nil else {
            throw MultiAccountSessionError.missingSession
        }
        mergedCookies["DedeUserID"] = String(mid)
        if mergedCookies["buvid3"]?.isEmpty != false {
            mergedCookies["buvid3"] = Self.generatedBuvid3()
        }
        let incomingAccessKey = Self.nonEmpty(cookies["access_key"])
        let credentials = StoredBiliAccountCredentials(
            cookieHeader: Self.cookieHeader(from: mergedCookies),
            accessKey: incomingAccessKey ?? (replacesSession ? nil : existing?.accessKey),
            credentialKind: credentialKind
        )
        credentialsByMID[mid] = credentials
        try persistAccountCredentials(credentials, for: mid)

        if let index = accounts.firstIndex(where: { $0.mid == mid }) {
            accounts[index].credentialKind = credentialKind
        } else {
            accounts.append(
                BiliAccountSummary(
                    mid: mid,
                    name: nil,
                    face: nil,
                    credentialKind: credentialKind
                )
            )
        }
        accounts.sort { $0.mid < $1.mid }

        if mainAccountMID == nil || makeMain {
            mainAccountMID = mid
        }
        if playbackAccountMID == nil {
            playbackAccountMID = mainAccountMID
        }
        if dynamicFeedAccountMID == nil {
            dynamicFeedAccountMID = mainAccountMID
        }
        if interactionAccountMID == nil {
            interactionAccountMID = mainAccountMID
        }

        if mainAccountMID == mid {
            syncPublishedMainAccount()
            try mirrorMainCredentialsToLegacyKeys()
            playbackCredentialVersion &+= 1
        }
        if playbackAccountMID == mid {
            playbackAccountCredentialVersion &+= 1
        }
        if dynamicFeedAccountMID == mid {
            dynamicFeedAccountCredentialVersion &+= 1
        }
        if interactionAccountMID == mid {
            interactionAccountCredentialVersion &+= 1
        }
        historyAccountCredentialVersion &+= 1
        accountConfigurationVersion &+= 1
        try persistRegistry()
        return accountSummary(mid: mid)!
    }

    private func accountResolution(
        for purpose: BiliAccountPurpose
    ) -> (mid: Int?, version: Int, isEnabled: Bool) {
        switch purpose {
        case .main:
            return (mainAccountMID, playbackCredentialVersion, true)
        case .playback:
            return (
                validAccountMID(playbackAccountMID) ?? mainAccountMID,
                playbackAccountCredentialVersion,
                true
            )
        case .dynamicFeed:
            return (
                validAccountMID(dynamicFeedAccountMID) ?? mainAccountMID,
                dynamicFeedAccountCredentialVersion,
                true
            )
        case .interaction:
            return (
                validAccountMID(interactionAccountMID) ?? mainAccountMID,
                interactionAccountCredentialVersion,
                true
            )
        case .historyRead:
            let mid = historyAccountPolicy == .playback
                ? validAccountMID(playbackAccountMID) ?? mainAccountMID
                : mainAccountMID
            return (mid, historyAccountCredentialVersion, true)
        case .historyWrite:
            guard historyAccountPolicy != .disabled else {
                return (nil, historyAccountCredentialVersion, false)
            }
            let mid = historyAccountPolicy == .playback
                ? validAccountMID(playbackAccountMID) ?? mainAccountMID
                : mainAccountMID
            return (mid, historyAccountCredentialVersion, true)
        }
    }

    private func validAccountMID(_ mid: Int?) -> Int? {
        guard let mid, credentialsByMID[mid] != nil else { return nil }
        return mid
    }

    private func credentialSnapshot(
        mid: Int,
        credentials: StoredBiliAccountCredentials,
        version: Int,
        isPurposeEnabled: Bool
    ) -> BiliAccountCredentialSnapshot {
        let header = resolvedCookieHeader(
            from: credentials.cookieHeader,
            fallbackSESSDATA: Self.cookieValue(named: "SESSDATA", in: credentials.cookieHeader)
        )
        let buvid = Self.cookieValue(named: "buvid3", in: header) ?? buvid3()
        return BiliAccountCredentialSnapshot(
            accountMID: mid,
            cookieHeader: header,
            anonymousCookieHeader: "buvid3=\(buvid)",
            accessKey: Self.nonEmpty(credentials.accessKey),
            credentialKind: credentials.credentialKind,
            isLoggedIn: Self.cookieValue(named: "SESSDATA", in: header)?.isEmpty == false,
            csrfToken: Self.csrfToken(in: header),
            version: version,
            isPurposeEnabled: isPurposeEnabled
        )
    }

    private func disabledCredentialSnapshot(version: Int) -> BiliAccountCredentialSnapshot {
        BiliAccountCredentialSnapshot(
            accountMID: nil,
            cookieHeader: anonymousCookieHeader(),
            anonymousCookieHeader: anonymousCookieHeader(),
            accessKey: nil,
            credentialKind: .unknown,
            isLoggedIn: false,
            csrfToken: nil,
            version: version,
            isPurposeEnabled: false
        )
    }

    private func resolvedCookieHeader(from header: String?, fallbackSESSDATA: String?) -> String {
        var values = Self.cookieValues(in: header)
        if let fallbackSESSDATA = Self.nonEmpty(fallbackSESSDATA) {
            values["SESSDATA"] = fallbackSESSDATA
        }
        if values["buvid3"]?.isEmpty != false {
            values["buvid3"] = buvid3()
        }
        return Self.cookieHeader(from: values)
    }

    private func syncPublishedMainAccount() {
        guard let mainAccountMID,
              let credentials = credentialsByMID[mainAccountMID]
        else {
            sessdata = nil
            accessKey = nil
            loginCookieHeader = nil
            loginCredentialKind = .unknown
            user = nil
            return
        }
        loginCookieHeader = credentials.cookieHeader
        sessdata = Self.cookieValue(named: "SESSDATA", in: credentials.cookieHeader)
        accessKey = credentials.accessKey
        loginCredentialKind = credentials.credentialKind
        user = accountSummary(mid: mainAccountMID).map(Self.navUserInfo)
    }

    private func persistRegistry() throws {
        let registry = StoredBiliAccountRegistry(
            accounts: accounts,
            mainAccountMID: mainAccountMID,
            playbackAccountMID: playbackAccountMID,
            dynamicFeedAccountMID: dynamicFeedAccountMID,
            interactionAccountMID: interactionAccountMID,
            historyPolicy: historyAccountPolicy
        )
        let data = try JSONEncoder().encode(registry)
        guard let value = String(data: data, encoding: .utf8) else { return }
        try keychain.save(value, for: accountRegistryKey)
    }

    private func persistAccountCredentials(
        _ credentials: StoredBiliAccountCredentials,
        for mid: Int
    ) throws {
        try keychain.save(credentials.cookieHeader, for: Self.accountCookieKey(mid))
        try keychain.save(credentials.credentialKind.rawValue, for: Self.accountCredentialKindKey(mid))
        if let accessKey = Self.nonEmpty(credentials.accessKey) {
            try keychain.save(accessKey, for: Self.accountAccessKeyKey(mid))
        } else {
            try keychain.delete(Self.accountAccessKeyKey(mid))
        }
    }

    private func deleteAccountCredentials(for mid: Int) throws {
        try keychain.delete(Self.accountCookieKey(mid))
        try keychain.delete(Self.accountAccessKeyKey(mid))
        try keychain.delete(Self.accountCredentialKindKey(mid))
    }

    private func mirrorMainCredentialsToLegacyKeys() throws {
        guard let mainAccountMID,
              let credentials = credentialsByMID[mainAccountMID]
        else { return }
        let mainSESSDATA = Self.cookieValue(named: "SESSDATA", in: credentials.cookieHeader) ?? ""
        try keychain.save(mainSESSDATA, for: sessdataKey)
        try keychain.save(credentials.cookieHeader, for: loginCookieHeaderKey)
        try keychain.save(credentials.credentialKind.rawValue, for: loginCredentialKindKey)
        if let accessKey = Self.nonEmpty(credentials.accessKey) {
            try keychain.save(accessKey, for: accessKeyKey)
        } else {
            try keychain.delete(accessKeyKey)
        }
    }

    private static func loadRegistry(
        from keychain: KeychainStore,
        key: String
    ) -> StoredBiliAccountRegistry? {
        guard let raw = try? keychain.read(key),
              let data = raw.data(using: .utf8)
        else { return nil }
        return try? JSONDecoder().decode(StoredBiliAccountRegistry.self, from: data)
    }

    private static func loadCredentials(
        for mid: Int,
        from keychain: KeychainStore
    ) -> StoredBiliAccountCredentials? {
        guard let header = try? keychain.read(accountCookieKey(mid)),
              cookieValue(named: "SESSDATA", in: header)?.isEmpty == false
        else { return nil }
        let accessKey = try? keychain.read(accountAccessKeyKey(mid))
        let kind = loadCredentialKind(from: keychain, key: accountCredentialKindKey(mid))
        return StoredBiliAccountCredentials(
            cookieHeader: header,
            accessKey: accessKey,
            credentialKind: kind
        )
    }

    private static func loadCredentialKind(
        from keychain: KeychainStore,
        key: String
    ) -> LoginCredentialKind {
        guard let raw = try? keychain.read(key),
              let kind = LoginCredentialKind(rawValue: raw)
        else { return .unknown }
        return kind
    }

    private static func accountCookieKey(_ mid: Int) -> String {
        "MULTI_ACCOUNT_\(mid)_COOKIE_HEADER"
    }

    private static func accountAccessKeyKey(_ mid: Int) -> String {
        "MULTI_ACCOUNT_\(mid)_ACCESS_KEY"
    }

    private static func accountCredentialKindKey(_ mid: Int) -> String {
        "MULTI_ACCOUNT_\(mid)_CREDENTIAL_KIND"
    }

    private static func navUserInfo(from summary: BiliAccountSummary) -> NavUserInfo {
        NavUserInfo(
            isLogin: true,
            face: summary.face,
            uname: summary.name,
            mid: summary.mid,
            wbiImg: nil
        )
    }

    private static func generatedBuvid3() -> String {
        UUID().uuidString.lowercased() + "infoc"
    }

    private static func csrfToken(in header: String) -> String? {
        cookieValue(named: "bili_jct", in: header)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    nonisolated private static let loginCookieNames = [
        "buvid3",
        "buvid4",
        "b_nut",
        "buvid_fp",
        "buvid_fp_plain",
        "_uuid",
        "b_lsid",
        "bili_ticket",
        "bili_ticket_expires",
        "DedeUserID",
        "DedeUserID__ckMd5",
        "SESSDATA",
        "bili_jct",
        "sid",
        "CURRENT_FNVAL",
        "CURRENT_QUALITY"
    ]

    nonisolated private static let accountBoundCookieNames: Set<String> = [
        "SESSDATA",
        "DedeUserID",
        "DedeUserID__ckMd5",
        "bili_jct",
        "sid",
        "bili_ticket",
        "bili_ticket_expires"
    ]

    private nonisolated static func cookieValue(named name: String, in header: String?) -> String? {
        cookieValues(in: header)[name]
    }

    private nonisolated static func cookieValues(in header: String?) -> [String: String] {
        guard let header else { return [:] }
        return header
            .split(separator: ";")
            .reduce(into: [String: String]()) { values, item in
                let pair = item.split(separator: "=", maxSplits: 1).map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                guard pair.count == 2, !pair[0].isEmpty, !pair[1].isEmpty else { return }
                values[pair[0]] = pair[1]
            }
    }

    private nonisolated static func cookieHeader(from values: [String: String]) -> String {
        loginCookieNames.compactMap { name in
            guard let value = values[name], !value.isEmpty else { return nil }
            return "\(name)=\(value)"
        }
        .joined(separator: "; ")
    }
}

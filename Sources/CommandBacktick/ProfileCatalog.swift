import AppKit

struct BrowserProfile: Decodable {
    var name: String = ""
    var gaiaGivenName: String?
    var gaiaName: String?
    var enterpriseLabel: String?
    var isUsingDefaultName: Bool?
    var isUsingDefaultAvatar: Bool?
    var useGaiaPicture: Bool?
    var gaiaPictureFileName: String?
    var localName: String { enterpriseLabel.flatMap { $0.isEmpty ? nil : $0 } ?? name }
    var accountName: String { gaiaGivenName.flatMap { $0.isEmpty ? nil : $0 } ?? gaiaName ?? "" }

    func displayName(among profiles: [String: BrowserProfile], directory: String) -> String {
        let account = accountName
        if account.isEmpty { return localName }
        if account.lowercased() == localName.lowercased() { return account }
        let duplicate = profiles.contains { key, other in
            key != directory && other.accountName == account &&
                (other.localName.lowercased() == account.lowercased() || other.isUsingDefaultName == true)
        }
        if isUsingDefaultName != true || !(enterpriseLabel ?? "").isEmpty || duplicate {
            return "\(account) (\(localName))"
        }
        return account
    }
}
struct ProfileRule {
    let name: String
    let imageURL: URL?
}
enum ProfileCatalog {
    static func rules(from profiles: [String: BrowserProfile], root: URL) -> [ProfileRule] {
        profiles.map { directory, profile in
            let file = profile.gaiaPictureFileName ?? ""
            let valid = isLeaf(directory) && isLeaf(file) &&
                (profile.isUsingDefaultAvatar == true || profile.useGaiaPicture == true)
            return ProfileRule(name: profile.displayName(among: profiles, directory: directory),
                imageURL: valid ? root.appendingPathComponent(directory).appendingPathComponent(file) : nil)
        }
    }
    static func isLeaf(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." && !value.contains("/") &&
            !value.contains("\\") && !value.contains("\0")
    }
    static func match(title: String, fullTitle: String, rules: [ProfileRule]) -> ProfileRule? {
        let matches = rules.filter {
            !$0.name.isEmpty && (title == $0.name || fullTitle.hasSuffix(" - Google Chrome - " + $0.name))
        }
        return matches.count == 1 ? matches[0] : nil
    }
    static func attach(to choices: inout [WindowChoice], bundleID: String?) {
        guard bundleID == "com.google.Chrome" else { return }
        struct State: Decodable {
            struct Profiles: Decodable { let infoCache: [String: BrowserProfile] }
            let profile: Profiles
        }
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Google/Chrome", isDirectory: true)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let data = try? Data(contentsOf: root.appendingPathComponent("Local State")),
              let state = try? decoder.decode(State.self, from: data) else { return }
        let rules = rules(from: state.profile.infoCache, root: root)
        var images: [URL: NSImage] = [:]
        for i in choices.indices {
            guard let rule = match(title: choices[i].title, fullTitle: choices[i].fullTitle, rules: rules) else { continue }
            choices[i].profile = rule.name
            if let url = rule.imageURL {
                let image = images[url] ?? NSImage(contentsOf: url)
                if let image { images[url] = image; choices[i].badge = image }
            }
        }
    }
}

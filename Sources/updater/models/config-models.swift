import Foundation

public enum RepoType: String, Codable {
    case script
    case application
    case resource
}

public struct CompileSpec: Codable {
    public let process: String
    public let arguments: [String]
}

public struct RelaunchSpec: Codable {
    public var enable: Bool
    public var target: String? 
    
    public init(
        enable: Bool = false,
        target: String? = nil
    ) {
        self.enable = enable
        self.target = target
    }
}

public struct RepoEntry: Codable {
    public let path: String
    public let type: RepoType?          
    public let compile: CompileSpec?    
    public var relaunch: RelaunchSpec?
}

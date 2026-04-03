import Foundation

// MARK: - UserDefaults Storage Protocols

/// 定义 UserDefaults key 的协议
public protocol UserDefaultsStorageKeys {
    // 由各 store 实现具体的 key
}

/// 提供 UserDefaults 持久化能力的协议
public protocol UserDefaultsStorage: AnyObject {
    associatedtype Keys: UserDefaultsStorageKeys

    /// 是否持久化。init 后不可修改。
    var persisting: Bool { get }

    /// 使用的 UserDefaults 实例
    var storage: UserDefaults { get }

    /// 持久化值到 UserDefaults
    func setValue(_ value: Any?, forKey key: String)
}

// MARK: - Default Implementations

public extension UserDefaultsStorage {
    var persisting: Bool { true }
    var storage: UserDefaults { .standard }

    func setValue(_ value: Any?, forKey key: String) {
        guard persisting else { return }
        storage.set(value, forKey: key)
    }
}

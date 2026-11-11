import Foundation

#if !canImport(Darwin)
/// Keychain status code type; only meaningful on Apple platforms, declared so the shared models build on Linux.
typealias OSStatus = Int32
#endif

import Foundation

// Centralized logging control. In Release builds, standard print/debugPrint become no-ops
// to avoid unexpected I/O and performance overhead. In Debug builds, they delegate to Swift.print.

#if DEBUG
@inlinable
public func print(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    Swift.print(items.map { String(describing: $0) }.joined(separator: separator), terminator: terminator)
}

@inlinable
public func debugPrint(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    Swift.debugPrint(items.map { String(describing: $0) }.joined(separator: separator), terminator: terminator)
}

@inlinable
public func print<Target>(_ items: Any..., to output: inout Target, separator: String = " ", terminator: String = "\n") where Target : TextOutputStream {
    var s = items.map { String(describing: $0) }.joined(separator: separator)
    s += terminator
    Swift.print(s, terminator: "", to: &output)
}
#else
@inlinable
public func print(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    // No-op in Release
}

@inlinable
public func debugPrint(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    // No-op in Release
}

@inlinable
public func print<Target>(_ items: Any..., to output: inout Target, separator: String = " ", terminator: String = "\n") where Target : TextOutputStream {
    // No-op in Release
}
#endif


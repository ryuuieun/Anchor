import Foundation

enum HotKeyRegistrationTransaction {
    static func register<Definition, Ref>(
        _ definitions: [Definition],
        register: (Definition) throws -> Ref,
        unregister: (Ref) -> Void
    ) throws -> [Ref] {
        var refs: [Ref] = []
        do {
            for definition in definitions {
                refs.append(try register(definition))
            }
            return refs
        } catch {
            for ref in refs.reversed() {
                unregister(ref)
            }
            throw error
        }
    }
}

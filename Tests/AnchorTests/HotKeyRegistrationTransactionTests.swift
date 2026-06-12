import XCTest
@testable import Anchor

final class HotKeyRegistrationTransactionTests: XCTestCase {
    func testRollsBackPreviouslyRegisteredRefsWhenRegistrationFails() {
        var registered: [Int] = []
        var unregistered: [Int] = []

        XCTAssertThrowsError(try HotKeyRegistrationTransaction.register(
            [1, 2, 3],
            register: { value in
                if value == 3 {
                    throw MockRegistrationError.failed
                }
                registered.append(value)
                return value
            },
            unregister: { ref in
                unregistered.append(ref)
            }
        ))

        XCTAssertEqual(registered, [1, 2])
        XCTAssertEqual(unregistered, [2, 1])
    }

    func testKeepsRegisteredRefsWhenAllRegistrationsSucceed() throws {
        var unregistered: [Int] = []

        let refs = try HotKeyRegistrationTransaction.register(
            [1, 2],
            register: { $0 * 10 },
            unregister: { ref in
                unregistered.append(ref)
            }
        )

        XCTAssertEqual(refs, [10, 20])
        XCTAssertTrue(unregistered.isEmpty)
    }
}

private enum MockRegistrationError: Error {
    case failed
}

import Foundation

@main
struct TestMain {
    static func main() {
        print("==================================================")
        print("         Running Swift Native Test Suite          ")
        print("==================================================")

        var passed = 0
        var failed = 0
        let totalStart = CFAbsoluteTimeGetCurrent()

        let runTest: (String, () throws -> Void) -> Void = { name, block in
            let start = CFAbsoluteTimeGetCurrent()
            do {
                try block()
                let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000.0
                print(String(format: "  ✔ PASS: %@ (%.2fms)", name, elapsedMs))
                passed += 1
            } catch {
                print("  ❌ FAIL: \(name) - \(error)")
                failed += 1
            }
        }

        print("\n--- [1] Application Configuration & State Suite ---")
        AppTests.run(testRunner: runTest)

        print("\n--- [2] Comprehensive Stress Test Suite ---")
        StressTests.run(testRunner: runTest)

        let totalElapsedMs = (CFAbsoluteTimeGetCurrent() - totalStart) * 1000.0

        print("\n--------------------------------------------------")
        print(String(format: "  Summary: %d Passed | %d Failed (Total: %.2fms)", passed, failed, totalElapsedMs))
        print("==================================================")

        if failed > 0 {
            exit(1)
        }
    }
}

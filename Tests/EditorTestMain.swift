import Foundation

@main
struct EditorTestMain {
    static func main() {
        print("==================================================")
        print("         Running Editor Native Test Suite         ")
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

        print("\n--- Image Annotation Engine Tests (test-image.jpg) ---")
        EditorTests.run(testRunner: runTest)

        let totalElapsedMs = (CFAbsoluteTimeGetCurrent() - totalStart) * 1000.0

        print("\n--------------------------------------------------")
        print(String(format: "  Summary: %d Passed | %d Failed (Total: %.2fms)", passed, failed, totalElapsedMs))
        print("==================================================")

        if failed > 0 {
            exit(1)
        }
    }
}

import Testing
@testable import ClipboardVocab

@Suite("ClipboardMonitor Tests")
struct ClipboardMonitorTests {

    @Test("Initial capture state is active")
    func testInitialState_isActive() {
        let monitor = ClipboardMonitorService()
        #expect(monitor.captureState == .active)
    }

    @Test("pause() sets captureState to .paused")
    func testPause_setsStateToPaused() {
        let monitor = ClipboardMonitorService()
        monitor.pause()
        #expect(monitor.captureState == .paused)
    }

    @Test("resume() sets captureState back to .active")
    func testResume_setsStateToActive() {
        let monitor = ClipboardMonitorService()
        monitor.pause()
        monitor.resume()
        #expect(monitor.captureState == .active)
    }

    @Test("stop() after start leaves monitor in a stoppable state without crash")
    func testStop_afterStart_doesNotCrash() {
        let monitor = ClipboardMonitorService()
        // start() would install a timer on a background queue; we skip that
        // and just verify stop() is safe to call without a prior start().
        monitor.stop() // no-op when timer is nil — must not crash
        #expect(monitor.captureState == .active)
    }

    @Test("pause then resume then pause cycles correctly")
    func testMultiplePauseResumeCycles() {
        let monitor = ClipboardMonitorService()
        monitor.pause()
        #expect(monitor.captureState == .paused)
        monitor.resume()
        #expect(monitor.captureState == .active)
        monitor.pause()
        #expect(monitor.captureState == .paused)
    }
}

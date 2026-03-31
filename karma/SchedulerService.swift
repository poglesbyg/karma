import Foundation
import AppKit

/// Triggers fetches on a 90-minute timer and after system wake.
/// Wake notifications are debounced to avoid fetching twice when the lid bounces.
class SchedulerService {
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var wakeDebounceTask: DispatchWorkItem?

    private var onTrigger: () -> Void
    private let wakeDebounceInterval: TimeInterval

    /// - Parameters:
    ///   - onTrigger: Called when a fetch should be triggered.
    ///   - wakeDebounceInterval: Seconds to wait after wake before triggering (default 30s;
    ///     injectable for tests).
    init(onTrigger: @escaping () -> Void, wakeDebounceInterval: TimeInterval = 30) {
        self.onTrigger = onTrigger
        self.wakeDebounceInterval = wakeDebounceInterval
        startTimer()
        observeWakeNotification()
    }

    // MARK: - Timer

    private func startTimer() {
        timer = Timer.scheduledTimer(
            withTimeInterval: 90 * 60,
            repeats: true
        ) { [weak self] _ in
            self?.triggerFetch()
        }
        timer?.tolerance = 60  // allow OS to batch for power efficiency
    }

    // MARK: - Wake observation

    private func observeWakeNotification() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleWakeNotification()
        }
    }

    func handleWakeNotification() {
        wakeDebounceTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            self?.triggerFetch()
        }
        wakeDebounceTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + wakeDebounceInterval, execute: task)
    }

    // MARK: - Trigger

    func triggerFetch() {
        onTrigger()
    }

    // MARK: - Cleanup

    deinit {
        timer?.invalidate()
        wakeDebounceTask?.cancel()
        if let obs = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
    }
}

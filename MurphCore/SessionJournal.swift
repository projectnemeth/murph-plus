// MurphCore/SessionJournal.swift
import Foundation

/// An append-only log of a session's events, one JSON object per line.
///
/// This is both the Watch's persistence and — in Stage 3 — its sync payload:
/// the same bytes are written to disk and shipped to the phone, so there is no
/// third representation to keep consistent. State is rebuilt by replay, which
/// is what makes crash recovery free.
///
/// Lives in `MurphCore` (Foundation only) so it is unit-testable from the iOS
/// test bundle rather than needing a watchOS test target.
final class SessionJournal {
    let sessionID: UUID
    let url: URL
    private(set) var events: [SessionEvent]

    private static let fileExtension = "journal"

    init(sessionID: UUID, directory: URL) throws {
        self.sessionID = sessionID
        self.url = directory
            .appendingPathComponent(sessionID.uuidString)
            .appendingPathExtension(Self.fileExtension)

        if FileManager.default.fileExists(atPath: url.path) {
            self.events = try Self.decodeLines(at: url)
        } else {
            self.events = []
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true
            )
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
    }

    var state: SessionState { SessionState.replay(events) }

    /// Appends and flushes before returning. A crash costs at most the event
    /// currently being written, never the ones already acknowledged.
    func append(_ event: SessionEvent) throws {
        var line = try JSONEncoder().encode(event)
        line.append(0x0A) // newline

        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
        try handle.synchronize()

        events.append(event)
    }

    func delete() throws {
        try FileManager.default.removeItem(at: url)
        events = []
    }

    static func all(in directory: URL) throws -> [SessionJournal] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )
        return try contents
            .filter { $0.pathExtension == fileExtension }
            .compactMap { UUID(uuidString: $0.deletingPathExtension().lastPathComponent) }
            .map { try SessionJournal(sessionID: $0, directory: directory) }
    }

    /// The unfinished session to offer on launch — the **most recently
    /// started** one, if any.
    ///
    /// "The one unfinished session" was an assumption, not a guarantee. A
    /// journal only becomes terminal when the user finishes or abandons it, and
    /// the launch prompt is the sole way to abandon one — so a user who
    /// dismisses the prompt (or is killed before answering) and starts a fresh
    /// workout leaves two behind. `contentsOfDirectory` returns them in no
    /// defined order, so which one the prompt offered was effectively arbitrary:
    /// "Workout in progress · Resume" could hand back last week's.
    ///
    /// Ordered on the journal's own `startedAt` rather than the file's
    /// modification date. It says the same thing here — appends only ever move
    /// mtime forward — and it cannot be perturbed by a backup, a restore or a
    /// file copy, none of which change what the journal says about itself.
    static func resumable(in directory: URL) throws -> SessionJournal? {
        try all(in: directory)
            .compactMap { journal -> (SessionJournal, Date)? in
                let state = journal.state
                guard !state.isTerminal, let startedAt = state.startedAt else { return nil }
                return (journal, startedAt)
            }
            .max { $0.1 < $1.1 }?
            .0
    }

    private static func decodeLines(at url: URL) throws -> [SessionEvent] {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return data
            .split(separator: 0x0A)
            .compactMap { try? decoder.decode(SessionEvent.self, from: Data($0)) }
    }
}

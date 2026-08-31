// MurphPlus/Prediction/HistoryStats.swift
import Foundation

enum HistoryStats {
    struct Summary {
        let personalBestSeconds: Double?
        let mostRecentSeconds: Double?
        let trendSeconds: Double?
    }

    static func summarize(completedSessions: [MurphSession]) -> Summary {
        let sorted = completedSessions
            .compactMap { session -> (Date, Double)? in
                guard let elapsed = session.totalElapsedSeconds else { return nil }
                return (session.date, elapsed)
            }
            .sorted { $0.0 < $1.0 }

        guard !sorted.isEmpty else {
            return Summary(personalBestSeconds: nil, mostRecentSeconds: nil, trendSeconds: nil)
        }

        let best = sorted.map(\.1).min()
        let mostRecent = sorted.last!.1
        let trend: Double? = sorted.count >= 2 ? mostRecent - sorted[sorted.count - 2].1 : nil

        return Summary(personalBestSeconds: best, mostRecentSeconds: mostRecent, trendSeconds: trend)
    }
}

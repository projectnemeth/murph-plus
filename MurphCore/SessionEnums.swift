// MurphPlus/Models/SessionEnums.swift
enum SessionStatus: String, Codable {
    case inProgress
    case completed
    case abandoned
}

enum SessionPhase: String, Codable {
    case notStarted
    case run1
    case rounds
    case run2
    case completed
}

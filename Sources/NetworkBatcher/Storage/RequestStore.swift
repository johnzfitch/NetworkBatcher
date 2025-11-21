import Foundation
import SQLite3

/// SQLite-backed persistent storage for deferred requests
/// Survives app suspension, termination, and device restart
public actor RequestStore {

    private var db: OpaquePointer?
    private let dbPath: String

    // MARK: - Initialization

    public init(identifier: String = "default") throws {
        let fileManager = FileManager.default
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let batcherDir = appSupport.appendingPathComponent("NetworkBatcher", isDirectory: true)
        try fileManager.createDirectory(at: batcherDir, withIntermediateDirectories: true)

        self.dbPath = batcherDir.appendingPathComponent("\(identifier).sqlite").path

        try openDatabase()
        try createTables()
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - Database Setup

    private func openDatabase() throws {
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let result = sqlite3_open_v2(dbPath, &db, flags, nil)

        guard result == SQLITE_OK else {
            throw StoreError.openFailed(code: result)
        }

        // Enable WAL mode for better concurrent performance
        sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA synchronous=NORMAL;", nil, nil, nil)
    }

    private func createTables() throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS deferred_requests (
            id TEXT PRIMARY KEY,
            url TEXT NOT NULL,
            method TEXT NOT NULL,
            headers TEXT,
            body BLOB,
            priority INTEGER NOT NULL,
            enqueued_at REAL NOT NULL,
            max_deferral_time REAL NOT NULL
        );

        CREATE INDEX IF NOT EXISTS idx_priority ON deferred_requests(priority);
        CREATE INDEX IF NOT EXISTS idx_enqueued_at ON deferred_requests(enqueued_at);

        CREATE TABLE IF NOT EXISTS metrics (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            event_type TEXT NOT NULL,
            timestamp REAL NOT NULL,
            data TEXT
        );

        CREATE TABLE IF NOT EXISTS transmission_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp REAL NOT NULL,
            request_count INTEGER NOT NULL,
            total_bytes INTEGER NOT NULL,
            network_type TEXT,
            is_charging INTEGER,
            trigger_reason TEXT
        );
        """

        let result = sqlite3_exec(db, sql, nil, nil, nil)
        guard result == SQLITE_OK else {
            throw StoreError.queryFailed(code: result)
        }
    }

    // MARK: - Request Operations

    /// Save a deferred request to the store
    public func save(_ request: DeferredRequest) throws {
        let sql = """
        INSERT OR REPLACE INTO deferred_requests
        (id, url, method, headers, body, priority, enqueued_at, max_deferral_time)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?);
        """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepareFailed
        }

        let headersJSON = try? JSONEncoder().encode(request.headers)
        let headersString = headersJSON.flatMap { String(data: $0, encoding: .utf8) }

        sqlite3_bind_text(statement, 1, request.id.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, request.url.absoluteString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 3, request.method, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 4, headersString, -1, SQLITE_TRANSIENT)

        if let body = request.body {
            body.withUnsafeBytes { ptr in
                sqlite3_bind_blob(statement, 5, ptr.baseAddress, Int32(body.count), SQLITE_TRANSIENT)
            }
        } else {
            sqlite3_bind_null(statement, 5)
        }

        sqlite3_bind_int(statement, 6, Int32(request.priority.rawValue))
        sqlite3_bind_double(statement, 7, request.enqueuedAt.timeIntervalSince1970)
        sqlite3_bind_double(statement, 8, request.maxDeferralTime)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw StoreError.insertFailed
        }
    }

    /// Retrieve all pending requests
    public func fetchAll() throws -> [DeferredRequest] {
        let sql = "SELECT * FROM deferred_requests ORDER BY priority ASC, enqueued_at ASC;"

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepareFailed
        }

        var requests: [DeferredRequest] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            if let request = parseRequest(from: statement) {
                requests.append(request)
            }
        }

        return requests
    }

    /// Fetch requests matching a specific priority
    public func fetch(priority: RequestPriority) throws -> [DeferredRequest] {
        let sql = "SELECT * FROM deferred_requests WHERE priority = ? ORDER BY enqueued_at ASC;"

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepareFailed
        }

        sqlite3_bind_int(statement, 1, Int32(priority.rawValue))

        var requests: [DeferredRequest] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            if let request = parseRequest(from: statement) {
                requests.append(request)
            }
        }

        return requests
    }

    /// Fetch up to N requests for batch transmission
    public func fetchBatch(limit: Int) throws -> [DeferredRequest] {
        let sql = """
        SELECT * FROM deferred_requests
        ORDER BY priority ASC, enqueued_at ASC
        LIMIT ?;
        """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepareFailed
        }

        sqlite3_bind_int(statement, 1, Int32(limit))

        var requests: [DeferredRequest] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            if let request = parseRequest(from: statement) {
                requests.append(request)
            }
        }

        return requests
    }

    /// Delete a request by ID
    public func delete(id: UUID) throws {
        let sql = "DELETE FROM deferred_requests WHERE id = ?;"

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepareFailed
        }

        sqlite3_bind_text(statement, 1, id.uuidString, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw StoreError.deleteFailed
        }
    }

    /// Delete multiple requests by ID
    public func delete(ids: [UUID]) throws {
        guard !ids.isEmpty else { return }

        let placeholders = ids.map { _ in "?" }.joined(separator: ",")
        let sql = "DELETE FROM deferred_requests WHERE id IN (\(placeholders));"

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepareFailed
        }

        for (index, id) in ids.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), id.uuidString, -1, SQLITE_TRANSIENT)
        }

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw StoreError.deleteFailed
        }
    }

    /// Delete expired requests
    public func deleteExpired() throws -> Int {
        let sql = """
        DELETE FROM deferred_requests
        WHERE (enqueued_at + max_deferral_time) < ?;
        """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepareFailed
        }

        sqlite3_bind_double(statement, 1, Date().timeIntervalSince1970)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw StoreError.deleteFailed
        }

        return Int(sqlite3_changes(db))
    }

    /// Clear all requests
    public func clear() throws {
        let sql = "DELETE FROM deferred_requests;"

        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw StoreError.deleteFailed
        }
    }

    /// Get count of pending requests
    public func count() throws -> Int {
        let sql = "SELECT COUNT(*) FROM deferred_requests;"

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepareFailed
        }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw StoreError.queryFailed(code: 0)
        }

        return Int(sqlite3_column_int(statement, 0))
    }

    /// Get total size of all queued payloads
    public func totalPayloadSize() throws -> Int {
        let sql = "SELECT COALESCE(SUM(LENGTH(body)), 0) FROM deferred_requests;"

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepareFailed
        }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw StoreError.queryFailed(code: 0)
        }

        return Int(sqlite3_column_int64(statement, 0))
    }

    // MARK: - Metrics

    /// Log a transmission event
    public func logTransmission(
        requestCount: Int,
        totalBytes: Int,
        networkType: String,
        isCharging: Bool,
        triggerReason: String
    ) throws {
        let sql = """
        INSERT INTO transmission_log
        (timestamp, request_count, total_bytes, network_type, is_charging, trigger_reason)
        VALUES (?, ?, ?, ?, ?, ?);
        """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepareFailed
        }

        sqlite3_bind_double(statement, 1, Date().timeIntervalSince1970)
        sqlite3_bind_int(statement, 2, Int32(requestCount))
        sqlite3_bind_int(statement, 3, Int32(totalBytes))
        sqlite3_bind_text(statement, 4, networkType, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(statement, 5, isCharging ? 1 : 0)
        sqlite3_bind_text(statement, 6, triggerReason, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw StoreError.insertFailed
        }
    }

    /// Get transmission statistics
    public func transmissionStats(since: Date) throws -> TransmissionStats {
        let sql = """
        SELECT
            COUNT(*) as batch_count,
            COALESCE(SUM(request_count), 0) as total_requests,
            COALESCE(SUM(total_bytes), 0) as total_bytes
        FROM transmission_log
        WHERE timestamp > ?;
        """

        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw StoreError.prepareFailed
        }

        sqlite3_bind_double(statement, 1, since.timeIntervalSince1970)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return TransmissionStats(batchCount: 0, totalRequests: 0, totalBytes: 0)
        }

        return TransmissionStats(
            batchCount: Int(sqlite3_column_int(statement, 0)),
            totalRequests: Int(sqlite3_column_int(statement, 1)),
            totalBytes: Int(sqlite3_column_int64(statement, 2))
        )
    }

    // MARK: - Helpers

    private func parseRequest(from statement: OpaquePointer?) -> DeferredRequest? {
        guard let statement = statement else { return nil }

        guard let idText = sqlite3_column_text(statement, 0),
              let urlText = sqlite3_column_text(statement, 1),
              let methodText = sqlite3_column_text(statement, 2) else {
            return nil
        }

        let idString = String(cString: idText)
        let urlString = String(cString: urlText)
        let method = String(cString: methodText)

        guard let id = UUID(uuidString: idString),
              let url = URL(string: urlString) else {
            return nil
        }

        var headers: [String: String] = [:]
        if let headersText = sqlite3_column_text(statement, 3) {
            let headersString = String(cString: headersText)
            if let data = headersString.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
                headers = decoded
            }
        }

        var body: Data?
        if let bodyPtr = sqlite3_column_blob(statement, 4) {
            let bodyLength = sqlite3_column_bytes(statement, 4)
            body = Data(bytes: bodyPtr, count: Int(bodyLength))
        }

        let priority = RequestPriority(rawValue: Int(sqlite3_column_int(statement, 5))) ?? .deferrable
        let enqueuedAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 6))
        let maxDeferralTime = sqlite3_column_double(statement, 7)

        return DeferredRequest(
            id: id,
            url: url,
            method: method,
            headers: headers,
            body: body,
            priority: priority,
            enqueuedAt: enqueuedAt,
            maxDeferralTime: maxDeferralTime
        )
    }
}

// MARK: - Supporting Types

public struct TransmissionStats: Sendable {
    public let batchCount: Int
    public let totalRequests: Int
    public let totalBytes: Int

    /// Average requests per batch
    public var averageRequestsPerBatch: Double {
        batchCount > 0 ? Double(totalRequests) / Double(batchCount) : 0
    }

    /// Estimated radio wake-ups saved (compared to individual requests)
    public var estimatedWakeUpsSaved: Int {
        max(0, totalRequests - batchCount)
    }
}

public enum StoreError: Error, LocalizedError {
    case openFailed(code: Int32)
    case queryFailed(code: Int32)
    case prepareFailed
    case insertFailed
    case deleteFailed

    public var errorDescription: String? {
        switch self {
        case .openFailed(let code):
            return "Failed to open database (code: \(code))"
        case .queryFailed(let code):
            return "Query failed (code: \(code))"
        case .prepareFailed:
            return "Failed to prepare statement"
        case .insertFailed:
            return "Failed to insert record"
        case .deleteFailed:
            return "Failed to delete record"
        }
    }
}

// SQLite transient constant
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

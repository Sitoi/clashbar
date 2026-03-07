@MainActor
extension AppState {
    func closeAllConnections() async {
        await self.runConnectionMutation(
            actionName: tr("log.action_name.close_all_connections"),
            endpoint: .closeAllConnections)
    }

    func closeConnection(id: String) async {
        await self.runConnectionMutation(
            actionName: tr("log.action_name.close_connection", id),
            endpoint: .closeConnection(id: id))
    }

    func copyAllLogs() {
        self.flushPendingMihomoLogsIfNeeded()
        let content = errorLogs
            .map(formattedLogEntry)
            .joined(separator: "\n")

        copyTextToPasteboard(content)
        appendLog(level: "info", message: tr("log.logs.copied_all", errorLogs.count))
    }

    private func runConnectionMutation(actionName: String, endpoint: Endpoint) async {
        // DRY: shared post-mutation refresh flow for connection operations.
        await runNoResponseAction(actionName) {
            try await self.clientOrThrow().requestNoResponse(endpoint)
            await self.refreshConnections()
        }
    }
}

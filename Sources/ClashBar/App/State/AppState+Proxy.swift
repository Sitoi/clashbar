@MainActor
extension AppState {
    func switchMode(to target: CoreMode) async {
        if !isModeSwitchEnabled || modeSwitchInFlight || target == currentMode { return }
        modeSwitchInFlight = true
        defer { modeSwitchInFlight = false }

        // Optimistic UI update: keep interaction snappy, polling will reconcile if server differs.
        currentMode = target

        do {
            try await modeSwitchTransport().requestNoResponse(.patchConfigs(body: ["mode": .string(target.rawValue)]))
        } catch {
            // Intentional no-op: mode switch failures stay silent by product decision.
        }
    }

    func toggleSystemProxy(_ enabled: Bool) async {
        isProxySyncing = true
        defer { isProxySyncing = false }

        do {
            if enabled {
                let target = try await resolveSystemProxyTargetFromRuntimeConfig()
                try await applySystemProxy(enabled: true, host: target.host, ports: target.ports)
            } else {
                try await applySystemProxy(enabled: false, host: self.controllerHost(), ports: .disabled)
            }

            // Keep a core-side sync call so proxy toggle and runtime config stay aligned.
            try await clientOrThrow().requestNoResponse(.patchConfigs(body: ["mode": .string(currentMode.rawValue)]))

            isSystemProxyEnabled = enabled
            let state = enabled ? tr("log.system_proxy.enabled") : tr("log.system_proxy.disabled")
            appendLog(level: "info", message: tr("log.system_proxy.toggled", state))
        } catch {
            appendLog(level: "error", message: tr("log.system_proxy.toggle_failed", systemProxyErrorMessage(error)))
            await refreshSystemProxyStatus()
        }
    }

    func copyProxyCommand() {
        let ports = currentSystemProxyPortsFromState()
        let httpPort = ports.httpPort ?? ports.socksPort ?? effectiveMixedPort()
        let socksPort = ports.socksPort ?? ports.httpPort ?? httpPort
        let script = [
            "export https_proxy=http://127.0.0.1:\(httpPort)",
            "http_proxy=http://127.0.0.1:\(httpPort)",
            "all_proxy=socks5://127.0.0.1:\(socksPort)",
        ].joined(separator: " ")
        copyTextToPasteboard(script)
        appendLog(level: "info", message: tr("log.proxy_export.copied"))
    }

    func switchProxy(group: String, target: String) async {
        await runNoResponseAction(tr("log.action_name.switch_proxy", group, target)) {
            try await self.clientOrThrow().requestNoResponse(.switchProxy(name: group, target: target))
            await self.refreshProxyGroups()
        }
    }

    func refreshGroupLatency(_ group: ProxyGroup) async {
        groupLatencyLoading.insert(group.name)
        defer { groupLatencyLoading.remove(group.name) }

        await runRefresh {
            let client = try self.clientOrThrow()
            let response: GroupDelayMeasurement = try await client.request(
                .groupDelay(
                    name: group.name,
                    url: defaultHealthcheckURL,
                    timeout: defaultHealthcheckTimeoutMilliseconds))
            let delays = response.values.filter { $0.value > 0 }

            self.groupLatencies[group.name] = delays
        }
    }

    func refreshAllGroupLatencies() async {
        let groups = proxyGroups
        await withTaskGroup(of: Void.self) { taskGroup in
            for group in groups {
                taskGroup.addTask { [weak self] in
                    await self?.refreshGroupLatency(group)
                }
            }
        }
    }

    func delayText(group: String, node: String) -> String {
        guard let value = delayValue(group: group, node: node) else { return tr("ui.common.unknown") }
        if value == 0 { return tr("ui.common.timeout") }
        return tr("ui.common.latency_ms", value)
    }

    func delayValue(group: String, node: String) -> Int? {
        groupLatencies[group]?[node] ?? proxyHistoryLatestDelay[node]
    }

    func controllerHost() -> String {
        guard let host = controllerHost(from: controller), !host.isEmpty else {
            return "127.0.0.1"
        }
        return host
    }

    func makeControllerUIURL(_ controller: String) -> String {
        "\(normalizedControllerAddress(controller))/ui"
    }
}

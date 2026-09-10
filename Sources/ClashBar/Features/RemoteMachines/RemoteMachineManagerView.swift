import SwiftUI

// swiftlint:disable:next type_name
private typealias T = MenuBarLayoutTokens

private enum EditorMode: Hashable {
    case add
    case edit(RemoteMachine)

    var machine: RemoteMachine? {
        if case let .edit(machine) = self {
            return machine
        }
        return nil
    }
}

private let panelHeight: CGFloat = 500
private let contentPadding: CGFloat = T.space8 * 2
private let headerBottomPadding: CGFloat = T.space6 * 2
private let rowSpacing: CGFloat = T.space8
private let rowContentSpacing: CGFloat = 12
private let rowPadding: CGFloat = 10
private let rowCornerRadius: CGFloat = T.panelCornerRadius
private let rowIconSize: CGFloat = T.rowHeight
private let rowActionSize: CGFloat = 26
private let editorSpacing: CGFloat = 20
private let formSpacing: CGFloat = T.space8 * 2
private let fieldSpacing: CGFloat = T.space6
private let portFieldWidth: CGFloat = 100

struct RemoteMachineManagerView: TranslatingView {
    @EnvironmentObject var appViewModel: AppViewModel
    @ObservedObject var store: RemoteMachineStore
    let localControllerDisplay: String
    var onSwitchTarget: ((MachineTarget) -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var editorMode: EditorMode?
    @State private var isHoveringLocalRow = false

    private var headerTitle: String {
        if let editorMode {
            return editorMode.machine == nil ? self.tr("ui.machine.add") : self.tr("ui.machine.edit")
        }
        return self.tr("ui.machine.manage")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: T.space6) {
                Label(self.headerTitle, systemImage: "network")
                    .font(.app(size: T.FontSize.title3, weight: .semibold))
                    .foregroundStyle(self.nativePrimaryLabel)

                Spacer()

                Button {
                    if self.editorMode != nil {
                        self.editorMode = nil
                    } else {
                        self.dismiss()
                    }
                } label: {
                    Image(systemName: self.editorMode != nil ? "chevron.left.circle.fill" : "xmark.circle.fill")
                        .font(.app(size: T.FontSize.title3, weight: .semibold))
                        .foregroundStyle(self.nativeTertiaryLabel)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(self.editorMode != nil ? self.tr("ui.action.cancel") : self.tr("ui.action.close"))
            }
            .padding([.horizontal, .top], contentPadding)
            .padding(.bottom, headerBottomPadding)

            ZStack(alignment: .topLeading) {
                if let mode = self.editorMode {
                    RemoteMachineEditorView(store: self.store, mode: mode) {
                        self.editorMode = nil
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)))
                } else {
                    self.machineList
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(self.nativeControlFill)
        .frame(width: T.panelWidth, height: panelHeight)
        .animation(
            .spring(response: T.AnimationDuration.standard, dampingFraction: 1),
            value: self.editorMode)
        .onAppear { self.store.startPeriodicConnectivityChecks() }
        .onDisappear { self.store.stopPeriodicConnectivityChecks() }
    }

    private var machineList: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: rowSpacing) {
                    self.localMachineRow

                    ForEach(self.store.machines) { machine in
                        RemoteMachineRowView(
                            machine: machine,
                            store: self.store,
                            onEdit: { self.editorMode = .edit(machine) },
                            editAccessibilityLabel: self.tr("ui.machine.edit"),
                            deleteAccessibilityLabel: self.tr("ui.action.delete"),
                            onSwitchTarget: self.handleTargetSelection,
                            dismiss: self.dismiss)
                    }
                }
                .padding(.horizontal, contentPadding)
                .padding(.bottom, contentPadding)
            }
            .scrollIndicators(.hidden)

            Button {
                self.editorMode = .add
            } label: {
                Label(self.tr("ui.machine.add"), systemImage: "plus")
                    .font(.app(size: T.FontSize.body, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, T.space8)
            }
            .appBorderedButtonStyle(prominent: true)
            .controlSize(.large)
            .padding(.horizontal, contentPadding)
            .padding(.bottom, contentPadding)
        }
    }

    private func handleTargetSelection(_ target: MachineTarget) {
        if let onSwitchTarget {
            onSwitchTarget(target)
        } else {
            Task { @MainActor in
                await self.store.switchToTarget(target)
            }
        }
    }

    private var localMachineRow: some View {
        let isActive = self.store.activeTarget.isLocal

        return Button {
            guard !isActive else { return }
            self.handleTargetSelection(.local)
            self.dismiss()
        } label: {
            HStack(spacing: rowContentSpacing) {
                Image(systemName: "desktopcomputer")
                    .font(.app(size: T.FontSize.body, weight: .semibold))
                    .foregroundStyle(self.nativeAccent.opacity(T.Opacity.solid))
                    .frame(width: rowIconSize)

                VStack(alignment: .leading, spacing: T.space4) {
                    Text(self.tr("ui.machine.local"))
                        .font(.app(size: T.FontSize.body, weight: .semibold))
                        .foregroundStyle(self.nativePrimaryLabel)

                    Text(self.localControllerDisplay)
                        .font(.app(size: T.FontSize.caption, weight: .regular))
                        .foregroundStyle(self.nativeSecondaryLabel)
                }

                Spacer()

                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(self.nativePositive.opacity(T.Opacity.solid))
                }
            }
            .padding(rowPadding)
            .background(
                self.nativeRowFill(active: isActive, hovered: self.isHoveringLocalRow && !isActive),
                in: .rect(cornerRadius: rowCornerRadius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: T.AnimationDuration.quick)) {
                self.isHoveringLocalRow = hovering
            }
        }
    }
}

private struct RemoteMachineRowView: View {
    let machine: RemoteMachine
    @ObservedObject var store: RemoteMachineStore
    let onEdit: () -> Void
    let editAccessibilityLabel: String
    let deleteAccessibilityLabel: String
    let onSwitchTarget: (MachineTarget) -> Void
    let dismiss: DismissAction

    @State private var isHoveringRow = false
    @State private var isHoveringEdit = false
    @State private var isHoveringDelete = false

    var body: some View {
        let status = self.store.statusFor(self.machine.id)
        let isActive = self.store.activeTargetID == self.machine.id
        let isSwitchEnabled = status.isConnected && !isActive

        return HStack(spacing: T.space6) {
            Button {
                guard isSwitchEnabled else { return }
                self.onSwitchTarget(.remote(self.machine))
                self.dismiss()
            } label: {
                HStack(spacing: rowContentSpacing) {
                    Image(systemName: "network")
                        .font(.app(size: T.FontSize.body, weight: .semibold))
                        .foregroundStyle(self.statusTint(status))
                        .frame(width: rowIconSize)

                    VStack(alignment: .leading, spacing: T.space4) {
                        Text(self.machine.name)
                            .font(.app(size: T.FontSize.body, weight: .semibold))
                            .foregroundStyle(self.nativePrimaryLabel)

                        HStack(spacing: T.space4) {
                            self.statusDot(status)

                            Text(self.machine.displayAddress)
                                .font(.app(size: T.FontSize.caption, weight: .regular))
                                .foregroundStyle(self.nativeSecondaryLabel)
                        }
                    }

                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!isSwitchEnabled)

            HStack(spacing: T.space6) {
                if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(self.nativePositive.opacity(T.Opacity.solid))
                }

                self.rowActionButton(
                    symbol: "pencil",
                    accessibilityLabel: self.editAccessibilityLabel,
                    hovered: self.isHoveringEdit,
                    destructive: false)
                {
                    self.onEdit()
                }
                .onHover { self.isHoveringEdit = $0 }

                self.rowActionButton(
                    symbol: "trash",
                    accessibilityLabel: self.deleteAccessibilityLabel,
                    hovered: self.isHoveringDelete,
                    destructive: true)
                {
                    self.store.removeMachine(id: self.machine.id)
                }
                .onHover { self.isHoveringDelete = $0 }
            }
        }
        .padding(rowPadding)
        .background(
            self.nativeRowFill(active: isActive, hovered: self.isHoveringRow && !isActive),
            in: .rect(cornerRadius: rowCornerRadius))
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: T.AnimationDuration.quick)) {
                self.isHoveringRow = hovering
            }
        }
    }

    private func rowActionButton(
        symbol: String,
        accessibilityLabel: String,
        hovered: Bool,
        destructive: Bool,
        action: @escaping () -> Void) -> some View
    {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(
                    width: rowActionSize,
                    height: rowActionSize)
                .background(
                    self.nativeActionBackground(hovered: hovered, destructive: destructive),
                    in: .rect(cornerRadius: T.cornerRadius))
        }
        .buttonStyle(.borderless)
        .foregroundStyle(self.nativeActionForeground(hovered: hovered, destructive: destructive))
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private func statusDot(_ status: MachineConnectionStatus) -> some View {
        if case .checking = status {
            ProgressView()
                .controlSize(.mini)
        } else {
            Circle()
                .fill(self.statusTint(status))
                .frame(width: T.space6, height: T.space6)
        }
    }

    private func statusTint(_ status: MachineConnectionStatus) -> Color {
        switch status {
        case .unknown:
            self.nativeSecondaryLabel
        case .checking:
            self.nativeWarning.opacity(T.Opacity.solid)
        case .connected:
            self.nativePositive.opacity(T.Opacity.solid)
        case .failed:
            self.nativeCritical.opacity(T.Opacity.solid)
        }
    }
}

private struct RemoteMachineEditorView: TranslatingView {
    @EnvironmentObject var appViewModel: AppViewModel
    @ObservedObject var store: RemoteMachineStore
    let mode: EditorMode
    let onComplete: () -> Void

    @State private var name: String = ""
    @State private var host: String = ""
    @State private var port: String = "9090"
    @State private var secret: String = ""
    @State private var useHTTPS = false

    @FocusState private var isNameFocused: Bool

    private var isFormValid: Bool {
        !self.name.trimmingCharacters(in: .whitespaces).isEmpty &&
            !self.host.trimmingCharacters(in: .whitespaces).isEmpty &&
            (Int(self.port) ?? 0) > 0 && (Int(self.port) ?? 0) <= 65535
    }

    var body: some View {
        VStack(alignment: .leading, spacing: editorSpacing) {
            VStack(alignment: .leading, spacing: T.space4) {
                Text(self.name.trimmingCharacters(in: .whitespaces).isEmpty ? self.tr("ui.machine.field.name") : self
                    .name)
                    .font(.app(size: T.FontSize.body, weight: .semibold))
                    .foregroundStyle(self.nativePrimaryLabel)

                Text(self.connectionPreview)
                    .font(.app(size: T.FontSize.caption, weight: .regular))
                    .foregroundStyle(self.nativeSecondaryLabel)
            }
            .padding(.bottom, T.space8)

            VStack(alignment: .leading, spacing: formSpacing) {
                self.nameField

                HStack(spacing: formSpacing) {
                    self.inputField(title: self.tr("ui.machine.field.host"), text: self.$host, isSecure: false)

                    self.inputField(title: self.tr("ui.machine.field.port"), text: self.$port, isSecure: false)
                        .frame(maxWidth: portFieldWidth)
                }

                self.inputField(title: self.tr("ui.machine.field.secret"), text: self.$secret, isSecure: true)

                HStack {
                    Text("HTTPS")
                        .font(.app(size: T.FontSize.body, weight: .medium))
                        .foregroundStyle(self.nativeSecondaryLabel)

                    Spacer()

                    Toggle("", isOn: self.$useHTTPS)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.regular)
                }
            }

            Spacer()

            Button(action: self.save) {
                Text(self.tr("ui.machine.save"))
                    .font(.app(size: T.FontSize.body, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, T.space8)
            }
            .appBorderedButtonStyle(prominent: true)
            .controlSize(.large)
            .disabled(!self.isFormValid)
        }
        .padding(.horizontal, contentPadding)
        .padding(.bottom, contentPadding)
        .onAppear {
            if let machine = self.mode.machine {
                self.name = machine.name
                self.host = machine.host
                self.port = "\(machine.port)"
                self.secret = machine.secret ?? ""
                self.useHTTPS = machine.useHTTPS
            } else {
                self.isNameFocused = true
            }
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: fieldSpacing) {
            Text(self.tr("ui.machine.field.name"))
                .font(.app(size: T.FontSize.body, weight: .medium))
                .foregroundStyle(self.nativeSecondaryLabel)

            TextField("", text: self.$name)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .font(.app(size: T.FontSize.body, weight: .regular))
                .focused(self.$isNameFocused)
        }
    }

    private func inputField(title: String, text: Binding<String>, isSecure: Bool) -> some View {
        VStack(alignment: .leading, spacing: fieldSpacing) {
            Text(title)
                .font(.app(size: T.FontSize.body, weight: .medium))
                .foregroundStyle(self.nativeSecondaryLabel)

            Group {
                if isSecure {
                    SecureField("", text: text)
                } else {
                    TextField("", text: text)
                }
            }
            .textFieldStyle(.roundedBorder)
            .controlSize(.large)
            .font(.app(size: T.FontSize.body, weight: .regular))
        }
    }

    private var connectionPreview: String {
        let resolvedHost = self.host.trimmingCharacters(in: .whitespaces).isEmpty ? "controller.example.com" : self.host
        let resolvedPort = self.port.trimmingCharacters(in: .whitespaces).isEmpty ? "9090" : self.port
        let scheme = self.useHTTPS ? "https" : "http"
        return self.tr("ui.machine.preview", scheme, resolvedHost, resolvedPort)
    }

    private func save() {
        let trimmedName = self.name.trimmingCharacters(in: .whitespaces)
        let trimmedHost = self.host.trimmingCharacters(in: .whitespaces)
        let portValue = Int(self.port) ?? 9090
        let trimmedSecret = self.secret.trimmingCharacters(in: .whitespaces)

        let machine = RemoteMachine(
            id: self.mode.machine?.id ?? UUID(),
            name: trimmedName,
            host: trimmedHost,
            port: portValue,
            secret: trimmedSecret.isEmpty ? nil : trimmedSecret,
            useHTTPS: self.useHTTPS)

        if self.mode.machine != nil {
            self.store.updateMachine(machine)
        } else {
            self.store.addMachine(machine)
        }

        self.onComplete()
    }
}

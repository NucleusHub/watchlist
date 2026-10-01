import NucleusUI
import PhotosUI
import SwiftUI

/// Tell us what went wrong, with screenshots. Sent to Nucleus ID's reports endpoint.
struct ReportSheet: View {
    @Environment(NucleusID.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var details = ""
    @State private var email = ""
    @State private var anonymous = false
    @State private var shots: [UIImage] = []
    @State private var picks: [PhotosPickerItem] = []
    @State private var sending = false
    @State private var sent = false
    @State private var failure: String?
    @State private var confirmingDiscard = false

    private var canSend: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && !details.trimmingCharacters(in: .whitespaces).isEmpty && !sending
    }

    private var hasInput: Bool { !title.isEmpty || !details.isEmpty || !shots.isEmpty }

    var body: some View {
        if sent {
            VStack(spacing: 16) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 56)).foregroundStyle(Nucleus.success)
                Text("Sent").font(.system(size: 24, weight: .bold))
                Text(auth.isSignedIn && !anonymous || !email.isEmpty ? "Thanks. We'll get back to you." : "Thanks for letting us know.")
                    .foregroundStyle(Nucleus.secondaryText)
                Button("Done") { dismiss() }.buttonStyle(NucleusPrimaryButtonStyle()).frame(maxWidth: 240)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(NucleusBackground())
        } else {
            form
        }
    }

    private var form: some View {
        NucleusSheetPage("Report a problem", confirmTitle: "Send", canConfirm: canSend,
                         onCancel: { if hasInput { confirmingDiscard = true } else { dismiss() } }, onConfirm: send) {
            NucleusSection(footer: failure.map { Text(verbatim: $0).foregroundStyle(Nucleus.danger) }) {
                TextField("What happened?", text: $title)
                    .font(.system(size: 17, weight: .medium))
                    .padding(.horizontal, 16).frame(minHeight: 52)
                    .onChange(of: title) { _, v in if v.count > 200 { title = String(v.prefix(200)) } }
                TextField("Steps, what you expected, what you saw", text: $details, axis: .vertical)
                    .lineLimit(5...14)
                    .padding(16)
                    .onChange(of: details) { _, v in if v.count > 10000 { details = String(v.prefix(10000)) } }
            }
            NucleusSection("Screenshots", footer: Text("Up to 4.")) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(shots.enumerated()), id: \.offset) { i, image in
                            Image(uiImage: image).resizable().scaledToFill()
                                .frame(width: 70, height: 120).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(alignment: .topTrailing) {
                                    Button { shots.remove(at: i) } label: {
                                        Image(systemName: "xmark.circle.fill").font(.system(size: 20)).foregroundStyle(.white, .black.opacity(0.6))
                                    }
                                    .padding(4)
                                }
                        }
                        if shots.count < 4 {
                            PhotosPicker(selection: $picks, maxSelectionCount: 4 - shots.count, matching: .screenshots) {
                                Image(systemName: "plus").font(.system(size: 22, weight: .semibold)).foregroundStyle(Nucleus.accent)
                                    .frame(width: 70, height: 120)
                                    .background(RoundedRectangle(cornerRadius: 10).strokeBorder(Nucleus.accent.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                            }
                        }
                    }
                    .padding(12)
                }
            }
            NucleusSection("Reply to", footer: Text(verbatim: diagnostics)) {
                if let user = auth.user {
                    Toggle(isOn: $anonymous) { Text("Send anonymously") }
                        .tint(Color(hex: 0x34C759))
                        .padding(.horizontal, 16).frame(minHeight: 52)
                    if !anonymous {
                        NucleusRow(verbatim: "@\(user.handle)", subtitle: Text("Nucleus ID"))
                    }
                } else {
                    TextField("Email (optional)", text: $email)
                        .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .padding(.horizontal, 16).frame(minHeight: 52)
                }
            }
        }
        .interactiveDismissDisabled(hasInput)
        .confirmationDialog("Discard this report?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { dismiss() }
        }
        .onChange(of: picks) { _, items in
            Task {
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data), shots.count < 4 {
                        shots.append(image)
                    }
                }
                picks = []
            }
        }
    }

    private var diagnostics: String {
        "Watchlist \(Bundle.main.versionString) · \(Device.modelID) · iOS \(UIDevice.current.systemVersion)"
    }

    private func send() {
        let mail = email.trimmingCharacters(in: .whitespaces)
        if !mail.isEmpty, mail.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, options: .regularExpression) == nil {
            failure = String(localized: "That email doesn't look right.")
            return
        }
        sending = true
        failure = nil
        Task {
            defer { sending = false }
            var body: [String: JSONValue] = [
                "title": .string(title.trimmingCharacters(in: .whitespaces)),
                "description": .string(details.trimmingCharacters(in: .whitespaces)),
                "locale": .string(Locale.preferredLanguages.first ?? "en"),
                "app": ["id": "watchlist", "name": "Watchlist",
                        "version": .string(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""),
                        "build": .string(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "")],
                "device": ["model": .string(UIDevice.current.model), "modelId": .string(Device.modelID), "manufacturer": "Apple",
                           "platform": "ios", "os": "ios", "osVersion": .string(UIDevice.current.systemVersion), "webView": nil],
                "attachments": .array(shots.compactMap { Images.jpeg($0, maxEdge: 1600, quality: 0.82) }
                    .map { ["type": "image/jpeg", "data": .string($0.base64EncodedString())] }),
            ]
            if !mail.isEmpty { body["email"] = .string(mail) }
            var req = URLRequest(url: NucleusID.origin.appending(path: "api/v1/reports"))
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONEncoder().encode(JSONValue.object(body))
            do {
                let (_, response) = auth.isSignedIn && !anonymous ? try await auth.authorized(req) : try await NucleusID.send(req)
                switch response.statusCode {
                case 200..<300:
                    Haptics.success()
                    withAnimation { sent = true }
                case 429: failure = String(localized: "Too many reports. Try again later.")
                default: failure = String(localized: "Couldn't send it (\(response.statusCode)).")
                }
            } catch {
                failure = String(localized: "You're offline. Try again when you're connected.")
            }
        }
    }
}

enum Device {
    static var modelID: String {
        if let sim = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return sim }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }
}

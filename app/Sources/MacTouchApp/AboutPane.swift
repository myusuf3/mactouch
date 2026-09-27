import MacTouchKit
import MacTouchModel
import SwiftUI

/// The app's own page: the sensor lit as it is now, the version, and who
/// made what.
struct AboutPane: View {
  @ObservedObject var model: DaemonModel

  private var version: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
  }

  var body: some View {
    Form {
      Section {
        VStack(spacing: 14) {
          DeviceHero(ring: model.deviceConnected ? model.ringState : .off, size: 128)
          VStack(spacing: 4) {
            Text("MacTouch")
              .font(.title.weight(.semibold))
            Text("A fingerprint sensor for your desk that your Mac can ask, “is that you?”")
              .font(.callout)
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.center)
          }
          VersionCapsule(text: version)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
      }
      Section {
        LabeledContent("Hardware") {
          Link("tinytouch by Zimeng Xiong", destination: URL(string: "https://github.com/ZimengXiong/tinyTouch")!)
        }
        LabeledContent("Source") {
          Link("github.com/myusuf3/mactouch", destination: URL(string: "https://github.com/myusuf3/mactouch")!)
        }
        LabeledContent("Licence", value: "MIT")
      }
    }
    .formStyle(.grouped)
  }
}

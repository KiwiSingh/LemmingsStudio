import SwiftUI

#if canImport(CoreAudioKit)
import CoreAudioKit

struct VisionBluetoothMIDIPairingView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        CABTMIDICentralViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
#else
struct VisionBluetoothMIDIPairingView: View {
    var body: some View {
        ContentUnavailableView(
            "Bluetooth MIDI pairing unavailable",
            systemImage: "antenna.radiowaves.left.and.right.slash",
            description: Text("This SDK target does not expose CoreAudioKit's Bluetooth MIDI central view controller. Pair the keyboard in system settings, then refresh CoreMIDI sources.")
        )
    }
}
#endif

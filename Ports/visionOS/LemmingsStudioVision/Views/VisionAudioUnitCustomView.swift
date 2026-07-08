import SwiftUI
import UIKit

struct VisionAudioUnitCustomView: UIViewControllerRepresentable {
    let controller: AnyObject

    func makeUIViewController(context: Context) -> UIViewController {
        guard let viewController = controller as? UIViewController else {
            let fallback = UIViewController()
            fallback.view.backgroundColor = .clear
            return fallback
        }
        return AudioUnitContainerViewController(child: viewController)
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

private final class AudioUnitContainerViewController: UIViewController {
    private let childController: UIViewController
    init(child: UIViewController) {
        self.childController = child
        super.init(nibName: nil, bundle: nil)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        addChild(childController)
        childController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(childController.view)
        NSLayoutConstraint.activate([
            childController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            childController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            childController.view.topAnchor.constraint(equalTo: view.topAnchor),
            childController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        childController.didMove(toParent: self)
    }
}

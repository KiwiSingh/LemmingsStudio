import SwiftUI
import AppKit

enum PianoRollKeyCommand:Equatable {case selectAll;case transpose(Int)}

struct PianoRollKeyCapture:NSViewRepresentable {
    var onCommand:(PianoRollKeyCommand)->Bool
    func makeNSView(context:Context)->KeyView {let view=KeyView();view.onCommand=onCommand;return view}
    func updateNSView(_ view:KeyView,context:Context){view.onCommand=onCommand}
    final class KeyView:NSView {
        var onCommand:((PianoRollKeyCommand)->Bool)?
        private var monitor:Any?
        override func viewDidMoveToWindow(){
            super.viewDidMoveToWindow()
            if let monitor {NSEvent.removeMonitor(monitor);self.monitor=nil}
            guard window != nil else {return}
            monitor=NSEvent.addLocalMonitorForEvents(matching:.keyDown){[weak self] event in
                guard let self,let window=self.window,event.window === window,window.attachedSheet==nil else {return event}
                if let text=window.firstResponder as? NSTextView,text.isEditable {return event}
                guard let command=Self.command(for:event),self.onCommand?(command)==true else {return event}
                return nil
            }
        }
        static func command(for event:NSEvent)->PianoRollKeyCommand? {
            let flags=event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.function,.numericPad,.capsLock])
            if event.keyCode==0 && flags == [.command] {return .selectAll}
            if event.keyCode==126 && flags == [.shift] {return .transpose(12)}
            if event.keyCode==125 && flags == [.shift] {return .transpose(-12)}
            return nil
        }
        deinit {if let monitor {NSEvent.removeMonitor(monitor)}}
    }
}

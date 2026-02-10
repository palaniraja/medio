import SwiftUI
import AppKit

struct ContentView: View {
    @State private var inputText = ""
    @State private var leftText = ""
    @State private var rightText = ""
    @State private var triggerProofread = false
    
    var body: some View {
        ZStack {
            VisualEffectBlur(material: .headerView, blendingMode: .behindWindow)
                .ignoresSafeArea()
            
            VStack(spacing: 12) {
                // Input area with button
                VStack(spacing: 8) {
                    WritingToolsTextView(
                        text: $inputText,
                        triggerProofread: $triggerProofread,
                        onProofreadComplete: { proofreadText in
                            rightText = proofreadText
                        }
                    )
                    .frame(height: 100)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                    
                    HStack {
                        Spacer()
                        Button(action: {
                            leftText = inputText
                            triggerProofread = true
                        }) {
                            HStack {
                                Image(systemName: "text.badge.checkmark")
                                Text("Proofread")
                            }
                        }
                        .keyboardShortcut(.return, modifiers: .command)
                        .buttonStyle(.borderedProminent)
                        .disabled(inputText.isEmpty)
                    }
                }
                .padding([.horizontal, .top])
                
                // Diff views
                HStack(spacing: 0) {
                    DiffTextView(text: $leftText, comparisonText: $rightText, side: .left)
                    Divider()
                        .background(Color(NSColor.separatorColor))
                    DiffTextView(text: $rightText, comparisonText: $leftText, side: .right)
                }
                .padding([.horizontal, .bottom])
            }
        }
    }
}

// NSViewRepresentable wrapper for NSTextView with Writing Tools support
struct WritingToolsTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var triggerProofread: Bool
    var onProofreadComplete: (String) -> Void
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        
        let textView = ProofreadTextView()
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isRichText = false
        textView.font = .systemFont(ofSize: 14)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
        textView.backgroundColor = .clear
        
        scrollView.documentView = textView
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? ProofreadTextView else { return }
        
        if textView.string != text {
            textView.string = text
        }
        
        if triggerProofread {
            DispatchQueue.main.async {
                context.coordinator.startProofreading(originalText: text)
                context.coordinator.onProofreadComplete = onProofreadComplete
                if #available(macOS 15.2, *) {
                    textView.showWritingTools(nil)
                }
                triggerProofread = false
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        var onProofreadComplete: ((String) -> Void)?
        var isProofreading = false
        var originalProofreadText: String?
        
        init(text: Binding<String>) {
            _text = text
        }
        
        func startProofreading(originalText: String) {
            isProofreading = true
            originalProofreadText = originalText
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let newText = textView.string
            
            // Always update the binding
            if text != newText {
                text = newText
                
                // Update right side with all changes while proofreading is active
                if isProofreading {
                    onProofreadComplete?(newText)
                }
            }
        }
        
        // Try to intercept Writing Tools completion
        @available(macOS 15.0, *)
        func textView(_ textView: NSTextView, writingToolsIgnoredRangesInEnclosingRange enclosingRange: NSRange) -> [NSValue] {
            return []
        }
    }
}

// Custom text view for Writing Tools
class ProofreadTextView: NSTextView {
}

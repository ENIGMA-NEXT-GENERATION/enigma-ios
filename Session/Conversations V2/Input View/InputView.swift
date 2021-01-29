
final class InputView : UIView, InputViewButtonDelegate, InputTextViewDelegate {
    private let delegate: InputViewDelegate
    
    var text: String {
        get { inputTextView.text }
        set { inputTextView.text = newValue }
    }
    
    override var intrinsicContentSize: CGSize { CGSize.zero }
    
    // MARK: UI Components
    private lazy var cameraButton = InputViewButton(icon: #imageLiteral(resourceName: "actionsheet_camera_black"), delegate: self)
    private lazy var libraryButton = InputViewButton(icon: #imageLiteral(resourceName: "actionsheet_camera_roll_black"), delegate: self)
    private lazy var gifButton = InputViewButton(icon: #imageLiteral(resourceName: "actionsheet_gif_black"), delegate: self)
    private lazy var documentButton = InputViewButton(icon: #imageLiteral(resourceName: "actionsheet_document_black"), delegate: self)
    private lazy var sendButton = InputViewButton(icon: #imageLiteral(resourceName: "ArrowUp"), isSendButton: true, delegate: self)
    
    private lazy var inputTextView = InputTextView(delegate: self)
    
    // MARK: Lifecycle
    init(delegate: InputViewDelegate) {
        self.delegate = delegate
        super.init(frame: CGRect.zero)
        setUpViewHierarchy()
    }
    
    override init(frame: CGRect) {
        preconditionFailure("Use init(delegate:) instead.")
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure("Use init(delegate:) instead.")
    }
    
    private func setUpViewHierarchy() {
        autoresizingMask = .flexibleHeight
        // Background & blur
        let backgroundView = UIView()
        backgroundView.backgroundColor = isLightMode ? .white : .black
        backgroundView.alpha = Values.lowOpacity
        addSubview(backgroundView)
        backgroundView.pin(to: self)
        let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
        addSubview(blurView)
        blurView.pin(to: self)
        // Separator
        let separator = UIView()
        separator.backgroundColor = Colors.text.withAlphaComponent(0.2)
        separator.set(.height, to: 1 / UIScreen.main.scale)
        addSubview(separator)
        separator.pin([ UIView.HorizontalEdge.leading, UIView.VerticalEdge.top, UIView.HorizontalEdge.trailing ], to: self)
        // Buttons
        func container(for button: InputViewButton) -> UIView {
            let result = UIView()
            result.addSubview(button)
            result.set(.width, to: InputViewButton.expandedSize)
            result.set(.height, to: InputViewButton.expandedSize)
            button.center(in: result)
            return result
        }
        let (cameraButtonContainer, libraryButtonContainer, gifButtonContainer, documentButtonContainer) = (container(for: cameraButton), container(for: libraryButton), container(for: gifButton), container(for: documentButton))
        let buttonStackView = UIStackView(arrangedSubviews: [ cameraButtonContainer, libraryButtonContainer, gifButtonContainer, documentButtonContainer, UIView.hStretchingSpacer() ])
        buttonStackView.axis = .horizontal
        buttonStackView.spacing = Values.smallSpacing
        // Bottom stack view
        let bottomStackView = UIStackView(arrangedSubviews: [ inputTextView, container(for: sendButton) ])
        bottomStackView.axis = .horizontal
        bottomStackView.spacing = Values.smallSpacing
        // Main stack view
        let mainStackView = UIStackView(arrangedSubviews: [ buttonStackView, bottomStackView ])
        mainStackView.axis = .vertical
        mainStackView.spacing = 12
        mainStackView.isLayoutMarginsRelativeArrangement = true
        let adjustment = (InputViewButton.expandedSize - InputViewButton.size) / 2
        mainStackView.layoutMargins = UIEdgeInsets(top: Values.smallSpacing, leading: Values.largeSpacing, bottom: Values.smallSpacing, trailing: Values.largeSpacing - adjustment)
        addSubview(mainStackView)
        mainStackView.pin(.top, to: .bottom, of: separator)
        mainStackView.pin([ UIView.HorizontalEdge.leading, UIView.HorizontalEdge.trailing ], to: self)
        mainStackView.pin(.bottom, to: .bottom, of: self, withInset: -12)
    }
    
    // MARK: Updating
    func inputTextViewDidChangeSize(_ inputTextView: InputTextView) {
        invalidateIntrinsicContentSize()
    }
    
    // MARK: Interaction
    func handleInputViewButtonTapped(_ inputViewButton: InputViewButton) {
        if inputViewButton == cameraButton { delegate.handleCameraButtonTapped() }
        if inputViewButton == libraryButton { delegate.handleLibraryButtonTapped() }
        if inputViewButton == gifButton { delegate.handleGIFButtonTapped() }
        if inputViewButton == documentButton { delegate.handleDocumentButtonTapped() }
        if inputViewButton == sendButton { delegate.handleSendButtonTapped() }
    }
    
    override func resignFirstResponder() -> Bool {
        inputTextView.resignFirstResponder()
    }
}

// MARK: Delegate
protocol InputViewDelegate {
    
    func handleCameraButtonTapped()
    func handleLibraryButtonTapped()
    func handleGIFButtonTapped()
    func handleDocumentButtonTapped()
    func handleSendButtonTapped()
}

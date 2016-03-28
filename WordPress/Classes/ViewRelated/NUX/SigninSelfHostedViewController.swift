import UIKit
import WordPressShared

///
///
class SigninSelfHostedViewController : SigninAbstractViewController
{

    @IBOutlet weak var usernameField: WPWalkthroughTextField!
    @IBOutlet weak var passwordField: WPWalkthroughTextField!
    @IBOutlet weak var siteURLField: WPWalkthroughTextField!
    @IBOutlet weak var submitButton: WPNUXMainButton!
    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var forgotPasswordButton: WPNUXSecondaryButton!
    var onePasswordButton: UIButton!

    lazy var loginFacade: LoginFacade = {
        let facade = LoginFacade()
        facade.delegate = self
        return facade
    }()

    lazy var blogSyncFacade = BlogSyncFacade()


    /// A convenience method for obtaining an instance of the controller from a storyboard.
    ///
    class func controller(loginFields: LoginFields) -> SigninSelfHostedViewController {
        let storyboard = UIStoryboard(name: "Signin", bundle: NSBundle.mainBundle())
        let controller = storyboard.instantiateViewControllerWithIdentifier("SigninSelfHostedViewController") as! SigninSelfHostedViewController
        controller.loginFields = loginFields
        return controller
    }


    // MARK: - Lifecycle Methods


    override func viewDidLoad() {
        super.viewDidLoad()

        setupOnePasswordButtonIfNeeded()
        displayLoginMessage("")
    }


    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)

        // Update special case login fields.
        loginFields.userIsDotCom = false

        configureTextFields()
        configureSubmitButton(false)
    }


    // MARK: Setup and Configuration


    ///
    ///
    func setupOnePasswordButtonIfNeeded() {
        WPStyleGuide.configureOnePasswordButtonForTextfield(usernameField,
                                                            target: self,
                                                            selector: #selector(SigninSelfHostedViewController.handleOnePasswordButtonTapped(_:)))
    }


    ///
    ///
    func configureTextFields() {
        usernameField.text = loginFields.username
        passwordField.text = loginFields.password
        siteURLField.text = loginFields.siteUrl
    }


    ///
    ///
    func configureForgotPasswordButton() {
        var status = ""
        if statusLabel.text != nil {
            status = statusLabel.text!
        }

        forgotPasswordButton.hidden = loginFields.siteUrl.isEmpty || !status.isEmpty
    }


    ///
    ///
    func configureSubmitButton(animating: Bool) {
        submitButton.showActivityIndicator(animating)

        submitButton.enabled = (
            !animating &&
            !loginFields.username.isEmpty &&
            !loginFields.password.isEmpty &&
            !loginFields.siteUrl.isEmpty
        )
    }


    ///
    ///
    func configureLoading(loading: Bool) {
        usernameField.enabled = !loading
        passwordField.enabled = !loading
        siteURLField.enabled = !loading

        configureSubmitButton(loading)
    }


    // MARK: - Instance Methods


    ///
    ///
    func validateForm() {
        view.endEditing(true)

        // is reachable?
        if !ReachabilityUtils.isInternetReachable() {
            ReachabilityUtils.showAlertNoInternetConnection()
            return
        }


        // Is everything filled out?
        if !SigninHelpers.validateFieldsPopulatedForSignin(loginFields) {
            WPError.showAlertWithTitle(NSLocalizedString("Error", comment: "Title of an error message"),
                                       message: NSLocalizedString("Please fill out all the fields", comment: "A short prompt asking the user to properly fill out all login fields."),
                                       withSupportButton: false)
            
            return
        }

        // Was a valid site URL entered.
        if !SigninHelpers.validateSiteForSignin(loginFields) {
            WPError.showAlertWithTitle(NSLocalizedString("Error", comment: "Title of an error message"),
                                       message: NSLocalizedString("The site's URL appears to be mistyped", comment: "A short prompt alerting to a misformatted URL"),
                                       withSupportButton: false)

            return
        }

        configureLoading(true)
        
        loginFacade.signInWithLoginFields(loginFields)
    }


    /// Displays an alert prompting that a site address is needed before 1Password can be used.
    ///
    func displayOnePasswordEmptySiteAlert() {
        // TODO: This can move to the self-hosted vc.
        let message = NSLocalizedString("A site address is required before 1Password can be used.",
                                        comment: "Error message displayed when the user is Signing into a self hosted site and tapped the 1Password Button before typing his siteURL")

        let alertController = UIAlertController(title: nil, message: message, preferredStyle: .Alert)
        alertController.addCancelActionWithTitle(NSLocalizedString("OK", comment: "OK Button Title"), handler: nil)

        presentViewController(alertController, animated: true, completion: nil)
    }


    // MARK: - Actions


    @IBAction func handleTextFieldDidChange(sender: UITextField) {
        loginFields.username = usernameField.nonNilTrimmedText()
        loginFields.password = passwordField.nonNilTrimmedText()
        loginFields.siteUrl = siteURLField.nonNilTrimmedText()

        configureForgotPasswordButton()
        configureSubmitButton(false)
    }


    @IBAction func handleSubmitForm() {
        validateForm()
    }


    @IBAction func handleSubmitButtonTapped(sender: UIButton) {
        validateForm()
    }


    func handleOnePasswordButtonTapped(sender: UIButton) {
        view.endEditing(true)

        if loginFields.userIsDotCom == false && loginFields.siteUrl.isEmpty {
            displayOnePasswordEmptySiteAlert()
            return
        }

        SigninHelpers.fetchOnePasswordCredentials(self, sourceView: sender, loginFields: loginFields) { [unowned self] (loginFields) in
            self.validateForm()
        }
    }


    @IBAction func handleForgotPasswordButtonTapped(sender: UIButton) {
        openForgotPasswordURL()
    }

}


extension SigninSelfHostedViewController: LoginFacadeDelegate {

    func finishedLoginWithUsername(username: String!, password: String!, xmlrpc: String!, options: [NSObject : AnyObject]!) {
        displayLoginMessage("")
        blogSyncFacade.syncBlogWithUsername(username, password: password, xmlrpc: xmlrpc, options: options) { [weak self] in
            self?.configureLoading(false)
            self?.dismiss()
        }
    }


    func displayLoginMessage(message: String!) {
        statusLabel.text = message
        configureForgotPasswordButton()
    }


    func displayRemoteError(error: NSError!) {
        configureLoading(false)
        displayError(error)
    }
}


extension SigninSelfHostedViewController: UITextFieldDelegate {
    func textFieldShouldReturn(textField: UITextField) -> Bool {
        if textField == usernameField {
            passwordField.becomeFirstResponder()
        } else if textField == passwordField {
            siteURLField.becomeFirstResponder()
        }
        return true
    }
}

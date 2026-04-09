#import "OpenAIAuthViewController.h"

#import "OpenAIAuthSession.h"
#import "LauncherPreferences.h"
#import "ios_uikit_bridge.h"
#import "utils.h"

@interface OpenAIAuthViewController ()
@property(nonatomic) UILabel *statusLabel;
@property(nonatomic) UILabel *detailLabel;
@property(nonatomic) UILabel *noteLabel;
@property(nonatomic) UIButton *signInButton;
@property(nonatomic) UIButton *finishButton;
@property(nonatomic) UIButton *signOutButton;
@property(nonatomic) UIActivityIndicatorView *activityIndicator;
@property(nonatomic) UITextView *infoTextView;
@end

@implementation OpenAIAuthViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = localize(@"openai_auth.title", nil);
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    self.statusLabel = [UILabel new];
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];

    self.detailLabel = [UILabel new];
    self.detailLabel.numberOfLines = 0;
    self.detailLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    self.detailLabel.textColor = UIColor.secondaryLabelColor;

    self.noteLabel = [UILabel new];
    self.noteLabel.numberOfLines = 0;
    self.noteLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    self.noteLabel.textColor = UIColor.secondaryLabelColor;
    self.noteLabel.text = localize(@"openai_auth.note", nil);

    self.signInButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.signInButton setTitle:localize(@"openai_auth.action.sign_in", nil) forState:UIControlStateNormal];
    self.signInButton.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    [self.signInButton addTarget:self action:@selector(actionSignIn) forControlEvents:UIControlEventTouchUpInside];

    self.finishButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.finishButton setTitle:localize(@"openai_auth.action.finish_from_clipboard", nil) forState:UIControlStateNormal];
    self.finishButton.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    [self.finishButton addTarget:self action:@selector(actionFinishFromClipboard) forControlEvents:UIControlEventTouchUpInside];

    self.signOutButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.signOutButton setTitle:localize(@"openai_auth.action.sign_out", nil) forState:UIControlStateNormal];
    self.signOutButton.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    [self.signOutButton addTarget:self action:@selector(actionSignOut) forControlEvents:UIControlEventTouchUpInside];

    self.activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.activityIndicator.hidesWhenStopped = YES;

    self.infoTextView = [UITextView new];
    self.infoTextView.editable = NO;
    self.infoTextView.selectable = YES;
    self.infoTextView.alwaysBounceVertical = YES;
    self.infoTextView.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    self.infoTextView.layer.cornerRadius = 12;
    self.infoTextView.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];

    UIStackView *buttonStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.signInButton, self.finishButton, self.signOutButton, self.activityIndicator]];
    buttonStack.axis = UILayoutConstraintAxisHorizontal;
    buttonStack.spacing = 12;
    buttonStack.alignment = UIStackViewAlignmentCenter;

    UIStackView *rootStack = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.statusLabel,
        self.detailLabel,
        self.noteLabel,
        buttonStack,
        self.infoTextView
    ]];
    rootStack.axis = UILayoutConstraintAxisVertical;
    rootStack.spacing = 12;
    rootStack.translatesAutoresizingMaskIntoConstraints = NO;

    [self.view addSubview:rootStack];
    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [rootStack.topAnchor constraintEqualToAnchor:guide.topAnchor constant:16],
        [rootStack.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:16],
        [rootStack.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-16],
        [rootStack.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor constant:-16],
        [self.infoTextView.heightAnchor constraintGreaterThanOrEqualToConstant:220]
    ]];

    [self refreshUI];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshUI];
}

- (void)refreshUI {
    OpenAIAuthSession *session = [OpenAIAuthSession sharedSession];
    self.statusLabel.text = session.isSignedIn
        ? localize(@"openai_auth.status.header.signed_in", nil)
        : (session.hasPendingManualSignIn ? localize(@"openai_auth.status.header.pending", nil) : localize(@"openai_auth.status.header.signed_out", nil));
    self.detailLabel.text = [session statusSummary];

    NSString *authorizationCode = [getPrefObject(@"ai.oauth_authorization_code") description] ?: @"";
    NSString *callbackURL = [getPrefObject(@"ai.oauth_callback_url") description] ?: @"";
    NSString *signedInAt = [getPrefObject(@"ai.oauth_signed_in_at") description] ?: @"";
    NSString *manualURL = [session pendingManualSignInURL] ?: @"";
    if (signedInAt.length == 0) {
        signedInAt = @"-";
    }
    if (authorizationCode.length == 0) {
        authorizationCode = @"-";
    }
    if (callbackURL.length == 0) {
        callbackURL = @"-";
    }
    if (manualURL.length == 0) {
        manualURL = @"-";
    }

    self.infoTextView.text = [NSString stringWithFormat:
        @"%@\n%@\n\n%@\n%@\n\n%@\n%@\n\n%@\n%@",
        localize(@"openai_auth.info.manual_url", nil), manualURL,
        localize(@"openai_auth.info.signed_in_at", nil), signedInAt,
        localize(@"openai_auth.info.authorization_code", nil), authorizationCode,
        localize(@"openai_auth.info.callback_url", nil), callbackURL];

    BOOL busy = self.activityIndicator.isAnimating;
    self.signInButton.enabled = !busy;
    self.finishButton.enabled = !busy && session.hasPendingManualSignIn;
    self.signOutButton.enabled = !busy && (session.isSignedIn || session.hasPendingManualSignIn);
}

- (void)actionSignIn {
    [self.view endEditing:YES];
    NSError *error = nil;
    NSString *urlString = [[OpenAIAuthSession sharedSession] prepareManualSignInURLWithError:&error];
    [self refreshUI];
    if (error) {
        showDialog(localize(@"Error", nil), error.localizedDescription);
        return;
    }

    UIPasteboard.generalPasteboard.string = urlString;
    showDialog(localize(@"openai_auth.title", nil), localize(@"openai_auth.success_copied_link", nil));
}

- (void)actionFinishFromClipboard {
    [self.view endEditing:YES];
    NSString *clipboardString = UIPasteboard.generalPasteboard.string ?: @"";
    NSError *error = nil;
    BOOL completed = [[OpenAIAuthSession sharedSession] completeManualSignInWithCallbackURLString:clipboardString error:&error];
    [self refreshUI];
    if (!completed) {
        showDialog(localize(@"Error", nil), error.localizedDescription);
        return;
    }
    showDialog(localize(@"openai_auth.title", nil), localize(@"openai_auth.success", nil));
}

- (void)actionSignOut {
    [self.view endEditing:YES];
    [[OpenAIAuthSession sharedSession] signOut];
    [self refreshUI];
}

- (void)setBusy:(BOOL)busy {
    if (busy) {
        [self.activityIndicator startAnimating];
    } else {
        [self.activityIndicator stopAnimating];
    }
    [self refreshUI];
}

@end

#import "AIModDoctorViewController.h"

#import "AIModDoctorService.h"
#import "LauncherPreferences.h"
#import "ios_uikit_bridge.h"
#import "utils.h"

@interface AIModDoctorViewController ()
@property(nonatomic) UILabel *summaryLabel;
@property(nonatomic) UILabel *statusLabel;
@property(nonatomic) UITextView *logTextView;
@property(nonatomic) UIButton *analyzeButton;
@property(nonatomic) UIButton *repairButton;
@property(nonatomic) UIActivityIndicatorView *activityIndicator;
@property(nonatomic) AIModDoctorService *service;
@end

@implementation AIModDoctorViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = localize(@"ai_doctor.title", nil);
    self.view.backgroundColor = UIColor.systemBackgroundColor;

    self.summaryLabel = [UILabel new];
    self.summaryLabel.numberOfLines = 0;
    self.summaryLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    self.summaryLabel.textColor = UIColor.secondaryLabelColor;

    self.statusLabel = [UILabel new];
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    self.statusLabel.textColor = UIColor.tertiaryLabelColor;

    self.analyzeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.analyzeButton setTitle:localize(@"ai_doctor.action.analyze", nil) forState:UIControlStateNormal];
    [self.analyzeButton addTarget:self action:@selector(actionAnalyze) forControlEvents:UIControlEventTouchUpInside];
    self.analyzeButton.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];

    self.repairButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.repairButton setTitle:localize(@"ai_doctor.action.repair", nil) forState:UIControlStateNormal];
    [self.repairButton addTarget:self action:@selector(actionRepair) forControlEvents:UIControlEventTouchUpInside];
    self.repairButton.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];

    self.activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.activityIndicator.hidesWhenStopped = YES;

    self.logTextView = [UITextView new];
    self.logTextView.editable = NO;
    self.logTextView.alwaysBounceVertical = YES;
    self.logTextView.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    self.logTextView.layer.cornerRadius = 12;
    self.logTextView.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];

    UIStackView *buttonStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.analyzeButton, self.repairButton, self.activityIndicator]];
    buttonStack.axis = UILayoutConstraintAxisHorizontal;
    buttonStack.spacing = 12;
    buttonStack.alignment = UIStackViewAlignmentCenter;
    buttonStack.distribution = UIStackViewDistributionFillProportionally;

    UIStackView *rootStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.summaryLabel, self.statusLabel, buttonStack, self.logTextView]];
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
        [self.logTextView.heightAnchor constraintGreaterThanOrEqualToConstant:280]
    ]];

    [self refreshSummary];
    [self appendLog:localize(@"ai_doctor.log.ready", nil)];
}

- (void)refreshSummary {
    NSString *profileName = self.profileName.length > 0 ? self.profileName : (self.profile[@"name"] ?: @"(unnamed)");
    self.summaryLabel.text = [NSString stringWithFormat:localize(@"ai_doctor.summary.profile", nil),
        profileName, self.profile[@"lastVersionId"] ?: @"(unknown)", self.gameDirectory ?: @"(missing)"];

    NSString *model = [getPrefObject(@"ai.ai_model") description];
    if (model.length == 0) {
        model = @"gpt-5.4-mini";
    }
    NSString *statusKey = getPrefBool(@"ai.ai_enabled") ? @"ai_doctor.status.enabled" : @"ai_doctor.status.disabled";
    BOOL fullAccessEnabled = getPrefObject(@"ai.ai_full_access") ? getPrefBool(@"ai.ai_full_access") : YES;
    NSString *accessKey = fullAccessEnabled ? @"ai_doctor.access.full" : @"ai_doctor.access.profile";
    self.statusLabel.text = [NSString stringWithFormat:localize(@"ai_doctor.summary.status", nil),
        localize(statusKey, nil), model, localize(accessKey, nil)];
}

- (void)actionAnalyze {
    [self startRunWithMode:AIModDoctorRunModeAnalyzeOnly];
}

- (void)actionRepair {
    [self startRunWithMode:AIModDoctorRunModeAutoRepair];
}

- (void)startRunWithMode:(AIModDoctorRunMode)mode {
    if (self.service) {
        return;
    }

    [self.view endEditing:YES];
    [self refreshSummary];
    [self appendLog:[NSString stringWithFormat:@"\n[%@] %@",
        [self timestampString],
        localize(mode == AIModDoctorRunModeAutoRepair ? @"ai_doctor.log.start_repair" : @"ai_doctor.log.start_analyze", nil)]];

    self.service = [AIModDoctorService new];
    self.service.profile = self.profile ?: @{};
    self.service.profileName = self.profileName;
    self.service.instanceDirectory = self.instanceDirectory;
    self.service.gameDirectory = self.gameDirectory;
    self.service.sharedModsDirectory = self.sharedModsDirectory;

    __weak typeof(self) weakSelf = self;
    self.service.eventHandler = ^(NSString *event) {
        [weakSelf appendLog:event];
    };

    [self setBusy:YES];
    [self.service runWithMode:mode completion:^(NSString *summary, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        [self setBusy:NO];
        if (error) {
            [self appendLog:[NSString stringWithFormat:@"[Error] %@", error.localizedDescription]];
            showDialog(localize(@"Error", nil), error.localizedDescription);
        } else if (summary.length > 0) {
            [self appendLog:[NSString stringWithFormat:@"\n[%@]\n%@", localize(@"ai_doctor.log.summary", nil), summary]];
        }
        self.service = nil;
    }];
}

- (void)setBusy:(BOOL)busy {
    self.analyzeButton.enabled = !busy;
    self.repairButton.enabled = !busy;
    if (busy) {
        [self.activityIndicator startAnimating];
    } else {
        [self.activityIndicator stopAnimating];
    }
}

- (NSString *)timestampString {
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.dateFormat = @"HH:mm:ss";
    return [formatter stringFromDate:[NSDate date]];
}

- (void)appendLog:(NSString *)line {
    if (line.length == 0) {
        return;
    }

    NSString *existingText = self.logTextView.text ?: @"";
    NSString *nextLine = [line hasSuffix:@"\n"] ? line : [line stringByAppendingString:@"\n"];
    self.logTextView.text = [existingText stringByAppendingString:nextLine];

    NSRange bottom = NSMakeRange(self.logTextView.text.length, 0);
    [self.logTextView scrollRangeToVisible:bottom];
}

@end

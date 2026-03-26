#import <WebKit/WebKit.h>
#import "LauncherMenuViewController.h"
#import "LauncherNewsViewController.h"
#import "LauncherPreferences.h"
#import "LauncherUIStyle.h"
#import "utils.h"

@interface LauncherNewsViewController()<WKNavigationDelegate>
@property(nonatomic) UIView *headerCard;
@property(nonatomic) UILabel *subtitleLabel;
@property(nonatomic) UIView *webContainerView;
@property(nonatomic) WKWebView *webView;
@property(nonatomic) UIActivityIndicatorView *loadingIndicator;
@end

@implementation LauncherNewsViewController

- (id)init {
    self = [super init];
    self.title = localize(@"News", nil);
    return self;
}

- (NSString *)imageName {
    return @"MenuNews";
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://wiki.angelauramc.dev/patchnotes/changelogs/IOS.html"]];

    self.headerCard = [[UIView alloc] initWithFrame:CGRectZero];
    self.headerCard.translatesAutoresizingMaskIntoConstraints = NO;
    LauncherStylePanel(self.headerCard, 24.0);

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.text = localize(@"News", nil);
    titleLabel.font = LauncherTitleFont(22.0);
    titleLabel.textColor = UIColor.labelColor;

    self.subtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.subtitleLabel.text = @"wiki.angelauramc.dev";
    self.subtitleLabel.font = LauncherBodyFont(13.0);
    self.subtitleLabel.textColor = UIColor.secondaryLabelColor;
    self.subtitleLabel.numberOfLines = 2;

    self.loadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.loadingIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    [self.loadingIndicator startAnimating];

    [self.headerCard addSubview:titleLabel];
    [self.headerCard addSubview:self.subtitleLabel];
    [self.headerCard addSubview:self.loadingIndicator];
    [self.view addSubview:self.headerCard];

    self.webContainerView = [[UIView alloc] initWithFrame:CGRectZero];
    self.webContainerView.translatesAutoresizingMaskIntoConstraints = NO;
    LauncherStylePanel(self.webContainerView, 26.0);
    self.webContainerView.clipsToBounds = YES;
    [self.view addSubview:self.webContainerView];

    WKWebViewConfiguration *webConfig = [[WKWebViewConfiguration alloc] init];
    self.webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:webConfig];
    self.webView.translatesAutoresizingMaskIntoConstraints = NO;
    self.webView.navigationDelegate = self;
    self.webView.opaque = NO;
    self.webView.backgroundColor = UIColor.clearColor;
    self.webView.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentAutomatic;
    NSString *javascript = @"var meta = document.createElement('meta');meta.setAttribute('name', 'viewport');meta.setAttribute('content', 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no');document.getElementsByTagName('head')[0].appendChild(meta);";
    WKUserScript *nozoom = [[WKUserScript alloc] initWithSource:javascript injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:YES];
    [self.webView.configuration.userContentController addUserScript:nozoom];
    [self.webView.scrollView setShowsHorizontalScrollIndicator:NO];
    [self.webContainerView addSubview:self.webView];
    [self.webView loadRequest:request];

    [NSLayoutConstraint activateConstraints:@[
        [self.headerCard.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12.0],
        [self.headerCard.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16.0],
        [self.headerCard.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16.0],

        [titleLabel.topAnchor constraintEqualToAnchor:self.headerCard.topAnchor constant:18.0],
        [titleLabel.leadingAnchor constraintEqualToAnchor:self.headerCard.leadingAnchor constant:20.0],
        [titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.loadingIndicator.leadingAnchor constant:-12.0],

        [self.subtitleLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:6.0],
        [self.subtitleLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [self.subtitleLabel.trailingAnchor constraintEqualToAnchor:self.headerCard.trailingAnchor constant:-20.0],
        [self.subtitleLabel.bottomAnchor constraintEqualToAnchor:self.headerCard.bottomAnchor constant:-18.0],

        [self.loadingIndicator.centerYAnchor constraintEqualToAnchor:titleLabel.centerYAnchor],
        [self.loadingIndicator.trailingAnchor constraintEqualToAnchor:self.headerCard.trailingAnchor constant:-20.0],

        [self.webContainerView.topAnchor constraintEqualToAnchor:self.headerCard.bottomAnchor constant:14.0],
        [self.webContainerView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:12.0],
        [self.webContainerView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-12.0],
        [self.webContainerView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-12.0],

        [self.webView.topAnchor constraintEqualToAnchor:self.webContainerView.topAnchor],
        [self.webView.leadingAnchor constraintEqualToAnchor:self.webContainerView.leadingAnchor],
        [self.webView.trailingAnchor constraintEqualToAnchor:self.webContainerView.trailingAnchor],
        [self.webView.bottomAnchor constraintEqualToAnchor:self.webContainerView.bottomAnchor]
    ]];

    if(!isJailbroken && getPrefBool(@"warnings.limited_ram_warn") && (roundf(NSProcessInfo.processInfo.physicalMemory / 0x1000000) < 3900)) {
        // "This device has a limited amount of memory available."
        [self showWarningAlert:@"limited_ram" hasPreference:YES exitWhenCompleted:NO];
    }

    self.navigationItem.leftBarButtonItem = self.splitViewController.displayModeButtonItem;
    self.navigationItem.rightBarButtonItem = [sidebarViewController drawAccountButton];
    self.navigationItem.leftItemsSupplementBackButton = true;
}

-(void)showWarningAlert:(NSString *)key hasPreference:(BOOL)isPreferenced exitWhenCompleted:(BOOL)shouldExit {
    UIAlertController *warning = [UIAlertController
                                      alertControllerWithTitle:localize([NSString stringWithFormat:@"login.warn.title.%@", key], nil)
                                      message:localize([NSString stringWithFormat:@"login.warn.message.%@", key], nil)
                                      preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *action;
    if(isPreferenced) {
        action = [UIAlertAction actionWithTitle:localize(@"OK", nil) style:UIAlertActionStyleDestructive handler:^(UIAlertAction * action) {
            setPrefBool([NSString stringWithFormat:@"warnings.%@_warn", key], NO);
        }];
    } else if(shouldExit) {
        action = [UIAlertAction actionWithTitle:localize(@"OK", nil) style:UIAlertActionStyleDestructive handler:^(UIAlertAction * action) {
            [UIApplication.sharedApplication performSelector:@selector(suspend)];
            usleep(100*1000);
            exit(0);
        }];
    } else {
        action = [UIAlertAction actionWithTitle:localize(@"OK", nil) style:UIAlertActionStyleCancel handler:nil];
    }
    warning.popoverPresentationController.sourceView = self.view;
    warning.popoverPresentationController.sourceRect = self.view.bounds;
    [warning addAction:action];
    [self presentViewController:warning animated:YES completion:nil];
}

-(void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    if (scrollView.contentOffset.x > 0)
        scrollView.contentOffset = CGPointMake(0, scrollView.contentOffset.y);
}

- (void)webView:(WKWebView *)webView 
decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction 
decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
     if (navigationAction.navigationType == WKNavigationTypeLinkActivated) {
        openLink(self, navigationAction.request.URL);
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }
    decisionHandler(WKNavigationActionPolicyAllow);
}

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
    [self.loadingIndicator startAnimating];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    [self.loadingIndicator stopAnimating];
}

@end

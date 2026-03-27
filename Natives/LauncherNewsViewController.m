#import <WebKit/WebKit.h>
#import "LauncherMenuViewController.h"
#import "LauncherNewsViewController.h"
#import "LauncherPreferences.h"
#import "utils.h"

@interface LauncherNewsViewController()<WKNavigationDelegate>
@end

@implementation LauncherNewsViewController
WKWebView *webView;
UIEdgeInsets insets;

static NSString *const kLauncherNewsGlassCSS =
    @"(function(){"
    "var style=document.getElementById('pl-launcher-glass-style');"
    "if(!style){style=document.createElement('style');style.id='pl-launcher-glass-style';document.head.appendChild(style);}"
    "style.textContent=`"
    "html,body,#app,.theme-container,.page,.theme-succinct-content,.content__default{background:transparent!important;}"
    "body{background:transparent!important;color:#f4f2ea!important;}"
    ".navbar,.sidebar,.search-box input,.search-box,.theme-succinct-content>.page-edit,.theme-succinct-content>.last-updated,.theme-succinct-content>.page-nav,footer.page-edit,.page-nav{"
    "background:rgba(18,20,26,.4)!important;"
    "border:1px solid rgba(255,255,255,.16)!important;"
    "box-shadow:0 12px 28px rgba(0,0,0,.18),inset 0 1px 0 rgba(255,255,255,.08)!important;"
    "backdrop-filter:blur(14px) saturate(115%);-webkit-backdrop-filter:blur(14px) saturate(115%);"
    "border-radius:18px!important;"
    "overflow:hidden!important;}"
    ".navbar{margin:10px 12px 0 12px!important;padding-inline:12px!important;}"
    ".sidebar{margin:10px 0 14px 12px!important;padding-top:10px!important;}"
    ".theme-succinct-content>.content__default>*{"
    "background:rgba(18,20,26,.38)!important;"
    "border:1px solid rgba(255,255,255,.15)!important;"
    "border-radius:18px!important;"
    "box-shadow:0 14px 30px rgba(0,0,0,.16),inset 0 1px 0 rgba(255,255,255,.08)!important;"
    "backdrop-filter:blur(14px) saturate(115%);-webkit-backdrop-filter:blur(14px) saturate(115%);"
    "padding:16px 18px!important;"
    "margin:0 4px 16px 4px!important;}"
    ".theme-succinct-content>.content__default>ul,.theme-succinct-content>.content__default>ol{padding-left:34px!important;}"
    ".theme-succinct-content>.content__default>h1,.theme-succinct-content>.content__default>h2,.theme-succinct-content>.content__default>h3{color:#fffaf0!important;}"
    ".theme-succinct-content>.content__default p,.theme-succinct-content>.content__default li,.theme-succinct-content>.content__default a,.theme-succinct-content>.content__default strong,.theme-succinct-content>.content__default code,.theme-succinct-content>.content__default span{color:#f4f2ea!important;}"
    ".sidebar-links,.sidebar-sub-headers,.nav-links{background:transparent!important;}"
    ".sidebar-link,.nav-link,.repo-link{border-radius:14px!important;}"
    ".search-box input{color:#fff!important;}"
    ".search-box input::placeholder{color:rgba(255,255,255,.72)!important;}"
    ".theme-succinct-content>.content__default .header-anchor{background:transparent!important;border:none!important;padding:0!important;margin-right:8px!important;}"
    ".theme-succinct-content>.content__default .icon.outbound,.navbar .icon,.sidebar .icon{color:inherit!important;}"
    "`;"
    "document.documentElement.style.background='transparent';"
    "document.body.style.background='transparent';"
    "})();";

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
    
    CGSize size = CGSizeMake(self.view.frame.size.width, self.view.frame.size.height);
    insets = UIApplication.sharedApplication.windows.firstObject.safeAreaInsets;
    
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:@"https://wiki.angelauramc.dev/patchnotes/changelogs/IOS.html"]];

    WKWebViewConfiguration *webConfig = [[WKWebViewConfiguration alloc] init];
    webView = [[WKWebView alloc] initWithFrame:self.view.frame configuration:webConfig];
    webView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    webView.translatesAutoresizingMaskIntoConstraints = NO;
    webView.navigationDelegate = self;
    webView.opaque = NO;
    webView.backgroundColor = UIColor.clearColor;
    webView.scrollView.backgroundColor = UIColor.clearColor;
    [self adjustWebViewForSize:size];
    webView.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    NSString *javascript = @"var meta = document.createElement('meta');meta.setAttribute('name', 'viewport');meta.setAttribute('content', 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no');document.getElementsByTagName('head')[0].appendChild(meta);";
    WKUserScript *nozoom = [[WKUserScript alloc] initWithSource:javascript injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:YES];
    [webView.configuration.userContentController addUserScript:nozoom];
    WKUserScript *glassTheme = [[WKUserScript alloc] initWithSource:kLauncherNewsGlassCSS injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:YES];
    [webView.configuration.userContentController addUserScript:glassTheme];
    [webView.scrollView setShowsHorizontalScrollIndicator:NO];
    [webView loadRequest:request];
    [self.view addSubview:webView];

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

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    [self adjustWebViewForSize:size];
}

- (void)adjustWebViewForSize:(CGSize)size {
    BOOL isPortrait = size.height > size.width;
    if (isPortrait) {
        webView.scrollView.contentInset = UIEdgeInsetsMake(self.navigationController.navigationBar.frame.size.height + insets.top, 0, self.navigationController.navigationBar.frame.size.height + insets.bottom, 0);
    } else {
        webView.scrollView.contentInset = UIEdgeInsetsMake(self.navigationController.navigationBar.frame.size.height, 0, self.navigationController.navigationBar.frame.size.height, 0);
    }
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

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    [webView evaluateJavaScript:kLauncherNewsGlassCSS completionHandler:nil];
}

@end

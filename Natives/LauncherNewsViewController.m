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

static NSString *const kLauncherIntroHTML =
    @"<!doctype html>"
    "<html lang='vi'>"
    "<head>"
    "<meta charset='utf-8'>"
    "<meta name='viewport' content='width=device-width, initial-scale=1, maximum-scale=1, viewport-fit=cover'>"
    "<title>__APP_NAME__</title>"
    "<style>"
    ":root{color-scheme:light only;--soft:rgba(16,28,42,.9);--muted:rgba(41,70,92,.68);--blue:#1492ff;--green:#66c23a;--shadow:rgba(8,24,42,.12);}"
    "*{box-sizing:border-box}html,body{margin:0;padding:0;background:transparent;color:var(--soft);font-family:'Avenir Next','SF Pro Display','Segoe UI',sans-serif;-webkit-font-smoothing:antialiased;text-rendering:optimizeLegibility}"
    "body{min-height:100vh;padding:22px 18px 88px;position:relative;overflow-x:hidden}"
    "body::before,body::after{content:'';position:fixed;inset:auto;pointer-events:none;filter:blur(10px);opacity:.34}"
    "body::before{width:320px;height:320px;left:-80px;top:18px;background:radial-gradient(circle at center,rgba(114,214,255,.18),rgba(114,214,255,0));}"
    "body::after{width:360px;height:360px;right:-120px;top:180px;background:radial-gradient(circle at center,rgba(120,255,203,.12),rgba(120,255,203,0));}"
    ".shell{max-width:1024px;margin:0 auto;display:grid;gap:18px}"
    ".masthead{display:flex;align-items:flex-start;justify-content:space-between;gap:16px;flex-wrap:wrap}"
    ".brandplate{display:inline-flex;align-items:center;gap:12px;padding:10px 14px;border-radius:24px;background:linear-gradient(180deg,rgba(248,252,255,.18),rgba(214,236,252,.08));box-shadow:0 8px 18px var(--shadow);backdrop-filter:blur(20px) saturate(108%)}"
    ".brandimg{display:block;width:min(100%,430px);height:auto}"
    ".brandhint{padding:12px 16px;border-radius:999px;background:rgba(238,248,255,.11);font-size:13px;font-weight:700;letter-spacing:.08em;text-transform:uppercase;color:var(--muted);backdrop-filter:blur(18px) saturate(108%)}"
    ".hero{display:grid;grid-template-columns:1.4fr .9fr;gap:18px;align-items:stretch}"
    ".card{background:linear-gradient(180deg,rgba(247,252,255,.17),rgba(206,233,249,.08));border:none;border-radius:28px;box-shadow:0 8px 18px var(--shadow);padding:24px 24px 22px;backdrop-filter:blur(20px) saturate(108%)}"
    ".badge{display:inline-flex;align-items:center;gap:10px;padding:10px 14px;border-radius:999px;background:rgba(236,247,255,.12);border:none;font-size:13px;font-weight:700;letter-spacing:.08em;text-transform:uppercase;color:var(--muted)}"
    ".dot{width:10px;height:10px;border-radius:999px;background:linear-gradient(135deg,#53b6ff,#6e87ff);box-shadow:0 0 0 5px rgba(83,182,255,.12)}"
    "h1{margin:18px 0 10px;font-size:clamp(38px,5.8vw,62px);line-height:.96;letter-spacing:-.045em}"
    ".lead{margin:0;max-width:720px;font-size:18px;line-height:1.56;color:var(--muted)}"
    ".stats{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:12px;margin-top:22px}"
    ".stat{padding:16px 18px;border-radius:22px;background:rgba(236,247,255,.11);border:none}"
    ".stat strong{display:block;font-size:22px;letter-spacing:-.03em}"
    ".stat span{display:block;margin-top:6px;font-size:13px;color:var(--muted)}"
    ".sidepanel{display:grid;gap:12px}"
    ".chip{padding:16px 18px;border-radius:22px;background:rgba(236,247,255,.11);border:none}"
    ".chip strong{display:block;font-size:14px;text-transform:uppercase;letter-spacing:.08em;color:var(--muted)}"
    ".chip span{display:block;margin-top:8px;font-size:19px;font-weight:700;letter-spacing:-.02em}"
    ".grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:18px}"
    ".feature h2,.steps h2{margin:0 0 14px;font-size:24px;letter-spacing:-.03em}"
    ".feature-list,.step-list{display:grid;gap:12px}"
    ".feature-item,.step-item{padding:16px 18px;border-radius:22px;background:rgba(236,247,255,.11);border:none}"
    ".feature-item strong,.step-item strong{display:block;font-size:17px}"
    ".feature-item p,.step-item p{margin:8px 0 0;font-size:14px;line-height:1.55;color:var(--muted)}"
    ".foot{display:flex;flex-wrap:wrap;gap:10px 14px;align-items:center;justify-content:space-between}"
    ".pill-row{display:flex;flex-wrap:wrap;gap:10px}"
    ".pill{padding:10px 14px;border-radius:999px;background:rgba(236,247,255,.11);border:none;font-size:13px;font-weight:700;color:var(--muted)}"
    ".signature{font-size:13px;color:var(--muted)}"
    "@media (max-width:860px){.hero,.grid{grid-template-columns:1fr}.stats{grid-template-columns:1fr}.card{border-radius:24px;padding:20px}.lead{font-size:16px}.brandplate{width:100%;justify-content:center}.brandimg{width:min(100%,360px)}}"
    "</style>"
    "</head>"
    "<body>"
    "<main class='shell'>"
    "<section class='masthead'>"
    "<div class='brandplate'>"
    "<img class='brandimg' src='__WORDMARK__' alt='Chill Launcher'>"
    "</div>"
    "<span class='brandhint'>Local intro page</span>"
    "</section>"
    "<section class='hero'>"
    "<article class='card'>"
    "<span class='badge'><span class='dot'></span> Chill Build</span>"
    "<h1>Sharper, smoother launcher chrome.</h1>"
    "<p class='lead'>A compact Chill Launcher build for iPhone and iPad with faster startup, cleaner profile management, lighter glass surfaces and a bundled ambient background loop that stays visible behind the controls.</p>"
    "<div class='stats'>"
    "<div class='stat'><strong>__VERSION__</strong><span>Current version</span></div>"
    "<div class='stat'><strong>Landscape</strong><span>Launcher tuned for wide layout</span></div>"
    "<div class='stat'><strong>iOS Glass</strong><span>Cool aqua glass tuned for bright ocean scenes</span></div>"
    "</div>"
    "</article>"
    "<aside class='sidepanel'>"
    "<div class='card chip'><strong>Status</strong><span>Ready to play</span></div>"
    "<div class='card chip'><strong>Build</strong><span>__BUILD__</span></div>"
    "<div class='card chip'><strong>Custom</strong><span>Ambient loop, Profiles, Controls</span></div>"
    "</aside>"
    "</section>"
    "<section class='grid'>"
    "<article class='card feature'>"
    "<h2>Highlights</h2>"
    "<div class='feature-list'>"
    "<div class='feature-item'><strong>Separate profiles</strong><p>Split Minecraft versions, memory, renderer and game directory per profile for faster switching.</p></div>"
    "<div class='feature-item'><strong>Bundled background loop</strong><p>A Chill-themed motion background ships inside the app, so the launcher always has a clean animated backdrop without importing a custom video.</p></div>"
    "<div class='feature-item'><strong>Custom controls</strong><p>Edit touch controls and gamepad config directly from the launcher without leaving the app.</p></div>"
    "</div>"
    "</article>"
    "<article class='card steps'>"
    "<h2>Quick start</h2>"
    "<div class='step-list'>"
    "<div class='step-item'><strong>1. Pick a profile</strong><p>Create or edit a profile with the right version, runtime and control preset.</p></div>"
    "<div class='step-item'><strong>2. Tune the launcher</strong><p>Open Settings to adjust renderer, interface and audio while the built-in Chill background stays ready in the launcher.</p></div>"
    "<div class='step-item'><strong>3. Press Play</strong><p>The launcher uses the current setup to start the game with a cleaner and more consistent UI.</p></div>"
    "</div>"
    "</article>"
    "</section>"
    "<footer class='card foot'>"
    "<div class='pill-row'>"
    "<span class='pill'>Local intro page</span>"
    "<span class='pill'>No external website dependency</span>"
    "<span class='pill'>Loads fast inside the app</span>"
    "</div>"
    "<span class='signature'>__APP_NAME__ - build __BUILD__</span>"
    "</footer>"
    "</main>"
    "</body>"
    "</html>";

- (NSString *)launcherIntroHTML {
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    NSString *appName = info[@"CFBundleDisplayName"] ?: info[@"CFBundleName"] ?: @"Chill Launcher";
    NSString *version = info[@"CFBundleShortVersionString"] ?: @"1.0";
    NSString *build = info[@"CFBundleVersion"] ?: version;
    UIImage *wordmarkImage = [UIImage imageNamed:@"BrandWordmark"];
    NSData *wordmarkData = wordmarkImage ? UIImagePNGRepresentation(wordmarkImage) : nil;
    NSString *wordmarkDataURI = wordmarkData ?
        [NSString stringWithFormat:@"data:image/png;base64,%@", [wordmarkData base64EncodedStringWithOptions:0]] :
        @"";
    NSString *html = [kLauncherIntroHTML stringByReplacingOccurrencesOfString:@"__APP_NAME__" withString:appName];
    html = [html stringByReplacingOccurrencesOfString:@"__VERSION__" withString:version];
    html = [html stringByReplacingOccurrencesOfString:@"__BUILD__" withString:build];
    html = [html stringByReplacingOccurrencesOfString:@"__WORDMARK__" withString:wordmarkDataURI];
    return html;
}

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
    [webView.scrollView setShowsHorizontalScrollIndicator:NO];
    [webView loadHTMLString:[self launcherIntroHTML] baseURL:nil];
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
     if (navigationAction.navigationType == WKNavigationTypeLinkActivated &&
         !navigationAction.request.URL.isFileURL) {
        openLink(self, navigationAction.request.URL);
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }
    decisionHandler(WKNavigationActionPolicyAllow);
}

@end

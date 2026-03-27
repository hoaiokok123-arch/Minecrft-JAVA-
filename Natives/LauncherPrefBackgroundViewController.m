#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#import "LauncherPrefBackgroundViewController.h"
#import "LauncherPreferences.h"
#import "ios_uikit_bridge.h"
#import "utils.h"

typedef NS_ENUM(NSInteger, LauncherBackgroundRow) {
    LauncherBackgroundRowCurrent,
    LauncherBackgroundRowChoose,
    LauncherBackgroundRowClear,
};

@interface LauncherPrefBackgroundViewController ()<UIDocumentPickerDelegate>
@end

@implementation LauncherPrefBackgroundViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        self.title = localize(@"preference.title.launcher_background_video", nil);
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;
    self.tableView.backgroundColor = UIColor.clearColor;
    PLApplyCompactTableLayout(self.tableView, 40);
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 3;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCellStyle style = indexPath.row == LauncherBackgroundRowCurrent ?
        UITableViewCellStyleValue1 : UITableViewCellStyleDefault;
    NSString *cellID = indexPath.row == LauncherBackgroundRowCurrent ? @"BackgroundValue1" : @"BackgroundDefault";

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:style reuseIdentifier:cellID];
    }

    PLApplyCompactTableCell(cell);
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.textColor = UIColor.labelColor;
    cell.imageView.tintColor = UIColor.secondaryLabelColor;
    cell.userInteractionEnabled = YES;

    switch (indexPath.row) {
        case LauncherBackgroundRowCurrent:
            cell.imageView.image = [UIImage systemImageNamed:@"film"];
            cell.textLabel.text = localize(@"preference.title.launcher_background_current", nil);
            cell.detailTextLabel.text = getLauncherBackgroundVideoDisplayName();
            cell.userInteractionEnabled = NO;
            break;
        case LauncherBackgroundRowChoose:
            cell.imageView.image = [UIImage systemImageNamed:@"play.rectangle"];
            cell.textLabel.text = localize(@"preference.title.launcher_background_choose", nil);
            cell.selectionStyle = UITableViewCellSelectionStyleGray;
            break;
        case LauncherBackgroundRowClear:
            cell.imageView.image = [UIImage systemImageNamed:@"trash"];
            cell.textLabel.text = localize(@"preference.title.launcher_background_clear", nil);
            cell.textLabel.textColor = UIColor.systemRedColor;
            cell.imageView.tintColor = UIColor.systemRedColor;
            cell.selectionStyle = UITableViewCellSelectionStyleGray;
            cell.userInteractionEnabled = getLauncherBackgroundVideoPath().length > 0;
            cell.textLabel.enabled = cell.userInteractionEnabled;
            break;
    }

    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 4;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    return 0.01;
}

- (void)presentVideoPicker {
    NSArray *contentTypes = @[
        UTTypeMovie,
        UTTypeVideo,
        UTTypeMPEG4Movie,
        UTTypeQuickTimeMovie
    ];
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:contentTypes];
    picker.delegate = self;
    picker.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:NO];

    if (indexPath.row == LauncherBackgroundRowChoose) {
        [self presentVideoPicker];
    } else if (indexPath.row == LauncherBackgroundRowClear && getLauncherBackgroundVideoPath().length > 0) {
        clearLauncherBackgroundVideo();
        [self.tableView reloadData];
    }
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentAtURL:(NSURL *)url {
    BOOL accessed = [url startAccessingSecurityScopedResource];
    NSError *error = setLauncherBackgroundVideoFromURL(url);
    if (accessed) {
        [url stopAccessingSecurityScopedResource];
    }

    if (error) {
        showDialog(localize(@"Error", nil), error.localizedDescription);
        return;
    }

    [self.tableView reloadData];
}

@end

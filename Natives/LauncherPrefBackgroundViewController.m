#import <PhotosUI/PhotosUI.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#import "LauncherPrefBackgroundViewController.h"
#import "LauncherPreferences.h"
#import "ios_uikit_bridge.h"
#import "utils.h"

typedef NS_ENUM(NSInteger, LauncherBackgroundRow) {
    LauncherBackgroundRowCurrent,
    LauncherBackgroundRowChoose,
    LauncherBackgroundRowClear,
    LauncherBackgroundRowScale,
    LauncherBackgroundRowOffsetX,
    LauncherBackgroundRowOffsetY,
    LauncherBackgroundRowReset,
};

@interface LauncherPrefBackgroundViewController ()<PHPickerViewControllerDelegate>
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
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.tableView.backgroundColor = UIColor.systemBackgroundColor;
    PLApplyCompactTableLayout(self.tableView, 40);
    [self applyTableAppearance];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(handleLauncherAppearanceDidChange:)
        name:PLLauncherAppearanceDidChangeNotification object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)applyTableAppearance {
    self.tableView.separatorStyle = getLauncherOutlineControlsEnabled() ?
        UITableViewCellSeparatorStyleNone :
        UITableViewCellSeparatorStyleSingleLine;
}

- (BOOL)hasSelectedVideo {
    return getLauncherBackgroundVideoPath().length > 0;
}

- (BOOL)hasCustomAdjustments {
    return getPrefInt(@"general.launcher_background_video_scale") != 100 ||
        getPrefInt(@"general.launcher_background_video_offset_x") != 0 ||
        getPrefInt(@"general.launcher_background_video_offset_y") != 0;
}

- (BOOL)isSliderRow:(LauncherBackgroundRow)row {
    return row >= LauncherBackgroundRowScale && row <= LauncherBackgroundRowOffsetY;
}

- (NSString *)preferenceKeyForSliderRow:(LauncherBackgroundRow)row {
    switch (row) {
        case LauncherBackgroundRowScale:
            return @"general.launcher_background_video_scale";
        case LauncherBackgroundRowOffsetX:
            return @"general.launcher_background_video_offset_x";
        case LauncherBackgroundRowOffsetY:
            return @"general.launcher_background_video_offset_y";
        default:
            return nil;
    }
}

- (NSString *)titleForSliderRow:(LauncherBackgroundRow)row value:(NSInteger)value {
    NSString *title;
    switch (row) {
        case LauncherBackgroundRowScale:
            title = localize(@"preference.title.launcher_background_scale", nil);
            return [NSString stringWithFormat:@"%@ %ld%%", title, (long)value];
        case LauncherBackgroundRowOffsetX:
            title = localize(@"preference.title.launcher_background_offset_x", nil);
            return [NSString stringWithFormat:@"%@ %+ld%%", title, (long)value];
        case LauncherBackgroundRowOffsetY:
            title = localize(@"preference.title.launcher_background_offset_y", nil);
            return [NSString stringWithFormat:@"%@ %+ld%%", title, (long)value];
        default:
            return @"";
    }
}

- (void)handleLauncherAppearanceDidChange:(NSNotification *)notification {
    [self applyTableAppearance];
    [self.tableView reloadData];
}

- (void)backgroundSliderChanged:(UISlider *)sender {
    NSInteger value = lroundf(sender.value);
    sender.value = value;
    NSString *key = [self preferenceKeyForSliderRow:(LauncherBackgroundRow)sender.tag];
    if (!key) {
        return;
    }
    setPrefInt(key, value);
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:sender.tag inSection:0];
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
    cell.textLabel.text = [self titleForSliderRow:(LauncherBackgroundRow)sender.tag value:value];
    postLauncherAppearanceDidChange();
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 7;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self isSliderRow:(LauncherBackgroundRow)indexPath.row]) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"BackgroundSlider"];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"BackgroundSlider"];
            UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(0, 0, MIN(220, tableView.bounds.size.width * 0.42), 28)];
            [slider addTarget:self action:@selector(backgroundSliderChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = slider;
        }

        PLApplyCompactTableCell(cell);
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.textColor = UIColor.labelColor;
        cell.textLabel.enabled = self.hasSelectedVideo;
        UISlider *slider = (UISlider *)cell.accessoryView;
        slider.frame = CGRectMake(0, 0, MIN(220, tableView.bounds.size.width * 0.42), 28);
        slider.tag = indexPath.row;
        slider.minimumValue = indexPath.row == LauncherBackgroundRowScale ? 50 : -100;
        slider.maximumValue = indexPath.row == LauncherBackgroundRowScale ? 250 : 100;
        slider.enabled = self.hasSelectedVideo;
        NSInteger value = getPrefInt([self preferenceKeyForSliderRow:(LauncherBackgroundRow)indexPath.row]);
        slider.value = value;
        cell.textLabel.text = [self titleForSliderRow:(LauncherBackgroundRow)indexPath.row value:value];
        if (getLauncherOutlineControlsEnabled()) {
            PLApplyLauncherCardChrome(cell, NO, NSDirectionalEdgeInsetsMake(0, 0, 0, 0), 10);
        } else if (@available(iOS 14.0, *)) {
            cell.backgroundConfiguration = nil;
            cell.layer.borderWidth = 0;
        }
        return cell;
    }

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
        case LauncherBackgroundRowReset:
            cell.imageView.image = [UIImage systemImageNamed:@"arrow.counterclockwise"];
            cell.textLabel.text = localize(@"preference.title.launcher_background_reset_adjustments", nil);
            cell.selectionStyle = UITableViewCellSelectionStyleGray;
            cell.userInteractionEnabled = self.hasCustomAdjustments;
            cell.textLabel.enabled = cell.userInteractionEnabled;
            break;
    }

    if (getLauncherOutlineControlsEnabled()) {
        PLApplyLauncherCardChrome(cell, NO, NSDirectionalEdgeInsetsMake(0, 0, 0, 0), 10);
    } else {
        if (@available(iOS 14.0, *)) {
            cell.backgroundConfiguration = nil;
        }
        cell.layer.borderWidth = 0;
    }

    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return [self isSliderRow:(LauncherBackgroundRow)indexPath.row] ? 46 : 40;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 4;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    return 0.01;
}

- (void)presentVideoPicker {
    PHPickerConfiguration *configuration = [[PHPickerConfiguration alloc] init];
    configuration.filter = [PHPickerFilter videosFilter];
    configuration.selectionLimit = 1;

    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:configuration];
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
    } else if (indexPath.row == LauncherBackgroundRowReset && self.hasCustomAdjustments) {
        resetLauncherBackgroundVideoAdjustments();
        [self.tableView reloadData];
    }
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    PHPickerResult *result = results.firstObject;
    if (!result) {
        return;
    }

    NSItemProvider *provider = result.itemProvider;
    NSArray<NSString *> *candidateTypes = @[
        UTTypeMPEG4Movie.identifier,
        UTTypeQuickTimeMovie.identifier,
        UTTypeMovie.identifier,
        UTTypeVideo.identifier
    ];

    NSString *typeIdentifier = nil;
    for (NSString *candidate in candidateTypes) {
        if ([provider hasItemConformingToTypeIdentifier:candidate]) {
            typeIdentifier = candidate;
            break;
        }
    }

    if (!typeIdentifier) {
        showDialog(localize(@"Error", nil), @"Unable to load the selected video.");
        return;
    }

    [provider loadFileRepresentationForTypeIdentifier:typeIdentifier completionHandler:^(NSURL * _Nullable url, NSError * _Nullable error) {
        if (error || !url) {
            dispatch_async(dispatch_get_main_queue(), ^{
                showDialog(localize(@"Error", nil), error.localizedDescription ?: @"Unable to load the selected video.");
            });
            return;
        }

        NSError *copyError = setLauncherBackgroundVideoFromURL(url);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (copyError) {
                showDialog(localize(@"Error", nil), copyError.localizedDescription);
                return;
            }
            [self.tableView reloadData];
        });
    }];
}

@end

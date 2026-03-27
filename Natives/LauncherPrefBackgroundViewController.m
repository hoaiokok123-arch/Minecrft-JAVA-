#import <AVFoundation/AVFoundation.h>
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
    LauncherBackgroundRowRotate,
    LauncherBackgroundRowReset,
};

@interface LauncherPrefBackgroundViewController ()<UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property(nonatomic) BOOL importingVideo;
@property(nonatomic) UIActivityIndicatorView *importIndicator;
@property(nonatomic) AVAssetExportSession *importSession;
@end

@implementation LauncherPrefBackgroundViewController

- (instancetype)init {
    self = [super initWithStyle:UITableViewStylePlain];
    if (self) {
        self.title = localize(@"preference.title.launcher_background_video", nil);
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.view.backgroundColor = UIColor.clearColor;
    self.tableView.backgroundColor = UIColor.clearColor;
    PLApplyCompactTableLayout(self.tableView, 40);
    [self applyTableAppearance];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(handleLauncherAppearanceDidChange:)
        name:PLLauncherAppearanceDidChangeNotification object:nil];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    PLApplyLauncherViewChrome(self.view);
    PLApplyLauncherNavigationBarChrome(self.navigationController.navigationBar);
    PLApplyLauncherToolbarChrome(self.navigationController.toolbar);
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
        getLauncherBackgroundVideoRotateEnabled();
}

- (BOOL)isSliderRow:(LauncherBackgroundRow)row {
    return row == LauncherBackgroundRowScale;
}

- (NSString *)preferenceKeyForSliderRow:(LauncherBackgroundRow)row {
    switch (row) {
        case LauncherBackgroundRowScale:
            return @"general.launcher_background_video_scale";
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
        default:
            return @"";
    }
}

- (void)handleLauncherAppearanceDidChange:(NSNotification *)notification {
    [self applyTableAppearance];
    [self.tableView reloadData];
}

- (void)setImportingVideo:(BOOL)importingVideo {
    _importingVideo = importingVideo;
    self.tableView.userInteractionEnabled = !importingVideo;
    self.navigationItem.hidesBackButton = importingVideo;
    if (!self.importIndicator) {
        self.importIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
        self.importIndicator.hidesWhenStopped = YES;
        self.importIndicator.translatesAutoresizingMaskIntoConstraints = NO;
        [self.view addSubview:self.importIndicator];
        [NSLayoutConstraint activateConstraints:@[
            [self.importIndicator.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
            [self.importIndicator.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor]
        ]];
    }
    if (importingVideo) {
        [self.importIndicator startAnimating];
    } else {
        [self.importIndicator stopAnimating];
    }
}

- (NSError *)backgroundImportError:(NSString *)description {
    return [NSError errorWithDomain:@"LauncherBackgroundVideo"
        code:1
        userInfo:@{NSLocalizedDescriptionKey: description}];
}

- (void)finishImportWithError:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.importSession = nil;
        self.importingVideo = NO;
        if (error) {
            showDialog(localize(@"Error", nil), error.localizedDescription);
        }
        [self.tableView reloadData];
    });
}

- (BOOL)selectedVideoLooksPortrait:(AVAsset *)asset {
    AVAssetTrack *track = [asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
    if (!track) {
        return NO;
    }
    CGSize transformedSize = CGSizeApplyAffineTransform(track.naturalSize, track.preferredTransform);
    return fabs(transformedSize.height) > fabs(transformedSize.width);
}

- (void)beginImportVideoFromURL:(NSURL *)url {
    NSURL *selectedURL = [url copy];
    self.importingVideo = YES;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @autoreleasepool {
            AVURLAsset *asset = [AVURLAsset URLAssetWithURL:selectedURL options:nil];
            BOOL shouldRotatePortraitVideo = [self selectedVideoLooksPortrait:asset];
            if ([asset tracksWithMediaType:AVMediaTypeVideo].count == 0) {
                [self finishImportWithError:[self backgroundImportError:@"Unable to load the selected video."]];
                return;
            }

            NSArray<NSString *> *compatiblePresets = [AVAssetExportSession exportPresetsCompatibleWithAsset:asset];
            NSString *presetName = [compatiblePresets containsObject:AVAssetExportPresetPassthrough] ?
                AVAssetExportPresetPassthrough :
                AVAssetExportPresetHighestQuality;
            AVAssetExportSession *session = [[AVAssetExportSession alloc] initWithAsset:asset presetName:presetName];
            if (!session) {
                [self finishImportWithError:[self backgroundImportError:@"Unable to prepare the selected video."]];
                return;
            }

            NSString *outputFileType = nil;
            NSString *extension = @"mp4";
            if ([session.supportedFileTypes containsObject:AVFileTypeMPEG4]) {
                outputFileType = AVFileTypeMPEG4;
            } else if ([session.supportedFileTypes containsObject:AVFileTypeQuickTimeMovie]) {
                outputFileType = AVFileTypeQuickTimeMovie;
                extension = @"mov";
            } else {
                outputFileType = session.supportedFileTypes.firstObject;
                if ([outputFileType isEqualToString:AVFileTypeQuickTimeMovie]) {
                    extension = @"mov";
                }
            }
            if (outputFileType.length == 0) {
                [self finishImportWithError:[self backgroundImportError:@"This video format is not supported for launcher background."]];
                return;
            }

            NSURL *stagedURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:
                [NSString stringWithFormat:@"launcher-video-import-%@.%@", NSUUID.UUID.UUIDString.lowercaseString, extension]]];
            [NSFileManager.defaultManager removeItemAtURL:stagedURL error:nil];

            session.outputURL = stagedURL;
            session.outputFileType = outputFileType;
            session.shouldOptimizeForNetworkUse = NO;
            dispatch_async(dispatch_get_main_queue(), ^{
                self.importSession = session;
            });

            [session exportAsynchronouslyWithCompletionHandler:^{
                if (session.status == AVAssetExportSessionStatusCompleted) {
                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                        NSError *error = setLauncherBackgroundVideoFromURL(stagedURL);
                        if (!error) {
                            setLauncherBackgroundVideoRotateEnabled(shouldRotatePortraitVideo);
                        }
                        [NSFileManager.defaultManager removeItemAtURL:stagedURL error:nil];
                        [self finishImportWithError:error];
                    });
                    return;
                }

                [NSFileManager.defaultManager removeItemAtURL:stagedURL error:nil];
                NSError *error = session.error;
                if (!error) {
                    NSString *message = session.status == AVAssetExportSessionStatusCancelled ?
                        @"Video import was cancelled." :
                        @"Unable to import the selected video.";
                    error = [self backgroundImportError:message];
                }
                [self finishImportWithError:error];
            }];
        }
    });
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
    NSIndexPath *resetIndexPath = [NSIndexPath indexPathForRow:LauncherBackgroundRowReset inSection:0];
    [self.tableView reloadRowsAtIndexPaths:@[resetIndexPath] withRowAnimation:UITableViewRowAnimationNone];
    postLauncherAppearanceDidChange();
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 6;
}

- (void)backgroundRotateChanged:(UISwitch *)sender {
    setLauncherBackgroundVideoRotateEnabled(sender.isOn);
    NSIndexPath *rotateIndexPath = [NSIndexPath indexPathForRow:LauncherBackgroundRowRotate inSection:0];
    NSIndexPath *resetIndexPath = [NSIndexPath indexPathForRow:LauncherBackgroundRowReset inSection:0];
    [self.tableView reloadRowsAtIndexPaths:@[rotateIndexPath, resetIndexPath] withRowAnimation:UITableViewRowAnimationNone];
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
        slider.minimumValue = 50;
        slider.maximumValue = 250;
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
    cell.accessoryView = nil;
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
        case LauncherBackgroundRowRotate: {
            if (![cell.accessoryView isKindOfClass:UISwitch.class]) {
                UISwitch *toggle = [UISwitch new];
                [toggle addTarget:self action:@selector(backgroundRotateChanged:) forControlEvents:UIControlEventValueChanged];
                PLApplyCompactSwitch(toggle);
                cell.accessoryView = toggle;
            }
            UISwitch *toggle = (UISwitch *)cell.accessoryView;
            toggle.on = getLauncherBackgroundVideoRotateEnabled();
            toggle.enabled = self.hasSelectedVideo;
            cell.imageView.image = [UIImage systemImageNamed:@"rotate.right"];
            cell.textLabel.text = localize(@"preference.title.launcher_background_rotate", nil);
            cell.selectionStyle = UITableViewCellSelectionStyleGray;
            cell.userInteractionEnabled = self.hasSelectedVideo;
            cell.textLabel.enabled = self.hasSelectedVideo;
            break;
        }
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
    UIImagePickerController *picker = [UIImagePickerController new];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.mediaTypes = @[
        UTTypeMovie.identifier,
        UTTypeVideo.identifier,
        UTTypeMPEG4Movie.identifier,
        UTTypeQuickTimeMovie.identifier
    ];
    picker.videoQuality = UIImagePickerControllerQualityTypeHigh;
    picker.delegate = self;
    picker.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:NO];
    if (self.importingVideo) {
        return;
    }

    if (indexPath.row == LauncherBackgroundRowChoose) {
        [self presentVideoPicker];
    } else if (indexPath.row == LauncherBackgroundRowClear && getLauncherBackgroundVideoPath().length > 0) {
        clearLauncherBackgroundVideo();
        [self.tableView reloadData];
    } else if (indexPath.row == LauncherBackgroundRowRotate && self.hasSelectedVideo) {
        BOOL enabled = !getLauncherBackgroundVideoRotateEnabled();
        setLauncherBackgroundVideoRotateEnabled(enabled);
        NSIndexPath *resetIndexPath = [NSIndexPath indexPathForRow:LauncherBackgroundRowReset inSection:0];
        [self.tableView reloadRowsAtIndexPaths:@[indexPath, resetIndexPath] withRowAnimation:UITableViewRowAnimationNone];
    } else if (indexPath.row == LauncherBackgroundRowReset && self.hasCustomAdjustments) {
        resetLauncherBackgroundVideoAdjustments();
        [self.tableView reloadData];
    }
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey, id> *)info {
    NSURL *url = info[UIImagePickerControllerMediaURL];
    if (!url) {
        [picker dismissViewControllerAnimated:YES completion:nil];
        showDialog(localize(@"Error", nil), @"Unable to load the selected video.");
        return;
    }

    [picker dismissViewControllerAnimated:YES completion:^{
        [self beginImportVideoFromURL:url];
    }];
}

@end

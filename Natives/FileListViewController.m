#import "FileListViewController.h"
#import "LauncherPreferences.h"
#import "utils.h"

@interface FileListViewController () {
}

@property(nonatomic) NSMutableArray *fileList;

@end

@implementation FileListViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;
    self.tableView.backgroundColor = UIColor.clearColor;

    if (self.fileList == nil) {
        self.fileList = [NSMutableArray array];
    } else {
        [self.fileList removeAllObjects];
    }

    // List files
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *files = [fm contentsOfDirectoryAtPath:self.listPath error:nil];
    for(NSString *file in files) {
        NSString *path = [self.listPath stringByAppendingPathComponent:file];
        BOOL isDir = NO;
        [fm fileExistsAtPath:path isDirectory:(&isDir)];
        if(!isDir && [file hasSuffix:@".json"]) {
            [self.fileList addObject:[file stringByDeletingPathExtension]];
        }
    }

    PLApplyCompactTableLayout(self.tableView, 40);
    self.preferredContentSize = PLCompactPopoverSize(300, 220);
    [self.tableView setSeparatorStyle:getLauncherOutlineControlsEnabled() ?
        UITableViewCellSeparatorStyleNone :
        UITableViewCellSeparatorStyleSingleLine];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    PLApplyLauncherViewChrome(self.view);
    if (self.presentationController.presentedView) {
        PLApplyLauncherViewChrome(self.presentationController.presentedView);
    }
    if (self.presentationController.containerView) {
        PLApplyLauncherViewChrome(self.presentationController.containerView);
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.fileList.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell"];

    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"cell"];
    }
    PLApplyCompactTableCell(cell);
    if (getLauncherOutlineControlsEnabled()) {
        PLApplyLauncherCardChrome(cell, NO, NSDirectionalEdgeInsetsMake(0, 0, 0, 0), 10);
    } else if (@available(iOS 14.0, *)) {
        cell.backgroundConfiguration = nil;
    }

    cell.textLabel.text = [self.fileList objectAtIndex:indexPath.row];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [self dismissViewControllerAnimated:YES completion:nil];

    self.whenItemSelected(self.fileList [indexPath.row]);
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        NSString *str = [self.fileList objectAtIndex:indexPath.row];
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *path = [NSString stringWithFormat:@"%@/%@.json", self.listPath, str];
        if (self.whenDelete != nil) {
            self.whenDelete(path);
        }
        [fm removeItemAtPath:path error:nil];
        [self.fileList removeObjectAtIndex:indexPath.row];
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
    }
}

@end

#import "AIModDoctorService.h"

#import "LauncherPreferences.h"
#import "UnzipKit.h"
#import "utils.h"

static NSString *const AIModDoctorErrorDomain = @"AIModDoctorErrorDomain";
static NSString *const AIModDoctorDefaultBaseURL = @"https://api.openai.com/v1";
static NSString *const AIModDoctorDefaultModel = @"gpt-5.4-mini";
static NSUInteger const AIModDoctorMaxSteps = 8;

typedef NS_ENUM(NSInteger, AIModDoctorErrorCode) {
    AIModDoctorErrorCodeConfiguration = 1,
    AIModDoctorErrorCodeNetwork,
    AIModDoctorErrorCodeAPI,
    AIModDoctorErrorCodeValidation,
    AIModDoctorErrorCodeTool
};

static NSString *AIModDoctorJSONString(id object) {
    if (!object) {
        return @"null";
    }

    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingPrettyPrinted error:nil];
    if (!data) {
        return @"{}";
    }
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"{}";
}

static NSString *AIModDoctorEnsureTrailingNewline(NSString *string) {
    if (string.length == 0 || [string hasSuffix:@"\n"]) {
        return string ?: @"";
    }
    return [string stringByAppendingString:@"\n"];
}

@interface AIModDoctorService()
@property(nonatomic, copy) NSString *homeDirectory;
@property(nonatomic, copy) NSString *sessionDirectory;
@property(nonatomic, copy) NSString *backupDirectory;
@property(nonatomic, copy) NSString *quarantineDirectory;
@property(nonatomic, copy) NSString *extractDirectory;
@property(nonatomic, copy) NSArray<NSString *> *readRoots;
@property(nonatomic, copy) NSArray<NSString *> *writeRoots;
@property(nonatomic) BOOL fullAccessEnabled;
@property(nonatomic) AIModDoctorRunMode currentMode;
@end

@implementation AIModDoctorService

- (void)runWithMode:(AIModDoctorRunMode)mode
         completion:(void (^)(NSString *summary, NSError *error))completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSError *error = nil;
        self.currentMode = mode;
        NSString *summary = [self runSynchronouslyWithError:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                completion(summary, error);
            }
        });
    });
}

- (NSString *)runSynchronouslyWithError:(NSError **)error {
    if (!getPrefBool(@"ai.ai_enabled")) {
        if (error) {
            *error = [self errorWithCode:AIModDoctorErrorCodeConfiguration description:@"AI Mod Doctor is disabled in Settings."];
        }
        return nil;
    }

    NSString *apiKey = [self apiKey];
    if (apiKey.length == 0) {
        if (error) {
            *error = [self errorWithCode:AIModDoctorErrorCodeConfiguration description:@"Missing OpenAI API key in Settings."];
        }
        return nil;
    }

    if (![self prepareSession:error]) {
        return nil;
    }

    [self emitEvent:@"[AI] Session %@", self.sessionDirectory.lastPathComponent];
    [self emitEvent:@"[AI] Mode: %@", self.currentMode == AIModDoctorRunModeAutoRepair ? @"auto repair" : @"analyze only"];

    NSMutableDictionary *requestBody = [@{
        @"model": [self modelName],
        @"input": [self initialMessages],
        @"tools": [self toolDefinitions]
    } mutableCopy];

    NSDictionary *response = [self sendResponsesRequest:requestBody error:error];
    if (!response) {
        return nil;
    }

    for (NSUInteger step = 0; step < AIModDoctorMaxSteps; step++) {
        NSArray<NSDictionary *> *calls = [self functionCallsFromResponse:response];
        if (calls.count == 0) {
            NSString *summary = [self summaryFromResponse:response];
            if (summary.length == 0) {
                summary = @"AI Mod Doctor finished without a textual summary.";
            }
            [self emitEvent:@"[AI] Completed"];
            return summary;
        }

        [self emitEvent:@"[AI] Step %lu: %lu tool call(s)", (unsigned long)(step + 1), (unsigned long)calls.count];
        NSMutableArray<NSDictionary *> *toolOutputs = [NSMutableArray arrayWithCapacity:calls.count];
        for (NSDictionary *call in calls) {
            NSDictionary *toolOutput = [self executeToolCall:call];
            NSString *callId = call[@"call_id"] ?: call[@"id"];
            [toolOutputs addObject:@{
                @"type": @"function_call_output",
                @"call_id": callId ?: @"unknown",
                @"output": AIModDoctorJSONString(toolOutput)
            }];
        }

        NSString *previousResponseId = response[@"id"];
        requestBody = [@{
            @"model": [self modelName],
            @"previous_response_id": previousResponseId ?: @"",
            @"input": toolOutputs,
            @"tools": [self toolDefinitions]
        } mutableCopy];

        response = [self sendResponsesRequest:requestBody error:error];
        if (!response) {
            return nil;
        }
    }

    if (error) {
        *error = [self errorWithCode:AIModDoctorErrorCodeAPI description:@"AI Mod Doctor exceeded its tool step limit."];
    }
    return nil;
}

#pragma mark Configuration

- (NSString *)apiKey {
    NSString *value = [getPrefObject(@"ai.ai_api_key") description];
    return [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

- (NSString *)modelName {
    NSString *value = [getPrefObject(@"ai.ai_model") description];
    value = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return value.length > 0 ? value : AIModDoctorDefaultModel;
}

- (NSString *)baseURLString {
    NSString *value = [getPrefObject(@"ai.ai_base_url") description];
    value = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (value.length == 0) {
        value = AIModDoctorDefaultBaseURL;
    }
    while ([value hasSuffix:@"/"]) {
        value = [value substringToIndex:value.length - 1];
    }
    return value;
}

- (NSURL *)responsesURL {
    NSString *baseURL = [self baseURLString];
    if ([baseURL hasSuffix:@"/responses"]) {
        return [NSURL URLWithString:baseURL];
    }
    return [NSURL URLWithString:[baseURL stringByAppendingString:@"/responses"]];
}

- (BOOL)prepareSession:(NSError **)error {
    self.homeDirectory = @(getenv("POJAV_HOME"));
    if (self.homeDirectory.length == 0) {
        if (error) {
            *error = [self errorWithCode:AIModDoctorErrorCodeConfiguration description:@"POJAV_HOME is not available."];
        }
        return NO;
    }

    self.homeDirectory = self.homeDirectory.stringByStandardizingPath;
    self.instanceDirectory = self.instanceDirectory.stringByStandardizingPath;
    self.gameDirectory = self.gameDirectory.stringByStandardizingPath;
    self.sharedModsDirectory = self.sharedModsDirectory.stringByStandardizingPath;
    id fullAccessPref = getPrefObject(@"ai.ai_full_access");
    self.fullAccessEnabled = fullAccessPref ? [fullAccessPref boolValue] : YES;

    NSString *sessionRoot = [self.homeDirectory stringByAppendingPathComponent:@"ai_mod_doctor"];
    NSString *sessionName = [NSString stringWithFormat:@"%@-%@", [self timestampString], [NSUUID UUID].UUIDString.lowercaseString];
    self.sessionDirectory = [sessionRoot stringByAppendingPathComponent:sessionName];
    self.backupDirectory = [self.sessionDirectory stringByAppendingPathComponent:@"backups"];
    self.quarantineDirectory = [self.sessionDirectory stringByAppendingPathComponent:@"quarantine"];
    self.extractDirectory = [self.sessionDirectory stringByAppendingPathComponent:@"extracted"];

    for (NSString *directory in @[sessionRoot, self.sessionDirectory, self.backupDirectory, self.quarantineDirectory, self.extractDirectory]) {
        if (![NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:error]) {
            return NO;
        }
    }

    NSMutableOrderedSet<NSString *> *readRoots = [NSMutableOrderedSet orderedSetWithArray:@[
        self.sessionDirectory ?: @"",
        self.instanceDirectory ?: @"",
        self.gameDirectory ?: @"",
        self.sharedModsDirectory ?: @"",
        self.homeDirectory ?: @""
    ]];
    [readRoots removeObject:@""];
    self.readRoots = readRoots.array;

    NSMutableOrderedSet<NSString *> *writeRoots = [NSMutableOrderedSet orderedSetWithArray:@[
        self.sessionDirectory ?: @"",
        self.instanceDirectory ?: @"",
        self.gameDirectory ?: @"",
        self.sharedModsDirectory ?: @""
    ]];
    [writeRoots removeObject:@""];
    if (self.fullAccessEnabled) {
        [writeRoots addObject:self.homeDirectory];
    }
    self.writeRoots = writeRoots.array;
    return YES;
}

- (NSString *)timestampString {
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.dateFormat = @"yyyyMMdd-HHmmss";
    return [formatter stringFromDate:[NSDate date]];
}

#pragma mark Prompting

- (NSArray<NSDictionary *> *)initialMessages {
    NSString *modeText = self.currentMode == AIModDoctorRunModeAutoRepair ? @"automatic diagnosis and repair" : @"read-only diagnosis";
    NSString *systemPrompt = [NSString stringWithFormat:
        @"You are AI System Doctor inside an iOS Minecraft launcher. You diagnose and repair the launcher's entire data area for the current user: mods, configs, shader packs, resource packs, data packs, profiles, control layouts, accounts, logs, runtime settings, and other files inside the allowed roots.\n"
        @"Use tools aggressively to inspect logs, directories, configs, text files, archives, launcher preferences, and profile metadata. Prefer minimal fixes. Disable or quarantine a likely broken component before deleting it. Use delete only if the file is obviously broken, duplicated, or the safer options are insufficient.\n"
        @"If you extract and patch an archive, repack it back to the original destination. You may move, copy, restore, create directories, download replacement files, and edit text files within the allowed roots. Always keep changes inside the allowed write roots. Never ask the user for permission; act within the tools you have. Finish with a concise summary of findings, actions, and backup or quarantine paths.\n"
        @"Current requested mode: %@.", modeText];

    NSString *userPrompt = [self contextSummary];
    return @[
        @{
            @"role": @"system",
            @"content": @[@{
                @"type": @"input_text",
                @"text": systemPrompt
            }]
        },
        @{
            @"role": @"user",
            @"content": @[@{
                @"type": @"input_text",
                @"text": userPrompt
            }]
        }
    ];
}

- (NSString *)contextSummary {
    NSString *latestLog = [self tailOfFileAtPath:[self.homeDirectory stringByAppendingPathComponent:@"latestlog.txt"] maxCharacters:12000];
    NSString *oldLog = [self tailOfFileAtPath:[self.homeDirectory stringByAppendingPathComponent:@"latestlog.old.txt"] maxCharacters:8000];
    NSString *profileModsDirectory = [self.gameDirectory stringByAppendingPathComponent:@"mods"];
    NSString *configDirectory = [self.gameDirectory stringByAppendingPathComponent:@"config"];
    NSString *profilesPath = [@(getenv("POJAV_GAME_DIR")) stringByAppendingPathComponent:@"launcher_profiles.json"];
    NSString *launcherPrefsPath = [self.homeDirectory stringByAppendingPathComponent:@"launcher_preferences_v2.plist"];
    NSString *accountsPath = [self.homeDirectory stringByAppendingPathComponent:@"accounts"];
    NSString *controlMapPath = [self.homeDirectory stringByAppendingPathComponent:@"controlmap"];
    NSString *runtimePath = [self.homeDirectory stringByAppendingPathComponent:@"java_runtimes"];

    NSMutableString *summary = [NSMutableString string];
    [summary appendFormat:@"Profile: %@\n", self.profileName.length > 0 ? self.profileName : @"Unnamed profile"];
    [summary appendFormat:@"Minecraft version: %@\n", self.profile[@"lastVersionId"] ?: @"(unknown)"];
    [summary appendFormat:@"Game directory: %@\n", self.gameDirectory ?: @"(missing)"];
    [summary appendFormat:@"Instance directory: %@\n", self.instanceDirectory ?: @"(missing)"];
    if (self.sharedModsDirectory.length > 0 && ![self.sharedModsDirectory isEqualToString:profileModsDirectory]) {
        [summary appendFormat:@"Shared mods directory: %@\n", self.sharedModsDirectory];
    }
    [summary appendFormat:@"AI session workspace: %@\n", self.sessionDirectory];
    [summary appendFormat:@"Allowed read roots: %@\n", [self.readRoots componentsJoinedByString:@", "]];
    [summary appendFormat:@"Allowed write roots: %@\n", [self.writeRoots componentsJoinedByString:@", "]];
    [summary appendString:@"\nDirectory snapshots:\n"];
    [summary appendFormat:@"- Profile mods: %@\n", [self directorySnapshotForPath:profileModsDirectory]];
    if (self.sharedModsDirectory.length > 0 && ![self.sharedModsDirectory isEqualToString:profileModsDirectory]) {
        [summary appendFormat:@"- Shared mods: %@\n", [self directorySnapshotForPath:self.sharedModsDirectory]];
    }
    [summary appendFormat:@"- Config: %@\n", [self directorySnapshotForPath:configDirectory]];
    [summary appendFormat:@"- Resource packs: %@\n", [self directorySnapshotForPath:[self.gameDirectory stringByAppendingPathComponent:@"resourcepacks"]]];
    [summary appendFormat:@"- Shader packs: %@\n", [self directorySnapshotForPath:[self.gameDirectory stringByAppendingPathComponent:@"shaderpacks"]]];
    [summary appendFormat:@"- Data packs: %@\n", [self directorySnapshotForPath:[self.gameDirectory stringByAppendingPathComponent:@"datapacks"]]];
    [summary appendFormat:@"- Accounts: %@\n", [self directorySnapshotForPath:accountsPath]];
    [summary appendFormat:@"- Control maps: %@\n", [self directorySnapshotForPath:controlMapPath]];
    [summary appendFormat:@"- Java runtimes: %@\n", [self directorySnapshotForPath:runtimePath]];
    [summary appendFormat:@"- Launcher profiles file: %@\n", [self fileSnapshotForPath:profilesPath]];
    [summary appendFormat:@"- Launcher preferences file: %@\n", [self fileSnapshotForPath:launcherPrefsPath]];

    [summary appendString:@"\nRecent latestlog.txt tail:\n"];
    [summary appendString:AIModDoctorEnsureTrailingNewline(latestLog.length > 0 ? latestLog : @"(latestlog.txt missing or empty)\n")];
    if (oldLog.length > 0) {
        [summary appendString:@"\nRecent latestlog.old.txt tail:\n"];
        [summary appendString:AIModDoctorEnsureTrailingNewline(oldLog)];
    }
    return summary;
}

- (NSString *)directorySnapshotForPath:(NSString *)path {
    BOOL isDirectory = NO;
    if (![NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDirectory] || !isDirectory) {
        return @"missing";
    }

    NSArray<NSString *> *files = [NSFileManager.defaultManager contentsOfDirectoryAtPath:path error:nil];
    if (files.count == 0) {
        return @"empty";
    }

    NSArray<NSString *> *sortedFiles = [files sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
    NSUInteger limit = MIN(sortedFiles.count, (NSUInteger)20);
    NSArray<NSString *> *prefix = [sortedFiles subarrayWithRange:NSMakeRange(0, limit)];
    NSString *joined = [prefix componentsJoinedByString:@", "];
    if (sortedFiles.count > limit) {
        joined = [joined stringByAppendingFormat:@", ... (%lu total)", (unsigned long)sortedFiles.count];
    }
    return joined;
}

- (NSString *)fileSnapshotForPath:(NSString *)path {
    NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
    if (!attributes) {
        return @"missing";
    }
    return [NSString stringWithFormat:@"%@ bytes", attributes[NSFileSize] ?: @0];
}

- (NSString *)tailOfFileAtPath:(NSString *)path maxCharacters:(NSUInteger)maxCharacters {
    NSError *error = nil;
    NSString *content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];
    if (!content) {
        content = [NSString stringWithContentsOfFile:path encoding:NSISOLatin1StringEncoding error:nil];
    }
    if (content.length == 0) {
        return @"";
    }
    if (content.length <= maxCharacters) {
        return content;
    }
    return [content substringFromIndex:content.length - maxCharacters];
}

#pragma mark Responses API

- (NSDictionary *)sendResponsesRequest:(NSDictionary *)body error:(NSError **)error {
    NSURL *url = [self responsesURL];
    if (!url) {
        if (error) {
            *error = [self errorWithCode:AIModDoctorErrorCodeConfiguration description:@"Invalid OpenAI base URL."];
        }
        return nil;
    }

    NSData *requestData = [NSJSONSerialization dataWithJSONObject:body options:0 error:error];
    if (!requestData) {
        return nil;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    request.timeoutInterval = 120;
    request.HTTPBody = requestData;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", [self apiKey]] forHTTPHeaderField:@"Authorization"];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSDictionary *responseObject = nil;
    __block NSError *requestError = nil;

    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithRequest:request
                                                               completionHandler:^(NSData *data, NSURLResponse *response, NSError *networkError) {
        if (networkError) {
            requestError = [self errorWithCode:AIModDoctorErrorCodeNetwork description:networkError.localizedDescription];
            dispatch_semaphore_signal(semaphore);
            return;
        }

        NSHTTPURLResponse *httpResponse = (id)response;
        NSDictionary *json = nil;
        if (data.length > 0) {
            json = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
        }

        if (httpResponse.statusCode < 200 || httpResponse.statusCode >= 300) {
            NSString *message = json[@"error"][@"message"];
            if (message.length == 0) {
                message = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            }
            requestError = [self errorWithCode:AIModDoctorErrorCodeAPI description:message.length > 0 ? message : @"OpenAI request failed."];
            dispatch_semaphore_signal(semaphore);
            return;
        }

        if (![json isKindOfClass:NSDictionary.class]) {
            requestError = [self errorWithCode:AIModDoctorErrorCodeAPI description:@"OpenAI returned an invalid JSON payload."];
            dispatch_semaphore_signal(semaphore);
            return;
        }

        responseObject = json;
        dispatch_semaphore_signal(semaphore);
    }];
    [task resume];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);

    if (requestError) {
        [self emitEvent:@"[AI] Request failed: %@", requestError.localizedDescription];
        if (error) {
            *error = requestError;
        }
        return nil;
    }

    [self emitEvent:@"[AI] Response %@", responseObject[@"id"] ?: @"(no id)"];
    return responseObject;
}

- (NSArray<NSDictionary *> *)functionCallsFromResponse:(NSDictionary *)response {
    NSMutableArray<NSDictionary *> *calls = [NSMutableArray array];
    for (NSDictionary *item in response[@"output"]) {
        if (![item isKindOfClass:NSDictionary.class]) {
            continue;
        }
        if ([item[@"type"] isEqualToString:@"function_call"]) {
            [calls addObject:item];
        }
    }
    return calls;
}

- (NSString *)summaryFromResponse:(NSDictionary *)response {
    NSString *summary = response[@"output_text"];
    if ([summary isKindOfClass:NSString.class] && summary.length > 0) {
        return summary;
    }

    NSMutableArray<NSString *> *fragments = [NSMutableArray array];
    for (NSDictionary *item in response[@"output"]) {
        if (![item isKindOfClass:NSDictionary.class] || ![item[@"type"] isEqualToString:@"message"]) {
            continue;
        }
        for (NSDictionary *content in item[@"content"]) {
            if (![content isKindOfClass:NSDictionary.class]) {
                continue;
            }
            id text = content[@"text"];
            if ([text isKindOfClass:NSString.class] && [text length] > 0) {
                [fragments addObject:text];
            } else if ([text isKindOfClass:NSDictionary.class]) {
                NSString *value = text[@"value"];
                if (value.length > 0) {
                    [fragments addObject:value];
                }
            }
        }
    }
    return [fragments componentsJoinedByString:@"\n"];
}

#pragma mark Tools

- (NSArray<NSDictionary *> *)toolDefinitions {
    NSMutableArray<NSDictionary *> *tools = [NSMutableArray array];
    [tools addObject:[self toolNamed:@"list_directory"
                         description:@"List files and folders inside an allowed directory."
                         properties:@{
                             @"path": @{@"type": @"string", @"description": @"Absolute path or path relative to the game directory."},
                             @"recursive": @{@"type": @"boolean"},
                             @"limit": @{@"type": @"integer", @"minimum": @1, @"maximum": @200}
                         }
                           required:@[@"path"]]];
    [tools addObject:[self toolNamed:@"read_text_file"
                         description:@"Read a text file such as logs, json, toml, cfg, properties, or shader config."
                         properties:@{
                             @"path": @{@"type": @"string"},
                             @"max_characters": @{@"type": @"integer", @"minimum": @256, @"maximum": @24000}
                         }
                           required:@[@"path"]]];
    [tools addObject:[self toolNamed:@"search_text"
                         description:@"Search filenames and text file contents under an allowed directory."
                         properties:@{
                             @"path": @{@"type": @"string"},
                             @"pattern": @{@"type": @"string"},
                             @"limit": @{@"type": @"integer", @"minimum": @1, @"maximum": @200}
                         }
                           required:@[@"path", @"pattern"]]];
    [tools addObject:[self toolNamed:@"read_archive_entries"
                         description:@"List filenames inside a zip or jar archive."
                         properties:@{
                             @"path": @{@"type": @"string"},
                             @"contains": @{@"type": @"string"},
                             @"limit": @{@"type": @"integer", @"minimum": @1, @"maximum": @400}
                         }
                           required:@[@"path"]]];
    [tools addObject:[self toolNamed:@"read_archive_text"
                         description:@"Read a UTF-8 text file from inside a zip or jar archive."
                         properties:@{
                             @"path": @{@"type": @"string"},
                             @"entry": @{@"type": @"string"},
                             @"max_characters": @{@"type": @"integer", @"minimum": @256, @"maximum": @24000}
                         }
                           required:@[@"path", @"entry"]]];

    if (self.currentMode == AIModDoctorRunModeAutoRepair) {
        [tools addObjectsFromArray:@[
            [self toolNamed:@"backup_item"
                 description:@"Copy a file or folder into the AI session backup directory."
                 properties:@{
                     @"path": @{@"type": @"string"}
                 }
                   required:@[@"path"]],
            [self toolNamed:@"quarantine_item"
                 description:@"Move a file or folder into the AI session quarantine directory."
                 properties:@{
                     @"path": @{@"type": @"string"},
                     @"reason": @{@"type": @"string"}
                 }
                   required:@[@"path"]],
            [self toolNamed:@"make_directory"
                 description:@"Create a directory and any missing parent directories."
                 properties:@{
                     @"path": @{@"type": @"string"}
                 }
                   required:@[@"path"]],
            [self toolNamed:@"copy_item"
                 description:@"Copy a file or directory to a new destination."
                 properties:@{
                     @"source_path": @{@"type": @"string"},
                     @"destination_path": @{@"type": @"string"}
                 }
                   required:@[@"source_path", @"destination_path"]],
            [self toolNamed:@"move_item"
                 description:@"Move or rename a file or directory."
                 properties:@{
                     @"source_path": @{@"type": @"string"},
                     @"destination_path": @{@"type": @"string"}
                 }
                   required:@[@"source_path", @"destination_path"]],
            [self toolNamed:@"disable_item"
                 description:@"Disable a mod-like file by renaming it to add the .disabled suffix."
                 properties:@{
                     @"path": @{@"type": @"string"}
                 }
                   required:@[@"path"]],
            [self toolNamed:@"delete_item"
                 description:@"Delete a file or folder. This tool automatically creates a backup copy first."
                 properties:@{
                     @"path": @{@"type": @"string"}
                 }
                   required:@[@"path"]],
            [self toolNamed:@"write_text_file"
                 description:@"Create or overwrite a UTF-8 text file. Existing files are backed up first."
                 properties:@{
                     @"path": @{@"type": @"string"},
                     @"content": @{@"type": @"string"}
                 }
                   required:@[@"path", @"content"]],
            [self toolNamed:@"replace_in_text_file"
                 description:@"Replace exact text in a UTF-8 text file. Existing files are backed up first."
                 properties:@{
                     @"path": @{@"type": @"string"},
                     @"old_text": @{@"type": @"string"},
                     @"new_text": @{@"type": @"string"}
                 }
                   required:@[@"path", @"old_text", @"new_text"]],
            [self toolNamed:@"extract_archive"
                 description:@"Extract a zip or jar archive into the AI session workspace for inspection and patching."
                 properties:@{
                     @"path": @{@"type": @"string"},
                     @"tag": @{@"type": @"string"}
                 }
                   required:@[@"path"]],
            [self toolNamed:@"download_file"
                 description:@"Download a file from a URL to an allowed destination path."
                 properties:@{
                     @"url": @{@"type": @"string"},
                     @"destination_path": @{@"type": @"string"}
                 }
                   required:@[@"url", @"destination_path"]],
            [self toolNamed:@"repack_archive"
                 description:@"Repack a directory from the AI session workspace back into a zip or jar destination. The destination is backed up first if it already exists."
                 properties:@{
                     @"source_directory": @{@"type": @"string"},
                     @"destination_path": @{@"type": @"string"}
                 }
                   required:@[@"source_directory", @"destination_path"]]
        ]];
    }

    return tools;
}

- (NSDictionary *)toolNamed:(NSString *)name
                description:(NSString *)description
                 properties:(NSDictionary *)properties
                   required:(NSArray<NSString *> *)required {
    return @{
        @"type": @"function",
        @"name": name,
        @"description": description,
        @"strict": @YES,
        @"parameters": @{
            @"type": @"object",
            @"properties": properties,
            @"required": required,
            @"additionalProperties": @NO
        }
    };
}

- (NSDictionary *)executeToolCall:(NSDictionary *)call {
    NSString *name = call[@"name"] ?: @"unknown";
    NSDictionary *arguments = [self dictionaryFromArguments:call[@"arguments"]];
    if (!arguments) {
        [self emitEvent:@"[Tool] %@ failed: invalid JSON arguments", name];
        return @{@"ok": @NO, @"error": @"Invalid JSON arguments."};
    }

    [self emitEvent:@"[Tool] %@ %@", name, AIModDoctorJSONString(arguments)];
    NSDictionary *result = nil;
    if ([name isEqualToString:@"list_directory"]) {
        result = [self toolListDirectory:arguments];
    } else if ([name isEqualToString:@"read_text_file"]) {
        result = [self toolReadTextFile:arguments];
    } else if ([name isEqualToString:@"search_text"]) {
        result = [self toolSearchText:arguments];
    } else if ([name isEqualToString:@"read_archive_entries"]) {
        result = [self toolReadArchiveEntries:arguments];
    } else if ([name isEqualToString:@"read_archive_text"]) {
        result = [self toolReadArchiveText:arguments];
    } else if ([name isEqualToString:@"backup_item"]) {
        result = [self toolBackupItem:arguments];
    } else if ([name isEqualToString:@"quarantine_item"]) {
        result = [self toolQuarantineItem:arguments];
    } else if ([name isEqualToString:@"make_directory"]) {
        result = [self toolMakeDirectory:arguments];
    } else if ([name isEqualToString:@"copy_item"]) {
        result = [self toolCopyItem:arguments];
    } else if ([name isEqualToString:@"move_item"]) {
        result = [self toolMoveItem:arguments];
    } else if ([name isEqualToString:@"disable_item"]) {
        result = [self toolDisableItem:arguments];
    } else if ([name isEqualToString:@"delete_item"]) {
        result = [self toolDeleteItem:arguments];
    } else if ([name isEqualToString:@"write_text_file"]) {
        result = [self toolWriteTextFile:arguments];
    } else if ([name isEqualToString:@"replace_in_text_file"]) {
        result = [self toolReplaceInTextFile:arguments];
    } else if ([name isEqualToString:@"extract_archive"]) {
        result = [self toolExtractArchive:arguments];
    } else if ([name isEqualToString:@"download_file"]) {
        result = [self toolDownloadFile:arguments];
    } else if ([name isEqualToString:@"repack_archive"]) {
        result = [self toolRepackArchive:arguments];
    } else {
        result = @{@"ok": @NO, @"error": [NSString stringWithFormat:@"Unknown tool: %@", name]};
    }

    [self emitEvent:@"[Tool] %@ result %@", name, result[@"ok"]];
    return result;
}

- (NSDictionary *)toolListDirectory:(NSDictionary *)arguments {
    NSError *error = nil;
    NSString *path = [self validatedPath:arguments[@"path"] write:NO error:&error];
    if (!path) {
        return [self toolError:error];
    }

    BOOL recursive = [arguments[@"recursive"] boolValue];
    NSUInteger limit = [self clampedInteger:arguments[@"limit"] defaultValue:50 min:1 max:200];
    BOOL isDirectory = NO;
    if (![NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDirectory] || !isDirectory) {
        return [self toolErrorMessage:@"Directory does not exist."];
    }

    NSMutableArray<NSDictionary *> *entries = [NSMutableArray array];
    BOOL truncated = NO;
    if (recursive) {
        NSDirectoryEnumerator *enumerator = [NSFileManager.defaultManager enumeratorAtPath:path];
        NSString *relativePath = nil;
        while ((relativePath = enumerator.nextObject)) {
            NSString *absolutePath = [path stringByAppendingPathComponent:relativePath];
            NSDictionary *entry = [self entryInfoForPath:absolutePath relativeTo:path];
            if (!entry) {
                continue;
            }
            [entries addObject:entry];
            if (entries.count >= limit) {
                truncated = enumerator.nextObject != nil;
                break;
            }
        }
    } else {
        NSArray<NSString *> *files = [[NSFileManager.defaultManager contentsOfDirectoryAtPath:path error:nil] sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
        for (NSString *fileName in files) {
            NSDictionary *entry = [self entryInfoForPath:[path stringByAppendingPathComponent:fileName] relativeTo:path];
            if (!entry) {
                continue;
            }
            [entries addObject:entry];
            if (entries.count >= limit) {
                truncated = files.count > limit;
                break;
            }
        }
    }

    return @{
        @"ok": @YES,
        @"path": path,
        @"recursive": @(recursive),
        @"entries": entries,
        @"truncated": @(truncated)
    };
}

- (NSDictionary *)toolReadTextFile:(NSDictionary *)arguments {
    NSError *error = nil;
    NSString *path = [self validatedPath:arguments[@"path"] write:NO error:&error];
    if (!path) {
        return [self toolError:error];
    }

    NSUInteger maxCharacters = [self clampedInteger:arguments[@"max_characters"] defaultValue:8000 min:256 max:24000];
    NSString *content = [self readTextFileAtPath:path error:&error];
    if (!content) {
        return [self toolError:error];
    }

    BOOL truncated = NO;
    if (content.length > maxCharacters) {
        content = [content substringFromIndex:content.length - maxCharacters];
        truncated = YES;
    }
    return @{
        @"ok": @YES,
        @"path": path,
        @"truncated": @(truncated),
        @"content": content
    };
}

- (NSDictionary *)toolSearchText:(NSDictionary *)arguments {
    NSError *error = nil;
    NSString *path = [self validatedPath:arguments[@"path"] write:NO error:&error];
    if (!path) {
        return [self toolError:error];
    }

    NSString *pattern = [arguments[@"pattern"] description] ?: @"";
    if (pattern.length == 0) {
        return [self toolErrorMessage:@"pattern must not be empty."];
    }

    NSUInteger limit = [self clampedInteger:arguments[@"limit"] defaultValue:50 min:1 max:200];
    NSMutableArray<NSDictionary *> *matches = [NSMutableArray array];
    NSDirectoryEnumerator *enumerator = [NSFileManager.defaultManager enumeratorAtPath:path];
    NSString *relativePath = nil;
    while ((relativePath = [enumerator nextObject])) {
        NSString *absolutePath = [path stringByAppendingPathComponent:relativePath];
        BOOL isDirectory = NO;
        if (![NSFileManager.defaultManager fileExistsAtPath:absolutePath isDirectory:&isDirectory] || isDirectory) {
            continue;
        }

        BOOL filenameMatch = [relativePath rangeOfString:pattern options:NSCaseInsensitiveSearch].location != NSNotFound;
        NSMutableDictionary *match = nil;
        if (filenameMatch) {
            match = [@{
                @"path": absolutePath,
                @"relative_path": relativePath,
                @"match_type": @"filename"
            } mutableCopy];
        }

        NSString *extension = absolutePath.pathExtension.lowercaseString;
        BOOL looksText = [@[@"txt", @"log", @"json", @"toml", @"cfg", @"conf", @"properties", @"ini", @"xml", @"plist", @"md"] containsObject:extension];
        if (looksText) {
            NSString *content = [self readTextFileAtPath:absolutePath error:nil];
            NSRange range = [content rangeOfString:pattern options:NSCaseInsensitiveSearch];
            if (range.location != NSNotFound) {
                if (!match) {
                    match = [@{
                        @"path": absolutePath,
                        @"relative_path": relativePath,
                        @"match_type": @"content"
                    } mutableCopy];
                } else {
                    match[@"match_type"] = @"filename+content";
                }
                NSUInteger start = range.location > 80 ? range.location - 80 : 0;
                NSUInteger length = MIN((NSUInteger)200, content.length - start);
                match[@"snippet"] = [content substringWithRange:NSMakeRange(start, length)];
            }
        }

        if (match) {
            [matches addObject:match];
            if (matches.count >= limit) {
                break;
            }
        }
    }

    return @{
        @"ok": @YES,
        @"path": path,
        @"pattern": pattern,
        @"matches": matches,
        @"truncated": @([matches count] >= limit)
    };
}

- (NSDictionary *)toolReadArchiveEntries:(NSDictionary *)arguments {
    NSError *error = nil;
    NSString *path = [self validatedPath:arguments[@"path"] write:NO error:&error];
    if (!path) {
        return [self toolError:error];
    }

    UZKArchive *archive = [[UZKArchive alloc] initWithPath:path error:&error];
    if (!archive) {
        return [self toolError:error];
    }

    NSArray<NSString *> *filenames = [archive listFilenames:&error];
    if (!filenames) {
        return [self toolError:error];
    }

    NSString *contains = [arguments[@"contains"] description];
    NSMutableArray<NSString *> *matches = [NSMutableArray array];
    NSUInteger limit = [self clampedInteger:arguments[@"limit"] defaultValue:200 min:1 max:400];
    for (NSString *entry in filenames) {
        if (contains.length > 0 && [entry rangeOfString:contains options:NSCaseInsensitiveSearch].location == NSNotFound) {
            continue;
        }
        [matches addObject:entry];
        if (matches.count >= limit) {
            break;
        }
    }

    return @{
        @"ok": @YES,
        @"path": path,
        @"entries": matches,
        @"truncated": @(matches.count < filenames.count)
    };
}

- (NSDictionary *)toolReadArchiveText:(NSDictionary *)arguments {
    NSError *error = nil;
    NSString *path = [self validatedPath:arguments[@"path"] write:NO error:&error];
    if (!path) {
        return [self toolError:error];
    }

    UZKArchive *archive = [[UZKArchive alloc] initWithPath:path error:&error];
    if (!archive) {
        return [self toolError:error];
    }

    NSString *entry = [arguments[@"entry"] description];
    NSData *data = [archive extractDataFromFile:entry error:&error];
    if (!data) {
        return [self toolError:error];
    }

    NSString *content = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!content) {
        content = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
    }
    if (!content) {
        return [self toolErrorMessage:@"Archive entry is not UTF-8 text."];
    }

    NSUInteger maxCharacters = [self clampedInteger:arguments[@"max_characters"] defaultValue:8000 min:256 max:24000];
    BOOL truncated = NO;
    if (content.length > maxCharacters) {
        content = [content substringFromIndex:content.length - maxCharacters];
        truncated = YES;
    }
    return @{
        @"ok": @YES,
        @"path": path,
        @"entry": entry,
        @"truncated": @(truncated),
        @"content": content
    };
}

- (NSDictionary *)toolBackupItem:(NSDictionary *)arguments {
    NSError *error = nil;
    NSString *path = [self validatedPath:arguments[@"path"] write:YES error:&error];
    if (!path) {
        return [self toolError:error];
    }

    NSString *backupPath = [self uniqueDestinationForSource:path underDirectory:self.backupDirectory];
    if (![self copyItemAtPath:path toPath:backupPath error:&error]) {
        return [self toolError:error];
    }
    return @{
        @"ok": @YES,
        @"path": path,
        @"backup_path": backupPath
    };
}

- (NSDictionary *)toolQuarantineItem:(NSDictionary *)arguments {
    NSError *error = nil;
    NSString *path = [self validatedPath:arguments[@"path"] write:YES error:&error];
    if (!path) {
        return [self toolError:error];
    }

    NSString *destination = [self uniqueDestinationForSource:path underDirectory:self.quarantineDirectory];
    [NSFileManager.defaultManager createDirectoryAtPath:destination.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    if (![NSFileManager.defaultManager moveItemAtPath:path toPath:destination error:&error]) {
        return [self toolError:error];
    }
    return @{
        @"ok": @YES,
        @"path": path,
        @"quarantine_path": destination,
        @"reason": [arguments[@"reason"] description] ?: @""
    };
}

- (NSDictionary *)toolMakeDirectory:(NSDictionary *)arguments {
    NSError *error = nil;
    NSString *path = [self validatedPath:arguments[@"path"] write:YES error:&error];
    if (!path) {
        return [self toolError:error];
    }

    if (![NSFileManager.defaultManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:&error]) {
        return [self toolError:error];
    }
    return @{
        @"ok": @YES,
        @"path": path,
        @"created": @YES
    };
}

- (NSDictionary *)toolCopyItem:(NSDictionary *)arguments {
    NSError *error = nil;
    NSString *sourcePath = [self validatedPath:arguments[@"source_path"] write:NO error:&error];
    if (!sourcePath) {
        return [self toolError:error];
    }
    NSString *destinationPath = [self validatedPath:arguments[@"destination_path"] write:YES error:&error];
    if (!destinationPath) {
        return [self toolError:error];
    }

    if (![self copyItemAtPath:sourcePath toPath:destinationPath error:&error]) {
        return [self toolError:error];
    }
    return @{
        @"ok": @YES,
        @"source_path": sourcePath,
        @"destination_path": destinationPath
    };
}

- (NSDictionary *)toolMoveItem:(NSDictionary *)arguments {
    NSError *error = nil;
    NSString *sourcePath = [self validatedPath:arguments[@"source_path"] write:YES error:&error];
    if (!sourcePath) {
        return [self toolError:error];
    }
    NSString *destinationPath = [self validatedPath:arguments[@"destination_path"] write:YES error:&error];
    if (!destinationPath) {
        return [self toolError:error];
    }

    [NSFileManager.defaultManager createDirectoryAtPath:destinationPath.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    [NSFileManager.defaultManager removeItemAtPath:destinationPath error:nil];
    if (![NSFileManager.defaultManager moveItemAtPath:sourcePath toPath:destinationPath error:&error]) {
        return [self toolError:error];
    }
    return @{
        @"ok": @YES,
        @"source_path": sourcePath,
        @"destination_path": destinationPath
    };
}

- (NSDictionary *)toolDisableItem:(NSDictionary *)arguments {
    NSError *error = nil;
    NSString *path = [self validatedPath:arguments[@"path"] write:YES error:&error];
    if (!path) {
        return [self toolError:error];
    }

    if ([path hasSuffix:@".disabled"]) {
        return @{
            @"ok": @YES,
            @"path": path,
            @"disabled_path": path,
            @"changed": @NO
        };
    }

    NSString *destination = [self uniqueSiblingPathForDisabledItem:path];
    if (![NSFileManager.defaultManager moveItemAtPath:path toPath:destination error:&error]) {
        return [self toolError:error];
    }
    return @{
        @"ok": @YES,
        @"path": path,
        @"disabled_path": destination,
        @"changed": @YES
    };
}

- (NSDictionary *)toolDeleteItem:(NSDictionary *)arguments {
    NSError *error = nil;
    NSString *path = [self validatedPath:arguments[@"path"] write:YES error:&error];
    if (!path) {
        return [self toolError:error];
    }

    NSString *backupPath = [self uniqueDestinationForSource:path underDirectory:self.backupDirectory];
    if (![self copyItemAtPath:path toPath:backupPath error:&error]) {
        return [self toolError:error];
    }
    if (![NSFileManager.defaultManager removeItemAtPath:path error:&error]) {
        return [self toolError:error];
    }
    return @{
        @"ok": @YES,
        @"path": path,
        @"backup_path": backupPath,
        @"deleted": @YES
    };
}

- (NSDictionary *)toolWriteTextFile:(NSDictionary *)arguments {
    NSError *error = nil;
    NSString *path = [self validatedPath:arguments[@"path"] write:YES error:&error];
    if (!path) {
        return [self toolError:error];
    }

    NSString *content = [arguments[@"content"] description] ?: @"";
    NSString *backupPath = [self backupIfExistsAtPath:path error:&error];
    if (error) {
        return [self toolError:error];
    }

    [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    if (![content writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
        return [self toolError:error];
    }
    NSMutableDictionary *result = @{
        @"ok": @YES,
        @"path": path,
        @"written": @YES
    }.mutableCopy;
    if (backupPath.length > 0) {
        result[@"backup_path"] = backupPath;
    }
    return result;
}

- (NSDictionary *)toolReplaceInTextFile:(NSDictionary *)arguments {
    NSError *error = nil;
    NSString *path = [self validatedPath:arguments[@"path"] write:YES error:&error];
    if (!path) {
        return [self toolError:error];
    }

    NSString *oldText = [arguments[@"old_text"] description] ?: @"";
    NSString *newText = [arguments[@"new_text"] description] ?: @"";
    if (oldText.length == 0) {
        return [self toolErrorMessage:@"old_text must not be empty."];
    }

    NSString *content = [self readTextFileAtPath:path error:&error];
    if (!content) {
        return [self toolError:error];
    }
    NSUInteger occurrences = [[content componentsSeparatedByString:oldText] count] - 1;
    if (occurrences == 0) {
        return [self toolErrorMessage:@"old_text was not found in the file."];
    }

    NSString *backupPath = [self backupIfExistsAtPath:path error:&error];
    if (error) {
        return [self toolError:error];
    }

    NSString *updated = [content stringByReplacingOccurrencesOfString:oldText withString:newText];
    if (![updated writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
        return [self toolError:error];
    }

    NSMutableDictionary *result = @{
        @"ok": @YES,
        @"path": path,
        @"occurrences": @(occurrences)
    }.mutableCopy;
    if (backupPath.length > 0) {
        result[@"backup_path"] = backupPath;
    }
    return result;
}

- (NSDictionary *)toolExtractArchive:(NSDictionary *)arguments {
    NSError *error = nil;
    NSString *path = [self validatedPath:arguments[@"path"] write:NO error:&error];
    if (!path) {
        return [self toolError:error];
    }

    UZKArchive *archive = [[UZKArchive alloc] initWithPath:path error:&error];
    if (!archive) {
        return [self toolError:error];
    }

    NSString *tag = [arguments[@"tag"] description];
    if (tag.length == 0) {
        tag = path.lastPathComponent.stringByDeletingPathExtension;
    }
    NSString *destination = [self uniqueDirectoryNamed:tag under:self.extractDirectory];
    if (![NSFileManager.defaultManager createDirectoryAtPath:destination withIntermediateDirectories:YES attributes:nil error:&error]) {
        return [self toolError:error];
    }
    if (![archive extractFilesTo:destination overwrite:YES error:&error]) {
        return [self toolError:error];
    }
    return @{
        @"ok": @YES,
        @"path": path,
        @"extracted_path": destination
    };
}

- (NSDictionary *)toolDownloadFile:(NSDictionary *)arguments {
    NSError *error = nil;
    NSString *urlString = [arguments[@"url"] description] ?: @"";
    NSString *destinationPath = [self validatedPath:arguments[@"destination_path"] write:YES error:&error];
    if (!destinationPath) {
        return [self toolError:error];
    }

    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        return [self toolErrorMessage:@"Invalid URL."];
    }

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSData *downloadedData = nil;
    __block NSError *downloadError = nil;
    NSURLSessionDataTask *task = [NSURLSession.sharedSession dataTaskWithURL:url
                                                           completionHandler:^(NSData *data, NSURLResponse *response, NSError *networkError) {
        if (networkError) {
            downloadError = networkError;
            dispatch_semaphore_signal(semaphore);
            return;
        }

        NSHTTPURLResponse *httpResponse = (id)response;
        if (httpResponse.statusCode < 200 || httpResponse.statusCode >= 300) {
            downloadError = [NSError errorWithDomain:AIModDoctorErrorDomain
                                                code:AIModDoctorErrorCodeNetwork
                                            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Download failed with HTTP %ld", (long)httpResponse.statusCode]}];
            dispatch_semaphore_signal(semaphore);
            return;
        }

        downloadedData = data;
        dispatch_semaphore_signal(semaphore);
    }];
    [task resume];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);

    if (downloadError) {
        return [self toolError:downloadError];
    }
    if (downloadedData.length == 0) {
        return [self toolErrorMessage:@"Downloaded file is empty."];
    }

    NSString *backupPath = [self backupIfExistsAtPath:destinationPath error:&error];
    if (error) {
        return [self toolError:error];
    }

    [NSFileManager.defaultManager createDirectoryAtPath:destinationPath.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    if (![downloadedData writeToFile:destinationPath options:NSDataWritingAtomic error:&error]) {
        return [self toolError:error];
    }

    NSMutableDictionary *result = @{
        @"ok": @YES,
        @"url": urlString,
        @"destination_path": destinationPath,
        @"size": @(downloadedData.length)
    }.mutableCopy;
    if (backupPath.length > 0) {
        result[@"backup_path"] = backupPath;
    }
    return result;
}

- (NSDictionary *)toolRepackArchive:(NSDictionary *)arguments {
    NSError *error = nil;
    NSString *sourceDirectory = [self validatedPath:arguments[@"source_directory"] write:NO error:&error];
    if (!sourceDirectory) {
        return [self toolError:error];
    }
    NSString *destinationPath = [self validatedPath:arguments[@"destination_path"] write:YES error:&error];
    if (!destinationPath) {
        return [self toolError:error];
    }
    if (![self path:sourceDirectory isInsideRoot:self.extractDirectory]) {
        return [self toolErrorMessage:@"source_directory must be inside the AI session extracted workspace."];
    }

    BOOL isDirectory = NO;
    if (![NSFileManager.defaultManager fileExistsAtPath:sourceDirectory isDirectory:&isDirectory] || !isDirectory) {
        return [self toolErrorMessage:@"source_directory does not exist."];
    }

    NSString *backupPath = [self backupIfExistsAtPath:destinationPath error:&error];
    if (error) {
        return [self toolError:error];
    }

    NSString *temporaryArchivePath = [self.sessionDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@",
        [NSUUID UUID].UUIDString.lowercaseString, destinationPath.lastPathComponent]];
    [NSFileManager.defaultManager removeItemAtPath:temporaryArchivePath error:nil];
    [NSFileManager.defaultManager createFileAtPath:temporaryArchivePath contents:[NSData data] attributes:nil];

    UZKArchive *archive = [[UZKArchive alloc] initWithPath:temporaryArchivePath error:&error];
    if (!archive) {
        archive = [UZKArchive zipArchiveAtPath:temporaryArchivePath];
        if (!archive) {
            return [self toolError:error ?: [self errorWithCode:AIModDoctorErrorCodeTool description:@"Unable to create a temporary archive."]];
        }
    }

    NSDirectoryEnumerator *enumerator = [NSFileManager.defaultManager enumeratorAtPath:sourceDirectory];
    NSString *relativePath = nil;
    while ((relativePath = enumerator.nextObject)) {
        NSString *absolutePath = [sourceDirectory stringByAppendingPathComponent:relativePath];
        BOOL fileIsDirectory = NO;
        if (![NSFileManager.defaultManager fileExistsAtPath:absolutePath isDirectory:&fileIsDirectory] || fileIsDirectory) {
            continue;
        }

        NSData *data = [NSData dataWithContentsOfFile:absolutePath options:0 error:&error];
        if (!data) {
            return [self toolError:error];
        }

        NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:absolutePath error:nil];
        NSDate *fileDate = attributes[NSFileModificationDate];
        NSNumber *permissions = attributes[NSFilePosixPermissions];
        short posixPermissions = permissions ? permissions.shortValue : 0644;
        BOOL success = [archive writeData:data
                                 filePath:relativePath
                                 fileDate:fileDate
                         posixPermissions:posixPermissions
                        compressionMethod:UZKCompressionMethodDefault
                                 password:nil
                                overwrite:YES
                                    error:&error];
        if (!success) {
            return [self toolError:error];
        }
    }

    [NSFileManager.defaultManager createDirectoryAtPath:destinationPath.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    [NSFileManager.defaultManager removeItemAtPath:destinationPath error:nil];
    if (![NSFileManager.defaultManager moveItemAtPath:temporaryArchivePath toPath:destinationPath error:&error]) {
        return [self toolError:error];
    }

    NSMutableDictionary *result = @{
        @"ok": @YES,
        @"source_directory": sourceDirectory,
        @"destination_path": destinationPath
    }.mutableCopy;
    if (backupPath.length > 0) {
        result[@"backup_path"] = backupPath;
    }
    return result;
}

#pragma mark Tool helpers

- (NSDictionary *)dictionaryFromArguments:(id)arguments {
    if ([arguments isKindOfClass:NSDictionary.class]) {
        return arguments;
    }
    if (![arguments isKindOfClass:NSString.class]) {
        return nil;
    }

    NSData *data = [arguments dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) {
        return nil;
    }
    id object = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
    if (![object isKindOfClass:NSDictionary.class]) {
        return nil;
    }
    return object;
}

- (NSDictionary *)entryInfoForPath:(NSString *)path relativeTo:(NSString *)root {
    NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
    if (!attributes) {
        return nil;
    }

    BOOL isDirectory = [attributes[NSFileType] isEqualToString:NSFileTypeDirectory];
    NSString *relativePath = [path substringFromIndex:MIN(root.length + 1, path.length)];
    return @{
        @"name": path.lastPathComponent ?: @"",
        @"relative_path": relativePath ?: @"",
        @"path": path,
        @"type": isDirectory ? @"directory" : @"file",
        @"size": attributes[NSFileSize] ?: @0
    };
}

- (NSUInteger)clampedInteger:(id)value defaultValue:(NSUInteger)defaultValue min:(NSUInteger)min max:(NSUInteger)max {
    NSInteger rawValue = defaultValue;
    if ([value respondsToSelector:@selector(integerValue)]) {
        rawValue = [value integerValue];
    }
    rawValue = MAX((NSInteger)min, MIN((NSInteger)max, rawValue));
    return (NSUInteger)rawValue;
}

- (NSString *)readTextFileAtPath:(NSString *)path error:(NSError **)error {
    NSString *content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:error];
    if (!content) {
        content = [NSString stringWithContentsOfFile:path encoding:NSISOLatin1StringEncoding error:error];
    }
    if (!content && error && !*error) {
        *error = [self errorWithCode:AIModDoctorErrorCodeTool description:@"Unable to decode text file."];
    }
    return content;
}

- (BOOL)copyItemAtPath:(NSString *)path toPath:(NSString *)destination error:(NSError **)error {
    [NSFileManager.defaultManager createDirectoryAtPath:destination.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    [NSFileManager.defaultManager removeItemAtPath:destination error:nil];
    return [NSFileManager.defaultManager copyItemAtPath:path toPath:destination error:error];
}

- (NSString *)backupIfExistsAtPath:(NSString *)path error:(NSError **)error {
    if (![NSFileManager.defaultManager fileExistsAtPath:path]) {
        return nil;
    }

    NSString *backupPath = [self uniqueDestinationForSource:path underDirectory:self.backupDirectory];
    if (![self copyItemAtPath:path toPath:backupPath error:error]) {
        return nil;
    }
    return backupPath;
}

- (NSString *)uniqueDestinationForSource:(NSString *)path underDirectory:(NSString *)directory {
    NSString *baseName = path.lastPathComponent.length > 0 ? path.lastPathComponent : @"item";
    NSString *token = [NSUUID UUID].UUIDString.lowercaseString;
    return [directory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@", token, baseName]];
}

- (NSString *)uniqueDirectoryNamed:(NSString *)name under:(NSString *)directory {
    NSString *sanitizedName = [[name stringByReplacingOccurrencesOfString:@"/" withString:@"-"]
        stringByReplacingOccurrencesOfString:@"\\" withString:@"-"];
    if (sanitizedName.length == 0) {
        sanitizedName = @"archive";
    }
    return [directory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@", sanitizedName, [NSUUID UUID].UUIDString.lowercaseString]];
}

- (NSString *)uniqueSiblingPathForDisabledItem:(NSString *)path {
    NSString *candidate = [path stringByAppendingString:@".disabled"];
    if (![NSFileManager.defaultManager fileExistsAtPath:candidate]) {
        return candidate;
    }
    return [path stringByAppendingFormat:@".%@.disabled", [NSUUID UUID].UUIDString.lowercaseString];
}

- (BOOL)path:(NSString *)path isInsideRoot:(NSString *)root {
    if (path.length == 0 || root.length == 0) {
        return NO;
    }

    NSString *normalizedPath = path.stringByStandardizingPath;
    NSString *normalizedRoot = root.stringByStandardizingPath;
    if ([normalizedPath isEqualToString:normalizedRoot]) {
        return YES;
    }
    NSString *rootWithSlash = [normalizedRoot hasSuffix:@"/"] ? normalizedRoot : [normalizedRoot stringByAppendingString:@"/"];
    return [normalizedPath hasPrefix:rootWithSlash];
}

- (NSString *)validatedPath:(NSString *)path write:(BOOL)write error:(NSError **)error {
    NSString *candidate = [path description];
    if (candidate.length == 0) {
        if (error) {
            *error = [self errorWithCode:AIModDoctorErrorCodeValidation description:@"Path is missing."];
        }
        return nil;
    }

    if (![candidate isAbsolutePath]) {
        candidate = [self.gameDirectory stringByAppendingPathComponent:candidate];
    }
    candidate = candidate.stringByStandardizingPath;

    NSArray<NSString *> *roots = write ? self.writeRoots : self.readRoots;
    for (NSString *root in roots) {
        if ([self path:candidate isInsideRoot:root]) {
            return candidate;
        }
    }

    if (error) {
        *error = [self errorWithCode:AIModDoctorErrorCodeValidation
                          description:[NSString stringWithFormat:@"Path is outside allowed %@ roots: %@", write ? @"write" : @"read", candidate]];
    }
    return nil;
}

- (NSDictionary *)toolError:(NSError *)error {
    return @{
        @"ok": @NO,
        @"error": error.localizedDescription ?: @"Unknown tool error."
    };
}

- (NSDictionary *)toolErrorMessage:(NSString *)message {
    return @{
        @"ok": @NO,
        @"error": message ?: @"Unknown tool error."
    };
}

- (NSError *)errorWithCode:(AIModDoctorErrorCode)code description:(NSString *)description {
    return [NSError errorWithDomain:AIModDoctorErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: description ?: @"Unknown AI Mod Doctor error."}];
}

- (void)emitEvent:(NSString *)format, ... {
    if (!self.eventHandler || format.length == 0) {
        return;
    }

    va_list arguments;
    va_start(arguments, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:arguments];
    va_end(arguments);

    dispatch_async(dispatch_get_main_queue(), ^{
        self.eventHandler(message);
    });
}

@end

#import <WebKit/WebKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#import "AccountListViewController.h"
#import "LauncherMenuViewController.h"
#import "LauncherNavigationController.h"
#import "LauncherPreferences.h"
#import "LauncherPreferencesViewController.h"
#import "NeeflowLauncherViewController.h"
#import "PLProfiles.h"
#import "authenticator/BaseAuthenticator.h"
#import "utils.h"

#include <stdlib.h>

static NSString *const NeeflowBridgePrompt = @"__NEEFLOW_BRIDGE__";

@interface NeeflowLauncherViewController () <WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler>
@property(nonatomic) WKWebView *webView;
- (NSString *)jsonString:(NSDictionary *)value;
- (NSString *)error:(NSString *)message;
- (NSString *)fetchApi:(NSArray *)arguments;
- (NSString *)setJitServerAddress:(NSArray *)arguments;
@end

@interface NeeflowScriptMessageHandler : NSObject <WKScriptMessageHandler>
@property(nonatomic, weak) id<WKScriptMessageHandler> delegate;
@end

@implementation NeeflowScriptMessageHandler

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    [self.delegate userContentController:userContentController didReceiveScriptMessage:message];
}

@end

@implementation NeeflowLauncherViewController

- (id)init {
    self = [super init];
    self.title = @"Neeflow";
    return self;
}

- (NSString *)imageName {
    return @"sparkles";
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:11 / 255.0 green:12 / 255.0 blue:15 / 255.0 alpha:1];

    NSString *bridge =
        @"(function(){if(window.NeeflowAndroid)return;"
        @"var methods=['getLauncherState','getRuntimeSettings','setRuntimeSetting','saveProfile','selectProfile','deleteProfile','saveUsername','launchGame','installLoader','listGameFiles','openGameFolder','openGameFile','openTouchControls','openRuntimeSettings','getJitServerAddress','setJitServerAddress','getPlatform'];"
        @"window.NeeflowAndroid={};methods.forEach(function(name){window.NeeflowAndroid[name]=function(){return window.prompt('__NEEFLOW_BRIDGE__',JSON.stringify({method:name,args:Array.prototype.slice.call(arguments)}))}});"
        @"var pending=Object.create(null),next=0;"
        @"window.__neeflowResolveApi=function(message){var resolve=pending[message.id];if(!resolve)return;delete pending[message.id];var body=typeof message.body==='string'?message.body:'{}';var data;try{data=JSON.parse(body)}catch(e){data={error:'Invalid native API response'}};resolve({ok:!data.error,status:data.error?502:200,json:function(){return Promise.resolve(data)},text:function(){return Promise.resolve(body)}})};"
        @"window.NeeflowAndroid.fetchApi=function(route){return new Promise(function(resolve){if(!window.webkit||!window.webkit.messageHandlers||!window.webkit.messageHandlers.neeflowApi){resolve({ok:false,status:500,json:function(){return Promise.resolve({error:'Native API bridge is unavailable'})},text:function(){return Promise.resolve('')}});return}var id=String(++next);pending[id]=resolve;window.webkit.messageHandlers.neeflowApi.postMessage({id:id,route:route})})};"
        @"var originalFetch=window.fetch.bind(window);window.fetch=function(input,init){var target=typeof input==='string'?input:(input&&input.url)||'';var url;try{url=new URL(target,window.location.href)}catch(e){return originalFetch(input,init)}if(url.pathname.indexOf('/api/')!==0)return originalFetch(input,init);return Promise.resolve(window.NeeflowAndroid.fetchApi(url.pathname+url.search)).then(function(result){if(result&&typeof result.json==='function')return result;var body=typeof result==='string'?result:'{}';var data;try{data=JSON.parse(body)}catch(e){data={error:'Invalid native API response'}};return{ok:!data.error,status:data.error?502:200,json:function(){return Promise.resolve(data)},text:function(){return Promise.resolve(body)}}})}})();";
    WKUserContentController *contentController = [WKUserContentController new];
    NeeflowScriptMessageHandler *messageHandler = [NeeflowScriptMessageHandler new];
    messageHandler.delegate = self;
    [contentController addScriptMessageHandler:messageHandler name:@"neeflowApi"];
    [contentController addUserScript:[[WKUserScript alloc] initWithSource:bridge injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES]];

    WKWebViewConfiguration *configuration = [WKWebViewConfiguration new];
    configuration.userContentController = contentController;
    self.webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:configuration];
    self.webView.translatesAutoresizingMaskIntoConstraints = NO;
    self.webView.UIDelegate = self;
    self.webView.navigationDelegate = self;
    self.webView.opaque = NO;
    self.webView.backgroundColor = self.view.backgroundColor;
    self.webView.scrollView.backgroundColor = self.view.backgroundColor;
    self.webView.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    self.webView.scrollView.bounces = NO;
    [self.view addSubview:self.webView];
    [NSLayoutConstraint activateConstraints:@[
        [self.webView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.webView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.webView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.webView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];

    NSString *pagePath = [NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"neeflow/index.html"];
    NSURL *pageURL = [NSURL fileURLWithPath:pagePath];
    [self.webView loadFileURL:pageURL allowingReadAccessToURL:pageURL.URLByDeletingLastPathComponent];

}

- (void)resolveApiRequest:(NSString *)identifier body:(NSString *)body {
    NSDictionary *response = @{ @"id": identifier, @"body": body ?: @"{}" };
    NSString *json = [self jsonString:response];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.webView) return;
        NSString *script = [NSString stringWithFormat:@"window.__neeflowResolveApi&&window.__neeflowResolveApi(%@)", json];
        [self.webView evaluateJavaScript:script completionHandler:nil];
    });
}

- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    if (![message.name isEqualToString:@"neeflowApi"] || !message.frameInfo.isMainFrame) return;
    NSDictionary *request = [message.body isKindOfClass:NSDictionary.class] ? message.body : nil;
    NSString *identifier = [request[@"id"] isKindOfClass:NSString.class] ? request[@"id"] : nil;
    NSString *route = [request[@"route"] isKindOfClass:NSString.class] ? request[@"route"] : nil;
    if (identifier.length == 0) return;
    if (route.length == 0 || route.length > 2048 || ![route hasPrefix:@"/api/"]) {
        [self resolveApiRequest:identifier body:[self error:@"Invalid API route"]];
        return;
    }

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NeeflowLauncherViewController *strongSelf = weakSelf;
        if (!strongSelf) return;
        NSString *body = [strongSelf fetchApi:@[route]];
        [strongSelf resolveApiRequest:identifier body:body];
    });
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.webView evaluateJavaScript:@"window.__neeflowRefreshNativeProfiles&&window.__neeflowRefreshNativeProfiles()" completionHandler:nil];
    [self.webView evaluateJavaScript:@"window.__neeflowRefreshJitServerStatus&&window.__neeflowRefreshJitServerStatus()" completionHandler:nil];
}

- (void)webView:(WKWebView *)webView runJavaScriptTextInputPanelWithPrompt:(NSString *)prompt
    defaultText:(NSString *)defaultText initiatedByFrame:(WKFrameInfo *)frame
    completionHandler:(void (^)(NSString * _Nullable))completionHandler {
    if (![prompt isEqualToString:NeeflowBridgePrompt] || !frame.isMainFrame) {
        completionHandler(nil);
        return;
    }

    NSData *payloadData = [defaultText dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *payload = payloadData ? [NSJSONSerialization JSONObjectWithData:payloadData options:0 error:nil] : nil;
    if (![payload isKindOfClass:NSDictionary.class]) {
        completionHandler([self error:@"Invalid Neeflow bridge request"].description);
        return;
    }
    completionHandler([self handleBridgeMethod:payload[@"method"] arguments:payload[@"args"]]);
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
    decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL *url = navigationAction.request.URL;
    if (url.isFileURL && [url.path hasPrefix:[NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"neeflow"]]) {
        decisionHandler(WKNavigationActionPolicyAllow);
        return;
    }
    if (navigationAction.navigationType == WKNavigationTypeLinkActivated && [url.scheme isEqualToString:@"https"]) {
        openLink(self, url);
    }
    decisionHandler(WKNavigationActionPolicyCancel);
}

- (NSString *)jsonString:(NSDictionary *)value {
    NSData *data = [NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingFragmentsAllowed error:nil];
    return data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"{\"error\":\"Could not serialize native response\"}";
}

- (NSString *)error:(NSString *)message {
    return [self jsonString:@{@"error": message ?: @"Native operation failed"}];
}

- (NSString *)ok:(NSString *)identifier {
    return [self jsonString:@{@"ok": @YES, @"id": identifier ?: @""}];
}

- (NSString *)handleBridgeMethod:(NSString *)method arguments:(NSArray *)arguments {
    if (![method isKindOfClass:NSString.class] || ![arguments isKindOfClass:NSArray.class]) {
        return [self error:@"Invalid Neeflow bridge request"];
    }
    @try {
        if ([method isEqualToString:@"getPlatform"]) return [self jsonString:@{@"platform": @"ios", @"native": @YES}];
        if ([method isEqualToString:@"getLauncherState"]) return [self launcherState];
        if ([method isEqualToString:@"getRuntimeSettings"]) return [self runtimeSettings];
        if ([method isEqualToString:@"setRuntimeSetting"]) return [self setRuntimeSetting:arguments];
        if ([method isEqualToString:@"getJitServerAddress"]) {
            id address = getPrefObject(@"general.jitstreamer_server");
            return [self jsonString:@{@"address": [address isKindOfClass:NSString.class] ? address : @""}];
        }
        if ([method isEqualToString:@"setJitServerAddress"]) return [self setJitServerAddress:arguments];
        if ([method isEqualToString:@"saveProfile"]) return [self saveProfile:arguments];
        if ([method isEqualToString:@"selectProfile"]) return [self selectProfile:arguments];
        if ([method isEqualToString:@"deleteProfile"]) return [self deleteProfile:arguments];
        if ([method isEqualToString:@"saveUsername"]) return [self saveUsername:arguments];
        if ([method isEqualToString:@"launchGame"]) return [self launchGame:arguments];
        if ([method isEqualToString:@"listGameFiles"]) return [self listGameFiles:arguments];
        if ([method isEqualToString:@"openGameFile"]) return [self openGameFile:arguments];
        if ([method isEqualToString:@"fetchApi"]) return [self fetchApi:arguments];
        if ([method isEqualToString:@"openGameFolder"]) return [self error:@"iOS keeps Minecraft files inside the app sandbox; the Files app cannot open this private folder."];
        if ([method isEqualToString:@"installLoader"]) return [self error:@"Install loaders from Amethyst's Profiles screen on iOS."];
        if ([method isEqualToString:@"openTouchControls"]) {
            [(id)self.splitViewController.viewControllers.lastObject performSelector:@selector(enterCustomControls)];
            return [self ok:@"controls"];
        }
        if ([method isEqualToString:@"openRuntimeSettings"]) {
            LauncherPreferencesViewController *settings = [LauncherPreferencesViewController new];
            UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:settings];
            navigation.modalPresentationStyle = UIModalPresentationFormSheet;
            [self presentViewController:navigation animated:YES completion:nil];
            return [self ok:@"settings"];
        }
    } @catch (NSException *exception) {
        return [self error:exception.reason ?: @"Native operation failed"];
    }
    return [self error:@"This operation is not available in the iOS launcher."];
}

- (NSString *)launcherState {
    PLProfiles *launcherProfiles = PLProfiles.current;
    NSString *selected = launcherProfiles.selectedProfileName ?: @"";
    NSMutableArray *profiles = [NSMutableArray new];
    NSArray *keys = [launcherProfiles.profiles.allKeys sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    for (NSString *key in keys) {
        NSDictionary *profile = launcherProfiles.profiles[key];
        NSString *versionId = profile[@"lastVersionId"];
        if (![versionId isKindOfClass:NSString.class] || versionId.length == 0 || [versionId isEqualToString:@"Unknown"]) continue;
        NSString *gameVersion = [self gameVersionForProfile:versionId];
        NSString *name = [profile[@"name"] isKindOfClass:NSString.class] && [profile[@"name"] length] > 0 ? profile[@"name"] : versionId;
        [profiles addObject:@{@"id": key, @"name": name, @"gameVersion": gameVersion, @"loader": [self loaderForVersion:versionId]}];
    }
    NSString *username = [BaseAuthenticator.current.authData[@"username"] isKindOfClass:NSString.class] ? BaseAuthenticator.current.authData[@"username"] : @"";
    return [self jsonString:@{@"username": username, @"selectedProfileId": selected, @"profiles": profiles}];
}

- (NSString *)gameVersionForProfile:(NSString *)versionId {
    const char *gameDirectory = getenv("GAME_DIR");
    if (!gameDirectory || versionId.length == 0 || [versionId isEqualToString:@"."] || [versionId isEqualToString:@".."] || [versionId containsString:@"/"] || [versionId containsString:@"\\"]) return versionId;
    NSString *versionsDirectory = [[NSString stringWithUTF8String:gameDirectory] stringByAppendingPathComponent:@"versions"];
    NSString *versionDirectory = [versionsDirectory stringByAppendingPathComponent:versionId];
    NSString *metadataPath = [versionDirectory stringByAppendingPathComponent:[versionId stringByAppendingPathExtension:@"json"]];
    NSDictionary *metadata = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:metadataPath] options:NSJSONReadingFragmentsAllowed error:nil];
    NSString *inheritedVersion = [metadata[@"inheritsFrom"] isKindOfClass:NSString.class] ? metadata[@"inheritsFrom"] : nil;
    if (inheritedVersion.length > 0) return inheritedVersion;
    NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:@"\\d{1,2}\\.\\d{1,2}(?:\\.\\d{1,2})?" options:0 error:nil];
    NSTextCheckingResult *match = [expression firstMatchInString:versionId options:0 range:NSMakeRange(0, versionId.length)];
    return match ? [versionId substringWithRange:match.range] : versionId;
}

- (NSString *)loaderForVersion:(NSString *)versionId {
    NSString *lowercase = versionId.lowercaseString;
    if ([lowercase containsString:@"optifine"]) return @"optifine";
    if ([lowercase containsString:@"neoforge"]) return @"neoforge";
    if ([lowercase containsString:@"fabric"]) return @"fabric";
    if ([lowercase containsString:@"quilt"]) return @"quilt";
    if ([lowercase containsString:@"forge"]) return @"forge";
    return @"vanilla";
}

- (NSInteger)maxAllocation {
    NSInteger memory = (NSInteger)(NSProcessInfo.processInfo.physicalMemory / 1048576);
    NSInteger maximum = MIN((NSInteger)(memory * 0.37), (NSInteger)4096);
    return MAX(256, 256 + ((maximum - 256) / 8) * 8);
}

- (NSString *)runtimeSettings {
    NSInteger memory = (NSInteger)(NSProcessInfo.processInfo.physicalMemory / 1048576);
    return [self jsonString:@{@"resolutionRatio": @(getPrefInt(@"video.resolution")),
                              @"allocation": @(getPrefInt(@"java.allocated_memory")),
                              @"deviceMemory": @(memory),
                              @"maxAllocation": @(self.maxAllocation),
                              @"javaArgs": getPrefObject(@"java.java_args") ?: @"",
                              @"forceVsync": @YES}];
}

- (NSString *)setJitServerAddress:(NSArray *)arguments {
    if (arguments.count < 1 || ![arguments[0] isKindOfClass:NSString.class]) return [self error:@"Invalid JIT server address."];
    NSString *address = [arguments[0] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (address.length > 255) return [self error:@"JIT server addresses cannot exceed 255 characters."];
    if (address.length > 0) {
        NSString *candidate = [address containsString:@"://"] ? address : [@"http://" stringByAppendingString:address];
        NSURLComponents *components = [NSURLComponents componentsWithString:candidate];
        if (!components.host.length || ![@[@"http", @"https"] containsObject:components.scheme.lowercaseString] || components.query.length || components.fragment.length || components.user.length || components.password.length || (components.path.length > 0 && ![components.path isEqualToString:@"/"]) || (components.port && (components.port.integerValue < 1 || components.port.integerValue > 65535))) {
            return [self error:@"Enter a JIT server host or http(s) URL without a path."];
        }
    }
    setPrefObject(@"general.jitstreamer_server", address);
    return [self ok:address];
}

- (NSString *)setRuntimeSetting:(NSArray *)arguments {
    if (arguments.count < 2 || ![arguments[0] isKindOfClass:NSString.class] || ![arguments[1] isKindOfClass:NSString.class]) return [self error:@"Invalid runtime setting"];
    NSString *key = arguments[0];
    NSString *value = arguments[1];
    if ([key isEqualToString:@"resolutionRatio"]) {
        NSInteger ratio = value.integerValue;
        if (ratio < 25 || ratio > 100 || (ratio - 25) % 5 != 0) return [self error:@"Resolution must be from 25% to 100% in 5% steps."];
        setPrefInt(@"video.resolution", ratio);
        return [self ok:value];
    }
    if ([key isEqualToString:@"allocation"]) {
        NSInteger allocation = value.integerValue;
        if (allocation < 256 || allocation > self.maxAllocation || (allocation - 256) % 8 != 0) return [self error:@"The requested memory allocation exceeds the safe limit for this device."];
        setPrefInt(@"java.allocated_memory", allocation);
        return [self ok:value];
    }
    if ([key isEqualToString:@"javaArgs"]) {
        if (value.length > 2000) return [self error:@"JVM arguments cannot exceed 2000 characters."];
        NSString *arguments = [[value stringByReplacingOccurrencesOfString:@"\n" withString:@" "] stringByReplacingOccurrencesOfString:@"\r" withString:@" "];
        setPrefObject(@"java.java_args", [arguments stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]);
        return [self ok:value];
    }
    if ([key isEqualToString:@"force_vsync"]) return [self error:@"iOS manages display synchronization for the Metal renderer."];
    return [self error:@"This runtime setting is not supported by Amethyst on iOS."];
}

- (NSString *)saveProfile:(NSArray *)arguments {
    if (arguments.count < 4) return [self error:@"Invalid Minecraft profile"];
    NSString *profileId = [arguments[0] isKindOfClass:NSString.class] ? arguments[0] : @"";
    NSString *name = [arguments[1] isKindOfClass:NSString.class] ? [arguments[1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : @"";
    NSString *gameVersion = [arguments[2] isKindOfClass:NSString.class] ? arguments[2] : @"";
    NSString *loader = [arguments[3] isKindOfClass:NSString.class] ? arguments[3] : @"";
    NSRegularExpression *valid = [NSRegularExpression regularExpressionWithPattern:@"^[A-Za-z0-9][A-Za-z0-9._+-]{0,31}$" options:0 error:nil];
    if (name.length == 0 || name.length > 40 || ![valid firstMatchInString:gameVersion options:0 range:NSMakeRange(0, gameVersion.length)]) return [self error:@"Invalid profile name or Minecraft version."];
    if (![loader isEqualToString:@"vanilla"]) return [self error:@"Create non-Vanilla profiles from Amethyst's Profiles screen on iOS."];

    PLProfiles *launcherProfiles = PLProfiles.current;
    NSString *key = launcherProfiles.profiles[profileId] ? profileId : name;
    NSMutableDictionary *profile = launcherProfiles.profiles[key] ? [launcherProfiles.profiles[key] mutableCopy] : [NSMutableDictionary new];
    profile[@"name"] = name;
    profile[@"lastVersionId"] = gameVersion;
    launcherProfiles.profiles[key] = profile;
    [launcherProfiles save];
    launcherProfiles.selectedProfileName = key;
    return [self ok:key];
}

- (NSString *)selectProfile:(NSArray *)arguments {
    if (arguments.count < 1 || ![arguments[0] isKindOfClass:NSString.class] || !PLProfiles.current.profiles[arguments[0]]) return [self error:@"Minecraft profile not found."];
    PLProfiles.current.selectedProfileName = arguments[0];
    return [self ok:arguments[0]];
}

- (NSString *)deleteProfile:(NSArray *)arguments {
    if (arguments.count < 1 || ![arguments[0] isKindOfClass:NSString.class]) return [self error:@"Invalid Minecraft profile"];
    NSString *profileId = arguments[0];
    PLProfiles *launcherProfiles = PLProfiles.current;
    if (!launcherProfiles.profiles[profileId]) return [self ok:@""];
    if (launcherProfiles.profiles.count <= 1) return [self error:@"The last Minecraft profile cannot be deleted."];
    [launcherProfiles.profiles removeObjectForKey:profileId];
    if ([launcherProfiles.selectedProfileName isEqualToString:profileId]) launcherProfiles.selectedProfileName = launcherProfiles.profiles.allKeys.firstObject;
    [launcherProfiles save];
    return [self ok:launcherProfiles.selectedProfileName];
}

- (BOOL)setLocalUsername:(NSString *)username {
    NSRegularExpression *valid = [NSRegularExpression regularExpressionWithPattern:@"^[A-Za-z0-9_]{3,16}$" options:0 error:nil];
    if (![username isKindOfClass:NSString.class] || ![valid firstMatchInString:username options:0 range:NSMakeRange(0, username.length)]) return NO;
    LocalAuthenticator *authenticator = [[LocalAuthenticator alloc] initWithInput:username];
    __block BOOL succeeded = NO;
    [authenticator loginWithCallback:^(id status, BOOL success) { succeeded = success; }];
    if (succeeded) setPrefObject(@"internal.selected_account", username);
    return succeeded;
}

- (NSString *)saveUsername:(NSArray *)arguments {
    if (arguments.count < 1 || ![self setLocalUsername:arguments[0]]) return [self error:@"Player names must contain 3–16 Latin letters, numbers, or underscores."];
    return [self ok:arguments[0]];
}

- (NSString *)launchGame:(NSArray *)arguments {
    if (arguments.count < 2 || ![arguments[0] isKindOfClass:NSString.class] || ![self setLocalUsername:arguments[1]]) return [self error:@"Choose a valid local player name before launching."];
    NSString *profileId = arguments[0];
    if (!PLProfiles.current.profiles[profileId]) return [self error:@"Minecraft profile not found."];
    PLProfiles.current.selectedProfileName = profileId;
    LauncherNavigationController *navigation = (id)self.splitViewController.viewControllers.lastObject;
    if ([navigation respondsToSelector:@selector(reloadProfileList)]) [navigation performSelector:@selector(reloadProfileList)];
    [navigation performSelector:@selector(launchMinecraft:) withObject:self.view];
    return [self ok:profileId];
}

- (NSString *)normalizedGamePath:(NSString *)relativePath error:(NSString **)errorMessage {
    if (![relativePath isKindOfClass:NSString.class] || relativePath.length > 512 || [relativePath hasPrefix:@"/"]) {
        if (errorMessage) *errorMessage = @"Invalid game file path.";
        return nil;
    }
    NSString *normalized = [relativePath stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
    for (NSString *part in [normalized componentsSeparatedByString:@"/"]) {
        if ([part isEqualToString:@".."] || [part isEqualToString:@"."] || (part.length == 0 && normalized.length > 0)) {
            if (errorMessage) *errorMessage = @"Invalid game file path.";
            return nil;
        }
    }
    NSString *root = [@(getenv("GAME_DIR")) stringByStandardizingPath];
    NSString *target = [[root stringByAppendingPathComponent:normalized] stringByStandardizingPath];
    if (![target isEqualToString:root] && ![target hasPrefix:[root stringByAppendingString:@"/"]]) {
        if (errorMessage) *errorMessage = @"Game file path escapes the Minecraft folder.";
        return nil;
    }
    return target;
}

- (NSString *)listGameFiles:(NSArray *)arguments {
    NSString *path = arguments.count > 0 && [arguments[0] isKindOfClass:NSString.class] ? arguments[0] : @"";
    NSString *pathError = nil;
    NSString *directoryPath = [self normalizedGamePath:path error:&pathError];
    if (!directoryPath) return [self error:pathError];
    BOOL isDirectory = NO;
    BOOL exists = [NSFileManager.defaultManager fileExistsAtPath:directoryPath isDirectory:&isDirectory];
    if (!exists && (path.length == 0 || [@[@"mods", @"resourcepacks", @"screenshots"] containsObject:path])) {
        NSError *createError = nil;
        if (![NSFileManager.defaultManager createDirectoryAtPath:directoryPath withIntermediateDirectories:YES attributes:nil error:&createError]) {
            return [self error:createError.localizedDescription ?: @"Could not create the Minecraft folder."];
        }
        isDirectory = YES;
    }
    if (!isDirectory) return [self error:@"Minecraft folder not found."];
    NSArray *names = [NSFileManager.defaultManager contentsOfDirectoryAtPath:directoryPath error:nil] ?: @[];
    NSArray *sortedNames = [names sortedArrayUsingComparator:^NSComparisonResult(NSString *left, NSString *right) {
        BOOL leftDirectory = NO, rightDirectory = NO;
        [NSFileManager.defaultManager fileExistsAtPath:[directoryPath stringByAppendingPathComponent:left] isDirectory:&leftDirectory];
        [NSFileManager.defaultManager fileExistsAtPath:[directoryPath stringByAppendingPathComponent:right] isDirectory:&rightDirectory];
        if (leftDirectory != rightDirectory) return leftDirectory ? NSOrderedAscending : NSOrderedDescending;
        return [left localizedCaseInsensitiveCompare:right];
    }];
    NSMutableArray *entries = [NSMutableArray new];
    for (NSString *name in [sortedNames subarrayWithRange:NSMakeRange(0, MIN(sortedNames.count, 500))]) {
        NSString *filePath = [directoryPath stringByAppendingPathComponent:name];
        NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:filePath error:nil] ?: @{};
        BOOL childDirectory = [attributes[NSFileType] isEqualToString:NSFileTypeDirectory];
        NSString *child = path.length ? [path stringByAppendingFormat:@"/%@", name] : name;
        [entries addObject:@{@"name": name, @"path": child, @"directory": @(childDirectory), @"size": childDirectory ? @0 : (attributes[NSFileSize] ?: @0)}];
    }
    return [self jsonString:@{@"path": path, @"entries": entries}];
}

- (NSString *)openGameFile:(NSArray *)arguments {
    if (arguments.count < 1 || ![arguments[0] isKindOfClass:NSString.class]) return [self error:@"Invalid game file path."];
    NSString *pathError = nil;
    NSString *filePath = [self normalizedGamePath:arguments[0] error:&pathError];
    if (!filePath) return [self error:pathError];
    BOOL isDirectory = NO;
    if (![NSFileManager.defaultManager fileExistsAtPath:filePath isDirectory:&isDirectory] || isDirectory) return [self error:@"Minecraft file is not readable."];
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:filePath]] applicationActivities:nil];
    activity.popoverPresentationController.sourceView = self.view;
    activity.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
    [self presentViewController:activity animated:YES completion:nil];
    return [self ok:arguments[0]];
}

- (id)fetchURL:(NSString *)urlString error:(NSError **)error {
    NSURL *url = [NSURL URLWithString:urlString];
    if (![url.scheme isEqualToString:@"https"] || !url.host.length) {
        if (error) *error = [NSError errorWithDomain:@"Neeflow" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Invalid upstream URL"}];
        return nil;
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:20];
    [request setValue:@"application/json, text/html;q=0.9, */*;q=0.8" forHTTPHeaderField:@"Accept"];
    [request setValue:@"NeeflowLauncher/1.0.0 (iOS)" forHTTPHeaderField:@"User-Agent"];
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    configuration.timeoutIntervalForRequest = 20;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration];
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSData *data = nil;
    __block NSURLResponse *response = nil;
    __block NSError *requestError = nil;
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *responseData, NSURLResponse *responseObject, NSError *failure) {
        data = responseData;
        response = responseObject;
        requestError = failure;
        dispatch_semaphore_signal(semaphore);
    }];
    [task resume];
    if (dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 25 * NSEC_PER_SEC)) != 0) {
        [task cancel];
        if (error) *error = [NSError errorWithDomain:@"Neeflow" code:2 userInfo:@{NSLocalizedDescriptionKey: @"The upstream server timed out"}];
        [session invalidateAndCancel];
        return nil;
    }
    [session finishTasksAndInvalidate];
    if (requestError) {
        if (error) *error = requestError;
        return nil;
    }
    if ([response isKindOfClass:NSHTTPURLResponse.class] && ((NSHTTPURLResponse *)response).statusCode >= 400) {
        if (error) *error = [NSError errorWithDomain:@"Neeflow" code:((NSHTTPURLResponse *)response).statusCode userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Upstream returned HTTP %ld", (long)((NSHTTPURLResponse *)response).statusCode]}];
        return nil;
    }
    return data;
}

- (NSDictionary *)fetchJSON:(NSString *)urlString error:(NSError **)error {
    NSData *data = [self fetchURL:urlString error:error];
    if (!data) return nil;
    id value = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingFragmentsAllowed error:error];
    return [value isKindOfClass:NSDictionary.class] ? value : nil;
}

- (NSString *)jitServerStatus {
    id configuredValue = getPrefObject(@"general.jitstreamer_server");
    NSString *address = [configuredValue isKindOfClass:NSString.class] ? [configuredValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : @"";
    if (address.length == 0) return [self jsonString:@{@"configured": @NO, @"reachable": @NO, @"message": @"Адрес JIT-сервера не задан."}];
    if (![address containsString:@"://"]) address = [@"http://" stringByAppendingString:address];

    NSURLComponents *components = [NSURLComponents componentsWithString:address];
    if (!components.host.length || ![@[@"http", @"https"] containsObject:components.scheme.lowercaseString] || components.query.length || components.fragment.length || components.user.length || components.password.length || (components.path.length > 0 && ![components.path isEqualToString:@"/"])) {
        return [self jsonString:@{@"configured": @YES, @"reachable": @NO, @"message": @"Неверный адрес JIT-сервера. Укажи хост или URL без пути."}];
    }

    NSString *baseURL = components.URL.absoluteString;
    while ([baseURL hasSuffix:@"/"]) baseURL = [baseURL substringToIndex:baseURL.length - 1];
    NSURL *versionURL = [NSURL URLWithString:[baseURL stringByAppendingString:@"/version"]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:versionURL cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:3];
    [request setValue:@"text/plain, application/json;q=0.9, */*;q=0.8" forHTTPHeaderField:@"Accept"];
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    configuration.timeoutIntervalForRequest = 3;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration];
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSData *responseData = nil;
    __block NSURLResponse *response = nil;
    __block NSError *requestError = nil;
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *responseObject, NSError *failure) {
        responseData = data;
        response = responseObject;
        requestError = failure;
        dispatch_semaphore_signal(semaphore);
    }];
    [task resume];

    BOOL completed = dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 4 * NSEC_PER_SEC)) == 0;
    BOOL reachable = completed && !requestError && [response isKindOfClass:NSHTTPURLResponse.class] && ((NSHTTPURLResponse *)response).statusCode >= 200 && ((NSHTTPURLResponse *)response).statusCode < 300;
    if (!completed) [task cancel];
    [session finishTasksAndInvalidate];

    NSString *version = @"";
    if (reachable && responseData.length > 0) {
        NSString *body = [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding];
        version = [body stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
        if (version.length > 80) version = [version substringToIndex:80];
    }
    NSString *message = @"Сервер не ответил на /version.";
    if (reachable) {
        message = @"Сервер отвечает на /version.";
    } else if (requestError.localizedDescription.length > 0) {
        message = requestError.localizedDescription;
    } else if (!completed) {
        message = @"Истекло время ожидания ответа сервера.";
    } else if ([response isKindOfClass:NSHTTPURLResponse.class]) {
        message = [NSString stringWithFormat:@"Сервер вернул HTTP %ld.", (long)((NSHTTPURLResponse *)response).statusCode];
    }
    return [self jsonString:@{@"configured": @YES, @"reachable": @(reachable), @"version": version, @"message": message}];
}

- (NSString *)fetchApi:(NSArray *)arguments {
    if (arguments.count < 1 || ![arguments[0] isKindOfClass:NSString.class]) return [self error:@"Invalid API route"];
    NSString *route = arguments[0];
    NSError *error = nil;
    if ([route isEqualToString:@"/api/jit/status"]) return [self jitServerStatus];
    if ([route isEqualToString:@"/api/minecraft/catalog"]) {
        NSDictionary *manifest = [self fetchJSON:@"https://piston-meta.mojang.com/mc/game/version_manifest_v2.json" error:&error];
        if (!manifest) return [self error:error.localizedDescription ?: @"Could not load Mojang's version manifest"];
        NSMutableArray *versions = [NSMutableArray new];
        for (NSDictionary *item in [manifest[@"versions"] isKindOfClass:NSArray.class] ? manifest[@"versions"] : @[]) {
            if (![item isKindOfClass:NSDictionary.class] || ![item[@"id"] isKindOfClass:NSString.class]) continue;
            [versions addObject:@{@"id": item[@"id"], @"type": item[@"type"] ?: @"release", @"releaseTime": item[@"releaseTime"] ?: @""}];
        }
        NSDictionary *unavailable = @{@"fabric": @"unavailable", @"quilt": @"unavailable", @"forge": @"unavailable", @"neoforge": @"unavailable", @"optifine": @"unavailable"};
        NSDictionary *loaders = @{@"fabric": @[], @"quilt": @[], @"forge": @[], @"neoforge": @[], @"optifine": @[]};
        return [self jsonString:@{@"latest": manifest[@"latest"] ?: @{}, @"versions": versions, @"loaders": loaders, @"loaderSources": unavailable}];
    }
    if ([route hasPrefix:@"/api/modrinth/search?"]) {
        NSURLComponents *incoming = [NSURLComponents componentsWithString:[@"https://local.invalid" stringByAppendingString:route]];
        NSString *query = @"";
        NSString *index = @"downloads";
        NSString *gameVersion = @"";
        NSString *loader = @"";
        for (NSURLQueryItem *item in incoming.queryItems) {
            if ([item.name isEqualToString:@"query"]) query = [item.value substringToIndex:MIN(item.value.length, 100)];
            if ([item.name isEqualToString:@"sort"] && @[@"relevance", @"downloads", @"follows", @"newest", @"updated"].count && [@[@"relevance", @"downloads", @"follows", @"newest", @"updated"] containsObject:item.value]) index = item.value;
            if ([item.name isEqualToString:@"gameVersion"]) gameVersion = item.value ?: @"";
            if ([item.name isEqualToString:@"loader"]) loader = item.value ?: @"";
        }
        NSURLComponents *upstream = [NSURLComponents componentsWithString:@"https://api.modrinth.com/v2/search"];
        NSMutableArray *facets = [NSMutableArray arrayWithObject:@[@"project_type:modpack"]];
        if (gameVersion.length) [facets addObject:@[[NSString stringWithFormat:@"versions:%@", gameVersion]]];
        if (loader.length) [facets addObject:@[[NSString stringWithFormat:@"categories:%@", loader]]];
        NSData *facetData = [NSJSONSerialization dataWithJSONObject:facets options:0 error:nil];
        NSString *facetString = [[NSString alloc] initWithData:facetData encoding:NSUTF8StringEncoding];
        upstream.queryItems = @[[NSURLQueryItem queryItemWithName:@"query" value:query], [NSURLQueryItem queryItemWithName:@"facets" value:facetString], [NSURLQueryItem queryItemWithName:@"index" value:index], [NSURLQueryItem queryItemWithName:@"limit" value:@"12"]];
        NSDictionary *result = [self fetchJSON:upstream.URL.absoluteString error:&error];
        if (!result) return [self error:error.localizedDescription ?: @"Modrinth request failed"];
        return [self jsonString:@{@"total_hits": result[@"total_hits"] ?: @0, @"hits": result[@"hits"] ?: @[]}];
    }
    NSRegularExpression *versionRoute = [NSRegularExpression regularExpressionWithPattern:@"^/api/modrinth/version/([A-Za-z0-9]{5,12})$" options:0 error:nil];
    NSTextCheckingResult *match = [versionRoute firstMatchInString:route options:0 range:NSMakeRange(0, route.length)];
    if (match) {
        NSString *versionId = [route substringWithRange:[match rangeAtIndex:1]];
        NSDictionary *result = [self fetchJSON:[@"https://api.modrinth.com/v2/version/" stringByAppendingString:versionId] error:&error];
        if (!result) return [self error:error.localizedDescription ?: @"Modrinth request failed"];
        NSDictionary *selected = nil;
        for (NSDictionary *file in [result[@"files"] isKindOfClass:NSArray.class] ? result[@"files"] : @[]) {
            if (![file isKindOfClass:NSDictionary.class]) continue;
            if (!selected || [file[@"primary"] boolValue]) selected = file;
            if ([file[@"primary"] boolValue]) break;
        }
        NSURL *fileURL = [NSURL URLWithString:selected[@"url"] ?: @""];
        if (!fileURL || ![fileURL.scheme isEqualToString:@"https"] || ![fileURL.host isEqualToString:@"cdn.modrinth.com"]) return [self error:@"No valid Modrinth pack file was found"];
        return [self jsonString:@{@"version": result[@"version_number"] ?: result[@"name"] ?: @"Latest",
                                  @"game_versions": result[@"game_versions"] ?: @[], @"loaders": result[@"loaders"] ?: @[],
                                  @"file": @{@"url": fileURL.absoluteString, @"filename": selected[@"filename"] ?: @"modpack.mrpack", @"size": selected[@"size"] ?: @0}}];
    }
    return [self error:@"API route not found"];
}

@end

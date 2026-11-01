#import "update.h"

static NSString *const releases=@"https://github.com/007hacky007/nfs-porsche-macos-arm64/releases/";
static NSString *const latestAPI=@"https://api.github.com/repos/007hacky007/nfs-porsche-macos-arm64/releases/latest";
static NSString *const builderImage=@"NFSV-Builder.dmg";   /* .github/workflows/release.yml */
static const NSTimeInterval checkInterval=24*60*60;

NSComparisonResult launcher_compare_versions(NSString *a,NSString *b){
    NSArray *left=[a componentsSeparatedByString:@"."],*right=[b componentsSeparatedByString:@"."];
    for(NSUInteger i=0;i<MAX(left.count,right.count);i++){
        long x=i<left.count?[left[i] integerValue]:0,y=i<right.count?[right[i] integerValue]:0;
        if(x!=y)return x<y?NSOrderedAscending:NSOrderedDescending;
    }
    return NSOrderedSame;
}

BOOL launcher_update_checks_enabled(NSUserDefaults *defaults){
    id value=[defaults objectForKey:@"LaunchCheckUpdates"];
    return [value isKindOfClass:NSNumber.class]?[value boolValue]:YES;
}

static BOOL release_link(id value){
    return [value isKindOfClass:NSString.class]&&[value hasPrefix:releases]&&[NSURL URLWithString:value];
}

NSDictionary *launcher_parse_release(NSData *body){
    if(!body)return nil;
    NSDictionary *release=[NSJSONSerialization JSONObjectWithData:body options:0 error:nil];
    if(![release isKindOfClass:NSDictionary.class])return nil;
    NSString *tag=release[@"tag_name"],*page=release[@"html_url"];
    if(![tag isKindOfClass:NSString.class]||!release_link(page)||[release[@"draft"] isEqual:@YES]||[release[@"prerelease"] isEqual:@YES])return nil;
    NSString *version=[tag hasPrefix:@"v"]||[tag hasPrefix:@"V"]?[tag substringFromIndex:1]:tag;
    NSRegularExpression *numeric=[NSRegularExpression regularExpressionWithPattern:@"^[0-9]{1,6}(\\.[0-9]{1,6}){0,3}$" options:0 error:nil];
    if(![numeric firstMatchInString:version options:0 range:NSMakeRange(0,version.length)])return nil;
    NSString *download=page;
    NSArray *assets=release[@"assets"];
    if([assets isKindOfClass:NSArray.class])for(NSDictionary *asset in assets){
        if([asset isKindOfClass:NSDictionary.class]&&[asset[@"name"] isEqual:builderImage]&&release_link(asset[@"browser_download_url"]))
            download=asset[@"browser_download_url"];
    }
    return @{@"version":version,@"page":page,@"download":download};
}

NSDictionary *launcher_pending_update(NSUserDefaults *defaults,NSString *stamp){
    NSString *version=[defaults stringForKey:@"UpdateLatestVersion"],*page=[defaults stringForKey:@"UpdateLatestPage"];
    NSString *download=[defaults stringForKey:@"UpdateLatestDownload"],*dismissed=[defaults stringForKey:@"UpdateDismissedVersion"];
    if(!stamp.length||!version||!release_link(page)||!release_link(download))return nil;
    if(launcher_compare_versions(version,stamp)!=NSOrderedDescending)return nil;
    if(dismissed&&launcher_compare_versions(version,dismissed)!=NSOrderedDescending)return nil;
    return @{@"version":version,@"page":page,@"download":download};
}

BOOL launcher_check_for_update(NSUserDefaults *defaults,NSString *stamp,NSDate *now,NFSVFetcher fetcher,void (^found)(NSDictionary *)){
    if(!stamp.length||!launcher_update_checks_enabled(defaults))return NO;
    NSDate *last=[defaults objectForKey:@"UpdateLastCheck"];
    if([last isKindOfClass:NSDate.class]){
        NSTimeInterval age=[now timeIntervalSinceDate:last];
        if(age>=0&&age<checkInterval)return NO;   /* a clock set back counts as due */
    }
    [defaults setObject:now forKey:@"UpdateLastCheck"];   /* failures wait a day too */
    fetcher(launcher_update_request(),^(NSData *body){
        NSDictionary *release=launcher_parse_release(body);
        if(!release)return;
        [defaults setObject:release[@"version"] forKey:@"UpdateLatestVersion"];
        [defaults setObject:release[@"page"] forKey:@"UpdateLatestPage"];
        [defaults setObject:release[@"download"] forKey:@"UpdateLatestDownload"];
        NSDictionary *pending=launcher_pending_update(defaults,stamp);
        if(pending)found(pending);
    });
    return YES;
}

void launcher_dismiss_update(NSUserDefaults *defaults,NSString *version){
    if(version)[defaults setObject:version forKey:@"UpdateDismissedVersion"];
}

NSURLRequest *launcher_update_request(void){
    NSMutableURLRequest *request=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:latestAPI]
                                                         cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:5];
    [request setValue:@"NFSV-Launcher" forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    return request;
}

NFSVFetcher launcher_github_fetcher(void){
    return ^(NSURLRequest *request,NFSVFetchCompletion done){
        NSURLSessionConfiguration *configuration=NSURLSessionConfiguration.ephemeralSessionConfiguration;
        configuration.timeoutIntervalForRequest=5;configuration.timeoutIntervalForResource=5;
        configuration.HTTPShouldSetCookies=NO;configuration.HTTPCookieStorage=nil;configuration.URLCache=nil;
        NSURLSession *session=[NSURLSession sessionWithConfiguration:configuration delegate:nil delegateQueue:NSOperationQueue.mainQueue];
        [[session dataTaskWithRequest:request completionHandler:^(NSData *data,NSURLResponse *response,NSError *error){
            BOOL ok=!error&&[response isKindOfClass:NSHTTPURLResponse.class]&&((NSHTTPURLResponse *)response).statusCode==200;
            done(ok?data:nil);
        }] resume];
        [session finishTasksAndInvalidate];
    };
}

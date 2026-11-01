#import <Foundation/Foundation.h>
/* Looks for a newer NFSV Builder release on GitHub, at most once a day and only when the app
 * carries the Builder version that built it (Info.plist NFSBuilderVersion). The launcher only
 * shows a notice; downloading is left to the browser. */
typedef void (^NFSVFetchCompletion)(NSData *body);
typedef void (^NFSVFetcher)(NSURLRequest *request,NFSVFetchCompletion done);

NSComparisonResult launcher_compare_versions(NSString *,NSString *);
BOOL launcher_update_checks_enabled(NSUserDefaults *);
/* @{@"version",@"page",@"download"} from a GitHub release, or nil if it is not a usable release. */
NSDictionary *launcher_parse_release(NSData *);
/* The remembered release newer than `stamp` that was not dismissed, or nil. */
NSDictionary *launcher_pending_update(NSUserDefaults *,NSString *stamp);
/* Sends one request through `fetcher` when checks are on, the app has a stamp and the last check
 * is a day old; calls `found` with the release to show. Returns whether a request was sent. */
BOOL launcher_check_for_update(NSUserDefaults *,NSString *stamp,NSDate *now,NFSVFetcher fetcher,void (^found)(NSDictionary *));
void launcher_dismiss_update(NSUserDefaults *,NSString *version);
NSURLRequest *launcher_update_request(void);
NFSVFetcher launcher_github_fetcher(void);

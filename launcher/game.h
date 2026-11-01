#import <Foundation/Foundation.h>
/* The prepared game files that the build places in the app's Resources/Game.
 * Returns nil and sets *problem when they are missing or do not match this build. */
NSURL *launcher_bundled_game(NSURL *resources,unsigned long long exeSize,NSString *exeSHA256,NSString **problem);
/* Older launchers stored an outside game folder; the app no longer uses one. */
void launcher_forget_game_folder(NSUserDefaults *);

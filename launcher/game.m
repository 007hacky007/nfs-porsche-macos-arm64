#import "game.h"
#import <CommonCrypto/CommonDigest.h>

static NSString *incomplete(NSString *detail){
    return [NSString stringWithFormat:@"This copy of NFSV.app is incomplete: %@ The app carries all of its game files inside and cannot use a game folder from elsewhere. Build NFSV.app again with NFSV Builder.",detail];
}

NSURL *launcher_bundled_game(NSURL *resources,unsigned long long exeSize,NSString *exeSHA256,NSString **problem){
    NSURL *folder=[resources URLByAppendingPathComponent:@"Game" isDirectory:YES];
    NSFileManager *files=NSFileManager.defaultManager;BOOL directory=NO;
    if(!resources||![files fileExistsAtPath:folder.path isDirectory:&directory]||!directory){
        *problem=incomplete(@"its game files are missing.");return nil;
    }
    for(NSString *name in @[@"GameData",@"FEData",@"fe.txt",@"install.txt"]){
        if(![files fileExistsAtPath:[folder URLByAppendingPathComponent:name].path]){
            *problem=incomplete([NSString stringWithFormat:@"its game files are missing %@.",name]);return nil;
        }
    }
    NSData *exe=[NSData dataWithContentsOfURL:[folder URLByAppendingPathComponent:@"Porsche.exe"] options:NSDataReadingMappedIfSafe error:nil];
    if(!exe){*problem=incomplete(@"its game files are missing Porsche.exe.");return nil;}
    NSMutableString *hex=[NSMutableString new];
    if(exe.length==exeSize){
        unsigned char digest[CC_SHA256_DIGEST_LENGTH];CC_SHA256(exe.bytes,(CC_LONG)exe.length,digest);
        for(unsigned i=0;i<sizeof digest;i++)[hex appendFormat:@"%02x",digest[i]];
    }
    if(![hex isEqualToString:exeSHA256]){*problem=incomplete(@"its Porsche.exe does not match the native code in this app.");return nil;}
    *problem=nil;return folder;
}

void launcher_forget_game_folder(NSUserDefaults *defaults){
    if([defaults objectForKey:@"GameFolder"])[defaults removeObjectForKey:@"GameFolder"];
}

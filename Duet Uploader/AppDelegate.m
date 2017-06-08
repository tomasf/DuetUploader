//
//  AppDelegate.m
//  Duet Uploader
//
//  Created by Tomas Franzén on 2016-10-02.
//  Copyright © 2016 Tomas Franzén. All rights reserved.
//

#import "AppDelegate.h"

@interface AppDelegate ()
@end


@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{@"port": @80}];
}


- (void)applicationWillTerminate:(NSNotification *)aNotification {
	// Insert code here to tear down your application
}


- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender {
	return NO;
}


@end

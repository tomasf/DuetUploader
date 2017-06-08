//
//  TFDUDocument.m
//  Duet Uploader
//
//  Created by Tomas Franzén on 2016-10-03.
//  Copyright © 2016 Tomas Franzén. All rights reserved.
//

#import "TFDUDocument.h"
#import "ViewController.h"


@implementation TFDUDocument

- (void)makeWindowControllers {
	NSWindowController *windowController = [[NSStoryboard storyboardWithName:@"Main" bundle:nil] instantiateControllerWithIdentifier:@"document"];
	[self addWindowController:windowController];
	ViewController *viewController = (ViewController*)windowController.contentViewController;
	viewController.document = self;
}


- (NSData *)dataOfType:(NSString *)typeName error:(NSError **)outError {
    if (outError) {
        *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:unimpErr userInfo:nil];
    }
    return nil;
}


- (BOOL)readFromData:(NSData *)data ofType:(NSString *)typeName error:(NSError **)outError {
    NSString *hostname = [[NSUserDefaults standardUserDefaults] stringForKey:@"hostname"];
    
    if (!hostname) {
        NSLog(@"No hostname");
        *outError = [NSError
                     errorWithDomain:@"se.tomasf.duetUploader"
                     code:1
                     userInfo:@{
                                NSLocalizedFailureReasonErrorKey: @"Please specify a hostname first in Preferences."
                                }];
        NSWindowController *prefs = [[NSStoryboard storyboardWithName:@"Main" bundle:nil] instantiateControllerWithIdentifier:@"preferences"];
        [prefs showWindow:nil];
        return NO;
    }
    
	return YES;
}


+ (BOOL)autosavesInPlace {
    return YES;
}


@end

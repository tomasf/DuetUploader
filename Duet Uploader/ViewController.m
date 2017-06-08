//
//  ViewController.m
//  Duet Uploader
//
//  Created by Tomas Franzén on 2016-10-02.
//  Copyright © 2016 Tomas Franzén. All rights reserved.
//

#import "ViewController.h"
#import "MAKVONotificationCenter.h"
#import "TFDPrinter.h"
#import "TFDExtras.h"
#import "TFDUDocument.h"
#import "TFPUProgressViewController.h"


@interface TFPUItem : NSObject
@property TFDPrinterDirectoryItem *info;
@property (copy) NSArray <TFPUItem*> *children;
@end


@implementation TFPUItem

- (BOOL)leaf {
	return !self.info.isDirectory;
}

@end


@interface TFDPrinterDirectoryItem (Private)
@property (copy, readwrite) NSString *name;
@property (copy, readwrite) NSString *path;
@property (readwrite) uint64_t size;
@property (readwrite) BOOL isDirectory;
@end




@interface ViewController () <NSBrowserDelegate>
@property TFDPrinter *printer;

@property TFPUItem *root;
@property NSArray <NSIndexPath*> *selection;

@property IBOutlet NSBrowser *browser;
@end


@implementation ViewController


- (TFPUItem*)itemForDirectoryItem:(TFDPrinterDirectoryItem*)info {
	TFPUItem *item = [TFPUItem new];
	item.info = info;
	item.children = nil;
	return item;
}


- (void)viewDidLoad {
	[super viewDidLoad];
	__weak __typeof__(self) weakSelf = self;
	
    
    NSString *hostname = [[NSUserDefaults standardUserDefaults] stringForKey:@"hostname"];
    NSInteger port = [[NSUserDefaults standardUserDefaults] integerForKey:@"port"];
    
	self.printer = [[TFDPrinter alloc] initWithHostname:hostname port:port updatingAutomatically:NO];

	TFDPrinterDirectoryItem *root = [TFDPrinterDirectoryItem new];
	root.path = @"/gcodes";
	root.isDirectory = YES;
	self.root = [self itemForDirectoryItem:root];
	[self loadChildrenForItemIfNeeded:self.root];
	
	
	[self addObserver:self keyPath:@"selection" options:0 block:^(MAKVONotification *notification) {
		if (self.selection.count == 1) {
			[weakSelf loadChildrenForIndexPathIfNeeded:weakSelf.selection.firstObject];
		}
	}];
}


- (NSInteger)columnContainingChildrenOfItem:(TFPUItem*)item {
	for (NSUInteger i=0; i<=self.browser.lastColumn; i++) {
		if ([self.browser parentForItemsInColumn:i] == item) {
			return i;
		}
	}
	return -1;
}


- (void)loadChildrenForItemIfNeeded:(TFPUItem*)item {
	__weak __typeof__(self) weakSelf = self;
	
	if (item.info.isDirectory && !item.children) {
		[self.printer fetchDirectoryListingForPath:item.info.path resultHandler:^(NSArray<TFDPrinterDirectoryItem *> *items) {
			item.children = [items tf_mapWithBlock:^id(TFDPrinterDirectoryItem *info) {
				return [weakSelf itemForDirectoryItem:info];
			}];
			
			NSInteger column = [weakSelf columnContainingChildrenOfItem:item];
			if (column != -1) {
				[weakSelf.browser reloadColumn:column];
			}
		}];
	}
}


- (void)loadChildrenForIndexPathIfNeeded:(NSIndexPath*)indexPath {
	TFPUItem *item = self.root;
	for (NSUInteger i=0; i<indexPath.length; i++) {
		NSUInteger index = [indexPath indexAtPosition:i];
		item = item.children[index];
	}
	
	[self loadChildrenForItemIfNeeded:item];
}


- (NSInteger)browser:(NSBrowser *)sender numberOfRowsInColumn:(NSInteger)column {
	return 1;
}


- (id)browser:(NSBrowser *)browser objectValueForItem:(TFPUItem*)item {
	return item.info.displayName;
}


- (id)rootItemForBrowser:(NSBrowser *)browser {
	return self.root;
}


- (BOOL)browser:(NSBrowser *)browser isLeafItem:(TFPUItem*)item {
	return !item.info.isDirectory;
}

- (id)browser:(NSBrowser *)browser child:(NSInteger)index ofItem:(TFPUItem*)item {
	return item.children[index];
}


- (NSInteger)browser:(NSBrowser *)browser numberOfChildrenOfItem:(TFPUItem*)item {
	return item.children.count;
}


- (NSIndexSet *)browser:(NSBrowser *)browser selectionIndexesForProposedSelection:(NSIndexSet *)proposedSelectionIndexes inColumn:(NSInteger)column {
	if (proposedSelectionIndexes.count == 0) {
		return proposedSelectionIndexes;
	}
	
	TFPUItem *item = [browser itemAtRow:proposedSelectionIndexes.firstIndex inColumn:column];
	
	if (item.info.isDirectory) {
		[self loadChildrenForItemIfNeeded:item];
		return proposedSelectionIndexes;
	} else {
		return [NSIndexSet indexSet];
	}
	
}

- (void)browser:(NSBrowser *)browser willDisplayCell:(NSTextFieldCell*)cell atRow:(NSInteger)row column:(NSInteger)column {
	TFPUItem *item = [browser itemAtRow:row inColumn:column];
	cell.textColor = item.info.isDirectory ? [NSColor blackColor] : [NSColor grayColor];
}


- (IBAction)upload:(id)sender {
	NSData *data = [NSData dataWithContentsOfURL:self.document.fileURL];
	if (!data) {
		return;
	}
	NSString *uploadPath;
	
	NSInteger column = self.browser.lastColumn-1;
	if (column < 0) {
		uploadPath = [self.root.info.path stringByAppendingPathComponent:self.document.fileURL.lastPathComponent];
	} else {
		NSInteger row = [self.browser selectedRowInColumn:column];
		if (row == -1) {
			return;
		}
		
		TFPUItem *item = [self.browser itemAtRow:row inColumn:column];
		uploadPath = [item.info.path stringByAppendingPathComponent:self.document.fileURL.lastPathComponent];
	}
	
	TFPUProgressViewController *viewController = [self.storyboard instantiateControllerWithIdentifier:@"progress"];
	[self presentViewControllerAsSheet:viewController];
	
	viewController.progressIndicator.minValue = 0;
	
	[self.printer uploadFile:data toPath:uploadPath progress:^(int64_t sent, int64_t total) {
		viewController.progressIndicator.maxValue = total;
		viewController.progressIndicator.doubleValue = sent;
	} completion:^(NSError *error) {
		[self.view.window endSheet:viewController.view.window];
		[viewController.view.window orderOut:nil];
		[self dismissController:viewController];
		if (error) {
			
			
		} else {
			NSAlert *alert = [NSAlert new];
			alert.messageText = @"Upload completed";
			alert.informativeText = [NSString stringWithFormat:@"Do you want to print \"%@\"?", self.document.fileURL.lastPathComponent];
			[alert addButtonWithTitle:@"Print"];
			[alert addButtonWithTitle:@"Don't Print"];
			
			[alert beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse returnCode) {
				if(returnCode == NSAlertFirstButtonReturn) {
					[self.printer printFile:uploadPath completion:^{
						[self.document close];
					}];
				}else{
					[self.document close];
				}
			}];
		}
	}];
}


@end

#import <Foundation/Foundation.h>
#import "OITIBaseListController.h"
#import <OITCore/OITCore.h>
#import <UIKit/UIKit.h>

@implementation OITIBaseListController

- (NSString *)oiti_plistName {
    return nil; // subclasses override
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSString *name = [self oiti_plistName];
        if (name.length) {
            _specifiers = [self loadSpecifiersFromPlistName:name target:self];
        }
    }
    return _specifiers;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    UIBarButtonItem *respring = [[UIBarButtonItem alloc] initWithTitle:@"Respring"
                                                                 style:UIBarButtonItemStylePlain
                                                                target:self
                                                                action:@selector(respringAsk:)];
    self.navigationItem.rightBarButtonItem = respring;
}

- (void)respringAsk:(id)sender {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Respring"
                                                                   message:@"You are about to respring."
                                                            preferredStyle:UIAlertControllerStyleAlert];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Respring"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) {
                                                [self respring];
                                            }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)respring {
    OITRequestRespring();
}

- (void)savePos {
    [self.view endEditing:YES];
}

@end

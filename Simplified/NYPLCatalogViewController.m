#import <SMXMLDocument/SMXMLDocument.h>

#import "NYPLAsyncData.h"
#import "NYPLCatalogLane.h"
#import "NYPLCatalogLaneCell.h"
#import "NYPLCatalogRoot.h"
#import "NYPLConfiguration.h"
#import "NYPLOPDSEntry.h"
#import "NYPLOPDSFeed.h"
#import "NYPLOPDSLink.h"

#import "NYPLCatalogViewController.h"

static CGFloat const rowHeight = 125.0;
static CGFloat const sectionHeaderHeight = 30.0;

@interface NYPLCatalogViewController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic) UIActivityIndicatorView *activityIndicatorView;
@property (nonatomic) NYPLCatalogRoot *catalogRoot;
@property (nonatomic) NSMutableDictionary *cachedCells;
@property (nonatomic) NSMutableDictionary *imageDataDictionary;
@property (nonatomic) NSUInteger indexOfNextLaneRequiringImageDownload;
@property (nonatomic) UITableView *tableView;
@property (nonatomic) NSDictionary *urlToCategoryFeedDataDictionary;

@end

@implementation NYPLCatalogViewController

#pragma mark NSObject

- (id)init
{
  self = [super init];
  if(!self) return nil;
  
  self.cachedCells = [NSMutableDictionary dictionary];
  self.imageDataDictionary = [NSMutableDictionary dictionary];
  self.title = NSLocalizedString(@"CatalogViewControllerTitle", nil);
  
  return self;
}

#pragma mark UIViewController

- (void)viewDidLoad
{
  self.view.backgroundColor = [UIColor whiteColor];
  
  self.activityIndicatorView = [[UIActivityIndicatorView alloc]
                                initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
  [self.view addSubview:self.activityIndicatorView];
  
  self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
  self.tableView.autoresizingMask = (UIViewAutoresizingFlexibleWidth |
                                     UIViewAutoresizingFlexibleHeight);
  self.tableView.dataSource = self;
  self.tableView.delegate = self;
  self.tableView.sectionHeaderHeight = sectionHeaderHeight;
  self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
  self.tableView.allowsSelection = NO;
  self.tableView.hidden = YES;
  [self.view addSubview:self.tableView];
  
  [self downloadFeed];
}

- (void)viewWillLayoutSubviews
{
  self.activityIndicatorView.center = self.view.center;
  
  UIEdgeInsets const insets = UIEdgeInsetsMake(self.topLayoutGuide.length,
                                               0,
                                               self.bottomLayoutGuide.length,
                                               0);
  
  self.tableView.contentInset = insets;
  self.tableView.scrollIndicatorInsets = insets;
}

#pragma mark UITableViewDataSource

- (UITableViewCell *)tableView:(__attribute__((unused)) UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *const)indexPath
{
  UITableViewCell *const cachedCell = [self.cachedCells objectForKey:indexPath];
  if(cachedCell) {
    return cachedCell;
  }
  
  if(indexPath.section < (NSInteger) self.indexOfNextLaneRequiringImageDownload) {
    UITableViewCell *const cell =
      [[NYPLCatalogLaneCell alloc]
       initWithLaneIndex:indexPath.section
       books:((NYPLCatalogLane *) self.catalogRoot.lanes[indexPath.section]).books
       imageDataDictionary:self.imageDataDictionary];
    [self.cachedCells setObject:cell forKey:indexPath];
    return cell;
  } else {
    // FIXME: This does not always seem to show when it should.
    return [[UITableViewCell alloc] init];
  }
}

- (NSInteger)tableView:(__attribute__((unused)) UITableView *)tableView
 numberOfRowsInSection:(__attribute__((unused)) NSInteger)section
{
  return 1;
}

- (NSInteger)numberOfSectionsInTableView:(__attribute__((unused)) UITableView *)tableView
{
  return self.catalogRoot.lanes.count;
}

#pragma mark UITableViewDelegate

- (CGFloat)tableView:(__attribute__((unused)) UITableView *)tableView
heightForRowAtIndexPath:(__attribute__((unused)) NSIndexPath *)indexPath
{
  return rowHeight;
}

- (CGFloat)tableView:(__attribute__((unused)) UITableView *)tableView
heightForHeaderInSection:(__attribute__((unused)) NSInteger)section
{
  return sectionHeaderHeight;
}

- (UIView *)tableView:(__attribute__((unused)) UITableView *)tableView
viewForHeaderInSection:(NSInteger const)section
{
  CGRect const frame = CGRectMake(0, 0, self.tableView.frame.size.width, sectionHeaderHeight);
  UIView *const view = [[UIView alloc] initWithFrame:frame];
  view.autoresizingMask = UIViewAutoresizingFlexibleWidth;
  
  {
    CGRect const frame = CGRectMake(5,
                                    5,
                                    self.tableView.frame.size.width,
                                    sectionHeaderHeight - 10);
    UILabel *const label = [[UILabel alloc] initWithFrame:frame];
    label.text = ((NYPLCatalogLane *) self.catalogRoot.lanes[section]).title;
    [view addSubview:label];
  }
  
  view.backgroundColor = [UIColor whiteColor];
  
  return view;
}

#pragma mark -

- (void)downloadFeed
{
  self.tableView.hidden = YES;
  self.activityIndicatorView.hidden = NO;
  [self.activityIndicatorView startAnimating];
  
  [NYPLCatalogRoot
   withURL:[NYPLConfiguration mainFeedURL]
   handler:^(NYPLCatalogRoot *const root) {
     [[NSOperationQueue mainQueue] addOperationWithBlock:^{
       self.activityIndicatorView.hidden = YES;
       [self.activityIndicatorView stopAnimating];
       
       if(!root) {
         [[[UIAlertView alloc]
           initWithTitle:NSLocalizedString(@"CatalogViewControllerFeedDownloadFailedTitle", nil)
           message:NSLocalizedString(@"CatalogViewControllerFeedDownloadFailedMessage", nil)
           delegate:nil
           cancelButtonTitle:nil
           otherButtonTitles:NSLocalizedString(@"OK", nil), nil]
          show];
         return;
       }
       
       self.tableView.hidden = NO;
       self.catalogRoot = root;
       [self.tableView reloadData];
       
       [self downloadImages];
     }];
   }];
}

- (void)downloadImages
{
  if(self.indexOfNextLaneRequiringImageDownload >= self.catalogRoot.lanes.count) {
    return;
  }
  
  NYPLCatalogLane *const lane = self.catalogRoot.lanes[self.indexOfNextLaneRequiringImageDownload];
  
  [NYPLAsyncData
   withURLSet:lane.imageURLs
   completionHandler:^(NSDictionary *const dataDictionary) {
     [[NSOperationQueue mainQueue] addOperationWithBlock:^{
       [dataDictionary enumerateKeysAndObjectsUsingBlock:^(id const key,
                                                           id const value,
                                                           __attribute__((unused)) BOOL *stop) {
         if(![value isKindOfClass:[NSNull class]]) {
           assert([key isKindOfClass:[NSURL class]]);
           assert([value isKindOfClass:[NSData class]]);
           [self.imageDataDictionary setValue:value forKey:key];
         }
       }];
       
       [self.tableView reloadData];
       ++self.indexOfNextLaneRequiringImageDownload;
       [self downloadImages];
     }];
   }];
}

@end

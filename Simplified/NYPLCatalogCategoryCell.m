#import "NYPLSession.h"

#import "NYPLCatalogCategoryCell.h"

@interface NYPLCatalogCategoryCell ()

@property (nonatomic) UILabel *author;
@property (nonatomic) UIImageView *cover;
@property (nonatomic) UILabel *title;
@property (nonatomic) NSURL *coverURL;

@end

@implementation NYPLCatalogCategoryCell

#pragma mark UIView

- (void)layoutSubviews
{
  self.cover.frame = CGRectMake(5, 5, 90, self.frame.size.height - 10);
  
  [self.title sizeToFit];
  CGRect titleFrame = self.title.frame;
  titleFrame.origin = CGPointMake(100, 5);
  titleFrame.size.width = self.frame.size.width - 105;
  self.title.frame = titleFrame;
  
  [self.author sizeToFit];
  CGRect authorFrame = self.author.frame;
  authorFrame.origin = CGPointMake(100, titleFrame.origin.y + titleFrame.size.height + 5);
  authorFrame.size.width = self.frame.size.width - 105;
  self.author.frame = authorFrame;
}

#pragma mark -

- (void)setBook:(NYPLCatalogBook *const)book
{
  if(!self.author) {
    self.author = [[UILabel alloc] initWithFrame:CGRectZero];
    [self addSubview:self.author];
  }
  
  if(!self.cover) {
    self.cover = [[UIImageView alloc] initWithFrame:CGRectZero];
    [self addSubview:self.cover];
  }
  
  if(!self.title) {
    self.title = [[UILabel alloc] initWithFrame:CGRectZero];
    [self addSubview:self.title];
  }
  
  self.author.text = [book.authorStrings componentsJoinedByString:@"; "];
  self.cover.image = nil;
  self.coverURL = book.imageURL;
  self.title.text = book.title;
  
  // TODO: The approach below will keep showing old covers across launches even if they've been
  // updated on the server. Consider if there's a better way to do this.
  
  // This avoids hitting the server constantly when scrolling within a category and ensures images
  // will still be there when the user scrolls back up. It also avoids creating tasks and refetching
  // images when the collection view reloads its data in response to an additional page being
  // fetched (which otherwise would cause a flickering effect and pointless bandwidth usage).
  self.cover.image = [UIImage imageWithData:
                      [[NYPLSession sharedSession] cachedDataForURL:book.imageURL]];
  
  if(!self.cover.image) {
    [[NYPLSession sharedSession]
     withURL:book.imageURL
     completionHandler:^(NSData *const data) {
       [[NSOperationQueue mainQueue] addOperationWithBlock:^{
         // TODO: This check prevents old operations from overwriting cover images in the case of
         // cells being reused before those operations completed. It avoids visual bugs, but said
         // operations should be killed to avoid unnecesssary bandwidth usage. Once that is in
         // place, this check and |self.coverURL| may no longer be needed.
         if([book.imageURL isEqual:self.coverURL]) {
           self.cover.image = [UIImage imageWithData:data];
           [self.cover sizeToFit];
           // Drop the now-useless URL reference.
           self.coverURL = nil;
         }
       }];
     }];
  }
  
  [self setNeedsLayout];
}

@end
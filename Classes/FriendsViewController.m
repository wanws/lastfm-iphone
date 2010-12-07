/* FriendsViewController.m - Display Last.fm friends list
 * 
 * Copyright 2009 Last.fm Ltd.
 *   - Primarily authored by Sam Steele <sam@last.fm>
 *
 * This file is part of MobileLastFM.
 *
 * MobileLastFM is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * MobileLastFM is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with MobileLastFM.  If not, see <http://www.gnu.org/licenses/>.
 */

#import "FriendsViewController.h"
#import "ProfileViewController.h"
#import "RadioListViewController.h"
#import "ArtworkCell.h"
#import "UIViewController+NowPlayingButton.h"
#import "MobileLastFMApplicationDelegate.h"
#import "UITableViewCell+ProgressIndicator.h"
#import "HomeViewController.h"
#include "version.h"

int usernameSort(id friend1, id friend2, void *reverse) {
	if ((int *)reverse == NO) {
		return [[friend2 objectForKey:@"username"] localizedCaseInsensitiveCompare:[friend1 objectForKey:@"username"]];
	}
	return [[friend1 objectForKey:@"username"] localizedCaseInsensitiveCompare:[friend2 objectForKey:@"username"]];
}

@implementation FriendsViewController
@synthesize delegate;

- (id)initWithUsername:(NSString *)username {
	UInt32 reverseSort = NO;
	
	if (self = [super initWithStyle:UITableViewStyleGrouped]) {
		_data = [[[[LastFMService sharedInstance] friendsOfUser:username] sortedArrayUsingFunction:usernameSort context:&reverseSort] retain];
		if([LastFMService sharedInstance].error) {
			[((MobileLastFMApplicationDelegate *)([UIApplication sharedApplication].delegate)) reportError:[LastFMService sharedInstance].error];
			[self release];
			return nil;
		}
		if(![_data count]) {
			[((MobileLastFMApplicationDelegate *)([UIApplication sharedApplication].delegate)) displayError:NSLocalizedString(@"FRIENDS_EMPTY", @"No friends") withTitle:NSLocalizedString(@"FRIENDS_EMPTY_TITLE", @"No friends title")];
			[self release];
			return nil;
		}
		_friendsListeningNow = [[[LastFMService sharedInstance] nowListeningFriendsOfUser:username] retain];
		self.title = @"Friends";
		UISegmentedControl *toggle = [[UISegmentedControl alloc] initWithItems:[NSArray arrayWithObjects:@"Friends Activity", @"All Friends", nil]];
		toggle.segmentedControlStyle = UISegmentedControlStyleBar;
		toggle.selectedSegmentIndex = 0;
		CGRect frame = toggle.frame;
		frame.size.width = self.view.frame.size.width - 20;
		toggle.frame = frame;
		[toggle addTarget:self
							 action:@selector(viewWillAppear:)
		 forControlEvents:UIControlEventValueChanged];
		self.navigationItem.titleView = toggle;
		UIBarButtonItem *backBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Friends", @"Friends back button title") style:UIBarButtonItemStylePlain target:nil action:nil];
		self.navigationItem.backBarButtonItem = backBarButtonItem;
		[backBarButtonItem release];
		_username = [username retain];
	}
	return self;
}
- (void)cancelButtonPressed:(id)sender {
	[delegate friendsViewControllerDidCancel:self];
}
- (void)viewDidLoad {
//	self.tableView.indicatorStyle = UIScrollViewIndicatorStyleWhite;
	UISearchBar *bar = [[UISearchBar alloc] initWithFrame:CGRectMake(0,0,self.view.bounds.size.width, 45)];
	bar.placeholder = @"Search Friends";
	self.tableView.tableHeaderView = bar;

	UISearchDisplayController *searchController = [[UISearchDisplayController alloc] initWithSearchBar:bar contentsController:self];
	searchController.delegate = self;
	searchController.searchResultsDataSource = self;
	searchController.searchResultsDelegate = self;
	[bar release];
}
- (BOOL)searchDisplayController:(UISearchDisplayController *)controller shouldReloadTableForSearchString:(NSString *)query {
	[_searchResults release];
	_searchResults = nil;
	if([query length]) {
		_searchResults = [[NSMutableArray alloc] init];
		query = [query lowercaseString];
		for (NSDictionary *friend in _data) {
			if ([[[friend objectForKey:@"username"] lowercaseString] rangeOfString:query].location == 0 || 
					([friend objectForKey:@"realname"] && [[[friend objectForKey:@"realname"] lowercaseString] rangeOfString:query].location == 0)) {
				[_searchResults addObject:friend];
			}
		} 
	}
	return YES;
}
- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	if(delegate) {
		self.navigationItem.titleView = nil;
		UIBarButtonItem *cancel = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Cancel", @"Cancel")
																															 style:UIBarButtonItemStylePlain
																															target:self
																															action:@selector(cancelButtonPressed:)];
		self.navigationItem.rightBarButtonItem = cancel;
		[cancel release];
	} else {
		[self showNowPlayingButton:[(MobileLastFMApplicationDelegate *)[UIApplication sharedApplication].delegate isPlaying]];
	}
	[self.tableView reloadData];
	[self loadContentForCells:[self.tableView visibleCells]];
	[self.tableView setContentOffset:CGPointMake(0,self.tableView.tableHeaderView.frame.size.height)];
	[self.tableView.tableHeaderView resignFirstResponder];
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	UISegmentedControl *toggle = (UISegmentedControl *)self.navigationItem.titleView;

	if(section == 0 && toggle != nil && toggle.selectedSegmentIndex == 0 && _searchResults == nil) {
		return @"Friends Listening Now";
	} else {
		return nil;
	}
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 1;
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	UISegmentedControl *toggle = (UISegmentedControl *)self.navigationItem.titleView;

	if(_searchResults)
		return [_searchResults count];
	else if(toggle == nil || toggle.selectedSegmentIndex == 1)
		return [_data count];
	else
		return [_friendsListeningNow count];
}
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	return 52;
}
- (void)_showProfile:(NSTimer *)timer {
	UISegmentedControl *toggle = (UISegmentedControl *)self.navigationItem.titleView;
	NSIndexPath *newIndexPath = timer.userInfo;
	NSArray *source = _data;
	if(_searchResults) {
		source = _searchResults;
	} else if(toggle != nil && toggle.selectedSegmentIndex == 0) {
		source = _friendsListeningNow;
	}
	if(delegate) {
		[delegate friendsViewController:self didSelectFriend:[[source objectAtIndex:[newIndexPath row]] objectForKey:@"username"]];
	} else {
		HomeViewController *home = [[HomeViewController alloc] initWithUsername:[[source objectAtIndex:[newIndexPath row]] objectForKey:@"username"]];
		[((MobileLastFMApplicationDelegate *)[UIApplication sharedApplication].delegate).rootViewController pushViewController:home animated:YES];
		[home release];
		[[self.tableView cellForRowAtIndexPath:newIndexPath] showProgress:NO];
	}
}	
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)newIndexPath {
	[tableView deselectRowAtIndexPath:newIndexPath animated:YES];
	[[tableView cellForRowAtIndexPath:newIndexPath] showProgress:YES];
	[NSTimer scheduledTimerWithTimeInterval:0.5
																	 target:self
																 selector:@selector(_showProfile:)
																 userInfo:newIndexPath
																	repeats:NO];
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UISegmentedControl *toggle = (UISegmentedControl *)self.navigationItem.titleView;
	ArtworkCell *cell;
	if(_searchResults) {
		cell = (ArtworkCell *)[tableView dequeueReusableCellWithIdentifier:[[_searchResults objectAtIndex:[indexPath row]] objectForKey:@"username"]];
		if (cell == nil)
			cell = [[[ArtworkCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:[[_searchResults objectAtIndex:[indexPath row]] objectForKey:@"username"]] autorelease];
	} else if(toggle != nil && toggle.selectedSegmentIndex == 0) {
		cell = (ArtworkCell *)[tableView dequeueReusableCellWithIdentifier:[[_friendsListeningNow objectAtIndex:[indexPath row]] objectForKey:@"username"]];
		if (cell == nil)
			cell = [[[ArtworkCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:[[_friendsListeningNow objectAtIndex:[indexPath row]] objectForKey:@"username"]] autorelease];
	} else {
		cell = (ArtworkCell *)[tableView dequeueReusableCellWithIdentifier:[[_data objectAtIndex:[indexPath row]] objectForKey:@"username"]];
		if (cell == nil)
			cell = [[[ArtworkCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:[[_data objectAtIndex:[indexPath row]] objectForKey:@"username"]] autorelease];
	}
	
	if(_searchResults) {
		cell.title.text = [[_searchResults objectAtIndex:[indexPath row]] objectForKey:@"username"];
		cell.title.backgroundColor = [UIColor whiteColor];
		cell.title.opaque = YES;
		cell.subtitle.text = @"";
		cell.subtitle.backgroundColor = [UIColor whiteColor];
		cell.subtitle.opaque = YES;
		cell.shouldCacheArtwork = YES;
		cell.imageURL = [[_searchResults objectAtIndex:[indexPath row]] objectForKey:@"image"];
		if(!delegate)
			cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		else
			cell.accessoryType = UITableViewCellAccessoryNone;
	} else if(toggle == nil || toggle.selectedSegmentIndex == 1) {
		cell.title.text = [[_data objectAtIndex:[indexPath row]] objectForKey:@"username"];
		cell.title.backgroundColor = [UIColor whiteColor];
		cell.title.opaque = YES;
		cell.subtitle.text = @"";
		cell.subtitle.backgroundColor = [UIColor whiteColor];
		cell.subtitle.opaque = YES;
		cell.shouldCacheArtwork = YES;
		cell.imageURL = [[_data objectAtIndex:[indexPath row]] objectForKey:@"image"];
		if(!delegate)
			cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		else
			cell.accessoryType = UITableViewCellAccessoryNone;
	} else if(toggle.selectedSegmentIndex == 0) {
		cell.title.text = [[_friendsListeningNow objectAtIndex:[indexPath row]] objectForKey:@"username"];
		cell.title.backgroundColor = [UIColor whiteColor];
		cell.title.opaque = YES;
		cell.subtitle.text = [NSString stringWithFormat:@"%@ - %@", [[_friendsListeningNow objectAtIndex:[indexPath row]] objectForKey:@"artist"],
													[[_friendsListeningNow objectAtIndex:[indexPath row]] objectForKey:@"title"]];
		cell.subtitle.backgroundColor = [UIColor whiteColor];
		cell.subtitle.opaque = YES;
		cell.shouldCacheArtwork = YES;
		cell.imageURL = [[_friendsListeningNow objectAtIndex:[indexPath row]] objectForKey:@"image"];
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	}
	return cell;
}
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
	return (interfaceOrientation == UIInterfaceOrientationPortrait);
}
- (void)dealloc {
	[super dealloc];
	[_username release];
	[_friendsListeningNow release];
	[_searchResults release];
	[_data release];
}
@end

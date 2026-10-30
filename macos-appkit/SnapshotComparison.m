#import "SnapshotComparison.h"

static NSArray *PackageKey(NSDictionary *resource) {
    return @[resource[@"canonical_tool_id"], resource[@"kind"], resource[@"installation_provider"] ?: NSNull.null,
             resource[@"provider_package_id"] ?: NSNull.null];
}

static NSDictionary<NSArray *, NSArray *> *PackageGroups(NSArray<NSDictionary *> *resources) {
    NSMutableDictionary *groups = [NSMutableDictionary dictionary];
    for (NSDictionary *resource in resources) {
        NSArray *key = PackageKey(resource);
        if (!groups[key]) groups[key] = [NSMutableArray array];
        [groups[key] addObject:resource];
    }
    return groups;
}

static void RecordChange(NSDictionary *before, NSDictionary *after, NSMutableArray *changed) {
    NSMutableArray *fields = [NSMutableArray array];
    for (NSString *field in @[@"version", @"installation_path", @"path_status"]) {
        id oldValue = before[field] ?: NSNull.null;
        id newValue = after[field] ?: NSNull.null;
        if (![oldValue isEqual:newValue]) [fields addObject:field];
    }
    if (fields.count) [changed addObject:@{@"before": before, @"after": after, @"fields": fields}];
}

static NSArray *SortedResources(NSArray *resources, BOOL changes) {
    return [resources sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        if (changes) { a = a[@"after"]; b = b[@"after"]; }
        for (NSString *key in @[@"display_name", @"canonical_tool_id", @"installation_instance_id"]) {
            NSComparisonResult order = [a[key] compare:b[key] options:NSLiteralSearch];
            if (order != NSOrderedSame) return order;
        }
        return NSOrderedSame;
    }];
}

@implementation SnapshotComparison

+ (NSDictionary *)fromInventory:(NSDictionary *)before toInventory:(NSDictionary *)after {
    NSDictionary *oldGroups = PackageGroups(before[@"resources"]);
    NSDictionary *newGroups = PackageGroups(after[@"resources"]);
    NSMutableSet *keys = [NSMutableSet setWithArray:oldGroups.allKeys];
    [keys addObjectsFromArray:newGroups.allKeys];
    NSMutableArray *added = [NSMutableArray array], *removed = [NSMutableArray array], *changed = [NSMutableArray array];
    for (NSArray *key in keys) {
        NSArray *oldGroup = oldGroups[key] ?: @[];
        NSArray *newGroup = newGroups[key] ?: @[];
        NSMutableArray *unmatched = [oldGroup mutableCopy];
        for (NSDictionary *resource in newGroup) {
            NSUInteger match = [unmatched indexOfObjectPassingTest:^BOOL(NSDictionary *candidate, NSUInteger index __unused, BOOL *stop __unused) {
                return [candidate[@"installation_instance_id"] isEqual:resource[@"installation_instance_id"]];
            }];
            if (match != NSNotFound) {
                RecordChange(unmatched[match], resource, changed);
                [unmatched removeObjectAtIndex:match];
            } else if (oldGroup.count == 1 && newGroup.count == 1) {
                // Some installers change instance IDs on upgrade; pair only an unambiguous package.
                RecordChange(oldGroup.firstObject, resource, changed);
                [unmatched removeAllObjects];
            } else {
                [added addObject:resource];
            }
        }
        [removed addObjectsFromArray:unmatched];
    }
    return @{@"added": SortedResources(added, NO), @"removed": SortedResources(removed, NO), @"changed": SortedResources(changed, YES)};
}
@end

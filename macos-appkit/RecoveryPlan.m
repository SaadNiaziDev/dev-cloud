#import "RecoveryPlan.h"
#import "CloudInventory.h"

NSArray<NSDictionary *> *RecoveryPlan(NSData *backup, NSDictionary *current, NSError **error) {
    id saved = backup.length <= CloudInventoryMaxBytes ? [NSJSONSerialization JSONObjectWithData:backup options:0 error:nil] : nil;
    NSData *normalized = [saved isKindOfClass:NSDictionary.class] ? CloudInventoryData(saved, NULL, nil) : nil;
    id validated = normalized ? [NSJSONSerialization JSONObjectWithData:normalized options:0 error:nil] : nil;
    NSData *currentData = [current isKindOfClass:NSDictionary.class] ? CloudInventoryData(current, NULL, nil) : nil;
    id destination = currentData ? [NSJSONSerialization JSONObjectWithData:currentData options:0 error:nil] : nil;
    if (!validated || ![saved isEqual:validated] || !destination) {
        if (error) *error = [NSError errorWithDomain:@"DevCloudRecovery" code:1 userInfo:@{NSLocalizedDescriptionKey: @"The backup or current scan is invalid. Scan again and select a verified backup."}];
        return nil;
    }
    NSMutableDictionary<NSString *, NSMutableArray *> *installed = [NSMutableDictionary dictionary];
    for (NSDictionary *item in destination[@"resources"]) {
        NSString *identifier = item[@"canonical_tool_id"];
        if (!installed[identifier]) installed[identifier] = [NSMutableArray array];
        [installed[identifier] addObject:item];
    }
    NSMutableArray *plan = [NSMutableArray array];
    for (NSDictionary *item in validated[@"resources"]) {
        NSString *identifier = item[@"canonical_tool_id"];
        NSArray *matches = installed[identifier];
        BOOL same = [matches containsObject:item];
        NSString *status = same ? (item[@"version"] == NSNull.null ? @"Detected; version unknown" : @"Present") : (matches.count ? @"Review version or source" : @"Manual setup needed");
        [plan addObject:@{@"tool": identifier, @"version": item[@"version"], @"provider": item[@"installation_provider"], @"status": status}];
    }
    return plan;
}

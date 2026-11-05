#import "RecoveryPlan.h"
#import "CloudInventory.h"

static NSString *SetupGuidance(NSDictionary *item) {
    NSString *provider = item[@"installation_provider"];
    if (![provider isKindOfClass:NSString.class] || ![@[@"homebrew", @"homebrew_formula"] containsObject:provider]) return nil;
    NSDictionary *recipes = @{@"git": @"brew install git", @"nodejs": @"brew install node", @"python": @"brew install python"};
    return recipes[item[@"canonical_tool_id"]];
}

NSString *RecoveryPlanDescription(NSArray<NSDictionary *> *plan) {
    NSMutableString *text = [NSMutableString stringWithString:@"Inventory only. Nothing is installed or changed. Homebrew suggestions require Homebrew and install its current version, which may differ from the backup.\n\n"];
    if (!plan.count) [text appendString:@"This backup contains no tools."];
    for (NSDictionary *item in plan) {
        NSString *version = [item[@"version"] isKindOfClass:NSString.class] ? item[@"version"] : @"version unknown";
        NSString *provider = [item[@"provider"] isKindOfClass:NSString.class] ? item[@"provider"] : @"source unknown";
        [text appendFormat:@"%@ · %@ · %@ — %@\n", item[@"tool"], version, provider, item[@"status"]];
        if (item[@"guidance"]) [text appendFormat:@"  Suggested manual step: %@\n", item[@"guidance"]];
    }
    return text;
}

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
        NSMutableDictionary *row = [@{@"tool": identifier, @"version": item[@"version"], @"provider": item[@"installation_provider"], @"status": status} mutableCopy];
        NSString *guidance = matches.count ? nil : SetupGuidance(item);
        if (guidance) row[@"guidance"] = guidance;
        [plan addObject:row];
    }
    return plan;
}

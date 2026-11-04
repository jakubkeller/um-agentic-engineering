using Amazon.CDK;
using Constructs;

namespace SampleAspNetApi.Helpers;

public static class TaggingHelper
{
    public static void SetBaseTags(Construct construct, string applicationName, BaseTaggingOptions taggingOptions)
    {
        AddTag(construct, "application", applicationName, new TagProps { Priority = 10 });
        AddTag(construct, "name", taggingOptions.Name, new TagProps { Priority = 10 });
        AddTag(construct, "data classification", taggingOptions.DataClassification.ToString(), new TagProps { Priority = 10 });
        AddTag(construct, "context", taggingOptions.Context, new TagProps { Priority = 10 });
        AddTag(construct, "creator", taggingOptions.Creator, new TagProps { Priority = 10 });
        AddTag(construct, "environment", taggingOptions.Environment.ToString(), new TagProps { Priority = 10 });
        AddTag(construct, "department", taggingOptions.Department, new TagProps { Priority = 10 });
        AddTag(construct, "owning team", taggingOptions.OwningTeam, new TagProps { Priority = 10 });
        AddTag(construct, "safe to shutdown", taggingOptions.SafeShutdown.ToString(), new TagProps { Priority = 10 });
        AddTag(construct, "business owner", taggingOptions.BusinessOwner, new TagProps { Priority = 10 });
        AddTag(construct, "cost center", taggingOptions.CostCenter, new TagProps { Priority = 10 });
        AddTag(construct, "map-migrated", taggingOptions.MapMigrated, new TagProps { Priority = 10 }, appendToKey: false);
        AddTag(construct, "map-migrated aws-migration-project-id", taggingOptions.AwsMigrationProjectId, new TagProps { Priority = 10 }, appendToKey: false, isUpperCaseValue: true);
        AddTag(construct, "map-dba", taggingOptions.MapDba, new TagProps { Priority = 10 }, appendToKey: false);
        AddTag(construct, "map-dba aws-migration-project-id", taggingOptions.AwsMigrationProjectId, new TagProps { Priority = 10 }, appendToKey: false, isUpperCaseValue: true);
        AddTag(construct, "compliance", taggingOptions.Compliance.ToString(), new TagProps { Priority = 10 });
        AddTag(construct, "data access", taggingOptions.DataAccess, new TagProps { Priority = 10 });
        AddTag(construct, "consumer", taggingOptions.Customer.ToString(), new TagProps { Priority = 10 });
        AddTag(construct, "customer type", taggingOptions.CustomerType.ToString(), new TagProps { Priority = 10 });
        AddTag(construct, "version", taggingOptions.Version, new TagProps { Priority = 10 });
        AddTag(construct, "servicerequest", taggingOptions.ServiceRequest, new TagProps { Priority = 10 });
        AddTag(construct, "maintenance window", taggingOptions.MaintenanceWindow.ToString(), new TagProps { Priority = 10 });
        AddTag(construct, "notification", taggingOptions.Notification, new TagProps { Priority = 10 });
        AddTag(construct, "operating system", taggingOptions.OS.ToString(), new TagProps { Priority = 10 });
    }

    public static void SetSchedulerTags(Construct construct, string schedule, BaseTaggingOptions taggingOptions)
    {
        AddTag(construct, "schedule", taggingOptions.ShutdownSchedule.ToString(), new TagProps { Priority = 10 });
    }

    public static void AddTag(Construct construct, string key, string value, bool appendToKey = true, bool isUpperCaseValue = false)
    {
        Amazon.CDK.Tags.Of(construct).Add(appendToKey ? "navitus:" + key.ToLower() : key.ToLower(), isUpperCaseValue ? value : value.ToLower());
    }
    public static void AddTag(Construct construct, string key, string value, TagProps tagProp, bool appendToKey = true, bool isUpperCaseValue = false)
    {
        Amazon.CDK.Tags.Of(construct).Add(appendToKey ? "navitus:" + key.ToLower() : key.ToLower(), isUpperCaseValue ? value : value.ToLower(), tagProp);
    }
    public static void RemoveTag(Construct construct, string key, bool hasAppendedKey = true)
    {
        Amazon.CDK.Tags.Of(construct).Remove(hasAppendedKey ? "navitus:" + key : key);
    }
    public static void RemoveTag(Construct construct, string key, TagProps tagProp, bool hasAppendedKey = true)
    {
        Amazon.CDK.Tags.Of(construct).Remove(hasAppendedKey ? "navitus:" + key : key, tagProp);
    }
}

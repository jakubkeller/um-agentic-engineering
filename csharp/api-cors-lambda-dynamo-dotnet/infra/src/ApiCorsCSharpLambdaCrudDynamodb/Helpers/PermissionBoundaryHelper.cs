using Constructs;
using Amazon.CDK;
using Amazon.CDK.AWS.IAM;

namespace SampleAspNetApi.Helpers
{

    public static class PermissionBoundaryHelper
    {
        public static void SetupPermissonBoundaries(Stack stack)
        {
            var policy = ManagedPolicy.FromManagedPolicyName(stack, "DeveloperBoundary", "DeveloperBoundaryPolicy");
            Amazon.CDK.AWS.IAM.PermissionsBoundary.Of(stack).Apply(policy);
        }
    }
}
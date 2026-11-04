using cdk = Amazon.CDK;
using System;
using System.Collections.Generic;
using System.Linq;
using ApiCorsCSharpLambdaCrudDynamodb;

namespace ApiCorsCSharpLambdaCrudDynamodb
{
  sealed class Program
  {
    public static void Main(string[] args)
    {
      var app = new cdk.App();
      
      //example of reading from context value
      var env = (string)app.Node.TryGetContext("env");

      new SampleAspNetApiStack(app, "SampleAspNetApiStack", new cdk.StackProps
      {
        Env = MakeEnvironment()
      });

      app.Synth();
    }
      private static cdk.IEnvironment MakeEnvironment(string account = null, string region = null)
      {
          return new Amazon.CDK.Environment
          {
              //return Account and region checking CDK env vars and falling back to constants.
              Account = account?.Length > 0 ? account : account ??
                  System.Environment.GetEnvironmentVariable("CDK_DEPLOY_ACCOUNT") ??
                  System.Environment.GetEnvironmentVariable("CDK_DEFAULT_ACCOUNT") ?? "421365371822",
              Region = region?.Length > 0 ? region : region ??
                  System.Environment.GetEnvironmentVariable("CDK_DEPLOY_REGION") ??
                  System.Environment.GetEnvironmentVariable("CDK_DEFAULT_REGION") ?? "us-east-2"
          };
      }
  }
}
using Amazon.CDK;
using Amazon.CDK.AWS.APIGateway;
using Amazon.CDK.AWS.DynamoDB;
using Amazon.CDK.AWS.IAM;
using Amazon.CDK.AWS.Lambda;
using Constructs;
using SampleAspNetApi.Helpers;
using SampleAspNetApi.Helpers.Enums;
using System.Collections.Generic;
using System.Diagnostics;
using System.Net;
using Attribute = Amazon.CDK.AWS.DynamoDB.Attribute;

namespace ApiCorsCSharpLambdaCrudDynamodb;

public class SampleAspNetApiStack : Stack
{
    internal SampleAspNetApiStack(Construct scope, string id, IStackProps props = null) : base(scope, id, props)
    {
        // Example of reading values for account, region, and directories
        var account = Stack.Of(this).Account;
        var region = Stack.Of(this).Region;
        var currentDir = System.IO.Directory.GetCurrentDirectory();
        var parentDir = System.IO.Directory.GetParent(currentDir);

        TaggingHelper.SetBaseTags(this, "SampleAspNetApiStack", new BaseTaggingOptions()
        {
            OS = OS.windows // Example of overriding default -> See BaseTaggingOptions
        });

        // Example on applying instance schedule tag for sandbox or development environment
        if (System.Environment.GetEnvironmentVariable("ENVIRONMENTTYPE") is "sandbox" or "development")
        {
            TaggingHelper.SetSchedulerTags(this, "SampleAspNetApiStack", new BaseTaggingOptions(){});
        }
        
        // Apply developer permissions boundary
        PermissionBoundaryHelper.SetupPermissonBoundaries(this);

        string debugModeString = scope.Node.TryGetContext("debug")?.ToString();
        bool debugMode = false;
        if (bool.TryParse(debugModeString, out debugMode) && debugMode)
        {
            Debugger.Launch();
        }

        var stackNameParameter = scope.Node.TryGetContext("stackModifier");
        if (stackNameParameter == null)
        {
            stackNameParameter = System.Environment.GetEnvironmentVariable("CDK_DEFAULT_STACKMODIFIER");
        }

        string tableName = "blogsDotNet" + stackNameParameter;
        // must match case of primary key on Blog model
        string primaryKey = "Id";

        var dynamoTable = new Table(this, tableName, new TableProps()
        {
            PartitionKey = new Attribute()
            {
                Name = primaryKey,
                Type = AttributeType.STRING
            },
            TableName = tableName,
            /**
             *  The default removal policy is RETAIN, which means that cdk destroy will not attempt to delete
             * the new table, and it will remain in your account until manually deleted. By setting the policy to
             * DESTROY, cdk destroy will delete the table (even if it has data in it)
             */
            RemovalPolicy = RemovalPolicy.DESTROY
        });

        // create environment variables that are needed by the Lambda functions
        var environmentVariables = new Dictionary<string, string>()
    {
       {"PRIMARY_KEY", primaryKey },
       {"TABLE_NAME", dynamoTable.TableName },
    };

        var blogServiceLambda = new Function(this, "blogFunction", new FunctionProps
        {
            Runtime = Runtime.DOTNET_6,
            Code = Code.FromAsset($"../dist/release/publish/SampleDynamoBlogAspNetApi/"),
            Handler = "SampleAspNetApi",
            Tracing = Tracing.ACTIVE, // enable X-Ray
            Environment = environmentVariables,
            Timeout = Duration.Seconds(30)
        });

        dynamoTable.GrantReadWriteData(blogServiceLambda);

        #region "Create API Gateway"
        string restApiName = "Blogs AspNet API Service" + stackNameParameter;
        string apiName = "blogsAspNetApi" + stackNameParameter;
        var description = "This is a demo API";

        // Create an API Gateway resource for each of the CRUD operations
        var api = new RestApi(this, apiName, new RestApiProps()
        {
            RestApiName = restApiName,
            Description = description,
            DeployOptions = new StageOptions
            {
                StageName = "dev",
                LoggingLevel = MethodLoggingLevel.ERROR,
                TracingEnabled = true,
                ThrottlingRateLimit = 50, //we need increase this limit after integration with Cognito authentication
                ThrottlingBurstLimit = 10 //we need increase this limit after integration with Cognito authentication
            }
        });
        #endregion

        #region "Secure API by API Key"
        //Add Usage plan and tie up it with API stage
        var apiKeyUsagePlan = api.AddUsagePlan("SampleApiKeyUsagePlan", new UsagePlanProps
        {
            Name = "SampleApiKeyUsagePlan",
            Description = "Usage plan for Sample API key",
            ApiStages = new UsagePlanPerApiStage[] { new UsagePlanPerApiStage
                {
                    Api = api,
                    Stage = api.DeploymentStage
                }}
        });

        //Secure endpoint by API Key, this will get replace by Cognito Authentication
        var apiKey = api.AddApiKey("SampleApiKey", new ApiKeyOptions { });

        //Map API key to usage plan. This way API Key gets applied to API Endpoint. 
        apiKeyUsagePlan.AddApiKey(apiKey);
        #endregion

        var items = api.Root.AddProxy(new ProxyResourceOptions
        {
            DefaultIntegration = new LambdaIntegration(blogServiceLambda),
            AnyMethod = true,
        });
        var swagger = api.Root.AddResource("swagger");
        var swaggerProxy = swagger.AddProxy(new ProxyResourceOptions()
        {
            DefaultIntegration = new LambdaIntegration(blogServiceLambda),
            DefaultMethodOptions = new MethodOptions(),
            AnyMethod = false
        });
        swaggerProxy.AddMethod("GET");
        AddCorsOptions(api.Root);
    }

    private void AddCorsOptions(Amazon.CDK.AWS.APIGateway.IResource apiResource)
    {
        apiResource.AddMethod("OPTIONS", new MockIntegration(
            new IntegrationOptions()
            {
                IntegrationResponses = new IntegrationResponse[]
                {
                    new IntegrationResponse()
                    {
                        StatusCode = ((int)HttpStatusCode.OK).ToString(),
                        ResponseParameters = new Dictionary<string, string>()
                        {
                            // Note the single quotes around the values in this collection, they are required
                            { "method.response.header.Access-Control-Allow-Headers", "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token,X-Amz-User-Agent'" },
                            { "method.response.header.Access-Control-Allow-Origin", "'*,http://localhost:3000'" },
                            { "method.response.header.Access-Control-Allow-Credentials", "'false'" },
                            { "method.response.header.Access-Control-Allow-Methods", "'OPTIONS,GET,PUT,POST,DELETE'" }
                        }
                    }
                },
                PassthroughBehavior = PassthroughBehavior.NEVER,
                RequestTemplates = new Dictionary<string, string>()
                {
                    { "application/json", "{\"statusCode\": 200}" }
                }
            }),
            new MethodOptions()
            {
                MethodResponses = new MethodResponse[]
                {
                    new MethodResponse()
                    {
                        StatusCode = ((int)HttpStatusCode.OK).ToString(),
                        ResponseParameters = new Dictionary<string, bool>()
                        {
                            { "method.response.header.Access-Control-Allow-Headers", true },
                            { "method.response.header.Access-Control-Allow-Methods", true },
                            { "method.response.header.Access-Control-Allow-Credentials", true },
                            { "method.response.header.Access-Control-Allow-Origin", true },
                        }
                    }
                }
            }
        );
    }
}

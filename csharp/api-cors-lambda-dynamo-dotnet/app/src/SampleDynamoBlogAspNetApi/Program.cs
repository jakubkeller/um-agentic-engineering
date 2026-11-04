using Amazon.DynamoDBv2;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.OpenApi.Models;
using SampleDynamoBlogAspNetApi.Repositories;
using SampleDynamoBlogAspNetApi.Services;
using SampleEntityFrameworkCoreAspNetApi.Contexts;
using SampleEntityFrameworkCoreAspNetApi.Repositories;
using SampleEntityFrameworkCoreAspNetApi.Services;

var builder = WebApplication.CreateBuilder(args);

// Add services to the container.
builder.Services.AddControllers();

builder.Services.AddSingleton<IAmazonDynamoDB, AmazonDynamoDBClient>();
builder.Services.AddSingleton<IBlogService, BlogService>();
builder.Services.AddSingleton<IDynamoBlogRepository, DynamoBlogRepository>();

builder.Services.AddSingleton<IWidgetService, WidgetService>();
builder.Services.AddSingleton<IWidgetRepository, WidgetRepository>();
// uncomment the line below to test EF Core utilization, assuming that an Aurora Postgres DB has already been setup with an accessible secret
// and an environment variable has been set
// reference: https://dev.azure.com/Navitus/NUCLEUS/_git/aws-devops-reference?path=%2Faws-cdk-examples%2Fcsharp%2Faurora-postgres
//builder.Services.AddDbContext<WidgetContext>();

// Add AWS Lambda support. When application is run in Lambda Kestrel is swapped out as the web server with Amazon.Lambda.AspNetCoreServer. This
// package will act as the webserver translating request and responses between the Lambda event source and ASP.NET Core.
builder.Services.AddAWSLambdaHosting(LambdaEventSource.RestApi);
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(c =>
{
  c.SwaggerDoc("v1", new() { Title = builder.Environment.ApplicationName, Version = "v1" });
  //c.AddSecurityDefinition("Bearer", new OpenApiSecurityScheme
  //{
  //  In = ParameterLocation.Header,
  //  Description = "Please enter a valid token",
  //  Name = "Authorization",
  //  Type = SecuritySchemeType.Http,
  //  BearerFormat = "JWT",
  //  Scheme = "Bearer"
  //});
  //c.AddSecurityRequirement(new OpenApiSecurityRequirement
  //{
  //  {
  //    new OpenApiSecurityScheme
  //    {
  //      Reference = new OpenApiReference
  //      {
  //        Type=ReferenceType.SecurityScheme,
  //        Id="Bearer"
  //      }
  //    },
  //    new string[]{}
  //  }
  //});
});

var app = builder.Build();
app.UseSwagger();
app.UseSwaggerUI();

app.UseHttpsRedirection();
//app.UseAuthorization();
app.MapControllers();

app.Run();

using Amazon.DynamoDBv2;
using Amazon.DynamoDBv2.DataModel;
using Amazon.DynamoDBv2.Model;
using Microsoft.Extensions.Logging;
using Moq;
using SampleDynamoBlogAspNetApi.Services;
using SampleDynamoBlogAspNetApi.Controllers;
using SampleDynamoBlogAspNetApi.Models;
using SampleDynamoBlogAspNetApi.Repositories;
using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using Xunit;

namespace SampleDynamoBlogAspNetApi.Tests.Repositories
{
    public class DynamoBlogRepositoryTest
    {
        ILogger<BlogsController> _mockLogger;
        IAmazonDynamoDB _dynamoDbClient;

        public DynamoBlogRepositoryTest()
        {
            _mockLogger = new Mock<ILogger<BlogsController>>().Object;
            var mockDynamoDbClient = new Mock<IAmazonDynamoDB>();
            var scanResponse = new ScanResponse()
            {
                Items = new List<Dictionary<string, AttributeValue>>()
            };

            // sample mocking of ddb client api
            mockDynamoDbClient.Setup(m => m.ScanAsync(It.IsAny<string>(), It.IsAny<List<string>>(), It.IsAny<CancellationToken>()))
              .Returns(Task.FromResult(scanResponse));
            _dynamoDbClient = mockDynamoDbClient.Object;
        }

        [Fact]
        public async void GetAll_Returns_AllBlogs()
        {
            var blogServiceMock = new Mock<IBlogService>();
            blogServiceMock.Setup(m => m.GetAll()).Returns(Task.FromResult(new List<Blog>() { new Blog() { Id = "1000" } }));

            var blogsController = new BlogsController(_mockLogger, blogServiceMock.Object);
            var results = await blogsController.GetBlogs();
            Assert.Collection(results, item => Assert.Equal("1000", item.Id));
            Assert.Single(results);            
        }
    }
}

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
    public class BlogServiceTest
    {
        ILogger<BlogService> _mockLogger;
        IAmazonDynamoDB _dynamoDbClient;

        public BlogServiceTest()
        {
            _mockLogger = new Mock<ILogger<BlogService>>().Object;
            var mockDynamoDbClient = new Mock<IAmazonDynamoDB>();
            var scanResponse = new ScanResponse()
            {
                Items = new List<Dictionary<string, AttributeValue>>()
            };
        }

        [Fact]
        public async void GetAll_Returns_ManyBlogs()
        {
            var dynamoBlogRepositoryMock = new Mock<IDynamoBlogRepository>();
            dynamoBlogRepositoryMock.Setup(m => m.GetAll()).Returns(Task.FromResult(new List<Blog>() { new Blog() { Id = "1000" }, new Blog() { Id = "2000" } }));

            var blogService = new BlogService(_mockLogger, dynamoBlogRepositoryMock.Object);
            var blogs = await blogService.GetAll();
            Assert.True(blogs.Count == 2);
        }

        [Fact]
        public async void GetOne_Returns_SingleBlog()
        {
            var dynamoBlogRepositoryMock = new Mock<IDynamoBlogRepository>();
            dynamoBlogRepositoryMock.Setup(m => m.GetOne(It.IsAny<string>())).Returns(Task.FromResult(new Blog() { Id = "2000" }));

            var blogService = new BlogService(_mockLogger, dynamoBlogRepositoryMock.Object);
            var blog = await blogService.GetOne("2000");
            Assert.NotNull(blog);
            Assert.True(blog.Id == "2000");
        }

        [Fact]
        public async void Create_Success()
        {
            var blogId = Guid.NewGuid().ToString();
            var blogName = "Test Name";
            var blogContent = "Test Content";
            var dynamoBlogRepositoryStub = new Mock<IDynamoBlogRepository>();

            dynamoBlogRepositoryStub.Setup(m => m.Create(It.IsAny<Blog>())).Returns(Task.FromResult(blogId));

            var blogToReturn = new Blog()
            {
                Id = blogId,
                Name = blogName,
                Content = blogContent,
                CreatedTimestamp = DateTime.UtcNow,
                ModifiedTimestamp = DateTime.UtcNow
            };
            dynamoBlogRepositoryStub.Setup(m => m.GetOne(blogId))
                .Returns(Task.FromResult(blogToReturn));

            var blogService = new BlogService(_mockLogger, dynamoBlogRepositoryStub.Object);
            var blog = await blogService.Create(new Blog() { Name = blogName, Content = "Test Content" });

            Assert.NotNull(blog);

            dynamoBlogRepositoryStub.Verify(m => m.Create(It.Is<Blog>(b =>
                b.Id != null
                && b.Name == blogName
                && b.Content == blogContent
                && b.CreatedTimestamp != DateTime.MinValue
                && b.ModifiedTimestamp == b.CreatedTimestamp
               )));

            dynamoBlogRepositoryStub.Verify(m => m.GetOne(It.IsAny<string>()), Times.Once());
        }

        [Fact]
        public async void Create_Exception_Null_Blog()
        {
            var dynamoBlogRepositoryStub = new Mock<IDynamoBlogRepository>();
            var blogService = new BlogService(_mockLogger, dynamoBlogRepositoryStub.Object);
            await Assert.ThrowsAsync<Exception>(() => blogService.Create(null));
        }

        [Fact]
        public async void Create_Exception_Id_Is_Set()
        {
            var dynamoBlogRepositoryStub = new Mock<IDynamoBlogRepository>();
            var blogService = new BlogService(_mockLogger, dynamoBlogRepositoryStub.Object);
            await Assert.ThrowsAsync<Exception>(() => blogService.Create(new Blog() { Id = "error" }));
        }

        [Fact]
        public async void Create_Exception_Dates_Are_Set()
        {

            var dynamoBlogRepositoryStub = new Mock<IDynamoBlogRepository>();
            var blogService = new BlogService(_mockLogger, dynamoBlogRepositoryStub.Object);
            await Assert.ThrowsAsync<Exception>(() => blogService.Create(new Blog() { CreatedTimestamp = DateTime.UtcNow }));
            await Assert.ThrowsAsync<Exception>(() => blogService.Create(new Blog() { ModifiedTimestamp = DateTime.UtcNow }));
        }

        [Fact]
        public async void Create_Exception_NameOrContent_Are_Not_Set()
        {

            var dynamoBlogRepositoryStub = new Mock<IDynamoBlogRepository>();
            var blogService = new BlogService(_mockLogger, dynamoBlogRepositoryStub.Object);
            await Assert.ThrowsAsync<Exception>(() => blogService.Create(new Blog() { Name = null, Content = "a" }));
            await Assert.ThrowsAsync<Exception>(() => blogService.Create(new Blog() { Name = "a", Content = null}));
        }

        [Fact]
        public async void Update_Success()
        {
            var blogId = Guid.NewGuid().ToString();
            var blogName = "Test Name";
            var blogContent = "Test Content";
            var dynamoBlogRepositoryStub = new Mock<IDynamoBlogRepository>();

            dynamoBlogRepositoryStub.Setup(m => m.Update(It.IsAny<Blog>()))
                .Returns(Task.FromResult(blogId));

            var now = DateTime.UtcNow;
            var blogToReturn = new Blog()
            {
                Id = blogId,
                Name = blogName,
                Content = blogContent,
                CreatedTimestamp = now,
                ModifiedTimestamp = now
            };
            dynamoBlogRepositoryStub.Setup(m => m.GetOne(blogId))
                .Returns(Task.FromResult(blogToReturn));

            var blogService = new BlogService(_mockLogger, dynamoBlogRepositoryStub.Object);
            var blog = await blogService.Update(blogId, new Blog() { Id=blogId, Name = blogName, Content = "Test Content1", CreatedTimestamp=now, ModifiedTimestamp=now });

            Assert.NotNull(blog);

            dynamoBlogRepositoryStub.Verify(m => m.Update(It.Is<Blog>(b =>
                b.Id == blogId
                && b.Name == blogName
                && b.Content == "Test Content1"
                && b.CreatedTimestamp == now
                && b.ModifiedTimestamp > now
               )));

            dynamoBlogRepositoryStub.Verify(m => m.GetOne(It.IsAny<string>()), Times.Exactly(2));
        }

        [Fact]
        public async void Update_Exception_Null_Blog_Or_Null_Id()
        {
            var dynamoBlogRepositoryStub = new Mock<IDynamoBlogRepository>();
            var blogService = new BlogService(_mockLogger, dynamoBlogRepositoryStub.Object);
            await Assert.ThrowsAsync<Exception>(() => blogService.Update("1", null));
            await Assert.ThrowsAsync<Exception>(() => blogService.Update(null, new Blog()));
        }

        [Fact]
        public async void Update_Exception_Id_Is_Not_Set()
        {
            var dynamoBlogRepositoryStub = new Mock<IDynamoBlogRepository>();
            var blogService = new BlogService(_mockLogger, dynamoBlogRepositoryStub.Object);
            await Assert.ThrowsAsync<Exception>(() => blogService.Update("1", new Blog() { Id = null }));
            await Assert.ThrowsAsync<Exception>(() => blogService.Update("1", new Blog() { Id = "2" }));
        }

        [Fact]
        public async void Update_Exception_Record_To_Update_Does_Not_Exist()
        {
            var dynamoBlogRepositoryStub = new Mock<IDynamoBlogRepository>();
            dynamoBlogRepositoryStub.Setup(m => m.GetOne("2")).Returns(Task.FromResult<Blog>(null));
            var blogService = new BlogService(_mockLogger, dynamoBlogRepositoryStub.Object);
            var now = DateTime.UtcNow;
            await Assert.ThrowsAsync<Exception>(() => blogService.Update("2", new Blog() { Id = "2", Name = "Test", Content = "Test Content1", CreatedTimestamp = now, ModifiedTimestamp = now }));
        }

        [Fact]
        public async void Update_Exception_Dates_Are_Set()
        {
            var dynamoBlogRepositoryStub = new Mock<IDynamoBlogRepository>();
            var blogService = new BlogService(_mockLogger, dynamoBlogRepositoryStub.Object);
            await Assert.ThrowsAsync<Exception>(() => blogService.Update("1", new Blog() { Id="1", CreatedTimestamp = DateTime.UtcNow }));
            await Assert.ThrowsAsync<Exception>(() => blogService.Update("1", new Blog() { Id = "1", ModifiedTimestamp = DateTime.UtcNow }));
        }

        [Fact]
        public async void Update_Exception_NameOrContent_Are_Not_Set()
        {

            var dynamoBlogRepositoryStub = new Mock<IDynamoBlogRepository>();
            var blogService = new BlogService(_mockLogger, dynamoBlogRepositoryStub.Object);
            await Assert.ThrowsAsync<Exception>(() => blogService.Update("1", new Blog() { Id = "1", Name = null, Content = "a" }));
            await Assert.ThrowsAsync<Exception>(() => blogService.Update("1", new Blog() { Id = "1", Name = "a", Content = null }));
        }

        [Fact]
        public async void Update_Exception_Modified_Created_Dates_Do_Not_Match_Existing_Record()
        {

            var dynamoBlogRepositoryStub = new Mock<IDynamoBlogRepository>();
            var now = DateTime.UtcNow;
            dynamoBlogRepositoryStub.Setup(m => m.GetOne(It.IsAny<string>())).Returns(Task.FromResult(new Blog() { Id = "1", Name="Name", Content="Content", CreatedTimestamp=now, ModifiedTimestamp=now }));
            var blogService = new BlogService(_mockLogger, dynamoBlogRepositoryStub.Object);
            await Assert.ThrowsAsync<Exception>(() => blogService.Update("1", new Blog() { Id = "1", Name = "a", Content = "a", CreatedTimestamp = DateTime.UtcNow, ModifiedTimestamp = now  }));
            await Assert.ThrowsAsync<Exception>(() => blogService.Update("1", new Blog() { Id = "1", Name = "a", Content = "a", CreatedTimestamp = now, ModifiedTimestamp = DateTime.UtcNow }));
        }

        [Fact]
        public async void Delete_Success()
        {
          
            var dynamoBlogRepositoryStub = new Mock<IDynamoBlogRepository>();

            var blogId = "1";
            dynamoBlogRepositoryStub.Setup(m => m.Delete(It.IsAny<string>()))
                .Returns(Task.FromResult(blogId));

            var blogToReturn = new Blog()
            {
                Id = blogId,
                Name = "Test",
                Content = "Test Content",
                CreatedTimestamp = DateTime.UtcNow,
                ModifiedTimestamp = DateTime.UtcNow
            };
            dynamoBlogRepositoryStub.Setup(m => m.GetOne(blogId))
                .Returns(Task.FromResult(blogToReturn));

            var blogService = new BlogService(_mockLogger, dynamoBlogRepositoryStub.Object);
            var blog = await blogService.Delete(blogId);

            dynamoBlogRepositoryStub.Verify(m => m.GetOne(It.IsAny<string>()), Times.Once());
            dynamoBlogRepositoryStub.Verify(m => m.Delete(blogId));


        }


        [Fact]
        public async void Delete_Exception_Null_Id()
        {
            var dynamoBlogRepositoryStub = new Mock<IDynamoBlogRepository>();
            var blogService = new BlogService(_mockLogger, dynamoBlogRepositoryStub.Object);
            await Assert.ThrowsAsync<Exception>(() => blogService.Delete(null));
        }

        [Fact]
        public async void Delete_Exception_Record_To_Delete_Does_Not_Exist()
        {
            var dynamoBlogRepositoryStub = new Mock<IDynamoBlogRepository>();
            dynamoBlogRepositoryStub.Setup(m => m.GetOne("2")).Returns(Task.FromResult<Blog>(null));
            var blogService = new BlogService(_mockLogger, dynamoBlogRepositoryStub.Object);
            var now = DateTime.UtcNow;
            await Assert.ThrowsAsync<Exception>(() => blogService.Delete("2"));
        }
    }
}

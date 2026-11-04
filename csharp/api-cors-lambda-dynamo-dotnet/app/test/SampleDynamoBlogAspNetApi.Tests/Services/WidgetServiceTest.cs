using Microsoft.Extensions.Logging;
using Moq;
using SampleEntityFrameworkCoreAspNetApi.Models;
using SampleEntityFrameworkCoreAspNetApi.Repositories;
using SampleEntityFrameworkCoreAspNetApi.Services;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Xunit;

namespace SampleEntityFrameworkCoreAspNetApi.Tests.Services;

public class WidgetServiceTest
{
    ILogger<WidgetService> _mockLogger;

    public WidgetServiceTest()
    {
        _mockLogger = new Mock<ILogger<WidgetService>>().Object;
    }

    [Fact]
    public async void GetAll_Returns_AllWidgets()
    {
        var widgetRepositoryMock = new Mock<IWidgetRepository>();
        widgetRepositoryMock.Setup(m => m.GetAll()).ReturnsAsync(
            new List<Widget>()
                { new Widget() { Id = "ABC123" }, new Widget() { Id = "CBA321" } });
        var widgetService = new WidgetService(_mockLogger, widgetRepositoryMock.Object);
        var widgets = await widgetService.GetAll();
        Assert.True(widgets.Count() == 2);
    }

    [Fact]
    public async void GetOne_Returns_OneWidget()
    {
        var widgetRepositoryMock = new Mock<IWidgetRepository>();
        widgetRepositoryMock.Setup(m => m.GetOne(It.IsAny<string>())).ReturnsAsync(new Widget() { Id = "ABC123" });
        var widgetService = new WidgetService(_mockLogger, widgetRepositoryMock.Object);
        var widget = await widgetService.GetOne("ABC123");
        Assert.NotNull(widget);
        Assert.True(widget?.Id?.Equals("ABC123"));
    }

    [Fact]
    public async void Create_Success()
    {
        var widgetId = Guid.NewGuid().ToString();
        var widgetName = "test widget";
        var widgetUrl = "test url";
        var widgetRepositoryMock = new Mock<IWidgetRepository>();

        widgetRepositoryMock.Setup(m => m.Create(It.IsAny<Widget>())).Returns(Task.FromResult(widgetId));

        var widgetToReturn = new Widget()
        {
            Id = widgetId,
            Name = widgetName,
            Url = widgetUrl
        };

        widgetRepositoryMock.Setup(m => m.GetOne(widgetId))
            .Returns(Task.FromResult(widgetToReturn));

        var widgetService = new WidgetService(_mockLogger, widgetRepositoryMock.Object);
        var widget = await widgetService.Create(new Widget() { Name = widgetName, Url = widgetUrl });

        Assert.NotNull(widget);

        widgetRepositoryMock.Verify(m => m.Create(It.Is<Widget>(w =>
            w.Id != null
            && w.Name == widgetName
            && w.Url == widgetUrl
        )));

        widgetRepositoryMock.Verify(m => m.GetOne(It.IsAny<string>()), Times.Once());
    }

    [Fact]
    public async void Create_Exception_Null_Blog()
    {
        var widgetRepositoryMock = new Mock<IWidgetRepository>();
        var widgetService = new WidgetService(_mockLogger, widgetRepositoryMock.Object);
        await Assert.ThrowsAsync<Exception>(() => widgetService.Create(null));
    }

    [Fact]
    public async void Create_Exception_Id_Is_Set()
    {
        var widgetRepositoryMock = new Mock<IWidgetRepository>();
        var widgetService = new WidgetService(_mockLogger, widgetRepositoryMock.Object);
        await Assert.ThrowsAsync<Exception>(() => widgetService.Create(new Widget() { Id = "error" }));
    }

    [Fact]
    public async void Create_Exception_NameOrUrl_Are_Not_Set()
    {

        var widgetRepositoryMock = new Mock<IWidgetRepository>();
        var widgetService = new WidgetService(_mockLogger, widgetRepositoryMock.Object);
        await Assert.ThrowsAsync<Exception>(() => widgetService.Create(new Widget() { Name = null, Url = "a" }));
        await Assert.ThrowsAsync<Exception>(() => widgetService.Create(new Widget() { Name = "a", Url = null }));
    }

    [Fact]
    public async void Update_Success()
    {
        var widgetId = Guid.NewGuid().ToString();
        var widgetName = "test widget";
        var widgetUrl = "test url";
        var widgetRepositoryMock = new Mock<IWidgetRepository>();

        widgetRepositoryMock.Setup(m => m.Update(It.IsAny<Widget>()))
            .Returns(Task.FromResult(widgetId));

        var widgetToReturn = new Widget()
        {
            Id = widgetId,
            Name = widgetName,
            Url = widgetUrl
        };

        widgetRepositoryMock.Setup(m => m.GetOne(widgetId))
            .Returns(Task.FromResult(widgetToReturn));

        var widgetService = new WidgetService(_mockLogger, widgetRepositoryMock.Object);
        var widget = await widgetService.Update(widgetId, new Widget() { Id = widgetId, Name = widgetName, Url = widgetUrl });

        Assert.NotNull(widget);

        widgetRepositoryMock.Verify(m => m.Update(It.Is<Widget>(w =>
             w.Id != null
            && w.Name == widgetName
            && w.Url == widgetUrl
           )));

        widgetRepositoryMock.Verify(m => m.GetOne(It.IsAny<string>()), Times.Exactly(2));
    }

    [Fact]
    public async void Update_Exception_Null_Widget_Or_Null_Id()
    {
        var widgetRepositoryMock = new Mock<IWidgetRepository>();
        var widgetService = new WidgetService(_mockLogger, widgetRepositoryMock.Object);
        await Assert.ThrowsAsync<Exception>(() => widgetService.Update("1", null));
        await Assert.ThrowsAsync<Exception>(() => widgetService.Update(null, new Widget()));
    }

    [Fact]
    public async void Update_Exception_Id_Is_Not_Set()
    {
        var widgetRepositoryMock = new Mock<IWidgetRepository>();
        var widgetService = new WidgetService(_mockLogger, widgetRepositoryMock.Object);
        await Assert.ThrowsAsync<Exception>(() => widgetService.Update("1", new Widget() { Id = null }));
        await Assert.ThrowsAsync<Exception>(() => widgetService.Update("1", new Widget() { Id = "2" }));
    }

    [Fact]
    public async void Update_Exception_Record_To_Update_Does_Not_Exist()
    {
        var widgetRepositoryMock = new Mock<IWidgetRepository>();
        widgetRepositoryMock.Setup(m => m.GetOne("2")).Returns(Task.FromResult<Widget>(null));
        var widgetService = new WidgetService(_mockLogger, widgetRepositoryMock.Object);
        await Assert.ThrowsAsync<Exception>(() => widgetService.Update("2", new Widget() { Id = "2", Name = "Test", Url = "Test Url" }));
    }

    [Fact]
    public async void Update_Exception_NameOrUrl_Are_Not_Set()
    {

        var widgetRepositoryMock = new Mock<IWidgetRepository>();
        var widgetService = new WidgetService(_mockLogger, widgetRepositoryMock.Object);
        await Assert.ThrowsAsync<Exception>(() => widgetService.Update("1", new Widget() { Id = "1", Name = null, Url = "a" }));
        await Assert.ThrowsAsync<Exception>(() => widgetService.Update("1", new Widget() { Id = "1", Name = "a", Url = null }));
    }

    [Fact]
    public async void Delete_Success()
    {

        var widgetRepositoryMock = new Mock<IWidgetRepository>();

        var widgetId = "1";
        widgetRepositoryMock.Setup(m => m.Delete(It.IsAny<string>()))
            .Returns(Task.FromResult(widgetId));

        var widgetToReturn = new Widget()
        {
            Id = widgetId,
            Name = "Test",
            Url = "Test url"
        };
        widgetRepositoryMock.Setup(m => m.GetOne(widgetId))
            .Returns(Task.FromResult(widgetToReturn));

        var widgetService = new WidgetService(_mockLogger, widgetRepositoryMock.Object);
        var widget = await widgetService.Delete(widgetId);

        widgetRepositoryMock.Verify(m => m.GetOne(It.IsAny<string>()), Times.Once());
        widgetRepositoryMock.Verify(m => m.Delete(widgetId));


    }

    [Fact]
    public async void Delete_Exception_Null_Id()
    {
        var widgetRepositoryMock = new Mock<IWidgetRepository>();
        var widgetService = new WidgetService(_mockLogger, widgetRepositoryMock.Object);
        await Assert.ThrowsAsync<Exception>(() => widgetService.Delete(null));
    }

    [Fact]
    public async void Delete_Exception_Record_To_Delete_Does_Not_Exist()
    {
        var widgetRepositoryMock = new Mock<IWidgetRepository>();
        widgetRepositoryMock.Setup(m => m.GetOne("2")).Returns(Task.FromResult<Widget>(null));
        var widgetService = new WidgetService(_mockLogger, widgetRepositoryMock.Object);
        await Assert.ThrowsAsync<Exception>(() => widgetService.Delete("2"));
    }
}

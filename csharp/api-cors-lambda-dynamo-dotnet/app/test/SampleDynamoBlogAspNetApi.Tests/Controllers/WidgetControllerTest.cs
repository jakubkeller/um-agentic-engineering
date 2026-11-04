using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging;
using Moq;
using SampleEntityFrameworkCoreAspNetApi.Controllers;
using SampleEntityFrameworkCoreAspNetApi.Models;
using SampleEntityFrameworkCoreAspNetApi.Services;
using System.Collections.Generic;
using Xunit;

namespace SampleEntityFrameworkCoreAspNetApi.Tests.Controllers;

public class WidgetControllerTest
{
    ILogger<WidgetsController> _mockLogger;

    public WidgetControllerTest()
    {
        _mockLogger = new Mock<ILogger<WidgetsController>>().Object;
    }

    [Fact]
    public async void TestGetAllReturnOK()
    {
        var data = new List<Widget>() { new Widget() { Id = "ABC123" } };
        var widgetServiceMock = new Mock<IWidgetService>();
        widgetServiceMock.Setup(m => m.GetAll()).ReturnsAsync(data);
        var widgetController = new WidgetsController(_mockLogger, widgetServiceMock.Object);

        var results = await widgetController.GetWidgets();

        Assert.IsType<OkObjectResult>(results);
        OkObjectResult okResult = (OkObjectResult)results;
        Assert.NotNull(okResult);
        var formularyData = (List<Widget>)(okResult.Value ?? new List<Widget> { });
        Assert.Collection(formularyData, item => Assert.Equal("ABC123", item.Id));
        Assert.Single(formularyData);
    }

    [Fact]
    public async void TestGetAllReturnNoContent()
    {
        var widgetServiceMock = new Mock<IWidgetService>();
        widgetServiceMock.Setup(m => m.GetAll()).ReturnsAsync(new List<Widget>() { });
        var widgetController = new WidgetsController(_mockLogger, widgetServiceMock.Object);

        var results = await widgetController.GetWidgets();
        Assert.IsType<NoContentResult>(results);
    }

    [Fact]
    public async void TestGetOneReturnOK()
    {
        var data = new Widget() { Id = "ABC123" };
        var widgetServiceMock = new Mock<IWidgetService>();
        widgetServiceMock.Setup(m => m.GetOne(It.IsAny<string>())).ReturnsAsync(data);
        var widgetController = new WidgetsController(_mockLogger, widgetServiceMock.Object);

        var result = await widgetController.GetWidget("ABC123");
        Assert.IsType<OkObjectResult>(result);
        OkObjectResult okResult = (OkObjectResult)result;
        var widget = (Widget)(okResult.Value ?? new Widget());
        Assert.NotNull(widget);
        Assert.True(widget?.Id?.Equals("ABC123"));
    }

    [Fact]
    public async void TestGetOneReturnNoContent()
    {
        var widgetServiceMock = new Mock<IWidgetService>();
        widgetServiceMock.Setup(m => m.GetOne(It.IsAny<string>())).ReturnsAsync(new Widget() { Id = "" });
        var widgetController = new WidgetsController(_mockLogger, widgetServiceMock.Object);

        var result = await widgetController.GetWidget("ABC123");
        Assert.IsType<NoContentResult>(result);
    }
}

using Microsoft.AspNetCore.Mvc;
using SampleEntityFrameworkCoreAspNetApi.Models;
using SampleEntityFrameworkCoreAspNetApi.Services;

namespace SampleEntityFrameworkCoreAspNetApi.Controllers;

[ApiController]
[Route("[controller]")]
public class WidgetsController : ControllerBase
{
    private readonly IWidgetService _widgetService;
    private ILogger<WidgetsController> _logger;

    public WidgetsController(ILogger<WidgetsController> logger, IWidgetService widgetService)
    {
        _logger = logger;
        _widgetService = widgetService;
    }

    // GET widgets/
    [HttpGet("")]
    public async Task<IActionResult> GetWidgets()
    {
        IEnumerable<Widget> widgets = await _widgetService.GetAll();

        if (widgets != null && widgets.Count() > 0)
        {
            return Ok(widgets);
        }
        return NoContent();
    }

    // GET widgets/123456
    [HttpGet("{id}")]
    public async Task<IActionResult> GetWidget(string id)
    {
        Widget? widget = await _widgetService.GetOne(id);

        if (widget != null && !string.IsNullOrWhiteSpace(widget.Id))
        {
            return Ok(widget);
        }
        return NoContent();
    }

    // POST widgets/123456
    [HttpPost("")]
    public async Task<IActionResult> CreateWidget(Widget widget)
    {
        Widget? createdWidget = await _widgetService.Create(widget);

        if (createdWidget != null && !string.IsNullOrWhiteSpace(createdWidget.Id))
        {
            return Ok(createdWidget);
        }
        return NoContent();
    }

    // PATCH widget/123456
    [HttpPatch("{id}")]
    public async Task<IActionResult> UpdateWidget(string id, Widget widget)
    {
        Widget? updatedWidget = await _widgetService.Update(id, widget);

        if (updatedWidget != null && !string.IsNullOrWhiteSpace(updatedWidget.Id))
        {
            return Ok(updatedWidget);
        }
        return NoContent();
    }

    // DELETE widget/123456
    [HttpDelete("{id}")]
    public async Task<IActionResult> DeleteWidget(string id)
    {
        return Ok(await _widgetService.Delete(id));
    }
}

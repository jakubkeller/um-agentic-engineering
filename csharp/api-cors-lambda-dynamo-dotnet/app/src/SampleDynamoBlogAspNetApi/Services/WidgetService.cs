using SampleEntityFrameworkCoreAspNetApi.Models;
using SampleEntityFrameworkCoreAspNetApi.Repositories;

namespace SampleEntityFrameworkCoreAspNetApi.Services;

public class WidgetService : IWidgetService
{
    private readonly IWidgetRepository _widgetRepository;
    private ILogger<WidgetService> _logger;

    public WidgetService(ILogger<WidgetService> logger, IWidgetRepository widgetRepository)
    {
        _logger = logger;
        _widgetRepository = widgetRepository;
    }

    public async Task<IEnumerable<Widget>> GetAll()
    {
        return await _widgetRepository.GetAll();
    }

    public async Task<Widget?> GetOne(string id)
    {
        if (string.IsNullOrEmpty(id))
        {
            throw new Exception("Required Parameter Id is missing");
        }

        return await _widgetRepository.GetOne(id);
    }

    public async Task<Widget?> Create(Widget widget)
    {
        if (widget == null)
        {
            throw new Exception("Required Parameter widget is missing");
        }

        if (!string.IsNullOrEmpty(widget.Id))
        {
            throw new Exception("Id can not be set on create widget");
        }

        if (string.IsNullOrWhiteSpace(widget.Name) || string.IsNullOrWhiteSpace(widget.Url))
        {
            throw new Exception("Name and Url are required to create a widget");
        }

        widget.Id = Guid.NewGuid().ToString();

        var widgetId = await _widgetRepository.Create(widget);

        return await _widgetRepository.GetOne(widgetId);
    }

    public async Task<Widget?> Update(string id, Widget widget)
    {
        if (string.IsNullOrEmpty(id))
        {
            throw new Exception("Required Parameter Id is missing");
        }

        if (widget == null)
        {
            throw new Exception("Required Parameter widget is missing");
        }

        if (string.IsNullOrWhiteSpace(widget.Id) || string.IsNullOrWhiteSpace(id) || widget.Id != id)
        {
            throw new Exception("Required Parameter Id is missing on object or does not match the key to update");
        }

        if (string.IsNullOrWhiteSpace(widget.Name) || string.IsNullOrWhiteSpace(widget.Url))
        {
            throw new Exception("Name and Url are required to update a widget");
        }

        var existingWidget = await _widgetRepository.GetOne(widget.Id);
        if (existingWidget == null)
        {
            throw new Exception("Widget does not exist");
        }

        await _widgetRepository.Update(widget);

        return await _widgetRepository.GetOne(widget.Id);
    }

    public async Task<string> Delete(string id)
    {
        if (string.IsNullOrEmpty(id))
        {
            throw new Exception("Required Parameter Id is missing");
        }

        var existingWidget = await _widgetRepository.GetOne(id);
        if (existingWidget == null)
        {
            throw new Exception("Widget does not exist");
        }

        await _widgetRepository.Delete(id);

        return id;
    }
}

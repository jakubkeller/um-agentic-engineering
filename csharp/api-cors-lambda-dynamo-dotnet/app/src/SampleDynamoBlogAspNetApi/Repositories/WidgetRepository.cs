using Microsoft.EntityFrameworkCore;
using SampleEntityFrameworkCoreAspNetApi.Contexts;
using SampleEntityFrameworkCoreAspNetApi.Models;

namespace SampleEntityFrameworkCoreAspNetApi.Repositories;

public class WidgetRepository : IWidgetRepository
{
    private readonly WidgetContext _widgetContext;
    private ILogger<WidgetRepository> _logger;

    public WidgetRepository(WidgetContext widgetContext, ILogger<WidgetRepository> logger)
    {
        _widgetContext = widgetContext;
        _logger = logger;
    }
    public async Task<IEnumerable<Widget>> GetAll()
    {
        return await _widgetContext.Widgets.ToListAsync();
    }

    public async Task<Widget?> GetOne(string id)
    {
        return await _widgetContext.Widgets.Where(widget => widget.Id == id).FirstOrDefaultAsync();
    }

    public async Task<string> Create(Widget widget)
    {
        if (widget == null) return string.Empty;

        _widgetContext.Add(widget);
        int createCount = await _widgetContext.SaveChangesAsync();

        if (createCount == 1 && widget != null && widget.Id != null)
        {
            return widget.Id;
        }
        return string.Empty;
    }

    public async Task<string> Update(Widget widget)
    {
        if (widget == null) return string.Empty;

        _widgetContext.Update(widget);
        int updateCount = await _widgetContext.SaveChangesAsync();

        if (updateCount == 1 && widget != null && widget.Id != null)
        {
            return widget.Id;
        }
        return string.Empty;
    }

    public async Task<string> Delete(string id)
    {
        _widgetContext.Remove(new Widget { Id = id });
        int deleteCount = await _widgetContext.SaveChangesAsync();

        if (deleteCount == 1)
        {
            return id;
        }
        return string.Empty;
    }
}

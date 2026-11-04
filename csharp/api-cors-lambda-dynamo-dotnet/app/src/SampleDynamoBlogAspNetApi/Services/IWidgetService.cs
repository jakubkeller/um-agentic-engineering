using SampleEntityFrameworkCoreAspNetApi.Models;

namespace SampleEntityFrameworkCoreAspNetApi.Services;

public interface IWidgetService
{
    Task<IEnumerable<Widget>> GetAll();
    Task<Widget?> GetOne(string id);
    Task<Widget?> Create(Widget widget);
    Task<Widget?> Update(string id, Widget widget);
    Task<string> Delete(string id);
}

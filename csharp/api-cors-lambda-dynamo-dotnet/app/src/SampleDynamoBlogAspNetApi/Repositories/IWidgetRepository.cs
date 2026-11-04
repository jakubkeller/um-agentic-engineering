using SampleEntityFrameworkCoreAspNetApi.Models;

namespace SampleEntityFrameworkCoreAspNetApi.Repositories;

public interface IWidgetRepository
{
    Task<IEnumerable<Widget>> GetAll();
    Task<Widget?> GetOne(string id);
    Task<string> Create(Widget Widget);
    Task<string> Update(Widget Widget);
    Task<string> Delete(string id);
}

using SampleDynamoBlogAspNetApi.Models;

namespace SampleDynamoBlogAspNetApi.Repositories
{
  public interface IDynamoBlogRepository
  {
    Task<List<Blog>> GetAll();
    Task<Blog> GetOne(string id);
    Task<string> Create(Blog blog);
    Task<string> Update(Blog blog);
    Task<string> Delete(string id);
  }
}

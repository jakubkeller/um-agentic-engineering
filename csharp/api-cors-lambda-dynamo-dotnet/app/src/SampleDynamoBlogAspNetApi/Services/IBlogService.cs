using SampleDynamoBlogAspNetApi.Models;

namespace SampleDynamoBlogAspNetApi.Repositories
{
  public interface IBlogService
  {
    Task<List<Blog>> GetAll();
    Task<Blog> GetOne(string id);
    Task<Blog> Create(Blog blog);
    Task<Blog> Update(string id, Blog blog);
    Task<string> Delete(string id);
  }
}

using Microsoft.AspNetCore.Mvc;
using SampleDynamoBlogAspNetApi.Models;
using SampleDynamoBlogAspNetApi.Services;
using SampleDynamoBlogAspNetApi.Repositories;

namespace SampleDynamoBlogAspNetApi.Controllers;

[ApiController]
[Route("[controller]")]
public class BlogsController : ControllerBase
{
  private readonly IBlogService _blogService;
  private ILogger<BlogsController> _logger;

  public BlogsController(ILogger<BlogsController> logger, IBlogService blogService)
  {
    _logger = logger;
    _blogService = blogService;
  }

  // GET blogs/
  [HttpGet("")]
  public async Task<List<Blog>> GetBlogs()
  {
    return await _blogService.GetAll();
  }

  // GET blogs/abcdefg123456
  [HttpGet("{Id}")]
  public async Task<Blog> GetBlog(string Id)
  {
    return await _blogService.GetOne(Id);
  }

  // POST blogs/abcdefg123456
  [HttpPost("")]
  public async Task<Blog> CreateBlog(Blog blog)
  {
    return await _blogService.Create(blog);
  }

  // PATCH blogs/abcdefg123456
  [HttpPatch("{Id}")]
  public async Task<Blog> UpdateBlog(string Id, Blog blog)
  {
    return await _blogService.Update(Id, blog);
  }

  // DELETE blogs/abcdefg123456
  [HttpDelete("{Id}")]
  public async Task<string> DeleteBlog(string Id)
  {
    return await _blogService.Delete(Id);
  }
}

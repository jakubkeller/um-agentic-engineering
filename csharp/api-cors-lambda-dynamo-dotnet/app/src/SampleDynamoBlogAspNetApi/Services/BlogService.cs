using SampleDynamoBlogAspNetApi.Repositories;
using SampleDynamoBlogAspNetApi.Models;

namespace SampleDynamoBlogAspNetApi.Services
{
    public class BlogService : IBlogService
    {
        private readonly IDynamoBlogRepository _blogRepository;
        private ILogger<BlogService> _logger;

        public BlogService(ILogger<BlogService> logger, IDynamoBlogRepository blogRepository)
        {
            _logger = logger;
            _blogRepository = blogRepository;
        }

        public async Task<List<Blog>> GetAll()
        {
            return await _blogRepository.GetAll();
        }

        public async Task<Blog> GetOne(string id)
        {
            if (string.IsNullOrEmpty(id))
            {
                throw new Exception("Required Parameter Id is missing");
            }

            return await _blogRepository.GetOne(id);
        }

        public async Task<Blog> Create(Blog blog)
        {
            if (blog == null)
            {
                throw new Exception("Required Parameter blog is missing");
            }

            if (!string.IsNullOrEmpty(blog.Id))
            {
                throw new Exception("Id can not be set on create blog");
            }

            if (blog.CreatedTimestamp != DateTime.MinValue || blog.ModifiedTimestamp != DateTime.MinValue)
            {
                throw new Exception("Created or Modified dates can not be set on create blog");
            }

            if (string.IsNullOrWhiteSpace(blog.Name) || string.IsNullOrWhiteSpace(blog.Content))
            {
                throw new Exception("Name and Content are required to create a blog");
            }

            blog.Id = Guid.NewGuid().ToString();
            blog.CreatedTimestamp = DateTime.UtcNow;
            blog.ModifiedTimestamp = blog.CreatedTimestamp;

            var blogId = await _blogRepository.Create(blog);

            return await _blogRepository.GetOne(blogId);
        }

        public async Task<Blog> Update(string id, Blog blog)
        {
            if (string.IsNullOrEmpty(id))
            {
                throw new Exception("Required Parameter Id is missing");
            }

            if (blog == null)
            {
                throw new Exception("Required Parameter blog is missing");
            }

            if (string.IsNullOrWhiteSpace(blog.Id) || string.IsNullOrWhiteSpace(id) || blog.Id != id)
            {
                throw new Exception("Required Parameter Id is missing on object or does not match the key to update");
            }

            if (string.IsNullOrWhiteSpace(blog.Name) || string.IsNullOrWhiteSpace(blog.Content))
            {
                throw new Exception("Name and Content are required to create a blog");
            }

            var existingBlog = await _blogRepository.GetOne(blog.Id);
            if (existingBlog == null)
            {
                throw new Exception("Blog does not exist");
            }

            if (blog.CreatedTimestamp != existingBlog.CreatedTimestamp || blog.ModifiedTimestamp != existingBlog.ModifiedTimestamp)
            {
                throw new Exception("Created and Modified dates must match the current record that is persisted");
            }

            blog.ModifiedTimestamp = DateTime.UtcNow;

            await _blogRepository.Update(blog);

            return await _blogRepository.GetOne(blog.Id);
        }

        public async Task<string> Delete(string id)
        {
            if (string.IsNullOrEmpty(id))
            {
                throw new Exception("Required Parameter Id is missing");
            }

            var existingBlog = await _blogRepository.GetOne(id);
            if (existingBlog == null)
            {
                throw new Exception("Blog does not exist");
            }

            await _blogRepository.Delete(id);

            return id;
        }
    }
}

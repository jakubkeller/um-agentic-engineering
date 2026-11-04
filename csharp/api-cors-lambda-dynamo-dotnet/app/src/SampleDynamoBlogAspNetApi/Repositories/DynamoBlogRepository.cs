using Amazon.DynamoDBv2.DataModel;
using Amazon.DynamoDBv2;
using Amazon;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using Microsoft.Extensions.Logging;
using SampleDynamoBlogAspNetApi.Models;

namespace SampleDynamoBlogAspNetApi.Repositories
{
    public class DynamoBlogRepository : IDynamoBlogRepository
    {
        private readonly ILogger<DynamoBlogRepository> _logger;
        private const string TABLENAME_ENVIRONMENT_VARIABLE_LOOKUP = "TABLE_NAME";
        private const string PRIMARYKEY_ENVIRONMENT_VARIABLE_LOOKUP = "PRIMARY_KEY";
        private readonly string _tableName;
        private readonly string _primaryKey;
        private readonly IDynamoDBContext _ddbContext;

        public DynamoBlogRepository(ILogger<DynamoBlogRepository> logger, IAmazonDynamoDB ddbClient)
        {
            _logger = logger;
            // Check to see if a table name was passed in through environment variables and if so
            // add the table mapping.
            var tableName = Environment.GetEnvironmentVariable(TABLENAME_ENVIRONMENT_VARIABLE_LOOKUP);
            _tableName = string.IsNullOrWhiteSpace(tableName) ? "blogs" : tableName;
            var primaryKey = Environment.GetEnvironmentVariable(PRIMARYKEY_ENVIRONMENT_VARIABLE_LOOKUP);
            _primaryKey = string.IsNullOrWhiteSpace(primaryKey) ? "Id" : primaryKey;

            if (!string.IsNullOrEmpty(_tableName))
            {
                AWSConfigsDynamoDB.Context.TypeMappings[typeof(Blog)] = new Amazon.Util.TypeMapping(typeof(Blog), _tableName);
            }

            var config = new DynamoDBContextConfig { Conversion = DynamoDBEntryConversion.V2 };
            this._ddbContext = new DynamoDBContext(ddbClient, config);
        }
        public async Task<List<Blog>> GetAll()
        {
            return await _ddbContext.ScanAsync<Blog>(new List<ScanCondition>()).GetRemainingAsync();
        }

        public async Task<Blog> GetOne(string id)
        {
            return await _ddbContext.LoadAsync<Blog>(id);
        }

        public async Task<string> Create(Blog blog)
        {
            if (blog == null) return string.Empty;

            await _ddbContext.SaveAsync<Blog>(blog);
            if (blog != null && blog.Id != null) {
                return blog.Id;
            }
            return string.Empty;
        }

        public async Task<string> Update(Blog blog)
        {
            if (blog == null) return string.Empty;
            await _ddbContext.SaveAsync<Blog>(blog);
            if (blog != null && blog.Id != null)
            {
                return blog.Id;
            }
            return string.Empty;
        }

        public async Task<string> Delete(string id)
        {
            await _ddbContext.DeleteAsync<Blog>(id);
            return id;
        }
    }
}

using Amazon.DynamoDBv2.DataModel;
using Microsoft.AspNetCore.Mvc;

namespace SampleDynamoBlogAspNetApi.Models
{
  [DynamoDBTable("blogs")]
  public class Blog
  {
    public Blog()
    {
      Name = string.Empty;
      Content = string.Empty;
    }

    [DynamoDBHashKey]
    public string? Id { get; set; }
    public string Name { get; set; }
    public string Content { get; set; }
    public DateTime CreatedTimestamp { get; set; }
    public DateTime ModifiedTimestamp { get; set; }
  }
}

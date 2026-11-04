using Microsoft.EntityFrameworkCore;
using SampleAspNetApi.AwsHelpers;
using SampleEntityFrameworkCoreAspNetApi.Models;

namespace SampleEntityFrameworkCoreAspNetApi.Contexts;

public class WidgetContext : DbContext
{
    public DbSet<Widget> Widgets { get; set; } = null!;
    private string dbConnectionString;

    protected override void OnConfiguring(DbContextOptionsBuilder options)
       => options.UseNpgsql(dbConnectionString);

    public WidgetContext(DbContextOptions<WidgetContext> options) : base(options)
    {
        string? secretArn = Environment.GetEnvironmentVariable("DBSECRETARN");
        if (secretArn == null)
        {
            throw new Exception("Missing DBSECRETARN Environment Variable");
        }

        var secret = AwsSecretHelper.GetSecret(secretArn);
        if (secret == null)
        {
            throw new Exception("Missing Database Secret Value");
        }

        dbConnectionString = ConnectionStringHelper.GetPostgresConnectionString(secret);
    }
}

using System.ComponentModel.DataAnnotations.Schema;

namespace SampleEntityFrameworkCoreAspNetApi.Models;

[Table("widget")]
public class Widget
{
    public Widget()
    {
        Name = string.Empty;
        Url = string.Empty;
    }

    [Column("id")]
    public string? Id { get; set; }
    [Column("name")]
    public string Name { get; set; }
    [Column("url")]
    public string Url { get; set; }
    [Column("state")]
    public int State { get; set; }
    [Column("windowstate")]
    public int WindowState { get; set; }
    [Column("positionx")]
    public int PositionX { get; set; }
    [Column("positiony")]
    public int PositionY { get; set; }
}

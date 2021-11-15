using namespace System.Management.Automation

class DecorateAttribute : Attribute
{
    DecorateAttribute ([scriptblock]$Decorator)
    {
        $this.Decorator = $Decorator
    }

    [scriptblock]$Decorator
}

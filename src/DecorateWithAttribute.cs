using System;

namespace Decr8r
{
    [AttributeUsage(AttributeTargets.Class)]
    public class DecorateWithAttribute : Attribute
    {
        public DecorateWithAttribute (string decoratorName)
        {
            DecoratorName = string.IsNullOrWhiteSpace(decoratorName)
                ? throw new ArgumentNullException(nameof(decoratorName), "Provide the name of a decorator command.")
                : decoratorName.Trim();
        }

        public string DecoratorName { get; private set; }
    }
}

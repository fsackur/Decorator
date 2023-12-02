using System;
using System.Reflection;
using System.Management.Automation;

namespace Decr8r
{
    public partial class DecoratedCommand
    {
        internal static class Reflected
        {
            private static BindingFlags privateFlags = BindingFlags.NonPublic | BindingFlags.Instance;

            internal static object? GetPropertyValue(object instance, string propertyName) {
                // any access of a null object returns null.
                if (instance == null || string.IsNullOrEmpty(propertyName)) {
                    return null;
                }

                var propertyInfo = instance.GetType().GetProperty(propertyName, privateFlags);

                if (propertyInfo != null)
                {
                    try
                    {
                        return propertyInfo.GetValue(instance);
                    }
                    catch {}
                }

                return null;
            }

            internal static object? InvokeMethod(object instance, string methodName, object[]? parameters) {
                // any access of a null object returns null.
                if (instance == null || string.IsNullOrEmpty(methodName)) {
                    return null;
                }

                var methodInfo = instance.GetType().GetMethod(methodName, privateFlags);

                if (methodInfo != null)
                {
                    try
                    {
                        return methodInfo.Invoke(instance, parameters);
                    }
                    catch {}
                }

                return null;
            }

            internal static Type? GetType(Assembly assembly, string name) {
                return assembly.GetType(name);
            }
        }
    }
}

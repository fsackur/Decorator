using System;
using System.Reflection;
using System.Collections.Generic;
using System.Linq;

namespace Decr8r
{
    public partial class DecoratedCommand
    {
        internal static class Reflected
        {
            internal static BindingFlags PrivateFlags = BindingFlags.NonPublic | BindingFlags.Instance;

            internal static object? GetValue(object instance, string propertyOrFieldName)
            {
                // any access of a null object returns null.
                if (instance == null || string.IsNullOrEmpty(propertyOrFieldName)) {
                    return null;
                }

                var propertyInfo = instance.GetType().GetProperty(propertyOrFieldName, PrivateFlags);
                if (propertyInfo is not null)
                {
                    try
                    {
                        return propertyInfo.GetValue(instance);
                    }
                    catch
                    {
                        return null;
                    }
                }

                var fieldInfo = instance.GetType().GetField(propertyOrFieldName, PrivateFlags);
                if (fieldInfo is not null)
                {
                    try
                    {
                        return fieldInfo.GetValue(instance);
                    }
                    catch {}
                }

                return null;
            }

            internal static object? InvokeMethod(object instance, string methodName, object[]? parameters)
            {
                // any access of a null object returns null.
                if (instance == null || string.IsNullOrEmpty(methodName)) {
                    return null;
                }

                var methodInfo = instance.GetType().GetMethod(methodName, PrivateFlags);

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

            internal static object? Construct(Type type, object[]? parameters)
            {
                // any access of a null object returns null.
                if (type == null) {
                    return null;
                }

                Type[] types = parameters?.Select(p => p.GetType()).ToArray() ?? Array.Empty<Type>();
                var ctor = type.GetConstructor(PrivateFlags, types);

                if (ctor != null)
                {
                    try
                    {
                        return ctor.Invoke(parameters);
                    }
                    catch {}
                }

                return null;
            }
            internal static Type? GetType(Assembly assembly, string name)
            {
                return assembly.GetType(name);
            }
        }
    }
}

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

            // internal static MethodInfo UpdateMethod = typeof(FunctionInfo).GetMethod("Update", privateFlags, null, new Type[] { typeof(ScriptBlock), typeof(bool), typeof(ScopedItemOptions), typeof(string) }, null)!;

            // internal static PropertyInfo InternalSessionStateProperty = typeof(SessionState).GetProperty("Internal", privateFlags)!;

            // internal static MethodInfo GetFunctionTableMethod = InternalSessionStateProperty.PropertyType.GetMethod("GetFunctionTableAtScope", privateFlags)!;

            // internal static PropertyInfo ContextProperty = typeof(PSCmdlet).GetProperty("Context", privateFlags)!;

            // internal static PropertyInfo CurrentCommandProcessorProperty = ContextProperty.PropertyType.GetProperty("CurrentCommandProcessor", privateFlags)!;

            // internal static PropertyInfo CmdletParameterBinderControllerProperty = CurrentCommandProcessorProperty.PropertyType.GetProperty("CmdletParameterBinderController", privateFlags)!;

            // internal static PropertyInfo UnboundArgumentsProperty = CmdletParameterBinderControllerProperty.PropertyType.GetProperty("UnboundArguments", privateFlags)!;

            // internal static PropertyInfo DebuggerProperty = ContextProperty.PropertyType.GetProperty("Debugger", privateFlags)!;

            // internal static ConstructorInfo ScriptInfoCtor = typeof(ScriptInfo).GetConstructor(privateFlags, null, new Type[] { typeof(string), typeof(ScriptBlock), ContextProperty.PropertyType }, null)!;

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

using System;
using System.Reflection;
using System.Management.Automation;

namespace Decr8r
{
    public partial class DecoratedCommand
    {
        internal static class ReflectedMembers
        {
            internal static BindingFlags PrivateFlags = BindingFlags.NonPublic | BindingFlags.Instance;

            internal static MethodInfo UpdateMethod = typeof(FunctionInfo).GetMethod("Update", PrivateFlags, null, new Type[] { typeof(ScriptBlock), typeof(bool), typeof(ScopedItemOptions), typeof(string) }, null)!;

            internal static PropertyInfo InternalSessionStateProperty = typeof(SessionState).GetProperty("Internal", PrivateFlags)!;

            internal static MethodInfo GetFunctionTableMethod = InternalSessionStateProperty.PropertyType.GetMethod("GetFunctionTableAtScope", PrivateFlags)!;

            internal static PropertyInfo ContextProperty = typeof(PSCmdlet).GetProperty("Context", PrivateFlags)!;

            internal static PropertyInfo DebuggerProperty = ContextProperty.PropertyType.GetProperty("Debugger", PrivateFlags)!;

            internal static ConstructorInfo ScriptInfoCtor = typeof(ScriptInfo).GetConstructor(PrivateFlags, null, new Type[] { typeof(string), typeof(ScriptBlock), ContextProperty.PropertyType }, null)!;

            internal static Type IScriptCommandInfo = typeof(FunctionInfo).GetInterface("IScriptCommandInfo")!;

            internal static PropertyInfo ScriptBlockProperty = IScriptCommandInfo.GetProperty("ScriptBlock")!;
        }
    }
}

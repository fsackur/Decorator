using System;
using System.Reflection;
using System.Management.Automation;
using System.Management.Automation.Language;
using SMA = System.Management.Automation;
using System.Diagnostics;
using System.Linq;
using System.Collections;
using ObjectModel = System.Collections.ObjectModel;
using System.Collections.Generic;

namespace Decr8r
{
    [Cmdlet("Decorate", "Command")]
    [OutputType(typeof(void))]
    public partial class DecoratedCommand : PSCmdlet, IDynamicParameters
    {
        // Parameters to exclude from GetDynamicParameters
        private static readonly ISet<string> StaticParams;

        static DecoratedCommand()
        {
            commandParam = new(
                "Command",
                typeof(CommandInfo),
                new ObjectModel.Collection<Attribute>
                {
                    new ParameterAttribute {
                        Position = int.MinValue + 1,    // MinValue disables positional binding; cannot have ambiguous. TODO: re-order values in dynamic block
                        Mandatory = true
                    },
                    new ValidateNotNullOrEmptyAttribute()
                }
            );

            StaticParams = new HashSet<string>(CommonParameters, StringComparer.OrdinalIgnoreCase);
            StaticParams.UnionWith(OptionalCommonParameters);
            StaticParams.Add(commandParam.Name);
        }

        // Not declared as Parameter as workaround for https://github.com/PowerShell/PowerShell/issues/3984
        public CommandInfo Command { get; set; }

        private static readonly RuntimeDefinedParameter commandParam;

        private SteppablePipeline? _pipeline;

        public DecoratedCommand()
        {
            Command = null!;
        }

        public DecoratedCommand(CommandInfo decoratedCommand)
        {
            Command = decoratedCommand ?? throw new ArgumentException("Decorated command cannot be null", nameof(decoratedCommand));
        }

        private readonly ISet<string> staticBoundParams = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        private object context { get => Reflected.GetPropertyValue(this, "Context")!; }

        internal class CommandParameterInternalWrapper
        {
            internal bool ParameterNameSpecified;
            internal string? ParameterName;
            internal string? ParameterText;
            internal bool ArgumentSpecified;
            internal object? ArgumentValue;
            internal CommandParameterInternalWrapper(object arg)
            {
                // Expected runtime type of arg: CommandParameterInternal
                ParameterNameSpecified = (Boolean)Reflected.GetPropertyValue(arg, "ParameterNameSpecified")!;
                ParameterName = ParameterNameSpecified ? Reflected.GetPropertyValue(arg, "ParameterName") as string : null;
                ParameterText = Reflected.GetPropertyValue(arg, "ParameterText") as string;
                ArgumentSpecified = (Boolean)Reflected.GetPropertyValue(arg, "ArgumentSpecified")!;
                ArgumentValue = ArgumentSpecified ? Reflected.GetPropertyValue(arg, "ArgumentValue") : null;
                if (ArgumentValue is PSObject pso)
                {
                    ArgumentValue = pso.BaseObject;
                }
            }
        }

        private IEnumerable<CommandParameterInternalWrapper> GetUnboundArguments()
        {
            var processor = Reflected.GetPropertyValue(context, "CurrentCommandProcessor")!;
            var parameterBinder = Reflected.GetPropertyValue(processor, "CmdletParameterBinderController")!;
            var args = Reflected.GetPropertyValue(parameterBinder, "UnboundArguments") as IEnumerable<object>
                ?? Enumerable.Empty<object>();
            return args.Select((a) => new CommandParameterInternalWrapper(a));
        }

        // https://stackoverflow.com/a/29680516/6274530
        // fails on abbreviated commands :-(
        private object? GetUnboundValue(string desiredParameter, int position = -1) {

            var args = GetUnboundArguments();

            var currentParameterName = string.Empty;
            object? unnamedValue = null;
            int currentPosition = 0;
            foreach (var arg in args) {

                // Is it a param name:
                var isParameterName = (Boolean)(Reflected.GetPropertyValue(arg, "ParameterNameSpecified") ?? false);
                if (isParameterName)
                {
                    string? parameterName = Reflected.GetPropertyValue(arg, "ParameterName") as string;
                    currentParameterName = parameterName ?? currentParameterName;
                    continue;
                }

                // Treat as a value:
                var parameterValue = Reflected.GetPropertyValue(arg, "ArgumentValue");

                if (!string.IsNullOrEmpty(currentParameterName))
                {
                    // Found currentParameterName's value. If it matches paramName, return it
                    if (currentParameterName.Equals(desiredParameter, StringComparison.OrdinalIgnoreCase))
                    {
                        return parameterValue;
                    }
                }
                else if (currentPosition++ == position)
                {
                    unnamedValue = parameterValue;  // Save this for later in case desiredParameter isn't found
                }

                // Found a value, so currentParameterName needs to be cleared
                currentParameterName = string.Empty;
            }

            return unnamedValue;
        }

        public IEnumerable<CallStackFrame> GetCallStack()
        {
            var Debugger = (Reflected.GetPropertyValue(context, "Debugger") as SMA.Debugger)!;
            return Debugger.GetCallStack();
        }

        public object GetDynParamStrategy(IEnumerable<StackFrame> stack)
        {
            var entrypoint = stack.First();
            // MethodBase entryMethod = entrypoint.GetMethod()!;
            var entryMethod = entrypoint.GetMethod()!;

            var PseudoParameterBinder = Reflected.GetType(typeof(PSObject).Assembly, "System.Management.Automation.Language.PseudoParameterBinder");

            foreach (var frame in stack.Skip(1))
            {
                try
                {
                    var method = frame.GetMethod()!;
                    if (method == entryMethod && method.DeclaringType == entryMethod.DeclaringType)
                    {
                        return "Recursion";
                    }
                    if (method.DeclaringType == PseudoParameterBinder)
                    {
                        return "Completion";
                    }
                }
                catch
                {
                    continue;
                }
            }


            return "foo";
        }

        // public RuntimeDefinedParameterDictionary dynParams = new() { { commandParam.Name, commandParam } };

        public object GetDynamicParameters()
        {
            // var h = InvokeCommand.InvokeScript("Get-History -Count 1").Select((pso) => ((Microsoft.PowerShell.Commands.HistoryInfo)pso.BaseObject).Id).FirstOrDefault();
            var dynParams = new RuntimeDefinedParameterDictionary() { { commandParam.Name, commandParam } };

            // When we invoke the static parameter binder, we recurse.
            var trace = new StackTrace();
            var _myFrame = trace.GetFrame(0)!;
            var myMethod = _myFrame.GetMethod()!;
            if (trace.GetFrames().Skip(1).Any((f) => { try { var fm = f.GetMethod(); return fm == myMethod && fm.DeclaringType == myMethod.DeclaringType; } catch { return false; } }))
            {
                return dynParams;
            }

            if (Command is null)
            {
                var myCommandParts = new List<string> { MyInvocation.InvocationName };
                var currentParamName = string.Empty;
                foreach (var arg in GetUnboundArguments())
                {
                    if (arg.ParameterNameSpecified)
                    {
                        myCommandParts.Add(arg.ParameterText!);
                        currentParamName = arg.ParameterName!;
                    }
                    if (arg.ArgumentSpecified)
                    {
                        if (arg.ArgumentValue is CommandInfo c)
                        {
                            if (commandParam.Name.StartsWith(currentParamName))
                            {
                                var childResolvedParam = string.Empty;
                                try { childResolvedParam = c.ResolveParameter(currentParamName).Name; } catch {}
                                if (string.IsNullOrEmpty(childResolvedParam))
                                {
                                    Command = c;
                                    break;
                                }
                            }
                            myCommandParts.Add(c.Name);
                        }
                        else if (arg.ArgumentValue is null)
                        {
                            continue;
                        }
                        else
                        {
                            myCommandParts.Add(arg.ArgumentValue.ToString());
                        }
                    }
                }

                if (Command is null)
                {
                    var myCommandLine = string.Join(' ', myCommandParts);

                    Token[] tokens = null!;
                    ParseError[] errors = null!;
                    var ast = Parser.ParseInput(myCommandLine, out tokens, out errors)
                        ?? throw new ParseException(errors);

                    var statementAst = ast.EndBlock.Statements.Last() as PipelineAst
                        ?? throw new ParseException("Invocation was not a PipelineAst");

                    var commandAst = statementAst.PipelineElements.OfType<CommandAst>().FirstOrDefault((c) =>
                    {
                        var commandInfo = InvokeCommand.GetCommand(c.GetCommandName(), CommandTypes.All);
                        while (commandInfo is AliasInfo)
                        {
                            commandInfo = ((AliasInfo)commandInfo).ResolvedCommand;
                        }
                        return commandInfo is CmdletInfo && commandInfo.Name == MyInvocation.MyCommand.Name;
                    });

                    if (commandAst is null)
                    {
                        return dynParams;
                    }

                    // triggers recursion!
                    var bindingResult = StaticParameterBinder.BindCommand(commandAst, true);

                    var commandParamResult = bindingResult.BoundParameters.Where((kvp) => kvp.Key == commandParam.Name).Select((kvp) => kvp.Value).FirstOrDefault();
                    if (commandParamResult is null)
                    {
                        return dynParams;
                    }

                    var valueAst = commandParamResult.Value;
                    var value = InvokeCommand.InvokeScript(valueAst.Extent.Text).Select((pso) => pso.BaseObject);
                    Command = value.FirstOrDefault() as CommandInfo
                        ?? throw new ParameterBindingException("Failed to parse the decorated command");
                }
            }

            var originalParams = Command.Parameters.Values.Where((p) => !StaticParams.Contains(p.Name));

            foreach (var p in originalParams)
            {
                var dynParam = new RuntimeDefinedParameter(p.Name, p.ParameterType, p.Attributes);
                dynParams[p.Name] = dynParam;
            }

            // TODO: re-order to ensure commandParam is always lowest above int.MinValue
            // var foo = originalParams.SelectMany((p) => p.Attributes)
            //                         .OfType<ParameterAttribute>()
            //                         .Select((p) => p.Position)
            //                         .Where((i) => i > int.MinValue)
            //                         .Order()
            //                         .First();
            return dynParams;
        }

        protected override void BeginProcessing()
        {
            staticBoundParams.UnionWith(MyInvocation.BoundParameters.Keys);

            MyInvocation.BoundParameters.Remove(commandParam.Name);

            var ps = PowerShell.Create(RunspaceMode.CurrentRunspace);
            ps.AddCommand(Command).AddParameters(MyInvocation.BoundParameters);
            _pipeline = ps.GetSteppablePipeline();
            _pipeline.Begin(this);
        }

        protected override void ProcessRecord()
        {
            var pipelineBoundParams = MyInvocation.BoundParameters.Where((kvp) => !staticBoundParams.Contains(kvp.Key));

            var (byValue, passObject) = pipelineBoundParams.Count() switch
            {
                0 => (false, false),
                1 => (Command.Parameters[pipelineBoundParams.First().Key]
                             .Attributes
                             .OfType<ParameterAttribute>()
                             .Where((a) => a.ParameterSetName == ParameterSetName)
                             .Any((a) => a.ValueFromPipeline),
                      true),
                _ => (true, true)
            };

            if (passObject)
            {
                var pso = new PSObject();
                foreach (var kvp in pipelineBoundParams)
                {
                    pso.Members.Add(new PSNoteProperty(kvp.Key, kvp.Value));
                }
                _pipeline!.Process(pso);
            }
            else
            {
                _pipeline!.Process();
            }
        }

        protected override void EndProcessing()
        {
            _pipeline!.End();
        }
    }
}

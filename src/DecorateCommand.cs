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
                        Position = 0,
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

        private IEnumerable GetUnboundArguments()
        {
            var processor = Reflected.GetPropertyValue(context, "CurrentCommandProcessor")!;
            var parameterBinder = Reflected.GetPropertyValue(processor, "CmdletParameterBinderController")!;

            // Expected runtime type: ObjectModel.Collection<CommandParameterInternal>
            var args = Reflected.GetPropertyValue(parameterBinder, "UnboundArguments") as IEnumerable;
            return args ?? Enumerable.Empty<object>();
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

        public CallStackFrame GetCaller()
        {
            var Debugger = (Reflected.GetPropertyValue(context, "Debugger") as SMA.Debugger)!;
            return Debugger.GetCallStack().Where((f) => f.FunctionName != this.GetType().Name).First()
                ?? throw new InvalidOperationException("Could not identify calling frame");
        }

        public CallStackFrame GetMyFrame()
        {
            var Debugger = (Reflected.GetPropertyValue(context, "Debugger") as SMA.Debugger)!;
            return Debugger.GetCallStack().First();
        }

        public object GetDynamicParameters()
        {
            var dynParams = new RuntimeDefinedParameterDictionary();

            var caller = GetCaller();

            var myFrame = GetMyFrame();
            var myCommandLine = myFrame.Position.Text;
            Token[] tokens = null!;
            ParseError[] errors = null!;
            var ast = Parser.ParseInput(myCommandLine, out tokens, out errors)
                ?? throw new ParseException(errors);
            var statementAst = ast.EndBlock.Statements.Last() as PipelineAst
                ?? throw new ParseException("Invocation was not a PipelineAst");
            CommandAst commandAst = null!;
            foreach (var a in statementAst.PipelineElements.Where((a) => a is CommandAst))
            {
                CommandAst c = (CommandAst)a!;
                var command = InvokeCommand.GetCommand(c.GetCommandName(), CommandTypes.All);
                while (command is AliasInfo)
                {
                    command = ((AliasInfo)command).ResolvedCommand;
                }
                if (command is CmdletInfo && command.Name == $"Decorate-Command")
                {
                    commandAst = c;
                    break;
                }
            }
                // ?? throw new ParseException("Invocation was not a CommandAst");

            var bindingResult = StaticParameterBinder.BindCommand(commandAst, true);



            if (Command is null)
            {
                // var context = Reflected.ContextProperty.GetValue(this);
                // var processor = Reflected.CurrentCommandProcessorProperty.GetValue(this);
                // var parameterBinder = Reflected.CmdletParameterBinderControllerProperty.GetValue(processor);
                // var args = Reflected.UnboundArgumentsProperty.GetValue(parameterBinder) as System.Collections.IEnumerable;

                var arg = GetUnboundValue("Command");
                // args is empty when completing command name
                dynParams[commandParam.Name] = commandParam;
                return dynParams;
            }

            var originalParams = Command.Parameters.Values.Where((p) => !StaticParams.Contains(p.Name));

            foreach (var p in originalParams)
            {
                var dynParam = new RuntimeDefinedParameter(p.Name, p.ParameterType, p.Attributes);
                dynParams[p.Name] = dynParam;
            }

            return dynParams;
        }

        protected override void BeginProcessing()
        {
            staticBoundParams.UnionWith(MyInvocation.BoundParameters.Keys);

            MyInvocation.BoundParameters.Remove("Command");

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

using System;
using System.Management.Automation;
using System.Management.Automation.Language;
using System.Diagnostics;
using System.Linq;
using ObjectModel = System.Collections.ObjectModel;
using System.Collections;
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

        private object context { get => Reflected.GetValue(this, "Context")!; }

        internal class CommandParameterInternalWrapper
        {
            internal bool SpaceAfterParameter = default;
            internal bool ParameterNameSpecified = default;
            internal bool ArgumentSpecified = default;
            internal bool ParameterAndArgumentSpecified = default;
            internal bool FromHashtableSplatting = default;
            internal string? ParameterName = default;
            internal string? ParameterText = default;
            internal Ast? ParameterAst = default;
            internal IScriptExtent? ParameterExtent = default;
            internal Ast? ArgumentAst = default;
            internal IScriptExtent? ArgumentExtent = default;
            internal object? ArgumentValue = default;
            internal bool ArgumentToBeSplatted = default;

            // Expected runtime type of arg: CommandParameterInternal
            internal CommandParameterInternalWrapper(object arg)
            {
                var fields = this.GetType().GetFields(Reflected.PrivateFlags);
                foreach (var field in fields)
                {
                    var value = Reflected.GetValue(arg, field.Name);
                    field.SetValue(this, value);
                }

                if (ArgumentValue is PSObject pso)
                {
                    ArgumentValue = pso.BaseObject;
                }
            }
        }

        private IEnumerable<CommandParameterInternalWrapper> GetUnboundArguments()
        {
            var processor = Reflected.GetValue(context, "CurrentCommandProcessor")!;
            var parameterBinder = Reflected.GetValue(processor, "CmdletParameterBinderController")!;
            var args = Reflected.GetValue(parameterBinder, "UnboundArguments") as IEnumerable<object>
                ?? Enumerable.Empty<object>();
            return args.Select((a) => new CommandParameterInternalWrapper(a));
        }

        private bool TryParseCommandArg()
        {
            // During command completion, we are called by the PseudoParameterBinder and argument
            // values are string. When the command is actually invoked, argument values are
            // populated with their actual values.
            var isInPseudoBinding = IsInPseudoBinding();

            var bindings = new Dictionary<string, CommandParameterInternalWrapper>();
            var args = new List<CommandParameterInternalWrapper>();

            var unboundArgs = GetUnboundArguments();
            var e = unboundArgs.GetEnumerator();
            while (e.MoveNext())
            {
                var arg = e.Current;

                if (arg.ParameterNameSpecified && commandParam.Name.StartsWith(arg.ParameterName!, StringComparison.OrdinalIgnoreCase))
                {
                    if (arg.ArgumentSpecified || e.MoveNext())
                    {
                        bindings.Add(arg.ParameterName!, e.Current);
                        continue;
                    }
                }

                if (arg.ArgumentSpecified)
                {
                    // Handle splatting
                    if (isInPseudoBinding
                        && arg.ArgumentValue is string s
                        && s.StartsWith("@"))
                    {
                        Token[] tokens;
                        ParseError[] errors;
                        var expressionAst = Parser.ParseInput((string)arg.ArgumentValue, out tokens, out errors)
                                                  .EndBlock
                                                  .Statements
                                                  .OfType<PipelineAst>()
                                                  .FirstOrDefault()?
                                                  .GetPureExpression();

                        if (expressionAst is VariableExpressionAst v && v.Splatted)
                        {
                            IDictionary? splat = SessionState.PSVariable.GetValue(v.VariablePath.UserPath) as IDictionary ?? new Hashtable();
                            foreach (var key in splat.Keys)
                            {
                                if (key is string k
                                    && commandParam.Name.StartsWith(k, StringComparison.OrdinalIgnoreCase)
                                    && splat[k] is PSObject o
                                    && o.BaseObject is CommandInfo c)
                                {
                                    arg.ArgumentValue = c;
                                    bindings[k] = arg;
                                }
                            }
                        }
                    }
                    else
                    {
                        args.Add(arg);
                    }
                }
            }

            Func<CommandParameterInternalWrapper, object?> unpack = arg => arg.ArgumentValue switch
            {
                CommandInfo c => c,
                object o when isInPseudoBinding && o as string is not null
                    => InvokeCommand.InvokeScript((string)o)
                                    .Select(pso => pso.BaseObject)
                                    .FirstOrDefault(),
                _ => null
            };

            // prefer named bindings
            var _command = bindings.OrderByDescending(kvp => kvp.Key.Length)
                                   .Select(kvp => unpack(kvp.Value))
                                   .OfType<CommandInfo>()
                                   .FirstOrDefault();

            // accept first positional binding
            _command ??= args.Select(unpack)
                             .OfType<CommandInfo>()
                             .FirstOrDefault();

            Command = _command!;
            return Command is not null;
        }

        private bool IsInPseudoBinding()
        {
            var stack = new StackTrace();
            return stack.GetFrames()
                        .Select((f) => f.GetMethod()?.DeclaringType?.FullName)
                        .OfType<string>()
                        .Any((name) => name == "System.Management.Automation.Language.PseudoParameterBinder");
        }

        public object GetDynamicParameters()
        {
            var dynParams = new RuntimeDefinedParameterDictionary() { { commandParam.Name, commandParam } };

            if (!TryParseCommandArg())
            {
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

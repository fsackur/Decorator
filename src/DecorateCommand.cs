using System;
using System.Management.Automation;
using SMA = System.Management.Automation;
using System.Diagnostics;
using System.Linq;
using System.Collections;
using System.Collections.Generic;

namespace Decr8r
{
    [Cmdlet("Decorate", "Command")]
    [OutputType(typeof(void))]
    public partial class DecoratedCommand : PSCmdlet, IDynamicParameters
    {
        // Parameters to exclude from GetDynamicParameters
        public static ISet<string> StaticParams;
        static DecoratedCommand()
        {
            StaticParams = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            StaticParams.UnionWith(CommonParameters);
            StaticParams.UnionWith(OptionalCommonParameters);
            StaticParams.Add(nameof(Command));
        }

        // We need ExecutionContext, but it's an internal class and an internal instance member.
        public dynamic? __context;
        public dynamic _Context
        {
            get
            {
                __context ??= ReflectedMembers.ContextProperty.GetValue(this)!;
                return __context;
            }
        }

        public SMA.Debugger Debugger { get => ReflectedMembers.DebuggerProperty.GetValue(_Context); }

        private CommandInfo _command;

        [Parameter(Mandatory = true, Position = 0)]
        public CommandInfo Command
        {
            get => _command;
            set
            {
                dynParams = null!;
                _command = value;
            }
        }

        private SteppablePipeline? _pipeline;

        public DecoratedCommand()
        {
            Command = null!;
        }
        // public DecoratedCommand() : this(ScriptBlock.Create("")) {}
        // public DecoratedCommand(ScriptBlock scriptBlock)
        // {
        //     Command = scriptBlock == null
        //         ? throw new ArgumentException("Decorated command cannot be null", nameof(scriptBlock))
        //         : (ScriptInfo)ReflectedMembers.ScriptInfoCtor.Invoke(new object[] { Guid.NewGuid().ToString(), scriptBlock, _Context as ExecutionContext });
        // }

        public DecoratedCommand(CommandInfo decoratedCommand)
        {
            Command = decoratedCommand ?? throw new ArgumentException("Decorated command cannot be null", nameof(decoratedCommand));
        }

        public CallStackFrame GetCaller()
        {
            return Debugger.GetCallStack().Where((f) => f.FunctionName != this.GetType().Name).First()
                ?? throw new InvalidOperationException("Could not identify calling frame");
        }

        private RuntimeDefinedParameterDictionary dynParams;
        private ISet<string> staticBoundParams;

        object IDynamicParameters.GetDynamicParameters() => GetDynamicParameters();

        public RuntimeDefinedParameterDictionary GetDynamicParameters()
        {
            if (dynParams is not null)
            {
                return dynParams;
            }

            dynParams = new();
            if (Command is null)
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

        // public RuntimeDefinedParameterDictionary GetMergedParameters(CommandInfo decorator)
        // {
        //     var dynParams = Parameters;

        //     var newParams = decorator.Parameters.Values.Where((p) =>
        //         p.ParameterType != this.GetType() &&
        //         !(CommonParameters.Contains(p.Name) || OptionalCommonParameters.Contains(p.Name))
        //     );

        //     foreach (var p in newParams)
        //     {
        //         var dynParam = new RuntimeDefinedParameter(p.Name, p.ParameterType, p.Attributes);
        //         dynParams[p.Name] = dynParam;
        //     }

        //     return dynParams;
        // }

        public void Begin() => BeginProcessing();
        protected override void BeginProcessing()
        {
            staticBoundParams = new HashSet<string>(MyInvocation.BoundParameters.Keys, StringComparer.OrdinalIgnoreCase);

            MyInvocation.BoundParameters.Remove("Command");

            var ps = PowerShell.Create(RunspaceMode.CurrentRunspace);
            ps.AddCommand(Command).AddParameters(MyInvocation.BoundParameters);
            _pipeline = ps.GetSteppablePipeline();
            _pipeline.Begin(this);
        }

        public void Process() => ProcessRecord();
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

        public void End() => EndProcessing();
        protected override void EndProcessing()
        {
            _pipeline!.End();
        }
    }
}

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

        [Parameter(Mandatory = true, Position = 0)]
        public CommandInfo Command { get; set; }

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

        public RuntimeDefinedParameterDictionary Parameters { get => (RuntimeDefinedParameterDictionary)GetDynamicParameters(); }

        object IDynamicParameters.GetDynamicParameters() => GetDynamicParameters();

        public RuntimeDefinedParameterDictionary GetDynamicParameters()
        {
            var dynParams = new RuntimeDefinedParameterDictionary();

            if (Command == null)
            {
                return dynParams;
            }

            var originalParams = Command.Parameters.Values.Where((p) => !(CommonParameters.Contains(p.Name) || OptionalCommonParameters.Contains(p.Name)));

            foreach (var p in originalParams)
            {
                var dynParam = new RuntimeDefinedParameter(p.Name, p.ParameterType, p.Attributes);
                dynParams[p.Name] = dynParam;
            }

            return dynParams;
        }

        public RuntimeDefinedParameterDictionary GetMergedParameters(CommandInfo decorator)
        {
            var dynParams = Parameters;

            var newParams = decorator.Parameters.Values.Where((p) =>
                p.ParameterType != this.GetType() &&
                !(CommonParameters.Contains(p.Name) || OptionalCommonParameters.Contains(p.Name))
            );

            foreach (var p in newParams)
            {
                var dynParam = new RuntimeDefinedParameter(p.Name, p.ParameterType, p.Attributes);
                dynParams[p.Name] = dynParam;
            }

            return dynParams;
        }

        public void Begin() => BeginProcessing();
        protected override void BeginProcessing()
        {
            // Type IScriptCommandInfo = typeof(CommandInfo).Assembly.GetType("System.Management.Automation.IScriptCommandInfo")!;
            // Type IScriptCommandInfo = Command.GetType().GetInterface("IScriptCommandInfo")!;
            // ScriptBlock scriptBlock;
            // if (Command.GetType().IsAssignableTo(ReflectedMembers.IScriptCommandInfo))
            // {
            //     scriptBlock = (ScriptBlock)ReflectedMembers.ScriptBlockProperty.GetValue(Command)!;
            // }
            // else
            // {
            //     throw new NotImplementedException("TODO: commands other than functions");
            // }

            var caller = GetCaller();
            var callerVars = caller.GetFrameVariables();
            // IDictionary<string, object> psbp = callerVars["PSBoundParameters"]?.Value as IDictionary<string, object> ?? new Dictionary<string, object>();
            IDictionary<string, object> psbp = (callerVars["PSBoundParameters"]?.Value as IDictionary<string, object>)!;
            psbp = psbp == null ? new Dictionary<string, object>(StringComparer.OrdinalIgnoreCase) : new Dictionary<string, object>(psbp, StringComparer.OrdinalIgnoreCase);

            // var wrapper = ScriptBlock.Create("& ")
            var commandOrigin = caller.InvocationInfo.CommandOrigin;

            var ps = PowerShell.Create(RunspaceMode.CurrentRunspace);
            ps.AddCommand(Command).AddParameters((IDictionary)psbp);
            _pipeline = ps.GetSteppablePipeline();
            _pipeline.Begin(this);

            // WriteObject("foo");
        }

        public void Process() => ProcessRecord();
        protected override void ProcessRecord()
        {
            _pipeline!.Process();
        }

        public void End() => EndProcessing();
        protected override void EndProcessing()
        {
            _pipeline!.End();
        }
    }
}

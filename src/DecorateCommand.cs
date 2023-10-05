using System;
using System.Reflection;
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
        private static readonly ISet<string> StaticParams;

        static DecoratedCommand()
        {
            StaticParams = new HashSet<string>(CommonParameters, StringComparer.OrdinalIgnoreCase);
            StaticParams.UnionWith(OptionalCommonParameters);
            StaticParams.Add(nameof(Command));
            StaticParams.Add(nameof(CommandName));
        }

        [Parameter()]
        public CommandInfo Command { get; set; }

        // workaround for https://github.com/PowerShell/PowerShell/issues/3984
        [Parameter()]
        public string? CommandName { get; set; }

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

        public object GetDynamicParameters()
        {
            var dynParams = new RuntimeDefinedParameterDictionary();

            if (Command is null && CommandName is null)
            {
                return dynParams;
            }

            if (Command is null)
            {
                Command = InvokeCommand.GetCommand(CommandName, CommandTypes.All);
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

            MyInvocation.BoundParameters.Remove(nameof(Command));
            MyInvocation.BoundParameters.Remove(nameof(CommandName));

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

using System;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Management.Automation.Language;
using System.Collections.Generic;
using System.Linq;


namespace Decr8r
{
    internal class DecoratorCannotBeAppliedException : Exception
    {
        internal DecoratorCannotBeAppliedException(string message) : base(message) {}
    }


    [AttributeUsage(AttributeTargets.Class)]
    public class DecorateWithAttribute : Attribute
    {
        public DecorateWithAttribute (string decoratorName)
        {
            decoratorName = string.IsNullOrWhiteSpace(decoratorName)
                ? throw new ArgumentNullException(nameof(decoratorName), "Provide the name of a decorator command.")
                : decoratorName.Trim();

            if (!
                (Runspace.CanUseDefaultRunspace
                    && Runspace.DefaultRunspace.Debugger is Debugger debugger
                    && debugger.GetCallStack().FirstOrDefault() is CallStackFrame caller))
            {
                throw new DecoratorCannotBeAppliedException("Decr8r: cannot decorate command: default runspace is not available.");
            }

            PSVariable? psVar;
            Ast? ast;
            var frameVars = caller.GetFrameVariables();

            // when invoking the command
            var invocation = caller.Position.Text;
            var isTabCompleting = invocation.StartsWith("[System.Management.Automation.CommandCompletion]::CompleteInput(");
            if (isTabCompleting)
            {
                if (frameVars.TryGetValue("inputScript", out psVar))
                {
                    invocation = (string)psVar.Value;
                }
                else if (frameVars.TryGetValue("ast", out psVar))
                {
                    ast = (Ast)psVar.Value;
                    invocation = ast.Extent.Text;
                }
                else
                {
                    // During tab-completion, this is swallowed. Tab-completion won't work and the command is not added to
                    // the table, but the command will be parsed again when needed.
                    throw new DecoratorCannotBeAppliedException("Decr8r: cannot decorate command: failed to identify command to decorate in the call stack.");
                }
            }

            Token[] tokens;
            ParseError[] errors;
            var commandAst = Parser.ParseInput(invocation, out tokens, out errors)
                                   .Find(ast => ast is CommandAst, true)
                                   as CommandAst
                                   ?? throw new DecoratorCannotBeAppliedException("Decr8r: cannot decorate command: failed to identify command to decorate in the call stack.");

            string commandName = (string)commandAst.CommandElements[0].SafeGetValue();

            CommandInvocationIntrinsics invokeCommand;
            object? executionContext = null;
            if (frameVars.TryGetValue("PSCmdlet", out psVar))
            {
                var psCmdlet = (PSCmdlet)psVar.Value;
                invokeCommand = psCmdlet.InvokeCommand;
            }
            else
            {
                executionContext = DecoratedCommand.Reflected.GetValue(debugger, "_context");
                EngineIntrinsics engineIntrinsics = (EngineIntrinsics)DecoratedCommand.Reflected.GetValue(executionContext!, "EngineIntrinsics")!;
                invokeCommand = engineIntrinsics.InvokeCommand;
            }

            Decorator = invokeCommand.GetCommand(decoratorName, CommandTypes.All);
            Command = invokeCommand.GetCommand(commandName, CommandTypes.All);
            if (isTabCompleting && Command is null)
            {
                commandName = invokeCommand.GetCommandName($"{commandName}*", true, false).First();
                Command = invokeCommand.GetCommand(commandName, CommandTypes.All);
            }

            var sessionState = Command.Module?.SessionState;
            if (sessionState is null)
            {
                executionContext ??= DecoratedCommand.Reflected.GetValue(debugger, "_context");
                sessionState = (SessionState)DecoratedCommand.Reflected.GetValue(executionContext!, "SessionState")!;
            }

            var internalSessionState = DecoratedCommand.Reflected.GetValue(sessionState, "_sessionState");
            var functionTable = (Dictionary<string, FunctionInfo>)DecoratedCommand.Reflected.InvokeMethod(internalSessionState!, "GetFunctionTable", new object[] { })!;

            var decoratedFunction = (FunctionInfo)DecoratedCommand.Reflected.Construct(typeof(FunctionInfo), new object[] { commandName })!;
            var scriptBlock = ScriptBlock.Create($"& {decoratorName} -Decorated {commandName} $args");

            DecoratedCommand.Reflected.FunctionInfoUpdate((FunctionInfo)Command, scriptBlock, true, (Command as FunctionInfo)!.Options, (Command as FunctionInfo)!.HelpFile);
        }

        public CommandInfo Decorator { get; init; }

        public CommandInfo Command { get; init; }
    }
}

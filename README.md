# Decr8r
Function decorators, like Python!

## Scratch notes for new project

I work a lot with Python, and I have a taste for metaprogramming and code generation. PS has some nice reflection characteristics, but it's not strong in these areas. I'd like to address that.

This impulse was specifically sparked by a module that needed the same parameter on a lot of functions.

I haven't figured out yet what this should do, what use cases to support.

I'm pretty certain that it will export Attribute classes. I want those attributes to add value to functions.

PS, as of 7.2.0, doesn't provide any generic hooks AFAICS. You can implement parameter validators and transformers and they'll work as expected, but you can't AFAICS, subclass e.g. CmdletBindingAttribute and expect anything to happen.

Therefore, the workflow would look something like this:

- write code:
  ```pwsh
  function Do-StuffWithNewParam
  {
      return $NewParam * 2
  }

  function Inject-NewParam
  {
      [Decr8r.Decorate("Do-StuffWithNewParam")]
      [CmdletBinding()]
      param
      (
          [Parameter()]$NewParam
      )
  }
  ```
- Apply decorator dynamically in your module:
  - append to psm1: `Apply-Decorators`
- Or, because dynamically rewriting functions will be slow on module import, in the build process:
  - step: `Compile decorated functions from source code`

## Next steps

- Hack, see what's possible, form ideas for use cases
- Keen to hear ideas
  - Ping me! I'm `@freddie_sackur` in the PowerShell discord. [Invite link](https://discord.com/invite/powershell)
  - Or, open an issue in this repo
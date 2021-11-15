class DecoratorException : Exception
{
    DecoratorException([string]$Message) : base($Message) {}
    DecoratorException([string]$Message, [Exception]$InnerException) : base($Message, $InnerException) {}
}

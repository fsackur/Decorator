using System;
using System.Management.Automation;
using System.Collections.ObjectModel;
using System.Collections.Generic;

namespace PasteFromSO
{
    internal class DynParamQuotedString {
        /*
            This works around the PowerShell bug where ValidateSet values aren't quoted when necessary, and
            adding the quotes breaks it. Example:

            ValidateSet valid values = 'Test string'  (The quotes are part of the string)

            PowerShell parameter binding would interperet that as [Test string] (no single quotes), which wouldn't match
            the valid value (which has the quotes). If you make the parameter a DynParamQuotedString, though,
            the parameter binder will coerce [Test string] into an instance of DynParamQuotedString, and the binder will
            call ToString() on the object, which will add the quotes back in.
        */

        internal static string DefaultQuoteCharacter = "'";

        public DynParamQuotedString(string quotedString) : this(quotedString, DefaultQuoteCharacter) {}
        public DynParamQuotedString(string quotedString, string quoteCharacter) {
            OriginalString = quotedString;
            _quoteCharacter = quoteCharacter;
        }

        public string OriginalString { get; set; }
        string _quoteCharacter;

        public override string ToString() {
            // I'm sure this is missing some other characters that need to be escaped. Feel free to add more:
            if (System.Text.RegularExpressions.Regex.IsMatch(OriginalString, @"\s|\(|\)|""|'")) {
                return string.Format("{1}{0}{1}", OriginalString.Replace(_quoteCharacter, string.Format("{0}{0}", _quoteCharacter)), _quoteCharacter);
            }
            else {
                return OriginalString;
            }
        }

        public static string[] GetQuotedStrings(IEnumerable<string> values) {
            var returnList = new List<string>();
            foreach (string currentValue in values) {
                returnList.Add((new DynParamQuotedString(currentValue)).ToString());
            }
            return returnList.ToArray();
        }
    }


    [Cmdlet(VerbsCommon.Get, "BookDetails")]
    public class GetBookDetails : PSCmdlet, IDynamicParameters
    {
        IDictionary<string, string[]> m_dummyData = new Dictionary<string, string[]>(StringComparer.OrdinalIgnoreCase) {
            {"Terry Pratchett", new [] {"Small Gods", "Mort", "Eric"}},
            {"Douglas Adams", new [] {"Hitchhiker's Guide", "The Meaning of Liff"}},
            {"An 'Author' (notice the ')", new [] {"A \"book\"", "Another 'book'","NoSpace(ButCharacterThatShouldBeEscaped)", "NoSpace'Quoted'", "NoSpace\"Quoted\""}}   // Test value I added
        };

        protected override void ProcessRecord()
        {
            WriteObject(string.Format("Author = {0}", _author));
            WriteObject(string.Format("Book = {0}", ((DynParamQuotedString) MyInvocation.BoundParameters["Book"]).OriginalString));
        }

        // Making this static means it should keep track of the last author used
        static string _author;
        public object GetDynamicParameters()
        {
            // Get 'Author' if found, otherwise get first unnamed value
            string author = GetUnboundValue("Author", 0) as string;
            if (!string.IsNullOrEmpty(author)) {
                _author = author.Trim('\'').Replace(
                    string.Format("{0}{0}", DynParamQuotedString.DefaultQuoteCharacter),
                    DynParamQuotedString.DefaultQuoteCharacter
                );
            }

            var parameters = new RuntimeDefinedParameterDictionary();

            bool isAuthorParamMandatory = true;
            if (!string.IsNullOrEmpty(_author) && m_dummyData.ContainsKey(_author)) {
                isAuthorParamMandatory = false;
                var m_bookParameter = new RuntimeDefinedParameter(
                    "Book",
                    typeof(DynParamQuotedString),
                    new Collection<Attribute>
                    {
                        new ParameterAttribute {
                            ParameterSetName = "BookStuff",
                            Position = 1,
                            Mandatory = true
                        },
                        new ValidateSetAttribute(DynParamQuotedString.GetQuotedStrings(m_dummyData[_author])),
                        new ValidateNotNullOrEmptyAttribute()
                    }
                );

                parameters.Add(m_bookParameter.Name, m_bookParameter);
            }

            // Create author parameter. Parameter isn't mandatory if _author
            // has a valid author in it
            var m_authorParameter = new RuntimeDefinedParameter(
                "Author",
                typeof(DynParamQuotedString),
                new Collection<Attribute>
                {
                    new ParameterAttribute {
                        ParameterSetName = "BookStuff",
                        Position = 0,
                        Mandatory = isAuthorParamMandatory
                    },
                    new ValidateSetAttribute(DynParamQuotedString.GetQuotedStrings(m_dummyData.Keys)),
                    new ValidateNotNullOrEmptyAttribute()
                }
            );
            parameters.Add(m_authorParameter.Name, m_authorParameter);

            return parameters;
        }

        /*
            TryGetProperty() and GetUnboundValue() are from here: https://gist.github.com/fearthecowboy/1936f841d3a81710ae87
            Source created a dictionary for all unbound values; I had issues getting ValidateSet on Author parameter to work
            if I used that directly for some reason, but changing it into a function to get a specific parameter seems to work
        */

        object TryGetProperty(object instance, string fieldName) {
            var bindingFlags = System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.Static | System.Reflection.BindingFlags.Public;

            // any access of a null object returns null.
            if (instance == null || string.IsNullOrEmpty(fieldName)) {
                return null;
            }

            var propertyInfo = instance.GetType().GetProperty(fieldName, bindingFlags);

            if (propertyInfo != null) {
                try {
                    return propertyInfo.GetValue(instance, null);
                }
                catch {
                }
            }

            // maybe it's a field
            var fieldInfo = instance.GetType().GetField(fieldName, bindingFlags);

            if (fieldInfo!= null) {
                try {
                    return fieldInfo.GetValue(instance);
                }
                catch {
                }
            }

            // no match, return null.
            return null;
        }

        object GetUnboundValue(string paramName) {
            return GetUnboundValue(paramName, -1);
        }

        object GetUnboundValue(string paramName, int unnamedPosition) {

            // If paramName isn't found, value at unnamedPosition will be returned instead
            var context = TryGetProperty(this, "Context");
            var processor = TryGetProperty(context, "CurrentCommandProcessor");
            var parameterBinder = TryGetProperty(processor, "CmdletParameterBinderController");
            var args = TryGetProperty(parameterBinder, "UnboundArguments") as System.Collections.IEnumerable;

            if (args != null) {
                var currentParameterName = string.Empty;
                object unnamedValue = null;
                int i = 0;
                foreach (var arg in args) {
                    var isParameterName = TryGetProperty(arg, "ParameterNameSpecified");
                    if (isParameterName != null && true.Equals(isParameterName)) {
                        string parameterName = TryGetProperty(arg, "ParameterName") as string;
                        currentParameterName = parameterName;

                        continue;
                    }

                    // Treat as a value:
                    var parameterValue = TryGetProperty(arg, "ArgumentValue");

                    if (currentParameterName != string.Empty) {
                        // Found currentParameterName's value. If it matches paramName, return
                        // it
                        if (currentParameterName.Equals(paramName, StringComparison.OrdinalIgnoreCase)) {
                            return parameterValue;
                        }
                    }
                    else if (i++ == unnamedPosition) {
                        unnamedValue = parameterValue;  // Save this for later in case paramName isn't found
                    }

                    // Found a value, so currentParameterName needs to be cleared
                    currentParameterName = string.Empty;
                }

                if (unnamedValue != null) {
                    return unnamedValue;
                }
            }

            return null;
        }
    }
}

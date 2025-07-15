# Represents a transformer function that processes the message content and returns a modified 
# message content.
public type Transformer isolated function (MessageContext msgCtx) returns anydata|error;

# Represents a filter function that checks the message context and returns a boolean indicating 
# whether the message should be processed further.
public type Filter isolated function (MessageContext msgCtx) returns boolean|error;

# Represents a generic message processor that can process the message and return an error if the 
# processing fails.
public type GenericProcessor isolated function (MessageContext msgCtx) returns error?;

# Represents a processor that can be a filter, transformer, or processor and can be attached to a 
# channel for processing messages. Processors should be idempotent i.e. repeating the execution 
# should not change the outcome or the channel state.
public type Processor GenericProcessor|Filter|Transformer;

# Represents a destination function that processes the message context and returns a result or an 
# error if it failed to send the message to the destination. Destinations are typically contains a 
# sender or writer that that delivers the message to the target.
public type Destination isolated function (MessageContext msgCtx) returns any|error;

# Represents a handler which can be either a `Processor` or a `Destination`.
public type Handler Processor|Destination;

# Handler related configuration.
#
# + id - the unique identifier for the handler.
public type HandlerConfiguration record {|
    string id;
|};

# Processor configuration annotation.
public const annotation HandlerConfiguration ProcessorConfig on function;

# Filter configuration annotation.
public const annotation HandlerConfiguration FilterConfig on function;

# Transformer configuration annotation.
public annotation HandlerConfiguration TransformerConfig on function;

# Destination configuration annotation.
public annotation HandlerConfiguration DestinationConfig on function;

# Error details.
#
# + message - the message associated with the error, which includes an ID and the message content
public type ErrorDetails record {|
    Message message;
|};

# Suspension error details.
# 
# + message - the message entered into the suspension state, which includes an ID and the message content
# + reason - the reason for the suspension
public type SuspensionErrorDetails record {|
    Message message;
    "OnError"|"OnTrigger" reason;
|};

# Generic error type.
public type Error distinct error;

# Execution error type for the channel execution.
public type ExecutionError distinct Error & error<ErrorDetails>;

# Suspension error type for the channel execution.
public type SuspensionError distinct Error & error<SuspensionErrorDetails>;

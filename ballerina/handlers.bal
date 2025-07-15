// Copyright (c) 2025 WSO2 LLC. (http://www.wso2.org).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

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
# with the same message should not change the outcome or the channel state.
public type Processor GenericProcessor|Filter|Transformer;

# Represents a destination function that processes the message context and returns a result or an 
# error if it failed to send the message to the destination. Destinations are typically contains a 
# sender or a writer that sends or writes the message to a specific destination.
public type Destination isolated function (MessageContext msgCtx) returns anydata|error;

# Represents a handler which can be either a `Processor` or a `Destination`.
public type Handler Processor|Destination;

# Handler related configuration.
public type HandlerConfiguration record {|
    # The unique identifier for the handler
    string id;
|};

# Represents a destination configuration that can be used to configure a destination with retry
# capabilities.
public type DestinationConfiguration record {|
    *HandlerConfiguration;
    # The retry configuration for the destination. By default, it is disabled
    RetryDestinationConfig retryConfig?;
|};

# Represents a retry configuration for a destination.
public type RetryDestinationConfig record {|
    # The maximum number of retries for the destination
    int maxRetries = 3;
    # The interval in seconds between retries
    decimal retryInterval = 1;
|};

# Processor configuration annotation.
public const annotation HandlerConfiguration ProcessorConfig on function;

# Filter configuration annotation.
public const annotation HandlerConfiguration FilterConfig on function;

# Transformer configuration annotation.
public const annotation HandlerConfiguration TransformerConfig on function;

# Destination configuration annotation.
public const annotation DestinationConfiguration DestinationConfig on function;
